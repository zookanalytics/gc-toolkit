// Package deployment is the deployment domain: how a rig's deployments to one
// environment stand, as GitHub records them, and the one patrol finding that
// carries a run of failed ones into the rig's own store. Its verb, `gctk
// deployment report`, reads the environment's newest deployments and files,
// updates or clears that finding through the runtime adapter's
// patrol-finding.sh. It owns no key on a bead and keeps no state of its own:
// each report reads GitHub again, and the finding's writer keeps the finding.
//
// Every deployment of the environment counts. A city turns the report on for
// a rig whose repository deploys the environment from its default branch,
// which is what makes the environment's deployments that branch's.
package deployment

import (
	"cmp"
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
)

const (
	// Environment is the environment a report reads when its caller names
	// none, the name Vercel gives the deployments of a project's production
	// branch.
	Environment = "Production"
	// Window is how many of the environment's newest deployments a report
	// reads: GitHub's largest page, so a run shorter than that shows the
	// success before it.
	Window = 100
	// Listed is how many of a run's failures the finding lists, newest first.
	Listed = 10
	// ReadBound bounds the GitHub read. The finding's writer runs after it,
	// inside the time the order gives the run.
	ReadBound = 30 * time.Second
	// Scope is the finding's scope, named for the verb that files it.
	Scope = "deployment-report"
	// Priority is the finding's priority. A failed deployment keeps its
	// commit's changes, and those of every commit after it, from the
	// environment, so the proactive pool takes its reaction ahead of the
	// default.
	Priority = 1
	// Script is the finding's writer, in the pack's scripts directory.
	Script = "patrol-finding.sh"
)

// The states of an environment's deployments.
const (
	// Failing is a newest finished deployment that failed.
	Failing = "failing"
	// Succeeded is a newest finished deployment that succeeded.
	Succeeded = "succeeded"
	// None is a read that holds no finished deployment.
	None = "none"
)

// City is Gas City as a report reaches it: its rigs, and the pack's scripts.
type City interface {
	Rigs() ([]gascity.Rig, error)
	Script(name string, args ...string) gascity.Result
}

// GitHub is GitHub as a report reaches it.
type GitHub interface {
	Deployments(repo, environment string, n int) ([]gh.Deployment, error)
}

// Report reads one rig's deployments to an environment and keeps the finding
// for a run of failed ones. Host is the host the GitHub client reads, which
// the rig's origin must be on, and Origin reads the URL of the remote named
// origin in a checkout.
type Report struct {
	City   City
	GitHub GitHub
	Host   string
	Origin func(dir string) (string, error)
}

// Verdict is how an environment's deployments stand. Newest is the newest
// finished deployment. When it failed, Failed is the run of failures it
// begins, newest first, Good is the newest success older than the run, nil
// when the read holds none, and Through says the run reaches the oldest
// deployment of a full window, so it may be longer than the read shows.
type Verdict struct {
	State   string
	Newest  *gh.Deployment
	Failed  []gh.Deployment
	Good    *gh.Deployment
	Through bool
}

// Judge reads how the deployments stand from one read of them, newest first,
// a window of n. A FAILURE or an ERROR is a failure and a SUCCESS a success.
// Any other state is unfinished or set aside, such as a deployment still in
// progress, or one GitHub marks INACTIVE, as Vercel does a deployment canceled
// from its dashboard, so it neither ends a run nor extends one.
func Judge(deps []gh.Deployment, n int) Verdict {
	v := Verdict{State: None}
	for i := range deps {
		d := &deps[i]
		switch d.State {
		case "FAILURE", "ERROR":
			if v.Newest == nil {
				v.State, v.Newest = Failing, d
			}
			v.Failed = append(v.Failed, *d)
		case "SUCCESS":
			if v.Newest == nil {
				return Verdict{State: Succeeded, Newest: d}
			}
			v.Good = d
			return v
		}
	}
	v.Through = v.State == Failing && len(deps) >= n
	return v
}

// Outcome is what one report read and did. State is the Verdict's, Failures
// the length of a failing run, and Recorded what the finding's writer said.
// Would is the writer's arguments on a dry run, which calls no writer. Failure
// says why the report did not complete, and is empty when it did.
type Outcome struct {
	Rig         string    `json:"rig"`
	Repository  string    `json:"repository,omitempty"`
	Environment string    `json:"environment"`
	State       string    `json:"state,omitempty"`
	Newest      *Deployed `json:"newest,omitempty"`
	Failures    int       `json:"failures,omitempty"`
	Recorded    string    `json:"recorded,omitempty"`
	Would       []string  `json:"would,omitempty"`
	Failure     string    `json:"failure,omitempty"`
}

