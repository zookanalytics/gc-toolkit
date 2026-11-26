package pr

import (
	"fmt"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
)

// Bringing a PR's branch current merges its target, as origin holds it, into
// the checkout of the branch. git merges from its own merge base, the newest
// commit the two share. When the target's history was rewritten after the
// branch last took it, such as by an upstream sync, that base falls before the
// whole of the old history the branch still carries, so the merge would take
// that history for the branch's own change: it would bring back what the
// rewrite dropped and conflict in files the branch never touched.
//
// So the merge goes from the commit of the target the branch took last. The
// clone's reflog of origin/<target> records each commit the target named,
// before and after each update, and those it no longer holds are its old
// history. Each whose merge base with HEAD is newer than git's own base gives
// a commit HEAD took from that history, and the one HEAD took last is the one
// its first-parent history took in latest, which the reflog's order cannot
// show once the target has gone back to an older history. HEAD's history must
// show it took nothing later: no merge after that commit took in a commit it
// does not hold, other than one that superseded an older history with it. A
// later commit of the target that git pruned from the reflog, or that the
// clone never fetched, shows there, and then the caller names the commit the
// branch took last, or nothing is merged. The merge takes a commit that
// supersedes it with the target: the target's tree whole, with the target and
// that commit as its parents, as `git merge -s ours` records a merge. git's own
// merge then goes from there, leaves a conflict in its merge state, and
// `git show --remerge-diff` on the merge shows only what was resolved by hand.
//
// With no such commit the target itself is merged, but only once the reflog
// shows that no commit the branch could have taken is missing from it. git
// prunes an update whose commits the ref no longer holds after
// gc.reflogExpireUnreachable, and a clone records nothing from before it was
// made. Where the reflog cannot show it, the caller names the commit the
// branch took last, or nothing is merged.

// BroughtCurrent is what bringing a checkout current with its target did.
type BroughtCurrent struct {
	// Target is the branch the checkout is brought current with, and Tip the
	// commit origin/<Target> names once fetched.
	Target, Tip string
	// Held is true when HEAD already held Tip, so nothing was merged.
	Held bool
	// Default is git's merge base of HEAD and Tip. Base is the commit the merge
	// goes from: Default, or the commit of the target's old history the branch
	// took last, which Supersede, the commit made for the merge, supersedes
	// with Tip.
	Default, Base, Supersede string
	// Message is the merge's message. Head is the checkout's HEAD once git
	// made the merge, and Conflicts lists the paths git left unmerged when it
	// stopped instead.
	Message, Head string
	Conflicts     []string
}

// CurrentRefusal is a checkout BringCurrent does not merge into, which it
// leaves as it was.
type CurrentRefusal struct{ Why string }

func (r *CurrentRefusal) Error() string { return r.Why }

