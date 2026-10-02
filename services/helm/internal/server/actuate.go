package server

// The board's WRITE routes: POST /helm/{open,accept,engage,dismiss}.
//
// These are the ONLY writes in the operator dashboard; everything else helm-svc
// serves is a read. open files a visit; accept slings the subject's recommended
// formula and dismisses its visit; engage spawns a Discuss sitting on the visit;
// dismiss closes it. The four share one HTTP shape, so the decisions a reader
// would otherwise reconstruct are stated here once.
//
// ── THEY OWN NO VERB LOGIC ─────────────────────────────────────────────
// Each verb lives ONCE, in gc-helm.sh (assets/scripts/gate-visit.test.sh and
// gc-helm-accept.test.sh guard those single copies). These handlers SHELL OUT
// to that script through internal/visit, exactly as assets/scripts/
// gc-visit-open.sh does. So subject resolution, the one-open-visit-per-subject
// gate, rig resolution, the un-engaged re-check accept makes before it slings,
// and the board cache bust are all INHERITED here, not reimplemented — and a fix
// to any of them is a fix to these routes with no Go change at all.
//
// Shelling to the gc CLI is an established pattern in this binary, not a new one:
// internal/source/gccli.go already does it for the gather.
//
// ── WHAT THIS LAYER DOES OWN ───────────────────────────────────────────
// Three things the script cannot do for us, because they are properties of being
// reachable over HTTP rather than from a terminal:
//
//  1. ARGUMENT SAFETY. The bead id becomes an argv element of a subprocess.
//     There is no shell (exec with an argv slice), so shell metacharacters are
//     inert — but ARGUMENT injection is live: an id beginning with "-" would be
//     parsed by a verb's flag loop as a flag. [validBeadID] is that boundary, and
//     it is deliberately the ONLY validation here. Whether the bead EXISTS,
//     carries a recommended formula, or has an un-engaged visit are the script's
//     gates; duplicating them would create a second copy that drifts.
//
//  2. CSRF. A GET surface published on a reachable origin is not made riskier by
//     being read from another page; a POST surface is. See [checkWriteOrigin].
//
//  3. DOUBLE-FIRE. The scripts' state checks are read-then-act, which is not
//     atomic, and a button is double-clicked routinely. Concurrent writes on one
//     subject race those checks whether they are the same verb (a double-clicked
//     Accept filing a second visit or slinging twice) or two verbs the UI offers
//     on one row at once (Accept slinging after Dismiss closed the visit it was
//     about to dismiss). [actuationGate] serializes writes per subject (bead)
//     in-process, so one subject's verbs never overlap.

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"sync"
)

// ToolResult is one completed gc-helm.sh write-verb run. A non-zero ExitCode is
// a normal result, not a Go error: the script's exit codes are its contract and
// the mapping below is the whole point of this file.
type ToolResult struct {
	Stdout   string
	Stderr   string
	ExitCode int
}

// Actuator runs one gc-helm.sh write verb for one bead.
//
// The interface exists so the handlers' mapping — which is where the operator's
// error messages are actually decided — is testable without a city, a Dolt or a
// gc binary. [ErrToolUnavailable] and [ErrToolTimeout] are the two failures an
// implementation reports as errors rather than exit codes; anything else it
// could not classify may be returned as a plain error and is reported as an
// internal fault.
type Actuator interface {
	Run(ctx context.Context, verb, bead string, extraArgs ...string) (ToolResult, error)
}

// Sentinel failures an [Actuator] reports instead of an exit code, because the
// script never ran (or never finished) and therefore never chose one.
var (
	ErrToolUnavailable = errors.New("write tool unavailable")
	ErrToolTimeout     = errors.New("write tool timed out")
)

