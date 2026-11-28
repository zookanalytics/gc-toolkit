package listing

import (
	"errors"
	"fmt"
	"slices"

	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/prstatus"
)

// PRAnswers asks the pr domain's evaluator about the PR each bead named owns,
// the question `gctk pr status` asks for a PR on Gas Town's pending record, over
// the listing's own pass ([pr.FromStore]): the bead's side from the rows the
// listing read, and the read the one-PR update saved on the bead. It
// reads no row the pass holds again, and nothing outside the store. It returns
// the answer for each bead it could answer and the error for each it could not,
// since the evaluator gives no answer on part of the facts.
func (ls *Listing) PRAnswers(ids []string) (map[string]pr.Answer, map[string]error) {
	answers, failed := map[string]pr.Answer{}, map[string]error{}
	for _, id := range slices.Compact(slices.Sorted(slices.Values(ids))) {
		a, err := pr.FromStore(ls.pass, id)
		if err != nil {
			failed[id] = err
			continue
		}
		answers[id] = a
	}
	return answers, failed
}

// PRLabels derives the status: and held: labels of the open PR each bead named
// owns, as `gctk pr status` derives them for the labels' writer: from the
// evaluator's answer beside the facts prstatus.Read gathers for a PR on Gas
// Town's pending record, and from those facts alone for any other. It returns
// the labels of each bead it derived, and the error of each it could not,
// since a read that does not answer changes no label.
func (ls *Listing) PRLabels(ids []string) (map[string][]string, map[string]error) {
	labels, failed := map[string][]string{}, map[string]error{}
	ids = slices.Compact(slices.Sorted(slices.Values(ids)))
	facts, err := prstatus.Read(ids, ls)
	if err == nil {
		err = errors.New("prstatus.Read gave no facts for it")
	}
	var pending []string
	for _, id := range ids {
		f, ok := facts[id]
		switch {
		case !ok:
			failed[id] = fmt.Errorf("what the city records about %s's PR did not read: %w", id, err)
		case pr.OnRecord(f.MergeResult):
			pending = append(pending, id)
		default:
			labels[id] = prstatus.Labels(prstatus.Derive(f), prstatus.Held(f))
		}
	}
	answers, unanswered := ls.PRAnswers(pending)
	for _, id := range pending {
		a, ok := answers[id]
		if !ok {
			failed[id] = fmt.Errorf("the evaluator gave no answer for %s's PR: %w", id, unanswered[id])
			continue
		}
		labels[id] = prstatus.Labels(prstatus.Render(a, facts[id]), prstatus.RenderHeld(a, facts[id]))
	}
	return labels, failed
}
