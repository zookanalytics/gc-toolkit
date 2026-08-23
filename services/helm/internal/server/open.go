package server

// POST /helm/open — file a visit on a bead, from the board.
//
// This is the FIRST write route in the operator dashboard. Everything else
// helm-svc serves is a read, so the decisions worth stating up front are the
// ones a reader will otherwise have to reconstruct.
//
// ── IT OWNS NO VISIT LOGIC ────────────────────────────────────────────
// Visit filing lives ONCE, in `gc-helm.sh open`'s marked gate-visit block
// (assets/scripts/gate-visit.test.sh guards that single copy across every
// consumer). This handler SHELLS OUT to that verb rather than re-deriving it,
// exactly as assets/scripts/gc-visit-open.sh does. So the subject-existence
// gate (tk-ujwvt), the one-open-visit-per-subject gate, rig resolution by id
// prefix and the board cache bust are all INHERITED here, not reimplemented —
// and a fix to any of them is a fix to this route with no Go change at all.
//
// Shelling to the gc CLI is an established pattern in this binary, not a new
// one: internal/source/gccli.go already does it for the gather.
//
// ── WHAT THIS LAYER DOES OWN ──────────────────────────────────────────
// Three things the script cannot do for us, because they are properties of
// being reachable over HTTP rather than from a terminal:
//
//  1. ARGUMENT SAFETY. The bead id becomes an argv element of a subprocess.
//     There is no shell (exec with an argv slice), so shell metacharacters are
//     inert — but ARGUMENT injection is live: an id beginning with "-" would be
//     parsed by cmd_open's flag loop as a flag, not a bead. [validBeadID] is
//     that boundary, and it is deliberately the ONLY validation here. Whether
//     the bead EXISTS is the script's gate, and duplicating it would create a
//     second copy that drifts — the mistake the ttyd guard's comment warns
//     about (web/src/terminal/endpoint.ts: the guard is the boundary, a second
//     copy in front of it is decorative).
//
//  2. CSRF. A GET surface published on a reachable origin is not made riskier
//     by being read from another page; a POST surface is. See [checkWriteOrigin].
//
//  3. DOUBLE-FIRE. cmd_open's one-visit-per-subject gate is read-then-create,
//     which is not atomic, and a button is double-clicked routinely. Two
//     concurrent opens on one bead would race that gate and file the second
//     visit it exists to prevent — splitting the conversation. [openGate]
//     collapses concurrent requests for the same bead in-process.

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

// ToolResult is one completed `gc-helm.sh open` run. A non-zero ExitCode is a
// normal result, not a Go error: the script's exit codes are its contract and
// the mapping below is the whole point of this file.
type ToolResult struct {
	Stdout   string
	Stderr   string
	ExitCode int
}

// Opener runs the `open` verb for one bead.
//
// The interface exists so the handler's mapping — which is where the operator's
// error messages are actually decided — is testable without a city, a Dolt or a
// gc binary. [ErrToolUnavailable] and [ErrToolTimeout] are the two failures an
// implementation reports as errors rather than exit codes; anything else it
// could not classify may be returned as a plain error and is reported as an
// internal fault.
type Opener interface {
	Open(ctx context.Context, bead string) (ToolResult, error)
}

// Sentinel failures an [Opener] reports instead of an exit code, because the
// script never ran (or never finished) and therefore never chose one.
var (
	ErrToolUnavailable = errors.New("visit tool unavailable")
	ErrToolTimeout     = errors.New("visit tool timed out")
)

// openRequest is the POST body: the bead to open a conversation on.
type openRequest struct {
	Bead string `json:"bead"`
}

// openResponse is the 200 body.
//
// DELIBERATELY NOT IN src/contract.ts. That file is the mirror of the BOARD
// contract, and web/contract_parity_test.go enforces a two-way match between
// its `export interface`s and the Go structs reachable from board.Board — so an
// interface added there for this route fails that test with no Go struct to
// pair with. The TypeScript mirror of these two shapes lives beside the fetch
// that reads them, in web/src/open/client.ts, and is kept small and flat so
// hand-mirroring stays cheap.
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