// actuateRequest is the POST body shared by every write route: the bead to act
// on. A visit id is accepted too — gc-helm.sh resolves it to its subject.
//
// Ruling and Decisions are dismiss-only and empty on the other routes. They
// carry the operator's answer to a prior dismiss that HELD for a gate decision
// (held_for_gate_decision): one resolve/leave choice per surfaced gate, plus the
// single ruling gc-helm.sh records for every gate resolved in the run. The first
// dismiss click sends neither; the decision re-submit sends both.
type actuateRequest struct {
	Bead      string         `json:"bead"`
	Ruling    string         `json:"ruling,omitempty"`
	Decisions []gateDecision `json:"decisions,omitempty"`
}

// gateDecision is the operator's choice for one open linked gate a held dismiss
// surfaced: resolve it (settled on the request's Ruling) or leave it open
// (re-asked as a fresh visit). Gate is a bead id, validated at this boundary.
type gateDecision struct {
	Gate   string `json:"gate"`
	Action string `json:"action"` // "resolve" | "leave"
}

// actuateErrorBody is the non-2xx body of every write route.
//
// Reason is a STABLE slug keyed off the script's exit code alone, so the UI has
// something to branch on that does not depend on message wording. Error is the
// script's own stderr sentence, passed through unedited — each verb already
// writes a different, specific sentence for each of its failures, and
// re-deriving those distinctions here would be a second copy of knowledge that
// lives in the script. Passing it through means these routes' messages IMPROVE
// when the script's do, with no change here.
type actuateErrorBody struct {
	Error  string `json:"error"`
	Reason string `json:"reason"`
}

// Reason slugs. One per exit code, plus the ones this layer decides itself.
const (
	reasonInvalidBead = "invalid_bead" // rejected before exec
	reasonForbidden   = "forbidden"    // cross-origin write
	reasonBusy        = "busy"         // same (verb, bead) already in flight here
	reasonUsage       = "usage"        // exit 2 on the open route (a wiring fault)
	reasonEnvironment = "environment"  // exit 3
	reasonVerbFailed  = "verb_failed"  // exit 1 or 4 — the verb ran and refused
	reasonTimeout     = "timeout"      // tool did not finish
	reasonUnavailable = "unavailable"  // tool could not be run at all
	reasonInternal    = "internal"     // anything unclassified
)

// beadIDRE is the argument boundary: what may become the bead argv element.
//
// Shaped to the ids the city actually mints — a lowercase alphanumeric rig
// prefix, a hyphen, an alphanumeric body, and optional dotted numeric suffixes
// for split beads (tk-yc00g, tk-eemvf.3, sl-kg9z6.4.1). The load-bearing
// property is the anchored leading LETTER: it is what makes "-x" and "--reason"
// unrepresentable, so a crafted id cannot reach a verb's flag loop as a flag.
var beadIDRE = regexp.MustCompile(`^[a-z][a-z0-9]*-[a-z0-9]+(?:\.[0-9]+)*$`)

// maxBeadIDLen bounds the argument before the regex sees it. The regex is
// anchored and linear, so this is not about backtracking — it is about not
// handing an unbounded string to a subprocess.
const maxBeadIDLen = 64

// validBeadID reports whether s is safe to pass as a verb's bead argument.
func validBeadID(s string) bool {
	return len(s) <= maxBeadIDLen && beadIDRE.MatchString(s)
}

// actuationGate serializes concurrent writes on ONE subject (bead). See the
// double-fire note in the file header. Every write verb (open, accept, engage,
// dismiss) mutates the subject's visit, so on one subject they are mutually
// exclusive: a board-row Accept and a drill-panel Dismiss must not overlap, or
// Accept can sling after Dismiss has closed the visit. Two different beads never
// contend — they never share a key. inFlight maps a held bead to the verb
// running on it, so a refusal can name what to wait for.
type actuationGate struct {
	mu       sync.Mutex
	inFlight map[string]string
}

func newActuationGate() *actuationGate { return &actuationGate{inFlight: map[string]string{}} }

// enter claims key for verb, reporting ok=false and the verb already running on
// it when a request for it is in flight. The caller must call leave when it took
// the claim.
func (g *actuationGate) enter(key, verb string) (bool, string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	if running, busy := g.inFlight[key]; busy {
		return false, running
	}
	g.inFlight[key] = verb
	return true, ""
}