// BringCurrent fetches target from origin and merges it into the checkout dir
// sits in, from the commit of the target the branch took last when the
// target was rewritten after that. base names that commit by its full object
// name, and "" has the clone's reflog find it. It refuses a checkout that
// holds work no commit holds, or is in the middle of an operation git stopped,
// a HEAD that shares no history with the target, a reflog that cannot show
// the commit when base is "", and a base that HEAD does not hold or that does
// not hold git's merge base. An error is a git call that did not answer or
// failed, and a merge stopped on a conflict is not one: its Conflicts are left
// in git's merge state for a person to resolve.
func BringCurrent(dir, target, base string) (*BroughtCurrent, error) {
	co, err := git.Open(dir)
	if err != nil {
		return nil, err
	}
	if op, err := git.InProgress(co.Top); err != nil {
		return nil, err
	} else if op != "" {
		return nil, &CurrentRefusal{Why: fmt.Sprintf("the checkout is in the middle of a %s: finish it or abort it first", op)}
	}
	if dirty, err := co.Dirty(); err != nil {
		return nil, err
	} else if dirty != "" {
		return nil, &CurrentRefusal{Why: "the checkout holds work no commit holds, which a merge could take in or lose:\n" + dirty}
	}
	if err := git.FetchTip(co.Top, target); err != nil {
		return nil, err
	}
	tip, err := git.Tip(co.Top, target)
	if err != nil {
		return nil, err
	}
	cur := &BroughtCurrent{Target: target, Tip: tip}
	if cur.Held, err = git.IsAncestor(co.Top, tip, co.Commit); err != nil {
		return nil, err
	} else if cur.Held {
		return cur, nil
	}
	def, ok, err := git.CommonBase(co.Top, co.Commit, tip)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, &CurrentRefusal{Why: fmt.Sprintf("HEAD shares no history with origin/%s", target)}
	}
	cur.Default, cur.Base = def, def
	if base == "" {
		if base, err = fromReflog(co.Top, target, co.Commit, tip, def); err != nil {
			return nil, err
		}
	} else if base, err = given(co.Top, base, co.Commit, tip, def); err != nil {
		return nil, err
	}
	from := tip
	if base != "" {
		tree, err := git.TreeOf(co.Top, tip)
		if err != nil {
			return nil, err
		}
		if cur.Supersede, err = git.CommitTree(co.Top, tree, []string{tip, base}, supersedeMessage(target, tip, base)); err != nil {
			return nil, err
		}
		cur.Base, from = base, cur.Supersede
	}
	cur.Message = cur.mergeMessage()
	if cur.Conflicts, err = git.Merge(co.Top, from, cur.Message); err != nil {
		return nil, err
	} else if len(cur.Conflicts) > 0 {
		return cur, nil
	}
	after, err := git.Open(co.Top)
	if err != nil {
		return nil, err
	}
	cur.Head = after.Commit
	return cur, nil
}

// fromReflog is the commit of the target's old history that head took last,
// as the clone's reflog of origin/<target> shows it, and "" when the reflog
// shows the target was not rewritten after head took it. A reflog that shows
// neither is a refusal, and so is a commit head's history shows it took a
// later one after.
func fromReflog(dir, target, head, tip, def string) (string, error) {
	updates, err := git.Reflog(dir, target)
	if err != nil {
		return "", err
	}
	base, err := lastTaken(dir, updates, head, tip, def)
	if err != nil {
		return "", err
	}
	if base != "" {
		if err := shownLast(dir, target, base, head, def); err != nil {
			return "", err
		}
		return base, nil
	}
	whole, err := reachesBefore(dir, updates, tip, def)
	if err != nil {
		return "", err
	}
	if !whole {
		return "", &CurrentRefusal{Why: fmt.Sprintf("the clone's reflog of origin/%[1]s does not reach back to before "+
			"%[1]s held %[2]s, git's merge base with HEAD. So it cannot show whether %[1]s was rewritten after this "+
			"branch last took it, and a merge from %[2]s would take any old history of %[1]s the branch still carries "+
			"for its own change.\nRun it again with --base <commit>, the full object name of the commit of %[1]s the "+
			"branch took last: the second parent of the branch's newest merge of %[1]s, or the commit the branch was "+
			"cut from when it never merged %[1]s.", target, def)}
	}
	return "", nil
}

// shownLast refuses base, the commit of the target's old history the reflog
// gives as the one head took last, unless head's own history shows it: each
// merge of head's first-parent history newer than def, git's merge base of head
// and the tip, that holds base took in only what base holds, or base through a
// commit that supersedes, which has base as its first parent and base's tree.
// A merge that took in more took a later commit of the target, which the
// reflog does not name.
func shownLast(dir, target, base, head, def string) error {
	merges, err := git.Merges(dir, head, def)
	if err != nil {
		return err
	}
	for _, m := range merges {
		if holds, err := git.IsAncestor(dir, base, m.Commit); err != nil {
			return err
		} else if !holds {
			break
		}
		for _, p := range m.TookIn {
			ok, err := takesNoMore(dir, p, base)
			if err != nil {
				return err
			}
			if !ok {
				return &CurrentRefusal{Why: fmt.Sprintf("the clone's reflog of origin/%[1]s gives %[2]s as the commit of %[1]s "+
					"this branch took last, but HEAD's merge %[3]s took in %[4]s, which %[2]s does not hold. So the branch "+
					"took a later commit of %[1]s, which git pruned from the reflog or the clone never fetched, and a "+
					"merge from %[2]s would take what the branch took with it for its own change.\nRun it again with "+
					"--base <commit>, the full object name of the commit of %[1]s the branch took last: the second parent "+
					"of the branch's newest merge of %[1]s.", target, base, m.Commit, p)}
			}
		}
	}
	return nil
}

