package pr

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/quote"
)

// A held post's follow-up. The quote holds a post by an account outside a
// repository the city's account can push to (services/gctk/quote), so no agent
// reads its text, and the operator learns of it through one human gate per
// account per item, on the bead that owns the PR, and for an issue or a PR no
// bead owns on a finding of its own for the item (FollowUpSubject). The board
// shows an open gate as a question, and on an open bead the gate holds the PR's
// merge until the operator clears it. It is the one hold a held post puts on
// the PR, since a review thread is weighed without its held posts (threadsOf).
// Every filer of a follow-up, the take and each reader of the item, decides and
// files under the store's record lock, and decides on the posts' marks as
// GitHub holds them then, so no two filers file for one post. human-gate.sh
// files one open gate per bead and key, so a later post by the same account
// while that gate is open is one its message covers. Once its gate is filed or
// found open, the post takes the take's mark, so no later filer files a gate
// for it again after the operator clears the one it has.

// followUpKeyPrefix opens the key of a held post's human gate, which the
// account's login, lower-cased, ends.
const followUpKeyPrefix = "outside-post-"

// followUpLogin is the shape of a login a gate's key may end with: letters,
// digits, hyphens and underscores, as GitHub's logins are and a key may hold
// (human-gate.sh).
var followUpLogin = regexp.MustCompile(`^[A-Za-z0-9_][A-Za-z0-9_-]*$`)

// followUpKey is the human gate's key for the posts of the account login on one
// item. An account GitHub no longer names, or a login of another shape, reads
// as unnamed.
func followUpKey(login string) string {
	if !followUpLogin.MatchString(login) {
		login = "unnamed"
	}
	return followUpKeyPrefix + strings.ToLower(login)
}

// followUpMessage is the gate's message for the posts of login on item number
// in repo, a PR when pull is true and an issue otherwise, first seen at url: a
// first line the board titles the gate with, then what the city did, where the
// operator reads the posts, and how to clear it.
func followUpMessage(repo string, number int, pull bool, login, url string) string {
	who := login
	if who == "" {
		who = "an account GitHub no longer names"
	}
	item := "issue"
	if pull {
		item = "PR"
	}
	return fmt.Sprintf("Posts by %s on %s#%d are held from the city's agents\n\n"+
		"%s is not an owner, a member or a collaborator of %s, so each of its posts on %s #%d reaches the city's "+
		"agents only as a placeholder, and none of them is an ask. Read them on GitHub, starting at %s. To have "+
		"the city act on what one says, say it in a post of your own on the %s. Clear this gate once you have "+
		"read them: a later post by the account files a new one.", who, repo, number, who, repo, item, number, url,
		item)
}

// Findings files a patrol finding under a key, through patrol-finding.sh, which
// keeps one live finding for each key, and returns the id of the finding it
// filed or found live there.
type Findings interface {
	File(ctx context.Context, key, title, message string) (string, error)
}

// findingKey is the key of the finding that holds the follow-up for the item
// number in repo, owner/name, when no bead owns it: one finding for each item.
func findingKey(repo string, number int) string {
	return fmt.Sprintf("outside-posts.%s.%d", strings.ReplaceAll(repo, "/", "."), number)
}

