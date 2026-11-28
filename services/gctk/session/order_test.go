package session

import (
	"os"
	"regexp"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/pelletier/go-toml/v2"

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

// The prompt-alert orders run the pass once for the city: one when Gas City
// escalates a seat and one when a prompt clears, since an order's event
// trigger names one event type. Each kills its run at its timeout, so the
// pass's deadline ends inside it, and each copies every message to the pack's
// mechanik, an agent the pack ships.
func TestThePromptAlertOrders(t *testing.T) {
	if _, err := os.Stat("../../../agents/mechanik/agent.toml"); err != nil {
		t.Fatalf("the pack ships no mechanik: %v", err)
	}
	for file, on := range map[string]string{
		"prompt-alert-on-escalation.toml": escalatedType,
		"prompt-alert-on-clear.toml":      clearedType,
	} {
		raw, err := os.ReadFile("../../../orders/" + file)
		if err != nil {
			t.Fatal(err)
		}
		var o struct {
			Order struct {
				Trigger, On, Interval, Scope, Timeout, Exec string
				Enabled                                     *bool
				Env                                         map[string]string
			}
		}
		if err := toml.Unmarshal(raw, &o); err != nil {
			t.Fatalf("%s: %v", file, err)
		}
		if o.Order.Trigger != "event" || o.Order.On != on || o.Order.Interval != "" || o.Order.Scope != "city" || o.Order.Enabled != nil {
			t.Errorf("%s: trigger %q on %q every %q, scope %q, enabled %v", file, o.Order.Trigger, o.Order.On, o.Order.Interval, o.Order.Scope, o.Order.Enabled)
		}
		if want := `"${GCTK_BIN:-$GC_CITY_PATH/.gc/services/gctk/bin/gctk}" session prompt-alert --agents "$GCTK_PROMPT_ALERT_AGENTS"`; o.Order.Exec != want {
			t.Errorf("%s: exec %q, want %q", file, o.Order.Exec, want)
		}
		timeout, err := time.ParseDuration(o.Order.Timeout)
		if err != nil || AlertDeadline >= timeout {
			t.Errorf("%s: the pass's deadline %s reaches the order's timeout %q", file, AlertDeadline, o.Order.Timeout)
		}
		if got := o.Order.Env["GCTK_PROMPT_ALERT_AGENTS"]; got != "mechanik" {
			t.Errorf("%s: GCTK_PROMPT_ALERT_AGENTS names %q", file, got)
		}
	}
}
