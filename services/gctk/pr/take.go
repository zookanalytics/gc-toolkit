package pr

import (
	"context"
	"errors"
	"fmt"
	"maps"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

// The take (specs/tk-1tfzr71.161/design.md, sections 1 to 3). Each post a
// person makes on a PR the city owns becomes an ask on the bead that owns the
// PR, which the PR's review run rules. The one-PR update saves each post that
// is feedback the city has not taken in the PR's saved read (untakenOf), and
// the landing order takes them from there: under the record lock it files an
// ask for each such post, whose one-line reason names the post (Post.reason),
// and once the ask is filed it marks the post with the city's EYES, the receipt
// the definition of feedback reads (gc_city_taken in
// assets/scripts/pr-post.sh). With the lock free it then has the update read
// the PR's conversation again, since a reaction moves no sign the cheap
// question reads, so the saved read shows the marks before the next run
// decides. A filing finds the ask filed before for the same reason, open or
// closed (review.FileAsk), so a post whose mark did not land is marked again
// with no second ask, and a post edited after its take, whose text no reason
// holds, is filed once. A take that does not complete leaves its posts untaken
// in the saved read, where they hold the PR's merge (unhandled), and the run
// reports it as a retry, so the run exits non-zero. One that keeps the last of
// its bound for the read once a mark has landed (refreshReserve) leaves the
// posts it did not reach for the next run.

// refreshReserve is how much of its bound a take keeps, once a mark has landed,
// for the one-PR update's read of the PR's conversation, the only write that
// shows the saved read the marks. A take that spent its whole bound on posts
// would save none of its marks, and each next run, finding every post still
// untaken, would start again from the first, so a PR with more posts than one
// act can take would never have them all taken. The read is a few GitHub and
// store calls, which take seconds.
const refreshReserve = 10 * time.Second

// takeOf is the take one owned PR owes: the bead that owns it, the PR's URL as
// the bead names it, and the PR's identity.
type takeOf struct {
	bead, url, key string
}

// of names the take, as each outcome it reports opens.
func (t takeOf) of() string { return "the take of " + t.url }

// takePlans are the takes and the conversions the PRs the store's live beads
// own owe, read through pass: a conversion for each PR whose bead carries
// the old receipts and owes their conversion (unconvertible), and a take
// for each PR whose bead's saved read holds a post the city has not taken,
// while the bead may have it taken (untakenOn), which a bead carrying the
// receipts may not. A PR more than one live bead owns owes neither, since the
// store names no one bead its asks would block. The plans are in the order of
// the PRs' identities.
func (u *run) takePlans(pass *ledger.Ledger) ([]plan, error) {
	all, err := ownersIn(pass)
	if err != nil {
		return nil, err
	}
	var out []plan
	for _, key := range slices.Sorted(maps.Keys(all)) {
		if len(all[key]) != 1 {
			continue
		}
		o := all[key][0]
		if len(o.receipts) > 0 && u.unconvertible(o) == "" {
			out = append(out, plan{id: "convert " + o.id, convert: &convertOf{bead: o.id, url: o.url, key: key}})
		}
		if posts, _ := u.untakenOn(o); len(posts) == 0 {
			continue
		}
		out = append(out, plan{id: "take " + o.id, take: &takeOf{bead: o.id, url: o.url, key: key}})
	}
	return out, nil
}

// untakenOn is the posts the read saved on the bead o reads holds untaken,
// which the take files and marks, or why it takes none: the bead must own the
// PR on the record, as an ask's filing requires, be open or blocked, be
// assigned to nobody or to the refinery, as any act's bead is, name its branch,
// which each ask names, and carry none of the old receipts, which the
// conversion turns into the city's marks first, and the saved read must be of
// its PR, show the PR open and have applied the definition of feedback from the
// bead's provenance instant.
func (u *run) untakenOn(o owned) ([]Post, string) {
	s := o.saved
	switch {
	case len(o.receipts) > 0:
		return nil, "the bead carries the old receipts (" + strings.Join(o.receipts, ", ") +
			"), which their conversion turns into the city's marks before a take"
	case !record.OnRecord(o.rec.Result):
		return nil, fmt.Sprintf("the bead owns no PR on the record: its merge_result reads %q", o.rec.Result)
	case o.status != "open" && o.status != "blocked":
		return nil, "the bead's status " + o.status + " is none the record knows"
	case o.assignee != "" && o.assignee != u.Refinery:
		return nil, "the bead is assigned to " + o.assignee + ", who works it now"
	case o.branch == "":
		return nil, "the bead names no branch for an ask to name"
	case s == nil || s.PR == nil || s.Conversation == nil:
		return nil, "the bead holds no saved read of the PR's conversation yet"
	case !strings.EqualFold(s.PR.Repository, o.repo) || s.PR.Number != o.number:
		return nil, fmt.Sprintf("the saved read is of %s#%d", s.PR.Repository, s.PR.Number)
	case s.PR.State != "OPEN":
		return nil, "the saved read shows the PR " + strings.ToLower(s.PR.State)
	case s.Conversation.Since != o.since:
		return nil, fmt.Sprintf("the saved conversation applied the definition of feedback from %q, not from the "+
			"bead's provenance instant %q", s.Conversation.Since, o.since)
	case len(s.Conversation.Untaken) == 0:
		return nil, "the saved read holds no post the city has not taken"
	}
	return s.Conversation.Untaken, ""
}

// take is a take's act, which ends stop after it starts: under the record lock
// it files the ask of each post the saved read holds untaken and marks the
// post once its ask is filed (takeLocked), and once a mark has landed and the
// lock is free it has the one-PR update read the PR's conversation again
// (RefreshConversation). A filing, a mark or a read again that does not
// complete makes it a retry, and the next run takes the posts again. Posts it
// left for that read's reserve make it left, and the next run takes them.
func (u *run) take(t takeOf, stop time.Duration) RunOutcome {
	ctx, cancel := bounded(stop)
	defer cancel()
	out, marked := u.takeLocked(ctx, t)
	if marked > 0 {
		why := "nothing reads the PR's conversation again here"
		if u.RefreshConversation != nil {
			why = ""
			if err := u.RefreshConversation(ctx, t.url); err != nil {
				why = "the one-PR update's read of the PR's conversation did not save: " + err.Error()
			}
		}
		if why != "" {
			out.Action = ActRetry
			out.Detail += "; " + why + ", so the saved read shows the posts untaken, and the next run makes the take again"
		}
	}
	if ctx.Err() != nil && (out.Action == ActRetry || out.Action == ActFailed) {
		out.Action = ActRetry
		out.Detail = fmt.Sprintf("the act was stopped at its %s: %s", stop, out.Detail)
	}
	return out
}

// takeLocked is the part of the take made under the record lock, within ctx:
// it reads the bead again, decides from that read which posts are untaken
// (untakenOn), and for each files the post's ask on the bead (review.FileAsk),
// then marks the post with takenMark. A post whose ask did not file is not
// marked, so the mark never stands without its ask. Once a mark has landed it
// starts no post with less than refreshReserve of ctx left. It returns the
// take's outcome, whose detail opens with the take it is (takeOf.of), and how
// many marks landed.
func (u *run) takeLocked(ctx context.Context, t takeOf) (RunOutcome, int) {
	unbound := u.Ledger
	u.Ledger = unbound.Within(ctx)
	defer func() { u.Ledger = unbound }()
	said := func(action, detail string) (RunOutcome, int) {
		return RunOutcome{Bead: t.bead, Action: action, Detail: t.of() + " " + detail}, 0
	}
	release, err := record.Lock(u.Dir, lockWait(ctx, u.Wait))
	if err != nil {
		return said(ActRetry, "waits for the next run: the record lock did not come free: "+err.Error())
	}
	defer release()
	r, err := u.read(t.bead)
	if err != nil {
		return said(ActFailed, "did not read the bead: "+err.Error())
	}
	if r == nil {
		return said(ActSkipped, "takes nothing: the store no longer holds the bead")
	}
	o, ok := ownerOf(r)
	if !ok || o.key() != t.key {
		return said(ActSkipped, "takes nothing: the bead no longer owns the PR")
	}
	posts, why := u.untakenOn(o)
	if len(posts) == 0 {
		return said(ActChecked, "takes nothing: "+why)
	}
	if why := u.originDiffers(o.host, o.repo); why != "" {
		return said(ActRetry, "waits for the next run: "+why)
	}
	hub := u.Hub(ctx, o.host)
	noChecks := func(string) (review.Index, error) {
		return review.Index{}, errors.New("a post's ask sends back no check")
	}
	var took, failed, left []string
	marked := 0
	for _, p := range posts {
		if ctx.Err() != nil {
			failed = append(failed, p.name()+" was not reached")
			continue
		}
		if end, ok := ctx.Deadline(); ok && marked > 0 && time.Until(end) < refreshReserve {
			left = append(left, p.name())
			continue
		}
		ask, filed, err := review.FileAsk(u.Ledger, review.AskRequest{Bead: o.id, Reason: p.reason(o.number)}, noChecks)
		if err != nil {
			failed = append(failed, fmt.Sprintf("%s: its ask did not file: %v", p.name(), err))
			continue
		}
		if err := hub.AddReaction(p.Node, takenMark); err != nil {
			failed = append(failed, fmt.Sprintf("%s: ask %s stands, and the city's %s did not land on the post: %v",
				p.name(), ask, takenMark, err))
			continue
		}
		marked++
		how := "filed"
		if !filed {
			how = "found"
		}
		took = append(took, fmt.Sprintf("%s, ask %s %s", p.name(), ask, how))
	}
	out := RunOutcome{Bead: t.bead, Action: ActTaken,
		Detail: fmt.Sprintf("%s took %s, each marked with the city's %s", t.of(), strings.Join(took, "; "), takenMark)}
	reserved := ""
	if len(left) > 0 {
		reserved = fmt.Sprintf("left %s for the next run, keeping the last %s of the act for the read of the "+
			"conversation that saves the marks", strings.Join(left, ", "), refreshReserve)
		out.Action = ActLeft
		out.Detail += ", and " + reserved
	}
	if len(failed) > 0 {
		out.Action = ActRetry
		out.Detail = fmt.Sprintf("%s did not complete, and the next run makes it again for what is left: %s", t.of(),
			strings.Join(failed, "; "))
		if len(took) > 0 {
			out.Detail += "; it took " + strings.Join(took, "; ")
		}
		if reserved != "" {
			out.Detail += "; it " + reserved
		}
	}
	return out, marked
}
