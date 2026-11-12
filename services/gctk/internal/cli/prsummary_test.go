package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// summaryStub answers `gc bd list --id <ids>` from $STUB_ROWS, a JSON array of
// rows, and appends each `gc bd update`'s arguments to $STUB_UPDATES, each
// ended by a NUL, an update ended by a blank one. $STUB_LIST_FAIL fails every
// list, and $STUB_UPDATE_FAIL every update.
const summaryStub = `#!/bin/sh
case "$2" in
  list)
    [ -z "$STUB_LIST_FAIL" ] || { echo "simulated list failure" >&2; exit 1; }
    ids=""
    while [ $# -gt 0 ]; do case "$1" in --id) ids="$2"; shift 2 ;; *) shift ;; esac; done
    printf '%s' "$STUB_ROWS" | jq -c --arg ids "$ids" '[.[] | select(.id as $i | $ids | split(",") | index($i))]' ;;
  update)
    [ -z "$STUB_UPDATE_FAIL" ] || { echo "simulated update failure" >&2; exit 1; }
    shift
    { for a in "$@"; do printf '%s\0' "$a"; done; printf '\0'; } >> "$STUB_UPDATES" ;;
  *) echo unsupported >&2; exit 2 ;;
esac
`

const summaryAnchor = `{"id":"tk-a","title":"Add the widget","issue_type":"feature","status":"open",` +
	`"created_at":"2026-01-01T00:00:00Z","metadata":{"pr_summary":"Adds the widget.\n\nAnd its stand.\n"}}`

// stubSummary puts the stub first on PATH over rows, and returns the file its
// updates are logged in.
func stubSummary(t *testing.T, rows string) string {
	t.Helper()
	bin := t.TempDir()
	if err := os.WriteFile(filepath.Join(bin, "gc"), []byte(summaryStub), 0o755); err != nil {
		t.Fatal(err)
	}
	updates := filepath.Join(bin, "updates")
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STUB_ROWS", rows)
	t.Setenv("STUB_UPDATES", updates)
	t.Setenv("STUB_LIST_FAIL", "")
	t.Setenv("STUB_UPDATE_FAIL", "")
	t.Setenv("GC_NO_API", "1")
	return updates
}

// updatesIn is each update the stub took, as its arguments.
func updatesIn(t *testing.T, file string) [][]string {
	t.Helper()
	raw, err := os.ReadFile(file)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		t.Fatal(err)
	}
	var out [][]string
	for _, u := range strings.Split(strings.TrimSuffix(string(raw), "\x00\x00"), "\x00\x00") {
		out = append(out, strings.Split(u, "\x00"))
	}
	return out
}

func runSummary(args ...string) (string, string, int) {
	var out, errb bytes.Buffer
	code := Run(append([]string{"pr", "summary"}, args...), "", &out, &errb)
	return out.String(), errb.String(), code
}

