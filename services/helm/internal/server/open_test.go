package server

// Tests for POST /helm/open.
//
// The subject here is the MAPPING, not the script: what the operator is told
// for each way an open can end. gc-helm.sh's own behaviour is covered by
// assets/scripts/gate-visit.test.sh; what could regress silently on this side
// is an exit code losing its distinct message, an invalid id reaching the
// subprocess, or a cross-site POST being served.

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/web"
)

// fakeOpener records what it was asked and returns a canned result.
type fakeOpener struct {
	mu    sync.Mutex
	calls []string

	res ToolResult
	err error

	// block, when non-nil, holds Open until it is closed — used to make two
	// requests genuinely concurrent.
	block chan struct{}
}

func (f *fakeOpener) Open(_ context.Context, bead string) (ToolResult, error) {
	f.mu.Lock()
	f.calls = append(f.calls, bead)
	f.mu.Unlock()
	if f.block != nil {
		<-f.block
	}
	return f.res, f.err
}

func (f *fakeOpener) seen() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string(nil), f.calls...)
}

// openReq builds a same-origin POST, the shape the board's fetch sends.
func openReq(body string) *http.Request {
	r := httptest.NewRequest(http.MethodPost, "/helm/open", strings.NewReader(body))
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set("Sec-Fetch-Site", "same-origin")
	return r
}

func serveOpen(t *testing.T, o Opener, r *http.Request) *httptest.ResponseRecorder {
	t.Helper()
	s := New(newFake(), time.Minute, WithOpener(o))
	rr := httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, r)
	return rr
}

func decodeOK(t *testing.T, rr *httptest.ResponseRecorder) openResponse {
	t.Helper()
	var got openResponse
	if err := json.Unmarshal(rr.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode 200 body: %v (body=%s)", err, rr.Body.String())
	}
	return got
}

func decodeErr(t *testing.T, rr *httptest.ResponseRecorder) openErrorBody {
	t.Helper()
	var got openErrorBody
	if err := json.Unmarshal(rr.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode error body: %v (body=%s)", err, rr.Body.String())
	}
	return got
}

// A new visit and an already-open one are both exit 0, and the operator must be
// able to tell them apart — clicking twice and reading "filed" both times would
// misdescribe what the city did.
func TestOpenDistinguishesFiledFromExisting(t *testing.T) {
	for _, tc := range []struct {
		name        string
		stdout      string
		wantOutcome string
		wantVisit   string
	}{
		{
			name:        "filed",
			stdout:      "gc-helm: visit tk-v1s1t filed on tk-abc12 (pool gc-toolkit/gc-toolkit.converse) — a converse session will spawn (cold) or vacuum it (warm).\n       Attach via the sessions picker.\n",
			wantOutcome: "filed",
			wantVisit:   "tk-v1s1t",
		},
		{
			name:        "already open",
			stdout:      "gc-helm: visit tk-old99 is already open for tk-abc12 — a converse session holds it (or will spawn/vacuum it).\n       Attach via the sessions picker.\n",
			wantOutcome: "existing",
			wantVisit:   "tk-old99",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := &fakeOpener{res: ToolResult{Stdout: tc.stdout}}
			rr := serveOpen(t, f, openReq(`{"bead":"tk-abc12"}`))
			if rr.Code != http.StatusOK {
				t.Fatalf("status = %d, want 200 (body=%s)", rr.Code, rr.Body.String())
			}
			got := decodeOK(t, rr)
			if got.Outcome != tc.wantOutcome {
				t.Errorf("outcome = %q, want %q", got.Outcome, tc.wantOutcome)
			}
			if got.Visit != tc.wantVisit {
				t.Errorf("visit = %q, want %q", got.Visit, tc.wantVisit)
			}
			if got.Bead != "tk-abc12" {
				t.Errorf("bead = %q, want tk-abc12", got.Bead)
			}
			// The script's own first sentence reaches the browser.
			if !strings.Contains(got.Message, "visit "+tc.wantVisit) {
				t.Errorf("message = %q, want it to carry the script's sentence", got.Message)
			}
		})
	}
}

