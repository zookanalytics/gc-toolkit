package review_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

// The check index reads commits in scratch repositories, the git adapter's
// fake, with no config of the host's.

func gitEnv(t *testing.T) {
	t.Helper()
	cfg := filepath.Join(t.TempDir(), "gitconfig")
	if err := os.WriteFile(cfg, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	for k, v := range map[string]string{
		"GIT_CONFIG_GLOBAL": cfg, "GIT_CONFIG_NOSYSTEM": "1",
		"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com",
		"GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.com",
	} {
		t.Setenv(k, v)
	}
}

func run(t *testing.T, dir string, args ...string) string {
	t.Helper()
	out, err := exec.Command("git", append([]string{"-C", dir}, args...)...).CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

// commit writes files (path to text, "" removes it) and commits them,
// returning the commit.
func commit(t *testing.T, dir string, files map[string]string) string {
	t.Helper()
	for path, text := range files {
		full := filepath.Join(dir, path)
		if text == "" {
			run(t, dir, "rm", "-q", path)
			continue
		}
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
		run(t, dir, "add", path)
	}
	run(t, dir, "commit", "-q", "--allow-empty", "-m", "c")
	return run(t, dir, "rev-parse", "HEAD")
}

func newRepo(t *testing.T) string {
	t.Helper()
	gitEnv(t)
	dir := t.TempDir()
	run(t, dir, "init", "-q", "-b", "main")
	return dir
}

// packIndex is a pack's index, written to a file of its own.
func packIndex(t *testing.T) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "review-checks.toml")
	text := "[checks.correctness]\npurpose = \"PACK correctness\"\nphase = \"pre-open\"\n" +
		"[checks.triage]\npurpose = \"PACK triage\"\nphase = \"pre-open\"\n" +
		"[checks.demo]\npurpose = \"PACK demo\"\nphase = \"open-as-draft\"\n"
	if err := os.WriteFile(p, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func names(rows []review.Row) []string {
	var out []string
	for _, r := range rows {
		out = append(out, r.Name)
	}
	return out
}

// The grammar: a check is a [checks.<name>] table, an older index's method key
// is not read, a key outside a checks table is not a check, and an empty
// purpose stays empty.
func TestParseReadsChecksTablesAlone(t *testing.T) {
	got := review.Parse(`# a comment line, ignored
[checks.correctness]
method = "skills/review-correctness/SKILL.md"
purpose = "Is it = correct?"
phase = "pre-open"
  # an indented comment
[checks.bare]
phase = "merge"
[unrelated]
purpose = "not-a-check"
[checks.Security] # trailing text ends the table
purpose = "p"
`)
	want := []review.Check{
		{Name: "correctness", Purpose: "Is it = correct?", Phase: "pre-open"},
		{Name: "bare", Phase: "merge"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("Parse = %+v; want %+v", got, want)
	}
}

// A check is known by its name without case and keeps the name its index
// writes; a missing phase is pre-open with a warning; a phase outside the
// ordered set is refused, and Rows leaves its row out and names it.
func TestPhasesAndLookup(t *testing.T) {
	ix := review.Index{Source: "idx", Checks: review.Parse(
		"[checks.Security]\npurpose = \"p\"\nphase = \"pre-open\"\n[checks.old]\npurpose = \"o\"\n[checks.weird]\nphase = \"Merge\"\n")}
	c, ok := ix.Lookup("security")
	if !ok || c.Name != "Security" {
		t.Fatalf("Lookup(security) = %+v, %t; want the Security row", c, ok)
	}
	if phase, warn, err := ix.PhaseOf(review.Check{Name: "old"}); phase != "pre-open" || !strings.Contains(warn, "is declared with no phase") || err != nil {
		t.Fatalf("an unphased row reads %q, %q, %v; want pre-open with a warning", phase, warn, err)
	}
	if _, _, err := ix.PhaseOf(review.Check{Name: "weird", Phase: "Merge"}); err == nil || !strings.Contains(err.Error(), "declares phase 'Merge', which is not a phase") {
		t.Fatalf("a phase outside the set reads %v; want it refused", err)
	}
	rows, warnings := ix.Rows()
	if got := names(rows); !reflect.DeepEqual(got, []string{"Security", "old"}) {
		t.Fatalf("Rows = %v; want the two rows that read", got)
	}
	if len(warnings) != 2 || !strings.Contains(warnings[1], "check 'weird' declares phase 'Merge'") {
		t.Fatalf("Rows warned %q; want the default and the refused row", warnings)
	}
}

func gateNames(gs []review.Gate) []string {
	var out []string
	for _, g := range gs {
		out = append(out, g.Name+"\t"+g.Phase)
	}
	return out
}

// The resolver: the checks at or before the phase, the three non-lanes
// dropped, a token once by its name without case and in the case it is first
// written, an undeclared token at pre-open with a warning that names the index,
// and a declared phase outside the ordered set refused.
func TestResolve(t *testing.T) {
	ix := review.Index{Source: "idx", Checks: review.Parse(
		"[checks.correctness]\nphase = \"pre-open\"\n[checks.triage]\nphase = \"pre-open\"\n[checks.demo]\nphase = \"open-as-draft\"\n[checks.weird]\nphase = \"Merge\"\n")}
	for _, tc := range []struct {
		set, through string
		want         []string
	}{
		{"correctness,triage,demo", "pre-open", []string{"correctness\tpre-open", "triage\tpre-open"}},
		{"correctness,triage,demo", "open-as-draft", []string{"correctness\tpre-open", "triage\tpre-open", "demo\topen-as-draft"}},
		{"correctness, demo ,approval,none,off", "merge", []string{"correctness\tpre-open", "demo\topen-as-draft"}},
		{"Correctness,correctness,TRIAGE", "merge", []string{"Correctness\tpre-open", "TRIAGE\tpre-open"}},
		{"bogus", "merge", []string{"bogus\tpre-open"}},
		{"", "merge", nil},
		{"none,off,approval", "merge", nil},
	} {
		gates, warnings, err := ix.Resolve(tc.set, tc.through)
		if err != nil {
			t.Fatalf("Resolve(%q, %s): %v", tc.set, tc.through, err)
		}
		if got := gateNames(gates); !reflect.DeepEqual(got, tc.want) {
			t.Errorf("Resolve(%q, %s) = %q; want %q", tc.set, tc.through, got, tc.want)
		}
		if tc.set == "bogus" && (len(warnings) != 1 || !strings.Contains(warnings[0], "is not declared in the index (idx)")) {
			t.Errorf("an undeclared token warned %q", warnings)
		}
	}
	if _, _, err := ix.Resolve("weird", "merge"); err == nil {
		t.Error("a set naming a check whose phase is outside the ordered set resolved")
	}
	if _, _, err := ix.Resolve("correctness", "nonsense"); err == nil {
		t.Error("a transition that is not a phase resolved")
	}
	gates, warnings, err := review.Index{}.Resolve("correctness,demo,approval", "pre-open")
	if err != nil || !reflect.DeepEqual(gateNames(gates), []string{"correctness\tpre-open", "demo\tpre-open"}) {
		t.Errorf("with no index read, Resolve = %q, %v; want every lane token at pre-open", gateNames(gates), err)
	}
	if len(warnings) != 1 || !strings.Contains(warnings[0], "no readable check index") {
		t.Errorf("with no index read, Resolve warned %q", warnings)
	}
}

// The layered index at a commit: the pack's rows where the commit carries no
// index, never the working tree's; a rig row changes a pack check key by key
// and keeps its name; a rig row adds a check after the pack's; and an index
// named outright stands in for both layers.
func TestLayeredIndexAtACommit(t *testing.T) {
	rig := newRepo(t)
	noIndex := commit(t, rig, map[string]string{"README": "readme\n"})
	withIndex := commit(t, rig, map[string]string{
		"review-checks.toml": "[checks.Demo]\nmethod = \"m\"\nphase = \"pre-open\"\n[checks.ux]\npurpose = \"RIG ux\"\nphase = \"pre-open\"\n",
	})
	if err := os.WriteFile(filepath.Join(rig, "review-checks.toml"), []byte("[checks.wt]\npurpose = \"WORKTREE\"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	src := review.IndexSources{Pack: packIndex(t), Repos: review.Repos(rig)}

	ix, err := review.ReadIndex(src, noIndex)
	if err != nil {
		t.Fatal(err)
	}
	rows, _ := ix.Rows()
	if got := names(rows); !reflect.DeepEqual(got, []string{"correctness", "triage", "demo"}) {
		t.Fatalf("a commit with no index reads %v; want the pack's rows alone", got)
	}

	ix, err = review.ReadIndex(src, withIndex)
	if err != nil {
		t.Fatal(err)
	}
	rows, _ = ix.Rows()
	want := []review.Row{
		{Name: "correctness", Purpose: "PACK correctness", Phase: "pre-open"},
		{Name: "triage", Purpose: "PACK triage", Phase: "pre-open"},
		{Name: "demo", Purpose: "PACK demo", Phase: "pre-open"},
		{Name: "ux", Purpose: "RIG ux", Phase: "pre-open"},
	}
	if !reflect.DeepEqual(rows, want) {
		t.Fatalf("the layered index reads %+v; want %+v", rows, want)
	}
	if !strings.HasSuffix(ix.Source, withIndex+":review-checks.toml") {
		t.Errorf("the index names its source %q", ix.Source)
	}

	named := filepath.Join(t.TempDir(), "named.toml")
	if err := os.WriteFile(named, []byte("[checks.only]\nphase = \"merge\"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	ix, err = review.ReadIndex(review.IndexSources{Named: named, Pack: src.Pack}, "")
	if err != nil {
		t.Fatal(err)
	}
	if rows, _ := ix.Rows(); !reflect.DeepEqual(names(rows), []string{"only"}) {
		t.Fatalf("an index named outright reads %v; want its own rows alone", names(rows))
	}
	ix, err = review.ReadIndex(review.IndexSources{Named: filepath.Join(t.TempDir(), "absent.toml")}, "")
	if err != nil || ix.Source != "" || len(ix.Checks) != 0 {
		t.Fatalf("a named index that does not read reads %+v, %v; want no index", ix, err)
	}
	if _, err := review.ReadIndex(src, ""); err != review.ErrNoCommit {
		t.Fatalf("a read that names no commit and no index: %v; want ErrNoCommit", err)
	}
}

// A commit no repository holds is fetched from origin by its id, once into one
// store however many times it is named; one nothing can fetch fails; and no
// repository at all fails, so the pack's rows never answer alone.
func TestCommitsAreFetchedByIDOrRefused(t *testing.T) {
	origin := newRepo(t)
	commit(t, origin, map[string]string{"review-checks.toml": "[checks.ux]\npurpose = \"one\"\nphase = \"open-as-draft\"\n"})
	clone := filepath.Join(t.TempDir(), "clone")
	run(t, origin, "clone", "-q", origin, clone)
	moved := commit(t, origin, map[string]string{"review-checks.toml": "[checks.ux]\npurpose = \"two\"\nphase = \"pre-open\"\n"})
	worktree := filepath.Join(t.TempDir(), "wt")
	run(t, clone, "worktree", "add", "-q", "--detach", worktree)

	repos := review.Repos(clone, clone, worktree)
	if len(repos) != 1 {
		t.Fatalf("Repos named one store as %v; want it once", repos)
	}
	ix, err := review.ReadIndex(review.IndexSources{Repos: repos}, moved)
	if err != nil {
		t.Fatal(err)
	}
	if c, _ := ix.Lookup("ux"); c.Purpose != "two" {
		t.Fatalf("an unfetched head reads ux as %+v; want that head's row", c)
	}
	if out := run(t, clone, "cat-file", "-t", moved); out != "commit" {
		t.Fatalf("the clone holds %s as %q after the read; want it fetched", moved, out)
	}
	if _, err := review.ReadIndex(review.IndexSources{Repos: repos}, strings.Repeat("0123456789", 4)); err == nil ||
		!strings.Contains(err.Error(), "could not be fetched from origin") {
		t.Fatalf("a commit nothing can fetch read %v; want it refused", err)
	}
	_, err = review.ReadIndex(review.IndexSources{Pack: packIndex(t)}, moved)
	if err == nil || !strings.Contains(err.Error(), "the rig's rows at that commit are unreadable") {
		t.Fatalf("no repository here read %v; want it refused", err)
	}
}

// A rig's guidance is the docs/review-<check>.md its commit carries, its check
// folded to lowercase, nothing where it carries none; the guidance a change
// edits is its index and each docs/review-*.md it touches from where it left
// its base, a file renamed away included.
func TestGuidanceAndTheGuidanceAChangeEdits(t *testing.T) {
	origin := newRepo(t)
	base := commit(t, origin, map[string]string{"README": "r\n", "docs/review-pm.md": "PM\n"})
	clone := filepath.Join(t.TempDir(), "clone")
	run(t, origin, "clone", "-q", origin, clone)
	run(t, clone, "checkout", "-q", "-b", "work")
	commit(t, clone, map[string]string{
		"docs/review-arch.md": "ARCH-GUIDANCE-MARK\n\n", "review-checks.toml": "[checks.ux]\nphase = \"merge\"\n",
		"src/main.go": "package main\n",
	})
	run(t, clone, "mv", "docs/review-pm.md", "docs/pm-notes.md")
	at := commit(t, clone, nil)
	src := review.IndexSources{Repos: review.Repos(clone)}

	text, err := review.Guidance(src, "ARCH", at)
	if err != nil || strings.TrimRight(text, "\n") != "ARCH-GUIDANCE-MARK" {
		t.Fatalf("Guidance(ARCH) = %q, %v; want the commit's docs/review-arch.md", text, err)
	}
	if text, err := review.Guidance(src, "arch", base); text != "" || err != nil {
		t.Fatalf("Guidance at a commit that carries none = %q, %v; want nothing", text, err)
	}
	if _, err := review.Guidance(src, "arch", strings.Repeat("ab", 20)); err == nil {
		t.Fatal("Guidance at a commit nothing can fetch read")
	}
	edits, err := review.GuidanceEdits(src, "main", at)
	if err != nil {
		t.Fatal(err)
	}
	slices.Sort(edits)
	if want := []string{"docs/review-arch.md", "docs/review-pm.md", "review-checks.toml"}; !reflect.DeepEqual(edits, want) {
		t.Fatalf("GuidanceEdits = %v; want %v", edits, want)
	}
}
