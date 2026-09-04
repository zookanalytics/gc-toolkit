package cli

import (
	"bytes"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/lifecycle"
)

// The behaviour of `gctk lifecycle` against a bead store is covered by
// assets/scripts/lifecycle.test.sh, which drives this binary through the same
// stub harness as the script it replaces — that suite is the acceptance bar.
// What is here is what that suite cannot reach: the argument grammar, and the
// machine dump the drift assertion reads.

func TestKVSplitsOnTheFirstEquals(t *testing.T) {
	// The shell's ${v%%=*} / ${v#*=} pair. A URL value carries more '=' signs
	// than the key does, so splitting on the last one would silently truncate
	// every pr_url the cadence records.
	for _, tc := range []struct{ in, key, value string }{
		{"merged_sha=abc123", "merged_sha", "abc123"},
		{"pr_url=https://x/p?a=1&b=2", "pr_url", "https://x/p?a=1&b=2"},
		{"empty=", "empty", ""},
		// No '=' at all: the shell yields the whole string for both halves.
		{"bare", "bare", "bare"},
	} {
		k, v := kv(tc.in)
		if k != tc.key || v != tc.value {
			t.Errorf("kv(%q) = (%q, %q), want (%q, %q)", tc.in, k, v, tc.key, tc.value)
		}
	}
}

func TestParseTransitionCollectsRepeatedFlags(t *testing.T) {
	o, err := parseTransition([]string{
		"--to", "merged", "--expect", "pull_request", "--close",
		"--set", "merged_sha=abc", "--set", "merged_target=main",
		"--unset", "rejection_reason", "--unset", "merge_hold",
		"--route", "human", "--assignee", "", "--append-notes", "landed", "--json",
	})
	if err != nil {
		t.Fatalf("parseTransition: %v", err)
	}
	if o.to != "merged" || o.expect != "pull_request" || !o.closeIt || !o.asJSON {
		t.Errorf("scalars parsed wrong: %+v", o)
	}
	if len(o.sets) != 2 || len(o.unsets) != 2 {
		t.Errorf("repeated flags = %v / %v, want two of each", o.sets, o.unsets)
	}
	// An empty --assignee is a REQUEST to clear, not an absent flag. Losing the
	// distinction would silently drop the clear from the atomic update.
	if !o.assigneeSet || o.assignee != "" {
		t.Errorf("--assignee '' = (set %v, %q), want (true, \"\")", o.assigneeSet, o.assignee)
	}
	if !o.routeSet || o.route != "human" {
		t.Errorf("--route = (set %v, %q)", o.routeSet, o.route)
	}
	if !o.notesSet || o.notes != "landed" {
		t.Errorf("--append-notes = (set %v, %q)", o.notesSet, o.notes)
	}
}

func TestUnknownArgumentIsRefused(t *testing.T) {
	if _, err := parseTransition([]string{"--to", "merged", "--wat"}); err == nil {
		t.Fatal("an unknown flag was accepted")
	}
}

// A value-taking flag with no following token is a malformed invocation and is
// refused. The empty string it would otherwise take drops --expect's
// compare-and-swap guard, so `--to pull_request --expect` with nothing after it
// would transition unguarded. lifecycle.sh hangs on this input instead (its
// `shift 2` underflows at $# = 1); a refusal is the behavior worth keeping.
func TestValueTakingFlagRejectsAMissingValue(t *testing.T) {
	for _, flag := range []string{
		"--to", "--expect", "--set", "--set-dated", "--unset",
		"--assignee", "--route", "--takeaway", "--append-notes",
	} {
		// The flag under test is last, with no token after it. A valid earlier
		// --to keeps each case about the trailing flag, not a missing target.
		args := []string{"--to", "pull_request", flag}
		if flag == "--to" {
			args = []string{flag}
		}
		if _, err := parseTransition(args); err == nil {
			t.Errorf("parseTransition(%v) accepted %s with no value", args, flag)
		}
	}
}

// An explicitly supplied empty argument is a real token, not a missing one, and
// is preserved: --assignee '' clears the assignee (a request the atomic update
// must carry) and --expect '' parses to the empty expectation the guard reads as
// no compare-and-swap. Only the total absence of a following token is malformed.
func TestExplicitEmptyArgumentIsPreserved(t *testing.T) {
	o, err := parseTransition([]string{"--to", "merged", "--expect", "", "--assignee", "", "--close"})
	if err != nil {
		t.Fatalf("parseTransition rejected explicit empty arguments: %v", err)
	}
	if o.expect != "" {
		t.Errorf("--expect '' = %q, want the empty expectation", o.expect)
	}
	if !o.assigneeSet || o.assignee != "" {
		t.Errorf("--assignee '' = (set %v, %q), want (true, \"\")", o.assigneeSet, o.assignee)
	}
}

