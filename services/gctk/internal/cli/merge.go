package cli

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
)

// `gctk merge` is the port of assets/scripts/merge.sh: arm 2 of the merge
// cadence, THE single writer of merged truth. The CLI is contract-preserving —
// it takes the same two pacing flags (--deadline <epoch-secs>, --cursor
// <file>), emits the same stdout grammar, and exits 0 except when the check
// resolver is missing, the gating anchors cannot be enumerated, or a record
// half failed after a merge (exit 1) — because refinery-reconcile.sh invokes it
// as an opaque command and must not notice which language answers.
//
// Visit order: anchors whose PR has left the open list, or could land this pass
// by everything read without a per-PR call (draft flag, anchor-local holds,
// approval, the merge state the posture arm recorded), are visited first and
// never paced; --deadline and --cursor pace the rest through a rotation
// (pace.go).
//
// The lifecycle transitions it performs are in-process (cli.Lifecycle), the
// same writer the shell reached through lifecycle.sh. Every other seam is a
// subprocess exactly as the script's was — gc/bd/gh/git and the sibling shell
// helpers (escalate.sh, record-failure-cap.sh, lane-state.sh, finalize-gate.sh,
// review-checks.sh, render-seed-audit.sh, stale-gate.sh), resolved from
// GCTK_SCRIPTS_DIR, which gctk-resolve.sh exports as merge.sh's directory before
// it execs this binary. That keeps the stub harness, the observability and the
// permissions surfaces identical. Run any other way, with GCTK_SCRIPTS_DIR
// unset, the pass refuses (exit 1) before it reads a PR.

const mergeProg = "merge"
const mergeGateRef = "refs/gc-toolkit/merge-gate"

// prFields is the pinned read's field set, PR_FIELDS in bd-lib.sh, which the
// script and pr-facts.sh read it from. A re-read asks for the same set, so the
// two answers compare field for field. merge.test.sh pins the exact set for
// both implementations.
const prFields = "state,isDraft,baseRefName,headRefName,headRefOid,headRepository,headRepositoryOwner,isCrossRepository,mergeStateStatus,mergeable,reviewDecision,url"

// The statuses a referencing bead is "in flight" at: open plus every other
// not-closed state a live worker or a wait can hold it at.
const mergeLiveStatuses = "open,in_progress,blocked,deferred,hooked,pinned"

// reviewThreads is GraphQL-only; paginated to exhaustion because a count read
// from a truncated connection decides wrongly.
const threadsQuery = `query($owner:String!,$repo:String!,$num:Int!,$endCursor:String){
  repository(owner:$owner,name:$repo){pullRequest(number:$num){
    reviewThreads(first:100,after:$endCursor){
      pageInfo{hasNextPage endCursor} nodes{isResolved}}}}}`

// The visit order's one read: every open PR's draft flag, head and each
// account's latest review, paginated. It asks for no merge state, because
// GitHub computes that per PR on request, and asked for a hundred PRs at once
// it times out.
const openPRsQuery = `query($owner:String!,$repo:String!,$endCursor:String){
  repository(owner:$owner,name:$repo){
    pullRequests(states:OPEN,first:100,after:$endCursor){
      pageInfo{hasNextPage endCursor}
      nodes{number isDraft headRefOid
        latestOpinionatedReviews(first:100){nodes{state submittedAt databaseId author{login}}}}}}}`

var (
	// url_repo_q: host/owner/repo from a .../pull/<digit> url, case preserved.
	reURLRepoQ = regexp.MustCompile(`^[A-Za-z][A-Za-z0-9+.-]*://([^/]+)/([^/]+/[^/]+)/pull/[0-9]`)
	// repo_q: the same, on an already-lowercased, whitespace-stripped url.
	reRepoQLower = regexp.MustCompile(`^[a-z][a-z0-9+.-]*://([^/]+)/([^/]+/[^/]+)/pull/[0-9]`)
	// the /pull/<number> segment a canonical pr_url is cut at.
	rePullSeg = regexp.MustCompile(`/pull/[0-9]+`)
	// an escalation key, in the charset escalate.sh and finalize-gate.sh accept.
	reEscalationKey = regexp.MustCompile(`^[A-Za-z0-9._-]+$`)
)

// Merge runs the one pass, paced by the --deadline and --cursor in args.
func Merge(args []string, stdout, stderr io.Writer) int {
	deadline, cursor := mergePaceArgs(args)
	scriptsDir := os.Getenv("GCTK_SCRIPTS_DIR")
	if p := helperDirProblem(scriptsDir); p != "" {
		fmt.Fprintf(stderr, "%s: %s; NOTHING is merged this pass\n", mergeProg, p)
		return 1
	}
	// A missing check resolver would make every anchor read as having no lanes,
	// which is merge's fail-open, so its absence holds the pass. The script runs
	// this check before it looks for gh, so a pass without either exits 1 here.
	if p := filepath.Join(scriptsDir, "review-checks.sh"); !isExecutable(p) {
		fmt.Fprintf(stderr, "%s: the check resolver is missing (%s); merge held\n", mergeProg, p)
		return 1
	}
	// A wrong merge cannot be retried away; merging nothing costs one pass. With
	// no gh there is nothing to drive, so exit 0 quietly, as the script does.
	if _, err := exec.LookPath("gh"); err != nil {
		return 0
	}
	m := &merger{
		stdout:     stdout,
		stderr:     stderr,
		client:     gcbd.New(),
		scriptsDir: scriptsDir,
		deadline:   deadline,
		cursor:     cursor,
		rereads:    envCount("MERGE_STATE_REREADS", 3),
		rereadSecs: envCount("MERGE_STATE_REREAD_SECS", 5),
	}
	m.repoRoot = strings.TrimSpace(runOut("git", "rev-parse", "--show-toplevel"))
	if rc, done := m.resolveOrigin(); done {
		return rc
	}
	// Used only to exclude our own reviews; unresolved holds the approval gate.
	m.selfLogin = strings.TrimSpace(string(firstOut(m.ghOrigin("user", "--jq", ".login"))))
	if m.selfLogin == "" {
		// Approval is universal, so with no acting login the city cannot tell an
		// external approver from its own review, and the approval gate holds
		// every PR this pass.
		fmt.Fprintf(stderr, "%s: WARN acting login unresolved; cannot distinguish an external approver from the city's own review, so the universal approval gate holds every PR this pass\n", mergeProg)
	}
	return m.run()
}

// mergePaceArgs reads the pacing flags the way merge.sh's loop does: --deadline
// and --cursor each take the argument after them, and any other argument is
// passed over.
func mergePaceArgs(args []string) (deadline, cursor string) {
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--deadline", "--cursor":
			v := ""
			if i+1 < len(args) {
				v = args[i+1]
			}
			if args[i] == "--deadline" {
				deadline = v
			} else {
				cursor = v
			}
			i++
		}
	}
	return deadline, cursor
}

type merger struct {
	stdout, stderr io.Writer
	client         *gcbd.Client
	originHost     string
	originRepo     string
	originRepoQ    string
	selfLogin      string
	repoRoot       string
	scriptsDir     string
	anchors        []gcbd.Bead
	// deadline and cursor pace the anchors the visit order does not put first.
	deadline string
	cursor   string

	// The UNKNOWN re-read's bounds, MERGE_STATE_REREADS and
	// MERGE_STATE_REREAD_SECS as bd-lib.sh reads them, and the re-reads this
	// pass has spent on UNKNOWN answers.
	rereads      int
	rereadSecs   int
	rereadsSpent int

	// The stale-PR-gate key stale-gate.sh names, read once per pass.
	staleKey     string
	staleKeyRead bool

	merged       int
	recovered    int
	held         int
	skipped      int
	recordFailed int
}

// resolveOrigin mirrors the origin-repo resolution: github only, the slug
// validated to exactly owner/repo. done=true means the caller returns rc.
func (m *merger) resolveOrigin() (rc int, done bool) {
	u := stripSpaces(runOut("git", "remote", "get-url", "origin"))
	var repo string
	switch {
	case strings.HasPrefix(u, "git@github.com:"),
		strings.HasPrefix(u, "https://github.com/"),
		strings.HasPrefix(u, "ssh://git@github.com/"):
		m.originHost = "github.com"
		repo = u
		repo = strings.TrimPrefix(repo, "ssh://git@github.com/")
		repo = strings.TrimPrefix(repo, "git@github.com:")
		repo = strings.TrimPrefix(repo, "https://github.com/")
		repo = strings.TrimSuffix(repo, ".git")
		repo = strings.TrimRight(repo, "/")
	}
	// Exactly owner/repo: reject owner/repo/extra, a leading slash, a trailing
	// slash, and a bare name.
	if n := strings.Count(repo, "/"); n != 1 || strings.HasPrefix(repo, "/") || strings.HasSuffix(repo, "/") {
		repo = ""
	}
	if repo == "" {
		fmt.Fprintf(m.stderr, "%s: cannot resolve this checkout's origin repository; NOTHING is merged this pass\n", mergeProg)
		return 0, true
	}
	m.originRepo = repo
	m.originRepoQ = m.originHost + "/" + m.originRepo
	return 0, false
}

