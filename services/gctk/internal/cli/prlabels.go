package cli

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/listing"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/prstatus"
)

// prLabels is the PRs' labels as the landing order and the net keep them
// (specs/tk-1tfzr71.149/design.md, section 9): the labels `gctk pr status`
// derives, over a listing of the pass the caller holds, and their one writer,
// pr-status-label.sh, which the runtime adapter runs from the pack's scripts
// directory with the reconcile and clear verbs it has.
type prLabels struct{ rt gascity.Runtime }

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

func (prLabels) Names() []string { return prstatus.LabelNames() }

func (l prLabels) Reconcile(ctx context.Context, bead, host, repo string, number int, current []string) error {
	return l.write(ctx, current, "reconcile", "--anchor", bead, "--pr", strconv.Itoa(number), "--repo", host+"/"+repo)
}

func (l prLabels) Clear(ctx context.Context, host, repo string, number int, current []string) error {
	return l.write(ctx, current, "clear", "--pr", strconv.Itoa(number), "--repo", host+"/"+repo)
}

// write runs the writer with args, stopped once ctx ends, and passes current
// as the labels the PR shows, which the writer reads itself when there are
// none. A run that does not exit 0 is an error carrying why.
func (l prLabels) write(ctx context.Context, current []string, args ...string) error {
	if len(current) > 0 {
		args = append(args, "--current-labels", strings.Join(current, ","))
	}
	res := l.rt.Within(ctx).Script("pr-status-label.sh", args...)
	if f := res.Failure(); f != "" {
		return fmt.Errorf("pr-status-label.sh %s: %s", args[0], f)
	}
	return nil
}
