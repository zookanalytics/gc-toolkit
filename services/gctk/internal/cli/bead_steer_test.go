package cli

import (
	"bytes"
	"os"
	"strings"
	"testing"
)

// A placement refused for what it asks exits 2 with the reason, before Gas City
// or the store is asked anything.
func TestBeadPlaceRefusesUsageBeforeAnyCall(t *testing.T) {
	log := stubLoggingGC(t, `{"rigs":[]}`)
	for name, tc := range map[string]struct {
		args []string
		want string
	}{
		"both placements":   {[]string{"bead", "place", "tk-new", "--under", "tk-epic", "--standalone"}, "two placements"},
		"neither placement": {[]string{"bead", "place", "tk-new"}, "--under <parent>"},
		"a bare route":      {[]string{"bead", "place", "tk-new", "--standalone", "--route", "polecat"}, "not rig-qualified"},
	} {
		var out, errb bytes.Buffer
		if code := Run(tc.args, "test", &out, &errb); code != 2 || !strings.Contains(errb.String(), tc.want) {
			t.Errorf("%s exited %d, want 2 naming %q: %s", name, code, tc.want, errb.String())
		}
	}
	if raw, _ := os.ReadFile(log); len(raw) != 0 {
		t.Errorf("a refused placement asked gc %q", raw)
	}
}

// A placement of a bead no rig's store holds exits 4 with nothing written.
func TestBeadPlaceOfABeadNoRigHolds(t *testing.T) {
	stubLoggingGC(t, `{"rigs":[{"name":"gc-toolkit","path":"/rig","prefix":"tk"}]}`)
	var out, errb bytes.Buffer
	if code := Run([]string{"bead", "place", "zz-1", "--standalone"}, "test", &out, &errb); code != 4 || !strings.Contains(errb.String(), "no rig's store holds zz-1") {
		t.Errorf("exited %d, want 4 naming the bead no rig holds: %s", code, errb.String())
	}
}

// A park's two forms are one call's choice: both or neither exit 2, and so does
// an empty text, before Gas City or the store is asked anything.
func TestBeadParkRefusesItsForms(t *testing.T) {
	log := stubLoggingGC(t, `{"rigs":[]}`)
	defer func() {
		if raw, _ := os.ReadFile(log); len(raw) != 0 {
			t.Errorf("a refused park asked gc %q", raw)
		}
	}()
	for name, tc := range map[string]struct {
		args []string
		want string
	}{
		"both forms":            {[]string{"bead", "park", "tk-e", "hold it", "--waiting-on", "tk-x"}, "two forms"},
		"neither form":          {[]string{"bead", "park", "tk-e"}, "--waiting-on <bead-id>"},
		"an empty text":         {[]string{"bead", "park", "tk-e", "  "}, "one-line headline"},
		"a body for no gate":    {[]string{"bead", "park", "tk-e", "--waiting-on", "tk-x", "--body", "b"}, "--body describes the gate"},
		"an empty --waiting-on": {[]string{"bead", "park", "tk-e", "--waiting-on", " "}, "--waiting-on requires a bead id"},
	} {
		var out, errb bytes.Buffer
		if code := Run(tc.args, "test", &out, &errb); code != 2 || !strings.Contains(errb.String(), tc.want) {
			t.Errorf("%s exited %d, want 2 naming %q: %s", name, code, tc.want, errb.String())
		}
	}
}

// An acceptance's vars are checked before anything is read, and a pull
// request's reference needs the pack's scripts, which resolve it.
func TestReactionAcceptChecksItsCallFirst(t *testing.T) {
	log := stubLoggingGC(t, `{"rigs":[]}`)
	t.Setenv("GCTK_SCRIPTS_DIR", "")
	var out, errb bytes.Buffer
	if code := Run([]string{"reaction", "accept", "tk-anc", "--var", "novalue"}, "test", &out, &errb); code != 2 || !strings.Contains(errb.String(), "--var takes <key>=<value>") {
		t.Errorf("a var with no key exited %d, want 2: %s", code, errb.String())
	}
	if raw, _ := os.ReadFile(log); len(raw) != 0 {
		t.Errorf("a refused var asked gc %q", raw)
	}
	errb.Reset()
	if code := Run([]string{"reaction", "accept", "1563"}, "test", &out, &errb); code != 4 || !strings.Contains(errb.String(), "GCTK_SCRIPTS_DIR") {
		t.Errorf("a PR reference with no scripts directory exited %d, want 4 naming GCTK_SCRIPTS_DIR: %s", code, errb.String())
	}
}
