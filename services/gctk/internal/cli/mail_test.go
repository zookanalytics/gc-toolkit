package cli

import (
	"bytes"
	"strings"
	"testing"
)

// The pass needs the agents whose sessions it reads: a run that names none is
// a usage error, refused before it reads anything.
func TestMailNotifyNeedsItsAgents(t *testing.T) {
	for _, args := range [][]string{
		{"mail", "notify"},
		{"mail", "notify", "--agents", ""},
		{"mail", "notify", "--agents", " , "},
	} {
		var out, errb bytes.Buffer
		if code := Run(args, "test", &out, &errb); code != 2 {
			t.Errorf("%q exited %d: %s", args, code, errb.String())
		}
		if out.Len() != 0 || !strings.Contains(errb.String(), "agents") {
			t.Errorf("%q printed %q and %q", args, out.String(), errb.String())
		}
	}
}