// takesNoMore reports whether p, a commit a merge took in, holds nothing base
// does not: base holds it, or it supersedes base, with base as its first
// parent and base's tree.
func takesNoMore(dir, p, base string) (bool, error) {
	if held, err := git.IsAncestor(dir, p, base); err != nil || held {
		return held, err
	}
	parents, err := git.Parents(dir, p)
	if err != nil || len(parents) == 0 || parents[0] != base {
		return false, err
	}
	pt, err := git.TreeOf(dir, p)
	if err != nil {
		return false, err
	}
	bt, err := git.TreeOf(dir, base)
	return err == nil && pt == bt, err
}

// reachesBefore reports whether updates, the reflog's, hold every commit the
// target has named since before it held def, git's merge base of HEAD and
// tip. Read back from the newest, which names tip, while each update starts
// at the commit the one before it ended at, they must reach the ref's making
// or a commit that did not hold def yet. git leaves the old name of an update
// as it was when it prunes the update before it, so a stretch it pruned breaks
// the chain.
func reachesBefore(dir string, updates []git.RefUpdate, tip, def string) (bool, error) {
	if len(updates) == 0 || updates[0].New != tip {
		return false, nil
	}
	k := 0
	for k+1 < len(updates) && updates[k].Old == updates[k+1].New {
		k++
	}
	start := updates[k].Old
	if git.IsNull(start) {
		return true, nil
	}
	held, err := git.IsAncestor(dir, def, start)
	return !held, err
}

// given checks base, the commit of the target the caller says head took
// last: head holds it, and it holds def, git's merge base of head and tip. It
// is "" when tip holds it too, since then the target was not rewritten after
// it and git's own base is the one to merge from.
func given(dir, base, head, tip, def string) (string, error) {
	if !git.IsObjectID(base) || !git.HasCommit(dir, base) {
		return "", &CurrentRefusal{Why: fmt.Sprintf("--base names %q, which is not the full object name of a commit the clone holds", base)}
	}
	if in, err := git.IsAncestor(dir, base, head); err != nil {
		return "", err
	} else if !in {
		return "", &CurrentRefusal{Why: fmt.Sprintf("--base names %s, which HEAD does not hold, so the branch never took it", base)}
	}
	if holds, err := git.IsAncestor(dir, def, base); err != nil {
		return "", err
	} else if !holds {
		return "", &CurrentRefusal{Why: fmt.Sprintf("--base names %s, which does not hold %s, the newest commit HEAD shares "+
			"with the target, so the branch took a later commit of the target than it", base, def)}
	}
	held, err := git.IsAncestor(dir, base, tip)
	if err != nil || held {
		return "", err
	}
	return base, nil
}

// lastTaken is the commit of the target's old history that head took last,
// "" when updates show none. Of the commits they name, before and after each
// update, those tip no longer holds are the target's old history, and each
// whose merge base with head is newer than def, git's merge base of head and
// tip, gives a commit head took from it. A branch that took tip's history
// after a rewrite has def there, so what it took before the rewrite is not
// newer. Of several, latest gives the one head took last.
func lastTaken(dir string, updates []git.RefUpdate, head, tip, def string) (string, error) {
	var named []string
	seen := map[string]bool{}
	for _, u := range updates {
		for _, c := range []string{u.New, u.Old} {
			if !seen[c] && !git.IsNull(c) {
				seen[c] = true
				named = append(named, c)
			}
		}
	}
	old, err := git.NotHeld(dir, named, tip)
	if err != nil {
		return "", err
	}
	var taken []string
	judged := map[string]bool{}
	for _, o := range old {
		mb, ok, err := git.CommonBase(dir, head, o)
		if err != nil {
			return "", err
		}
		if !ok || mb == def || judged[mb] {
			continue
		}
		judged[mb] = true
		if newer, err := git.IsAncestor(dir, def, mb); err != nil {
			return "", err
		} else if newer {
			taken = append(taken, mb)
		}
	}
	switch len(taken) {
	case 0:
		return "", nil
	case 1:
		return taken[0], nil
	}
	return latest(dir, taken, head, def)
}

