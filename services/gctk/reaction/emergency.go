package reaction

import (
	"fmt"
	"slices"
	"strings"
	"unicode"
)

// The outcomes of an emergency's check of main.
const (
	mainRed     = iota // the named check is failing
	mainNotRed         // it is not failing, or the head carries no such check
	mainUnknown        // the check could not be read, which confirms nothing
)

// checkMain reads whether check, a check run's name or a commit status's
// context, is failing at the head of the default branch of the repository the
// subject's rig checks out. Failing is a check run that concluded failure,
// timed_out or startup_failure, or a commit status of failure or error. A run
// still going, or one cancelled by a newer push, is not failing. Only the named
// check confirms, since another failing there says nothing about this bead, and
// why names any other that fails. A checkout, an origin or a GitHub answer that
// does not read leaves the claim unknown, and unknown confirms nothing.
func (r *Reactions) checkMain(bead, check string) (outcome int, why string) {
	dir := r.rigDir(bead)
	if dir == "" {
		return mainUnknown, fmt.Sprintf("no rig checkout is known for %s, so its repository could not be named", prefixOf(bead))
	}
	url := ""
	if r.Origin != nil {
		url, _ = r.Origin(dir)
	}
	url = strings.TrimSpace(url)
	slug := githubSlug(url)
	if slug == "" {
		shown := url
		if shown == "" {
			shown = "none"
		}
		return mainUnknown, fmt.Sprintf("the origin of %s (%s) is not a GitHub repository", dir, shown)
	}
	if r.GitHub == nil {
		return mainUnknown, "no GitHub is reachable, so main's checks could not be read"
	}
	branch, err := r.GitHub.DefaultBranch(slug)
	if err != nil {
		return mainUnknown, fmt.Sprintf("GitHub did not answer for the default branch of %s (%v)", slug, err)
	}
	checks, err := r.GitHub.HeadChecks(slug, branch)
	if err != nil {
		return mainUnknown, fmt.Sprintf("GitHub did not answer for the checks on %s of %s (%v)", branch, slug, err)
	}
	head := branch + " of " + slug
	if sha := checks.SHA; sha != "" {
		head += " at " + sha[:min(len(sha), 12)]
	}
	type entry struct {
		name, state string
		red         bool
	}
	var all []entry
	for _, run := range checks.Runs {
		c := run.Conclusion
		all = append(all, entry{run.Name, c, c == "failure" || c == "timed_out" || c == "startup_failure"})
	}
	for _, s := range checks.Statuses {
		all = append(all, entry{s.Context, s.State, s.State == "failure" || s.State == "error"})
	}
	present := false
	var named, others []string
	for _, e := range all {
		if e.name == check {
			present = true
		}
		if !e.red {
			continue
		}
		shown := shownCheck(e.name, e.state)
		if e.name == check {
			named = append(named, shown)
		} else {
			others = append(others, shown)
		}
	}
	named, others = uniqueSorted(named), uniqueSorted(others)
	if len(named) > 0 {
		return mainRed, head + " is red: " + strings.Join(named, ", ")
	}
	why = check + " is not failing on " + head
	if !present {
		why = head + " has no check named " + check
	}
	if len(others) > 0 {
		why += "; other checks failing there: " + strings.Join(others, ", ")
	}
	return mainNotRed, why
}

// rigDir is the checkout of the subject's rig: the directory the store the
// caller named sits in, else the path the rig list gives the rig whose prefix
// is the bead's.
func (r *Reactions) rigDir(bead string) string {
	if d, ok := strings.CutSuffix(r.DB, "/.beads"); ok && d != "" {
		return d
	}
	rigs, err := r.Runtime.Rigs()
	if err != nil {
		return ""
	}
	for _, g := range rigs {
		if g.Prefix == prefixOf(bead) {
			return g.Path
		}
	}
	return ""
}

// githubSlug is the owner/name of a github.com remote URL, empty for any other.
func githubSlug(url string) string {
	rest := ""
	for _, p := range []string{"ssh://git@github.com/", "git@github.com:", "https://github.com/"} {
		if s, ok := strings.CutPrefix(url, p); ok {
			rest = s
			break
		}
	}
	rest = strings.TrimRight(strings.TrimSuffix(rest, ".git"), "/")
	owner, name, ok := strings.Cut(rest, "/")
	if !ok || owner == "" || name == "" || strings.Contains(name, "/") {
		return ""
	}
	return rest
}

// shownCheck is a check as a message names it, its control characters blanked.
func shownCheck(name, state string) string {
	return strings.Map(func(r rune) rune {
		if unicode.IsControl(r) {
			return ' '
		}
		return r
	}, name+" ("+state+")")
}

func uniqueSorted(s []string) []string {
	slices.Sort(s)
	return slices.Compact(s)
}