func writeFile(t *testing.T, text string) string {
	t.Helper()
	f := filepath.Join(t.TempDir(), "summary.md")
	if err := os.WriteFile(f, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
	return f
}

func TestPRSummaryPrintsWhatTheBeadRecords(t *testing.T) {
	stubSummary(t, "["+summaryAnchor+`,{"id":"tk-n","title":"None","status":"closed","metadata":{}}]`)
	out, _, code := runSummary("tk-a")
	if code != 0 || out != "Adds the widget.\n\nAnd its stand.\n" {
		t.Errorf("exit %d, printed %q", code, out)
	}
	if out, _, code = runSummary("tk-n"); code != 0 || out != "" {
		t.Errorf("a bead that records none: exit %d, printed %q", code, out)
	}
	out, errText, code := runSummary("tk-z")
	if code != 2 || out != "" || !strings.Contains(errText, "tk-z did not read") {
		t.Errorf("a bead the store does not hold: exit %d, printed %q, said %q", code, out, errText)
	}
	t.Setenv("STUB_LIST_FAIL", "1")
	if out, _, code = runSummary("tk-a"); code != 2 || out != "" {
		t.Errorf("a list that failed: exit %d, printed %q", code, out)
	}
}

func TestPRSummaryRecordsTheSummaryAndTheTitleInOneWrite(t *testing.T) {
	updates := stubSummary(t, "["+summaryAnchor+"]")
	_, errText, code := runSummary("tk-a", "--file", writeFile(t, "Reworks the widget.\n\nIts stand stays.\n\n"), "--title", "fix: rework the widget")
	if code != 0 || !strings.Contains(errText, "recorded the summary and the title on tk-a") {
		t.Fatalf("exit %d: %s", code, errText)
	}
	want := []string{"update", "tk-a", "--title", "fix: rework the widget", "--set-metadata", "pr_summary=Reworks the widget.\n\nIts stand stays."}
	if got := updatesIn(t, updates); len(got) != 1 || !slices.Equal(got[0], want) {
		t.Errorf("updates = %q, want one %q", got, want)
	}
}

func TestPRSummaryRecordsWhatItIsGiven(t *testing.T) {
	t.Run("a summary from stdin", func(t *testing.T) {
		updates := stubSummary(t, "["+summaryAnchor+"]")
		r, w, err := os.Pipe()
		if err != nil {
			t.Fatal(err)
		}
		stdin := os.Stdin
		os.Stdin = r
		t.Cleanup(func() { os.Stdin = stdin })
		if _, err := w.WriteString("From stdin.\n"); err != nil {
			t.Fatal(err)
		}
		w.Close()
		if _, errText, code := runSummary("tk-a", "--file", "-"); code != 0 {
			t.Fatalf("exit %d: %s", code, errText)
		}
		if got := updatesIn(t, updates); len(got) != 1 || !slices.Equal(got[0], []string{"update", "tk-a", "--set-metadata", "pr_summary=From stdin."}) {
			t.Errorf("updates = %q", got)
		}
	})
	t.Run("a title alone", func(t *testing.T) {
		updates := stubSummary(t, "["+summaryAnchor+"]")
		if _, errText, code := runSummary("tk-a", "--title", "feat: add the widget"); code != 0 || !strings.Contains(errText, "recorded the title on tk-a") {
			t.Fatalf("exit %d: %s", code, errText)
		}
		if got := updatesIn(t, updates); len(got) != 1 || !slices.Equal(got[0], []string{"update", "tk-a", "--title", "feat: add the widget"}) {
			t.Errorf("updates = %q", got)
		}
	})
}

func TestPRSummaryRefusesWhatHasNoWords(t *testing.T) {
	for name, args := range map[string][]string{
		"an empty file":                   {"--file", writeFile(t, "")},
		"a file of newlines":              {"--file", writeFile(t, "\n\n")},
		"a file of whitespace":            {"--file", writeFile(t, " \t\n \n"), "--title", "fix: keep it"},
		"an empty title":                  {"--title", ""},
		"an empty title beside a summary": {"--file", writeFile(t, "Words."), "--title", ""},
		"a title of whitespace":           {"--file", writeFile(t, "Words."), "--title", "  "},
		"an empty --file":                 {"--file", ""},
	} {
		t.Run(name, func(t *testing.T) {
			updates := stubSummary(t, "["+summaryAnchor+"]")
			_, errText, code := runSummary(append([]string{"tk-a"}, args...)...)
			if code != 1 || !strings.Contains(errText, "nothing was written") {
				t.Errorf("exit %d: %s", code, errText)
			}
			if got := updatesIn(t, updates); len(got) != 0 {
				t.Errorf("a refused record wrote %q", got)
			}
		})
	}
}

func TestPRSummaryNamesAWriteThatDidNotLand(t *testing.T) {
	updates := stubSummary(t, "["+summaryAnchor+"]")
	_, errText, code := runSummary("tk-a", "--file", filepath.Join(t.TempDir(), "absent.md"), "--title", "fix: x")
	if code != 2 || !strings.Contains(errText, "the summary did not read") {
		t.Errorf("a file that did not read: exit %d: %s", code, errText)
	}
	if got := updatesIn(t, updates); len(got) != 0 {
		t.Errorf("an unread file wrote %q", got)
	}
	t.Setenv("STUB_UPDATE_FAIL", "1")
	_, errText, code = runSummary("tk-a", "--file", writeFile(t, "Words."))
	if code != 2 || !strings.Contains(errText, "did not land") || !strings.Contains(errText, "simulated update failure") {
		t.Errorf("a refused update: exit %d: %s", code, errText)
	}
}
