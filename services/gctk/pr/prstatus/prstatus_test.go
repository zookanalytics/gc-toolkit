package prstatus

import (
	"slices"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/standing/person"
)

// oneGate is one open human gate that holds the anchor, as [Facts.Gates] carries
// it, and personOwed one bead a person owes the next move on, as [Facts.Owed]
// carries it.
var (
	oneGate    = []person.Blocker{gate("g")}
	personOwed = []person.Blocker{{ID: "d", Title: "pick the release window", Status: "open", IssueType: "decision"}}
)

// The precedence table, one row per case pr-status-label.test.sh asserts.
// Keeping them here too proves the rule in isolation from the gathering
// ([Read]), so a failure names the logic or the wiring, never both at once. The
// facts hold no approval, so Derive gives no merging: only the evaluator's
// answer for a PR on the pending record reads one ([Render]).
func TestDerive(t *testing.T) {
	for _, tc := range []struct {
		name string
		f    Facts
		want State
	}{
		{"nothing outstanding", Facts{}, NeedsReview},
		{"one bead in the in-flight set", Facts{InFlightCount: 1}, Working},
		{"empty in-flight set", Facts{InFlightCount: 0}, NeedsReview},
		{"operator freeze merge_hold=true", Facts{MergeHold: "true"}, NeedsAttention},
		{"rebase hold", Facts{RebaseHold: "true"}, NeedsAttention},
		{"needs-attention outranks working (hold + live work)", Facts{MergeHold: "true", InFlightCount: 2}, NeedsAttention},
		{"open human gate on the anchor", Facts{Gates: oneGate}, NeedsAttention},
		{"open human gate outranks live work", Facts{Gates: oneGate, InFlightCount: 2}, NeedsAttention},
		{"a hold outranks a bead that stays for its work", Facts{MergeHold: "true", Staying: personOwed}, NeedsAttention},
		{"a bead that stays for its work holds the PR as working", Facts{Staying: personOwed}, Working},

		// Whatever Held names is a thing a person has to act on, so it holds the PR
		// as a human gate on the anchor does, whatever is in flight beside it.
		{"a bead a person owes", Facts{Owed: personOwed}, NeedsAttention},
		{"a bead a person owes with work in flight", Facts{Owed: personOwed, InFlightCount: 1}, NeedsAttention},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := Derive(tc.f); got != tc.want {
				t.Errorf("Derive(%+v) = %q, want %q", tc.f, got, tc.want)
			}
		})
	}
}

// Held names each thing that holds the PR, in the order gate, blocked, and
// leaves out a value whose condition no longer stands. Any value means
// Derive reads needs-attention; the holds that carry no value (merge_hold and
// rebase_hold) read needs-attention with Held empty.
func TestHeld(t *testing.T) {
	for _, tc := range []struct {
		name string
		f    Facts
		want []Hold
	}{
		{"nothing holds the PR", Facts{}, nil},
		{"a PR the city is changing", Facts{InFlightCount: 1}, nil},
		{"the merge freeze carries no held value", Facts{MergeHold: "true"}, nil},
		{"the rebase hold carries no held value", Facts{RebaseHold: "true"}, nil},

		{"an open human gate on the anchor", Facts{Gates: oneGate}, []Hold{HeldGate}},
		{"…whatever is in flight beside it", Facts{Gates: oneGate, InFlightCount: 1}, []Hold{HeldGate}},

		{"a bead a person owes", Facts{Owed: personOwed}, []Hold{HeldBlocked}},
		{"…and holds whatever is in flight beside it", Facts{Owed: personOwed, InFlightCount: 2}, []Hold{HeldBlocked}},
		{"two beads a person owes are one value", Facts{Owed: []person.Blocker{personOwed[0], {ID: "e", Title: "pick the reviewer", Status: "open", IssueType: "decision"}}}, []Hold{HeldBlocked}},

		{"a human gate and a bead a person owes stand together", Facts{Gates: oneGate, Owed: personOwed}, []Hold{HeldGate, HeldBlocked}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := Held(tc.f)
			if !slices.Equal(got, tc.want) {
				t.Errorf("Held(%+v) = %v, want %v", tc.f, got, tc.want)
			}
			if len(got) > 0 && Derive(tc.f) != NeedsAttention {
				t.Errorf("Held(%+v) = %v but Derive = %q, want needs-attention while any value stands", tc.f, got, Derive(tc.f))
			}
		})
	}
}

// OwnAttention tells a PR whose needs-attention rests on the human gates and
// the beads a person owes that hold it from one that reads needs-attention for
// a reason of its own as well, which still stands once those beads are
// answered.
func TestOwnAttention(t *testing.T) {
	for _, tc := range []struct {
		name string
		f    Facts
		want bool
	}{
		{"an open human gate alone", Facts{Gates: oneGate}, false},
		{"a bead a person owes alone", Facts{Owed: personOwed}, false},
		{"a human gate and a bead a person owes together", Facts{Gates: oneGate, Owed: personOwed}, false},
		{"a human gate beside the merge freeze", Facts{Gates: oneGate, MergeHold: "true"}, true},
		{"a bead a person owes beside the rebase hold", Facts{Owed: personOwed, RebaseHold: "true"}, true},
		{"the merge freeze alone", Facts{MergeHold: "true"}, true},
		{"a PR that waits only on its review", Facts{}, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := OwnAttention(tc.f); got != tc.want {
				t.Errorf("OwnAttention(%+v) = %v, want %v", tc.f, got, tc.want)
			}
			if OwnAttention(tc.f) && Derive(tc.f) != NeedsAttention {
				t.Errorf("OwnAttention(%+v) holds but Derive = %q, want needs-attention", tc.f, Derive(tc.f))
			}
		})
	}
}

// isSet mirrors the shell is_set: null and false arrive empty through
// `(v // "") | tostring`, and the string spellings of an unset flag read as
// unset too. A merge_hold carrying one of those must NOT read as a hold.
func TestIsSetMatchesTheShellTruthiness(t *testing.T) {
	for _, v := range []string{"", "false", "False", "FALSE", "0", "null"} {
		if isSet(v) {
			t.Errorf("isSet(%q) = true, want false (unset spelling)", v)
		}
		if got := Derive(Facts{MergeHold: v}); got != NeedsReview {
			t.Errorf("merge_hold=%q derived %q, want needs-review (not a hold)", v, got)
		}
	}
	for _, v := range []string{"true", "held", "1", "yes", "anything"} {
		if !isSet(v) {
			t.Errorf("isSet(%q) = false, want true (a set value)", v)
		}
	}
}
