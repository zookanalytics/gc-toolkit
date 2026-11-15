package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

func runGctk(t *testing.T, args ...string) (code int, stdout, stderr string) {
	t.Helper()
	var out, errb bytes.Buffer
	code = Run(args, "test", &out, &errb)
	return code, out.String(), errb.String()
}

// The check index's calls: a call that names no commit, two forms in one call
// and a flag only another form takes are usage errors even where the pack's
// index cannot be found, and an index named outright answers each form with no
// commit.
func TestReviewChecksCalls(t *testing.T) {
	idx := filepath.Join(t.TempDir(), "review-checks.toml")
	if err := os.WriteFile(idx, []byte("[checks.correctness]\npurpose = \"p\"\nphase = \"pre-open\"\n[checks.demo]\npurpose = \"d\"\nphase = \"open-as-draft\"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("GC_REVIEW_CHECKS_INDEX", "")
	// No GCTK_SCRIPTS_DIR, and a gc that names no scripts directory ahead of
	// any other, so the pack's index cannot be found.
	trap := t.TempDir()
	if err := os.WriteFile(filepath.Join(trap, "gc"), []byte("#!/bin/sh\nexit 1\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", trap+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("GCTK_SCRIPTS_DIR", "")
	for _, tc := range []struct {
		args []string
		code int
		out  string
	}{
		{[]string{"review", "checks", "--show"}, 2, ""},
		{[]string{"review", "checks", "--resolve", "correctness", "--through", "merge", "--at", ""}, 2, ""},
		{[]string{"review", "checks", "--file", idx, "--resolve", "correctness"}, 2, ""},
		{[]string{"review", "checks", "--file", idx, "--resolve", "correctness", "--through", "merge", "--check", "demo"}, 2, ""},
		{[]string{"review", "checks", "--file", idx, "--through", "merge"}, 2, ""},
		{[]string{"review", "checks", "--file", idx, "--with-phase"}, 2, ""},
		{[]string{"review", "checks", "--file", idx}, 0, "correctness\tp\tpre-open\ndemo\td\topen-as-draft\n"},
		{[]string{"review", "checks", "--file", idx, "--show", "--check", "DEMO"}, 0, "demo\td\topen-as-draft\n"},
		{[]string{"review", "checks", "--file", idx, "--check", "nonesuch"}, 1, ""},
		{[]string{"review", "checks", "--file", idx, "--resolve", "correctness,demo,approval", "--through", "pre-open"}, 0, "correctness\n"},
		{[]string{"review", "checks", "--file", idx, "--resolve", "", "--through", "merge"}, 0, ""},
		{[]string{"review", "checks", "--file", idx, "--resolve", "demo", "--through", "merge", "--with-phase"}, 0, "demo\topen-as-draft\n"},
		{[]string{"review", "checks", "--file", filepath.Join(t.TempDir(), "absent.toml")}, 1, ""},
		{[]string{"review", "guidance", "arch"}, 2, ""},
		{[]string{"review", "guidance", "../README", "--at", "HEAD"}, 2, ""},
		{[]string{"review", "guidance", "--edits", "--at", "HEAD"}, 2, ""},
		{[]string{"review", "guidance", "arch", "--base", "main", "--at", "HEAD"}, 2, ""},
	} {
		code, out, _ := runGctk(t, tc.args...)
		if code != tc.code || out != tc.out {
			t.Errorf("gctk %s = exit %d, %q; want exit %d, %q", strings.Join(tc.args, " "), code, out, tc.code, tc.out)
		}
	}
	t.Setenv("GC_REVIEW_CHECKS_INDEX", idx)
	if code, out, _ := runGctk(t, "review", "checks", "--resolve", "correctness,demo", "--through", "pre-open"); code != 0 || out != "correctness\n" {
		t.Errorf("with GC_REVIEW_CHECKS_INDEX naming the index, a resolve with no commit = exit %d, %q", code, out)
	}
}

// The loop's check exits 75 when the store does not answer, so the check
// re-runs without spending an attempt, and 1 for a bead that is no run.
func TestReviewPassedExits(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "tk-x", Status: "open", IssueType: "task"})
	var out, errb bytes.Buffer
	if code := passedIn(ledger.New(s), "tk-x", 0, false, &out, &errb); code != 1 {
		t.Errorf("a bead that is no run exits %d; want 1", code)
	}
	s.FindErr = &gcbd.ReadError{Reason: "down"}
	if code := passedIn(ledger.New(s), "tk-x", 0, false, &out, &errb); code != passedNoVerdict {
		t.Errorf("a store that does not answer exits %d; want %d", code, passedNoVerdict)
	}
}
