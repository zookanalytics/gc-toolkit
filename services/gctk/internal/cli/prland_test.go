package cli

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// The record's two commands run through the store stub the bead holds tests
// use, which answers `bd where`, `bd list` and `rig list`, and has no answer
// for an update, so a command that writes where it must not fails here. The
// domain's rules are pr's own tests, on the fakes.

const validated = "1111111111111111111111111111111111111111"

// landingCmd runs gctk with args over store, in a clone whose origin is origin,
// or a clone with no origin when origin is empty.
func landingCmd(t *testing.T, store, origin string, args ...string) (stdout, stderr string, code int) {
	t.Helper()
	bin := t.TempDir()
	if err := os.WriteFile(filepath.Join(bin, "gc"), []byte(storeStub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STUB_STORE", store)
	rig := t.TempDir()
	setup := [][]string{{"init", "-q"}}
	if origin != "" {
		setup = append(setup, []string{"remote", "add", "origin", origin})
	}
	for _, a := range setup {
		if out, err := exec.Command("git", append([]string{"-C", rig}, a...)...).CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", a, err, out)
		}
	}
	t.Setenv("GC_RIG_ROOT", rig)
	var out, errbuf bytes.Buffer
	code = Run(args, "", &out, &errbuf)
	return out.String(), errbuf.String(), code
}

func TestPRReconcileWithNoPendingRecordSaysSo(t *testing.T) {
	out, errs, code := landingCmd(t, `[{"id":"st-1","status":"open"}]`, "git@github.com:acme/widgets.git",
		"pr", "reconcile", "--refinery", "rig/refinery", "--db", t.TempDir())
	if code != 0 || strings.TrimSpace(out) != "No pending pull-request merges." {
		t.Fatalf("exit %d, stdout %q, stderr %q", code, out, errs)
	}
}

func TestPRReconcileUsage(t *testing.T) {
	for _, args := range [][]string{
		{"pr", "reconcile"},
		{"pr", "reconcile", "--refinery", "rig/refinery", "--count", "0"},
		{"pr", "reconcile", "--refinery", "rig/refinery", "extra"},
	} {
		if _, _, code := landingCmd(t, `[]`, "git@github.com:acme/widgets.git", args...); code != 1 {
			t.Errorf("%v exited %d, want the usage exit 1", args, code)
		}
	}
}

func TestPRRecordUsage(t *testing.T) {
	pr := "https://github.com/acme/widgets/pull/7"
	for _, args := range [][]string{
		{"pr", "record", "st-1", "--pr", "https://github.com/acme/widgets/issues/7", "--head", validated, "--target", "main", "--refinery", "r"},
		{"pr", "record", "st-1", "--pr", pr, "--head", "1111111", "--target", "main", "--refinery", "r"},
		{"pr", "record", "st-1", "--pr", pr, "--head", validated, "--target", "main"},
		{"pr", "record", "st-1", "--pr", pr, "--head", validated, "--target", "bad..name", "--refinery", "r"},
		{"pr", "record", "--pr", pr, "--head", validated, "--target", "main", "--refinery", "r"},
	} {
		if _, _, code := landingCmd(t, `[]`, "git@github.com:acme/widgets.git", args...); code != 1 {
			t.Errorf("%v exited %d, want the usage exit 1", args, code)
		}
	}
}

// A bead that is closed, or that the refinery does not hold, gets no write: the
// stub answers no update, so a write would exit 2.
func TestPRRecordWritesNothingOnABeadThatIsNotTheRefinerys(t *testing.T) {
	for name, store := range map[string]string{
		"closed":           `[{"id":"st-1","status":"closed","assignee":"rig/refinery"}]`,
		"another assignee": `[{"id":"st-1","status":"open","assignee":"someone"}]`,
	} {
		t.Run(name, func(t *testing.T) {
			_, errs, code := landingCmd(t, store, "https://github.com/acme/widgets.git",
				"pr", "record", "st-1", "--pr", "https://github.com/acme/widgets/pull/7", "--head", validated,
				"--target", "main", "--refinery", "rig/refinery", "--db", t.TempDir())
			if code != 3 || !strings.Contains(errs, "nothing written") {
				t.Fatalf("exit %d, stderr %q, want the refusal exit 3", code, errs)
			}
		})
	}
}

func TestPRRecordRefusesAPROutsideTheRigsOrigin(t *testing.T) {
	_, errs, code := landingCmd(t, `[{"id":"st-1","status":"open","assignee":"rig/refinery"}]`,
		"git@github.com:acme/other.git",
		"pr", "record", "st-1", "--pr", "https://github.com/acme/widgets/pull/7", "--head", validated,
		"--target", "main", "--refinery", "rig/refinery", "--db", t.TempDir())
	if code != 1 || !strings.Contains(errs, "is not the rig's origin") {
		t.Fatalf("exit %d, stderr %q, want exit 1 naming the origin", code, errs)
	}
}

// An origin that does not read is a read that did not answer, exit 2, never
// the refusal of a PR outside the rig's repository.
func TestPRRecordWhoseOriginDoesNotReadWritesNothingAndExits2(t *testing.T) {
	_, errs, code := landingCmd(t, `[{"id":"st-1","status":"open","assignee":"rig/refinery"}]`, "",
		"pr", "record", "st-1", "--pr", "https://github.com/acme/widgets/pull/7", "--head", validated,
		"--target", "main", "--refinery", "rig/refinery", "--db", t.TempDir())
	if code != 2 || !strings.Contains(errs, "origin did not read") {
		t.Fatalf("exit %d, stderr %q, want exit 2 naming the origin's read", code, errs)
	}
}

// A run of the landing order loads the definition of feedback in the clone it
// reads, $GC_RIG_ROOT, so it reads that rig's declaration, whatever directory
// gctk runs in: the test runs in this checkout, which does not declare the
// prefix.
func TestLandingLoadsTheDefinitionInItsClone(t *testing.T) {
	packScripts(t)
	t.Setenv("GC_RIG_ROOT", declaringRig(t, declared))
	l, err := landing(filepath.Join(t.TempDir(), ".beads"), "rig/refinery")
	if err != nil {
		t.Fatal(err)
	}
	f, err := l.Feedback()
	if err != nil {
		t.Fatal(err)
	}
	if !readsDeclared(t, f) {
		t.Fatal("the definition did not read the declaration of the clone at $GC_RIG_ROOT")
	}
}

// The landing order files its human gates through the runtime adapter: the
// pack's human-gate.sh, from GCTK_SCRIPTS_DIR, gets the bead, the key and the
// whole message, and a gate the script does not file is an error carrying the
// script's own words.
func TestLandingFilesItsGatesThroughTheRuntime(t *testing.T) {
	scripts := t.TempDir()
	log := filepath.Join(scripts, "calls")
	stub := "#!/bin/sh\nfor a in \"$@\"; do printf '%s\\n' \"$a\"; done >> '" + log + "'\n" +
		"[ \"${STUB_EXIT:-0}\" = 0 ] || echo 'human-gate.sh: the store refused it' >&2\nexit \"${STUB_EXIT:-0}\"\n"
	if err := os.WriteFile(filepath.Join(scripts, "human-gate.sh"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("GCTK_SCRIPTS_DIR", scripts)
	l, err := landing(filepath.Join(t.TempDir(), ".beads"), "rig/refinery")
	if err != nil {
		t.Fatal(err)
	}
	if err := l.Gates.File("tk-1", "pull_request_closed_unmerged", "Pull request closed.\nMore."); err != nil {
		t.Fatal(err)
	}
	if raw, _ := os.ReadFile(log); string(raw) != "--subject\ntk-1\n--key\npull_request_closed_unmerged\n--message\nPull request closed.\nMore.\n" {
		t.Fatalf("human-gate.sh got %q", raw)
	}
	t.Setenv("STUB_EXIT", "1")
	if err := l.Gates.File("tk-1", "k", "m"); err == nil || !strings.Contains(err.Error(), "the store refused it") {
		t.Fatalf("a gate the script refused read as %v", err)
	}
}

// auditClone is a clone at $GC_RIG_ROOT that carries a rendered seed audit
// beside its pack.toml, with stubs of the pack's render-seed-audit.sh and
// seed-audit-reaudit.sh in GCTK_SCRIPTS_DIR that log their arguments to
// calls.render and calls.reaudit. The render stub writes the pages STUB_PAGES
// names to its --base-stale-out file, and each exits STUB_EXIT with its reason
// last.
func auditClone(t *testing.T) (clone, scripts string) {
	t.Helper()
	clone = t.TempDir()
	if err := os.MkdirAll(filepath.Join(clone, "generated", "seed-audit"), 0o755); err != nil {
		t.Fatal(err)
	}
	for _, p := range []string{"pack.toml", "generated/seed-audit/INDEX.md"} {
		if err := os.WriteFile(filepath.Join(clone, p), []byte("x\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	scripts = t.TempDir()
	stubs := map[string]string{
		"render-seed-audit.sh": "#!/bin/sh\nfor a in \"$@\"; do printf '%s\\n' \"$a\"; done >> '" + scripts + "/calls.render'\n" +
			"out=''; prev=''\nfor a in \"$@\"; do [ \"$prev\" = --base-stale-out ] && out=\"$a\"; prev=\"$a\"; done\n" +
			"[ \"${STUB_EXIT:-0}\" = 0 ] || { echo 'render-seed-audit: gc is not on PATH' >&2; exit \"$STUB_EXIT\"; }\n" +
			": > \"$out\"\nfor p in $STUB_PAGES; do printf '%s\\n' \"$p\" >> \"$out\"; done\n" +
			"echo 'the merge makes no render stale'\n",
		"seed-audit-reaudit.sh": "#!/bin/sh\nfor a in \"$@\"; do printf '%s\\n' \"$a\"; done >> '" + scripts + "/calls.reaudit'\n" +
			"echo \"seed-audit-reaudit: filed main's re-audit re-1\" >&2\n" +
			"[ \"${STUB_EXIT:-0}\" = 0 ] || { echo 'seed-audit-reaudit: the dedup query failed' >&2; exit \"$STUB_EXIT\"; }\n" +
			"echo 're-1 gc-toolkit/gc-toolkit.polecat filed'\n",
	}
	for name, body := range stubs {
		if err := os.WriteFile(filepath.Join(scripts, name), []byte(body), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("GC_RIG_ROOT", clone)
	t.Setenv("GCTK_SCRIPTS_DIR", scripts)
	return clone, scripts
}

// Only a clone that carries a rendered seed audit beside its pack.toml has an
// audit a landing can leave stale.
func TestLandingKeepsASeedAuditOnlyWhereTheCloneCarriesOne(t *testing.T) {
	clone, _ := auditClone(t)
	l, err := landing(filepath.Join(t.TempDir(), ".beads"), "rig/refinery")
	if err != nil {
		t.Fatal(err)
	}
	if l.Audit == nil {
		t.Fatal("a clone carrying generated/seed-audit/INDEX.md has no audit")
	}
	for _, p := range []string{"generated/seed-audit/INDEX.md", "pack.toml"} {
		if err := os.Remove(filepath.Join(clone, p)); err != nil {
			t.Fatal(err)
		}
		if l, err := landing(filepath.Join(t.TempDir(), ".beads"), "rig/refinery"); err != nil || l.Audit != nil {
			t.Fatalf("a clone without %s has an audit (%v)", p, err)
		}
	}
}

// The audit checks a commit by the pack's render-seed-audit.sh, run in the
// clone on the merge of the commit into itself, and reads the stale pages from
// the file the script names them in. A check the script does not complete is an
// error carrying its own words.
func TestTheSeedAuditChecksACommitThroughThePacksRenderer(t *testing.T) {
	clone, scripts := auditClone(t)
	l, err := landing(filepath.Join(t.TempDir(), ".beads"), "rig/refinery")
	if err != nil {
		t.Fatal(err)
	}
	t.Setenv("STUB_PAGES", "agents/claude.md formulas/mol-polecat-base.md")
	pages, err := l.Audit.Stale(validated)
	if err != nil || strings.Join(pages, ",") != "agents/claude.md,formulas/mol-polecat-base.md" {
		t.Fatalf("Stale = %v, %v, want the two pages the script named", pages, err)
	}
	raw, _ := os.ReadFile(filepath.Join(scripts, "calls.render"))
	args := strings.Split(strings.TrimSuffix(string(raw), "\n"), "\n")
	if len(args) != 7 || strings.Join(args[:6], " ") != "--root "+clone+" --check-merge "+validated+" "+validated+" --base-stale-out" {
		t.Fatalf("render-seed-audit.sh got %q", args)
	}
	if _, err := os.Stat(args[6]); !os.IsNotExist(err) {
		t.Errorf("the stale pages' file %s outlived the check (%v)", args[6], err)
	}
	t.Setenv("STUB_PAGES", "")
	if pages, err := l.Audit.Stale(validated); err != nil || len(pages) != 0 {
		t.Fatalf("a current audit read as %v, %v", pages, err)
	}
	t.Setenv("STUB_EXIT", "2")
	if _, err := l.Audit.Stale(validated); err == nil || !strings.Contains(err.Error(), "exit 2: render-seed-audit: gc is not on PATH") {
		t.Fatalf("a check the script did not complete read as %v", err)
	}
}

// The audit hands the stale pages to the pack's seed-audit-reaudit.sh, with the
// branch and who found them, and answers with the line the writer ends on. A
// writer that exits other than 0 is an error carrying its own words.
func TestTheSeedAuditHandsItsPagesToThePacksWriter(t *testing.T) {
	_, scripts := auditClone(t)
	l, err := landing(filepath.Join(t.TempDir(), ".beads"), "rig/refinery")
	if err != nil {
		t.Fatal(err)
	}
	answer, err := l.Audit.Reaudit("main", "The landing order, checking main,", []string{"agents/claude.md", "formulas/mol-x.md"})
	if err != nil || answer != "re-1 gc-toolkit/gc-toolkit.polecat filed" {
		t.Fatalf("Reaudit = %q, %v, want the writer's last line", answer, err)
	}
	raw, _ := os.ReadFile(filepath.Join(scripts, "calls.reaudit"))
	if want := "--base\nmain\n--seen-by\nThe landing order, checking main,\n--page\nagents/claude.md\n--page\nformulas/mol-x.md\n"; string(raw) != want {
		t.Fatalf("seed-audit-reaudit.sh got %q, want %q", raw, want)
	}
	t.Setenv("STUB_EXIT", "2")
	if _, err := l.Audit.Reaudit("main", "x,", []string{"agents/claude.md"}); err == nil ||
		!strings.Contains(err.Error(), "exit 2: seed-audit-reaudit: the dedup query failed") {
		t.Fatalf("a writer that dispatched nothing read as %v", err)
	}
}