func TestDumpMachineNamesEveryDeclaredEdge(t *testing.T) {
	var out bytes.Buffer
	if rc := dumpMachine(&out); rc != 0 {
		t.Fatalf("dumpMachine = %d, want 0", rc)
	}
	got := out.String()
	for _, want := range []string{
		"states " + strings.Join(lifecycle.States, " "),
		"human_states " + strings.Join(lifecycle.HumanStates, " "),
		"closed_states " + strings.Join(lifecycle.ClosedStates, " "),
	} {
		if !strings.Contains(got, want+"\n") {
			t.Errorf("missing line %q in:\n%s", want, got)
		}
	}
	for _, e := range lifecycle.Transitions {
		if !strings.Contains(got, "transition "+e.From+">"+e.To+"\n") {
			t.Errorf("missing edge %s>%s in:\n%s", e.From, e.To, got)
		}
	}
	// One line per edge and nothing else: the drift assertion compares the
	// `transition ` lines as a set, and a duplicate would make it disagree with
	// a TOML that is actually correct.
	if n := strings.Count(got, "transition "); n != len(lifecycle.Transitions) {
		t.Errorf("dumped %d transition lines, want %d", n, len(lifecycle.Transitions))
	}
}

// Every refusal that precedes the read must exit without touching a bead. If
// one of these reached the store first, a malformed call would be a write.
func TestPreReadRefusalsNeverTouchABead(t *testing.T) {
	for _, tc := range []struct {
		name string
		args []string
		want string
	}{
		{"no id", []string{}, "needs a bead id"},
		{"no --to", []string{"b-1"}, "needs --to <state>"},
		{"undeclared state", []string{"b-1", "--to", "nowhere"}, "is not a declared state"},
		{"close on a non-closed state", []string{"b-1", "--to", "abandoned", "--close"}, "not a closed state"},
		{"closed state without --close", []string{"b-1", "--to", "merged"}, "requires --close"},
		// `merged` means "landed; merged_sha recorded", so the sha rides the same
		// atomic write; a bead with no PR takes --to unanchored --close instead.
		{"--to merged without a merged_sha", []string{"b-1", "--to", "merged", "--close"}, "requires --set merged_sha"},
		{"--to merged with an empty merged_sha", []string{"b-1", "--to", "merged", "--close", "--set", "merged_sha="}, "requires --set merged_sha"},
		// A key set twice, or set and unset, resolves by argument order and can
		// never verify; the merged_sha guard scans the first token, so either shape
		// would otherwise slip an empty sha past it and close with no landing.
		{"a key set and unset in one call", []string{"b-1", "--to", "merged", "--close", "--set", "merged_sha=abc", "--unset", "merged_sha"}, "both set and unset"},
		{"a key set twice on the set side", []string{"b-1", "--to", "merged", "--close", "--set", "merged_sha=abc", "--set", "merged_sha="}, "set more than once"},
		{"--set merge_result", []string{"b-1", "--to", "pull_request", "--set", "merge_result=x"}, "written by --to"},
		{"--set gc.routed_to", []string{"b-1", "--to", "pull_request", "--set", "gc.routed_to=x"}, "route via --route"},
		{"--set gc.takeaway", []string{"b-1", "--to", "abandoned", "--set", "gc.takeaway=x"}, "written by --takeaway"},
		{"--set-dated merge_result", []string{"b-1", "--to", "pull_request", "--set-dated", "merge_result=x@oid"}, "written by --to"},
		{"--set-dated with no oid", []string{"b-1", "--to", "pull_request", "--set-dated", "pr.machine=settled"}, "<value>@<oid>"},
		{"--set-dated carrying its own instant", []string{"b-1", "--to", "pull_request", "--set-dated", "pr.machine=settled@oid@2026-01-01T00:00:00Z"}, "<value>@<oid>"},
		{"--set-dated with no '='", []string{"b-1", "--to", "pull_request", "--set-dated", "pr.machine"}, "is not k=<value>@<oid>"},
		// A human state names the person it waits on. The refusal is decided on
		// arguments alone, so it happens before any bead is read.
		{"empty --route into a human state", []string{"b-1", "--to", "abandoned", "--route", ""}, "waiting on nobody"},
		{"empty --takeaway", []string{"b-1", "--to", "abandoned", "--takeaway", ""}, "no question recorded"},
		{"whitespace-only --takeaway", []string{"b-1", "--to", "abandoned", "--takeaway", " \t\n "}, "no question recorded"},
		{"--takeaway over the cap", []string{"b-1", "--to", "abandoned", "--takeaway", strings.Repeat("x", lifecycle.TakeawayMax+1)}, "the cap is 140"},
		// A value-taking flag with no following token is malformed; the refusal is
		// on arguments alone, ahead of any read. --expect is the one that matters:
		// the empty string it used to take dropped the compare-and-swap guard.
		{"--expect with no value", []string{"b-1", "--to", "pull_request", "--expect"}, "flag --expect needs a value"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var out, errOut bytes.Buffer
			if rc := cmdTransition(tc.args, &out, &errOut); rc != 1 {
				t.Errorf("exit = %d, want 1", rc)
			}
			if !strings.Contains(errOut.String(), tc.want) {
				t.Errorf("stderr = %q, want it to contain %q", errOut.String(), tc.want)
			}
			if out.Len() != 0 {
				t.Errorf("a refusal wrote to stdout: %q", out.String())
			}
		})
	}
}

