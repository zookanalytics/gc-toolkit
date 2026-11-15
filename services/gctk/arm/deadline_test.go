package arm

import (
	"os"
	"regexp"
	"testing"
	"time"
)

// The order that runs the start kills it at its timeout, so the start's
// deadline sits below that timeout, with room for the last sling it begins to
// run past its allowance. The order runs this verb in the store its rig names.
func TestTheDeadlineSitsBelowTheOrdersTimeout(t *testing.T) {
	raw, err := os.ReadFile("../../../orders/deferred-dispatch.toml")
	if err != nil {
		t.Fatal(err)
	}
	m := regexp.MustCompile(`(?m)^timeout = "([0-9]+s)"$`).FindSubmatch(raw)
	if m == nil {
		t.Fatal("orders/deferred-dispatch.toml names no timeout in seconds")
	}
	timeout, err := time.ParseDuration(string(m[1]))
	if err != nil {
		t.Fatal(err)
	}
	if passDeadline+slingAllowance >= timeout {
		t.Errorf("the start's deadline %s and one sling's allowance %s reach the order's timeout %s", passDeadline, slingAllowance, timeout)
	}
	for _, want := range []string{`bead start-armed --db \"$GC_RIG_ROOT/.beads\"`, `GCTK_SCRIPTS_DIR=\"$PACK_DIR/assets/scripts\"`, `scope = "rig"`, `trigger = "cooldown"`} {
		if !regexp.MustCompile(regexp.QuoteMeta(want)).Match(raw) {
			t.Errorf("orders/deferred-dispatch.toml does not carry %s", want)
		}
	}
	if regexp.MustCompile(`(?m)^no_work_gate\s*=`).Match(raw) {
		t.Error("orders/deferred-dispatch.toml opts out of the single-flight gate")
	}
}
