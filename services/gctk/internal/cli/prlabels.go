package cli

import (
	"fmt"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/listing"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
)

// prLabels is the PRs' labels as the landing order and the net keep them
// (specs/tk-1tfzr71.149/design.md, section 9): the labels `gctk pr status`
// derives, over a listing of the pass the caller holds, and every label
// prstatus names, which the pr domain writes through GitHub.
type prLabels struct{}

func (prLabels) Derive(pass *ledger.Ledger, beads []string) (map[string][]string, map[string]error) {
	ls, err := listing.Over(pass)
	if err != nil {
		failed := map[string]error{}
		for _, b := range beads {
			failed[b] = fmt.Errorf("the store's listing did not read: %w", err)
		}
		return nil, failed
	}
	return ls.PRLabels(beads)
}

func (prLabels) Kept(name string) bool { return prstatus.IsLabel(name) }

func (prLabels) Defined() []gh.Label {
	var out []gh.Label
	for _, l := range prstatus.Defined() {
		out = append(out, gh.Label{Name: l.Name, Color: l.Color, Description: l.Description})
	}
	return out
}