func (m *merger) run() int {
	anchors, ok := m.client.List("--status=open", "--metadata-field", "merge_result=pull_request", "--limit=0", "--json")
	if !ok {
		fmt.Fprintf(m.stderr, "%s: could not enumerate gating anchors; failing loudly rather than merging on a partial view\n", mergeProg)
		return 1
	}
	if len(anchors) == 0 {
		fmt.Fprintf(m.stdout, "%s: no gating anchors\n", mergeProg)
		return 0
	}
	m.anchors = anchors
	first, rest := m.visitOrder(anchors)
	p := newPacer(m.cursor, m.deadline, m.stderr)
	for _, row := range first {
		m.visit(row, nil)
	}
	for _, row := range rest {
		if !m.visit(row, p) {
			break
		}
	}
	p.end()
	if p.resumeAt != "" {
		fmt.Fprintf(m.stdout, "%s: visited %d landing-first and %d of %d other anchors before the deadline; the next pass resumes at %s\n",
			mergeProg, len(first), p.visited, len(rest), p.resumeAt)
	} else {
		fmt.Fprintf(m.stdout, "%s: visited %d landing-first and %d of %d other anchors\n",
			mergeProg, len(first), p.visited, len(rest))
	}
	fmt.Fprintf(m.stdout, "%s: %d merged, %d recovered, %d held, %d skipped, %d record-failed\n",
		mergeProg, m.merged, m.recovered, m.held, m.skipped, m.recordFailed)
	if m.recordFailed != 0 {
		return 1
	}
	return 0
}

// --- visit order: what can land this pass first, the rest in rotation ---------
// This arm's cost grows with the PR set, and the pass that runs it has a budget,
// so a deadline or a kill can stop it part-way. What it must never defer is a
// landing. So every anchor is visited first, and the deadline never stops that
// group, unless something read without a per-PR call already rules its merge
// out this pass:
//   - its PR is a draft, or the acting login is unresolved (the approval gate
//     then holds every PR);
//   - the anchor carries merge_hold, review comments nothing has answered, or
//     no normalized check_set;
//   - the approval rule (reviewVerdict), applied to each account's latest
//     APPROVED or CHANGES_REQUESTED review, finds a veto or no approval;
//   - the merge state pr-facts.sh recorded at the PR's live head, in the
//     posture arm that runs right before this one, is one the merge never
//     proceeds on: anything but CLEAN, UNSTABLE, or UNKNOWN, the state GitHub
//     reports until it has computed one.
// Those anchors are visited in id order after the cursor, wrapping (pace.go),
// until the deadline: a visit there refreshes a verdict and nothing lands. An
// anchor whose PR has left the open list (merged, which owes the record, or
// closed) is visited first. A PR whose state moves after these reads keeps the
// group they gave it until the next pass reads it again. When the open-PR read
// fails, every anchor joins the first group and the pass is not paced at all.

// visitOrder splits the anchors into the group visited first, in enumeration
// order, and the paced rest, in the order the cursor gives them.
func (m *merger) visitOrder(anchors []gcbd.Bead) (first, rest []*gcbd.Bead) {
	open, ok := m.openPRs()
	if !ok {
		fmt.Fprintf(m.stderr, "%s: WARN open-PR list unreadable; every anchor is visited this pass, unpaced\n", mergeProg)
		for i := range anchors {
			first = append(first, &anchors[i])
		}
		return first, nil
	}
	for i := range anchors {
		if m.landsFirst(&anchors[i], open) {
			first = append(first, &anchors[i])
		} else {
			rest = append(rest, &anchors[i])
		}
	}
	return first, paceOrder(rest, m.cursor)
}

// landsFirst reports whether an anchor is visited first: its PR has left the
// open list, or nothing read without a per-PR call rules its merge out.
func (m *merger) landsFirst(a *gcbd.Bead, open map[string]*openPR) bool {
	pr, ok := open[a.Meta("pr_number")]
	if !ok {
		return true
	}
	if m.selfLogin == "" || pr.IsDraft {
		return false
	}
	if isHeld(a.Meta("merge_hold")) || strings.HasPrefix(a.Meta("pr_posture"), "commented@") ||
		stripSpacesCommas(a.Meta("check_set")) == "" {
		return false
	}
	if v := reviewVerdict(pr.reviews(), m.selfLogin); v.veto != "" || v.approver == "" {
		return false
	}
	// pr_merge_state is <state>@<head>, and a state recorded at an older head
	// says nothing about this one.
	if ms := strings.Split(a.Meta("pr_merge_state"), "@"); len(ms) > 1 && ms[1] != "" && ms[1] == pr.HeadRefOid {
		switch ms[0] {
		case "CLEAN", "UNSTABLE", "UNKNOWN":
		default:
			return false
		}
	}
	return true
}

// openPRs reads every open PR, keyed by number. ok=false is a read that failed
// or did not decode whole: `jq -s` slurps the paginated stream or nothing, and
// a page with no pullRequests answers nothing.
func (m *merger) openPRs() (map[string]*openPR, bool) {
	raw, rc := m.gh("api", "graphql", "--hostname", m.originHost, "--paginate",
		"-f", "query="+openPRsQuery,
		"-f", "owner="+originOwner(m.originRepo),
		"-f", "repo="+originName(m.originRepo))
	if rc != 0 {
		return nil, false
	}
	dec := json.NewDecoder(bytes.NewReader(gcbd.Scrub(raw)))
	dec.UseNumber()
	open := map[string]*openPR{}
	pages := 0
	for {
		var page struct {
			Data struct {
				Repository struct {
					PullRequests *struct {
						Nodes []openPR `json:"nodes"`
					} `json:"pullRequests"`
				} `json:"repository"`
			} `json:"data"`
		}
		if err := dec.Decode(&page); err != nil {
			if err == io.EOF {
				break
			}
			return nil, false
		}
		prs := page.Data.Repository.PullRequests
		if prs == nil {
			return nil, false
		}
		pages++
		for i := range prs.Nodes {
			open[prs.Nodes[i].Number.String()] = &prs.Nodes[i]
		}
	}
	return open, pages > 0
}

// visit takes one anchor through the pass. The two tests on the row alone come
// first, so the one visit a walk past its deadline is guaranteed never goes to
// an anchor the pass skips for free. p is nil for an anchor visited first,
// which is never paced. visit reports false when the deadline stopped the walk.
func (m *merger) visit(row *gcbd.Bead, p *pacer) bool {
	if row.ID == "" {
		return true
	}
	if !allDigits(row.Meta("pr_number")) {
		m.skipped++
		return true
	}
	if p != nil && !p.visit(row.ID) {
		return false
	}
	m.handle(row)
	return true
}

