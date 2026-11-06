package prstatus

import (
	"slices"
	"testing"
)

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
		{"open human gate on the anchor", Facts{OpenHumanGate: true}, NeedsAttention},
		{"open human gate on an approved PR", Facts{OpenHumanGate: true, PRPosture: "approved@oid@t", PRMachine: "settled@oid@t"}, NeedsAttention},
		{"open human gate outranks live work", Facts{OpenHumanGate: true, InFlightCount: 2}, NeedsAttention},
		{"a hold outranks an approval", Facts{MergeHold: "true", PRPosture: "approved@oid@t"}, NeedsAttention},

		// Whatever Held names is a thing a person has to act on, so it holds the PR
		// as a human gate on the anchor does, whatever is in flight beside it.
		{"a blocker a person owes", Facts{PersonBlocker: true}, NeedsAttention},
		{"a blocker a person owes on an approved PR with work in flight", Facts{PersonBlocker: true, PRPosture: "approved@oid@t", InFlightCount: 1}, NeedsAttention},
		{"review feedback the city has not answered, nothing in flight", Facts{PRPosture: "review_required@oid@t", PRMachine: "settled@oid@t", PRUnansweredThreads: "1@oid"}, NeedsAttention},
		{"…which a fix unit in flight answers", Facts{PRPosture: "review_required@oid@t", PRUnansweredThreads: "1@oid", InFlightCount: 1}, Working},
		{"…and an answer or a resolve releases", Facts{PRPosture: "review_required@oid@t", PRMachine: "settled@oid@t", PRUnansweredThreads: "0@oid"}, NeedsReview},

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
		{"the blocker cause holds whatever is in flight", Facts{PRPosture: "approved@oid@t", PRMachine: "blocked@oid@t", PRMachineCause: CauseBlocker, InFlightCount: 2}, NeedsAttention},
		{"the blocker cause holds an unapproved PR", Facts{PRPosture: "review_required@oid@t", PRMachine: "blocked@oid@t", PRMachineCause: CauseBlocker, InFlightCount: 1}, NeedsAttention},

		// A recorded value outside its writer's vocabulary is a state the
		// derivation cannot name.
		{"an unknown posture value", Facts{PRPosture: "dismissed@oid@t"}, NeedsAttention},
		{"an unknown machine value", Facts{PRPosture: "approved@oid@t", PRMachine: "stalled@oid@t"}, NeedsAttention},
		{"an unknown blocked cause", Facts{PRPosture: "approved@oid@t", PRMachine: "blocked@oid@t", PRMachineCause: "mystery"}, NeedsAttention},
		{"a cause beside a verdict that is not blocked is not read", Facts{PRPosture: "approved@oid@t", PRMachine: "settled@oid@t", PRMachineCause: "mystery"}, Merging},
		{"a thread count that is not a count", Facts{PRPosture: "review_required@oid@t", PRUnansweredThreads: "some@oid"}, NeedsAttention},
		{"…read whatever head it was counted at", Facts{PRPosture: "approved@new@t", PRUnansweredThreads: "-1@old"}, NeedsAttention},

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

// Blocked is the rule Derive reads a blocked verdict by, so each case also holds
// Derive to it: a verdict Blocked counts derives needs-attention, and one it
// does not count, with nothing else holding the PR, does not.
func TestBlocked(t *testing.T) {
	for _, tc := range []struct {
		name string
		f    Facts
		want bool
	}{
		{"at the posture's head, nothing in flight", Facts{PRPosture: "approved@oid@t", PRMachine: "blocked@oid@t", PRMachineCause: CauseCheckFailed}, true},
		{"no posture recorded", Facts{PRMachine: "blocked@oid@t", PRMachineCause: CauseRule}, true},
		{"no cause recorded", Facts{PRPosture: "approved@oid@t", PRMachine: "blocked@oid@t"}, true},
		{"at a head the posture has left", Facts{PRPosture: "approved@new@t", PRMachine: "blocked@old@t", PRMachineCause: CauseCheckFailed}, false},
		{"city work in flight on the cause", Facts{PRPosture: "approved@oid@t", PRMachine: "blocked@oid@t", PRMachineCause: CauseCheckFailed, InFlightCount: 1}, false},
		{"the blocker cause, whatever is in flight", Facts{PRPosture: "approved@oid@t", PRMachine: "blocked@oid@t", PRMachineCause: CauseBlocker, InFlightCount: 2}, true},
		{"the blocker cause on an unapproved PR", Facts{PRPosture: "review_required@oid@t", PRMachine: "blocked@oid@t", PRMachineCause: CauseBlocker, InFlightCount: 1}, true},
		{"the blocker cause at a head the posture has left", Facts{PRPosture: "approved@new@t", PRMachine: "blocked@old@t", PRMachineCause: CauseBlocker}, false},
		{"a cause outside the vocabulary at a head the posture has left", Facts{PRPosture: "approved@new@t", PRMachine: "blocked@old@t", PRMachineCause: "mystery"}, true},
		{"a cause outside the vocabulary with city work in flight", Facts{PRPosture: "approved@oid@t", PRMachine: "blocked@oid@t", PRMachineCause: "mystery", InFlightCount: 1}, true},
		{"a cause beside a verdict that is not blocked", Facts{PRPosture: "approved@oid@t", PRMachine: "settled@oid@t", PRMachineCause: "mystery"}, false},
		{"a verdict that is not blocked", Facts{PRPosture: "approved@oid@t", PRMachine: "settled@oid@t"}, false},
		{"no verdict recorded", Facts{PRPosture: "approved@oid@t"}, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := Blocked(tc.f); got != tc.want {
				t.Errorf("Blocked(%+v) = %v, want %v", tc.f, got, tc.want)
			}
			if got := Derive(tc.f) == NeedsAttention; got != tc.want {
				t.Errorf("Derive(%+v) reads needs-attention %v, want %v as Blocked reads it", tc.f, got, tc.want)
			}
		})
	}
}

