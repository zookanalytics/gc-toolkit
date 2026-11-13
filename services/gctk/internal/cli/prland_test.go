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
