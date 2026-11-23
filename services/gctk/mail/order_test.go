package mail

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/pelletier/go-toml/v2"
)

// The two orders run the pass once for the city, one when mail is sent and one
// when mail is replied to, since an order's event trigger names one event
// type, and each kills its run at its timeout, so the pass's deadline ends
// inside it. Each wakes the sessions of every converse template the pack
// ships, and of no other agent.
func TestTheOrders(t *testing.T) {
	entries, err := os.ReadDir("../../../agents")
	if err != nil {
		t.Fatal(err)
	}
	var converse []string
	for _, e := range entries {
		if e.IsDir() && strings.HasPrefix(e.Name(), "converse-") {
			converse = append(converse, e.Name())
		}
	}
	if len(converse) == 0 {
		t.Fatal("the pack ships no converse template under agents/")
	}
	for file, event := range map[string]string{"mail-notify-on-send.toml": "mail.sent", "mail-notify-on-reply.toml": "mail.replied"} {
		raw, err := os.ReadFile(filepath.Join("../../../orders", file))
		if err != nil {
			t.Fatal(err)
		}
		var o struct {
			Order struct {
				Trigger, On, Scope, Timeout, Exec string
				Enabled                           *bool
				Env                               map[string]string
			}
		}
		if err := toml.Unmarshal(raw, &o); err != nil {
			t.Fatalf("%s: %v", file, err)
		}
		if o.Order.Trigger != "event" || o.Order.On != event || o.Order.Scope != "city" || o.Order.Enabled != nil {
			t.Errorf("%s: trigger %q on %q, scope %q, enabled %v", file, o.Order.Trigger, o.Order.On, o.Order.Scope, o.Order.Enabled)
		}
		if want := `"${GCTK_BIN:-$GC_CITY_PATH/.gc/services/gctk/bin/gctk}" mail notify --agents "$GCTK_MAIL_NOTIFY_AGENTS"`; o.Order.Exec != want {
			t.Errorf("%s: exec %q, want %q", file, o.Order.Exec, want)
		}
		timeout, err := time.ParseDuration(o.Order.Timeout)
		if err != nil || Deadline >= timeout {
			t.Errorf("%s: the pass's deadline %s reaches the order's timeout %q", file, Deadline, o.Order.Timeout)
		}
		agents := strings.Fields(o.Order.Env["GCTK_MAIL_NOTIFY_AGENTS"])
		slices.Sort(agents)
		if !slices.Equal(agents, converse) {
			t.Errorf("%s: GCTK_MAIL_NOTIFY_AGENTS names %q, and the pack's converse templates are %q", file, agents, converse)
		}
	}
}
