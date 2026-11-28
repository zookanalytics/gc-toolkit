package pr

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/quote"
)

// A held post's follow-up. The quote holds a post by an account outside a
// repository the city's account can push to (services/gctk/quote), so no agent
// reads its text, and the operator learns of it through one human gate per
// account per PR, on the bead that owns the PR. The board shows an open gate as
// a question, and on an open bead the gate holds the PR's merge until the
// operator clears it. human-gate.sh files one open gate per bead and key, so
// the take and every reader of the PR file it once, and a later post by the
// same account while it is open is one its message covers.

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
