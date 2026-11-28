package cli

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/session"
)

// promptAlertStub puts a gc on PATH that logs each call's arguments on one
// line and answers the pass's reads as a city with one seat escalated at a
// prompt does. A mail send to $STUB_FAIL_TO exits 1, as gc does when its store
// is down, and any other send prints gc's JSON result.
func promptAlertStub(t *testing.T) (calls func() string) {
	t.Helper()
	bin := t.TempDir()
	log := filepath.Join(bin, "calls")
	stub := `#!/bin/sh
echo "$*" >> '` + log + `'
case "$1 $2 $3" in
  "events --type work.escalated")
    printf '%s\n' '{"seq":2,"type":"work.escalated","ts":"2026-11-23T13:35:46-07:00","actor":"controller","subject":"tk-cp742aw","message":"nudge_refused","payload":{"session_id":"s-1","session_name":"gc-toolkit__polecat-s-1","template":"gc-toolkit/gc-toolkit.polecat","bead_id":"tk-cp742aw","reason":"nudge_refused"}}' ;;
  "events --type session.pending")
    printf '%s\n' '{"seq":1,"type":"session.pending","ts":"2026-11-23T13:13:42-07:00","actor":"controller","subject":"s-1","payload":{"session_id":"s-1","request_id":"tmux-a","kind":"approval","metadata":{"tool_name":"Bash","command":"rm -rf build"}}}' ;;
  "events --type session.pending_cleared") exit 0 ;;
  "agent list --json") printf '%s\n' '{"agents":[{"name":"mechanik","qualified_name":"gc-toolkit.mechanik","scope":"city"}]}' ;;
  "mail send "*)
    if [ "$3" = "$STUB_FAIL_TO" ]; then echo 'gc mail send: store unavailable' >&2; exit 1; fi
    printf '%s\n' '{"schema_version":"1","ok":true,"command":"mail.send","action":"send","id":"m-1"}' ;;
  *) exit 9 ;;
esac
`
	if err := os.WriteFile(filepath.Join(bin, "gc"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	return func() string {
		raw, _ := os.ReadFile(log)
		return string(raw)
	}
}

// A send that fails exits 1 and names what was not mailed and to whom on
// standard error, with the record of what did go on standard output. The next
// run mails what the failed send owed and nothing else, and exits 0.
func TestPromptAlertFailsLoudlyOnAFailedSend(t *testing.T) {
	city := t.TempDir()
	if err := os.Mkdir(filepath.Join(city, ".gc"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("GC_CITY_PATH", city)
	t.Setenv("GC_ESCALATION_RECIPIENT", "")
	t.Setenv("STUB_FAIL_TO", "gc-toolkit.mechanik")
	calls := promptAlertStub(t)
	var out, errb bytes.Buffer
	if code := Run([]string{"session", "prompt-alert", "--agents", "mechanik"}, "", &out, &errb); code != 1 {
		t.Fatalf("exit %d, stderr %q", code, errb.String())
	}
	if !strings.Contains(errb.String(), `"Prompt waiting: session s-1 (gc-toolkit/gc-toolkit.polecat)" was not mailed to gc-toolkit.mechanik`) ||
		!strings.Contains(errb.String(), "store unavailable") {
		t.Errorf("stderr %q", errb.String())
	}
	var rec session.AlertRecord
	if err := json.Unmarshal(out.Bytes(), &rec); err != nil || len(rec.Alerted) != 1 || strings.Join(rec.Alerted[0].To, " ") != "human" {
		t.Errorf("record %q, %v", out.String(), err)
	}
	if n := strings.Count(calls(), "mail send "); n != 2 {
		t.Errorf("%d sends:\n%s", n, calls())
	}
	if _, err := os.Stat(filepath.Join(city, ".gc", "runtime", "packs", "gc-toolkit", session.AlertLedgerFile)); err != nil {
		t.Errorf("the ledger was not written in the city's runtime: %v", err)
	}
	t.Setenv("STUB_FAIL_TO", "")
	out.Reset()
	errb.Reset()
	if code := Run([]string{"session", "prompt-alert", "--agents", "mechanik"}, "", &out, &errb); code != 0 {
		t.Fatalf("exit %d, stderr %q", code, errb.String())
	}
	sends := strings.Count(calls(), "mail send ")
	if sends != 3 || !strings.Contains(calls(), "mail send gc-toolkit.mechanik --subject=Prompt waiting") {
		t.Errorf("%d sends:\n%s", sends, calls())
	}
}