func TestReopenTakesNoOptions(t *testing.T) {
	var out, errOut bytes.Buffer
	if rc := cmdReopen([]string{"b-1", "--force"}, &out, &errOut); rc != 1 {
		t.Errorf("exit = %d, want 1", rc)
	}
	if !strings.Contains(errOut.String(), "takes no options") {
		t.Errorf("stderr = %q", errOut.String())
	}
}

func TestUnknownVerbPrintsUsage(t *testing.T) {
	var out, errOut bytes.Buffer
	if rc := Lifecycle([]string{"wat"}, &out, &errOut); rc != 1 {
		t.Errorf("exit = %d, want 1", rc)
	}
	if !strings.Contains(errOut.String(), "gctk lifecycle transition") {
		t.Errorf("stderr = %q, want the usage block", errOut.String())
	}
}

func TestDatedSincePreservesWhileValueAndOIDHold(t *testing.T) {
	// The reconcile cadence re-reaches the same verdict at the same head every
	// few minutes. A clock that restarted there would report a three-day wait as
	// new and sort the most neglected row last, with nothing in either key saying
	// so — the failure is invisible on the rendered board.
	const oid = "1111111111111111111111111111111111111111"
	const oid2 = "2222222222222222222222222222222222222222"
	pinned := time.Date(2026, 9, 3, 12, 0, 0, 0, time.UTC)
	restore := now
	now = func() time.Time { return pinned }
	defer func() { now = restore }()
	fresh := pinned.Format("2006-01-02T15:04:05Z")

	for _, tc := range []struct{ name, have, want, expect string }{
		{"first write", "", "settled@" + oid, fresh},
		{"unchanged value at an unchanged head", "settled@" + oid + "@2026-08-28T04:05:06Z", "settled@" + oid, "2026-08-28T04:05:06Z"},
		{"a changed verdict is a new turn", "progressing@" + oid + "@2026-08-28T04:05:06Z", "settled@" + oid, fresh},
		{"a moved head is a new turn", "settled@" + oid + "@2026-08-28T04:05:06Z", "settled@" + oid2, fresh},
		{"an undated legacy value has no instant to keep", "settled@" + oid, "settled@" + oid, fresh},
		// A stored value carrying a fourth component is not the shape this rule
		// reads, so it cannot yield an instant to preserve.
		{"a malformed stored value", "settled@" + oid + "@a@b", "settled@" + oid, fresh},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := datedSince(tc.have, tc.want); got != tc.expect {
				t.Errorf("datedSince(%q, %q) = %q, want %q", tc.have, tc.want, got, tc.expect)
			}
		})
	}
}

func TestSqueezeSpaceMatchesTheShellNormalization(t *testing.T) {
	// `tr -s '[:space:]' ' '` plus the shell's one-space trims. It runs before
	// the empty check, which is what makes a whitespace-only takeaway an empty
	// one rather than a stored blank the board renders as a question nobody asked.
	for _, tc := range []struct{ in, want string }{
		{"already tight", "already tight"},
		{"  leading and trailing  ", "leading and trailing"},
		{"runs\t\tof\n\nwhitespace", "runs of whitespace"},
		{"   ", ""},
		{"", ""},
		{"\t\n\v\f\r", ""},
	} {
		if got := squeezeSpace(tc.in); got != tc.want {
			t.Errorf("squeezeSpace(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

func TestTakeawayCapIsMeasuredInCodepoints(t *testing.T) {
	// The board renders one line of text, so the cap counts what a reader sees.
	// A byte count would refuse a takeaway well inside the cap the moment it
	// carried an em dash — which is most of them.
	wide := strings.Repeat("é", lifecycle.TakeawayMax)
	if got, refusal := normalizeTakeaway(wide); refusal != nil || got != wide {
		t.Errorf("%d codepoints was refused by a byte-counting cap: %v", lifecycle.TakeawayMax, refusal)
	}
	if _, refusal := normalizeTakeaway(wide + "é"); refusal == nil {
		t.Errorf("%d codepoints was accepted over the cap", lifecycle.TakeawayMax+1)
	} else if !strings.Contains(refusal[0], "141 chars") {
		t.Errorf("the refusal does not report the measured length: %q", refusal[0])
	}
}
