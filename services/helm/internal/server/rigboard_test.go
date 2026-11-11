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

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/rigboard"
)

// rigGC answers the rig board's rig list for one rig.
type rigGC struct{}

func (rigGC) JSON(_ context.Context, out any, args ...string) error {
	if len(args) >= 2 && args[0] == "rig" && args[1] == "list" {
		return json.Unmarshal([]byte(`{"rigs":[{"name":"gc-toolkit","path":"/city/rigs/gc-toolkit"}]}`), out)
	}
	return errors.New("rigGC answers no " + strings.Join(args, " "))
}

// rigReads stands in for the read of a rig's store: a document holding one
// task, or its failure, and the count of reads.
type rigReads struct {
	mu    sync.Mutex
	reads int
	fail  error
}

func (r *rigReads) read(_ context.Context, rig rigboard.Rig) (rigboard.Document, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.fail != nil {
		return rigboard.Document{}, r.fail
	}
	r.reads++
	return rigboard.Document{Rig: rig.Name, Rows: map[string]rigboard.Row{"tk-1": {ID: "tk-1", Signal: "Not scheduled"}}}, nil
}

func newRigServer(reads *rigReads) *Server {
	s := New(newFake(), time.Minute, WithRigBoard(rigGC{}, time.Minute))
	s.rigBoard.read = reads.read
	return s
}

func get(t *testing.T, s *Server, path string) *httptest.ResponseRecorder {
	t.Helper()
	rr := httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, path, nil))
	return rr
}

func TestRigBoardRoutes(t *testing.T) {
	reads := &rigReads{}
	s := newRigServer(reads)

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
	reads := &rigReads{}
	s := newRigServer(reads)
	for range 3 {
		if rr := get(t, s, "/helm/rigs/gc-toolkit"); rr.Code != http.StatusOK {
			t.Fatalf("status %d", rr.Code)
		}
	}
	if reads.reads != 1 {
		t.Fatalf("three reads gathered %d times, want once", reads.reads)
	}
	s.invalidateBoard()
	get(t, s, "/helm/rigs/gc-toolkit")
	if reads.reads != 2 {
		t.Fatalf("a read after a write gathered %d times in all, want twice", reads.reads)
	}
	now := time.Now()
	s.now = func() time.Time { return now.Add(2 * time.Minute) }
	get(t, s, "/helm/rigs/gc-toolkit")
	if reads.reads != 3 {
		t.Fatalf("a read past the time to live gathered %d times in all, want three", reads.reads)
	}
}

// TestRigBoardSaysAFailedRead holds a failed read to an error, never a
// document drawn from nothing.
func TestRigBoardSaysAFailedRead(t *testing.T) {
	s := newRigServer(&rigReads{fail: errors.New("the store did not answer")})
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
