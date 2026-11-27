package session

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
	raw, err := os.ReadFile("../../../orders/seat-progress-detect.toml")
	if err != nil {
		t.Fatal(err)
	}
	m := regexp.MustCompile(`(?m)^timeout = "([0-9]+s)"$`).FindSubmatch(raw)
	if m == nil {
		t.Fatal("orders/seat-progress-detect.toml names no timeout in seconds")
	}
	timeout, err := time.ParseDuration(string(m[1]))
	if err != nil {
		t.Fatal(err)
	}
	if Deadline+CallBound >= timeout {
		t.Errorf("the deadline %s and the event's bound %s reach the order's timeout %s", Deadline, CallBound, timeout)
	}
	for _, want := range []string{
		`exec = "\"${GCTK_BIN:-$GC_CITY_PATH/.gc/services/gctk/bin/gctk}\" session progress"`,
		`scope = "city"`, `trigger = "cooldown"`, `interval = "30m"`,
	} {
		if !strings.Contains(string(raw), want) {
			t.Errorf("orders/seat-progress-detect.toml does not carry %s", want)
		}
	}
	if !slices.Contains(doctor.Monitors, "seat-progress-detect") {
		t.Error("the order, seat-progress-detect by its file's name, is not among the doctor's monitors")
	}
}

// The act's order runs the verb with --act once for the city when the look's
// event fires, with the pack's scripts named for its writer, and its read
// deadline ends inside the order's timeout. It notices nothing a look did not,
// so it is no monitor of the doctor's.
func TestTheActsOrder(t *testing.T) {
	raw, err := os.ReadFile("../../../orders/seat-progress-report.toml")
	if err != nil {
		t.Fatal(err)
	}
	m := regexp.MustCompile(`(?m)^timeout = "([0-9]+s)"$`).FindSubmatch(raw)
	if m == nil {
		t.Fatal("orders/seat-progress-report.toml names no timeout in seconds")
	}
	timeout, err := time.ParseDuration(string(m[1]))
	if err != nil {
		t.Fatal(err)
	}
	if Deadline >= timeout {
		t.Errorf("the deadline %s reaches the order's timeout %s", Deadline, timeout)
	}
	for _, want := range []string{
		`exec = "GCTK_SCRIPTS_DIR=\"$PACK_DIR/assets/scripts\" \"${GCTK_BIN:-$GC_CITY_PATH/.gc/services/gctk/bin/gctk}\" session progress --act"`,
		`scope = "city"`, `trigger = "event"`, `on = "` + EventType + `"`,
	} {
		if !strings.Contains(string(raw), want) {
			t.Errorf("orders/seat-progress-report.toml does not carry %s", want)
		}
	}
	if slices.Contains(doctor.Monitors, "seat-progress-report") {
		t.Error("the act's order is among the doctor's monitors")
	}
}
