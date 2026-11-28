package pr

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/quote"
)

// A held post's follow-up. The quote holds a post by an account outside a
// repository the city's account can push to (services/gctk/quote), so no agent
// reads its text, and the operator learns of it through one human gate per
// account per PR, on the bead that owns the PR. The board shows an open gate as
// a question, and on an open bead the gate holds the PR's merge until the
// operator clears it. It is the one hold a held post puts on the PR, since a
// review thread is weighed without its held posts (threadsOf). human-gate.sh
// files one open gate per bead and key, so the take and every reader of the PR
// file it once, and a later post by the same account while it is open is one
// its message covers. Once its gate is filed or found open, the post takes the
// take's mark, so no later read files a gate for it again after the operator
// clears the one it has.

// followUpKeyPrefix opens the key of a held post's human gate, which the
// account's login, lower-cased, ends.
const followUpKeyPrefix = "outside-post-"

// followUpLogin is the shape of a login a gate's key may end with: letters,
// digits, hyphens and underscores, as GitHub's logins are and a key may hold
// (human-gate.sh).
var followUpLogin = regexp.MustCompile(`^[A-Za-z0-9_][A-Za-z0-9_-]*$`)

// followUpKey is the human gate's key for the posts of the account login on one
// PR. An account GitHub no longer names, or a login of another shape, reads as
// unnamed.
func followUpKey(login string) string {
	if !followUpLogin.MatchString(login) {
		login = "unnamed"
	}
	return followUpKeyPrefix + strings.ToLower(login)
}

// followUpMessage is the gate's message for the posts of login on PR number in
// repo, first seen at url: a first line the board titles the gate with, then
// what the city did, where the operator reads the posts, and how to clear it.
func followUpMessage(repo string, number int, login, url string) string {
	who := login
	if who == "" {
		who = "an account GitHub no longer names"
	}
	return fmt.Sprintf("Posts by %s on %s#%d are held from the city's agents\n\n"+
		"%s is not an owner, a member or a collaborator of %s, so each of its posts on PR #%d reaches the city's "+
		"agents only as a placeholder, and none of them is an ask. Read them on GitHub, starting at %s. To have "+
		"the city act on what one says, say it in a post of your own on the PR. Clear this gate once you have "+
		"read them: a later post by the account files a new one.", who, repo, number, who, repo, number, url)
}

// FollowUp files the operator's follow-up on subject, the bead that owns PR
// number in repo, for each account among held, once: a human gate under the
// account's key (followUpKey), or the one open there. An error names each
// account whose gate did not file, and the rest are filed.
func FollowUp(ctx context.Context, g Gates, subject, repo string, number int, held []quote.Held) error {
	if g == nil {
		return errors.New("nothing files human gates here")
	}
	seen := map[string]bool{}
	var failed []string
	for _, h := range held {
		key := followUpKey(h.Author)
		if seen[key] {
			continue
		}
		seen[key] = true
		if err := g.File(ctx, subject, key, followUpMessage(repo, number, h.Author, h.URL)); err != nil {
			failed = append(failed, err.Error())
		}
	}
	if len(failed) > 0 {
		return fmt.Errorf("the follow-up of a held post did not file: %s", strings.Join(failed, "; "))
	}
	return nil
}

// Marker leaves a reaction on a post, named by its node id, as the take marks
// a post it took.
type Marker interface {
	AddReaction(subject, content string) error
}

// Owed is each post among held that carries neither of the city's marks, so
// its follow-up is still to file: a post the take or a read followed up
// carries takenMark.
func Owed(held []quote.Held) []quote.Held {
	var out []quote.Held
	for _, h := range held {
		if !slices.Contains(h.Reactions, takenMark) && !slices.Contains(h.Reactions, handledMark) {
			out = append(out, h)
		}
	}
	return out
}

// FollowUpHeld files the follow-up a read owes the posts its quote held on PR
// number in repo, on subject, the bead that owns the PR, as the take files it
// for a held post it takes. Each post still owed one (Owed) is followed up
// under its account's key, through one gate per account, and once that gate is
// filed or found open the post is marked with takenMark through m. A post whose
// gate did not file is not marked, so the mark never stands without its
// follow-up. An error names each account whose gate did not file and each post
// whose mark did not land, and the rest are filed and marked.
func FollowUpHeld(ctx context.Context, g Gates, m Marker, subject, repo string, number int, held []quote.Held) error {
	if g == nil || m == nil {
		return errors.New("nothing files human gates or marks posts here")
	}
	byKey := map[string][]quote.Held{}
	var keys []string
	for _, h := range Owed(held) {
		key := followUpKey(h.Author)
		if _, ok := byKey[key]; !ok {
			keys = append(keys, key)
		}
		byKey[key] = append(byKey[key], h)
	}
	var failed []string
	for _, key := range keys {
		posts := byKey[key]
		if err := g.File(ctx, subject, key, followUpMessage(repo, number, posts[0].Author, posts[0].URL)); err != nil {
			failed = append(failed, fmt.Sprintf("the gate under %s did not file: %v", key, err))
			continue
		}
		for _, h := range posts {
			if err := mark(m, h.Node); err != nil {
				failed = append(failed, fmt.Sprintf("the gate under %s stands, and the city's %s did not land on %s: %v",
					key, takenMark, h.URL, err))
			}
		}
	}
	if len(failed) > 0 {
		return fmt.Errorf("the follow-up of a held post did not complete: %s", strings.Join(failed, "; "))
	}
	return nil
}

// mark leaves takenMark on the post whose node id is node through m.
func mark(m Marker, node string) error {
	if strings.TrimSpace(node) == "" {
		return errors.New("GitHub named no node id for it")
	}
	return m.AddReaction(node, takenMark)
}

// OwnerOf is the bead a held post's follow-up on the PR at url lands on: the
// one live bead that owns the PR (ownersIn), else a closed bead whose record
// named it in pr_url and that is no other bead's child, read through l, and ""
// when the store holds neither. The board shows a gate on a closed bead as it
// shows any other.
func OwnerOf(l *ledger.Ledger, url string) (string, error) {
	host, repo, number, ok := record.ParseURL(url)
	if !ok {
		return "", fmt.Errorf("%q names no pull request", url)
	}
	owners, err := ownersIn(l)
	if err != nil {
		return "", err
	}
	o, err := one(owners[identity(host, repo, number)], url)
	if err != nil || o.id != "" {
		return o.id, err
	}
	rows, err := l.Find(record.NamedIn(url))
	if err != nil {
		return "", err
	}
	slices.SortFunc(rows, func(a, b *ledger.Record) int { return strings.Compare(a.ID, b.ID) })
	for _, r := range rows {
		if parent, _, err := anchorKey.Get(r); err == nil && (strings.TrimSpace(parent) == "" || parent == r.ID) {
			return r.ID, nil
		}
	}
	return "", nil
}