func (g *actuationGate) leave(key string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	delete(g.inFlight, key)
}

// runActuation is the shared write-route middleware: method, opener presence,
// CSRF, body decode, id validation, the per-(verb, bead) gate, the subprocess
// run, and the exit/error mapping. On success it invalidates the board cache and
// returns the run's result plus the resolved bead; the per-verb handler shapes
// the response body. On any failure it has already written the error response and
// returns ok=false.
func (s *Server) runActuation(w http.ResponseWriter, r *http.Request, verb string) (ToolResult, string, bool) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		writeActuateError(w, http.StatusMethodNotAllowed, reasonUsage, "this route accepts POST only")
		return ToolResult{}, "", false
	}
	// A service built without an actuator serves the board exactly as before and
	// refuses the write honestly, rather than 404ing as if the route were a typo.
	// Mirrors how a missing SPA degrades in [WithSPA].
	if s.actuator == nil {
		writeActuateError(w, http.StatusServiceUnavailable, reasonUnavailable,
			"this board cannot actuate: helm-svc was started without a write tool")
		return ToolResult{}, "", false
	}
	if err := checkWriteOrigin(r); err != nil {
		writeActuateError(w, http.StatusForbidden, reasonForbidden, err.Error())
		return ToolResult{}, "", false
	}

	var req actuateRequest
	// Bounded: the body carries one bead id.
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&req); err != nil {
		writeActuateError(w, http.StatusBadRequest, reasonUsage,
			"could not read the request body as JSON ({\"bead\":\"<id>\"})")
		return ToolResult{}, "", false
	}
	bead := strings.TrimSpace(req.Bead)
	if bead == "" {
		writeActuateError(w, http.StatusBadRequest, reasonInvalidBead, "no bead id in the request")
		return ToolResult{}, "", false
	}
	if !validBeadID(bead) {
		// Says what shape is expected: the operator sees this when a row id is
		// malformed, and "invalid" alone would not tell them what to look at.
		writeActuateError(w, http.StatusBadRequest, reasonInvalidBead,
			"not a bead id: "+bead+" — expected a form like tk-abc12 or tk-abc12.3")
		return ToolResult{}, "", false
	}

	// dismiss carries the gate-decision flags (--json always, plus the operator's
	// resolve/leave choices); the other verbs carry none. Built here, at the HTTP
	// boundary, because the gate ids become argv elements and must cross the same
	// validation the subject does. A malformed decision is a bad request, caught
	// before the gate and the subprocess.
	extraArgs, argErr := extraArgsFor(verb, req)
	if argErr != nil {
		writeActuateError(w, http.StatusBadRequest, reasonUsage, argErr.Error())
		return ToolResult{}, "", false
	}

	// Keyed on the subject (bead): every write verb mutates its visit, so a
	// double-clicked Accept, and an Accept racing a Dismiss on one row, both
	// collapse to one in-flight write. The same verb on two different beads still
	// runs concurrently. The refusal names the verb already holding the subject.
	if ok, running := s.gate.enter(bead, verb); !ok {
		writeActuateError(w, http.StatusConflict, reasonBusy,
			"already running "+running+" on "+bead+" — wait for that to finish")
		return ToolResult{}, "", false
	}
	defer s.gate.leave(bead)

	// THE SIDE EFFECT DOES NOT DIE WITH THE CLIENT (review of PR#421, P1).
	//
	// Passing r.Context() straight through would tie the subprocess to the
	// browser: a refresh, a closed tab or a dropped proxy connection cancels it,
	// the run is SIGKILLed mid-write, and the handler reports a timeout. That is
	// unsafe for these verbs specifically, because none is atomic — open creates
	// the visit bead before it stamps routing and adds the tracks edge; accept
	// slings before it dismisses; engage spawns a session before it binds. A kill
	// inside any of those windows leaves partial state while the browser is told
	// nothing happened, and the operator's retry then double-fires.
	//
	// WithoutCancel keeps the request's values and drops only its cancellation, so
	// once validated and holding the per-(verb, bead) gate the run is bound by the
	// actuator's own timeout and nothing else. A disconnected operator loses the
	// RESPONSE, not the write.
	res, err := s.actuator.Run(context.WithoutCancel(r.Context()), verb, bead, extraArgs...)
	if err != nil {
		status, reason, msg := mapActuateErr(err)
		log.Printf("helm: %s %s: %v", verb, bead, err)
		writeActuateError(w, status, reason, msg)
		return ToolResult{}, "", false
	}
	if res.ExitCode != 0 {
		// dismiss's exit 5 is NOT a failure: it is the subject carrying open linked
		// human gates a close would orphan, which the verb surfaces for a decision
		// (gc-helm.sh dismiss-gate-decision). Hand it back to handleDismiss un-mapped
		// — it renders the gates into a resolve/leave prompt — and do NOT bust the
		// board cache, because nothing was closed.
		if verb == "dismiss" && res.ExitCode == exitHeldForGateDecision {
			return res, bead, true
		}
		status, reason := mapExit(verb, res.ExitCode)
		msg := firstStderrLine(res.Stderr)
		if msg == "" {
			// The script failed without saying why. Do not invent a cause — name
			// the exit code so the operator can look it up.
			msg = "the " + verb + " tool failed (exit " + strconv.Itoa(res.ExitCode) + ") without reporting a reason"
		}
		log.Printf("helm: %s %s: exit %d: %s", verb, bead, res.ExitCode, msg)
		writeActuateError(w, status, reason, msg)
		return ToolResult{}, "", false
	}

	// A SUCCESSFUL WRITE CHANGES THE BOARD, SO DROP THE ONE WE ARE HOLDING (review
	// of PR#421, P2). gc-helm.sh busts its OWN on-disk cache, but this service
	// never reads it: Server.Board serves s.cached until s.expiry. Without this,
	// the next refresh can show the pre-write board for up to the TTL — the row the
	// operator just acted on still reads as it did, which invites a second click on
	// work already in flight.
	s.invalidateBoard()
	return res, bead, true
}

