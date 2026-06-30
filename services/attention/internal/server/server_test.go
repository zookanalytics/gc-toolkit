package server

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/attention/internal/board"
	"github.com/zookanalytics/gc-toolkit/services/attention/internal/source"
)

// fakeSource returns canned anchors and counts gather calls so cache behaviour
// is observable.
type fakeSource struct {
	calls  atomic.Int32
	result *source.Result
	err    error
}

func (f *fakeSource) Gather(context.Context) (*source.Result, error) {
	f.calls.Add(1)
	if f.err != nil {
		return nil, f.err
	}
	return f.result, nil
}

func newFake() *fakeSource {
	return &fakeSource{result: &source.Result{
		Anchors: []board.Anchor{
			{ID: "tk-flag", Kind: "flagged", Source: "flagged", Rig: "gc-toolkit", Reason: "boom"},
			{ID: "tk-epic", Kind: "epic", Source: "epic", Rig: "gc-toolkit", Children: []board.Child{{ID: "c", Status: "open"}}},
		},
		Sessions: map[string]board.HostSession{},
	}}
}

func TestHealthz(t *testing.T) {
	s := New(newFake(), time.Minute)
	rr := httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if rr.Code != http.StatusOK {
		t.Fatalf("healthz status = %d, want 200", rr.Code)
	}
}

func TestBoardEndpointRanks(t *testing.T) {
	s := New(newFake(), time.Minute)
	for _, path := range []string{"/attention", "/"} {
		rr := httptest.NewRecorder()
		s.Handler().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, path, nil))
		if rr.Code != http.StatusOK {
			t.Fatalf("%s status = %d, want 200", path, rr.Code)
		}
		var b board.Board
		if err := json.Unmarshal(rr.Body.Bytes(), &b); err != nil {
			t.Fatalf("%s: decode board: %v", path, err)
		}
		if b.Total != 2 || len(b.Tiles) != 2 {
			t.Fatalf("%s: want 2 tiles, got total=%d tiles=%d", path, b.Total, len(b.Tiles))
		}
		// The flagged anchor must rank first (FLAGGED band dominates).
		if b.Tiles[0].ID != "tk-flag" || b.Tiles[0].Severity != board.SevFlagged {
			t.Errorf("%s: top tile = %s/%s, want tk-flag/FLAGGED", path, b.Tiles[0].ID, b.Tiles[0].Severity)
		}
		if b.GeneratedAt.IsZero() {
			t.Errorf("%s: generated_at not stamped", path)
		}
	}
}

func TestUnknownPath404s(t *testing.T) {
	s := New(newFake(), time.Minute)
	rr := httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/nope", nil))
	if rr.Code != http.StatusNotFound {
		t.Errorf("unknown path status = %d, want 404", rr.Code)
	}
}

func TestCacheServesWithinTTL(t *testing.T) {
	f := newFake()
	s := New(f, time.Minute)
	// Pin a clock so the TTL window is deterministic.
	base := time.Date(2026, 6, 30, 12, 0, 0, 0, time.UTC)
	cur := base
	s.now = func() time.Time { return cur }

	if _, err := s.Board(context.Background()); err != nil {
		t.Fatal(err)
	}
	cur = base.Add(30 * time.Second) // still within the 1m TTL
	if _, err := s.Board(context.Background()); err != nil {
		t.Fatal(err)
	}
	if got := f.calls.Load(); got != 1 {
		t.Errorf("within TTL: gather called %d times, want 1 (cache hit)", got)
	}
	cur = base.Add(2 * time.Minute) // past the TTL
	if _, err := s.Board(context.Background()); err != nil {
		t.Fatal(err)
	}
	if got := f.calls.Load(); got != 2 {
		t.Errorf("past TTL: gather called %d times, want 2 (recompute)", got)
	}
}

func TestBoardErrorIs502(t *testing.T) {
	f := &fakeSource{err: context.DeadlineExceeded}
	s := New(f, time.Minute)
	rr := httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/attention", nil))
	if rr.Code != http.StatusBadGateway {
		t.Errorf("gather error status = %d, want 502", rr.Code)
	}
}
