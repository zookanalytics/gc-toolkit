package server

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/rigboard"
)

// twoRigGC answers the rig board's rig list for two rigs.
type twoRigGC struct{}

func (twoRigGC) JSON(_ context.Context, out any, args ...string) error {
	if len(args) >= 2 && args[0] == "rig" && args[1] == "list" {
		return json.Unmarshal([]byte(`{"rigs":[{"name":"one","path":"/city/rigs/one"},{"name":"two","path":"/city/rigs/two"}]}`), out)
	}
	return errors.New("twoRigGC answers no " + strings.Join(args, " "))
}

// StopGathers ends every gather in flight and returns only once each has
// returned, here two reads that take time to return once their context ends,
// as a store read does while its processes are killed and reaped. A request
// waiting on a gather it ended answers that the board is stopping, and a
// gather asked for after it reads nothing.
func TestStopGathersEndsEveryGatherAndWaitsForIt(t *testing.T) {
	s := New(WithRigBoard(twoRigGC{}, time.Minute))
	var reads, returned atomic.Int32
	started := make(chan struct{}, 2)
	s.rigBoard.read = func(ctx context.Context, rig rigboard.Rig) (rigboard.Document, error) {
		reads.Add(1)
		started <- struct{}{}
		<-ctx.Done()
		time.Sleep(100 * time.Millisecond)
		returned.Add(1)
		return rigboard.Document{}, context.Cause(ctx)
	}

	answers := make(chan *httptest.ResponseRecorder, 2)
	for _, rig := range []string{"one", "two"} {
		go func() { answers <- get(t, s, "/helm/rigs/"+rig) }()
	}
	for range 2 {
		select {
		case <-started:
		case <-time.After(5 * time.Second):
			t.Fatal("the two reads did not both start")
		}
	}

	s.StopGathers()
	if n := returned.Load(); n != 2 {
		t.Fatalf("StopGathers returned while %d of the 2 reads in flight had not", 2-n)
	}
	for range 2 {
		if rr := <-answers; rr.Code != http.StatusBadGateway || !strings.Contains(rr.Body.String(), ErrStopping.Error()) {
			t.Errorf("a request whose read the stop ended = %d %s, want a 502 saying the board is stopping", rr.Code, rr.Body.String())
		}
	}

	if rr := get(t, s, "/helm/rigs/one"); rr.Code != http.StatusBadGateway || !strings.Contains(rr.Body.String(), ErrStopping.Error()) {
		t.Errorf("a rig asked for after the stop = %d %s, want a 502 saying the board is stopping", rr.Code, rr.Body.String())
	}
	if n := reads.Load(); n != 2 {
		t.Errorf("the rigs were read %d times, want only the 2 reads the stop ended", n)
	}
}