// An unrecognised success sentence must still read as success: the visit was
// filed regardless of how the script phrased it.
func TestOpenUnparsedSuccessIsStillSuccess(t *testing.T) {
	f := &fakeOpener{res: ToolResult{Stdout: "gc-helm: something new and unrecognised\n"}}
	rr := serveOpen(t, f, openReq(`{"bead":"tk-abc12"}`))
	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rr.Code)
	}
	got := decodeOK(t, rr)
	if got.Outcome != "opened" {
		t.Errorf("outcome = %q, want opened", got.Outcome)
	}
	if got.Message == "" {
		t.Error("message is empty; the operator would be told nothing")
	}
}

// THE POINT OF THE WHOLE ROUTE'S ERROR HANDLING: each exit code lands on its
// own status and reason, and the script's specific sentence survives to the
// browser. A regression here is what turns the button's failure mode back into
// a shrug.
func TestOpenExitCodesMapDistinctly(t *testing.T) {
	for _, tc := range []struct {
		name       string
		exit       int
		stderr     string
		wantStatus int
		wantReason string
		wantMsg    string
	}{
		{
			name:       "bead not found: wrong prefix",
			exit:       4,
			stderr:     "gc-helm: open: bead not found: 'zz-nope1' — its id prefix 'zz' matches no rig in 'gc rig list'. No visit filed.\n",
			wantStatus: http.StatusUnprocessableEntity,
			wantReason: reasonVerbFailed,
			wantMsg:    "its id prefix 'zz' matches no rig",
		},
		{
			name:       "data plane down",
			exit:       4,
			stderr:     "gc-helm: open: could not verify 'tk-abc12' — 'gc bd show' did not answer (connection refused) (data plane down?). No visit filed.\n",
			wantStatus: http.StatusUnprocessableEntity,
			wantReason: reasonVerbFailed,
			wantMsg:    "data plane down?",
		},
		{
			name:       "environment",
			exit:       3,
			stderr:     "gc-helm: could not enumerate rigs\n",
			wantStatus: http.StatusServiceUnavailable,
			wantReason: reasonEnvironment,
			wantMsg:    "could not enumerate rigs",
		},
		{
			name:       "usage is a wiring fault, not operator error",
			exit:       2,
			stderr:     "gc-helm: open: unknown flag '--nope'\n",
			wantStatus: http.StatusInternalServerError,
			wantReason: reasonUsage,
			wantMsg:    "unknown flag",
		},
		{
			name:       "unknown code",
			exit:       9,
			stderr:     "gc-helm: exploded\n",
			wantStatus: http.StatusBadGateway,
			wantReason: reasonInternal,
			wantMsg:    "exploded",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := &fakeOpener{res: ToolResult{ExitCode: tc.exit, Stderr: tc.stderr}}
			rr := serveOpen(t, f, openReq(`{"bead":"tk-abc12"}`))
			if rr.Code != tc.wantStatus {
				t.Errorf("status = %d, want %d", rr.Code, tc.wantStatus)
			}
			got := decodeErr(t, rr)
			if got.Reason != tc.wantReason {
				t.Errorf("reason = %q, want %q", got.Reason, tc.wantReason)
			}
			if !strings.Contains(got.Error, tc.wantMsg) {
				t.Errorf("error = %q, want it to contain %q", got.Error, tc.wantMsg)
			}
			// The tool's own name is stripped: the operator did not run it.
			if strings.HasPrefix(got.Error, "gc-helm:") {
				t.Errorf("error = %q, still carries the script's prefix", got.Error)
			}
		})
	}
}

// Exit 3 is the code gc-helm.sh currently overloads (tk-lzdty half 2). This
// route must not add a second guess on top of it: whatever sentence the script
// gives is what the operator sees, so the day the script's sentences separate,
// these do too with no change here.
func TestOpenExitThreePassesTheScriptsSentenceThrough(t *testing.T) {
	sentences := []string{
		"gc-helm: could not enumerate rigs (timed out after 30s)\n",
		"gc-helm: could not enumerate rigs (jq failed to parse 'gc rig list')\n",
		"gc-helm: could not enumerate rigs (this city has no rigs)\n",
	}
	seen := map[string]bool{}
	for _, s := range sentences {
		f := &fakeOpener{res: ToolResult{ExitCode: 3, Stderr: s}}
		rr := serveOpen(t, f, openReq(`{"bead":"tk-abc12"}`))
		got := decodeErr(t, rr)
		if seen[got.Error] {
			t.Errorf("two different script sentences rendered identically: %q", got.Error)
		}
		seen[got.Error] = true
	}
}

