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

// Each parity route runs the verb its path names, on the requested bead, and
// hands back the tool's own stdout — the whole of it, since engage's attach line
// and accept's dismiss line are on a second line the operator needs.
func TestActuateRoutesRunTheirVerb(t *testing.T) {
	for _, verb := range []string{"accept", "engage", "dismiss"} {
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

// The in-process gate keys on (verb, bead): a double-clicked Accept collapses,
// but Accept and Dismiss on one row never block each other.
func TestActuationGateIsPerVerbAndBead(t *testing.T) {
	g := newActuationGate()
	if !g.enter("accept:tk-abc12") {
		t.Fatal("first enter refused")
	}
	if g.enter("accept:tk-abc12") {
		t.Error("a second accept on the same bead was admitted while one was in flight")
	}
	if !g.enter("dismiss:tk-abc12") {
		t.Error("dismiss was blocked by an in-flight accept on the same bead")
	}
	g.leave("accept:tk-abc12")
	if !g.enter("accept:tk-abc12") {
		t.Error("accept stayed locked after leave")
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
			f := &fakeActuator{res: ToolResult{Stdout: "gc-helm: " + verb + ": ok on tk-abc12\n"}}
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
