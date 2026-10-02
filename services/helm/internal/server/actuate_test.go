package server

// Tests for the parity write routes POST /helm/{accept,engage,dismiss}.
//
// open_test.go exhausts the SHARED write middleware (the exit-code mapping, CSRF,
// the argument boundary, the client-disconnect and cache behaviour) through the
// open route. These tests prove the three new routes are wired onto that same
// middleware and carry the tool's sentence back — plus the two places the new
// verbs genuinely differ from open: accept's exit 1 and its verb-dependent
// exit 2. The stub fakeActuator, serveOpen, openReq, newFake and decodeErr live
// in open_test.go / server_test.go.

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/web"
)

// actuateReq builds a same-origin POST to a write route, the shape the board's
// fetch sends.
func actuateReq(verb, body string) *http.Request {
	r := httptest.NewRequest(http.MethodPost, "/helm/"+verb, strings.NewReader(body))
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set("Sec-Fetch-Site", "same-origin")
	return r
}

func decodeActuate(t *testing.T, rr *httptest.ResponseRecorder) actuateResponse {
	t.Helper()
	var got actuateResponse
	if err := json.Unmarshal(rr.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode 200 body: %v (body=%s)", err, rr.Body.String())
	}
	return got
}

// Each flat parity route (accept, engage) runs the verb its path names, on the
// requested bead, and hands back the tool's own stdout — the whole of it, since
// engage's attach line and accept's dismiss line are on a second line the operator
// needs. dismiss has its own shape (--json, a closed/held outcome) and its own
// tests below.
func TestActuateRoutesRunTheirVerb(t *testing.T) {
	for _, verb := range []string{"accept", "engage"} {
		t.Run(verb, func(t *testing.T) {
			f := &fakeActuator{res: ToolResult{Stdout: "gc-helm: " + verb + ": did the thing on tk-abc12\n  attach: gc session attach gc-42\n"}}
			rr := serveOpen(t, f, actuateReq(verb, `{"bead":"tk-abc12"}`))
			if rr.Code != http.StatusOK {
				t.Fatalf("status = %d, want 200 (body=%s)", rr.Code, rr.Body.String())
			}
			got := decodeActuate(t, rr)
			if got.Verb != verb {
				t.Errorf("verb = %q, want %q", got.Verb, verb)
			}
			if got.Bead != "tk-abc12" {
				t.Errorf("bead = %q, want tk-abc12", got.Bead)
			}
			if !strings.Contains(got.Message, "did the thing") || !strings.Contains(got.Message, "attach: gc session attach gc-42") {
				t.Errorf("message = %q, want it to carry the tool's full stdout", got.Message)
			}
			if calls := f.seenCalls(); len(calls) != 1 || calls[0].verb != verb || calls[0].bead != "tk-abc12" {
				t.Errorf("actuator saw %+v, want one %s on tk-abc12", calls, verb)
			}
		})
	}
}

// accept's sling-failure path exits 1 (gc-helm.sh cmd_accept). The route reports
// it as a verb failure (422) with the script's sentence, not a 5xx — the visit is
// left open and retry or Discuss is the move.
func TestAcceptSlingFailureExitOneIsVerbFailed(t *testing.T) {
	f := &fakeActuator{res: ToolResult{
		ExitCode: 1,
		Stderr:   "gc-helm: accept: 'gc sling ... --on mol-x' failed for tk-abc12 — the visit is left open for retry or Discuss. Nothing dismissed.\n",
	}}
	rr := serveOpen(t, f, actuateReq("accept", `{"bead":"tk-abc12"}`))
	if rr.Code != http.StatusUnprocessableEntity {
		t.Fatalf("status = %d, want 422", rr.Code)
	}
	got := decodeErr(t, rr)
	if got.Reason != reasonVerbFailed {
		t.Errorf("reason = %q, want %q", got.Reason, reasonVerbFailed)
	}
	if !strings.Contains(got.Error, "left open for retry") {
		t.Errorf("error = %q, want the script's sentence", got.Error)
	}
	if strings.HasPrefix(got.Error, "gc-helm:") {
		t.Errorf("error = %q, still carries the script's prefix", got.Error)
	}
}

