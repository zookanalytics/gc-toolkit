package session

import (
	"cmp"
	"context"
	"fmt"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
)

const (
	// FindingScript is the writer of the act's finding, in the pack's scripts
	// directory. While a finding is open under the key and about the claim, it
	// files no second one and counts an occurrence on that one, and it notes
	// the text only when the text changed.
	FindingScript = "patrol-finding.sh"
	// FindingScope is the scope the finding is filed and deduplicated in.
	FindingScope = "witness-findings"
	// FindingKey prefixes the finding's key, which the seat's session id ends.
	FindingKey = "no-progress."
)

// Scripts runs one of the pack's scripts.
type Scripts interface {
	Script(name string, args ...string) gascity.Result
}

// Report is the seat-progress act, which the seat-progress-report order runs on
// the look's event. Gas City tells an exec order nothing of the event that
// fired it, so the act reads every seat again through the look's reader and
// acts on what it reads then: for each seat still stalled, it files the patrol
// finding no-progress.<session> about the claim, in the claim's rig. It
// records no event, so it never fires itself, and it ends no session.
type Report struct {
	Look    *Progress
	Scripts Scripts
}

// Filed is a finding the act's writer took: the seat, its claim and the key,
// with what the writer printed.
type Filed struct {
	Rig     string `json:"rig"`
	Bead    string `json:"bead"`
	Session string `json:"session"`
	Key     string `json:"key"`
	Output  string `json:"-"`
}

// Acted is what an act's run did: the record its read composed, nil when a
// read the whole look rests on failed, each finding filed, and each thing that
// failed, any of which makes the run's exit non-zero.
type Acted struct {
	Record   *Record  `json:"record"`
	Filed    []Filed  `json:"filed"`
	Failures []string `json:"-"`
}

// Run reads once and files a finding for each stalled seat. A filing the run's
// context has ended before is not made, and fails the run.
func (r *Report) Run(ctx context.Context) Acted {
	read := r.Look.Read(ctx)
	out := Acted{Record: read.Record, Filed: []Filed{}, Failures: read.Failures}
	if read.Record == nil {
		return out
	}
	for _, s := range read.Record.Stalled {
		if ctx.Err() != nil {
			out.Failures = append(out.Failures, fmt.Sprintf("no finding was filed for %s holding %s: the act was stopped first", s.Session, s.Bead))
			continue
		}
		res := r.Scripts.Script(FindingScript, FindingArgs(s, read.Record.Read)...)
		if f := res.Failure(); f != "" {
			out.Failures = append(out.Failures, fmt.Sprintf("%s filed nothing for %s holding %s, so the next look's event files it again: %s",
				FindingScript, s.Session, s.Bead, f))
			continue
		}
		out.Filed = append(out.Filed, Filed{Rig: s.Rig, Bead: s.Bead, Session: s.Session, Key: FindingKey + s.Session, Output: res.Output})
	}
	return out
}

// FindingArgs are the writer's arguments for one stalled seat the look read at
// read: the finding goes to the claim's rig, keyed by the seat's session and
// about its claim, and it is filed beside another live finding whose subject
// it shares. The message holds nothing that moves while the seat stays
// stalled, such as the time the look read, because the writer notes each
// change of text on the finding.
func FindingArgs(s Stalled, read time.Time) []string {
	label := cmp.Or(s.Agent, s.Session)
	hours := int(read.Sub(s.Since) / time.Hour)
	title := fmt.Sprintf("%s prints but has written nothing for %d hours, holding %s", label, hours, s.Bead)
	message := fmt.Sprintf("The pool seat %s (%s) holds %s, and its pane printed in the %d seconds before the seat-progress look read it, but %s. Gas City's work ladder takes no step on a pool seat whose pane keeps printing.\n\n"+
		"`gc session peek %s` shows what it prints. Neither the look nor its report ends a session, so restarting the seat is a person's decision. `gc session kill %s` ends its runtime without discarding its work, and a pool seat holding started work restarts in place with its claims.",
		s.Session, label, s.Bead, int(Printing/time.Second), silence(s), s.Session, s.Session)
	return []string{"--rig", s.Rig, "--scope", FindingScope, "--key", FindingKey + s.Session, "--about", s.Bead, "--distinct",
		"--title", title, "--message", message}
}

// silence says since when a stalled seat has printed with nothing written.
func silence(s Stalled) string {
	at := s.Since.UTC().Format(time.RFC3339)
	switch s.From {
	case FromWrite:
		return fmt.Sprintf("its newest write as %s, to the claim's store or the city's, was at %s", s.Identity, at)
	case FromPrompt:
		return fmt.Sprintf("it has written nothing as %s to the claim's store or the city's since a prompt it waited at was answered at %s", s.Identity, at)
	default:
		return fmt.Sprintf("it has written nothing as %s to the claim's store or the city's since it woke at %s", s.Identity, at)
	}
}
