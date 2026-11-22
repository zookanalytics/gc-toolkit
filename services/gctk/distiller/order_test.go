package distiller

import (
	"os"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
)

// The order kills its run at its timeout, so the start's four bounds end inside
// it: the rig list's and the roster's, which the runtime adapter keeps, the
// store read's and the sling's. The start takes its lock without waiting, so
// the lock adds none. The order runs the verb once for the city on a daily
// cooldown.
func TestTheOrder(t *testing.T) {
	raw, err := os.ReadFile("../../../orders/feedback-distiller.toml")
	if err != nil {
		t.Fatal(err)
	}
	m := regexp.MustCompile(`(?m)^timeout = "([0-9]+s)"$`).FindSubmatch(raw)
	if m == nil {
		t.Fatal("orders/feedback-distiller.toml names no timeout in seconds")
	}
	timeout, err := time.ParseDuration(string(m[1]))
	if err != nil {
		t.Fatal(err)
	}
	if sum := gascity.RigListWait + gascity.RosterWait + StoreWait + SlingWait; sum >= timeout {
		t.Errorf("the start's bounds sum to %s, which reaches the order's timeout %s", sum, timeout)
	}
	for _, want := range []string{
		`exec = "\"${GCTK_BIN:-$GC_CITY_PATH/.gc/services/gctk/bin/gctk}\" distiller start"`,
		`scope = "city"`, `trigger = "cooldown"`, `interval = "24h"`,
	} {
		if !strings.Contains(string(raw), want) {
			t.Errorf("orders/feedback-distiller.toml does not carry %s", want)
		}
	}
}