// EXIT 2 IS VERB-DEPENDENT. On accept it is "the subject carries no recommended
// formula — it is discuss-only", a legitimate refusal the operator meets on a
// stale board row, so it is a 422 the message can explain — NOT the 500 wiring
// fault open's exit 2 is. Both halves are asserted so the distinction cannot be
// collapsed back into one shared mapping.
func TestExitTwoIsVerbDependent(t *testing.T) {
	fa := &fakeActuator{res: ToolResult{
		ExitCode: 2,
		Stderr:   "gc-helm: accept: tk-abc12 carries no gc.recommended_formula — it is discuss-only. Engage it to decide. Nothing dispatched.\n",
	}}
	ra := serveOpen(t, fa, actuateReq("accept", `{"bead":"tk-abc12"}`))
	if ra.Code != http.StatusUnprocessableEntity {
		t.Fatalf("accept exit 2 status = %d, want 422 (a discuss-only row is a refusal, not a service fault)", ra.Code)
	}
	if got := decodeErr(t, ra).Reason; got != reasonVerbFailed {
		t.Errorf("accept exit 2 reason = %q, want %q", got, reasonVerbFailed)
	}

	fo := &fakeActuator{res: ToolResult{ExitCode: 2, Stderr: "gc-helm: open: unknown flag '--nope'\n"}}
	ro := serveOpen(t, fo, openReq(`{"bead":"tk-abc12"}`))
	if ro.Code != http.StatusInternalServerError {
		t.Errorf("open exit 2 status = %d, want 500 — the verb-dependence regressed", ro.Code)
	}
	if got := decodeErr(t, ro).Reason; got != reasonUsage {
		t.Errorf("open exit 2 reason = %q, want %q", got, reasonUsage)
	}
}

// The parity routes share open's write middleware, verified per verb so a route
// wired without it cannot slip through: cross-site refused before exec, a bad id
// refused before exec, a nil actuator honest with 503, and non-POST 405.
func TestActuateRoutesShareTheWriteMiddleware(t *testing.T) {
	for _, verb := range []string{"accept", "engage", "dismiss"} {
		t.Run(verb+"/cross-site refused before exec", func(t *testing.T) {
			f := &fakeActuator{res: ToolResult{Stdout: "should never run"}}
			r := httptest.NewRequest(http.MethodPost, "/helm/"+verb, strings.NewReader(`{"bead":"tk-abc12"}`))
			r.Header.Set("Content-Type", "application/json")
			r.Header.Set("Sec-Fetch-Site", "cross-site")
			r.Header.Set("Origin", "https://evil.example")
			rr := serveOpen(t, f, r)
			if rr.Code != http.StatusForbidden {
				t.Fatalf("status = %d, want 403", rr.Code)
			}
			if calls := f.seen(); len(calls) != 0 {
				t.Fatalf("the tool ran for a cross-site %s: %q", verb, calls)
			}
		})
		t.Run(verb+"/bad id refused before exec", func(t *testing.T) {
			f := &fakeActuator{res: ToolResult{Stdout: "should never run"}}
			rr := serveOpen(t, f, actuateReq(verb, `{"bead":"--reason=pwned"}`))
			if rr.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, want 400", rr.Code)
			}
			if got := decodeErr(t, rr).Reason; got != reasonInvalidBead {
				t.Errorf("reason = %q, want %q", got, reasonInvalidBead)
			}
			if calls := f.seen(); len(calls) != 0 {
				t.Fatalf("a rejected id reached the %s subprocess: %q", verb, calls)
			}
		})
		t.Run(verb+"/nil actuator is honest 503", func(t *testing.T) {
			s := New(newFake(), time.Minute) // no actuator wired
			rr := httptest.NewRecorder()
			s.Handler().ServeHTTP(rr, actuateReq(verb, `{"bead":"tk-abc12"}`))
			if rr.Code != http.StatusServiceUnavailable {
				t.Fatalf("status = %d, want 503", rr.Code)
			}
			if got := decodeErr(t, rr).Reason; got != reasonUnavailable {
				t.Errorf("reason = %q, want %q", got, reasonUnavailable)
			}
		})
		t.Run(verb+"/non-POST is 405", func(t *testing.T) {
			f := &fakeActuator{}
			s := New(newFake(), time.Minute, WithActuator(f))
			rr := httptest.NewRecorder()
			s.Handler().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/helm/"+verb, nil))
			if rr.Code != http.StatusMethodNotAllowed {
				t.Errorf("GET status = %d, want 405", rr.Code)
			}
		})
	}
}

