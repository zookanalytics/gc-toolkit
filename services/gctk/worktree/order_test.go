package worktree

import (
	"os"
	"regexp"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/doctor"
)

// The order kills its run at its timeout, so the look's read deadline and its
// event's bound end inside it. The order runs the verb once for the city on
// its cooldown, and the doctor records its last good run.
func TestTheOrder(t *testing.T) {
	raw, err := os.ReadFile("../../../orders/orphan-work-detect.toml")
	if err != nil {
		t.Fatal(err)
	}
	m := regexp.MustCompile(`(?m)^timeout = "([0-9]+s)"$`).FindSubmatch(raw)
	if m == nil {
		t.Fatal("orders/orphan-work-detect.toml names no timeout in seconds")
	}
	timeout, err := time.ParseDuration(string(m[1]))
	if err != nil {
		t.Fatal(err)
	}
	if Deadline+CallBound >= timeout {
		t.Errorf("the deadline %s and the event's bound %s reach the order's timeout %s", Deadline, CallBound, timeout)
	}
	for _, want := range []string{
		`exec = "\"${GCTK_BIN:-$GC_CITY_PATH/.gc/services/gctk/bin/gctk}\" worktree salvage"`,
		`scope = "city"`, `trigger = "cooldown"`, `interval = "15m"`,
	} {
		if !strings.Contains(string(raw), want) {
			t.Errorf("orders/orphan-work-detect.toml does not carry %s", want)
		}
	}
	if !slices.Contains(doctor.Monitors, "orphan-work-detect") {
		t.Error("the order, orphan-work-detect by its file's name, is not among the doctor's monitors")
	}
}