// openErrorBody is the non-2xx body.
//
// Reason is a STABLE slug keyed off the script's exit code alone, so the UI has
// something to branch on that does not depend on message wording. Error is the
// script's own stderr sentence, passed through unedited — cmd_open already
// writes a different, specific sentence for each of its failures (wrong id
// prefix vs. no ledger answers vs. data plane down), and re-deriving that
// distinction here would be a second copy of knowledge that lives in the
// script. Passing it through means this route's messages IMPROVE when the
// script's do, with no change here (see the exit-3 note on [mapExit]).
type openErrorBody struct {
	Error  string `json:"error"`
	Reason string `json:"reason"`
}

// Reason slugs. One per exit code, plus the ones this layer decides itself.
const (
	reasonInvalidBead = "invalid_bead" // rejected before exec
	reasonForbidden   = "forbidden"    // cross-origin write
	reasonBusy        = "busy"         // same bead already in flight here
	reasonUsage       = "usage"        // exit 2
	reasonEnvironment = "environment"  // exit 3
	reasonVerbFailed  = "verb_failed"  // exit 4
	reasonTimeout     = "timeout"      // tool did not finish
	reasonUnavailable = "unavailable"  // tool could not be run at all
	reasonInternal    = "internal"     // anything unclassified
)

// beadIDRE is the argument boundary: what may become argv[2] of the script.
//
// Shaped to the ids the city actually mints — a lowercase alphanumeric rig
// prefix, a hyphen, an alphanumeric body, and optional dotted numeric suffixes
// for split beads (tk-yc00g, tk-eemvf.3, sl-kg9z6.4.1). The load-bearing
// property is the anchored leading LETTER: it is what makes "-x" and "--reason"
// unrepresentable, so a crafted id cannot reach cmd_open's flag loop as a flag.
var beadIDRE = regexp.MustCompile(`^[a-z][a-z0-9]*-[a-z0-9]+(?:\.[0-9]+)*$`)

// maxBeadIDLen bounds the argument before the regex sees it. The regex is
// anchored and linear, so this is not about backtracking — it is about not
// handing an unbounded string to a subprocess.
const maxBeadIDLen = 64

// validBeadID reports whether s is safe to pass as the script's bead argument.
func validBeadID(s string) bool {
	return len(s) <= maxBeadIDLen && beadIDRE.MatchString(s)
}

// openGate collapses concurrent opens of the SAME bead. See the double-fire
// note in the file header. Different beads never contend.
type openGate struct {
	mu       sync.Mutex
	inFlight map[string]bool
}

func newOpenGate() *openGate { return &openGate{inFlight: map[string]bool{}} }

// enter claims the bead, reporting false when a request for it is already
// running. The caller must call leave when it took the claim.
func (g *openGate) enter(bead string) bool {
	g.mu.Lock()
	defer g.mu.Unlock()
	if g.inFlight[bead] {
		return false
	}
	g.inFlight[bead] = true
	return true
}

func (g *openGate) leave(bead string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	delete(g.inFlight, bead)
}

