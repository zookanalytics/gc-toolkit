package listing

import (
	"slices"

	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
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
