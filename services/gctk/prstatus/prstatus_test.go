package prstatus

import "testing"

// The precedence table, one row per case pr-status-label.test.sh asserts.
// Keeping them here too proves the rule in isolation from the `gc bd` gathering,
// so a failure names the logic or the wiring, never both at once.
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
		{"open visit on the anchor", Facts{OpenVisit: true}, NeedsAttention},
		{"open visit on an approved PR", Facts{OpenVisit: true, PRPosture: "approved@oid@t", PRMachine: "settled@oid@t"}, NeedsAttention},
		{"open visit outranks live work", Facts{OpenVisit: true, InFlightCount: 2}, NeedsAttention},
		{"a hold outranks an approval", Facts{MergeHold: "true", PRPosture: "approved@oid@t"}, NeedsAttention},

		// An approved PR with nothing known blocking it is the city's to land,
		// whatever it waits on: the merge pass, a required check still running
		// (progressing), or city work in flight on the way.
		{"approved, no machine verdict yet", Facts{PRPosture: "approved@oid@t"}, Merging},
		{"approved, the merge pass settled", Facts{PRPosture: "approved@oid@t", PRMachine: "settled@oid@t"}, Merging},
		{"approved, a required check still running", Facts{PRPosture: "approved@oid@t", PRMachine: "progressing@oid@t"}, Merging},
		{"approved with city work in flight", Facts{PRPosture: "approved@oid@t", InFlightCount: 1}, Merging},
		{"an approved draft the city opened", Facts{PRPosture: "approved@oid@t", OpenedAsDraft: "oid"}, Merging},

		// The merge pass's blocked verdict holds the PR at the head the posture
		// was read at. A verdict at another head was reached about another commit.
		{"blocked at the current head", Facts{PRPosture: "approved@oid@t", PRMachine: "blocked@oid@t", PRMachineCause: CauseReviewThreads}, NeedsAttention},
		{"blocked at a head the posture has left", Facts{PRPosture: "approved@new@t", PRMachine: "blocked@old@t", PRMachineCause: CauseCheckFailed}, Merging},
		{"blocked with no posture recorded", Facts{PRMachine: "blocked@oid@t", PRMachineCause: CauseRule}, NeedsAttention},
		{"blocked with no cause recorded", Facts{PRPosture: "approved@oid@t", PRMachine: "blocked@oid@t"}, NeedsAttention},
		{"blocked, with city work in flight on the cause", Facts{PRPosture: "approved@oid@t", PRMachine: "blocked@oid@t", PRMachineCause: CauseCheckFailed, InFlightCount: 1}, Merging},
		{"an unrouted blocker holds whatever is in flight", Facts{PRPosture: "approved@oid@t", PRMachine: "blocked@oid@t", PRMachineCause: CauseBlocker, InFlightCount: 2}, NeedsAttention},
		{"an unrouted blocker holds an unapproved PR", Facts{PRPosture: "review_required@oid@t", PRMachine: "blocked@oid@t", PRMachineCause: CauseBlocker, InFlightCount: 1}, NeedsAttention},

		// A recorded value outside its writer's vocabulary is a state the
		// derivation cannot name.
		{"an unknown posture value", Facts{PRPosture: "dismissed@oid@t"}, NeedsAttention},
		{"an unknown machine value", Facts{PRPosture: "approved@oid@t", PRMachine: "stalled@oid@t"}, NeedsAttention},
		{"an unknown blocked cause", Facts{PRPosture: "approved@oid@t", PRMachine: "blocked@oid@t", PRMachineCause: "mystery"}, NeedsAttention},
		{"a cause beside a verdict that is not blocked is not read", Facts{PRPosture: "approved@oid@t", PRMachine: "settled@oid@t", PRMachineCause: "mystery"}, Merging},

		// The open-as-draft stage: the city opened the PR as a draft and owes the
		// checks that flip it ready, so nothing asks a human to review it yet.
		{"draft the city opened, not yet readied", Facts{OpenedAsDraft: "abc"}, Working},
		{"draft readied, nothing in flight", Facts{OpenedAsDraft: "abc", DraftReadied: "abc"}, NeedsReview},
		{"draft readied at a later head", Facts{OpenedAsDraft: "abc", DraftReadied: "def"}, NeedsReview},
		{"draft stage under a hold", Facts{OpenedAsDraft: "abc", MergeHold: "true"}, NeedsAttention},
		{"draft stage with live work", Facts{OpenedAsDraft: "abc", InFlightCount: 1}, Working},
		{"readied marker alone is not the stage", Facts{DraftReadied: "abc"}, NeedsReview},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := Derive(tc.f); got != tc.want {
				t.Errorf("Derive(%+v) = %q, want %q", tc.f, got, tc.want)
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

// The stage test is presence, the prefilter pr-open.sh and gate-ensure.sh run on
// the same two oid markers, not the hold truthiness rule: any non-empty
// opened_as_draft opens the stage and any non-empty draft_readied ends it.
func TestInDraftStageIsMarkerPresence(t *testing.T) {
	for _, tc := range []struct {
		opened, readied string
		want            bool
	}{
		{"", "", false},
		{"abc", "", true},
		{"abc", "abc", false},
		{"", "abc", false},
		{"0", "", true},
		{"false", "", true},
		{"abc", "false", false},
	} {
		if got := inDraftStage(tc.opened, tc.readied); got != tc.want {
			t.Errorf("inDraftStage(%q, %q) = %v, want %v", tc.opened, tc.readied, got, tc.want)
		}
	}
}

// A posture or machine verdict stored as value@oid@instant is read as its value
// and the oid after it; a bare value with no '@' reads whole, with no oid.
func TestSplitDated(t *testing.T) {
	for _, tc := range []struct{ in, value, oid string }{
		{"", "", ""},
		{"approved", "approved", ""},
		{"approved@oid", "approved", "oid"},
		{"approved@oid@2026-09-27T00:00:00Z", "approved", "oid"},
		{"blocked@@2026-09-27T00:00:00Z", "blocked", ""},
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
