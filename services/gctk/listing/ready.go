package listing

import (
	"context"
	"errors"
	"fmt"
	"path/filepath"
	"slices"
	"sync"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/feedback"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
)

// readyLimit bounds how many PRs one call to Ready evaluates at once, as
// closedReadLimit bounds the reads of a parent's beads, so one read of a rig
// starts at most that many gh calls at a time. A PR's own reads of GitHub run
// one after another.
const readyLimit = closedReadLimit

// gitHubOn is the GitHub the evaluator reads a PR on host through: gh, each of
// whose calls ends when ctx does, and whose reads take gh's cached answer to a
// read made within maxAge. It is a variable so that the package's tests can
// serve a fake.
var gitHubOn = func(ctx context.Context, host string, maxAge time.Duration) pr.GitHub {
	return gh.NewContext(ctx, host).Cached(maxAge)
}

// feedbackIn is the pack's definition of feedback, loaded in checkout, a rig's
// clone, so that it holds the posts that rig's default branch declares not for
// review. The commands that resolve and load it, and each that applies it, end
// when ctx does, their processes killed with them. It is a variable so that the
// package's tests can set the definition.
var feedbackIn = func(ctx context.Context, checkout string) (pr.Feedback, error) {
	scripts, err := feedback.ScriptsDirContext(ctx)
	if err != nil {
		return nil, err
	}
	rule, err := feedback.LoadContext(ctx, scripts, checkout)
	if err != nil {
		return nil, err
	}
	return rule, nil
}

// Ready asks the pr domain's evaluator ([pr.Ready]) whether the PR each bead
// named owns is ready to merge, the question `gctk pr status` asks for a PR on
// Gas Town's pending record. It returns the answer for each bead it could
// answer and the error for each it could not, since the evaluator gives no
// answer on part of the facts.
//
// The evaluator reads the store through the listing's rows, and GitHub through
// gh on the host each PR's URL names. A read of GitHub takes gh's own cached
// answer to the same read made within maxAge (`gh api --cache`), so a reader
// that asks over and over asks GitHub at most once per maxAge for each read,
// and a maxAge under a second asks GitHub every time. The evaluator applies the
// pack's definition of feedback, loaded once per call in the checkout that
// holds the listing's store, the directory above its .beads, so a listing of
// the store gc resolves answers no bead. Every read of the store and of GitHub,
// and every command that loads or applies the definition, ends when the
// listing's context does, so a call whose context ended returns once it has
// stopped them all. At most readyLimit beads are evaluated at once.
func (ls *Listing) Ready(ids []string, maxAge time.Duration) (map[string]pr.Answer, map[string]error) {
	ids = slices.Compact(slices.Sorted(slices.Values(ids)))
	answers, failed := map[string]pr.Answer{}, map[string]error{}
	if len(ids) == 0 {
		return answers, failed
	}
	rule, err := ls.feedback()
	if err != nil {
		for _, id := range ids {
			failed[id] = err
		}
		return answers, failed
	}
	src := pr.Sources{
		Ledger:   ls.pass,
		GitHub:   func(host string) pr.GitHub { return gitHubOn(ls.ctx, host, maxAge) },
		Feedback: rule,
	}
	var mu sync.Mutex
	var wg sync.WaitGroup
	sem := make(chan struct{}, readyLimit)
	for _, id := range ids {
		wg.Add(1)
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			a, err := pr.Ready(src, id)
			mu.Lock()
			defer mu.Unlock()
			if err != nil {
				failed[id] = err
				return
			}
			answers[id] = a
		}()
	}
	wg.Wait()
	return answers, failed
}

// feedback loads the pack's definition of feedback in the checkout that holds
// the listing's store, within the listing's context.
func (ls *Listing) feedback() (pr.Feedback, error) {
	if ls.db == "" {
		return nil, errors.New("listing: the listing names no store, so no rig's checkout holds the definition of feedback")
	}
	rule, err := feedbackIn(ls.ctx, filepath.Dir(filepath.Clean(ls.db)))
	if err != nil {
		return nil, fmt.Errorf("listing: the definition of feedback did not load: %w", err)
	}
	return rule, nil
}
