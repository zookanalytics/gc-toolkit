package reaction

import (
	"fmt"
	"regexp"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
)

// gateMessage is the message of the gate a ruling or a recommend files: the
// headline, then who filed it, naming the run that filed it, which a re-offered
// reaction's check passes over, and on a recommend the formula Accept runs, so
// the gate's brief changes whenever its action does.
func gateMessage(d *Dispose, title string) string {
	run := ""
	if d.Run != "" {
		run = ", run " + d.Run
	}
	reco := ""
	if d.Disposition == Recommend {
		reco = "\nIt recommends " + d.RecommendedFormula + ", the formula Accept runs on " + d.Bead + "."
	}
	return title + "\nFiled by a first reaction on " + d.Bead + " (" + d.Disposition + run + "), which waits on it." + reco +
		"\n\n" + d.Reason +
		"\n\nThe card in " + d.Bead + "'s notes carries the evidence. Clearing this gate makes " + d.Bead + " ready."
}

// oneLine is text with each run of white space made one space, trimmed, as
// lifecycle.Headline makes a headline one line.
func oneLine(text string) string { return strings.Join(strings.Fields(text), " ") }

// asksThis reports whether a gate titled got asks the question of a gate
// titled want: the same title, or human-gate.sh's cut of it, which ends in an
// ellipsis.
func asksThis(got, want string) bool {
	if got == want {
		return true
	}
	cut, ok := strings.CutSuffix(got, "…")
	return ok && cut != "" && strings.HasPrefix(want, cut)
}

// openGates is the open human gates under key that hold bead: each bead a
// blocks edge of bead's names that is a human gate, not closed, filed under
// key.
func (r *Reactions) openGates(bead, key string) ([]*ledger.Record, error) {
	rows, err := r.Ledger.Find(ledger.ByID(bead).WithClosed())
	if err != nil {
		return nil, err
	}
	var far []string
	for _, row := range rows {
		if row.ID != bead {
			continue
		}
		edges, err := row.Edges()
		if err != nil {
			return nil, fmt.Errorf("%s's edges did not decode: %w", bead, err)
		}
		for _, e := range edges {
			if e.Type == ledger.EdgeBlocks {
				far = append(far, e.ID)
			}
		}
	}
	if len(rows) == 0 {
		return nil, fmt.Errorf("the store did not answer for %s", bead)
	}
	if len(far) == 0 {
		return nil, nil
	}
	gates, err := r.Ledger.Find(ledger.ByID(far...).WithClosed())
	if err != nil {
		return nil, err
	}
	var out []*ledger.Record
	for _, g := range gates {
		if prstatus.IsHumanGate(g.IssueType(), g.AwaitType()) && g.Status() != "closed" && g.AwaitID() == key {
			out = append(out, g)
		}
	}
	return out, nil
}

// beadID is the shape of a bead id human-gate.sh prints.
var beadID = regexp.MustCompile(`^[A-Za-z0-9]+-[A-Za-z0-9._-]+$`)

// fileGate puts the subject to the operator as the one open first-reaction
// gate that asks this exit's question. An open first-reaction gate whose brief,
// its title and its description, is not this exit's asks a superseded
// reaction's question, so it is withdrawn first. human-gate.sh files one open
// gate per subject and key, so a re-run finds the gate an earlier run filed
// rather than filing a second. It returns the gate's id.
func (r *Reactions) fileGate(d *Dispose) (string, error) {
	title := oneLine(d.Takeaway)
	message := gateMessage(d, title)
	gates, err := r.openGates(d.Bead, GateKey)
	if err != nil {
		return "", fmt.Errorf("could not read the human gates of %s (%v), so whether a first-reaction gate already asks is unknown; nothing was filed. Clear the cause and re-run this command", d.Bead, err)
	}
	superseded := false
	for _, g := range gates {
		if g.Description() != message || !asksThis(g.Title(), title) {
			superseded = true
		}
	}
	if superseded {
		res := r.Runtime.Script("human-gate.sh", "--retract", "--subject", d.Bead, "--key", GateKey,
			"--message", "superseded by a newer first reaction on "+d.Bead+", which asks: "+title)
		if f := res.Failure(); f != "" {
			return "", fmt.Errorf("could not withdraw the superseded first-reaction gate on %s (human-gate.sh: %s); nothing new was filed. Clear the cause and re-run this command", d.Bead, f)
		}
	}
	res := r.Runtime.Script("human-gate.sh", "--subject", d.Bead, "--key", GateKey, "--message", message)
	if f := res.Failure(); f != "" {
		return "", fmt.Errorf("could not file the human gate on %s (human-gate.sh: %s). Clear the cause and re-run this command", d.Bead, f)
	}
	// human-gate.sh prints the gate's id as its last act, after any note, and
	// the script's output reaches the runtime as one stream in write order.
	gate := res.Tail()
	if !beadID.MatchString(gate) {
		return "", fmt.Errorf("human-gate.sh exited 0 on %s and named no gate (it printed %q), so whether the gate is filed is unknown. Re-run this command: it finds a gate that landed", d.Bead, gate)
	}
	return gate, nil
}
