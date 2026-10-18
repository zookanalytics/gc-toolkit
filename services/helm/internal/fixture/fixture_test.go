package fixture

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const testBoard = `{"generated_at":"2026-10-17T00:00:00Z","rows":[]}`

// spaStub stands in for the embedded app's handler and names the path it got.
var spaStub = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = io.WriteString(w, "app:"+r.URL.Path)
})

func serve(t *testing.T, h http.Handler, method, path string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(method, path, strings.NewReader(`{"bead":"tk-abc12"}`)))
	return rec
}

func mustHandler(t *testing.T, answers map[string]Answer) http.Handler {
	t.Helper()
	h, err := Handler([]byte(testBoard), answers, spaStub)
	if err != nil {
		t.Fatalf("Handler: %v", err)
	}
	return h
}

func readError(t *testing.T, rec *httptest.ResponseRecorder) errorBody {
	t.Helper()
	var e errorBody
	if err := json.Unmarshal(rec.Body.Bytes(), &e); err != nil {
		t.Fatalf("the error body %q is not JSON: %v", rec.Body.String(), err)
	}
	return e
}

func TestTheBoardIsServedAsJSONAtItsOwnPath(t *testing.T) {
	h := mustHandler(t, nil)
	for _, method := range []string{http.MethodGet, http.MethodHead, http.MethodPost} {
		rec := serve(t, h, method, "/helm")
		if rec.Code != http.StatusOK {
			t.Errorf("%s /helm: status %d, want 200", method, rec.Code)
		}
		if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
			t.Errorf("%s /helm: Content-Type %q, want application/json", method, ct)
		}
		if method != http.MethodHead && rec.Body.String() != testBoard {
			t.Errorf("%s /helm: body %q, want the board answer byte for byte", method, rec.Body.String())
		}
	}
}

func TestEveryOtherPathGoesToTheApp(t *testing.T) {
	h := mustHandler(t, nil)
	for _, path := range []string{"/", "/index.html", "/assets/index-abc.js", "/v0/city/x/beads"} {
		rec := serve(t, h, http.MethodGet, path)
		if got, want := rec.Body.String(), "app:"+path; got != want {
			t.Errorf("GET %s: body %q, want %q from the app handler", path, got, want)
		}
	}
}

func TestAVerbAnswersWithItsCannedAnswer(t *testing.T) {
	h := mustHandler(t, map[string]Answer{
		"dismiss": {Status: http.StatusOK, Body: []byte(`{"bead":"tk-abc12","verb":"dismiss","message":"dismissed"}`)},
		"accept":  {Status: http.StatusConflict, Body: []byte(`{"error":"already running engage on tk-abc12","reason":"busy"}`)},
	})
	rec := serve(t, h, http.MethodPost, "/helm/dismiss")
	if rec.Code != http.StatusOK || rec.Body.String() != `{"bead":"tk-abc12","verb":"dismiss","message":"dismissed"}` {
		t.Errorf("POST /helm/dismiss: %d %q, want the canned 200 answer", rec.Code, rec.Body.String())
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
		t.Errorf("POST /helm/dismiss: Content-Type %q, want application/json", ct)
	}
	rec = serve(t, h, http.MethodPost, "/helm/accept")
	if rec.Code != http.StatusConflict || readError(t, rec).Reason != "busy" {
		t.Errorf("POST /helm/accept: %d %q, want the canned 409 answer", rec.Code, rec.Body.String())
	}
}

func TestAVerbWithNoAnswerIsRefusedAsUnavailable(t *testing.T) {
	h := mustHandler(t, map[string]Answer{"dismiss": {Status: http.StatusOK, Body: []byte(`{}`)}})
	// open, the verbs the app knows, and one the service might add later.
	for _, verb := range []string{"open", "accept", "engage", "park"} {
		rec := serve(t, h, http.MethodPost, "/helm/"+verb)
		if rec.Code != http.StatusServiceUnavailable {
			t.Errorf("POST /helm/%s: status %d, want 503", verb, rec.Code)
			continue
		}
		e := readError(t, rec)
		if e.Reason != "unavailable" || !strings.Contains(e.Error, verb) {
			t.Errorf("POST /helm/%s: body %+v, want reason unavailable and a sentence naming the verb", verb, e)
		}
	}
}