// The in-process gate keys on the subject (bead): every write verb mutates its
// visit, so a double-clicked Accept collapses AND an Accept racing a Dismiss on
// one subject is held. The refusal names the verb already running.
func TestActuationGateSerializesWritesPerSubject(t *testing.T) {
	g := newActuationGate()
	if ok, _ := g.enter("tk-abc12", "accept"); !ok {
		t.Fatal("first enter refused")
	}
	if ok, running := g.enter("tk-abc12", "accept"); ok {
		t.Error("a second accept on the same subject was admitted while one was in flight")
	} else if running != "accept" {
		t.Errorf("busy verb = %q, want %q", running, "accept")
	}
	if ok, running := g.enter("tk-abc12", "dismiss"); ok {
		t.Error("dismiss was admitted while an accept on the same subject was in flight — the accept/dismiss race is open")
	} else if running != "accept" {
		t.Errorf("busy verb = %q, want %q", running, "accept")
	}
	g.leave("tk-abc12")
	if ok, _ := g.enter("tk-abc12", "accept"); !ok {
		t.Error("subject stayed locked after leave")
	}
}

// A successful parity write drops the cached board, exactly as open does: accept
// dismisses a visit and slings, dismiss closes one, so the row the operator acted
// on changes and the next refresh must re-gather rather than serve the stale TTL.
func TestActuateSuccessInvalidatesTheBoardCache(t *testing.T) {
	f := &fakeActuator{res: ToolResult{Stdout: "gc-helm: accept: dispatched mol-x at tk-abc12\n"}}
	s := New(newFake(), time.Minute, WithActuator(f))
	if _, err := s.Board(context.Background()); err != nil {
		t.Fatalf("warm the board: %v", err)
	}
	s.mu.Lock()
	warm := s.cached != nil
	s.mu.Unlock()
	if !warm {
		t.Fatal("precondition: the board cache did not warm, so this test proves nothing")
	}
	rr := httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, actuateReq("accept", `{"bead":"tk-abc12"}`))
	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body=%s)", rr.Code, rr.Body.String())
	}
	s.mu.Lock()
	still := s.cached != nil
	s.mu.Unlock()
	if still {
		t.Error("the board cache survived a successful accept; the next refresh can show the pre-accept board")
	}
}

// Each parity route must win over the "/" catch-all, or a POST would reach the
// SPA handler and read as a 200 HTML page.
func TestActuateRoutesBeatTheSPACatchAll(t *testing.T) {
	spa, err := web.NewHandler()
	if err != nil {
		t.Fatalf("web.NewHandler: %v", err)
	}
	for _, verb := range []string{"accept", "engage", "dismiss"} {
		t.Run(verb, func(t *testing.T) {
			// dismiss runs with --json, so its stub must answer JSON, not prose.
			stdout := "gc-helm: " + verb + ": ok on tk-abc12\n"
			if verb == "dismiss" {
				stdout = `{"subject":"tk-abc12","matched":1,"closed":1,"ok":true}`
			}
			f := &fakeActuator{res: ToolResult{Stdout: stdout}}
			s := New(newFake(), time.Minute, WithSPA(spa), WithActuator(f))
			rr := httptest.NewRecorder()
			s.Handler().ServeHTTP(rr, actuateReq(verb, `{"bead":"tk-abc12"}`))
			if rr.Code != http.StatusOK {
				t.Fatalf("status = %d, want 200", rr.Code)
			}
			if ct := rr.Header().Get("Content-Type"); !strings.Contains(ct, "application/json") {
				t.Errorf("Content-Type = %q, want JSON — the SPA answered instead", ct)
			}
			if calls := f.seen(); len(calls) != 1 {
				t.Errorf("tool ran %d times, want 1", len(calls))
			}
		})
	}
}

func decodeDismiss(t *testing.T, rr *httptest.ResponseRecorder) dismissResponse {
	t.Helper()
	var got dismissResponse
	if err := json.Unmarshal(rr.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode 200 body: %v (body=%s)", err, rr.Body.String())
	}
	return got
}

