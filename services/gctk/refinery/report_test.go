package refinery

import (
	"context"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	gcfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
)

func (c *city) report(t *testing.T, rt *gcfake.Runtime) Acted {
	t.Helper()
	q := &Queue{City: c, Open: c.open, Now: func() time.Time { return t0 }}
	return (&Report{Look: q, Scripts: rt}).Run(context.Background())
}

// The act reads the queues again and files one human gate on each stuck
// handoff, keyed so a second run while the gate is open files nothing, and it
// records no event, so it does not fire itself.
func TestTheActGatesEachStuckHandoffAndRecordsNoEvent(t *testing.T) {
	c := newCity()
	c.handoff("tk-1", 5*time.Hour)
	c.handoff("tk-2", time.Hour)
	rt := &gcfake.Runtime{}
	out := c.report(t, rt)
	if len(out.Failures) > 0 {
		t.Fatal(out.Failures)
	}
	if len(c.Emitted()) != 0 {
		t.Errorf("the act recorded %v", c.Emitted())
	}
	calls := rt.Scripts()
	if len(calls) != 1 || calls[0].Name != "human-gate.sh" {
		t.Fatalf("calls %+v", calls)
	}
	want := []string{"--subject", "tk-1", "--key", "witness-refinery-queue", "--quiet-window", "86400", "--message"}
	if !reflect.DeepEqual(calls[0].Args[:len(want)], want) {
		t.Errorf("args %q", calls[0].Args)
	}
	message := calls[0].Args[len(want)]
	for _, part := range []string{"The refinery handoff tk-1 has sat assigned to " + ref, "since " + stamp(5*time.Hour), "past the 4 hours a handoff takes"} {
		if !strings.Contains(message, part) {
			t.Errorf("message lacks %q: %s", part, message)
		}
	}
	if len(out.Gated) != 1 || out.Gated[0].Bead != "tk-1" || out.Gated[0].Refinery != ref {
		t.Errorf("gated %+v", out.Gated)
	}
}

// A gate the writer does not file fails the run, and a queue that does not
// read files nothing for it.
func TestTheActFailsForAGateNotFiled(t *testing.T) {
	c := newCity()
	c.handoff("tk-1", 5*time.Hour)
	rt := &gcfake.Runtime{OnScript: func(gcfake.Call) gascity.Result { return gascity.Result{Code: 1, Output: "human-gate: refused"} }}
	out := c.report(t, rt)
	if len(out.Gated) != 0 || len(out.Failures) != 1 || !strings.Contains(out.Failures[0], "human-gate.sh filed no gate on tk-1") {
		t.Errorf("gated %+v, failures %v", out.Gated, out.Failures)
	}
	c.openErr[tools.Store()] = context.DeadlineExceeded
	rt = &gcfake.Runtime{}
	if out := c.report(t, rt); len(out.Failures) != 1 || len(rt.Scripts()) != 0 {
		t.Errorf("failures %v, calls %v", out.Failures, rt.Scripts())
	}
}
