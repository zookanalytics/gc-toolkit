package actions

import (
	"os"
	"regexp"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/doctor"
)

// The order runs in every rig, since a rig opts in from its own repository, and
// runs the verb for its own rig with the scripts directory the finding's writer
// is read from. A pass that starts its last workflow at the start bound and
// reads it for the whole of both its GitHub reads still leaves the finding's
// writer half the order's timeout. The interval outlasts the timeout, and it is
// the Turn, so a workflow one pass leaves unread comes first in a later one.
// The doctor records its last good run.
func TestTheOrder(t *testing.T) {
	raw, err := os.ReadFile("../../../orders/actions-failure-report.toml")
	if err != nil {
		t.Fatal(err)
	}
	read := func(key string) time.Duration {
		m := regexp.MustCompile(`(?m)^` + key + ` = "([0-9]+[smh])"$`).FindSubmatch(raw)
		if m == nil {
			t.Fatalf("orders/actions-failure-report.toml names no %s", key)
		}
		d, err := time.ParseDuration(string(m[1]))
		if err != nil {
			t.Fatal(err)
		}
		return d
	}
	timeout, interval := read("timeout"), read("interval")
	if StartBound+2*ReadBound >= timeout/2 {
		t.Errorf("a workflow started at %s and read for %s leaves the finding's writer less than half the order's timeout %s", StartBound, 2*ReadBound, timeout)
	}
	if interval <= timeout {
		t.Errorf("the interval %s does not outlast the timeout %s", interval, timeout)
	}
	if interval != Turn {
		t.Errorf("the interval %s is not the Turn %s, so the passes do not each start one workflow further on", interval, Turn)
	}
	for _, want := range []string{
		`exec = "GCTK_SCRIPTS_DIR=\"$PACK_DIR/assets/scripts\" \"${GCTK_BIN:-$GC_CITY_PATH/.gc/services/gctk/bin/gctk}\" actions report --rig \"$GC_RIG\""`,
		`scope = "rig"`, `trigger = "cooldown"`, "#   " + Mark + "\n",
	} {
		if !strings.Contains(string(raw), want) {
			t.Errorf("orders/actions-failure-report.toml does not carry %s", want)
		}
	}
	if regexp.MustCompile(`(?m)^enabled\b`).Match(raw) {
		t.Error("orders/actions-failure-report.toml sets enabled, and a rig opts in from its own repository, so the order runs in every rig")
	}
	if !slices.Contains(doctor.Monitors, "actions-failure-report") {
		t.Error("the order, actions-failure-report by its file's name, is not among the doctor's monitors")
	}
}
