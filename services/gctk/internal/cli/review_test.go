package cli

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	gcfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
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
	if code := passedIn(ledger.New(s), "tk-x", 0, false, nil, &out, &errb); code != 1 {
		t.Errorf("a bead that is no run exits %d; want 1", code)
	}
	s.FindErr = &gcbd.ReadError{Reason: "down"}
	if code := passedIn(ledger.New(s), "tk-x", 0, false, nil, &out, &errb); code != passedNoVerdict {
		t.Errorf("a store that does not answer exits %d; want %d", code, passedNoVerdict)
	}
}

// putOutput puts a closed step of the run that wrote raw as its output.
func putOutput(s *fake.Store, id, raw string) {
	s.Put(fake.Bead{ID: id, Status: "closed", IssueType: "task", Metadata: map[string]string{
		"gc.root_bead_id": "tk-run", "gc.output_json": raw,
	}})
}

// checking runs the loop's check over iteration n of the run in s with
// --record, its scripts answered by rt.
func checking(t *testing.T, s *fake.Store, rt *gcfake.Runtime, n int) (int, string, string) {
	t.Helper()
	var out, errb bytes.Buffer
	rec := &recorder{dir: t.TempDir(), wait: time.Second, gates: gates{rt}, scripts: rt}
	code := passedIn(ledger.New(s), "tk-run", n, false, rec, &out, &errb)
	return code, out.String(), errb.String()
}

// The loop's check with --record records the run's result when the iteration
// ends the loop, and then closes the findings whose asks closed: at a pass it
// exits 0 once that landed; at an iteration that neither passed nor is the
// last it records nothing; at the last attempt not passing it records a result
// that does not pass, asks a person through a review-loop-exhausted gate and
// exits 1, so the loop ends exhausted. A write, the gate or the findings' close
// that does not land exits 75, which spends no attempt. A shadow run writes,
// files and runs nothing.
func TestTheLoopsCheckRecordsTheRunsResult(t *testing.T) {
	triage := func(n int, head string) string {
		return `{"review":"triage","iteration":` + string(rune('0'+n)) + `,"head":"` + head + `","checks":[],"material":false}`
	}
	repair := func(n int, head, pushed string) string {
		return `{"review":"repair","iteration":` + string(rune('0'+n)) + `,"head":"` + head + `","rulings":[],"pushed":"` + pushed + `"}`
	}
	result := func(s *fake.Store) string { r, _ := s.Row("tk-pr"); return r.Metadata["review_results"] }
	scripts := func(rt *gcfake.Runtime) []string {
		var out []string
		for _, c := range rt.Scripts() {
			out = append(out, c.Name+" "+strings.Join(c.Args, " "))
		}
		return out
	}
	withBound := func(s *fake.Store) *fake.Store {
		r, _ := s.Row("tk-run")
		r.Metadata["gc.var.max_attempts"] = "2"
		s.Put(r)
		return s
	}

	s := withBound(runStore())
	putOutput(s, "tk-o1", triage(1, runHead))
	putOutput(s, "tk-o2", repair(1, runHead, ""))
	rt := &gcfake.Runtime{}
	code, out, errs := checking(t, s, rt, 1)
	if code != 0 || !strings.Contains(result(s), `"head":"`+runHead+`","target":"main","passed":true`) ||
		!strings.Contains(out, "tk-pr: review passed at "+runHead+" into main") {
		t.Fatalf("a passed iteration = exit %d, review_results %s: %s%s", code, result(s), out, errs)
	}
	if got := scripts(rt); len(got) != 1 || got[0] != "finding.sh close-answered --anchor tk-pr" {
		t.Fatalf("a passed iteration ran %v; want only finding.sh close-answered", got)
	}

	s = withBound(runStore())
	putOutput(s, "tk-o1", triage(1, runHead))
	putOutput(s, "tk-o2", repair(1, runHead, runNext))
	rt = &gcfake.Runtime{}
	if code, out, errs := checking(t, s, rt, 1); code != 1 || result(s) != "" || len(rt.Scripts()) != 0 {
		t.Fatalf("an iteration that pushed, not the last = exit %d, review_results %q, scripts %v: %s%s", code, result(s), scripts(rt), out, errs)
	}
	putOutput(s, "tk-o3", triage(2, runNext))
	code, out, errs = checking(t, s, rt, 2)
	if code != 1 || !strings.Contains(result(s), `"head":"`+runNext+`","target":"main","passed":false`) {
		t.Fatalf("the last attempt not passing = exit %d, review_results %s: %s%s", code, result(s), out, errs)
	}
	got := scripts(rt)
	if len(got) != 2 || !strings.HasPrefix(got[0], "human-gate.sh --subject tk-pr --key review-loop-exhausted --message Review run tk-run exhausted its attempts at "+runNext) ||
		got[1] != "finding.sh close-answered --anchor tk-pr" {
		t.Fatalf("the exhausted loop ran %v; want its gate, then the findings' close", got)
	}

	s = withBound(runStore())
	putOutput(s, "tk-o1", triage(1, runHead))
	putOutput(s, "tk-o2", repair(1, runHead, ""))
	s.UpdateErr = errors.New("the store did not take the write")
	if code, _, errs := checking(t, s, &gcfake.Runtime{}, 1); code != passedNoVerdict || !strings.Contains(errs, "runs again") {
		t.Fatalf("a result write that did not land = exit %d: %s; want %d", code, errs, passedNoVerdict)
	}
	s.UpdateErr = nil
	rt = &gcfake.Runtime{OnScript: func(c gcfake.Call) gascity.Result {
		return gascity.Result{Code: 1, Output: "finding.sh: could not read findings"}
	}}
	if code, _, errs := checking(t, s, rt, 1); code != passedNoVerdict || !strings.Contains(errs, "findings whose asks closed") {
		t.Fatalf("a findings' close that did not land = exit %d: %s; want %d", code, errs, passedNoVerdict)
	}

	s = withBound(runStore())
	r, _ := s.Row("tk-run")
	r.Metadata["gc.var.shadow"] = "true"
	s.Put(r)
	putOutput(s, "tk-o1", triage(1, runHead))
	putOutput(s, "tk-o2", repair(1, runHead, runNext))
	putOutput(s, "tk-o3", triage(2, runNext))
	rt = &gcfake.Runtime{}
	code, out, _ = checking(t, s, rt, 2)
	if code != 1 || result(s) != "" || len(rt.Scripts()) != 0 || !strings.Contains(out, "shadow run, nothing filed") {
		t.Fatalf("a shadow run's last attempt = exit %d, review_results %q, scripts %v: %s", code, result(s), scripts(rt), out)
	}
}