// handleOpen serves POST /helm/open. It has its own handler, rather than sharing
// [Server.handleActuateVerb], because its success body is richer: the operator
// must be able to tell a newly-filed visit from one that was already open, and
// which visit that is.
func (s *Server) handleOpen(w http.ResponseWriter, r *http.Request) {
	res, bead, ok := s.runActuation(w, r, "open")
	if !ok {
		return
	}
	outcome, visit := parseOpenStdout(res.Stdout)
	writeJSON(w, http.StatusOK, openResponse{
		Bead:    bead,
		Outcome: outcome,
		Visit:   visit,
		Message: firstLine(res.Stdout),
	})
}

func (s *Server) handleAccept(w http.ResponseWriter, r *http.Request) {
	s.handleActuateVerb(w, r, "accept")
}
func (s *Server) handleEngage(w http.ResponseWriter, r *http.Request) {
	s.handleActuateVerb(w, r, "engage")
}

// handleDismiss serves POST /helm/dismiss. It has its own handler, rather than
// the flat [Server.handleActuateVerb], because dismiss runs with --json and its
// result is a discriminated outcome the operator must act on: the sitting CLOSED,
// or dismiss HELD because the subject carries open linked human gates a close
// would orphan (gc-helm.sh exit 5). The held body carries each gate so the board
// can take the resolve/leave decision in place; the decision returns as the
// request's ruling + decisions, which runActuation forwards and gc-helm.sh
// applies before it closes the visit. runActuation has already mapped every true
// failure, so a result reaching here is exit 0 (closed) or exit 5 (held).
func (s *Server) handleDismiss(w http.ResponseWriter, r *http.Request) {
	res, bead, ok := s.runActuation(w, r, "dismiss")
	if !ok {
		return
	}
	// dismiss always runs with --json, so stdout is one JSON object, never the
	// prose the other parity verbs pass through. A shape this cannot read is
	// reported, never shown raw.
	var out dismissToolJSON
	if err := json.Unmarshal([]byte(strings.TrimSpace(res.Stdout)), &out); err != nil {
		log.Printf("helm: dismiss %s: unreadable --json stdout: %v", bead, err)
		writeActuateError(w, http.StatusBadGateway, reasonInternal,
			"the dismiss tool answered in a shape the board could not read")
		return
	}
	if res.ExitCode == exitHeldForGateDecision || out.HeldForGateDecision {
		writeJSON(w, http.StatusOK, dismissResponse{
			Bead:    bead,
			Verb:    "dismiss",
			Outcome: dismissOutcomeHeld,
			Message: heldMessage(len(out.Gates)),
			Gates:   out.Gates,
		})
		return
	}
	writeJSON(w, http.StatusOK, dismissResponse{
		Bead:    bead,
		Verb:    "dismiss",
		Outcome: dismissOutcomeClosed,
		Message: closedMessage(out.Closed),
	})
}