// FollowUpSubject is the bead the follow-up for the held posts on item number
// in repo, at url, goes on: on a PR, the bead that owns it in l (OwnerOf), and
// for an issue, or a PR no bead owns, a finding of its own for the item, filed
// through f under findingKey, or the live one there, so that no held post goes
// without a question the board shows. Nothing waits on such a finding, and
// once the operator clears each gate on it, its message leaves an agent
// nothing to do.
func FollowUpSubject(ctx context.Context, l *ledger.Ledger, f Findings, repo string, number int, pull bool,
	url string) (string, error) {
	item := "issue"
	if pull {
		item = "PR"
		bead, err := OwnerOf(l, url)
		if err != nil || bead != "" {
			return bead, err
		}
	}
	if f == nil {
		return "", errors.New("nothing files a finding here")
	}
	title := fmt.Sprintf("Posts by outside accounts on %s#%d are held from the city's agents", repo, number)
	message := fmt.Sprintf("An agent of the city read %s, and no bead owns the %s, so this finding holds the "+
		"operator's follow-up for the posts there by accounts that are not owners, members or collaborators of %s. "+
		"Each such account has a human gate on this finding under the key %s<login>, whose message says where to "+
		"read its posts. No agent reads their text, so once the operator clears each gate nothing is left for an "+
		"agent to do here.", url, item, repo, followUpKeyPrefix)
	return f.File(ctx, findingKey(repo, number), title, message)
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
		if err := g.File(ctx, subject, key, followUpMessage(repo, number, true, h.Author, h.URL)); err != nil {
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
// its follow-up is still to file as far as the read that held it saw: a post
// the take or a read followed up carries takenMark.
func Owed(held []quote.Held) []quote.Held {
	var out []quote.Held
	for _, h := range held {
		if !marked(h.Reactions) {
			out = append(out, h)
		}
	}
	return out
}

// marked is whether reactions, the reactions the city's account left on a
// post, hold either of the city's marks.
func marked(reactions []string) bool {
	return slices.Contains(reactions, takenMark) || slices.Contains(reactions, handledMark)
}

// stillOwed is each post among held that a follow-up is still owed for by
// current, the reactions the city's account has left on each post as GitHub
// holds them now, by node id: one current shows with neither of the city's
// marks. A post current does not hold owes none, since it was deleted, or its
// author's standing changed so that it is no longer held. A post GitHub named
// no node id for is owed one, since nothing shows whether the city marked it,
// and its mark then fails and says so.
func stillOwed(held []quote.Held, current map[string][]string) []quote.Held {
	var out []quote.Held
	for _, h := range held {
		reactions, ok := current[h.Node]
		if strings.TrimSpace(h.Node) == "" || (ok && !marked(reactions)) {
			out = append(out, h)
		}
	}
	return out
}

// FollowUpHeld files the follow-up a read owes the posts its quote held on item
// number in repo, a PR when pull is true and an issue otherwise, as the take
// files it for a held post it takes, and returns the bead it filed it on, ""
// when no post was owed one by then. It holds the record lock of the store
// whose .beads directory is dir, waiting for it up to wait, which the take
// holds for the whole of its act, and under the lock it quotes the item again
// through read, so it decides on each post as GitHub holds it then. A post
// another filer followed up since held was read carries takenMark there and
// owes nothing. For the posts still owed one (stillOwed) it asks subject for
// the bead their gates go on (FollowUpSubject), follows each up under its
// account's key, through one gate per account, and once that gate is filed or
// found open marks the post with takenMark through m. A post whose gate did not
// file is not marked, so the mark never stands without its follow-up. An error
// names each account whose gate did not file and each post whose mark did not
// land, and the rest are filed and marked.
func FollowUpHeld(ctx context.Context, dir string, wait time.Duration, g Gates, m Marker,
	read func() ([]quote.Held, error), subject func() (string, error), repo string, number int, pull bool,
	held []quote.Held) (string, error) {
	if g == nil || m == nil || read == nil || subject == nil {
		return "", errors.New("nothing files human gates, marks posts, reads them again or names their bead here")
	}
	release, err := record.Lock(dir, lockWait(ctx, wait))
	if err != nil {
		return "", fmt.Errorf("the follow-up of a held post did not take the record lock: %w", err)
	}
	defer release()
	now, err := read()
	if err != nil {
		return "", fmt.Errorf("the follow-up of a held post did not read the posts again: %w", err)
	}
	current := map[string][]string{}
	for _, h := range now {
		if strings.TrimSpace(h.Node) != "" {
			current[h.Node] = h.Reactions
		}
	}
	owed := stillOwed(held, current)
	if len(owed) == 0 {
		return "", nil
	}
	bead, err := subject()
	if err == nil && strings.TrimSpace(bead) == "" {
		err = errors.New("no bead was named for its gates")
	}
	if err != nil {
		return "", fmt.Errorf("the follow-up of a held post has no bead to go on: %w", err)
	}
	return bead, followUpOwed(ctx, g, m, bead, repo, number, pull, owed)
}

// followUpOwed files on subject the follow-up each post among owed is owed, one
// gate per account under its key, and marks each of the account's posts with
// takenMark through m once that gate is filed or found open. Its caller holds
// the record lock, and decided owed under it.
func followUpOwed(ctx context.Context, g Gates, m Marker, subject, repo string, number int, pull bool,
	owed []quote.Held) error {
	byKey := map[string][]quote.Held{}
	var keys []string
	for _, h := range owed {
		key := followUpKey(h.Author)
		if _, ok := byKey[key]; !ok {
			keys = append(keys, key)
		}
		byKey[key] = append(byKey[key], h)
	}
	var failed []string
	for _, key := range keys {
		posts := byKey[key]
		if err := g.File(ctx, subject, key, followUpMessage(repo, number, pull, posts[0].Author, posts[0].URL)); err != nil {
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