func TestAVerbAcceptsPOSTOnly(t *testing.T) {
	h := mustHandler(t, map[string]Answer{"dismiss": {Status: http.StatusOK, Body: []byte(`{}`)}})
	for _, method := range []string{http.MethodGet, http.MethodPut, http.MethodDelete} {
		rec := serve(t, h, method, "/helm/dismiss")
		if rec.Code != http.StatusMethodNotAllowed || rec.Header().Get("Allow") != http.MethodPost {
			t.Errorf("%s /helm/dismiss: %d Allow=%q, want 405 with Allow: POST", method, rec.Code, rec.Header().Get("Allow"))
		}
		if e := readError(t, rec); e.Reason != "usage" {
			t.Errorf("%s /helm/dismiss: reason %q, want usage", method, e.Reason)
		}
	}
}

func TestAPathThatNamesNoVerbIsNotFound(t *testing.T) {
	h := mustHandler(t, nil)
	for _, path := range []string{"/helm/", "/helm/dismiss/extra", "/helm/Dismiss", "/helm/1x"} {
		if rec := serve(t, h, http.MethodPost, path); rec.Code != http.StatusNotFound {
			t.Errorf("POST %s: status %d, want 404", path, rec.Code)
		}
	}
}

func TestHandlerRefusesABoardThatIsNotAJSONObject(t *testing.T) {
	for _, board := range []string{"", "not json", "[1,2]", `"board"`, "{"} {
		if _, err := Handler([]byte(board), nil, spaStub); err == nil {
			t.Errorf("Handler(%q): no error, want a refusal", board)
		}
	}
	if _, err := Handler([]byte(testBoard), nil, nil); err == nil {
		t.Error("Handler with no app handler: no error, want a refusal")
	}
}

func writeFiles(t *testing.T, files map[string]string) string {
	t.Helper()
	dir := t.TempDir()
	for name, body := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

func TestLoadAnswersReadsTheStatusFromTheFileName(t *testing.T) {
	dir := writeFiles(t, map[string]string{
		"dismiss.json":     `{"bead":"tk-abc12","verb":"dismiss","message":"dismissed"}`,
		"accept.409.json":  `{"error":"busy","reason":"busy"}`,
		"open.json":        `{"bead":"tk-abc12","outcome":"filed","visit":"tk-v1","message":"filed"}`,
		".DS_Store":        "not json",
		"engage.503.json":  `{"error":"no tool","reason":"unavailable"}`,
		"park-later.json":  `{}`,
		"snake_case.json":  `{}`,
		"accept-all.json":  `{}`,
		"dismiss-all.json": `{}`,
	})
	got, err := LoadAnswers(dir)
	if err != nil {
		t.Fatalf("LoadAnswers: %v", err)
	}
	want := map[string]int{"dismiss": 200, "accept": 409, "open": 200, "engage": 503,
		"park-later": 200, "snake_case": 200, "accept-all": 200, "dismiss-all": 200}
	if len(got) != len(want) {
		t.Errorf("LoadAnswers: %d answers, want %d (the dotfile skipped)", len(got), len(want))
	}
	for verb, status := range want {
		if got[verb].Status != status {
			t.Errorf("answer for %s: status %d, want %d", verb, got[verb].Status, status)
		}
	}
	if string(got["dismiss"].Body) != `{"bead":"tk-abc12","verb":"dismiss","message":"dismissed"}` {
		t.Errorf("answer for dismiss: body %q, want the file's bytes", got["dismiss"].Body)
	}
}

func TestLoadAnswersRefusesWhatItCannotServe(t *testing.T) {
	cases := map[string]map[string]string{
		"a body that is not JSON":       {"dismiss.json": "dismissed"},
		"two answers for one verb":      {"dismiss.json": `{}`, "dismiss.409.json": `{}`},
		"a status out of range":         {"dismiss.700.json": `{}`},
		"a status that is no code":      {"dismiss.ok.json": `{}`},
		"a status of two digits":        {"dismiss.42.json": `{}`},
		"a file that is not .json":      {"dismiss.txt": `{}`},
		"a verb with upper case":        {"Dismiss.json": `{}`},
		"a name with three parts":       {"dismiss.409.extra.json": `{}`},
		"a status with a sign":          {"dismiss.+20.json": `{}`},
		"a verb that opens with a dash": {"-x.json": `{}`},
	}
	for name, files := range cases {
		if _, err := LoadAnswers(writeFiles(t, files)); err == nil {
			t.Errorf("%s: no error, want a refusal", name)
		}
	}
	dir := t.TempDir()
	if err := os.Mkdir(filepath.Join(dir, "dismiss.json"), 0o755); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadAnswers(dir); err == nil {
		t.Error("a directory among the answers: no error, want a refusal")
	}
	if _, err := LoadAnswers(filepath.Join(dir, "missing")); err == nil {
		t.Error("a missing answers directory: no error, want a refusal")
	}
}