// extraArgsFor builds a verb's handler-supplied flags. Only dismiss has any;
// every other verb runs on its positionals alone.
func extraArgsFor(verb string, req actuateRequest) ([]string, error) {
	if verb != "dismiss" {
		return nil, nil
	}
	return dismissExtraArgs(req)
}

// dismissExtraArgs builds the dismiss flags: always --json (so the service reads
// the structured result and the held gates), plus the operator's per-gate
// resolve/leave choices when a prior held response prompted them. Each gate id is
// validated to the bead-id shape — the same argument boundary the subject crosses
// — so a crafted id cannot reach dismiss's flag loop as a flag. gc-helm.sh takes
// ONE --ruling for every gate resolved in a run, so the ruling is a single request
// field, required once any gate is resolved and omitted when none is.
func dismissExtraArgs(req actuateRequest) ([]string, error) {
	args := []string{"--json"}
	resolving := false
	for _, d := range req.Decisions {
		if !validBeadID(d.Gate) {
			return nil, errors.New("not a gate id: " + d.Gate + " — expected a form like tk-abc12")
		}
		switch d.Action {
		case "resolve":
			args = append(args, "--resolve-gate", d.Gate)
			resolving = true
		case "leave":
			args = append(args, "--leave-gate", d.Gate)
		default:
			return nil, errors.New(`unknown gate decision action: "` + d.Action + `" — expected "resolve" or "leave"`)
		}
	}
	if resolving {
		ruling := strings.TrimSpace(req.Ruling)
		if ruling == "" {
			return nil, errors.New("resolving a gate needs a ruling (the decision it resolves with)")
		}
		args = append(args, "--ruling", ruling)
	}
	return args, nil
}

// handleActuateVerb serves accept, engage and dismiss: the shared write
// middleware, then the flat [actuateResponse]. Unlike open, what these three
// return that a surface acts on is the tool's own sentence, so there is no
// per-verb parsing to do here.
func (s *Server) handleActuateVerb(w http.ResponseWriter, r *http.Request, verb string) {
	res, bead, ok := s.runActuation(w, r, verb)
	if !ok {
		return
	}
	writeJSON(w, http.StatusOK, actuateResponse{
		Bead:    bead,
		Verb:    verb,
		Message: strings.TrimSpace(res.Stdout),
	})
}

// openResponse is the 200 body of POST /helm/open.
//
// DELIBERATELY NOT IN src/contract.ts. That file is the mirror of the BOARD
// contract, and web/contract_parity_test.go enforces a two-way match between its
// `export interface`s and the Go structs reachable from board.Board — so an
// interface added there for this route fails that test with no Go struct to pair
// with. The TypeScript mirror of these shapes lives beside the fetch that reads
// them, in web/src/open/client.ts, and is kept small and flat so hand-mirroring
// stays cheap.
type openResponse struct {
	Bead string `json:"bead"`
	// Outcome is "filed" (a new visit) or "existing" (one was already open).
	// The operator needs these distinguished: clicking twice and being told
	// "filed" both times would misrepresent what the city did.
	Outcome string `json:"outcome"`
	// Visit is the visit bead's id when the script named one.
	Visit string `json:"visit,omitempty"`
	// Message is the script's own sentence, verbatim.
	Message string `json:"message"`
}

