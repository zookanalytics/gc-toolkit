package refinery

import (
	"context"
	"fmt"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
)

const (
	// GateScript is the writer of the act's human gate, in the pack's scripts
	// directory. It files nothing while a gate under the key blocks the
	// handoff, so a second run for one event changes nothing.
	GateScript = "human-gate.sh"
	// GateKey is the gate's situation key.
	GateKey = "witness-refinery-queue"
	// QuietWindow is how long, in seconds, after a person answers the gate
	// moot: or benign: that the writer files none for the same handoff. Each
	// look that fires the act re-detects one condition that persists, so the
	// next look's event would otherwise undo the person's answer.
	QuietWindow = "86400"
)

// Scripts runs one of the pack's scripts.
type Scripts interface {
	Script(name string, args ...string) gascity.Result
}

// Report is the refinery-queue act, which the refinery-queue-report order runs
// on the look's event. Gas City tells an exec order nothing of the event that
// fired it, so the act reads every queue again through the look's reader and
// acts on what it reads then: for each handoff still stuck, it files a human
// gate on the handoff. An open gate holds the handoff, so the look passes over
// it until a person answers the gate. The act records no event, so it never
// fires itself.
type Report struct {
	Look    *Queue
	Scripts Scripts
}

// Gated is a gate the act's writer took: the handoff and its refinery, with
// what the writer printed.
type Gated struct {
	Rig      string `json:"rig"`
	Bead     string `json:"bead"`
	Refinery string `json:"refinery"`
	Output   string `json:"-"`
}

// Acted is what an act's run did: the record its read composed, nil when a
// read the whole look rests on failed, each gate filed, and each thing that
// failed, any of which makes the run's exit non-zero.
type Acted struct {
	Record   *Record  `json:"record"`
	Gated    []Gated  `json:"gated"`
	Failures []string `json:"-"`
}

// Run reads once and files a gate on each stuck handoff. A filing the run's
// context has ended before is not made, and fails the run.
func (r *Report) Run(ctx context.Context) Acted {
	read := r.Look.Read(ctx)
	out := Acted{Record: read.Record, Gated: []Gated{}, Failures: read.Failures}
	if read.Record == nil {
		return out
	}
	for _, s := range read.Record.Stuck {
		if ctx.Err() != nil {
			out.Failures = append(out.Failures, fmt.Sprintf("no gate was filed on %s: the act was stopped first", s.Bead))
			continue
		}
		res := r.Scripts.Script(GateScript, GateArgs(s)...)
		if f := res.Failure(); f != "" {
			out.Failures = append(out.Failures, fmt.Sprintf("%s filed no gate on %s, so the next look's event files it again: %s", GateScript, s.Bead, f))
			continue
		}
		out.Gated = append(out.Gated, Gated{Rig: s.Rig, Bead: s.Bead, Refinery: s.Refinery, Output: res.Output})
	}
	return out
}

// GateArgs are the writer's arguments for one stuck handoff.
func GateArgs(s Stuck) []string {
	message := fmt.Sprintf("The refinery handoff %s has sat assigned to %s, unprepared and held by nothing, since %s, past the %d hours a handoff takes to turn over. It is not draining on its own, so inspect the bead and the refinery's session.",
		s.Bead, s.Refinery, s.Since.UTC().Format(time.RFC3339), int(Bound/time.Hour))
	return []string{"--subject", s.Bead, "--key", GateKey, "--quiet-window", QuietWindow, "--message", message}
}