// A fix ahead of a PR prints the fix and the ask that holds the PR for it: both
// filed, the fix slung, at the first call; both found, the fix on its way, at
// the next; the fix filed and the sling's failure, exit 2, when the sling does
// not land; and exit 3 with nothing filed for a bead with no PR on the record.
// Each usage error is exit 1.
func TestReviewAheadPrintsWhatStands(t *testing.T) {
	pr := fake.Bead{ID: "tk-pr", Status: "blocked", IssueType: "task", Metadata: map[string]string{
		"merge_result": "pull_request_pending", "branch": "polecat/tk-pr", "pr_head_sha": "1111", "merged_target": "main"}}
	index := func(string) (review.Index, error) {
		return review.Index{Source: "idx", Checks: review.Parse("[checks.arch]\nphase = \"pre-open\"\n")}, nil
	}
	req := review.AheadRequest{Bead: "tk-pr", Title: "docs: add the architecture document", Description: "Cover the orders.",
		Pool: "rig/gc-toolkit.polecat", Formula: "mol-polecat-work", Checks: []string{"arch"}}
	ahead := func(s *fake.Store, rt gascity.Runtime) (int, string, string) {
		var out, errb bytes.Buffer
		code := aheadIn(ledger.New(s), rt, req, index, &out, &errb)
		return code, out.String(), errb.String()
	}

	s := fake.New()
	s.Put(pr)
	rt := &gcfake.Runtime{OnSling: func(sl gascity.Sling) gascity.SlingResult {
		row, _ := s.Row(sl.Bead)
		row.Metadata["gc.routed_to"] = sl.Target
		s.Put(row)
		return gascity.SlingResult{}
	}}
	code, out, errOut := ahead(s, rt)
	if code != 0 || out != "fk-1 filed, slung to rig/gc-toolkit.polecat on mol-polecat-work\nfk-2 filed, waiting on fk-1\n" {
		t.Fatalf("the first call = %d, %q, %q", code, out, errOut)
	}
	code, out, errOut = ahead(s, rt)
	if code != 0 || out != "fk-1 found, on its way already\nfk-2 found, waiting on fk-1\n" {
		t.Fatalf("the next call = %d, %q, %q", code, out, errOut)
	}

	s = fake.New()
	s.Put(pr)
	failing := &gcfake.Runtime{OnSling: func(gascity.Sling) gascity.SlingResult {
		return gascity.SlingResult{Result: gascity.Result{Code: 1, Output: "no such pool"}}
	}}
	code, out, errOut = ahead(s, failing)
	if code != 2 || out != "fk-1 filed\n" || !strings.Contains(errOut, "no such pool") {
		t.Fatalf("a call whose sling fails = %d, %q, %q", code, out, errOut)
	}

	s = fake.New()
	s.Put(pr)
	s.Put(fake.Bead{ID: "tk-held", Title: req.Title, Status: "open", IssueType: "task", Labels: []string{"hold:mayor"}})
	code, out, errOut = ahead(s, &gcfake.Runtime{})
	if code != 0 || out != "tk-held found, held by its hold:mayor label, so it is sent nowhere\nfk-1 filed, waiting on tk-held\n" {
		t.Fatalf("a call that finds the fix held = %d, %q, %q", code, out, errOut)
	}

	s = fake.New()
	off := pr
	off.Metadata = map[string]string{"merge_result": "mr_merged", "branch": "polecat/tk-pr"}
	s.Put(off)
	code, out, errOut = ahead(s, &gcfake.Runtime{})
	if code != 3 || out != "" || len(s.Creates()) != 0 || !strings.Contains(errOut, "owns no PR on the record") {
		t.Fatalf("a bead with no PR on the record = %d, %q, %q", code, out, errOut)
	}

	file := filepath.Join(t.TempDir(), "fix.md")
	if err := os.WriteFile(file, []byte("Cover the orders.\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	for _, args := range [][]string{
		{"review", "ahead", "tk-pr", "--file", file, "--pool", "p", "--on", "f", "--check", "arch"},
		{"review", "ahead", "tk-pr", "--title", "t", "--file", file, "--on", "f", "--check", "arch"},
		{"review", "ahead", "tk-pr", "--title", "t", "--file", file, "--pool", "p", "--on", "f"},
		{"review", "ahead", "tk-pr", "--title", "t", "--file", file, "--pool", "p", "--on", "f", "--check", "no such"},
		{"review", "ahead", "tk-pr", "--title", "t", "--file", filepath.Join(t.TempDir(), "none"), "--pool", "p", "--on", "f", "--check", "arch"},
	} {
		if code, _, _ := runGctk(t, args...); code != 1 {
			t.Errorf("gctk %q = exit %d; want the usage exit 1", args, code)
		}
	}
}