// handleOpen serves POST /helm/open.
func (s *Server) handleOpen(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		writeOpenError(w, http.StatusMethodNotAllowed, reasonUsage,
			"this route accepts POST only")
		return
	}
	// A service built without an opener serves the board exactly as before and
	// refuses the write honestly, rather than 404ing as if the route were a
	// typo. Mirrors how a missing SPA degrades in [WithSPA].
	if s.opener == nil {
		writeOpenError(w, http.StatusServiceUnavailable, reasonUnavailable,
			"this board cannot file visits: helm-svc was started without a visit tool")
		return
	}
	if err := checkWriteOrigin(r); err != nil {
		writeOpenError(w, http.StatusForbidden, reasonForbidden, err.Error())
		return
	}

	var req openRequest
	// Bounded: the body carries one bead id.
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&req); err != nil {
		writeOpenError(w, http.StatusBadRequest, reasonUsage,
			"could not read the request body as JSON ({\"bead\":\"<id>\"})")
		return
	}
	bead := strings.TrimSpace(req.Bead)
	if bead == "" {
		writeOpenError(w, http.StatusBadRequest, reasonInvalidBead,
			"no bead id in the request")
		return
	}
	if !validBeadID(bead) {
		// Says what shape is expected: the operator sees this when a row id is
		// malformed, and "invalid" alone would not tell them what to look at.
		writeOpenError(w, http.StatusBadRequest, reasonInvalidBead,
			"not a bead id: "+bead+" — expected a form like tk-abc12 or tk-abc12.3")
		return
	}

	if !s.openGate.enter(bead) {
		writeOpenError(w, http.StatusConflict, reasonBusy,
			"already opening a conversation on "+bead+" — wait for that to finish")
		return
	}
	defer s.openGate.leave(bead)

	// THE SIDE EFFECT DOES NOT DIE WITH THE CLIENT (review of PR#421, P1).
	//
	// This used to pass r.Context() straight through, which tied the subprocess
	// to the browser: a refresh, a closed tab or a proxy dropping the connection
	// cancelled it, cmd.Cancel SIGKILLed the process GROUP, and the handler
	// reported the timeout path. That is unsafe for this verb specifically,
	// because `gc-helm.sh open` is not atomic — the gate-visit block creates the
	// visit bead first and only then stamps gc.routed_to / task_kind and adds the
	// tracks edge (assets/scripts/gc-helm.sh). A kill inside that window leaves an
	// open, unrouted, unlinked visit task while the browser is told nothing was
	// filed, and a retry files a SECOND one, because the script's duplicate guard
	// keys on exactly the metadata and edge that never landed.
	//
	// WithoutCancel keeps the request's values and drops only its cancellation, so
	// once the request is validated and the per-bead gate is held the run is bound
	// by the opener's own timeout and nothing else. A disconnected operator now
	// loses the RESPONSE, not the write.
	//
	// The timeout window is narrowed, not closed: a genuinely wedged data plane
	// can still be killed mid-window. That case is no longer described as "no
	// visit was filed" anywhere — see mapOpenErr below, the README's exit table,
	// and the web client's messages.
	res, err := s.opener.Open(context.WithoutCancel(r.Context()), bead)
	if err != nil {
		status, reason, msg := mapOpenErr(err)
		log.Printf("helm: open %s: %v", bead, err)
		writeOpenError(w, status, reason, msg)
		return
	}
	if res.ExitCode != 0 {
		status, reason := mapExit(res.ExitCode)
		msg := firstStderrLine(res.Stderr)
		if msg == "" {
			// The script failed without saying why. Do not invent a cause —
			// name the exit code so the operator can look it up.
			msg = "the visit tool failed (exit " + strconv.Itoa(res.ExitCode) + ") without reporting a reason"
		}
		log.Printf("helm: open %s: exit %d: %s", bead, res.ExitCode, msg)
		writeOpenError(w, status, reason, msg)
		return
	}

	outcome, visit := parseOpenStdout(res.Stdout)
	// A FILED VISIT CHANGES THE BOARD, SO DROP THE ONE WE ARE HOLDING (review of
	// PR#421, P2). `gc-helm.sh open` busts its OWN cache, but that is the script's
	// on-disk cache and this service never reads it: Server.Board serves s.cached
	// until s.expiry. Without this, the next refresh can show the pre-open board
	// for up to the TTL even though the POST succeeded — the row the operator just
	// acted on still reads unheld, which invites a second click on work already in
	// flight. Both success outcomes invalidate: `existing` means a visit is open
	// that this board may equally not be showing yet.
	s.invalidateBoard()
	writeJSON(w, http.StatusOK, openResponse{
		Bead:    bead,
		Outcome: outcome,
		Visit:   visit,
		Message: firstLine(res.Stdout),
	})
}

