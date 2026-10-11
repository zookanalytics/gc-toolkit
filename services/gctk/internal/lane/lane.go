// Package lane derives a review lane's GREEN state from the finding and
// review-outcome graph, never from a stored check.<lane> marker. It is the port
// of assets/scripts/lane-state.sh, the one shared helper the merge predicate,
// pr-open, the liveness sweep and the board ask, so every reader derives green
// the same way — and now from one code path: `gctk lane-state` (internal/cli)
// is the script's CLI, and `gctk merge` calls Green in-process.
//
// A lane is one reviewer, named by one check_set member. green(anchor, lane)
// holds when a closed review bead backs the lane and no review for the lane is
// in flight:
//
//   - backing: a closed task_kind=review bead whose anchor_bead is this anchor,
//     carrying a reviewed_oid, whose check_name is this lane (an absent
//     check_name resolves to correctness), carrying signoff_verdict=approve and
//     not superseded (gc.outcome is not superseded); OR the anchor's pr_number
//     has an APPROVED GitHub review, which names no check and so backs every
//     lane. signoff_verdict is the only stamp that names the verdict: signoff
//     writes gc.outcome=recorded on every close, approve and request-changes
//     alike, so a close with no signoff_verdict backs no lane locally and is
//     corroborated only by the GitHub-approval fallback. The reviewed_oid clause
//     guards a local backing bead (an approve naming no reviewed commit is a
//     stale row); the fallback is independent evidence and needs no such pin.
//   - in flight: an open review bead for this lane holds the lane out of green,
//     whatever else is true — the precedence that keeps green from co-existing
//     with a live review.
//
// Two conditions the full derivation names are deliberately NOT read here: an
// open must-fix finding (anchor-wide, the merge predicate's own blocker probe)
// and an open validation pass (the validator owns that bead).
//
// Every accessor mirrors the jq the script used, corners included: `(.x // "")
// | tostring` treats null and false alike as absent.
package lane

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os/exec"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
)

// Verdict is the derivation's answer, numbered as the script's exit code: a
// caller that runs lane-state as a process and one that calls Green read the
// same three values.
type Verdict int

const (
	// IsGreen: a closed review backs the lane and none is in flight (exit 0).
	IsGreen Verdict = 0
	// NotGreen: no backing, a review in flight, or a fallback that could not be
	// confirmed (exit 1). Fail-closed: every failure of the remote path is this.
	NotGreen Verdict = 1
	// Unreadable: the store would not read (exit 2). A merge predicate treats it
	// as not green, never as green by default, and names the read that failed.
	Unreadable Verdict = 2
)

// AllStatuses is the --status set the derivation lists, in the script's order:
// live AND closed review beads, because an open one must be SEEN to exclude the
// lane and a closed one is the backing — a filter that skipped either would
// derive green from an absence.
var AllStatuses = []string{"open", "in_progress", "blocked", "deferred", "hooked", "pinned", "closed"}

// Origin names the checkout's GitHub repository as owner/repo. ok=false when
// the origin is not a GitHub URL of a recognised form, or could not be read.
type Origin interface {
	Slug() (slug string, ok bool)
}

// Approver answers whether a PR carries an APPROVED review. ok=false when the
// question could not be answered (no gh, a failed call, an unreadable stream);
// the caller reads that as not green.
type Approver interface {
	ApprovedReviewOnPR(repoSlug, pr string) (approved, ok bool)
}

// Remote is the GitHub-approval fallback's two seams. The zero value has
// neither, so the fallback is unavailable and a lane with no local backing is
// not green — the fail-closed default.
type Remote struct {
	Origin   Origin
	Approver Approver
}

// Green derives the lane's state for anchor. Unreadable comes with the error
// whose text the CLI prints after its "lane-state: " prefix; the other two
// verdicts carry no error.
func Green(store gcbd.Store, remote Remote, anchor, lane string, noRemote bool) (Verdict, error) {
	rows, ok := store.List(gcbd.ListQuery{
		MetadataField: []string{"anchor_bead=" + anchor},
		Status:        AllStatuses,
	})
	if !ok {
		return Unreadable, fmt.Errorf("could not read review beads on %s", anchor)
	}

	// An open review for this lane holds it out of green whatever else is true.
	for i := range rows {
		r := &rows[i]
		if !reviewOnLane(r, lane) {
			continue
		}
		if r.StatusLower() != "closed" {
			return NotGreen, nil
		}
	}

	for i := range rows {
		r := &rows[i]
		if !reviewOnLane(r, lane) || r.StatusLower() != "closed" {
			continue
		}
		if r.Meta("reviewed_oid") == "" {
			continue
		}
		if r.Meta("signoff_verdict") == "approve" && r.Meta("gc.outcome") != "superseded" {
			return IsGreen, nil
		}
	}

	// No local backing. An operator's GitHub approval is the last way the approve
	// half is met; absent that, or when it cannot be confirmed, the lane is not
	// green.
	if noRemote {
		return NotGreen, nil
	}
	if githubApproved(store, remote, anchor) {
		return IsGreen, nil
	}
	return NotGreen, nil
}

// reviewOnLane is the row filter both passes share: task_kind=review and the
// row's lane (check_name, empty resolving to correctness) equal to lane.
func reviewOnLane(b *gcbd.Bead, lane string) bool {
	if b.Meta("task_kind") != "review" {
		return false
	}
	check := b.Meta("check_name")
	if check == "" {
		check = "correctness"
	}
	return check == lane
}