// handle is one anchor through the pass, past the free skips. It returns
// nothing; every outcome is a counter bump and a log line, exactly as the
// script's loop body.
func (m *merger) handle(row *gcbd.Bead) {
	id := row.ID
	num := row.Meta("pr_number")

	// --- pinned PR read --------------------------------------------------------
	prRaw := firstOut(m.gh("pr", "view", num, "--repo", m.originRepoQ, "--json", prFields))
	if len(bytes.TrimSpace(prRaw)) == 0 {
		fmt.Fprintf(m.stdout, "%s: PR#%s view failed; merge held (anchor %s, retry next pass)\n", mergeProg, num, id)
		m.held++
		return
	}
	var pr prViewRow
	_ = json.Unmarshal(gcbd.Scrub(prRaw), &pr)
	state := pr.State
	base := pr.BaseRefName
	headRef := pr.HeadRefName
	headOid := pr.HeadRefOid
	mergeState := pr.MergeStateStatus
	liveURL := canonPrURL(pr.URL)
	headRepo := ""
	if o, n := pr.HeadRepositoryOwner.Login, pr.HeadRepository.Name; o != "" && n != "" {
		headRepo = o + "/" + n
	}
	// `if has("isCrossRepository") then tostring else "" end`: a key that is
	// present but null reads "null" and reaches the cross-repo gate, and only an
	// absent key leaves the identity unreadable.
	headCross := jqHasToString(pr.IsCrossRepository)

	// --- identity gates ---------------------------------------------------------
	if urlRepoQ(liveURL) != m.originRepoQ {
		fmt.Fprintf(m.stdout, "%s: PR#%s answered from '%s', not '%s'; merge held (anchor %s)\n", mergeProg, num, urlRepoQ(liveURL), m.originRepoQ, id)
		m.held++
		return
	}
	if headRepo == "" || headCross == "" {
		fmt.Fprintf(m.stdout, "%s: PR#%s head identity unreadable; merge held (anchor %s)\n", mergeProg, num, id)
		m.held++
		return
	}
	if headRepo != m.originRepo || headCross != "false" {
		fmt.Fprintf(m.stdout, "%s: PR#%s is opened from '%s' (cross=%s), not this repository's own branch; merge held (anchor %s)\n", mergeProg, num, headRepo, headCross, id)
		m.held++
		return
	}
	// This arm merges an OPEN non-draft PR and records one already merged; the
	// rest is pr-facts.sh's.
	if state != "MERGED" {
		if state != "OPEN" {
			m.skipped++
			return
		}
		if pr.IsDraft {
			m.skipped++
			return
		}
	}

	// --- live anchor re-read: identity, ahead of either write -------------------
	fresh, ok := m.anchorRow(id)
	if !ok {
		fmt.Fprintf(m.stderr, "%s: anchor %s re-read failed; skip (retry next pass)\n", mergeProg, id)
		m.skipped++
		return
	}
	fstatus := fresh.StatusLower()
	fresult := fresh.Meta("merge_result")
	fpr := fresh.Meta("pr_number")
	if fstatus != "open" || fresult != "pull_request" || fpr != num {
		fmt.Fprintf(m.stderr, "%s: anchor %s changed since enumeration (status='%s' merge_result='%s' pr='%s'); skip\n", mergeProg, id, fstatus, fresult, fpr)
		m.skipped++
		return
	}
	prurl := fresh.Meta("pr_url")
	abranch := fresh.Meta("branch")
	if prurl != "" && canonPrURL(prurl) != liveURL {
		fmt.Fprintf(m.stdout, "%s: anchor %s records pr_url '%s' but PR#%s is '%s'; merge held — operator must repair\n", mergeProg, id, prurl, num, liveURL)
		m.held++
		return
	}
	if abranch != "" && headRef != abranch {
		fmt.Fprintf(m.stdout, "%s: anchor %s records branch '%s' but PR#%s is opened from '%s'; merge held — operator must repair\n", mergeProg, id, abranch, num, headRef)
		m.held++
		return
	}

	// --- a PR already merged: the record, not the merge -------------------------
	if state == "MERGED" {
		mergeOid := m.mergeCommitOid(num)
		if mergeOid == "" {
			fmt.Fprintf(m.stderr, "%s: WARN PR#%s is MERGED but the mergeCommit read came back empty; recording merged_sha=unverified:PR#%s\n", mergeProg, num, num)
			mergeOid = "unverified:PR#" + num
		}
		short := shortSha(mergeOid)
		if m.transition(m.stdout, m.stderr, id, "--to", "merged", "--expect", "pull_request", "--close",
			"--set", "merged_sha="+mergeOid, "--unset", "merge_record_failures",
			"--append-notes", "Merged to "+base+" at "+short+" (record recovered by merge)") {
			m.recovered++
			fmt.Fprintf(m.stdout, "%s: recovered %s — PR#%s was already merged to %s at %s; the record had not landed\n", mergeProg, id, num, base, short)
		} else {
			fmt.Fprintf(m.stderr, "%s: PR#%s is MERGED but the record failed for %s; retry next pass\n", mergeProg, num, id)
			m.recordFailed++
			m.recordCap(id, num, mergeOid, base)
		}
		return
	}

	// --- the rest of the anchor-local authorization set, off the same row -------
	target := fresh.Meta("merged_target")
	hold := fresh.Meta("merge_hold")
	checkset := fresh.Meta("check_set")
	posture := fresh.Meta("pr_posture")
	aroute := fresh.Meta("gc.routed_to")

	// --- validate, in order -------------------------------------------------------
	if stripSpacesCommas(checkset) == "" {
		fmt.Fprintf(m.stdout, "%s: PR#%s anchor %s has no normalized check_set (empty is never the 'none' opt-out); merge held\n", mergeProg, num, id)
		m.held++
		return
	}
	if isHeld(hold) {
		if hold == "signoff_cap" && fresh.Meta("signoff_cap") != "" {
			m.recordMachine(id, "wedged-exception", headOid, aroute)
		}
		fmt.Fprintf(m.stdout, "%s: PR#%s merge_hold set (operator gate); merge held (anchor %s)\n", mergeProg, num, id)
		m.held++
		return
	}
	if strings.HasPrefix(posture, "commented@") {
		fmt.Fprintf(m.stdout, "%s: PR#%s carries review comments nothing has answered (%s); merge held (anchor %s, pr-facts routes them)\n", mergeProg, num, posture, id)
		m.held++
		return
	}
	// One-anchor-per-PR: a second open anchor of this number, keyed by the
	// repository its OWN pr_url names, holds every anchor of the PR. The set is
	// the pass's own enumeration: inside a reconcile pass every repeat of that
	// list is served from the cache the enumeration filled (bd-lib.sh's bd_list
	// refetches an entry only past its 90s max age), so a full-store read per
	// anchor would buy no fresher view.
	if others := duplicateAnchors(m.anchors, id, num, prurl); others != "" {
		fmt.Fprintf(m.stdout, "%s: PR#%s is claimed by more than one open anchor (%s + %s); merge held — close/demote the duplicate (doctor check-one-anchor-per-pr owns the structure)\n", mergeProg, num, id, others)
		m.escalate("--subject", id, "--key", "one-anchor-per-pr."+num,
			"--message", "PR#"+num+" ("+liveURL+") is claimed by multiple open anchors ("+id+", "+others+"); every anchor of this PR is held until exactly one remains.")
		m.held++
		return
	}
	if target != "" && base != "" && target != base {
		fmt.Fprintf(m.stdout, "%s: PR#%s base '%s' != merged_target '%s' (retargeted); merge held (anchor %s, pr-facts escalates)\n", mergeProg, num, base, target, id)
		m.held++
		return
	}
	ng, laneOK := m.firstNotgreenLane(id, checkset)
	if !laneOK {
		fmt.Fprintf(m.stdout, "%s: PR#%s lane state unreadable on anchor %s; merge held\n", mergeProg, num, id)
		m.held++
		return
	}
	if ng != "" {
		m.recordMachine(id, "progressing", headOid, aroute)
		fmt.Fprintf(m.stdout, "%s: PR#%s lane '%s' does not derive green; merge held (anchor %s)\n", mergeProg, num, ng, id)
		m.held++
		return
	}

	// --- unclosed rework/review children: metadata keys AND dependency edges ------
	byPR, byOK := m.client.List("--metadata-field", "pr_number="+num, "--status="+mergeLiveStatuses, "--limit=0", "--json")
	if !byOK {
		fmt.Fprintf(m.stdout, "%s: PR#%s referencing-bead read failed; merge held (anchor %s)\n", mergeProg, num, id)
		m.held++
		return
	}
	children, cOK := m.client.DepList(id, "--direction=up", "-t", "parent-child", "--json")
	blockers, bOK := m.client.DepList(id, "--direction=down", "-t", "blocks", "--json")
	if !cOK || !bOK {
		fmt.Fprintf(m.stdout, "%s: PR#%s dependency probe unreadable; merge held (anchor %s)\n", mergeProg, num, id)
		m.held++
		return
	}
	if inflight := m.inflightHolder(id, byPR, children, blockers); inflight != "" {
		if ph := poolHolder(blockers); ph != "" {
			m.recordMachine(id, "progressing", headOid, aroute)
		} else if sh := stuckHolder(blockers); sh != "" {
			m.recordBlocked(id, headOid, aroute, "held by "+inflight+" — an unrouted blocker no automated actor will clear")
		}
		fmt.Fprintf(m.stdout, "%s: PR#%s held by %s; merge held (anchor %s)\n", mergeProg, num, inflight, id)
		m.held++
		return
	}

	// --- open visit on this anchor: a person owes a conversation before finalize ---
	if reason, ok := m.finalizeGate(id); !ok {
		if reason == "" {
			reason = "finalize gate refused (fail-closed)"
		}
		fmt.Fprintf(m.stdout, "%s: PR#%s %s; merge held (anchor %s)\n", mergeProg, num, reason, id)
		m.held++
		return
	}

	// --- approval ------------------------------------------------------------------
	reviewsRaw, rrc := m.ghOrigin("--paginate", "repos/"+m.originRepo+"/pulls/"+num+"/reviews?per_page=100", "--jq", ".[]")
	if rrc != 0 {
		fmt.Fprintf(m.stdout, "%s: PR#%s reviews history read failed; merge held (anchor %s)\n", mergeProg, num, id)
		m.held++
		return
	}
	rs, rok := reviewState(reviewsRaw, m.selfLogin)
	if !rok {
		fmt.Fprintf(m.stdout, "%s: PR#%s reviews history unreadable; merge held (anchor %s)\n", mergeProg, num, id)
		m.held++
		return
	}
	if rs.veto != "" {
		m.recordMachine(id, "settled", headOid, aroute)
		fmt.Fprintf(m.stdout, "%s: PR#%s reviewer '%s' has a standing CHANGES_REQUESTED and the cadence has run dry; merge held for re-review (anchor %s)\n", mergeProg, num, rs.veto, id)
		m.held++
		return
	}
	// Approval is a universal merge rule: every PR needs a standing APPROVED
	// review from an account other than the city's. No check_set token arms it
	// and none opts out.
	if m.selfLogin == "" {
		fmt.Fprintf(m.stdout, "%s: PR#%s approval required but the acting login is unresolved; merge held (anchor %s)\n", mergeProg, num, id)
		m.held++
		return
	}
	if rs.approver == "" {
		m.recordMachine(id, "settled", headOid, aroute)
		fmt.Fprintf(m.stdout, "%s: PR#%s no external APPROVED review stands (approval is a universal merge rule); merge held (anchor %s)\n", mergeProg, num, id)
		m.held++
		return
	}

	// --- UNKNOWN: GitHub has not computed this PR against its current base -------
	// A merge this arm makes moves the base under every later candidate on that
	// base, so their pinned reads answer UNKNOWN. The pinned read started the
	// computation, so read it again before deciding, within the pass's re-read
	// budget. Every read here comes after the latest merge this pass made, because
	// merges happen only at the end of an anchor's turn. A computed answer is
	// judged below like any pinned one, so BEHIND and DIRTY keep their own
	// handling. Every pinned field outside the mergeability facts was validated
	// above, so a re-read that changes one is a different PR from the one those
	// gates passed. A re-read that fails is held like a failed pinned read and
	// records nothing.
	unknownNote := ""
	if mergeState == "UNKNOWN" && m.rereads > 0 {
		outcome, reads, again, state, changed := m.prViewSettled(num, prRaw)
		switch outcome {
		case settledComputed:
			var re prViewRow
			_ = json.Unmarshal(gcbd.Scrub(again), &re)
			pr = re
			mergeState = state
			fmt.Fprintf(m.stdout, "%s: PR#%s answered UNKNOWN on the pinned read and %s on re-read %d (anchor %s)\n", mergeProg, num, mergeState, reads, id)
		case settledChanged:
			fmt.Fprintf(m.stdout, "%s: PR#%s changed between the pinned read and re-read %d of its UNKNOWN merge state (%s); merge held (anchor %s)\n", mergeProg, num, reads, changed, id)
			m.held++
			return
		case settledFailed:
			fmt.Fprintf(m.stdout, "%s: PR#%s view failed on re-read %d of its UNKNOWN merge state; merge held (anchor %s, retry next pass)\n", mergeProg, num, reads, id)
			m.held++
			return
		default:
			if reads > 0 {
				unknownNote = fmt.Sprintf(" after %d re-read(s); the pass's re-read budget is spent", reads)
			} else {
				unknownNote = "; not re-read, the pass's re-read budget is spent"
			}
		}
	}

	// --- mergeStateStatus: CLEAN, or UNSTABLE decided on required contexts only ----
	switch mergeState {
	case "CLEAN":
		// proceed
	case "UNSTABLE":
		st, reqContexts := m.requiredContextsFor(base)
		if st != "known" {
			fmt.Fprintf(m.stdout, "%s: PR#%s is UNSTABLE and the required-check set for '%s' is unreadable; merge held (anchor %s)\n", mergeProg, num, base, id)
			m.held++
			return
		}
		if len(reqContexts) > 0 {
			rollupRaw := firstOut(m.gh("pr", "view", num, "--repo", m.originRepoQ, "--json", "statusCheckRollup"))
			if len(bytes.TrimSpace(rollupRaw)) == 0 {
				fmt.Fprintf(m.stdout, "%s: PR#%s is UNSTABLE and the check rollup is unreadable; merge held (anchor %s)\n", mergeProg, num, id)
				m.held++
				return
			}
			notgreen, rollOK := notGreenRequired(rollupRaw, reqContexts)
			if !rollOK {
				fmt.Fprintf(m.stdout, "%s: PR#%s is UNSTABLE and the check rollup is unreadable; merge held (anchor %s)\n", mergeProg, num, id)
				m.held++
				return
			}
			if notgreen != "" {
				fmt.Fprintf(m.stdout, "%s: PR#%s is UNSTABLE and a REQUIRED check is not green at %s: %s; merge held (anchor %s)\n", mergeProg, num, headOid, notgreen, id)
				m.held++
				return
			}
		}
		fmt.Fprintf(m.stdout, "%s: PR#%s is UNSTABLE but no required check on '%s' is red (the rest are advisory); proceeding (anchor %s)\n", mergeProg, num, base, id)
	case "BLOCKED":
		m.handleBlocked(id, num, base, headOid, aroute, pr.ReviewDecision)
		m.held++
		return
	default:
		if mergeState == "BEHIND" {
			m.recordBlocked(id, headOid, aroute, "the base branch '"+base+"' moved ahead; bring '"+headRef+"' current with '"+base+"' before it can merge")
		} else if mergeState == "DIRTY" {
			m.recordBlocked(id, headOid, aroute, "the branch conflicts with '"+base+"' and no merge-in rework is in flight; bring '"+headRef+"' current with '"+base+"' before it can merge")
		} else {
			m.recordMachine(id, "settled", headOid, aroute)
		}
		msState := mergeState
		if msState == "" {
			msState = "unknown"
		}
		fmt.Fprintf(m.stdout, "%s: PR#%s not mergeable yet (mergeStateStatus='%s'%s); merge held (anchor %s)\n", mergeProg, num, msState, unknownNote, id)
		m.held++
		return
	}
	if headOid == "" {
		fmt.Fprintf(m.stdout, "%s: PR#%s live head unresolved; cannot head-match the merge; merge held (anchor %s)\n", mergeProg, num, id)
		m.held++
		return
	}

	// --- generated-artifact freshness AT THE MERGE RESULT --------------------------
	renderer := m.scriptPath("render-seed-audit.sh")
	if m.repoRoot != "" && fileExists(filepath.Join(m.repoRoot, "pack.toml")) &&
		fileExists(filepath.Join(m.repoRoot, "generated/seed-audit/INDEX.md")) && fileExists(renderer) {
		if rc := runRC("git", "fetch", "--quiet", "--no-tags", "origin",
			"+refs/heads/"+base+":"+mergeGateRef+"/base", "+refs/heads/"+headRef+":"+mergeGateRef+"/head"); rc != 0 {
			fmt.Fprintf(m.stdout, "%s: PR#%s could not fetch '%s' and '%s' to check what the merge would land; merge held (anchor %s)\n", mergeProg, num, base, headRef, id)
			m.held++
			return
		}
		fetchedHead := strings.TrimSpace(runOut("git", "rev-parse", "--verify", "--quiet", mergeGateRef+"/head"))
		if fetchedHead != headOid {
			shown := fetchedHead
			if shown == "" {
				shown = "none"
			}
			fmt.Fprintf(m.stdout, "%s: PR#%s head moved during the freshness probe (fetched '%s', validated '%s'); merge held (anchor %s)\n", mergeProg, num, shown, headOid, id)
			m.held++
			return
		}
		saOut, saRC := runCombined("bash", renderer, "--root", m.repoRoot, "--check-merge", mergeGateRef+"/base", mergeGateRef+"/head")
		if saRC != 0 {
			saWhy := "generated-artifact freshness could not be determined"
			if saRC == 1 {
				saWhy = "would land a stale generated/seed-audit"
			}
			fmt.Fprintf(m.stdout, "%s: PR#%s %s; merge held (anchor %s)\n", mergeProg, num, saWhy, id)
			m.printIndented(saOut, 6)
			m.escalate("--subject", id, "--key", "seed-audit-merge-gate."+num,
				"--message", "PR#"+num+" "+saWhy+"; the merge is held.\n\ngenerated/seed-audit is rendered from the whole source tree and committed per\nbranch, so a branch carrying a render made at an older base lands over prompt\ninputs it never saw. Bring the head branch current with '"+base+"', run\nassets/scripts/render-seed-audit.sh, commit generated/seed-audit, and push.\n\n"+saOut)
			m.held++
			return
		}
	}

	// --- terminal re-read: the FULL anchor-local authorization set ----------------
	final, ok := m.anchorRow(id)
	if !ok {
		fmt.Fprintf(m.stdout, "%s: PR#%s anchor %s unreadable immediately before the merge; merge held\n", mergeProg, num, id)
		m.held++
		return
	}
	freason := terminalReason(final, num, base, liveURL, headRef)
	if freason == "OK" {
		fcs := final.Meta("check_set")
		if rg, ok := m.firstNotgreenLane(id, fcs); !ok {
			freason = "lane state unreadable before the merge"
		} else if rg != "" {
			freason = "lane " + rg + " is no longer green"
		}
	}
	if freason == "OK" {
		if reason, ok := m.finalizeGate(id); !ok {
			if reason != "" {
				freason = reason
			} else {
				freason = "open visit or unreadable visit probe (fail-closed)"
			}
		}
	}
	if freason != "OK" {
		fmt.Fprintf(m.stdout, "%s: PR#%s anchor %s changed between validation and the merge — %s; merge held\n", mergeProg, num, id, freason)
		m.held++
		return
	}

	// --- merge, then record via ONE lifecycle transition ---------------------------
	merr, mrc := runCombined("gh", "pr", "merge", num, "--repo", m.originRepoQ, "--squash", "--match-head-commit", headOid)
	if mrc != 0 {
		fmt.Fprintf(m.stderr, "%s: PR#%s merge attempt failed (rc=%d): %s; merge held (anchor %s)\n", mergeProg, num, mrc, merr, id)
		m.held++
		return
	}
	mergeOid := m.mergeCommitOid(num)
	if mergeOid == "" {
		fmt.Fprintf(m.stderr, "%s: WARN PR#%s merged but the mergeCommit read came back empty; recording merged_sha=unverified:PR#%s\n", mergeProg, num, num)
		mergeOid = "unverified:PR#" + num
	}
	short := shortSha(mergeOid)
	landTarget := target
	if landTarget == "" {
		landTarget = base
	}
	noteShort := short
	if noteShort == "" {
		noteShort = "merge"
	}
	if m.transition(m.stdout, m.stderr, id, "--to", "merged", "--expect", "pull_request", "--close",
		"--set", "merged_sha="+mergeOid, "--unset", "merge_record_failures",
		"--append-notes", "Merged to "+landTarget+" at "+noteShort) {
		m.merged++
		echoShort := short
		if echoShort == "" {
			echoShort = "?"
		}
		fmt.Fprintf(m.stdout, "%s: merged + recorded %s — PR#%s squashed to %s at %s\n", mergeProg, id, num, landTarget, echoShort)
	} else {
		fmt.Fprintf(m.stderr, "%s: PR#%s MERGED but the lifecycle record FAILED for %s; pr-facts records it next pass\n", mergeProg, num, id)
		m.recordFailed++
		m.recordCap(id, num, mergeOid, landTarget)
	}
}