// mapExit turns a gc-helm.sh exit code into an HTTP status and a stable reason.
//
// The codes are the script's documented contract (see "Exit codes" in
// assets/scripts/gc-helm.sh) and helm-svc already mirrors them on the board
// path (cmd/helm-svc/board.go).
//
// EXIT 3 IS KNOWINGLY COARSE, AND THAT IS NOT THIS LAYER'S BUG TO FIX. In the
// script it still collapses a rig-enumeration timeout, a jq parse failure and a
// genuinely rigless city into one sentence — tk-lzdty half 2, open at the time
// of writing. This route therefore reports exit 3 as "environment" and shows
// the script's sentence verbatim rather than guessing which of the three it
// was. Guessing here would hard-code the ambiguity into a second place; passing
// it through means the day tk-lzdty lands and the script's sentences separate,
// the browser separates with it and nothing here changes.
func mapExit(code int) (status int, reason string) {
	switch code {
	case 2:
		// The handler validates the id first, so reaching this means the script
		// and this layer disagree about what an argument is — a wiring fault,
		// not operator error.
		return http.StatusInternalServerError, reasonUsage
	case 3:
		return http.StatusServiceUnavailable, reasonEnvironment
	case 4:
		// Bead not found / could not verify / visit filing failed. The subject
		// is the request's own content, so this is a 422 rather than a 5xx:
		// nothing is wrong with the service.
		return http.StatusUnprocessableEntity, reasonVerbFailed
	default:
		return http.StatusBadGateway, reasonInternal
	}
}

// mapOpenErr classifies a failure to RUN the script at all.
func mapOpenErr(err error) (status int, reason, msg string) {
	switch {
	case errors.Is(err, ErrToolTimeout):
		return http.StatusGatewayTimeout, reasonTimeout,
			"the visit tool did not finish in time — the city's data plane may be slow or wedged; " +
				"a visit may or may not have been filed, so check the bead before retrying"
	case errors.Is(err, ErrToolUnavailable):
		return http.StatusServiceUnavailable, reasonUnavailable,
			"the visit tool could not be run: " + err.Error()
	default:
		return http.StatusInternalServerError, reasonInternal,
			"the visit tool could not be run: " + err.Error()
	}
}

// filedRE and existingRE read cmd_open's two success sentences:
//
//	gc-helm: visit <id> filed on <bead> (pool <p>) — …
//	gc-helm: visit <id> is already open for <bead> — …
//
// Parsing prose is not ideal, and it is the honest option here: the script is
// the single copy of the visit logic and it speaks in sentences, so the choice
// is between reading them and duplicating the logic that produced them. A
// sentence that stops matching degrades to outcome "opened" with the message
// still shown — never to an error, because the visit really was filed.
var (
	filedRE    = regexp.MustCompile(`visit\s+(\S+)\s+filed\s+on`)
	existingRE = regexp.MustCompile(`visit\s+(\S+)\s+is\s+already\s+open`)
)

// parseOpenStdout classifies a successful run.
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
// tailscale-serve, so reaching this route at all already requires being on the
// tailnet — the same boundary that admits the board's reads and the ttyd
// terminal, and this route does not widen it. What POST adds over GET is not
// reachability but CSRF: the operator's browser is ON the tailnet, so any page
// they visit could otherwise POST here with their network position and file
// visits in their name.
//
// Two checks, both cheap, neither relying on the other:
//
//   - Sec-Fetch-Site, which every current browser sets and no page can forge.
//     "same-origin" and "none" (a typed URL) pass; "cross-site" and
//     "same-site" do not.
//   - The absence of that header is NOT treated as a pass on its own — a
//     non-browser client (curl, a script on the host) sends neither it nor
//     Origin, and that is the case this must keep working. So a request with
//     no Sec-Fetch-Site passes only when it also carries no Origin; an Origin
//     without Sec-Fetch-Site is a browser-shaped request from an unknown page
//     and is refused.
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

func writeOpenError(w http.ResponseWriter, status int, reason, msg string) {
	writeJSON(w, status, openErrorBody{Error: msg, Reason: reason})
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
// "gc-helm: " / "gc-helm: open: " prefix removed — the prefix names the tool
// the operator did not invoke, and the panel already says what was attempted.
func firstStderrLine(s string) string {
	ln := firstLine(s)
	ln = strings.TrimPrefix(ln, "gc-helm: ")
	return strings.TrimPrefix(ln, "open: ")
}