func hasArg(args []string, want string) bool {
	for _, a := range args {
		if a == want {
			return true
		}
	}
	return false
}

// argFollows reports whether val is the argv element immediately after flag — the
// property that keeps a flag's value from floating loose into another position.
func argFollows(args []string, flag, val string) bool {
	for i := 0; i+1 < len(args); i++ {
		if args[i] == flag && args[i+1] == val {
			return true
		}
	}
	return false
}

// dismiss runs with --json and reports a CLOSED outcome when it closed the
// sitting. The flag is not optional — it is how the service reads the structured
// result and the held gates — so the forwarding is asserted here.
func TestDismissClosedReportsOutcomeAndForwardsJSON(t *testing.T) {
	f := &fakeActuator{res: ToolResult{Stdout: `{"subject":"tk-abc12","matched":1,"closed":1,"ok":true}`}}
	rr := serveOpen(t, f, actuateReq("dismiss", `{"bead":"tk-abc12"}`))
	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body=%s)", rr.Code, rr.Body.String())
	}
	got := decodeDismiss(t, rr)
	if got.Outcome != dismissOutcomeClosed {
		t.Errorf("outcome = %q, want %q", got.Outcome, dismissOutcomeClosed)
	}
	if len(got.Gates) != 0 {
		t.Errorf("gates = %+v, want none on a closed dismiss", got.Gates)
	}
	calls := f.seenCalls()
	if len(calls) != 1 || !hasArg(calls[0].args, "--json") {
		t.Errorf("dismiss ran with args %v, want it to carry --json", calls)
	}
}

// THE FINDING (review tk-89vkuv, P1). A dismiss that HELD for a gate decision
// (gc-helm.sh exit 5) must not read as an internal 502 with the gate details lost
// to firstStderrLine. It is a 200 carrying outcome held_for_gate_decision and every
// surfaced gate, so the board takes the resolve/leave decision in place instead of
// sending the operator to the CLI.
func TestDismissHeldForGateDecisionIsNotInternal(t *testing.T) {
	f := &fakeActuator{res: ToolResult{
		ExitCode: 5,
		Stdout:   `{"subject":"tk-abc12","ok":false,"held_for_gate_decision":true,"gates":[{"id":"tk-g1","blocks":"tk-abc12","demand":"should the merge wait on this?"}]}`,
		Stderr:   "gc-helm: dismiss: tk-abc12 carries open linked gate(s) a dismiss would orphan\n",
	}}
	rr := serveOpen(t, f, actuateReq("dismiss", `{"bead":"tk-abc12"}`))
	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 — exit 5 is a decision, not a 502 (body=%s)", rr.Code, rr.Body.String())
	}
	got := decodeDismiss(t, rr)
	if got.Outcome != dismissOutcomeHeld {
		t.Fatalf("outcome = %q, want %q", got.Outcome, dismissOutcomeHeld)
	}
	if len(got.Gates) != 1 || got.Gates[0].ID != "tk-g1" || got.Gates[0].Blocks != "tk-abc12" {
		t.Errorf("gates = %+v, want the surfaced gate carried through with its id and blocked bead", got.Gates)
	}
	if got.Gates[0].Demand == "" {
		t.Error("gate demand headline was dropped; the operator needs it to decide")
	}
}

// A held dismiss closed nothing, so it must NOT bust the board cache: invalidate
// only on a real write.
func TestDismissHeldDoesNotInvalidateBoard(t *testing.T) {
	f := &fakeActuator{res: ToolResult{
		ExitCode: 5,
		Stdout:   `{"subject":"tk-abc12","ok":false,"held_for_gate_decision":true,"gates":[{"id":"tk-g1","blocks":"tk-abc12","demand":"q"}]}`,
	}}
	s := New(newFake(), time.Minute, WithActuator(f))
	if _, err := s.Board(context.Background()); err != nil {
		t.Fatalf("warm the board: %v", err)
	}
	rr := httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, actuateReq("dismiss", `{"bead":"tk-abc12"}`))
	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rr.Code)
	}
	s.mu.Lock()
	still := s.cached != nil
	s.mu.Unlock()
	if !still {
		t.Error("a held dismiss busted the board cache, but it closed nothing")
	}
}

