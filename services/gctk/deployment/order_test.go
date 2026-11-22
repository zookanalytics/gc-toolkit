package deployment

import (
	"os"
	"regexp"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/doctor"
)

// The order ships disabled and runs per rig, so the rigs it reports are the
// ones a city's config turns it on for. It runs the verb for its own rig, with
// the scripts directory the finding's writer is read from and the environment
// its env names, and the GitHub read ends well inside its timeout. The doctor
// records its last good run.
func TestTheOrder(t *testing.T) {
	raw, err := os.ReadFile("../../../orders/production-deploy-report.toml")
	if err != nil {
		t.Fatal(err)
	}
	m := regexp.MustCompile(`(?m)^timeout = "([0-9]+s)"$`).FindSubmatch(raw)
	if m == nil {
		t.Fatal("orders/production-deploy-report.toml names no timeout in seconds")
	}
	timeout, err := time.ParseDuration(string(m[1]))
	if err != nil {
		t.Fatal(err)
	}
	if 2*ReadBound >= timeout {
		t.Errorf("the GitHub read's bound %s leaves the finding's writer less than its own share of the order's timeout %s", ReadBound, timeout)
	}
	for _, want := range []string{
		`exec = "GCTK_SCRIPTS_DIR=\"$PACK_DIR/assets/scripts\" \"${GCTK_BIN:-$GC_CITY_PATH/.gc/services/gctk/bin/gctk}\" deployment report --rig \"$GC_RIG\" --environment \"$GCTK_DEPLOYMENT_ENVIRONMENT\""`,
		`scope = "rig"`, `enabled = false`, `trigger = "cooldown"`, `interval = "1h"`,
		"GCTK_DEPLOYMENT_ENVIRONMENT = \"" + Environment + "\"",
	} {
		if !strings.Contains(string(raw), want) {
			t.Errorf("orders/production-deploy-report.toml does not carry %s", want)
		}
	}
	if !slices.Contains(doctor.Monitors, "production-deploy-report") {
		t.Error("the order, production-deploy-report by its file's name, is not among the doctor's monitors")
	}
}
