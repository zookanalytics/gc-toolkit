package prstatus_test

import (
	"slices"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus/fixture"
)

// Each scenario every reader is tested against pins the status and the held
// values the definition gives its anchor, and each reason names a bead the
// scenario holds or none. A change to the rule changes these pins here, and the
// readers' tests, which compare with the definition's own answer, follow it.
func TestScenariosPinTheRule(t *testing.T) {
	scenarios, err := fixture.Scenarios()
	if err != nil {
		t.Fatal(err)
	}
	for _, sc := range scenarios {
		t.Run(sc.Name, func(t *testing.T) {
			ans, err := sc.Answer()
			if err != nil {
				t.Fatal(err)
			}
			var held []string
			for _, h := range ans.Held {
				held = append(held, string(h))
			}
			if string(ans.Status) != sc.Want.Status || !slices.Equal(held, sc.Want.Held) {
				t.Errorf("status=%q held=%v, want %q and %v", ans.Status, held, sc.Want.Status, sc.Want.Held)
			}
			for _, r := range ans.Reasons {
				if _, ok := sc.Bead(r.ID); r.ID != "" && !ok {
					t.Errorf("reason %+v names a bead the scenario does not hold", r)
				}
			}
			if prstatus.Derive(ans.Facts) != ans.Status {
				t.Errorf("the answer's status is not Derive's")
			}
		})
	}
}