// A failure with nothing on stderr must not be reported as a success, and must
// not invent a cause.
func TestOpenSilentFailureNamesTheExitCode(t *testing.T) {
	f := &fakeOpener{res: ToolResult{ExitCode: 4}}
	rr := serveOpen(t, f, openReq(`{"bead":"tk-abc12"}`))
	if rr.Code != http.StatusUnprocessableEntity {
		t.Fatalf("status = %d, want 422", rr.Code)
	}
	if got := decodeErr(t, rr).Error; !strings.Contains(got, "exit 4") {
		t.Errorf("error = %q, want it to name the exit code", got)
	}
}

func TestOpenToolFailures(t *testing.T) {
	for _, tc := range []struct {
		name       string
		err        error
		wantStatus int
		wantReason string
	}{
		{"timeout", fmt.Errorf("%w after 2m0s", ErrToolTimeout), http.StatusGatewayTimeout, reasonTimeout},
		{"unavailable", fmt.Errorf("%w: /nope: no such file", ErrToolUnavailable), http.StatusServiceUnavailable, reasonUnavailable},
		{"unclassified", errors.New("something else"), http.StatusInternalServerError, reasonInternal},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := &fakeOpener{err: tc.err}
			rr := serveOpen(t, f, openReq(`{"bead":"tk-abc12"}`))
			if rr.Code != tc.wantStatus {
				t.Errorf("status = %d, want %d", rr.Code, tc.wantStatus)
			}
			if got := decodeErr(t, rr).Reason; got != tc.wantReason {
				t.Errorf("reason = %q, want %q", got, tc.wantReason)
			}
		})
	}
}

// A timeout must say that nothing was filed — the operator's next move (retry,
// or go look) depends on it.
func TestOpenTimeoutSaysNoVisitWasFiled(t *testing.T) {
	f := &fakeOpener{err: fmt.Errorf("%w after 2m0s", ErrToolTimeout)}
	rr := serveOpen(t, f, openReq(`{"bead":"tk-abc12"}`))
	if got := decodeErr(t, rr).Error; !strings.Contains(got, "no visit was filed") {
		t.Errorf("error = %q, want it to say no visit was filed", got)
	}
}

// THE ARGUMENT BOUNDARY. A rejected id must never reach the subprocess — an id
// beginning with "-" would be read by cmd_open's flag loop as a flag.
func TestOpenRejectsBadBeadIDsWithoutExecuting(t *testing.T) {
	for _, bad := range []string{
		"-x",
		"--reason=pwned",
		"-",
		"tk-abc12 extra",
		"tk-abc12;whoami",
		"tk-abc12\nopen tk-other",
		"../../etc/passwd",
		"TK-ABC12",
		"tk_abc12",
		"tkabc12",
		"tk-",
		"",
		"   ",
		strings.Repeat("a", 40) + "-" + strings.Repeat("b", 40),
	} {
		t.Run(fmt.Sprintf("%q", bad), func(t *testing.T) {
			f := &fakeOpener{res: ToolResult{Stdout: "should never run"}}
			body, err := json.Marshal(openRequest{Bead: bad})
			if err != nil {
				t.Fatalf("marshal: %v", err)
			}
			rr := serveOpen(t, f, openReq(string(body)))
			if rr.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, want 400 (body=%s)", rr.Code, rr.Body.String())
			}
			if got := decodeErr(t, rr).Reason; got != reasonInvalidBead {
				t.Errorf("reason = %q, want %q", got, reasonInvalidBead)
			}
			if calls := f.seen(); len(calls) != 0 {
				t.Fatalf("the tool ran with %q; a rejected id must never reach the subprocess", calls)
			}
		})
	}
}