// githubApproved is the fallback: an APPROVED GitHub review on the anchor's PR
// backs every lane. Consulted only when no local review bead backs the lane,
// and fail-closed: any step that cannot be completed is false, never true.
func githubApproved(store gcbd.Store, remote Remote, anchor string) bool {
	pr := store.Show(anchor).Meta("pr_number")
	if pr == "" {
		return false
	}
	if remote.Origin == nil || remote.Approver == nil {
		return false
	}
	slug, ok := remote.Origin.Slug()
	if !ok {
		return false
	}
	approved, ok := remote.Approver.ApprovedReviewOnPR(slug, pr)
	return ok && approved
}

// OriginSlug reduces a GitHub origin URL to owner/repo. It accepts the three
// forms the script's case matched — git@github.com:, https://github.com/ and
// ssh://git@github.com/ — and applies its sed chain in order: strip the
// prefixes, then a trailing .git, then trailing slashes. The result must be
// exactly owner/repo: owner/repo/extra, a leading slash, a trailing slash and a
// bare name are rejected. The URL is taken as given; GitOrigin strips the
// whitespace `git remote get-url` prints around it.
func OriginSlug(remoteURL string) (string, bool) {
	u := remoteURL
	switch {
	case strings.HasPrefix(u, "git@github.com:"),
		strings.HasPrefix(u, "https://github.com/"),
		strings.HasPrefix(u, "ssh://git@github.com/"):
	default:
		return "", false
	}
	u = strings.TrimPrefix(u, "ssh://git@github.com/")
	u = strings.TrimPrefix(u, "git@github.com:")
	u = strings.TrimPrefix(u, "https://github.com/")
	u = strings.TrimSuffix(u, ".git")
	u = strings.TrimRight(u, "/")
	if strings.Count(u, "/") != 1 || strings.HasPrefix(u, "/") || strings.HasSuffix(u, "/") {
		return "", false
	}
	return u, true
}

// GitOrigin reads the checkout's origin through `git remote get-url origin`,
// strips every whitespace byte (the script's `tr -d '[:space:]'`) and reduces
// it with OriginSlug. git's exit status is not consulted, as the script's
// pipeline did not consult it: a git that fails or is absent prints nothing,
// and nothing is no GitHub URL.
type GitOrigin struct{}

// Slug implements Origin.
func (GitOrigin) Slug() (string, bool) {
	out, _ := exec.Command("git", "remote", "get-url", "origin").Output()
	return OriginSlug(stripSpaces(string(out)))
}

// FixedSlug is an Origin that answers one slug: for a caller that already
// resolved the repository (gctk merge) and for tests.
type FixedSlug string

// Slug implements Origin. The empty string is no slug.
func (s FixedSlug) Slug() (string, bool) { return string(s), s != "" }

// GHApprover asks GitHub through `gh api`, exactly as the script did:
// `repos/<slug>/pulls/<pr>/reviews?per_page=100 --paginate`, which prints one
// JSON array per page, concatenated. No gh on PATH, a non-zero exit, or an
// empty body is ok=false.
type GHApprover struct{}

// ApprovedReviewOnPR implements Approver.
func (GHApprover) ApprovedReviewOnPR(repoSlug, pr string) (bool, bool) {
	if _, err := exec.LookPath("gh"); err != nil {
		return false, false
	}
	out, err := exec.Command("gh", "api", "repos/"+repoSlug+"/pulls/"+pr+"/reviews?per_page=100", "--paginate").Output()
	if err != nil || len(out) == 0 {
		return false, false
	}
	return ApprovedInStream(out)
}

// ApprovedInStream reads the body `gh api --paginate` prints — a stream of
// concatenated JSON arrays, one per page — the way the script's `jq -s '[
// .[][]? | select(((.state // "") | tostring) == "APPROVED") ] | length > 0'`
// read it. The body is scrubbed of C0 bytes first (the script's scrub); each
// page that is an array contributes its elements, a page that is not one is
// skipped (jq's `?`); approved is true when any element's .state reads
// "APPROVED". A stream that stops decoding partway — a cut-short page — is
// ok=false, as jq failed the whole stream, so a partial answer is never read as
// a verdict. An element that is not an object (jq cannot index a string with
// .state) fails the same way; a null element indexes to null and is skipped.
func ApprovedInStream(body []byte) (approved, ok bool) {
	dec := json.NewDecoder(bytes.NewReader(gcbd.Scrub(body)))
	dec.UseNumber()
	for {
		var page any
		if err := dec.Decode(&page); err != nil {
			if errors.Is(err, io.EOF) {
				return approved, true
			}
			return false, false
		}
		elems, isArray := page.([]any)
		if !isArray {
			continue
		}
		for _, e := range elems {
			switch el := e.(type) {
			case nil:
			case map[string]any:
				if jqString(el["state"]) == "APPROVED" {
					approved = true
				}
			default:
				return false, false
			}
		}
	}
}

// jqString reproduces `(v // "") | tostring` for a decoded JSON value, the
// accessor gcbd.Bead.Meta applies to metadata: null and false are absent,
// true is "true", a number is its literal, and anything else its JSON.
func jqString(v any) string {
	switch t := v.(type) {
	case nil:
		return ""
	case bool:
		if !t {
			return ""
		}
		return "true"
	case string:
		return t
	case json.Number:
		return t.String()
	default:
		raw, err := json.Marshal(t)
		if err != nil {
			return ""
		}
		return string(raw)
	}
}

// stripSpaces is `tr -d '[:space:]'`.
func stripSpaces(s string) string {
	return strings.Map(func(r rune) rune {
		switch r {
		case ' ', '\t', '\n', '\v', '\f', '\r':
			return -1
		}
		return r
	}, s)
}
