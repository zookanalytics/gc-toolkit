// Package actions is the GitHub Actions domain: how each workflow stands on a
// rig's default branch, as the runs a push there started record it, and the
// tracker that sends a workflow failing there to be fixed. Its verb, `gctk
// actions track`, reads the branch's newest push runs in one GitHub read and,
// for each workflow whose newest decided run failed, files the failure's
// tracker through the runtime adapter's preexisting-failure.sh, the pack's
// writer of one tracker per failure on a base branch, which sends each tracker
// it files to be fixed. It owns no key on a bead and keeps no state of its own:
// each pass reads GitHub again, and the tracker's writer keeps the one bead per
// failure.
package actions

import (
	"fmt"
	"maps"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

const (
	// Window is how many of the branch's newest push runs a pass reads,
	// finished or not, across every workflow: GitHub's largest page.
	Window = 100
	// Listed is how many of a failed run's failed jobs the tracker lists.
	Listed = 10
	// ReadBound bounds each GitHub read.
	ReadBound = 30 * time.Second
	// Script is the tracker's writer, in the pack's scripts directory.
	Script = "preexisting-failure.sh"
	// said opens each line the writer says of its own, its warn prefix.
	said = "preexisting-failure: "
	// chainMax is the most disposition edges a pass follows from a closed
	// tracker. A real chain is a fold or two long, so a longer one is a fault
	// in the edges.
	chainMax = 20
)

// The states of a workflow on the default branch.
const (
	// Failing is a newest decided run that failed.
	Failing = "failing"
	// Succeeded is a newest decided run that succeeded.
	Succeeded = "succeeded"
	// None is a read that holds no decided run of the workflow.
	None = "none"
)

// What a pass did for a failing workflow.
const (
	// Tracked is a key a live bead already tracks, so the pass filed nothing.
	Tracked = "tracked"
	// HeldBack is a failed run that the key's tracking covered before it last
	// ended, so a later run may already show the failure fixed: the tracker was
	// filed after the run was made, or a newer run of the workflow, made before
	// the tracking ended, has not decided.
	HeldBack = "held back"
	// Filed is a key the writer answered with its tracker: the one it filed,
	// or one another caller filed since the pass looked, as Said tells.
	Filed = "filed"
	// WouldFile is a key a dry run would have the writer file.
	WouldFile = "would file"
)

// failureKey is the key the writer stamps on each tracker it files.
var failureKey = ledger.ReadOnly("failure_key", ledger.String,
	"gctk actions track reads the closed trackers of a workflow's key, and files nothing for a failed run that "+
		"the failure's tracking covered before it ended.")

// City is Gas City as a pass reaches it: its rigs, and the pack's scripts.
type City interface {
	Rigs() ([]gascity.Rig, error)
	Script(name string, args ...string) gascity.Result
}

// GitHub is GitHub as a pass reaches it.
type GitHub interface {
	BranchRuns(repo, branch string, n int) ([]gh.WorkflowRun, error)
	RunJobs(repo string, run int64) ([]gh.Job, error)
}

// Pass reads one rig's workflow runs on its default branch and files the
// tracker of each workflow failing there. Host is the host the GitHub client
// reads, which the rig's origin must be on. Origin and DefaultBranch read a
// checkout: the URL of its remote named origin, and the branch origin's HEAD
// names. Store opens the ledger over the store whose .beads directory is db.
type Pass struct {
	City          City
	GitHub        GitHub
	Store         func(db string) (*ledger.Ledger, error)
	Host          string
	Origin        func(dir string) (string, error)
	DefaultBranch func(dir string) (string, error)
}

// Verdict is how one workflow stands on the branch: its file, the newest run
// that succeeded or failed, which decides, the run of the workflow made next
// after that one, and, when the deciding run failed, the newest success older
// than it. Next and Good are nil when the read holds no such run.
type Verdict struct {
	Path   string
	State  string
	Newest *gh.WorkflowRun
	Next   *gh.WorkflowRun
	Good   *gh.WorkflowRun
}

// failed reports whether a run or a job with conclusion failed: it failed, ran
// out of time or could not start.
func failed(conclusion string) bool {
	return conclusion == "failure" || conclusion == "timed_out" || conclusion == "startup_failure"
}

// Judge reads how each workflow stands from one read of the branch's runs,
// newest first, one Verdict per workflow file the runs name, in the order of
// their paths. A workflow's newest run that failed or succeeded decides. A run
// that ends any other way, such as one cancelled, skipped or neutral, decides
// nothing, and nor does one that has not finished.
func Judge(runs []gh.WorkflowRun) []Verdict {
	byPath := map[string]*Verdict{}
	newer := map[string]*gh.WorkflowRun{}
	for i := range runs {
		r := &runs[i]
		v := byPath[r.Path]
		if v == nil {
			v = &Verdict{Path: r.Path, State: None}
			byPath[r.Path] = v
		}
		switch {
		case v.State == Succeeded || v.Good != nil:
		case v.State == Failing:
			if r.Conclusion == "success" {
				v.Good = r
			}
		case failed(r.Conclusion):
			v.State, v.Newest, v.Next = Failing, r, newer[r.Path]
		case r.Conclusion == "success":
			v.State, v.Newest, v.Next = Succeeded, r, newer[r.Path]
		}
		newer[r.Path] = r
	}
	out := make([]Verdict, 0, len(byPath))
	for _, p := range slices.Sorted(maps.Keys(byPath)) {
		out = append(out, *byPath[p])
	}
	return out
}

// branchRuns are the runs a push to branch in repo itself started. A run of
// another branch, another event, or a commit from another repository, such as
// a fork's pull request from the fork's own branch of that name, is left out.
func branchRuns(runs []gh.WorkflowRun, repo, branch string) []gh.WorkflowRun {
	var out []gh.WorkflowRun
	for _, r := range runs {
		if r.Branch == branch && r.Event == "push" && strings.EqualFold(r.HeadRepo, repo) {
			out = append(out, r)
		}
	}
	return out
}

// Outcome is what one pass read and did: the rig, its repository and default
// branch, how many of the read's runs a push to the branch started and when the
// oldest of the read was made, and each workflow those runs name, in the order
// of their paths. Failure says why the pass did not complete, the rig's own
// reads or each workflow's that did not, and is empty when it did.
type Outcome struct {
	Rig        string     `json:"rig"`
	Repository string     `json:"repository,omitempty"`
	Branch     string     `json:"branch,omitempty"`
	Runs       int        `json:"runs"`
	Since      *time.Time `json:"since,omitempty"`
	Workflows  []Workflow `json:"workflows"`
	Failure    string     `json:"failure,omitempty"`
}

// Workflow is what a pass read and did for one workflow. State is the
// Verdict's and Run its deciding run. For a failing workflow, Key is its
// failure's key, Did what the pass did, Tracker the bead that tracks the key,
// Settled when the key's tracking last ended and the bead whose close ended it,
// for a run held back, Said what the writer said, and Would the writer's
// arguments on a dry run, which calls no writer. Failure says why this
// workflow's pass did not complete, and is empty when it did.
type Workflow struct {
	Path      string     `json:"path"`
	State     string     `json:"state"`
	Run       *Ran       `json:"run,omitempty"`
	Key       string     `json:"key,omitempty"`
	Did       string     `json:"did,omitempty"`
	Tracker   string     `json:"tracker,omitempty"`
	Settled   *time.Time `json:"settled,omitempty"`
	SettledBy string     `json:"settled_by,omitempty"`
	Said      string     `json:"said,omitempty"`
	Would     []string   `json:"would,omitempty"`
	Failure   string     `json:"failure,omitempty"`
}

// Ran is a workflow's deciding run, as an outcome names it.
type Ran struct {
	ID         int64     `json:"id"`
	Number     int       `json:"number"`
	Attempt    int       `json:"attempt"`
	Commit     string    `json:"commit"`
	Conclusion string    `json:"conclusion"`
	Started    time.Time `json:"started"`
	Link       string    `json:"link"`
}

// Run reads rig's default branch and files the tracker of each workflow that
// fails there, writing nothing with dryRun.
func (p *Pass) Run(rig string, dryRun bool) Outcome {
	out := Outcome{Rig: rig, Workflows: []Workflow{}}
	fail := func(format string, a ...any) Outcome {
		out.Failure = fmt.Sprintf(format, a...)
		return out
	}
	rigs, err := p.City.Rigs()
	if err != nil {
		return fail("the city's rigs did not read: %v", err)
	}
	i := slices.IndexFunc(rigs, func(g gascity.Rig) bool { return g.Name == rig })
	if i < 0 {
		return fail("the city names no rig %s", rig)
	}
	dir := rigs[i].Path
	url, err := p.Origin(dir)
	if err != nil {
		return fail("the origin of %s's checkout %s did not read: %v", rig, dir, err)
	}
	host, repo, ok := git.RemoteRepository(url)
	if !ok || !strings.EqualFold(host, p.Host) {
		return fail("the origin of %s's checkout, %s, names no repository on %s", rig, url, p.Host)
	}
	out.Repository = repo
	branch, err := p.DefaultBranch(dir)
	if err != nil {
		return fail("the default branch of %s's checkout %s did not read: %v", rig, dir, err)
	}
	out.Branch = branch
	read, err := p.GitHub.BranchRuns(repo, branch, Window)
	if err != nil {
		return fail("GitHub did not answer for the runs on %s of %s: %v", branch, repo, err)
	}
	if len(read) > 0 {
		out.Since = &read[len(read)-1].Created
	}
	runs := branchRuns(read, repo, branch)
	out.Runs = len(runs)
	t := &tracking{pass: p, repo: repo, branch: branch, store: rigs[i].Store(), dryRun: dryRun}
	var unfinished []string
	for _, v := range Judge(runs) {
		w := Workflow{Path: v.Path, State: v.State}
		if n := v.Newest; n != nil {
			w.Run = &Ran{ID: n.ID, Number: n.Number, Attempt: n.Attempt, Commit: n.Commit, Conclusion: n.Conclusion,
				Started: n.Started, Link: n.URL}
		}
		if v.State == Failing {
			t.track(&w, v)
		}
		if w.Failure != "" {
			unfinished = append(unfinished, w.Path+": "+w.Failure)
		}
		out.Workflows = append(out.Workflows, w)
	}
	out.Failure = strings.Join(unfinished, "; ")
	return out
}

// tracking is one pass's filing of trackers in one rig: the repository and
// branch it read, the rig's store, and the ledger over it once a guard opens
// it.
type tracking struct {
	pass         *Pass
	repo, branch string
	store        string
	dryRun       bool
	ledger       *ledger.Ledger
}

// track files the tracker of one failing workflow, unless a live bead already
// tracks its key, or the key's tracking covered its deciding run before it
// last ended. The failed run's jobs are read only once a tracker is to be
// filed.
func (t *tracking) track(w *Workflow, v Verdict) {
	key, err := t.answer("key", "--target", v.Path)
	if err != nil {
		w.Failure = fmt.Sprintf("%s derived no key for %s: %v", Script, v.Path, err)
		return
	}
	w.Key = key
	id, err := t.answer("find", key)
	if err != nil {
		w.Failure = fmt.Sprintf("%s could not look up the tracker of %s: %v", Script, key, err)
		return
	}
	if id != "" {
		w.Did, w.Tracker = Tracked, id
		return
	}
	end, err := t.settled(key)
	if err != nil {
		w.Failure = fmt.Sprintf("the closed trackers of %s did not read: %v", key, err)
		return
	}
	if end.covered(v) {
		w.Did, w.Settled, w.SettledBy = HeldBack, &end.at, end.by
		return
	}
	jobs, err := t.pass.GitHub.RunJobs(t.repo, v.Newest.ID)
	if err != nil {
		w.Failure = fmt.Sprintf("GitHub did not answer for the jobs of run %d of %s: %v", v.Newest.ID, t.repo, err)
		return
	}
	args := []string{"file", key, "--summary", summary(v, t.branch), "--message", message(t.repo, t.branch, v, jobs)}
	if t.dryRun {
		w.Did, w.Would = WouldFile, args
		return
	}
	res := t.pass.City.Script(Script, args...)
	w.Said = saidOf(res)
	if f := res.Failure(); f != "" {
		w.Failure = fmt.Sprintf("%s did not file the tracker of %s: %s", Script, key, f)
		return
	}
	if id = answerOf(res); id == "" {
		w.Failure = fmt.Sprintf("%s answered no tracker of %s: %s", Script, key, res.Tail())
		return
	}
	w.Did, w.Tracker = Filed, id
}

// answer runs the writer with args and reads its answer: the line it prints on
// standard output, empty when it prints none. A run that does not exit 0 is an
// error.
func (t *tracking) answer(args ...string) (string, error) {
	res := t.pass.City.Script(Script, args...)
	if f := res.Failure(); f != "" {
		return "", fmt.Errorf("%s", f)
	}
	return answerOf(res), nil
}

// answerOf is the writer's answer in a result whose output holds its standard
// output and standard error together: the last line that is not blank, unless
// that line is one the writer says of its own, which opens with its name, or
// one that holds a blank, which no key the pass derives or bead id holds. The
// writer prints its answer after everything else, the lines the sling it runs
// prints among them.
func answerOf(res gascity.Result) string {
	lines := strings.Split(strings.TrimSpace(res.Output), "\n")
	last := strings.TrimSpace(lines[len(lines)-1])
	if strings.HasPrefix(last, said) || strings.ContainsAny(last, " \t") {
		return ""
	}
	return last
}

// saidOf is what the writer said of its own, its lines joined, the name they
// open with dropped.
func saidOf(res gascity.Result) string {
	var lines []string
	for _, l := range strings.Split(res.Output, "\n") {
		if l = strings.TrimSpace(l); strings.HasPrefix(l, said) {
			lines = append(lines, strings.TrimPrefix(l, said))
		}
	}
	return strings.Join(lines, "; ")
}

// ended is how the tracking of a key last ended: when, the bead whose close
// ended it, empty when no closed bead carries the key, and when the key's most
// recently closed tracker was filed.
type ended struct {
	at, filed time.Time
	by        string
}

// covered reports whether the tracking covered the failure of v's deciding run
// before it ended, so the pass files nothing for it. A run that started after
// the tracking ended is not covered. One that started before it is covered when
// the tracker was filed after the run was made, or when the workflow has a
// newer run, made before the tracking ended, that has not decided and may show
// the fix. That leaves the newest run made between the filing and the end, such
// as the run of the commit that landed the fix, which a landing starts before
// it closes the tracker: when it fails, the fix did not end the failure.
func (e ended) covered(v Verdict) bool {
	n := v.Newest
	return e.by != "" && n.Started.Before(e.at) &&
		(n.Created.Before(e.filed) || v.Next != nil && v.Next.Created.Before(e.at))
}

// settled is how the tracking of key last ended: the latest close among the
// key's most recently closed tracker and the closed beads its chain of
// duplicates and supersedes edges reaches, the bead whose close that is, and
// when that tracker was filed. The writer's lookup follows those edges to the
// bead that carries the failure now (tracked_by in
// assets/scripts/preexisting-failure.sh), so a tracker closed as the duplicate
// of the failing test's tracker ends when that tracker's fix closes it. The
// chain stops at a bead that is not closed, at one it reached before, and at
// one the rig's store does not hold, which the writer's lookup reads from the
// store its prefix names, so a fix closed in another rig's store ends no
// tracking. It goes on past a not-needed close, where the writer's lookup
// stops, to the evidence its edge names, so the tracking ends when that
// evidence closed.
func (t *tracking) settled(key string) (end ended, err error) {
	if t.ledger == nil {
		if t.ledger, err = t.pass.Store(t.store); err != nil {
			return end, err
		}
	}
	rows, err := t.ledger.Find(ledger.Matching(failureKey, key).WithClosed().InStatus("closed"))
	if err != nil {
		return end, err
	}
	var last *ledger.Record
	for _, rec := range rows {
		if k, ok, err := failureKey.Get(rec); err != nil || !ok || k != key || rec.Status() != "closed" {
			continue
		}
		closed, err := closedAt(rec)
		if err != nil {
			return end, err
		}
		if last == nil || closed.After(end.at) || closed.Equal(end.at) && rec.ID > last.ID {
			last, end.at = rec, closed
		}
	}
	if last == nil {
		return end, nil
	}
	if end.filed, err = filedAt(last); err != nil {
		return end, err
	}
	end.by = last.ID
	seen := map[string]bool{last.ID: true}
	for rec, hops := last, 0; hops < chainMax; hops++ {
		next, err := successor(rec)
		if err != nil || next == "" || seen[next] {
			return end, err
		}
		seen[next] = true
		rows, err := t.ledger.Find(ledger.ByID(next).WithClosed())
		if err != nil {
			return end, err
		}
		i := slices.IndexFunc(rows, func(r *ledger.Record) bool { return r.ID == next })
		if i < 0 || rows[i].Status() != "closed" {
			return end, nil
		}
		rec = rows[i]
		closed, err := closedAt(rec)
		if err != nil {
			return end, err
		}
		if closed.After(end.at) {
			end.at, end.by = closed, rec.ID
		}
	}
	return end, nil
}

// successor is the bead a closed bead names as its canonical or its successor:
// its first duplicates or supersedes edge, as bead-rehome.sh writes one
// (disposed_to in assets/scripts/bd-lib.sh), empty when it names none.
func successor(rec *ledger.Record) (string, error) {
	edges, err := rec.Edges()
	if err != nil {
		return "", err
	}
	for _, e := range edges {
		if (e.Type == "duplicates" || e.Type == "supersedes") && e.ID != "" {
			return e.ID, nil
		}
	}
	return "", nil
}

// closedAt is when a closed bead closed.
func closedAt(rec *ledger.Record) (time.Time, error) {
	at, err := time.Parse(time.RFC3339, rec.ClosedAt())
	if err != nil {
		return at, fmt.Errorf("%s names no time it closed: %w", rec.ID, err)
	}
	return at, nil
}

// filedAt is when a bead was filed.
func filedAt(rec *ledger.Record) (time.Time, error) {
	at, err := time.Parse(time.RFC3339, rec.CreatedAt())
	if err != nil {
		return at, fmt.Errorf("%s names no time it was filed: %w", rec.ID, err)
	}
	return at, nil
}

// summary is the few words the tracker's title carries after its key.
func summary(v Verdict, branch string) string {
	return strings.NewReplacer("<", "", ">", "").Replace(fmt.Sprintf("%s failed on %s", named(v.Path, v.Newest), branch))
}

// message is the tracker's text: the failed run, its commit, the success
// before it, its failed jobs and steps, the command that prints its log, and
// how its worker finds a tracker the failure already has.
func message(repo, branch string, v Verdict, jobs []gh.Job) string {
	n := v.Newest
	var b strings.Builder
	fmt.Fprintf(&b, "The workflow %s failed on %s of %s in %s at %s: %s\n\n",
		named(v.Path, n), branch, repo, runName(n), stamp(n.Started), n.URL)
	fmt.Fprintf(&b, "A push of commit %s started it", short(n.Commit))
	if h := oneLine(n.Headline); h != "" {
		fmt.Fprintf(&b, ": %s", h)
	}
	b.WriteString("\n\n")
	switch g := v.Good; {
	case g != nil && g.Commit == n.Commit:
		fmt.Fprintf(&b, "Its last success before it was %s at %s, on the same commit, so the code did not change between them.\n\n",
			runName(g), stamp(g.Started))
	case g != nil:
		fmt.Fprintf(&b, "Its last success before it was %s at %s, and the changes between their commits are https://github.com/%s/compare/%s...%s\n\n",
			runName(g), stamp(g.Started), repo, g.Commit, n.Commit)
	default:
		fmt.Fprintf(&b, "None of its runs among the newest %d push runs on %s succeeded before it.\n\n", Window, branch)
	}
	fmt.Fprintf(&b, "What failed in %s:\n", runName(n))
	var red []gh.Job
	for _, j := range jobs {
		if failed(j.Conclusion) {
			red = append(red, j)
		}
	}
	for _, j := range red[:min(len(red), Listed)] {
		fmt.Fprintf(&b, "- the job %s: %s%s", oneLine(j.Name), j.Conclusion, at(j.Steps))
		if j.URL != "" {
			fmt.Fprintf(&b, ", %s", j.URL)
		}
		b.WriteByte('\n')
	}
	switch {
	case len(red) == 0:
		b.WriteString("- GitHub lists no failed job in it\n")
	case len(red) > Listed:
		b.WriteString("- and more failed jobs\n")
	}
	fmt.Fprintf(&b, "\nIts failed steps' log prints with:\n\n    gh run view %d --repo %s --log-failed\n\n", n.ID, repo)
	b.WriteString("The failure may have a tracker of its own already. Find the failing test or target in that log, " +
		"and look its tracker up by the key the tracker's writer derives:\n\n" +
		"    KEY=$(\"$(gc <binding> scripts-dir)/" + Script + "\" key --test \"<the failing test function>\")\n" +
		"    \"$(gc <binding> scripts-dir)/" + Script + "\" find \"$KEY\"\n\n" +
		"A failing file, package or build target takes key --target <path>, and a lint finding key --lint <linter> <path>. " +
		"When find prints a bead, add what this run showed to its notes, and close this bead as its duplicate, " +
		"as your prompt closes a work bead that duplicates another. Later failures of this workflow then find that bead.")
	return b.String()
}

// at names the steps of a failed job that ended in neither a success nor a
// skip, as a job's line closes, and nothing when it has none.
func at(steps []gh.Step) string {
	var names []string
	for _, s := range steps {
		if s.Conclusion != "" && s.Conclusion != "success" && s.Conclusion != "skipped" {
			names = append(names, fmt.Sprintf("%s (%s)", oneLine(s.Name), s.Conclusion))
		}
	}
	switch len(names) {
	case 0:
		return ""
	case 1:
		return ", at the step " + names[0]
	}
	return ", at the steps " + strings.Join(names, ", ")
}

// named is how a tracker names a workflow: its name with its file, or its file
// alone when the workflow names itself after its path, as GitHub names one
// whose file gives it no name.
func named(path string, r *gh.WorkflowRun) string {
	file := path[strings.LastIndex(path, "/")+1:]
	name := oneLine(r.Name)
	if name == "" || name == path || name == file {
		return file
	}
	return name + " (" + file + ")"
}

// runName is a run as a tracker names it: its number, with its attempt when
// GitHub ran it more than once.
func runName(r *gh.WorkflowRun) string {
	if r.Attempt > 1 {
		return fmt.Sprintf("run #%d (attempt %d)", r.Number, r.Attempt)
	}
	return fmt.Sprintf("run #%d", r.Number)
}

// short is a commit's short oid.
func short(commit string) string { return commit[:min(len(commit), 7)] }

// stamp is a time as a tracker names it.
func stamp(t time.Time) string { return t.UTC().Format("2006-01-02 15:04 UTC") }

// oneLine is text on one line, its control characters blanked and its runs of
// space closed up.
func oneLine(s string) string {
	return strings.Join(strings.FieldsFunc(s, func(r rune) bool { return r == ' ' || r < 0x20 || r == 0x7f }), " ")
}