// The ids the city actually mints must all be accepted — a boundary that
// rejects real rows is as broken as one that admits flags.
func TestOpenAcceptsRealBeadIDs(t *testing.T) {
	for _, good := range []string{"tk-abc12", "tk-yc00g", "tk-eemvf.3", "sl-kg9z6.4.1", "su-ab9je", "gc2-x1y2"} {
		t.Run(good, func(t *testing.T) {
			f := &fakeOpener{res: ToolResult{Stdout: "gc-helm: visit tk-v filed on " + good + " (pool p) — x.\n"}}
			body, err := json.Marshal(openRequest{Bead: good})
			if err != nil {
				t.Fatalf("marshal: %v", err)
			}
			rr := serveOpen(t, f, openReq(string(body)))
			if rr.Code != http.StatusOK {
				t.Fatalf("status = %d, want 200 (body=%s)", rr.Code, rr.Body.String())
			}
			if calls := f.seen(); len(calls) != 1 || calls[0] != good {
				t.Errorf("tool saw %q, want exactly [%q]", calls, good)
			}
		})
	}
}

// CSRF. The operator's browser sits on the tailnet, so a page they visit must
// not be able to file visits with their network position.
func TestOpenRefusesCrossSiteWrites(t *testing.T) {
	for _, tc := range []struct {
		name      string
		fetchSite string
		origin    string
		wantAllow bool
	}{
		{"same-origin", "same-origin", "https://board.example", true},
		{"typed url", "none", "", true},
		{"non-browser client", "", "", true},
		{"cross-site", "cross-site", "https://evil.example", false},
		{"same-site subdomain", "same-site", "https://other.example", false},
		{"origin without fetch metadata", "", "https://evil.example", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := &fakeOpener{res: ToolResult{Stdout: "gc-helm: visit tk-v filed on tk-abc12 (pool p) — x.\n"}}
			r := httptest.NewRequest(http.MethodPost, "/helm/open", strings.NewReader(`{"bead":"tk-abc12"}`))
			r.Header.Set("Content-Type", "application/json")
			if tc.fetchSite != "" {
				r.Header.Set("Sec-Fetch-Site", tc.fetchSite)
			}
			if tc.origin != "" {
				r.Header.Set("Origin", tc.origin)
			}
			rr := serveOpen(t, f, r)
			if tc.wantAllow {
				if rr.Code != http.StatusOK {
					t.Fatalf("status = %d, want 200 (body=%s)", rr.Code, rr.Body.String())
				}
				return
			}
			if rr.Code != http.StatusForbidden {
				t.Fatalf("status = %d, want 403", rr.Code)
			}
			if got := decodeErr(t, rr).Reason; got != reasonForbidden {
				t.Errorf("reason = %q, want %q", got, reasonForbidden)
			}
			if calls := f.seen(); len(calls) != 0 {
				t.Fatalf("the tool ran for a cross-site write: %q", calls)
			}
		})
	}
}

// Double-click. cmd_open's one-visit-per-subject gate is read-then-create, so
// two concurrent opens on one bead could each pass it and file two visits —
// splitting the conversation the gate exists to keep whole.
func TestOpenCollapsesConcurrentOpensOfTheSameBead(t *testing.T) {
	f := &fakeOpener{
		res:   ToolResult{Stdout: "gc-helm: visit tk-v filed on tk-abc12 (pool p) — x.\n"},
		block: make(chan struct{}),
	}
	s := New(newFake(), time.Minute, WithOpener(f))

	first := make(chan int, 1)
	go func() {
		rr := httptest.NewRecorder()
		s.Handler().ServeHTTP(rr, openReq(`{"bead":"tk-abc12"}`))
		first <- rr.Code
	}()

	// Wait until the first request is inside the tool, so the second is
	// genuinely concurrent rather than merely later.
	deadline := time.After(2 * time.Second)
	for len(f.seen()) == 0 {
		select {
		case <-deadline:
			t.Fatal("first request never reached the tool")
		default:
			time.Sleep(time.Millisecond)
		}
	}

	second := httptest.NewRecorder()
	s.Handler().ServeHTTP(second, openReq(`{"bead":"tk-abc12"}`))
	if second.Code != http.StatusConflict {
		t.Errorf("second concurrent open status = %d, want 409", second.Code)
	}
	if got := decodeErr(t, second).Reason; got != reasonBusy {
		t.Errorf("second reason = %q, want %q", got, reasonBusy)
	}

	close(f.block)
	if code := <-first; code != http.StatusOK {
		t.Errorf("first open status = %d, want 200", code)
	}
	if calls := f.seen(); len(calls) != 1 {
		t.Errorf("tool ran %d times, want exactly 1 — the second must not reach it", len(calls))
	}
}