// handleBlocked records the machine verdict for a BLOCKED PR and names the cause
// off the branch's own rules.
func (m *merger) handleBlocked(id, num, base, headOid, aroute, reviewDecision string) {
	st, threadReq, approvals := m.reviewGatesFor(base)
	rdShown := reviewDecision
	if rdShown == "" {
		rdShown = "empty"
	}
	if st != "known" {
		m.recordBlocked(id, headOid, aroute, "BLOCKED by branch protection; the rules for '"+base+"' could not be read to name the cause")
		fmt.Fprintf(m.stdout, "%s: PR#%s is BLOCKED by branch protection but the rules for '%s' could not be read to name the cause (reviewDecision='%s'); merge held (anchor %s)\n", mergeProg, num, base, rdShown, id)
		return
	}
	bcause := ""
	bu := 0
	if threadReq {
		if n, ok := m.unresolvedThreads(num); ok {
			bu = n
			if bu > 0 {
				bcause = "threads"
			}
		} else {
			bu = 0
			bcause = "threads-unreadable"
		}
	}
	if bcause == "" {
		if approvals >= 1 && reviewDecision != "APPROVED" {
			bcause = "approval"
		} else {
			bcause = "other"
		}
	}
	switch bcause {
	case "threads":
		m.recordBlocked(id, headOid, aroute, strconv.Itoa(bu)+" unresolved review thread(s) must be resolved before this PR can merge")
		fmt.Fprintf(m.stdout, "%s: PR#%s is BLOCKED by branch protection: %d unresolved review thread(s) hold required_review_thread_resolution (reviewDecision='%s'); merge held (anchor %s)\n", mergeProg, num, bu, rdShown, id)
	case "threads-unreadable":
		m.recordBlocked(id, headOid, aroute, "a required review thread's resolution state could not be read")
		fmt.Fprintf(m.stdout, "%s: PR#%s is BLOCKED by branch protection: review-thread resolution is required but its reviewThreads could not be read to count them (reviewDecision='%s'); merge held (anchor %s)\n", mergeProg, num, rdShown, id)
	case "approval":
		m.recordMachine(id, "settled", headOid, aroute)
		fmt.Fprintf(m.stdout, "%s: PR#%s is BLOCKED by branch protection: waiting on an approving review (%d required, reviewDecision='%s'); merge held (anchor %s)\n", mergeProg, num, approvals, rdShown, id)
	case "other":
		m.recordBlocked(id, headOid, aroute, "branch protection holds it by a rule other than an unresolved required thread or a missing approval")
		fmt.Fprintf(m.stdout, "%s: PR#%s is BLOCKED by branch protection by a rule other than an unresolved required thread or a missing approval (thread-resolution required=%s, approvals required=%d, reviewDecision='%s'); merge held (anchor %s)\n", mergeProg, num, strconv.FormatBool(threadReq), approvals, rdShown, id)
	}
}

