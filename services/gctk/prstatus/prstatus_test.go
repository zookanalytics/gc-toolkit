package prstatus

import (
	"slices"
	"testing"
)

// oneGate is one open human gate that holds the anchor, as [Facts.Gates] carries
// it, and personOwed one bead a person owes the next move on, as [Facts.Owed]
// carries it.
var (
	oneGate    = []Blocker{gate("g")}
	personOwed = []Blocker{{ID: "d", Title: "pick the release window", Status: "open", IssueType: "decision"}}
)

// The precedence table, one row per case pr-status-label.test.sh asserts.
// Keeping them here too proves the rule in isolation from the gathering
// ([Read]), so a failure names the logic or the wiring, never both at once.
func TestDerive(t *testing.T) {
	for _, tc := range []struct {
		name string
		f    Facts
		want State
	}{
		{"nothing outstanding", Facts{}, NeedsReview},
		{"one bead in the in-flight set", Facts{InFlightCount: 1}, Working},
		{"empty in-flight set", Facts{InFlightCount: 0}, NeedsReview},
		{"sticky changes_requested, empty in-flight set", Facts{PRPosture: "changes_requested@oid@t"}, NeedsReview},
		{"changes_requested with live work", Facts{PRPosture: "changes_requested@oid@t", InFlightCount: 1}, Working},
		{"operator freeze merge_hold=true", Facts{MergeHold: "true"}, NeedsAttention},
		{"rebase hold", Facts{RebaseHold: "true"}, NeedsAttention},
		{"posture commented, empty in-flight set", Facts{PRPosture: "commented@oid@t"}, NeedsReview},
		{"needs-attention outranks working (hold + live work)", Facts{MergeHold: "true", InFlightCount: 2}, NeedsAttention},
		{"open human gate on the anchor", Facts{Gates: oneGate}, NeedsAttention},
		{"open human gate on an approved PR", Facts{Gates: oneGate, PRPosture: "approved@oid@t"}, NeedsAttention},
		{"open human gate outranks live work", Facts{Gates: oneGate, InFlightCount: 2}, NeedsAttention},
		{"a hold outranks an approval", Facts{MergeHold: "true", PRPosture: "approved@oid@t"}, NeedsAttention},

		// Whatever Held names is a thing a person has to act on, so it holds the PR
		// as a human gate on the anchor does, whatever is in flight beside it.
		{"a bead a person owes", Facts{Owed: personOwed}, NeedsAttention},
		{"a bead a person owes on an approved PR with work in flight", Facts{Owed: personOwed, PRPosture: "approved@oid@t", InFlightCount: 1}, NeedsAttention},

		// An approved PR with nothing known blocking it is the city's to land,
		// whatever it waits on, city work in flight on the way included.
		{"approved, nothing in flight", Facts{PRPosture: "approved@oid@t"}, Merging},
		{"approved with city work in flight", Facts{PRPosture: "approved@oid@t", InFlightCount: 1}, Merging},

		// A recorded posture outside its writer's vocabulary is a state the
		// derivation cannot name.
		{"an unknown posture value", Facts{PRPosture: "dismissed@oid@t"}, NeedsAttention},
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
		{"an approved PR the city is landing", Facts{PRPosture: "approved@oid@t", InFlightCount: 1}, nil},
		{"the merge freeze carries no held value", Facts{MergeHold: "true"}, nil},
		{"the rebase hold carries no held value", Facts{RebaseHold: "true"}, nil},

		{"an open human gate on the anchor", Facts{Gates: oneGate}, []Hold{HeldGate}},
		{"…whatever is in flight beside it", Facts{Gates: oneGate, InFlightCount: 1}, []Hold{HeldGate}},

		{"a bead a person owes", Facts{Owed: personOwed}, []Hold{HeldBlocked}},
		{"…and holds whatever is in flight beside it", Facts{Owed: personOwed, InFlightCount: 2}, []Hold{HeldBlocked}},
		{"two beads a person owes are one value", Facts{Owed: []Blocker{personOwed[0], {ID: "e", Title: "pick the reviewer", Status: "open", IssueType: "decision"}}}, []Hold{HeldBlocked}},

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

// A posture stored as value@oid@instant is read as its value and the oid after
// it; a bare value with no '@' reads whole, with no oid.
func TestSplitDated(t *testing.T) {
	for _, tc := range []struct{ in, value, oid string }{
		{"", "", ""},
		{"approved", "approved", ""},
		{"approved@oid", "approved", "oid"},
		{"approved@oid@2026-09-27T00:00:00Z", "approved", "oid"},
		{"commented@@2026-09-27T00:00:00Z", "commented", ""},
	} {
		if value, oid := splitDated(tc.in); value != tc.value || oid != tc.oid {
			t.Errorf("splitDated(%q) = (%q, %q), want (%q, %q)", tc.in, value, oid, tc.value, tc.oid)
		}
	}
	// The split reaches Derive: a dated approved posture lands merging.
	if got := Derive(Facts{PRPosture: "approved@abc123@2026-09-27T00:00:00Z"}); got != Merging {
		t.Errorf("dated approved posture derived %q, want merging", got)
	}
}