// Deployed is the newest finished deployment, as an outcome names it.
type Deployed struct {
	Commit  string    `json:"commit"`
	PR      int       `json:"pr,omitempty"`
	State   string    `json:"state"`
	Created time.Time `json:"created"`
	Link    string    `json:"link"`
}

// Run reports rig's deployments to environment, the default when it is empty.
func (r *Report) Run(rig, environment string, dryRun bool) Outcome {
	environment = cmp.Or(environment, Environment)
	out := Outcome{Rig: rig, Environment: environment}
	fail := func(format string, a ...any) Outcome {
		out.Failure = fmt.Sprintf(format, a...)
		return out
	}
	rigs, err := r.City.Rigs()
	if err != nil {
		return fail("the city's rigs did not read: %v", err)
	}
	i := slices.IndexFunc(rigs, func(g gascity.Rig) bool { return g.Name == rig })
	if i < 0 {
		return fail("the city names no rig %s", rig)
	}
	url, err := r.Origin(rigs[i].Path)
	if err != nil {
		return fail("the origin of %s's checkout %s did not read: %v", rig, rigs[i].Path, err)
	}
	host, repo, ok := git.RemoteRepository(url)
	if !ok || !strings.EqualFold(host, r.Host) {
		return fail("the origin of %s's checkout, %s, names no repository on %s", rig, url, r.Host)
	}
	out.Repository = repo
	deps, err := r.GitHub.Deployments(repo, environment, Window)
	if err != nil {
		return fail("GitHub did not answer for the %s deployments of %s: %v", environment, repo, err)
	}
	v := Judge(deps, Window)
	out.State, out.Failures = v.State, len(v.Failed)
	if v.Newest != nil {
		out.Newest = &Deployed{Commit: v.Newest.Commit, PR: v.Newest.PR, State: v.Newest.State, Created: v.Newest.Created, Link: link(repo, v.Newest)}
	}
	args := findingArgs(rig, repo, environment, v)
	if args == nil {
		out.Recorded = fmt.Sprintf("no finished %s deployment is among the newest %d, so there is nothing to record", environment, Window)
		return out
	}
	if dryRun {
		out.Would = args
		return out
	}
	res := r.City.Script(Script, args...)
	if f := res.Failure(); f != "" {
		return fail("%s did not record the %s deployments of %s: %s", Script, environment, repo, f)
	}
	out.Recorded = res.Said("patrol-finding")
	return out
}

// Key is the finding's key for environment: one finding per environment in a
// rig's store.
func Key(environment string) string {
	var b strings.Builder
	dash := false
	for _, c := range strings.ToLower(environment) {
		switch {
		case c >= 'a' && c <= 'z' || c >= '0' && c <= '9':
			b.WriteRune(c)
			dash = false
		case !dash && b.Len() > 0:
			b.WriteByte('-')
			dash = true
		}
	}
	return "deployment." + strings.TrimSuffix(b.String(), "-")
}

// findingArgs are the finding writer's arguments for how the deployments
// stand: a report of a failing run, a clear on a success, and nil when the read
// holds no finished deployment.
func findingArgs(rig, repo, environment string, v Verdict) []string {
	base := []string{"--key", Key(environment), "--scope", Scope, "--rig", rig}
	switch v.State {
	case Failing:
		return append(base, "--type", "task", "--priority", fmt.Sprint(Priority),
			"--title", title(repo, environment, v), "--message", message(repo, environment, v))
	case Succeeded:
		return append(base, "--cleared", "--message", fmt.Sprintf("The %s deployment of %s succeeded at %s: %s",
			environment, named(v.Newest), stamp(v.Newest.Created), link(repo, v.Newest)))
	}
	return nil
}

// title is the finding's label, which its bead keeps from its first filing.
func title(repo, environment string, v Verdict) string {
	t := fmt.Sprintf("The %s deployment of %s fails at %s", environment, repo, named(v.Newest))
	if h := oneLine(v.Newest.Headline); h != "" {
		t += ": " + h
	}
	return t
}