// latest is the one of taken, commits head took from the target, that head's
// first-parent history took in last: the one held by the fewest of its
// commits newer than def, since each of them holds all that the one before it
// holds. Of two that one commit took in, the one that holds the other is the
// later. Taken that this leaves unordered is a refusal.
func latest(dir string, taken []string, head, def string) (string, error) {
	line, err := git.FirstParents(dir, head, def)
	if err != nil {
		return "", err
	}
	best, fewest := "", -1
	var tied []string
	for _, c := range taken {
		n, err := holders(dir, line, c)
		if err != nil {
			return "", err
		}
		switch {
		case fewest < 0 || n < fewest:
			best, fewest, tied = c, n, nil
		case n == fewest:
			tied = append(tied, c)
		}
	}
	for _, c := range tied {
		if later, err := git.IsAncestor(dir, best, c); err != nil {
			return "", err
		} else if later {
			best = c
			continue
		}
		if earlier, err := git.IsAncestor(dir, c, best); err != nil {
			return "", err
		} else if !earlier {
			return "", &CurrentRefusal{Why: fmt.Sprintf("HEAD took %s and %s from histories of the target its own "+
				"history does not order, so it cannot show which it took last.\nRun it again with --base <commit>, the "+
				"full object name of the commit of the target the branch took last.", best, c)}
		}
	}
	return best, nil
}

// holders counts the commits of line, a first-parent history newest first,
// that hold c. Each holds what the one after it holds, so the count is found
// by halving.
func holders(dir string, line []string, c string) (int, error) {
	lo, hi := 0, len(line)
	for lo < hi {
		mid := (lo + hi) / 2
		holds, err := git.IsAncestor(dir, c, line[mid])
		if err != nil {
			return 0, err
		}
		if holds {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return lo, nil
}

// abbrev is the abbreviation a message names a commit by.
func abbrev(id string) string { return id[:min(len(id), 12)] }

func (c *BroughtCurrent) mergeMessage() string {
	subject := fmt.Sprintf("Merge origin/%s at %s", c.Target, abbrev(c.Tip))
	if c.Supersede == "" {
		return subject + "\n"
	}
	return subject + " from " + abbrev(c.Base) + "\n\n" + fill(fmt.Sprintf(
		"origin/%[1]s was rewritten after this branch last took it, at %[2]s. "+
			"Merged from git's own merge base, %[3]s, the old history the branch "+
			"still carries would count as its own change. So this merge takes "+
			"%[4]s, which supersedes %[2]s with %[5]s and carries its tree, and "+
			"git merges from %[2]s: the merge changes the branch only by what "+
			"changed from %[2]s to %[5]s, and git show --remerge-diff on it shows "+
			"only what was resolved by hand.",
		c.Target, abbrev(c.Base), abbrev(c.Default), abbrev(c.Supersede), abbrev(c.Tip)))
}

func supersedeMessage(target, tip, base string) string {
	return fmt.Sprintf("Supersede %s with origin/%s at %s\n\n", abbrev(base), target, abbrev(tip)) + fill(fmt.Sprintf(
		"origin/%[1]s no longer holds %[2]s, which this branch took from it "+
			"before its history was rewritten. This commit carries the tree of "+
			"%[3]s whole and has %[2]s as its second parent, as git merge -s ours "+
			"records a merge, so a merge that takes it goes from %[2]s. Its own "+
			"git show --remerge-diff is the rewrite: read the merge that takes it.",
		target, abbrev(base), abbrev(tip)))
}

// fill wraps a paragraph at 72 columns, ending it with a newline.
func fill(text string) string {
	var b strings.Builder
	width := 0
	for _, w := range strings.Fields(text) {
		switch {
		case width == 0:
		case width+1+len(w) > 72:
			b.WriteString("\n")
			width = 0
		default:
			b.WriteString(" ")
			width++
		}
		b.WriteString(w)
		width += len(w)
	}
	return b.String() + "\n"
}