// --- lifecycle transitions (in-process) -----------------------------------------

func (m *merger) transition(out, errw io.Writer, id string, args ...string) bool {
	full := append([]string{"transition", id}, args...)
	return Lifecycle(full, out, errw) == 0
}

func (m *merger) recordMachine(id, value, headOid, route string) {
	if headOid == "" {
		return
	}
	if !m.transition(io.Discard, io.Discard, id, "--to", "pull_request", "--expect", "pull_request",
		"--route", route, "--set-dated", "pr.machine="+value+"@"+headOid, "--unset", "pr.machine_reason") {
		fmt.Fprintf(m.stderr, "%s: WARN %s machine axis '%s@%s' did not record; the board reads it as unknown until the next pass\n", mergeProg, id, value, headOid)
	}
}

func (m *merger) recordBlocked(id, headOid, route, reason string) {
	if headOid == "" {
		return
	}
	if !m.transition(io.Discard, io.Discard, id, "--to", "pull_request", "--expect", "pull_request",
		"--route", route, "--set-dated", "pr.machine=blocked@"+headOid, "--set", "pr.machine_reason="+reason) {
		fmt.Fprintf(m.stderr, "%s: WARN %s machine axis 'blocked@%s' did not record; the board reads it as unknown until the next pass\n", mergeProg, id, headOid)
	}
}

// --- subprocess seams -----------------------------------------------------------

func (m *merger) gh(args ...string) ([]byte, int) {
	return capture("gh", args...)
}

func (m *merger) ghOrigin(args ...string) ([]byte, int) {
	full := append([]string{"api", "--hostname", m.originHost}, args...)
	return capture("gh", full...)
}

// anchorRow reads the anchor's live row; ok=false on an unreadable bead or one
// whose metadata is null — never an all-default row. Both re-reads decide the
// merge off this row, so it takes the authoritative `gc bd show` path that
// merge.sh's anchor_row reads, never the supervisor API: the daemon's cache can
// lag a fresh write, and a merge_hold, an unanswered-comment posture or a
// retarget written just before the pass would read as absent.
func (m *merger) anchorRow(id string) (*gcbd.Bead, bool) {
	b := m.client.ShowDirect(id)
	if b == nil || b.Metadata == nil {
		return nil, false
	}
	return b, true
}

func (m *merger) mergeCommitOid(num string) string {
	raw := firstOut(m.gh("pr", "view", num, "--repo", m.originRepoQ, "--json", "mergeCommit"))
	var v struct {
		MergeCommit struct {
			Oid string `json:"oid"`
		} `json:"mergeCommit"`
	}
	_ = json.Unmarshal(gcbd.Scrub(raw), &v)
	return v.MergeCommit.Oid
}

// settledOutcome is how prViewSettled ended: gh_pr_view_settled's return code
// in bd-lib.sh.
type settledOutcome int

const (
	settledComputed settledOutcome = iota // a re-read answered a computed state
	settledUnknown                        // still UNKNOWN, and the pass's re-reads are spent
	settledChanged                        // a re-read changed a field outside the mergeability facts
	settledFailed                         // a re-read failed
)

// prViewSettled is bd-lib.sh's gh_pr_view_settled. It reads again a PR whose
// pinned read, pinnedRaw asked with --json prFields, answered an UNKNOWN merge
// state. A re-read that answers a computed state decides the PR and spends
// nothing. One that answers UNKNOWN again spends one of the pass's m.rereads,
// and once they are spent no PR is re-read for the rest of the pass. A PR's
// first re-read goes out at once, because its pinned read already started the
// computation, and each later one waits m.rereadSecs. The wait is a `sleep`
// subprocess, as the script's is, so the suite's stub sleep records the
// schedule.
//
// reads is the number of re-reads made. On settledComputed, raw is that answer
// and state its mergeStateStatus. On settledChanged, changed names each field
// outside the mergeability facts that differs, with its pinned and re-read
// values. A re-read that fails, or answers something other than a JSON object,
// says nothing about the merge state, so it spends nothing.
func (m *merger) prViewSettled(num string, pinnedRaw []byte) (outcome settledOutcome, reads int, raw []byte, state, changed string) {
	var pinned map[string]json.RawMessage
	pinnedErr := json.Unmarshal(gcbd.Scrub(pinnedRaw), &pinned)
	for m.rereadsSpent < m.rereads {
		if reads > 0 {
			runRC("sleep", strconv.Itoa(m.rereadSecs))
		}
		reads++
		out, rc := m.gh("pr", "view", num, "--repo", m.originRepoQ, "--json", prFields)
		if rc != 0 || len(bytes.TrimSpace(out)) == 0 {
			return settledFailed, reads, nil, "", ""
		}
		var again map[string]json.RawMessage
		if pinnedErr != nil || pinned == nil || json.Unmarshal(gcbd.Scrub(out), &again) != nil || again == nil {
			return settledFailed, reads, nil, "", ""
		}
		if c := changedFields(pinned, again); c != "" {
			return settledChanged, reads, nil, "", c
		}
		if ms := jqAltString(again["mergeStateStatus"]); ms != "" && ms != "UNKNOWN" {
			return settledComputed, reads, out, ms, ""
		}
		m.rereadsSpent++
	}
	return settledUnknown, reads, nil, "", ""
}