// A different bead is never blocked by one in flight.
func TestOpenDoesNotBlockADifferentBead(t *testing.T) {
	g := newOpenGate()
	if !g.enter("tk-abc12") {
		t.Fatal("first enter refused")
	}
	if !g.enter("tk-other") {
		t.Error("a different bead was refused while another was in flight")
	}
	g.leave("tk-abc12")
	if !g.enter("tk-abc12") {
		t.Error("bead stayed locked after leave")
	}
}

func TestOpenRejectsNonPost(t *testing.T) {
	f := &fakeOpener{}
	s := New(newFake(), time.Minute, WithOpener(f))
	for _, m := range []string{http.MethodGet, http.MethodPut, http.MethodDelete} {
		rr := httptest.NewRecorder()
		s.Handler().ServeHTTP(rr, httptest.NewRequest(m, "/helm/open", nil))
		if rr.Code != http.StatusMethodNotAllowed {
			t.Errorf("%s status = %d, want 405", m, rr.Code)
		}
		if got := rr.Header().Get("Allow"); got != http.MethodPost {
			t.Errorf("%s Allow = %q, want POST", m, got)
		}
	}
	if calls := f.seen(); len(calls) != 0 {
		t.Errorf("the tool ran for a non-POST request: %q", calls)
	}
}

func TestOpenMalformedBody(t *testing.T) {
	f := &fakeOpener{}
	rr := serveOpen(t, f, openReq(`{"bead":`))
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rr.Code)
	}
	if got := decodeErr(t, rr).Reason; got != reasonUsage {
		t.Errorf("reason = %q, want %q", got, reasonUsage)
	}
}

// Without an opener the board still serves; the route says why rather than
// 404ing as though it were a typo.
func TestOpenWithoutOpenerIsHonest(t *testing.T) {
	s := New(newFake(), time.Minute)
	rr := httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, openReq(`{"bead":"tk-abc12"}`))
	if rr.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503", rr.Code)
	}
	if got := decodeErr(t, rr).Reason; got != reasonUnavailable {
		t.Errorf("reason = %q, want %q", got, reasonUnavailable)
	}
}

// The route must win over the "/" catch-all, or a POST would reach the SPA
// handler and read as a 200 HTML page.
func TestOpenRouteBeatsTheSPACatchAll(t *testing.T) {
	spa, err := web.NewHandler()
	if err != nil {
		t.Fatalf("web.NewHandler: %v", err)
	}
	f := &fakeOpener{res: ToolResult{Stdout: "gc-helm: visit tk-v filed on tk-abc12 (pool p) — x.\n"}}
	s := New(newFake(), time.Minute, WithSPA(spa), WithOpener(f))
	rr := httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, openReq(`{"bead":"tk-abc12"}`))
	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rr.Code)
	}
	if ct := rr.Header().Get("Content-Type"); !strings.Contains(ct, "application/json") {
		t.Fatalf("Content-Type = %q, want JSON — the SPA answered instead", ct)
	}
	if calls := f.seen(); len(calls) != 1 {
		t.Errorf("tool ran %d times, want 1", len(calls))
	}
}

// The board itself must be unaffected by the new route.
func TestBoardStillServesAlongsideOpen(t *testing.T) {
	f := &fakeOpener{}
	s := New(newFake(), time.Minute, WithOpener(f))
	for _, path := range []string{"/helm", "/", "/healthz"} {
		rr := httptest.NewRecorder()
		s.Handler().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, path, nil))
		if rr.Code != http.StatusOK {
			t.Errorf("GET %s = %d, want 200", path, rr.Code)
		}
	}
}