// message is the finding's text. It is made from what the read holds of the
// run and nothing of when it was read, so a report of a run that has not moved
// repeats it, and the finding counts the report, while a new failure changes
// it. The window a run outgrows moves with every new deployment, so the text
// names nothing that depends on where the window ends. Its first line names
// the newest failure and its link, because the note a changed text leaves on
// the finding keeps only its first 200 characters.
func message(repo, environment string, v Verdict) string {
	n := v.Newest
	first := &v.Failed[len(v.Failed)-1]
	var b strings.Builder
	fmt.Fprintf(&b, "The %s deployment of %s failed at %s: %s\n\n", environment, named(n), stamp(n.Created), link(repo, n))
	if h := oneLine(n.Headline); h != "" {
		fmt.Fprintf(&b, "Its commit is %s: %s\n\n", n.Commit, h)
	}
	switch {
	case v.Good != nil && len(v.Failed) == 1:
		fmt.Fprintf(&b, "The deployment before it, of %s at %s, succeeded, and the changes between them are %s\n\n",
			named(v.Good), stamp(v.Good.Created), compare(repo, v.Good, n))
	case v.Good != nil:
		fmt.Fprintf(&b, "%d deployments in a row have failed, the first of %s at %s. The one before them, of %s at %s, succeeded, and the changes from it to the first failure are %s\n\n",
			len(v.Failed), named(first), stamp(first.Created), named(v.Good), stamp(v.Good.Created), compare(repo, v.Good, first))
	case v.Through:
		fmt.Fprintf(&b, "None of the newest %d %s deployments succeeded, so the failures may have begun before them.\n\n", Window, environment)
	default:
		fmt.Fprintf(&b, "No %s deployment has succeeded. %d have failed, the first of %s at %s.\n\n",
			environment, len(v.Failed), named(first), stamp(first.Created))
	}
	b.WriteString("What GitHub records of the newest failure:\n")
	fmt.Fprintf(&b, "- the deployment's status: %s%s\n", n.State, described(n.Description, n.LogURL))
	for _, s := range n.Failing {
		fmt.Fprintf(&b, "- the commit status %s: %s%s\n", oneLine(s.Context), s.State, described(s.Description, s.TargetURL))
	}
	b.WriteString("\nThe failed deployments, newest first:\n")
	for i := range v.Failed[:min(len(v.Failed), Listed)] {
		f := &v.Failed[i]
		fmt.Fprintf(&b, "- %s at %s", named(f), stamp(f.Created))
		if f.PRURL != "" {
			fmt.Fprintf(&b, ", %s", f.PRURL)
		}
		if h := oneLine(f.Headline); h != "" {
			fmt.Fprintf(&b, ": %s", h)
		}
		b.WriteByte('\n')
	}
	if len(v.Failed) > Listed {
		b.WriteString("- and older failures\n")
	}
	fmt.Fprintf(&b, "\nGitHub carries no build log, so the failing step's error is behind the links above, on the host that ran the deployment. "+
		"This finding notes each later failure, and the next %s deployment that succeeds clears its situation.", environment)
	return b.String()
}

// compare is the GitHub page of the changes from one deployment's commit to
// another's.
func compare(repo string, from, to *gh.Deployment) string {
	return "https://github.com/" + repo + "/compare/" + from.Commit + "..." + to.Commit
}

// named is a deployment's commit as a message names it: its short oid, with
// its pull request when GitHub associates one.
func named(d *gh.Deployment) string {
	s := d.Commit[:min(len(d.Commit), 7)]
	if d.PR > 0 {
		s += fmt.Sprintf(" (#%d)", d.PR)
	}
	return s
}

// link is where a deployment is read: the URL its status gives for its output,
// else the one it gives for what it serves, else its commit on GitHub.
func link(repo string, d *gh.Deployment) string {
	return cmp.Or(d.LogURL, d.EnvironmentURL, "https://github.com/"+repo+"/commit/"+d.Commit)
}

// described is a status's description and link as a list line closes, each
// left out when the status gives none.
func described(description, url string) string {
	s := ""
	if d := oneLine(description); d != "" {
		s += ", " + d
	}
	if url != "" {
		s += ", " + url
	}
	return s
}

// stamp is a time as a message names it.
func stamp(t time.Time) string { return t.UTC().Format("2006-01-02 15:04 UTC") }

// oneLine is text on one line, its control characters blanked and its runs of
// space closed up.
func oneLine(s string) string {
	return strings.Join(strings.FieldsFunc(s, func(r rune) bool { return r == ' ' || r < 0x20 || r == 0x7f }), " ")
}
