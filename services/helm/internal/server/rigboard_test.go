package server

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
	"github.com/zookanalytics/gc-toolkit/services/helm/internal/rigboard"
)

// rigGC answers the rig board's gc calls for one rig holding one task, and
// counts the store reads.
type rigGC struct {
	mu    sync.Mutex
	lists int
	fail  error
}

func (g *rigGC) JSON(_ context.Context, out any, args ...string) error {
	g.mu.Lock()
	defer g.mu.Unlock()
	var payload string
	switch {
	case len(args) >= 2 && args[0] == "rig" && args[1] == "list":
		payload = `{"rigs":[{"name":"gc-toolkit","path":"/city/rigs/gc-toolkit"}]}`
	case len(args) >= 4 && args[0] == "bd" && args[3] == "list":
		if g.fail != nil {
			return g.fail
		}
		if strings.Contains(strings.Join(args, " "), "--parent") {
			payload = `[]`
		} else {
			g.lists++
			payload = `[{"id":"tk-1","title":"a task","status":"open","priority":2,"issue_type":"task","created_at":"2026-11-11T00:00:00Z"}]`
		}
	default:
		return errors.New("rigGC answers no " + strings.Join(args, " "))
	}
	return json.Unmarshal([]byte(payload), out)
}

func clearHolds(_ context.Context, _ string, ids []string) (map[string]waits.Holds, map[string]error, error) {
	out := map[string]waits.Holds{}
	for _, id := range ids {
		out[id] = waits.Holds{ID: id, Status: waits.Clear}
	}
	return out, map[string]error{}, nil
}

func newRigServer(gc *rigGC) *Server {
	s := New(newFake(), time.Minute, WithRigBoard(gc, time.Minute))
	s.rigBoard.readHolds = clearHolds
	return s
}

func get(t *testing.T, s *Server, path string) *httptest.ResponseRecorder {
	t.Helper()
	rr := httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, path, nil))
	return rr
}

func TestRigBoardRoutes(t *testing.T) {
	gc := &rigGC{}
	s := newRigServer(gc)

	rr := get(t, s, "/helm/rigs")
	var rigs rigboard.Rigs
	if rr.Code != http.StatusOK || json.Unmarshal(rr.Body.Bytes(), &rigs) != nil || len(rigs.Rigs) != 1 || rigs.Rigs[0] != "gc-toolkit" {
		t.Fatalf("GET /helm/rigs = %d %s", rr.Code, rr.Body.String())
	}

	rr = get(t, s, "/helm/rigs/gc-toolkit")
	var resp rigboard.Response
	if rr.Code != http.StatusOK || json.Unmarshal(rr.Body.Bytes(), &resp) != nil {
		t.Fatalf("GET /helm/rigs/gc-toolkit = %d %s", rr.Code, rr.Body.String())
	}
	if resp.Board.Rig != "gc-toolkit" || resp.ReadAt == "" || resp.Board.Rows["tk-1"].Signal != "Not scheduled" {
		t.Errorf("document = %+v", resp)
	}

	if rr := get(t, s, "/helm/rigs/nowhere"); rr.Code != http.StatusNotFound {
		t.Errorf("an unknown rig = %d, want 404", rr.Code)
	}
}

// TestRigBoardCaches holds the document's cache to the board's rule: served
// whole for its time to live, and gathered again once a write route succeeds.
func TestRigBoardCaches(t *testing.T) {
	gc := &rigGC{}
	s := newRigServer(gc)
	for range 3 {
		if rr := get(t, s, "/helm/rigs/gc-toolkit"); rr.Code != http.StatusOK {
			t.Fatalf("status %d", rr.Code)
		}
	}
	if gc.lists != 1 {
		t.Fatalf("three reads gathered %d times, want once", gc.lists)
	}
	s.invalidateBoard()
	get(t, s, "/helm/rigs/gc-toolkit")
	if gc.lists != 2 {
		t.Fatalf("a read after a write gathered %d times in all, want twice", gc.lists)
	}
	now := time.Now()
	s.now = func() time.Time { return now.Add(2 * time.Minute) }
	get(t, s, "/helm/rigs/gc-toolkit")
	if gc.lists != 3 {
		t.Fatalf("a read past the time to live gathered %d times in all, want three", gc.lists)
	}
}

// TestRigBoardSaysAFailedRead holds a failed read to an error, never a
// document drawn from nothing.
func TestRigBoardSaysAFailedRead(t *testing.T) {
	gc := &rigGC{fail: errors.New("the store did not answer")}
	s := newRigServer(gc)
	rr := get(t, s, "/helm/rigs/gc-toolkit")
	if rr.Code != http.StatusBadGateway || !strings.Contains(rr.Body.String(), "the store did not answer") {
		t.Fatalf("a failed read = %d %s, want 502 naming the failure", rr.Code, rr.Body.String())
	}
	if strings.Contains(rr.Body.String(), `"board"`) {
		t.Errorf("a failed read carried a document: %s", rr.Body.String())
	}
}

func TestRigBoardOff(t *testing.T) {
	s := New(newFake(), time.Minute)
	if rr := get(t, s, "/helm/rigs/gc-toolkit"); rr.Code != http.StatusServiceUnavailable {
		t.Errorf("without the rig board = %d, want 503", rr.Code)
	}
}