// Held names each thing that holds the PR, in the order gate, review, blocked,
// and leaves out a value whose condition no longer stands. Any value means
// Derive reads needs-attention; the holds that carry no value (merge_hold and
// rebase_hold) read needs-attention with Held empty.
func TestHeld(t *testing.T) {
	approved := func(f Facts) Facts {
		f.PRPosture = "approved@oid@t"
		return f
	}
	threads := approved(Facts{PRMachine: "blocked@oid@t", PRMachineCause: CauseReviewThreads})
	stuck := approved(Facts{PRMachine: "blocked@oid@t", PRMachineCause: CauseBlocker})
	// The exemplar: an unapproved PR whose findings are closed, nothing in
	// flight, and an operator thread unresolved with no answer of the city's,
	// on a base that requires no thread resolution, so the merge pass records
	// no thread verdict.
	unanswered := Facts{PRPosture: "review_required@oid@t", PRMachine: "settled@oid@t", PRUnansweredThreads: "1@oid"}
	with := func(f Facts, edit func(*Facts)) Facts { edit(&f); return f }
	for _, tc := range []struct {
		name string
		f    Facts
		want []Hold
	}{
		{"nothing holds the PR", Facts{}, nil},
		{"an approved PR the city is landing", approved(Facts{PRMachine: "settled@oid@t", InFlightCount: 1}), nil},
		{"the merge freeze carries no held value", Facts{MergeHold: "true"}, nil},
		{"the rebase hold carries no held value", Facts{RebaseHold: "true"}, nil},

		{"an open human gate on the anchor", Facts{OpenHumanGate: true}, []Hold{HeldGate}},
		{"…whatever is in flight beside it", Facts{OpenHumanGate: true, InFlightCount: 1}, []Hold{HeldGate}},

		{"an unresolved required thread, nothing in flight", threads, []Hold{HeldReview}},
		{"the thread verdict with a fix in flight", func() Facts { f := threads; f.InFlightCount = 1; return f }(), nil},
		{"the thread verdict at a head the posture has left", func() Facts { f := threads; f.PRPosture = "approved@new@t"; return f }(), nil},
		{"a failed check is not a review hold", approved(Facts{PRMachine: "blocked@oid@t", PRMachineCause: CauseCheckFailed}), nil},
		{"a verdict that is not blocked keeps no thread cause", approved(Facts{PRMachine: "settled@oid@t", PRMachineCause: CauseReviewThreads}), nil},

		{"review feedback the city has not answered, nothing in flight", unanswered, []Hold{HeldReview}},
		{"…on an approved PR", approved(unanswered), []Hold{HeldReview}},
		{"…with no posture recorded yet", Facts{PRUnansweredThreads: "2@oid"}, []Hold{HeldReview}},
		{"…beside the thread verdict is one value", with(threads, func(f *Facts) { f.PRUnansweredThreads = "1@oid" }), []Hold{HeldReview}},
		{"every thread answered or resolved", with(unanswered, func(f *Facts) { f.PRUnansweredThreads = "0@oid" }), nil},
		{"a fix unit in flight answers the feedback", with(unanswered, func(f *Facts) { f.InFlightCount = 1 }), nil},
		{"feedback still waiting to be routed", with(unanswered, func(f *Facts) { f.PRPosture = "commented@oid@t" }), nil},
		{"a count read at a head the posture has left", with(unanswered, func(f *Facts) { f.PRPosture = "review_required@new@t" }), nil},
		{"a count recorded with no head", with(unanswered, func(f *Facts) { f.PRUnansweredThreads = "1" }), nil},

		{"a blocker no automated actor holds", stuck, []Hold{HeldBlocked}},
		{"the stuck blocker holds whatever is in flight", func() Facts { f := stuck; f.InFlightCount = 2; return f }(), []Hold{HeldBlocked}},
		{"the stuck blocker at a head the posture has left", func() Facts { f := stuck; f.PRPosture = "approved@new@t"; return f }(), nil},
		{"a blocker a person owes", Facts{PersonBlocker: true}, []Hold{HeldBlocked}},
		{"a stuck blocker beside one a person owes is one value", func() Facts { f := stuck; f.PersonBlocker = true; return f }(), []Hold{HeldBlocked}},

		{"a human gate and a person's blocker stand together", Facts{OpenHumanGate: true, PersonBlocker: true}, []Hold{HeldGate, HeldBlocked}},
		{"a human gate beside the thread verdict", func() Facts { f := threads; f.OpenHumanGate = true; return f }(), []Hold{HeldGate, HeldReview}},
		{"every value at once", func() Facts { f := threads; f.OpenHumanGate = true; f.PersonBlocker = true; return f }(), []Hold{HeldGate, HeldReview, HeldBlocked}},
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

// The PR's own work in flight is a review or rework child that is open or
// in_progress. Any other kind in the in-flight set, or a
// review or rework child at another live status, counts in flight and holds
// nothing.
func TestIsWork(t *testing.T) {
	for _, tc := range []struct {
		kind, status string
		want         bool
	}{
		{"review", "open", true},
		{"review", "in_progress", true},
		{"rework", "open", true},
		{"rework", "in_progress", true},
		{"review", "blocked", false},
		{"rework", "deferred", false},
		{"rework", "", false},
		{"validation", "open", false},
		{"finding", "in_progress", false},
		{"", "open", false},
	} {
		if got := IsWork(tc.kind, tc.status); got != tc.want {
			t.Errorf("IsWork(%q, %q) = %v, want %v", tc.kind, tc.status, got, tc.want)
		}
	}
}
