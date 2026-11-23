package cli

import (
	"bytes"
	"os"
	"strings"
	"testing"
)

// A promise's call is checked before Gas City or the store is asked anything:
// a type the pack does not define, a missing bead, a conversation named as its
// own work, and work in another store each exit 2.
func TestGateCreateChecksItsCallFirst(t *testing.T) {
	log := stubLoggingGC(t, `{"rigs":[]}`)
	defer func() {
		if raw, _ := os.ReadFile(log); len(raw) != 0 {
			t.Errorf("a refused promise asked gc %q", raw)
		}
	}()
	for name, tc := range map[string]struct {
		args []string
		want string
	}{
		"a type the pack does not define": {[]string{"gate", "create", "--type", "human", "--await-id", "tk-w", "--blocks", "tk-c"}, "no gate type the pack defines"},
		"no type":                         {[]string{"gate", "create", "--await-id", "tk-w", "--blocks", "tk-c"}, "no gate type the pack defines"},
		"no work":                         {[]string{"gate", "create", "--type", "gctk:needs-review", "--blocks", "tk-c"}, "--await-id"},
		"no conversation":                 {[]string{"gate", "create", "--type", "gctk:needs-review", "--await-id", "tk-w"}, "--blocks"},
		"the conversation as its own work": {[]string{"gate", "create", "--type", "gctk:needs-review", "--await-id", "tk-c", "--blocks", "tk-c"},
			"cannot wait on a gate for itself"},
		"work in another store": {[]string{"gate", "create", "--type", "gctk:needs-review", "--await-id", "gc-w", "--blocks", "tk-c"}, "another store"},
	} {
		var out, errb bytes.Buffer
		if code := Run(tc.args, "test", &out, &errb); code != 2 || !strings.Contains(errb.String(), tc.want) {
			t.Errorf("%s exited %d, want 2 naming %q: %s", name, code, tc.want, errb.String())
		}
		if out.Len() != 0 {
			t.Errorf("%s printed %q, want no gate", name, out.String())
		}
	}
}