// actuateResponse is the 200 body of the accept, engage and dismiss routes.
//
// One flat shape for all three, because — unlike open's filed/existing/visit
// distinction, which the operator must see to not double-file — what these three
// return that a surface acts on is the tool's own sentence. It names the ids each
// verb produces in prose (accept: the slung formula and the closed visit; engage:
// the spawned session to attach to; dismiss: the closed visit), and passing that
// through verbatim means these routes' messages IMPROVE when the script's do,
// with no change here. Like [openResponse], it is DELIBERATELY NOT in
// src/contract.ts; its mirror lives beside the fetch in web/src/actuate/client.ts.
type actuateResponse struct {
	Bead string `json:"bead"`
	Verb string `json:"verb"`
	// Message is the script's stdout, trimmed: its success sentence, and for
	// engage the follow-on "attach: gc session attach <id>" line. Empty is
	// possible and honest (dismiss on a subject with no open visit says so on
	// stdout, but a bare success is not invented into a claim).
	Message string `json:"message"`
}

// exitHeldForGateDecision is gc-helm.sh dismiss's exit 5: the subject carries open
// linked human gates a close would orphan, so the verb surfaced them and closed
// nothing. Not a failure — a decision the operator still owes.
const exitHeldForGateDecision = 5

// dismiss outcomes, the discriminator on dismissResponse.
const (
	dismissOutcomeClosed = "closed"
	dismissOutcomeHeld   = "held_for_gate_decision"
)

// dismissResponse is the 200 body of POST /helm/dismiss.
//
// Richer than the flat [actuateResponse] the other parity verbs share, for the
// same reason [openResponse] is: the operator must tell the two outcomes apart. A
// dismiss either CLOSED the sitting (Outcome "closed") or HELD because the subject
// carries open linked human gates a close would orphan (Outcome
// "held_for_gate_decision", gc-helm.sh exit 5). The held body carries each gate so
// the board takes the resolve/leave decision in place rather than failing with a
// lost sentence and sending the operator to the CLI.
//
// DELIBERATELY NOT IN src/contract.ts, like [openResponse] and [actuateResponse]:
// its mirror lives beside the fetch in web/src/actuate/client.ts.
type dismissResponse struct {
	Bead string `json:"bead"`
	Verb string `json:"verb"`
	// Outcome is "closed" or "held_for_gate_decision". The browser branches on it,
	// never on Message, the same discipline the reason slug carries for errors.
	Outcome string `json:"outcome"`
	// Message is a short board sentence for the outcome. dismiss runs with --json,
	// so there is no verbatim script prose to pass through here.
	Message string `json:"message"`
	// Gates is the open linked gates a held dismiss surfaced, each to be decided;
	// empty (and omitted) on a closed outcome.
	Gates []dismissGate `json:"gates,omitempty"`
}

// dismissGate is one open linked gate a held dismiss surfaced. Mirrors the objects
// in gc-helm.sh dismiss --json's held_for_gate_decision.gates: the gate id, the
// bead it blocks, and its demand headline.
type dismissGate struct {
	ID     string `json:"id"`
	Blocks string `json:"blocks"`
	Demand string `json:"demand"`
}

// dismissToolJSON is the parse target for gc-helm.sh dismiss --json. One struct
// reads both shapes: the closed result {subject, matched, closed, ok:true} and the
// held result {subject, ok:false, held_for_gate_decision:true, gates:[…]}. Fields
// absent from one shape stay zero-valued.
type dismissToolJSON struct {
	Subject             string        `json:"subject"`
	OK                  bool          `json:"ok"`
	Matched             int           `json:"matched"`
	Closed              int           `json:"closed"`
	HeldForGateDecision bool          `json:"held_for_gate_decision"`
	Gates               []dismissGate `json:"gates"`
	GateReadFailed      bool          `json:"gate_read_failed"`
}

