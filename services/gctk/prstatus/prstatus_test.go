package prstatus

import "testing"

// The precedence table, one row per case pr-status-label.test.sh asserts.
// Keeping them here too proves the rule in isolation from the `gc bd` gathering,
// so a failure names the logic or the wiring, never both at once.
func TestDerive(t *testing.T) {
	for _, tc := range []struct {
		name       string
		f          Facts
		want       State
		wantReason Reason
	}{
		{"nothing outstanding", Facts{}, NeedsReview, ReasonNone},
		{"one active bead in the in-flight set", Facts{InFlightActive: 1}, Working, ReasonNone},
		{"empty in-flight set", Facts{}, NeedsReview, ReasonNone},
		{"sticky changes_requested, empty in-flight set", Facts{PRPosture: "changes_requested@oid@t"}, NeedsReview, ReasonNone},
		{"changes_requested with live work", Facts{PRPosture: "changes_requested@oid@t", InFlightActive: 1}, Working, ReasonNone},
		{"signoff-cap park", Facts{MergeHold: "signoff_cap", SignoffCap: "codex"}, NeedsAttention, ReasonCapPark},
		{"operator freeze merge_hold=true", Facts{MergeHold: "true"}, NeedsAttention, ReasonMergeHold},
		{"rebase hold", Facts{RebaseHold: "true"}, NeedsAttention, ReasonRebaseHold},
		{"approved and merging (CLEAN)", Facts{PRPosture: "approved@oid@t", PRMergeState: "CLEAN@oid"}, Working, ReasonNone},
		{"approved but wedged (BLOCKED), empty in-flight set", Facts{PRPosture: "approved@oid@t", PRMergeState: "BLOCKED@oid"}, NeedsAttention, ReasonApprovedWedged},
		{"approved + BLOCKED + active work is working", Facts{PRPosture: "approved@oid@t", PRMergeState: "BLOCKED@oid", InFlightActive: 1}, Working, ReasonNone},
		{"posture commented, empty in-flight set", Facts{PRPosture: "commented@oid@t"}, NeedsReview, ReasonNone},
		{"needs-attention outranks working (cap park + active work)", Facts{MergeHold: "signoff_cap", SignoffCap: "codex", InFlightActive: 2}, NeedsAttention, ReasonCapPark},

		// merge_hold=signoff_cap WITHOUT a cap value is not the cap park; it is a
		// plain truthy hold, so isSet still catches it as needs-attention.
		{"signoff_cap hold with no cap value is still a hold", Facts{MergeHold: "signoff_cap"}, NeedsAttention, ReasonMergeHold},

		// A blocked-only frontier is not working — the defect this fix closes. A
		// human visit on it is a conversation awaiting engagement; without one the
		// work has stalled.
		{"blocked-only frontier, no visit", Facts{InFlightBlocked: 1}, NeedsAttention, ReasonStall},
		{"blocked-only frontier, human visit awaits", Facts{InFlightBlocked: 1, HumanVisitAwaits: true}, NeedsAttention, ReasonVisitEngage},
		// An active member alongside a blocked one is the city still moving: working.
		{"active + blocked frontier is working", Facts{InFlightActive: 1, InFlightBlocked: 1}, Working, ReasonNone},
		{"active + blocked, visit present, still working", Facts{InFlightActive: 1, InFlightBlocked: 1, HumanVisitAwaits: true}, Working, ReasonNone},
		// A hold outranks a blocked frontier and names the hold, not the block.
		{"merge hold outranks a blocked frontier", Facts{MergeHold: "true", InFlightBlocked: 1, HumanVisitAwaits: true}, NeedsAttention, ReasonMergeHold},
		// A visit with no blocked work does not by itself flip the state.
		{"visit awaits but nothing blocked is needs-review", Facts{HumanVisitAwaits: true}, NeedsReview, ReasonNone},
		{"visit awaits with active work is working", Facts{InFlightActive: 1, HumanVisitAwaits: true}, Working, ReasonNone},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got, gotReason := Derive(tc.f)
			if got != tc.want {
				t.Errorf("Derive(%+v) state = %q, want %q", tc.f, got, tc.want)
			}
			if gotReason != tc.wantReason {
				t.Errorf("Derive(%+v) reason = %q, want %q", tc.f, gotReason, tc.wantReason)
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
		if got, _ := Derive(Facts{MergeHold: v}); got != NeedsReview {
			t.Errorf("merge_hold=%q derived %q, want needs-review (not a hold)", v, got)
		}
	}
	for _, v := range []string{"true", "signoff_cap", "1", "yes", "anything"} {
		if !isSet(v) {
			t.Errorf("isSet(%q) = false, want true (a set value)", v)
		}
	}
}

// A posture stored as value@oid@instant and a merge state as value@oid are read
// by the value before the first '@'; a bare value with no '@' reads whole.
func TestBeforeSplitsTheDatedValue(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{"", ""},
		{"approved", "approved"},
		{"approved@oid", "approved"},
		{"approved@oid@2026-09-27T00:00:00Z", "approved"},
	} {
		if got := before(tc.in, "@"); got != tc.want {
			t.Errorf("before(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
	// The split reaches Derive: a dated approved posture still lands working.
	if got, _ := Derive(Facts{PRPosture: "approved@abc123@2026-09-27T00:00:00Z"}); got != Working {
		t.Errorf("dated approved posture derived %q, want working", got)
	}
}
