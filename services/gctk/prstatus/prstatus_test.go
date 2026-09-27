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
		{"signoff-cap park", Facts{MergeHold: "signoff_cap", SignoffCap: "codex"}, NeedsAttention},
		{"operator freeze merge_hold=true", Facts{MergeHold: "true"}, NeedsAttention},
		{"rebase hold", Facts{RebaseHold: "true"}, NeedsAttention},
		{"approved and merging (CLEAN)", Facts{PRPosture: "approved@oid@t", PRMergeState: "CLEAN@oid"}, Working},
		{"approved but wedged (BLOCKED), empty in-flight set", Facts{PRPosture: "approved@oid@t", PRMergeState: "BLOCKED@oid"}, NeedsAttention},
		{"approved + BLOCKED + live work is working", Facts{PRPosture: "approved@oid@t", PRMergeState: "BLOCKED@oid", InFlightCount: 1}, Working},
		{"posture commented, empty in-flight set", Facts{PRPosture: "commented@oid@t"}, NeedsReview},
		{"needs-attention outranks working (cap park + live work)", Facts{MergeHold: "signoff_cap", SignoffCap: "codex", InFlightCount: 2}, NeedsAttention},

		// merge_hold=signoff_cap WITHOUT a cap value is not the cap park; it is a
		// plain truthy hold, so isSet still catches it as needs-attention.
		{"signoff_cap hold with no cap value is still a hold", Facts{MergeHold: "signoff_cap"}, NeedsAttention},
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
	if got := Derive(Facts{PRPosture: "approved@abc123@2026-09-27T00:00:00Z"}); got != Working {
		t.Errorf("dated approved posture derived %q, want working", got)
	}
}
