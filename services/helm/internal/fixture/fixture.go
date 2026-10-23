// Package fixture serves the Helm board on fixture data, so a demo capture can
// show the board a commit builds with no city behind it.
//
// It serves the embedded app, a board answer read from a file at the board's own
// path, and a canned answer for each write verb, and nothing else. It gathers no
// bead state and runs no write tool, so nothing it serves reads or writes a city.
// cmd/helm-fixture is its command, and that command's tests hold its import graph
// to this package, the app's package and the standard library.
package fixture

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

// Answer is one write verb's canned HTTP answer: the status and the JSON body the
// app's client reads (services/helm/web/src/actuate/client.ts and
// src/open/client.ts).
type Answer struct {
	Status int
	Body   []byte
}

// verbRE is the shape of a write verb's name, the last segment of
// POST /helm/<verb>.
var verbRE = regexp.MustCompile(`^[a-z][a-z0-9_-]*$`)

// errorBody mirrors helm-svc's actuateErrorBody (internal/server/actuate.go), the
// non-2xx body the app's clients read their reason and sentence from.
type errorBody struct {
	Error  string `json:"error"`
	Reason string `json:"reason"`
}

// Handler returns the fixture's routes.
//
//   - /helm answers board, in the place helm-svc answers the board it computes,
//     as JSON, whatever the method.
//   - POST /helm/<verb> answers with that verb's canned answer. A verb with none
//     answers 503 with reason "unavailable", as helm-svc answers a write when it
//     has no write tool, so the app shows its refusal and nothing runs.
//   - Any other method on /helm/<verb> answers 405, as helm-svc's does.
//   - Every other path goes to spa, the embedded app's handler.
//
// Any segment after /helm/ is a verb, so a verb the service adds later is served
// here too, refused until it has an answer.
func Handler(board []byte, answers map[string]Answer, spa http.Handler) (http.Handler, error) {
	if !json.Valid(board) {
		return nil, fmt.Errorf("the board answer is not JSON")
	}
	if trimmed := strings.TrimSpace(string(board)); !strings.HasPrefix(trimmed, "{") {
		return nil, fmt.Errorf("the board answer is not a JSON object")
	}
	if spa == nil {
		return nil, fmt.Errorf("no app handler")
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/helm", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write(board)
	})
	mux.HandleFunc("/helm/", func(w http.ResponseWriter, r *http.Request) {
		verb := strings.TrimPrefix(r.URL.Path, "/helm/")
		if !verbRE.MatchString(verb) {
			http.NotFound(w, r)
			return
		}
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			writeError(w, http.StatusMethodNotAllowed, "usage", "this route accepts POST only")
			return
		}
		a, ok := answers[verb]
		if !ok {
			writeError(w, http.StatusServiceUnavailable, "unavailable",
				"this board is serving fixture data and has no answer for "+verb)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(a.Status)
		_, _ = w.Write(a.Body)
	})
	mux.Handle("/", spa)
	return mux, nil
}

func writeError(w http.ResponseWriter, status int, reason, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(errorBody{Error: msg, Reason: reason})
}

// LoadAnswers reads the canned write answers in dir. A file named <verb>.json is
// that verb's answer with status 200, and <verb>.<status>.json answers with that
// HTTP status, so a verb can answer the way a refusal does. Each body must be
// JSON and a verb takes one file. A dotfile is skipped. Any other entry is an
// error, so a misnamed answer stops the start instead of going unserved.
func LoadAnswers(dir string) (map[string]Answer, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, fmt.Errorf("read the answers directory: %w", err)
	}
	answers := map[string]Answer{}
	files := map[string]string{}
	for _, e := range entries {
		name := e.Name()
		if strings.HasPrefix(name, ".") {
			continue
		}
		if e.IsDir() {
			return nil, fmt.Errorf("%s in %s is a directory; the answers directory holds only <verb>.json and <verb>.<status>.json files", name, dir)
		}
		stem, ok := strings.CutSuffix(name, ".json")
		verb, code, hasCode := strings.Cut(stem, ".")
		if !ok || !verbRE.MatchString(verb) {
			return nil, fmt.Errorf("%s in %s is neither <verb>.json nor <verb>.<status>.json", name, dir)
		}
		status := http.StatusOK
		if hasCode {
			n, err := strconv.Atoi(code)
			if err != nil || len(code) != 3 || n < 100 || n > 599 {
				return nil, fmt.Errorf("%s in %s names %q, which is not an HTTP status from 100 to 599", name, dir, code)
			}
			status = n
		}
		if prev, dup := files[verb]; dup {
			return nil, fmt.Errorf("%s and %s in %s both answer %s; give each verb one answer", prev, name, dir, verb)
		}
		body, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			return nil, fmt.Errorf("read %s: %w", name, err)
		}
		if !json.Valid(body) {
			return nil, fmt.Errorf("%s in %s is not JSON", name, dir)
		}
		files[verb] = name
		answers[verb] = Answer{Status: status, Body: body}
	}
	return answers, nil
}
