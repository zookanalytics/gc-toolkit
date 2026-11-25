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

// The order runs in every rig as it ships, and runs the verb for its own rig
// with the scripts directory the tracker's writer is read from. A pass whose
// two GitHub reads each run to their bound still leaves the writer most of the
// order's timeout, and the interval outlasts the timeout, so one pass ends
// before the next starts. The doctor records its last good run.
func TestTheOrder(t *testing.T) {
	raw, err := os.ReadFile("../../../orders/actions-track.toml")
	if err != nil {
		t.Fatal(err)
	}
	read := func(key string) time.Duration {
		m := regexp.MustCompile(`(?m)^` + key + ` = "([0-9]+[smh])"$`).FindSubmatch(raw)
		if m == nil {
			t.Fatalf("orders/actions-track.toml names no %s", key)
		}
		d, err := time.ParseDuration(string(m[1]))
		if err != nil {
			t.Fatal(err)
		}
		return d
	}
	timeout, interval := read("timeout"), read("interval")
	if 2*ReadBound >= timeout/2 {
		t.Errorf("two GitHub reads at their bound %s leave the writer less than half the order's timeout %s", ReadBound, timeout)
	}
	if interval <= timeout {
		t.Errorf("the interval %s does not outlast the timeout %s", interval, timeout)
	}
	for _, want := range []string{
		`exec = "GCTK_SCRIPTS_DIR=\"$PACK_DIR/assets/scripts\" \"${GCTK_BIN:-$GC_CITY_PATH/.gc/services/gctk/bin/gctk}\" actions track --rig \"$GC_RIG\""`,
		`scope = "rig"`, `trigger = "cooldown"`, `interval = "5m"`,
	} {
		if !strings.Contains(string(raw), want) {
			t.Errorf("orders/actions-track.toml does not carry %s", want)
		}
	}
	if regexp.MustCompile(`(?m)^enabled\b`).Match(raw) {
		t.Error("orders/actions-track.toml sets enabled, and the order runs in every rig as it ships")
	}
	if !slices.Contains(doctor.Monitors, "actions-track") {
		t.Error("the order, actions-track by its file's name, is not among the doctor's monitors")
	}
}
