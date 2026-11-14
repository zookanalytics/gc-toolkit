package review

import (
	"errors"
	"fmt"
	"os"
	"regexp"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
)

// The check index. An index is a review-checks.toml that declares each check's
// name, one line of purpose, and the phase it gates. A rig's effective index
// has two layers:
//
//   - The pack's index, the review-checks.toml at the root of the pack. It
//     declares every check the pack ships a skill for, so every rig gets every
//     one of them.
//   - The rig's index, the review-checks.toml the commit a caller judges
//     carries. It is optional. A row for a check the pack declares changes that
//     check's purpose or phase, key by key, and a key it leaves out or leaves
//     empty keeps the pack's value. A row for any other check adds a check of
//     the rig's own.
//
// A caller names the commit it judges, and the rig's rows come from that commit
// and from nowhere else. An index named outright stands in for both layers.
//
// The index declares mechanical facts only. When a check applies to a given
// diff is a judgment its method states in prose. A check's method is the
// skill named from the check, so an older index's method key is not read.

// The phases, in the order of the stage transitions they gate. A check that
// reads only the diff is pre-open, and one that needs the deployed preview is
// open-as-draft.
var phases = []string{"pre-open", "open-as-draft", "ready-for-review", "merge"}

// PhaseRank is the position of phase among the phases, from 1, and 0 for a
// value that is not a phase.
func PhaseRank(phase string) int {
	return slices.Index(phases, phase) + 1
}

// Phases is every phase, in order, for a message that names them.
func Phases() string { return strings.Join(phases, "|") }

// Check is one row of an index: the check's name as the index writes it, its
// purpose, and the phase it declares, "" when it declares none.
type Check struct {
	Name, Purpose, Phase string
}

// checkName is the name a check's table and a guidance file take.
var checkName = regexp.MustCompile(`^[A-Za-z0-9_-]+$`)

// ValidName reports whether name can name a check.
func ValidName(name string) bool { return checkName.MatchString(name) }

// A check's table header, and a key line the grammar reads.
var (
	checkHeader = regexp.MustCompile(`^\s*\[checks\.([A-Za-z0-9_-]+)\]\s*$`)
	keyLine     = regexp.MustCompile(`^\s*(purpose|phase)\s*=`)
)

// Parse reads index text into its rows, in the grammar every index is written
// in, a minimal subset of TOML: table headers, `key = "value"` lines, `#`
// comments and blank lines. A check is a [checks.<name>] table, and its purpose
// and phase keys are the ones read, the last line of each standing. A value is
// the text after the line's first `=`, trimmed, with one surrounding double
// quote stripped from each end. Any other table ends the check before it, so a
// key outside a [checks.*] table is never read into a check.
func Parse(text string) []Check {
	var out []Check
	var cur *Check
	flush := func() {
		if cur != nil {
			out = append(out, *cur)
		}
		cur = nil
	}
	for _, line := range strings.Split(text, "\n") {
		trimmed := strings.TrimSpace(line)
		switch {
		case strings.HasPrefix(trimmed, "#"):
			continue
		case strings.HasPrefix(trimmed, "["):
			flush()
			if m := checkHeader.FindStringSubmatch(line); m != nil {
				cur = &Check{Name: m[1]}
			}
			continue
		case cur == nil:
			continue
		}
		m := keyLine.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		_, v, _ := strings.Cut(line, "=")
		v = strings.TrimSpace(v)
		v = strings.TrimPrefix(v, `"`)
		v = strings.TrimSuffix(v, `"`)
		if m[1] == "purpose" {
			cur.Purpose = v
		} else {
			cur.Phase = v
		}
	}
	flush()
	return out
}

// Overlay lays a rig's rows over the pack's. Within a layer the first row for a
// name stands, a name compared without case. A rig row for a pack check
// replaces each key it gives a value and keeps the pack's name. Any other rig
// row is added, so the pack's checks come first in the pack's order and the
// rig's own follow in the rig's.
func Overlay(pack, rig []Check) []Check {
	var out []Check
	at := map[string]int{}
	for _, c := range pack {
		k := strings.ToLower(c.Name)
		if _, seen := at[k]; seen || c.Name == "" {
			continue
		}
		at[k] = len(out)
		out = append(out, c)
	}
	seenRig := map[string]bool{}
	for _, c := range rig {
		k := strings.ToLower(c.Name)
		if seenRig[k] || c.Name == "" {
			continue
		}
		seenRig[k] = true
		if i, ok := at[k]; ok {
			if c.Purpose != "" {
				out[i].Purpose = c.Purpose
			}
			if c.Phase != "" {
				out[i].Phase = c.Phase
			}
			continue
		}
		at[k] = len(out)
		out = append(out, c)
	}
	return out
}

// IndexSources are where an index is read. Named is an index named outright,
// which stands in for both layers. Otherwise Pack is the path of the pack's
// review-checks.toml, and Repos the repositories a commit is looked for in, in
// order: the checkout the caller runs in, then the rig's.
type IndexSources struct {
	Named string
	Pack  string
	Repos []string
}