// firstNotgreenLane returns the first declared lane that does not derive green.
// The lanes are the ones review-checks.sh resolves for the merge, which drops
// the non-lanes none/off and the approval merge rule. ok=false is a state the
// caller holds on: the resolver exited non-zero, or a lane was unreadable
// (lane-state green exit 2). A resolver that dies prints nothing, and reading
// that as no lanes would merge on approval alone. An empty lane with ok=true
// means every declared lane is green.
func (m *merger) firstNotgreenLane(anchor, checkSet string) (lane string, ok bool) {
	lanes, rrc := m.scriptCapture("review-checks.sh", "--resolve", "--check-set", checkSet, "--through", "merge")
	if rrc != 0 {
		return "", false
	}
	for _, l := range strings.Split(lanes, "\n") {
		if l == "" {
			continue
		}
		switch m.scriptRC("lane-state.sh", "green", "--anchor", anchor, "--lane", l) {
		case 0:
			// green; next lane
		case 1:
			return l, true
		default:
			return "", false
		}
	}
	return "", true
}

// staleGateKey is the escalation key liveness-sweep.sh files its stale-PR-gate
// visit under, on an anchor whose PR stopped moving. Landing the PR is one of the
// dispositions that visit asks for, so a merge it held would block its own
// answer. The key's one definition is stale-gate.sh, which the shell scripts
// source and this port runs as `stale-gate.sh key`, once per pass. A key that
// does not read, or reads outside the charset finalize-gate.sh accepts for a
// key, excepts nothing: every visit then holds its merge, the fail-closed side
// of the gate.
func (m *merger) staleGateKey() string {
	if !m.staleKeyRead {
		m.staleKeyRead = true
		out, rc := m.scriptCapture("stale-gate.sh", "key")
		if k := strings.TrimSpace(out); rc == 0 && reEscalationKey.MatchString(k) {
			m.staleKey = k
		} else {
			fmt.Fprintf(m.stderr, "%s: WARN stale-gate.sh did not name the stale-PR-gate key; no visit is excepted from the finalize gate this pass\n", mergeProg)
		}
	}
	return m.staleKey
}

// finalizeGate reports whether the gate is open (ok) and, when held, the reason
// finalize-gate.sh printed. The gate excepts the stale-PR-gate visit only while
// nobody is engaged in it.
func (m *merger) finalizeGate(id string) (reason string, ok bool) {
	args := []string{"check", id}
	if k := m.staleGateKey(); k != "" {
		args = append(args, "--except-key", k)
	}
	out, rc := m.scriptCapture("finalize-gate.sh", args...)
	return strings.TrimRight(out, "\n"), rc == 0
}

// unresolvedThreads counts unresolved review threads on num. ok=false is an
// unreadable connection, never zero: a page that will not decode makes the
// whole count unreadable, as `jq -s` reads the paginated stream, because the
// unresolved threads may sit on exactly that page.
func (m *merger) unresolvedThreads(num string) (int, bool) {
	raw, rc := m.ghOrigin("graphql", "--paginate",
		"-f", "query="+threadsQuery,
		"-f", "owner="+originOwner(m.originRepo),
		"-f", "repo="+originName(m.originRepo),
		"-F", "num="+num)
	if rc != 0 || len(bytes.TrimSpace(raw)) == 0 {
		return 0, false
	}
	dec := json.NewDecoder(bytes.NewReader(gcbd.Scrub(raw)))
	dec.UseNumber()
	saw := false
	count := 0
	for {
		var page gqlThreadsPage
		if err := dec.Decode(&page); err != nil {
			if err == io.EOF {
				break
			}
			return 0, false
		}
		rt := page.Data.Repository.PullRequest.ReviewThreads
		if rt == nil {
			continue
		}
		saw = true
		for _, n := range rt.Nodes {
			if n.IsResolved == nil || !*n.IsResolved {
				count++
			}
		}
	}
	if !saw {
		return 0, false
	}
	return count, true
}

// reviewGatesFor reads branch protection: whether an unresolved thread blocks
// a merge and how many approvals are required. st is "known" or "unknown".
func (m *merger) reviewGatesFor(branch string) (st string, threadReq bool, approvals int) {
	raw, rc := m.ghOrigin("repos/" + m.originRepo + "/rules/branches/" + branch)
	var rules []branchRule
	if rc != 0 || json.Unmarshal(gcbd.Scrub(raw), &rules) != nil {
		return "unknown", false, 0
	}
	for _, r := range rules {
		if r.Type != "pull_request" {
			continue
		}
		if r.Parameters.RequiredReviewThreadResolution != nil && *r.Parameters.RequiredReviewThreadResolution {
			threadReq = true
		}
		if n := int(numberToInt64(r.Parameters.RequiredApprovingReviewCount)); n > approvals {
			approvals = n
		}
	}
	return "known", threadReq, approvals
}

// requiredContextsFor reads the status checks that actually gate branch, from
// rulesets and classic protection. st is "known" or "unknown".
func (m *merger) requiredContextsFor(branch string) (st string, contexts []string) {
	rulesRaw, rrc := m.ghOrigin("repos/" + m.originRepo + "/rules/branches/" + branch)
	branchRaw, brc := m.ghOrigin("repos/" + m.originRepo + "/branches/" + branch)
	var rules []branchRule
	if rrc != 0 || json.Unmarshal(gcbd.Scrub(rulesRaw), &rules) != nil {
		return "unknown", nil
	}
	var bm map[string]json.RawMessage
	if brc != 0 || json.Unmarshal(gcbd.Scrub(branchRaw), &bm) != nil {
		return "unknown", nil
	}
	if _, ok := bm["name"]; !ok {
		return "unknown", nil
	}
	var bo branchObj
	_ = json.Unmarshal(gcbd.Scrub(branchRaw), &bo)
	set := map[string]struct{}{}
	for _, r := range rules {
		if r.Type != "required_status_checks" {
			continue
		}
		for _, c := range r.Parameters.RequiredStatusChecks {
			if c.Context != "" {
				set[c.Context] = struct{}{}
			}
		}
	}
	for _, c := range bo.Protection.RequiredStatusChecks.Contexts {
		if c != "" {
			set[c] = struct{}{}
		}
	}
	for _, c := range bo.Protection.RequiredStatusChecks.Checks {
		if c.Context != "" {
			set[c.Context] = struct{}{}
		}
	}
	out := make([]string, 0, len(set))
	for c := range set {
		out = append(out, c)
	}
	sort.Strings(out)
	return "known", out
}

// --- sibling-script helpers -----------------------------------------------------

// helperDirProblem says why dir cannot serve as the sibling-script directory,
// or "" when it can. merge.sh exports its own directory as GCTK_SCRIPTS_DIR
// before it execs this binary; a binary run any other way has no directory to
// resolve the helpers in, and a bare name would fall to a PATH lookup. A named
// directory missing a helper is not refused here, because merge.sh refuses the
// pass only for a missing check resolver, which Merge checks next. Every other
// helper is handled where it is called. A missing lane-state.sh or
// finalize-gate.sh holds that anchor. A missing stale-gate.sh excepts no visit
// from the finalize gate, so an open stale-PR-gate visit holds its anchor. A
// missing escalate.sh, record-failure-cap.sh or render-seed-audit.sh is
// skipped. The pass still records a PR that has already merged.
func helperDirProblem(dir string) string {
	if dir == "" {
		return "GCTK_SCRIPTS_DIR is unset, so the sibling helpers (lane-state.sh, finalize-gate.sh, review-checks.sh, escalate.sh, record-failure-cap.sh, render-seed-audit.sh, stale-gate.sh) cannot be found; run gctk merge through assets/scripts/merge.sh, which sets it"
	}
	return ""
}

func (m *merger) scriptPath(name string) string { return filepath.Join(m.scriptsDir, name) }

func (m *merger) escalate(args ...string) {
	p := m.scriptPath("escalate.sh")
	if !isExecutable(p) {
		return
	}
	cmd := exec.Command(p, args...)
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	_ = cmd.Run()
}

func (m *merger) recordCap(id, num, mergeOid, base string) {
	p := m.scriptPath("record-failure-cap.sh")
	if !isExecutable(p) {
		return
	}
	cmd := exec.Command(p, id, num, mergeOid, base)
	cmd.Stdout = m.stdout
	cmd.Stderr = m.stderr
	_ = cmd.Run()
}

func (m *merger) scriptRC(name string, args ...string) int {
	cmd := exec.Command(m.scriptPath(name), args...)
	cmd.Stdout = io.Discard
	cmd.Stderr = m.stderr
	return gcbd.ExitCode(cmd.Run())
}

func (m *merger) scriptCapture(name string, args ...string) (string, int) {
	cmd := exec.Command(m.scriptPath(name), args...)
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = io.Discard
	err := cmd.Run()
	return buf.String(), gcbd.ExitCode(err)
}

func (m *merger) printIndented(s string, max int) {
	lines := strings.Split(s, "\n")
	for i, line := range lines {
		if i >= max {
			break
		}
		fmt.Fprintf(m.stdout, "  %s\n", line)
	}
}

// --- pure helpers ----------------------------------------------------------------

func stripSpaces(s string) string {
	return strings.Map(func(r rune) rune {
		switch r {
		case ' ', '\t', '\n', '\v', '\f', '\r':
			return -1
		}
		return r
	}, s)
}

func stripSpacesCommas(s string) string {
	return strings.Map(func(r rune) rune {
		switch r {
		case ' ', '\t', '\n', '\v', '\f', '\r', ',':
			return -1
		}
		return r
	}, s)
}