// The decision re-submit carries the operator's resolve/leave choices and the one
// ruling gc-helm.sh records for every resolved gate; the service turns them into
// the flags, each value adjacent to its flag.
func TestDismissForwardsTheGateDecision(t *testing.T) {
	f := &fakeActuator{res: ToolResult{Stdout: `{"subject":"tk-abc12","matched":1,"closed":1,"ok":true}`}}
	body := `{"bead":"tk-abc12","ruling":"land it","decisions":[{"gate":"tk-g1","action":"resolve"},{"gate":"tk-g2","action":"leave"}]}`
	rr := serveOpen(t, f, actuateReq("dismiss", body))
	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body=%s)", rr.Code, rr.Body.String())
	}
	calls := f.seenCalls()
	if len(calls) != 1 {
		t.Fatalf("dismiss ran %d times, want 1", len(calls))
	}
	args := calls[0].args
	if !argFollows(args, "--resolve-gate", "tk-g1") || !argFollows(args, "--leave-gate", "tk-g2") || !argFollows(args, "--ruling", "land it") {
		t.Errorf("dismiss args %v: a flag and its value are not adjacent", args)
	}
	if !hasArg(args, "--json") {
		t.Errorf("dismiss args %v missing --json", args)
	}
}

// A leave-only decision needs no ruling: re-asking a gate records nothing.
func TestDismissLeaveOnlyNeedsNoRuling(t *testing.T) {
	f := &fakeActuator{res: ToolResult{Stdout: `{"subject":"tk-abc12","matched":1,"closed":1,"ok":true}`}}
	body := `{"bead":"tk-abc12","decisions":[{"gate":"tk-g1","action":"leave"}]}`
	rr := serveOpen(t, f, actuateReq("dismiss", body))
	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body=%s)", rr.Code, rr.Body.String())
	}
	args := f.seenCalls()[0].args
	if hasArg(args, "--ruling") {
		t.Errorf("args %v carry --ruling for a leave-only decision", args)
	}
	if !hasArg(args, "--leave-gate") {
		t.Errorf("args %v missing --leave-gate", args)
	}
}

// A gate id becomes an argv element of the subprocess, so it crosses the same
// bead-id boundary the subject does: a crafted id is a 400 before anything runs,
// never a flag reaching dismiss.
func TestDismissRejectsBadGateID(t *testing.T) {
	f := &fakeActuator{res: ToolResult{Stdout: "should never run"}}
	body := `{"bead":"tk-abc12","ruling":"x","decisions":[{"gate":"--oops","action":"resolve"}]}`
	rr := serveOpen(t, f, actuateReq("dismiss", body))
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 (body=%s)", rr.Code, rr.Body.String())
	}
	if got := decodeErr(t, rr).Reason; got != reasonUsage {
		t.Errorf("reason = %q, want %q", got, reasonUsage)
	}
	if len(f.seen()) != 0 {
		t.Error("the subprocess ran despite a bad gate id")
	}
}

// Resolving a gate records a ruling; absent one, the request is a 400 before exec
// rather than a gc-helm.sh refusal one round-trip later.
func TestDismissResolveNeedsRuling(t *testing.T) {
	f := &fakeActuator{res: ToolResult{Stdout: "should never run"}}
	body := `{"bead":"tk-abc12","decisions":[{"gate":"tk-g1","action":"resolve"}]}`
	rr := serveOpen(t, f, actuateReq("dismiss", body))
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 (body=%s)", rr.Code, rr.Body.String())
	}
	if len(f.seen()) != 0 {
		t.Error("the subprocess ran despite a resolve with no ruling")
	}
}

// dismiss promises JSON (it runs with --json). Stdout the service cannot parse is a
// 502 it names, never a panic and never raw bytes shown to the operator.
func TestDismissUnreadableJSONIsReported(t *testing.T) {
	f := &fakeActuator{res: ToolResult{Stdout: "not json at all"}}
	rr := serveOpen(t, f, actuateReq("dismiss", `{"bead":"tk-abc12"}`))
	if rr.Code != http.StatusBadGateway {
		t.Fatalf("status = %d, want 502 (body=%s)", rr.Code, rr.Body.String())
	}
	if got := decodeErr(t, rr).Reason; got != reasonInternal {
		t.Errorf("reason = %q, want %q", got, reasonInternal)
	}
}
