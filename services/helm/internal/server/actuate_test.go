package server

// Tests for the engage write route, POST /helm/engage.
//
// open_test.go exhausts the SHARED write middleware (the exit-code mapping, CSRF,
// the argument boundary, the client-disconnect and cache behaviour) through the
// open route. These tests prove engage is wired onto that same middleware and
// carries the tool's sentence back, plus the place it differs from open: its
// verb-dependent exit 2. The stub fakeActuator, serveOpen, openReq and decodeErr
// live in open_test.go.

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

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

// The engage route runs engage on the requested bead and hands back the tool's
// own stdout — the whole of it, since engage's attach line is on a second line
// the operator needs.
func TestActuateRoutesRunTheirVerb(t *testing.T) {
	for _, verb := range []string{"engage"} {
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

// EXIT 2 IS VERB-DEPENDENT. On engage it is a 422 the message can explain —
// NOT the 500 wiring fault open's exit 2 is. Both halves are asserted so the
// distinction cannot be collapsed back into one shared mapping.
func TestExitTwoIsVerbDependent(t *testing.T) {
	fe := &fakeActuator{res: ToolResult{ExitCode: 2, Stderr: "gc-helm: engage takes one subject\n"}}
	re := serveOpen(t, fe, actuateReq("engage", `{"bead":"tk-abc12"}`))
	if re.Code != http.StatusUnprocessableEntity {
		t.Fatalf("engage exit 2 status = %d, want 422", re.Code)
	}
	if got := decodeErr(t, re).Reason; got != reasonVerbFailed {
		t.Errorf("engage exit 2 reason = %q, want %q", got, reasonVerbFailed)
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

// The engage route shares open's write middleware, verified so a route wired
// without it cannot slip through: cross-site refused before exec, a bad id
// refused before exec, a nil actuator honest with 503, and non-POST 405.
func TestActuateRoutesShareTheWriteMiddleware(t *testing.T) {
	for _, verb := range []string{"engage"} {
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
			s := New() // no actuator wired
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
			s := New(WithActuator(f))
			rr := httptest.NewRecorder()
			s.Handler().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/helm/"+verb, nil))
			if rr.Code != http.StatusMethodNotAllowed {
				t.Errorf("GET status = %d, want 405", rr.Code)
			}
		})
	}
}

// The in-process gate keys on the subject (bead): every write verb acts on what
// the bead's conversations hold, so a double-clicked engage collapses AND an
// open racing an engage on one subject is held. The refusal names the verb
// already running.
func TestActuationGateSerializesWritesPerSubject(t *testing.T) {
	g := newActuationGate()
	if ok, _ := g.enter("tk-abc12", "engage"); !ok {
		t.Fatal("first enter refused")
	}
	if ok, running := g.enter("tk-abc12", "engage"); ok {
		t.Error("a second engage on the same subject was admitted while one was in flight")
	} else if running != "engage" {
		t.Errorf("busy verb = %q, want %q", running, "engage")
	}
	if ok, running := g.enter("tk-abc12", "open"); ok {
		t.Error("open was admitted while an engage on the same subject was in flight — the open/engage race is open")
	} else if running != "engage" {
		t.Errorf("busy verb = %q, want %q", running, "engage")
	}
	g.leave("tk-abc12")
	if ok, _ := g.enter("tk-abc12", "engage"); !ok {
		t.Error("subject stayed locked after leave")
	}
}

// A successful engage drops the rig board's cached answers, exactly as open
// does: engage starts a sitting on a conversation, so the row the operator acted
// on changes and the next refresh must re-gather rather than serve the stale TTL.
func TestActuateSuccessInvalidatesTheRigBoardCache(t *testing.T) {
	reads := &rigReads{}
	s := newRigServer(reads)
	s.actuator = &fakeActuator{res: ToolResult{Stdout: "gc-helm: engage: started gc-42 on tk-abc12\n"}}
	get(t, s, "/helm/rigs/gc-toolkit")
	rr := httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, actuateReq("engage", `{"bead":"tk-abc12"}`))
	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body=%s)", rr.Code, rr.Body.String())
	}
	get(t, s, "/helm/rigs/gc-toolkit")
	if reads.reads != 2 {
		t.Errorf("the rig was read %d times, want twice: the cache survived a successful engage", reads.reads)
	}
}

// The engage route must win over the "/" catch-all, or a POST would reach the
// SPA handler and read as a 200 HTML page.
func TestActuateRoutesBeatTheSPACatchAll(t *testing.T) {
	spa, err := web.NewHandler()
	if err != nil {
		t.Fatalf("web.NewHandler: %v", err)
	}
	for _, verb := range []string{"engage"} {
		t.Run(verb, func(t *testing.T) {
			f := &fakeActuator{res: ToolResult{Stdout: "gc-helm: " + verb + ": ok on tk-abc12\n"}}
			s := New(WithSPA(spa), WithActuator(f))
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