// heldMessage is the board sentence for a dismiss held on a gate decision; it
// points the operator at the gates the body carries rather than restating them.
func heldMessage(n int) string {
	if n == 1 {
		return "Dismiss is held: this subject has an open linked gate a close would orphan. Decide it below."
	}
	return "Dismiss is held: this subject has " + strconv.Itoa(n) + " open linked gates a close would orphan. Decide each below."
}

// closedMessage is the board sentence for a completed dismiss, keyed off how many
// visits closed — 0 is the honest "nothing was holding a sitting".
func closedMessage(closed int) string {
	switch {
	case closed <= 0:
		return "No open visit was holding a sitting."
	case closed == 1:
		return "The visit was closed."
	default:
		return "Closed " + strconv.Itoa(closed) + " visits."
	}
}

// mapExit turns a gc-helm.sh exit code into an HTTP status and a stable reason.
//
// The codes are the script's documented contract (see "Exit codes" in
// assets/scripts/gc-helm.sh) and helm-svc already mirrors them on the board path
// (cmd/helm-svc/board.go).
//
// EXIT 2 IS VERB-DEPENDENT. On open the handler pre-validates the id, so exit 2
// (usage) can only mean the script and this layer disagree about an argument — a
// wiring fault, reported 500. On accept, exit 2 is also "the subject carries no
// gc.recommended_formula — it is discuss-only", a legitimate refusal the operator
// meets when they act on a stale board row, so it is a 422, not a service fault.
// engage and dismiss reach exit 2 only on the pre-validated usage paths open
// does; 422 there is harmless, since the web never sends them and the script's
// sentence still shows.
//
// EXIT 3 IS KNOWINGLY COARSE, AND THAT IS NOT THIS LAYER'S BUG TO FIX. In the
// script it still collapses a rig-enumeration timeout, a jq parse failure and a
// genuinely rigless city into one sentence (tk-lzdty half 2). This route reports
// exit 3 as "environment" and shows the script's sentence verbatim rather than
// guessing which of the three it was — so the day the script's sentences separate,
// the browser separates with it and nothing here changes.
func mapExit(verb string, code int) (status int, reason string) {
	switch code {
	case 1:
		// accept's sling-failure path (gc-helm.sh cmd_accept) exits 1: the sling
		// did not land and the visit is left open for retry or Discuss. A verb
		// runtime failure, like exit 4 — the request's own content could not be
		// actuated, nothing is wrong with the service. open never exits 1.
		return http.StatusUnprocessableEntity, reasonVerbFailed
	case 2:
		if verb == "open" {
			return http.StatusInternalServerError, reasonUsage
		}
		return http.StatusUnprocessableEntity, reasonVerbFailed
	case 3:
		return http.StatusServiceUnavailable, reasonEnvironment
	case 4:
		// Bead not found / unverifiable / discuss-state refusal / filing failed.
		// The subject is the request's own content, so this is a 422 rather than a
		// 5xx: nothing is wrong with the service.
		return http.StatusUnprocessableEntity, reasonVerbFailed
	default:
		return http.StatusBadGateway, reasonInternal
	}
}

// mapActuateErr classifies a failure to RUN the script at all.
func mapActuateErr(err error) (status int, reason, msg string) {
	switch {
	case errors.Is(err, ErrToolTimeout):
		return http.StatusGatewayTimeout, reasonTimeout,
			"the write tool did not finish in time — the city's data plane may be slow or wedged; " +
				"the action may or may not have gone through, so check the bead before retrying"
	case errors.Is(err, ErrToolUnavailable):
		return http.StatusServiceUnavailable, reasonUnavailable,
			"the write tool could not be run: " + err.Error()
	default:
		return http.StatusInternalServerError, reasonInternal,
			"the write tool could not be run: " + err.Error()
	}
}

