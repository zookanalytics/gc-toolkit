package pr

import (
	"fmt"
	"slices"
	"sort"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
)

// approval reads the reviews by the approval rule: each account's latest
// review that approves or requests changes counts, when GitHub says the
// account can push to the repository, the approval GitHub counts toward a
// required review. A later review that only comments leaves it standing, and a
// dismissed review counts for nothing. No account is excluded for being a bot,
// an app or the city's own. It returns the accounts whose approval stands and
// those whose request for changes stands, each sorted.
func approval(reviews []gh.Review) (approvers, requesters []string) {
	latest := map[string]gh.Review{}
	for _, v := range reviews {
		if !v.AuthorCanPush || v.Author == "" || (v.State != "APPROVED" && v.State != "CHANGES_REQUESTED") {
			continue
		}
		cur, seen := latest[v.Author]
		if !seen || v.SubmittedAt > cur.SubmittedAt || (v.SubmittedAt == cur.SubmittedAt && v.ID > cur.ID) {
			latest[v.Author] = v
		}
	}
	for login, v := range latest {
		if v.State == "APPROVED" {
			approvers = append(approvers, login)
		} else {
			requesters = append(requesters, login)
		}
	}
	sort.Strings(approvers)
	sort.Strings(requesters)
	return approvers, requesters
}

// The conclusions a check run's result can pass with, and those that say
// nothing of how the job fared at the head.
var (
	passingConclusions = []string{"SUCCESS", "NEUTRAL"}
	silentConclusions  = []string{"SKIPPED", "CANCELLED"}
)

// checks reads each check run the PR requires, across the check suites at its
// head, by the rule for required checks: each suite holds the check's latest
// result, a re-run's in place of the attempt it re-ran. A skipped or cancelled
// result counts for nothing, since neither says how the job fared at the head.
// The check passes when a result is left and every result left completed as
// success or neutral. A failed result holds the PR. A check with no result left,
// or one still running, holds it until a run reports. A required commit status
// has no check suite and is left to the merge state. No time is compared.
func checks(suites []gh.CheckSuite) []Condition {
	var names []string
	results := map[string][]gh.CheckRun{}
	for _, s := range suites {
		for _, r := range s.Runs {
			if !r.Required {
				continue
			}
			if _, seen := results[r.Name]; !seen {
				names = append(names, r.Name)
			}
			results[r.Name] = append(results[r.Name], r)
		}
	}
	sort.Strings(names)
	var out []Condition
	for _, name := range names {
		var left, failed, running int
		var failure string
		for _, r := range results[name] {
			if slices.Contains(silentConclusions, r.Conclusion) {
				continue
			}
			left++
			switch {
			case r.Status != "COMPLETED":
				running++
			case !slices.Contains(passingConclusions, r.Conclusion):
				failed++
				if failure == "" {
					failure = r.Conclusion
				}
			}
		}
		switch {
		case failed > 0:
			out = append(out, Condition{Kind: KindCheckFailed, Value: name,
				Detail: fmt.Sprintf("required check %s has a result at the head that did not pass (%s)", name, failure)})
		case left == 0:
			out = append(out, Condition{Kind: KindCheckPending, Value: name,
				Detail: fmt.Sprintf("required check %s has only skipped or cancelled results at the head, so it waits for a run", name)})
		case running > 0:
			out = append(out, Condition{Kind: KindCheckPending, Value: name,
				Detail: fmt.Sprintf("required check %s is still running at the head", name)})
		}
	}
	return out
}