func allDigits(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

// envCount reads a count from the environment as bd-lib.sh's case guard does: a
// value that is empty or not all digits takes the default.
func envCount(name string, def int) int {
	v := os.Getenv(name)
	if !allDigits(v) {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return def
	}
	return n
}

// isHeld mirrors is_held: a value is held unless it is one of the "unset" forms.
func isHeld(v string) bool {
	switch v {
	case "", "false", "False", "FALSE", "0", "null":
		return false
	}
	return true
}

func urlRepoQ(url string) string {
	mm := reURLRepoQ.FindStringSubmatch(url)
	if mm == nil {
		return ""
	}
	return mm[1] + "/" + mm[2]
}

// repoQ is the repository a url names, lowercased; "?" when it names none.
func repoQ(url string) string {
	mm := reRepoQLower.FindStringSubmatch(strings.ToLower(stripSpaces(url)))
	if mm == nil {
		return "?"
	}
	return mm[1] + "/" + mm[2]
}

// canonPrURL is cutAtPull plus canon_pr_url's trailing-slash trim.
func canonPrURL(s string) string { return strings.TrimRight(cutAtPull(s), "/") }

// cutAtPull keeps a whitespace-stripped url up to and including its first
// /pull/<n> — the terminal re-read's sub() shape.
func cutAtPull(s string) string {
	s = stripSpaces(s)
	if loc := rePullSeg.FindStringIndex(s); loc != nil {
		s = s[:loc[1]]
	}
	return s
}

func originOwner(repo string) string {
	if i := strings.Index(repo, "/"); i >= 0 {
		return repo[:i]
	}
	return repo
}

func originName(repo string) string {
	if i := strings.Index(repo, "/"); i >= 0 {
		return repo[i+1:]
	}
	return repo
}

func shortSha(oid string) string {
	if strings.HasPrefix(oid, "unverified:") {
		return oid
	}
	if len(oid) > 8 {
		return oid[:8]
	}
	return oid
}

func fileExists(p string) bool {
	st, err := os.Stat(p)
	return err == nil && !st.IsDir()
}

func isExecutable(p string) bool {
	st, err := os.Stat(p)
	return err == nil && !st.IsDir() && st.Mode()&0o111 != 0
}

// capture runs a command, returns stdout and the exit code, discarding stderr —
// the `$(cmd 2>/dev/null)` shape.
func capture(bin string, args ...string) ([]byte, int) {
	cmd := exec.Command(bin, args...)
	out, err := cmd.Output()
	return out, gcbd.ExitCode(err)
}

func firstOut(out []byte, _ int) []byte { return out }

func runOut(bin string, args ...string) string {
	out, _ := capture(bin, args...)
	return string(out)
}

func runRC(bin string, args ...string) int {
	cmd := exec.Command(bin, args...)
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	return gcbd.ExitCode(cmd.Run())
}

func runCombined(bin string, args ...string) (string, int) {
	cmd := exec.Command(bin, args...)
	out, err := cmd.CombinedOutput()
	return strings.TrimRight(string(out), "\n"), gcbd.ExitCode(err)
}

// --- JSON-shaped helpers ---------------------------------------------------------

type prViewRow struct {
	State            string `json:"state"`
	IsDraft          bool   `json:"isDraft"`
	BaseRefName      string `json:"baseRefName"`
	HeadRefName      string `json:"headRefName"`
	HeadRefOid       string `json:"headRefOid"`
	MergeStateStatus string `json:"mergeStateStatus"`
	ReviewDecision   string `json:"reviewDecision"`
	URL              string `json:"url"`
	HeadRepository   struct {
		Name string `json:"name"`
	} `json:"headRepository"`
	HeadRepositoryOwner struct {
		Login string `json:"login"`
	} `json:"headRepositoryOwner"`
	// Raw, so an absent key (nil) stays distinguishable from a present null.
	IsCrossRepository json.RawMessage `json:"isCrossRepository"`
}

// jqHasToString reproduces `if has(k) then (.k | tostring) else "" end` for a
// value decoded as json.RawMessage: an absent key is "", a string is its text,
// and any other value, null included, is its JSON spelling.
func jqHasToString(raw json.RawMessage) string {
	v := bytes.TrimSpace(raw)
	if len(v) == 0 {
		return ""
	}
	if v[0] == '"' {
		var s string
		if json.Unmarshal(v, &s) == nil {
			return s
		}
		return ""
	}
	var buf bytes.Buffer
	if json.Compact(&buf, v) != nil {
		return ""
	}
	return buf.String()
}

// jqToString is jq's `.[$k] | tostring`: a missing key reads as null, a string
// is its text, and any other value is its JSON spelling.
func jqToString(raw json.RawMessage) string {
	if len(bytes.TrimSpace(raw)) == 0 {
		return "null"
	}
	return jqHasToString(raw)
}

// jqAltString is jq's `(.k // "") | tostring`: a missing key, null and false
// read as "", a string is its text, and any other value is its JSON spelling.
func jqAltString(raw json.RawMessage) string {
	switch v := bytes.TrimSpace(raw); string(v) {
	case "", "null", "false":
		return ""
	default:
		return jqHasToString(v)
	}
}

// mergeabilityFacts are the fields a re-read may change, because GitHub computes
// them against the PR's base. Every other pinned field was validated before the
// re-read.
var mergeabilityFacts = map[string]bool{"mergeStateStatus": true, "mergeable": true, "reviewDecision": true}

// changedFields names each field outside the mergeability facts whose value
// differs between two reads, as `key 'pinned' -> 're-read'`, in key order and
// joined by ", ". Empty means the reads agree. Values compare as JSON values, as
// jq's != does, so key order and number spelling are not a change, and a key one
// read lacks reads as null.
func changedFields(pinned, again map[string]json.RawMessage) string {
	seen := map[string]bool{}
	var keys []string
	for _, row := range []map[string]json.RawMessage{pinned, again} {
		for k := range row {
			if !mergeabilityFacts[k] && !seen[k] {
				seen[k] = true
				keys = append(keys, k)
			}
		}
	}
	sort.Strings(keys)
	var out []string
	for _, k := range keys {
		if !jsonEqual(pinned[k], again[k]) {
			out = append(out, k+" '"+jqToString(pinned[k])+"' -> '"+jqToString(again[k])+"'")
		}
	}
	return strings.Join(out, ", ")
}

// jsonEqual compares two raw values as decoded JSON. A missing value is null.
func jsonEqual(a, b json.RawMessage) bool {
	var va, vb any
	if len(bytes.TrimSpace(a)) > 0 && json.Unmarshal(a, &va) != nil {
		return false
	}
	if len(bytes.TrimSpace(b)) > 0 && json.Unmarshal(b, &vb) != nil {
		return false
	}
	return reflect.DeepEqual(va, vb)
}

type gqlThreadsPage struct {
	Data struct {
		Repository struct {
			PullRequest struct {
				ReviewThreads *struct {
					Nodes []struct {
						IsResolved *bool `json:"isResolved"`
					} `json:"nodes"`
				} `json:"reviewThreads"`
			} `json:"pullRequest"`
		} `json:"repository"`
	} `json:"data"`
}

type branchRule struct {
	Type       string `json:"type"`
	Parameters struct {
		RequiredReviewThreadResolution *bool       `json:"required_review_thread_resolution"`
		RequiredApprovingReviewCount   json.Number `json:"required_approving_review_count"`
		RequiredStatusChecks           []struct {
			Context string `json:"context"`
		} `json:"required_status_checks"`
	} `json:"parameters"`
}

type branchObj struct {
	Protection struct {
		RequiredStatusChecks struct {
			Contexts []string `json:"contexts"`
			Checks   []struct {
				Context string `json:"context"`
			} `json:"checks"`
		} `json:"required_status_checks"`
	} `json:"protection"`
}

// duplicateAnchors returns the comma-joined ids of other open anchors that claim
// this PR number, each keyed by the repository its own pr_url names. "?" on
// either side is the fail-closed wildcard.
func duplicateAnchors(dups []gcbd.Bead, id, num, ourURL string) string {
	ours := repoQ(ourURL)
	var out []string
	for i := range dups {
		d := &dups[i]
		if d.ID == id {
			continue
		}
		if d.Meta("pr_number") != num {
			continue
		}
		rq := repoQ(d.Meta("pr_url"))
		if ours == "?" || rq == "?" || rq == ours {
			out = append(out, d.ID)
		}
	}
	return strings.Join(out, ",")
}

// inflightHolder is the first open rework/review/finding bead that holds the
// merge: a pr_number holder qualified by repository, or any dep-edge blocker
// (the edge is the claim, local by construction). The order is by_pr, then
// children, then blockers.
func (m *merger) inflightHolder(id string, byPR, children, blockers []gcbd.Bead) string {
	ours := strings.ToLower(m.originRepoQ)
	type tagged struct {
		b   *gcbd.Bead
		dep bool
	}
	var all []tagged
	for i := range byPR {
		all = append(all, tagged{&byPR[i], false})
	}
	for i := range children {
		all = append(all, tagged{&children[i], true})
	}
	for i := range blockers {
		all = append(all, tagged{&blockers[i], true})
	}
	for _, t := range all {
		b := t.b
		if b.ID == id || !isLive(b) {
			continue
		}
		if !t.dep {
			mr := b.Meta("merge_result")
			tk := strings.ToLower(b.Meta("tracking_only"))
			rq := repoQ(b.Meta("pr_url"))
			okTrack := tk == "" || tk == "false" || tk == "0" || tk == "null"
			if !(mr == "" && okTrack && (rq == "?" || rq == ours)) {
				continue
			}
		}
		kind := "unclosed rework/review bead"
		if b.Meta("task_kind") == "finding" {
			if fd := b.Meta("finding.disposition"); fd != "" {
				kind = fd + " finding"
			} else {
				kind = "finding"
			}
		}
		return fmt.Sprintf("%s %s (%s)", kind, b.ID, holderStatus(b))
	}
	return ""
}

// mergeLive is mergeLiveStatuses as the set a holder's status is tested in.
var mergeLive = strings.Split(mergeLiveStatuses, ",")

// holderStatus is a referencing bead's status as the holder probes read it,
// `(.status // "open") | ascii_downcase`: only a null or absent status defaults
// to open, and an empty string stays empty.
func holderStatus(b *gcbd.Bead) string { return b.StatusLowerOr("open") }

// isLive reports whether a referencing bead's status lets it hold the merge.
func isLive(b *gcbd.Bead) bool { return inSlice(mergeLive, holderStatus(b)) }

// poolHolder is the first live blocker a pool will claim (routed to something
// other than a human).
func poolHolder(blockers []gcbd.Bead) string {
	for i := range blockers {
		b := &blockers[i]
		if !isLive(b) {
			continue
		}
		if r := b.Meta("gc.routed_to"); r != "" && r != "human" {
			return b.ID
		}
	}
	return ""
}

// stuckHolder is the first live blocker carrying no route at all — one no
// automated actor will claim and no `asking` edge names.
func stuckHolder(blockers []gcbd.Bead) string {
	for i := range blockers {
		b := &blockers[i]
		if isLive(b) && b.Meta("gc.routed_to") == "" {
			return b.ID
		}
	}
	return ""
}

type reviewRow struct {
	Login       string
	State       string
	SubmittedAt string
	IDNum       int64
}

type reviewSummary struct {
	veto     string
	approver string
}

// reviewState applies the approval rule (reviewVerdict) to a PR's REST reviews
// history. ok=false is an unreadable history: `jq -cs` slurps the whole stream
// or nothing, so one row that will not decode makes all of it unreadable,
// because the veto or the only approval may be that row or follow it.
func reviewState(raw []byte, self string) (reviewSummary, bool) {
	dec := json.NewDecoder(bytes.NewReader(gcbd.Scrub(raw)))
	dec.UseNumber()
	var all []reviewRow
	for {
		var obj struct {
			User struct {
				Login string `json:"login"`
			} `json:"user"`
			State       string      `json:"state"`
			SubmittedAt string      `json:"submitted_at"`
			ID          json.Number `json:"id"`
		}
		if err := dec.Decode(&obj); err != nil {
			// The end of the stream, trailing whitespace and an empty history
			// all decode to io.EOF; anything else is a row that did not decode.
			if err == io.EOF {
				break
			}
			return reviewSummary{}, false
		}
		all = append(all, reviewRow{
			Login:       obj.User.Login,
			State:       obj.State,
			SubmittedAt: obj.SubmittedAt,
			IDNum:       numberToInt64(obj.ID),
		})
	}
	return reviewVerdict(all, self), true
}

// reviewVerdict is the approval rule, which the approval gate and the visit
// order share so the two never disagree on approval. Each reviewer other than
// self takes its latest APPROVED or CHANGES_REQUESTED review, and that review
// decides veto and approver. Every DISMISSED review is dropped before the
// latest is taken, so a dismissed approval does not count and a dismissed
// CHANGES_REQUESTED does not hide its author's older approval. An approval
// stands across later pushes until someone dismisses it, so the commit a review
// was given at is not read.
func reviewVerdict(all []reviewRow, self string) reviewSummary {
	var summary reviewSummary
	// Group the non-self APPROVED and CHANGES_REQUESTED reviews by login and keep
	// the latest per reviewer by (submitted_at, id). A DISMISSED row is dropped
	// before the latest is taken.
	groups := map[string][]reviewRow{}
	for _, r := range all {
		if r.Login == self {
			continue
		}
		if r.State != "APPROVED" && r.State != "CHANGES_REQUESTED" {
			continue
		}
		groups[r.Login] = append(groups[r.Login], r)
	}
	logins := make([]string, 0, len(groups))
	for l := range groups {
		logins = append(logins, l)
	}
	sort.Strings(logins)
	for _, l := range logins {
		g := groups[l]
		sort.SliceStable(g, func(i, j int) bool {
			if g[i].SubmittedAt != g[j].SubmittedAt {
				return g[i].SubmittedAt < g[j].SubmittedAt
			}
			return g[i].IDNum < g[j].IDNum
		})
		latest := g[len(g)-1]
		if latest.State == "CHANGES_REQUESTED" && summary.veto == "" {
			summary.veto = l
		}
		if latest.State == "APPROVED" && summary.approver == "" {
			summary.approver = l
		}
	}
	return summary
}

// openPR is one node of the open-PR read.
type openPR struct {
	Number                   json.Number `json:"number"`
	IsDraft                  bool        `json:"isDraft"`
	HeadRefOid               string      `json:"headRefOid"`
	LatestOpinionatedReviews struct {
		Nodes []struct {
			State       string      `json:"state"`
			SubmittedAt string      `json:"submittedAt"`
			DatabaseID  json.Number `json:"databaseId"`
			Author      struct {
				Login string `json:"login"`
			} `json:"author"`
		} `json:"nodes"`
	} `json:"latestOpinionatedReviews"`
}

// reviews is each account's latest review on the PR, in the rows the approval
// rule reads.
func (pr *openPR) reviews() []reviewRow {
	out := make([]reviewRow, 0, len(pr.LatestOpinionatedReviews.Nodes))
	for _, n := range pr.LatestOpinionatedReviews.Nodes {
		out = append(out, reviewRow{
			Login:       n.Author.Login,
			State:       n.State,
			SubmittedAt: n.SubmittedAt,
			IDNum:       numberToInt64(n.DatabaseID),
		})
	}
	return out
}

func numberToInt64(n json.Number) int64 {
	if n == "" {
		return 0
	}
	if i, err := n.Int64(); err == nil {
		return i
	}
	if f, err := n.Float64(); err == nil {
		return int64(f)
	}
	return 0
}

// notGreenRequired names each required context that is MISSING or RED in the
// rollup, joined by spaces. ok=false means the rollup did not decode.
func notGreenRequired(rollupRaw []byte, required []string) (string, bool) {
	var v struct {
		StatusCheckRollup []map[string]any `json:"statusCheckRollup"`
	}
	if json.Unmarshal(gcbd.Scrub(rollupRaw), &v) != nil {
		return "", false
	}
	nameOf := func(item map[string]any) string {
		if n, ok := item["name"].(string); ok && n != "" {
			return n
		}
		if c, ok := item["context"].(string); ok {
			return c
		}
		return ""
	}
	green := func(item map[string]any) bool {
		if c, ok := item["conclusion"].(string); ok && c != "" {
			u := strings.ToUpper(c)
			return u == "SUCCESS" || u == "NEUTRAL" || u == "SKIPPED"
		}
		if s, ok := item["state"].(string); ok && s != "" {
			return strings.ToUpper(s) == "SUCCESS"
		}
		return false
	}
	var out []string
	for _, c := range required {
		var hits []map[string]any
		for _, item := range v.StatusCheckRollup {
			if nameOf(item) == c {
				hits = append(hits, item)
			}
		}
		if len(hits) == 0 {
			out = append(out, c+"(MISSING)")
			continue
		}
		red := false
		for _, h := range hits {
			if !green(h) {
				red = true
				break
			}
		}
		if red {
			out = append(out, c+"(RED)")
		}
	}
	return strings.Join(out, " "), true
}

// terminalReason re-derives the full stored authorization set immediately before
// the merge, returning "OK" or the first field that moved.
func terminalReason(final *gcbd.Bead, num, base, url, ref string) string {
	st := final.StatusLower()
	mr := final.Meta("merge_result")
	pn := final.Meta("pr_number")
	h := final.Meta("merge_hold")
	t := final.Meta("merged_target")
	pu := cutAtPull(final.Meta("pr_url"))
	br := final.Meta("branch")
	fcs := final.Meta("check_set")
	switch {
	case st != "open":
		return "status is now " + st
	case mr != "pull_request":
		return "merge_result is now " + mr
	case pn != num:
		return "anchor now claims PR#" + pn
	case isHeld(h):
		return "merge_hold was set after validation"
	case strings.HasPrefix(final.Meta("pr_posture"), "commented@"):
		return "review comments went unanswered after validation"
	case t != "" && t != base:
		return "retargeted after validation (merged_target=" + t + ")"
	case pu != "" && pu != url:
		return "pr_url changed after validation"
	case br != "" && br != ref:
		return "branch changed after validation"
	case stripSpacesCommas(fcs) == "":
		return "check_set emptied after validation"
	default:
		return "OK"
	}
}

func inSlice(s []string, v string) bool {
	for _, x := range s {
		if x == v {
			return true
		}
	}
	return false
}