// filedRE and existingRE read cmd_open's two success sentences:
//
//	gc-helm: visit <id> filed on <bead> (pool <p>) — …
//	gc-helm: visit <id> is already open for <bead> — …
//
// Parsing prose is not ideal, and it is the honest option here: the script is the
// single copy of the visit logic and it speaks in sentences, so the choice is
// between reading them and duplicating the logic that produced them. A sentence
// that stops matching degrades to outcome "opened" with the message still shown —
// never to an error, because the visit really was filed. open_parity_test.go
// pins these against the script's real echoes.
var (
	filedRE    = regexp.MustCompile(`visit\s+(\S+)\s+filed\s+on`)
	existingRE = regexp.MustCompile(`visit\s+(\S+)\s+is\s+already\s+open`)
)

// parseOpenStdout classifies a successful open run.
func parseOpenStdout(out string) (outcome, visit string) {
	if m := filedRE.FindStringSubmatch(out); m != nil {
		return "filed", m[1]
	}
	if m := existingRE.FindStringSubmatch(out); m != nil {
		return "existing", m[1]
	}
	return "opened", ""
}

// checkWriteOrigin refuses a cross-site write.
//
// THE EXPOSURE DECISION, stated once. helm-svc is published to the tailnet by
// tailscale-serve, so reaching these routes at all already requires being on the
// tailnet — the same boundary that admits the board's reads and the ttyd
// terminal, and these routes do not widen it. What POST adds over GET is not
// reachability but CSRF: the operator's browser is ON the tailnet, so any page
// they visit could otherwise POST here with their network position and act in
// their name.
//
// Two checks, both cheap, neither relying on the other:
//
//   - Sec-Fetch-Site, which every current browser sets and no page can forge.
//     "same-origin" and "none" (a typed URL) pass; "cross-site" and "same-site"
//     do not.
//   - The absence of that header is NOT treated as a pass on its own — a
//     non-browser client (curl, a script on the host) sends neither it nor
//     Origin, and that is the case this must keep working. So a request with no
//     Sec-Fetch-Site passes only when it also carries no Origin; an Origin
//     without Sec-Fetch-Site is a browser-shaped request from an unknown page and
//     is refused.
//
// Deliberately NOT a token or a login. This service has no session concept and
// inventing one here would be a second, weaker authentication story beside
// tailscale's — the same reasoning endpoint.ts gives for not re-checking the
// ttyd session name in the browser.
func checkWriteOrigin(r *http.Request) error {
	switch r.Header.Get("Sec-Fetch-Site") {
	case "same-origin", "none":
		return nil
	case "":
		if r.Header.Get("Origin") == "" {
			return nil
		}
		return errors.New("refused a cross-site write: this route accepts requests from the board's own origin")
	default:
		return errors.New("refused a cross-site write: this route accepts requests from the board's own origin")
	}
}

func writeActuateError(w http.ResponseWriter, status int, reason, msg string) {
	writeJSON(w, status, actuateErrorBody{Error: msg, Reason: reason})
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(body); err != nil {
		log.Printf("helm: encode response: %v", err)
	}
}

// firstLine returns the first non-empty line of s, trimmed.
func firstLine(s string) string {
	for _, ln := range strings.Split(s, "\n") {
		if t := strings.TrimSpace(ln); t != "" {
			return t
		}
	}
	return ""
}

// firstStderrLine returns the first non-empty stderr line with the script's
// "gc-helm: " and "<verb>: " prefixes removed — the prefixes name the tool the
// operator did not invoke, and the panel already says what was attempted.
func firstStderrLine(s string) string {
	ln := firstLine(s)
	ln = strings.TrimPrefix(ln, "gc-helm: ")
	for _, prefix := range []string{"open: ", "accept: ", "engage: ", "dismiss: "} {
		if strings.HasPrefix(ln, prefix) {
			return strings.TrimPrefix(ln, prefix)
		}
	}
	return ln
}
