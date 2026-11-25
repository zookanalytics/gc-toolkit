package doctor

import (
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"
	"time"
)

// The grammar reads [[accepted]] tables of check, reason, ruling and an
// optional for, each a basic string on its own line, around comments and
// blank lines, with escapes decoded.
func TestParseAccepted(t *testing.T) {
	got, err := ParseAccepted(`# a comment

[[accepted]]
check = "rig:gc-toolkit:dolt-backup"
reason = "a \"quoted\" reason"
ruling = "a ruling"

  [[accepted]]
  check="dolt-compact-state"
  for = "90m"
  reason = "r"
  ruling = "u"
`)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got[0].Check != "rig:gc-toolkit:dolt-backup" || got[0].Reason != `a "quoted" reason` || got[0].For != "" ||
		got[1].Check != "dolt-compact-state" || got[1].For != "90m" || got[1].bound != 90*time.Minute {
		t.Fatalf("parsed %+v", got)
	}
}

// Every line the grammar does not read is refused, with its line, so an entry
// the file means to hold is never dropped.
func TestParseAcceptedRefuses(t *testing.T) {
	entry := "[[accepted]]\ncheck = \"a\"\nreason = \"r\"\nruling = \"u\"\n"
	for _, tc := range []struct{ name, text, says string }{
		{"a key outside a table", "check = \"a\"\n", "outside an [[accepted]] table"},
		{"another table", "[accepted]\n", "line 1 is neither"},
		{"an unknown key", entry + "owner = \"me\"\n", "not a key of an entry"},
		{"a key set twice", entry + "reason = \"again\"\n", "a second time"},
		{"a missing ruling", "[[accepted]]\ncheck = \"a\"\nreason = \"r\"\n", "has no ruling"},
		{"two entries for one check", entry + entry, "two entries name the check a"},
		{"a bare value", "[[accepted]]\ncheck = a\n", "line 2 is neither"},
		{"a trailing comment", "[[accepted]]\ncheck = \"a\" # why\n", "line 2 is neither"},
		{"two strings", "[[accepted]]\ncheck = \"a\" \"b\"\n", "not one basic string"},
		{"an empty value", "[[accepted]]\ncheck = \"\"\n", "sets check to nothing"},
		{"a for that is no duration", entry + "for = \"soon\"\n", "no Go duration over zero"},
		{"a for of zero", entry + "for = \"0s\"\n", "no Go duration over zero"},
	} {
		_, err := ParseAccepted(tc.text)
		if err == nil || !strings.Contains(err.Error(), tc.says) {
			t.Errorf("%s: err = %v, want one saying %q", tc.name, err, tc.says)
		}
	}
}

// An entry with no bound accepts its check however long it has failed, and one
// with a bound only while it has failed less than that.
func TestAccepts(t *testing.T) {
	es, err := ParseAccepted("[[accepted]]\ncheck = \"a\"\nreason = \"r\"\nruling = \"u\"\n[[accepted]]\ncheck = \"b\"\nfor = \"3h\"\nreason = \"r\"\nruling = \"u\"\n")
	if err != nil {
		t.Fatal(err)
	}
	if !es[0].Accepts(t0, t0.Add(1000*time.Hour)) {
		t.Error("an entry with no bound stops accepting")
	}
	if !es[1].Accepts(t0, t0.Add(3*time.Hour-time.Second)) || es[1].Accepts(t0, t0.Add(3*time.Hour)) {
		t.Error("a 3h entry does not end at 3h")
	}
}

// A file that does not read names its path.
func TestReadAcceptedNamesTheFile(t *testing.T) {
	p := filepath.Join(t.TempDir(), "accepted.toml")
	if _, err := ReadAccepted(p); err == nil {
		t.Fatal("a missing file read")
	}
	if err := os.WriteFile(p, []byte("check = \"a\"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := ReadAccepted(p); err == nil || !strings.Contains(err.Error(), p) {
		t.Fatalf("err = %v", err)
	}
}

// The pack's accepted file reads, and holds the entry the operator's approval
// of the design accepted: dolt-compact-state for three hours, with its reason
// and that ruling.
func TestThePacksAcceptedFile(t *testing.T) {
	es, err := ReadAccepted("../../../doctor/accepted.toml")
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]string{}
	for _, e := range es {
		got[e.Check] = e.For
		if e.Reason == "" || !strings.Contains(e.Ruling, "PR #1537") {
			t.Errorf("%s carries reason %q and ruling %q", e.Check, e.Reason, e.Ruling)
		}
	}
	if len(got) != 1 || got["dolt-compact-state"] != "3h" {
		t.Fatalf("the pack accepts %v", got)
	}
}

// The doctor order kills its run at its timeout, so the doctor's deadline and
// the run's three calls to the event log end inside it. The order runs the
// verb with the pack's accepted file, once for the city, every hour.
func TestTheOrder(t *testing.T) {
	raw, err := os.ReadFile("../../../orders/doctor-run.toml")
	if err != nil {
		t.Fatal(err)
	}
	m := regexp.MustCompile(`(?m)^timeout = "([0-9]+s)"$`).FindSubmatch(raw)
	if m == nil {
		t.Fatal("orders/doctor-run.toml names no timeout in seconds")
	}
	timeout, err := time.ParseDuration(string(m[1]))
	if err != nil {
		t.Fatal(err)
	}
	if Deadline+3*CallBound >= timeout {
		t.Errorf("the deadline %s and three calls of %s reach the order's timeout %s", Deadline, CallBound, timeout)
	}
	for _, want := range []string{
		`exec = "\"${GCTK_BIN:-$GC_CITY_PATH/.gc/services/gctk/bin/gctk}\" doctor run --accepted \"$PACK_DIR/doctor/accepted.toml\""`,
		`scope = "city"`, `trigger = "cooldown"`, `interval = "1h"`,
	} {
		if !strings.Contains(string(raw), want) {
			t.Errorf("orders/doctor-run.toml does not carry %s", want)
		}
	}
	if !slices.Contains(Monitors, "doctor-run") {
		t.Error("the order, doctor-run by its file's name, is not among the monitors")
	}
}