// Index is an effective index: its rows, and what was read for them, "" when
// nothing was.
type Index struct {
	Checks []Check
	Source string
}

// ErrNoCommit is the error of a read that names no commit where it must.
var ErrNoCommit = errors.New("no commit named")

// ReadIndex reads the effective index at the commit at: the index named
// outright when src names one, else the pack's rows with the rows at carries
// laid over them. A named index that does not read reads as no index at all. A
// commit no repository holds or can fetch, a call with no repository to read
// it in, and a rig index at a readable commit that does not read are errors,
// since resolving under the pack's rows alone would hand a rig the pack's
// phases in place of its own.
func ReadIndex(src IndexSources, at string) (Index, error) {
	if src.Named != "" {
		raw, err := os.ReadFile(src.Named)
		if err != nil {
			return Index{}, nil
		}
		return Index{Checks: Parse(string(raw)), Source: src.Named}, nil
	}
	if at == "" {
		return Index{}, ErrNoCommit
	}
	var ix Index
	var pack []Check
	if src.Pack != "" {
		if raw, err := os.ReadFile(src.Pack); err == nil {
			pack = Parse(string(raw))
			ix.Source = src.Pack
		}
	}
	repo, err := commitRepo(src.Repos, at, "the rig's rows at that commit are unreadable")
	if err != nil {
		return Index{}, err
	}
	text, held, err := git.FileAt(repo, at, "review-checks.toml")
	if err != nil {
		return Index{}, fmt.Errorf("%s:review-checks.toml is there but would not read: %w", at, err)
	}
	var rig []Check
	if held {
		rig = Parse(text)
		if ix.Source != "" {
			ix.Source += " + "
		}
		ix.Source += at + ":review-checks.toml"
	}
	ix.Checks = Overlay(pack, rig)
	return ix, nil
}

// Repos is the repositories among dirs a commit is looked for in, in order,
// each once by the object store it reads, so a commit missing from one store is
// fetched into it once. A dir that is no repository is left out.
func Repos(dirs ...string) []string {
	var out, stores []string
	for _, d := range dirs {
		if d == "" {
			continue
		}
		top, ok := git.Toplevel(d)
		if !ok {
			continue
		}
		store, err := git.Store(top)
		if err != nil {
			store = top
		}
		if slices.Contains(stores, store) {
			continue
		}
		out = append(out, top)
		stores = append(stores, store)
	}
	return out
}

// commitRepo is the repository among repos that holds the commit at names. A
// commit pushed since a checkout last fetched is not there yet, so a full
// commit id none holds is fetched from origin by its id, into each repository
// in turn until one holds it, rather than some other commit's file read for it.
// unread says what goes unread when no repository can be read at all.
func commitRepo(repos []string, at, unread string) (string, error) {
	if len(repos) == 0 {
		return "", fmt.Errorf("no repository here to read '%s' from (no checkout toplevel, GC_RIG_ROOT unset), so %s", at, unread)
	}
	for _, r := range repos {
		if git.HasCommit(r, at) {
			return r, nil
		}
	}
	if git.IsObjectID(at) {
		for _, r := range repos {
			if git.FetchCommit(r, at) == nil && git.HasCommit(r, at) {
				return r, nil
			}
		}
	}
	return "", fmt.Errorf("commit '%s' is in no repository here and could not be fetched from origin; the rig's files at that commit are unreadable", at)
}

// PhaseOf is the phase every reader takes a row to gate: a missing phase is
// pre-open, with a warning, and a phase outside the ordered set is an error,
// so no reader guesses one.
func (ix Index) PhaseOf(c Check) (phase, warning string, err error) {
	if c.Phase == "" {
		return "pre-open", fmt.Sprintf("check '%s' is declared with no phase (%s); defaulting to pre-open", c.Name, ix.Source), nil
	}
	if PhaseRank(c.Phase) == 0 {
		return "", "", fmt.Errorf("check '%s' declares phase '%s', which is not a phase (%s), in %s; fix the index",
			c.Name, c.Phase, Phases(), ix.Source)
	}
	return c.Phase, "", nil
}

// Lookup is the row the index declares for name, compared without case.
func (ix Index) Lookup(name string) (Check, bool) {
	for _, c := range ix.Checks {
		if strings.EqualFold(c.Name, name) {
			return c, true
		}
	}
	return Check{}, false
}

// Row is one check as a reader takes it: its name, its purpose and the phase
// it gates.
type Row struct {
	Name, Purpose, Phase string
}

// Rows is every row whose phase reads, with a warning for each row it took a
// default for and each row it left out, which names why.
func (ix Index) Rows() (rows []Row, warnings []string) {
	for _, c := range ix.Checks {
		phase, warn, err := ix.PhaseOf(c)
		if err != nil {
			warnings = append(warnings, err.Error())
			continue
		}
		if warn != "" {
			warnings = append(warnings, warn)
		}
		rows = append(rows, Row{Name: c.Name, Purpose: c.Purpose, Phase: phase})
	}
	return rows, warnings
}

