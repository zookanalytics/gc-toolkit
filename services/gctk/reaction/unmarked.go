package reaction

import (
	"slices"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	prrecord "github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// unmarkedTypes are the issue types the unmarked list takes, an allowlist, so a
// new type is listed only once it is added here. It leaves out the convoy,
// epic, step and molecule types, which are machinery or work in flight, a
// decision, which is a person's choice already, and a spec, which is an output
// and not an input. A graph.v2 pour does not retype its steps, so a workflow
// root and most of its steps are tasks, which the list drops by their keys.
var unmarkedTypes = []string{"task", "bug", "feature", "spike", "chore"}

// topologyKinds are the gc.kind values of a topology root.
var topologyKinds = []string{"workflow", "scope", "spec"}

// reviewKind is the task kind of a review lane on the old review path, a
// dispatched sign-off and so work in flight. The list passes over such a lane
// while such beads exist, and the old path's retirement removes the clause.
const reviewKind = "review"

// workMarkers are the keys that put a bead's work in motion: a review lane's
// check_name and anchor_bead, and an implementation anchor's branch,
// merge_result, work_dir, pr_url and pr_number. An anchor is a task or a bug
// with no task_kind, so its markers alone set it apart from new work.
var workMarkers = []stringKey{prrecord.Branch, prrecord.Result, workDirKey, prrecord.PRURL, prrecord.PRNumber,
	checkNameKey, anchorKey}

// isUnmarked reports whether a ready bead is one the unmarked list takes: open,
// with no mark (marked), no dispatch path and no dispatch hold, no parent, whose
// parent-child edge is its own, and no sign of machinery: a type the allowlist
// leaves out, a topology root, a step, a reaction's own root and step among
// them, a standing record, a feedback pattern, a review lane, or a work marker.
// A wrong row costs the po a line and starts no session, so the machinery
// clauses stay loose.
func isUnmarked(r *ledger.Record) (bool, error) {
	if st := r.Status(); st != "" && st != "open" {
		return false, nil
	}
	if marked(r) || gascity.HasDispatchHold(r.Labels()) || len(dispatchPaths(r)) > 0 {
		return false, nil
	}
	if !slices.Contains(unmarkedTypes, r.IssueType()) || slices.Contains(topologyKinds, raw(kindKey, r)) {
		return false, nil
	}
	for _, k := range []stringKey{stepRefKey, stepIDKey, rootBeadKey} {
		if raw(k, r) != "" {
			return false, nil
		}
	}
	if kind := raw(taskKindKey, r); slices.Contains(standingKinds, kind) || kind == feedbackPattern || kind == reviewKind {
		return false, nil
	}
	for _, k := range workMarkers {
		if raw(k, r) != "" {
			return false, nil
		}
	}
	parents, err := r.Parents()
	if err != nil {
		return false, &ledger.ReadError{ID: r.ID, Reason: "its edges did not decode: " + err.Error()}
	}
	return len(parents) == 0, nil
}

// Unmarked is the open beads of the rig's store that no mark, owner, route,
// arm, hold, wait or run claims, highest priority first: the beads filed with
// no mark, which the po's backlog refinement opens with. The po holds each one
// the operator agrees is new work, and the next sweep takes it. Its one read is
// the sweep's, bd's ready set of unassigned beads that are not epics, so a bead
// a wait holds is not listed. It keeps the beads isUnmarked takes, then drops
// every bead a live run works, by waits' run link. A run map that does not read
// drops nothing, which it says. An error is a ready read that failed, or a
// bead whose edges did not decode, and lists nothing.
func (r *Reactions) Unmarked() ([]*ledger.Record, error) {
	ready, err := r.Ledger.ReadyByPriority(sweepRule)
	if err != nil {
		return nil, err
	}
	var listed []*ledger.Record
	for _, rec := range ready {
		ok, err := isUnmarked(rec)
		if err != nil {
			return nil, err
		}
		if ok {
			listed = append(listed, rec)
		}
	}
	listed, _, err = r.dropInFlight(listed)
	if err != nil {
		r.say("could not read the live runs (%v), so a bead a live workflow drives may be listed", err)
	}
	return listed, nil
}