// Gate is one check a check_set token names that gates a transition: the token
// as the set writes it, which names a lane, and the phase it gates at.
type Gate struct {
	Name, Phase string
}

// The check_set tokens that name no lane: none and off are the gateless
// sentinels, and approval is a merge rule. Resolve drops all three, so no
// transition re-derives the drop.
var nonLanes = []string{"none", "off", "approval"}

// Resolve is the checks in the check_set set that gate the transition through:
// every check whose phase is at or before it, each once by its name without
// case and in the case the set first writes it. A token the index does not
// declare, every token when nothing was read, gates at pre-open, the earliest
// phase and the one the old path dispatches at every stage, so the token always
// has a path to its review rather than a merge-only gate that could hold the
// merge with no review produced. A declared check whose phase is outside the
// ordered set is an error, so every caller holds its transition rather than
// guess. through must be a phase.
func (ix Index) Resolve(set, through string) (gates []Gate, warnings []string, err error) {
	rank := PhaseRank(through)
	if rank == 0 {
		return nil, nil, fmt.Errorf("'%s' is not a phase (%s)", through, Phases())
	}
	var seen []string
	for _, tok := range strings.Split(set, ",") {
		tok = strings.Join(strings.Fields(tok), "")
		low := strings.ToLower(tok)
		if tok == "" || slices.Contains(nonLanes, low) || slices.Contains(seen, low) {
			continue
		}
		seen = append(seen, low)
		c, ok := ix.Lookup(tok)
		if !ok {
			if ix.Source != "" {
				warnings = append(warnings, fmt.Sprintf("check '%s' is not declared in the index (%s); defaulting to pre-open", tok, ix.Source))
			}
			gates = append(gates, Gate{Name: tok, Phase: "pre-open"})
			continue
		}
		phase, warn, perr := ix.PhaseOf(c)
		if perr != nil {
			return nil, warnings, perr
		}
		if warn != "" {
			warnings = append(warnings, warn)
		}
		if PhaseRank(phase) <= rank {
			gates = append(gates, Gate{Name: tok, Phase: phase})
		}
	}
	if ix.Source == "" {
		warnings = append(warnings, "no readable check index (the pack's index, the commit's and any index named outright all came up empty); every non-sentinel token takes pre-open and gates every transition")
	}
	return gates, warnings, nil
}

// GuidancePath is the file a rig's guidance for check is in at a commit, the
// check's name folded to lowercase.
func GuidancePath(check string) string {
	return "docs/review-" + strings.ToLower(check) + ".md"
}

// Guidance is the rig's guidance for check at the commit at, the text of its
// GuidancePath there, "" when the commit carries none. The file exists only at
// a commit, so an index named outright never stands in for it.
func Guidance(src IndexSources, check, at string) (string, error) {
	if at == "" {
		return "", ErrNoCommit
	}
	path := GuidancePath(check)
	repo, err := commitRepo(src.Repos, at, path+" went unread")
	if err != nil {
		return "", err
	}
	text, _, err := git.FileAt(repo, at, path)
	if err != nil {
		return "", fmt.Errorf("%s:%s is there but would not read: %w", at, path, err)
	}
	return text, nil
}

// guidanceFile reports whether path is a file of a rig's review guidance: its
// index or one of its docs/review-<check>.md.
var guidanceFile = regexp.MustCompile(`^(review-checks\.toml|docs/review-[^/]*\.md)$`)

// GuidanceEdits is the rig's review guidance the change at the commit at edits:
// its index and each docs/review-*.md among the paths it touches from where it
// left base, as origin has base now. A rename counts at both of its paths, so
// a guidance file renamed away is an edit to it. base must be a branch name.
func GuidanceEdits(src IndexSources, base, at string) ([]string, error) {
	if at == "" {
		return nil, ErrNoCommit
	}
	repo, err := commitRepo(src.Repos, at, "the paths it touches went unread")
	if err != nil {
		return nil, err
	}
	// A base origin cannot answer for keeps the tip last fetched, the shell's
	// rule, and the merge base below fails when there is none.
	_ = git.FetchTip(repo, base)
	fork, err := git.MergeBase(repo, "refs/remotes/origin/"+base, at)
	if err != nil {
		return nil, fmt.Errorf("no fork point between origin/%s and %s reads: %w", base, at, err)
	}
	paths, err := git.ChangedPaths(repo, fork, at)
	if err != nil {
		return nil, fmt.Errorf("the paths from %s to %s did not read: %w", fork, at, err)
	}
	var out []string
	for _, p := range paths {
		if guidanceFile.MatchString(p) {
			out = append(out, p)
		}
	}
	return out, nil
}
