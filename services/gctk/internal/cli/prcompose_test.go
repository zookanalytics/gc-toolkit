package cli

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// composeStub answers the reads a composition makes: `bd where` with
// $STUB_WHERE, the store gc resolves for the caller, `rig list` with
// $STUB_RIGS, the stores and their prefixes, and `bd list` with the rows each
// --metadata-field k=v keeps. A list's rows come from $STUB_ROWS, or, when
// $STUB_STORES maps each store's .beads directory to its rows, from the store
// the call names, as gc picks it: the one bd's --db names, else the one whose
// prefix begins the first id --id names, else the caller's. $STUB_LIST_FAIL
// fails every list, $STUB_WHERE_FAIL the where, and $STUB_LOG, when set, logs
// each call as the store it names, "-" for none, and its verb.
const composeStub = `#!/bin/sh
db=-
if [ "$1" = bd ] && [ "$2" = --db ]; then db="$3"; shift 3; set -- bd "$@"; fi
[ -z "$STUB_LOG" ] || printf '%s %s %s\n' "$db" "$1" "$2" >> "$STUB_LOG"
case "$1 $2" in
  "bd where") [ -z "$STUB_WHERE_FAIL" ] || { echo "no store here" >&2; exit 1; }; printf '%s\n' "$STUB_WHERE"; exit 0 ;;
  "rig list") printf '%s\n' "$STUB_RIGS"; exit 0 ;;
  "bd list") ;;
  *) echo unsupported >&2; exit 2 ;;
esac
[ -z "$STUB_LIST_FAIL" ] || { echo "simulated list failure" >&2; exit 1; }
shift 2
store=$db
filter='.'
while [ $# -gt 0 ]; do
  case "$1" in
    --id) shift; [ "$store" != - ] || store=$(printf '%s' "$STUB_RIGS" | jq -r --arg id "${1%%,*}" \
      '[ .rigs[] | select(.prefix as $p | $p != "" and ($id | startswith($p + "-"))) ] | .[0].path // empty | . + "/.beads"') ;;
    --metadata-field) shift; filter="$filter | map(select((.metadata[\"${1%%=*}\"] // \"\") == \"${1#*=}\"))" ;;
  esac
  shift
done
[ "$store" != - ] && [ -n "$store" ] || store=$(printf '%s' "$STUB_WHERE" | jq -r '.path')
if [ -n "$STUB_STORES" ]; then
  printf '%s' "$STUB_STORES" | jq -c --arg s "$store" ".[\$s] // [] | $filter"
else
  printf '%s' "$STUB_ROWS" | jq -c "$filter"
fi
`

// stubCompose puts composeStub first on PATH, answering every list with rows
// from the one store, a rig's, whose prefix begins the beads these tests name.
func stubCompose(t *testing.T, rows string) {
	t.Helper()
	bin := t.TempDir()
	if err := os.WriteFile(filepath.Join(bin, "gc"), []byte(composeStub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STUB_ROWS", rows)
	t.Setenv("STUB_STORES", "")
	t.Setenv("STUB_WHERE", `{"path":"/rig/.beads","prefix":"tk"}`)
	t.Setenv("STUB_RIGS", `{"rigs":[{"name":"rig","prefix":"tk","path":"/rig"}]}`)
	t.Setenv("STUB_LIST_FAIL", "")
	t.Setenv("STUB_WHERE_FAIL", "")
	t.Setenv("STUB_LOG", "")
	t.Setenv("GC_NO_API", "1")
}

const composeAnchor = `{"id":"tk-a","title":"Add the widget","issue_type":"feature","status":"open",` +
	`"description":"Build the widget.","created_at":"2026-01-01T00:00:00Z",` +
	`"metadata":{"branch":"polecat/tk-a","target":"main","check_set":"correctness","merge_result":"pull_request",` +
	`"pr_summary":"Adds the widget."}}`

type composed struct {
	Title           string `json:"title"`
	Body            string `json:"body"`
	Summary         string `json:"summary"`
	BranchBeads     string `json:"branch_beads"`
	BranchBeadCount int    `json:"branch_bead_count"`
}

func runCompose(t *testing.T, args ...string) (composed, string, string, int) {
	t.Helper()
	var out, errb bytes.Buffer
	code := Run(append([]string{"pr", "compose"}, args...), "", &out, &errb)
	var got composed
	if code == 0 {
		if err := json.Unmarshal(out.Bytes(), &got); err != nil {
			t.Fatalf("stdout is not one JSON object: %v: %q", err, out.String())
		}
	}
	return got, out.String(), errb.String(), code
}

func TestPRComposeANewPR(t *testing.T) {
	stubCompose(t, "["+composeAnchor+"]")
	got, raw, _, code := runCompose(t, "tk-a", "--target", "main", "--head", "abcdef1234567890", "--opening",
		"--gates", "correctness\tpre-open", "--sections", "summary")
	if code != 0 {
		t.Fatalf("exit %d", code)
	}
	if got.Title != "feat: Add the widget (tk-a)" || got.Summary != "written" || got.BranchBeads != "" {
		t.Errorf("%+v", got)
	}
	if !strings.HasPrefix(got.Body, "<!-- gc:pr-summary -->\n## Summary\n\nAdds the widget.\n") ||
		!strings.HasSuffix(got.Body, "- Gates `correctness` signed off pre-open at `abcdef12`. For CI status, see the PR checks.\n<!-- /gc:pr-summary -->\n") {
		t.Errorf("body:\n%s", got.Body)
	}
	if !strings.Contains(raw, `"<!-- gc:pr-summary -->`) {
		t.Errorf("the markers are escaped in the JSON: %s", raw)
	}
	got, _, _, code = runCompose(t, "tk-a", "--target", "trunk", "--head", "abcdef1234567890", "--opening",
		"--gates", "correctness\tpre-open", "--sections", "summary")
	if code != 0 || !strings.Contains(got.Body, "- Target: `trunk`\n") {
		t.Errorf("the region names the target given, not the bead's: exit %d:\n%s", code, got.Body)
	}
}

func TestPRComposeGatesGivenEmpty(t *testing.T) {
	stubCompose(t, "["+composeAnchor+"]")
	got, _, _, code := runCompose(t, "tk-a", "--target", "main", "--head", "abcdef12", "--opening", "--gates", "", "--sections", "summary")
	if code != 0 || got.Summary != "written" || !strings.Contains(got.Body, "- Anchor declares no pre-open gate (`check_set=correctness`); opened at `abcdef12`.") {
		t.Errorf("exit %d: %+v", code, got)
	}
	got, _, _, code = runCompose(t, "tk-a", "--target", "main", "--head", "abcdef12", "--opening", "--sections", "summary")
	if code != 0 || got.Summary != "needs-gates" || got.Body != "" {
		t.Errorf("without --gates: exit %d: %+v", code, got)
	}
}

func TestPRComposeAPublishedBody(t *testing.T) {
	rows := "[" + composeAnchor + `,{"id":"tk-b","title":"Rider","status":"closed","created_at":"2026-02-01T00:00:00Z",` +
		`"metadata":{"fold_target":"polecat/tk-a"}}]`
	stubCompose(t, rows)
	body := "Operator text.\n"
	file := filepath.Join(t.TempDir(), "body.md")
	if err := os.WriteFile(file, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	got, _, _, code := runCompose(t, "tk-a", "--target", "main", "--head", "abcdef12", "--body-file", file)
	if code != 0 || got.Summary != "unmanaged" || got.BranchBeads != "written" || got.BranchBeadCount != 2 {
		t.Fatalf("exit %d: %+v", code, got)
	}
	if !strings.HasPrefix(got.Body, "Operator text.\n\n<!-- gc:branch-beads -->\n") || !strings.Contains(got.Body, "- `tk-b` — Rider\n") {
		t.Errorf("body:\n%s", got.Body)
	}

	t.Run("from stdin", func(t *testing.T) {
		r, w, err := os.Pipe()
		if err != nil {
			t.Fatal(err)
		}
		if _, err := w.WriteString(body); err != nil {
			t.Fatal(err)
		}
		w.Close()
		stdin := os.Stdin
		os.Stdin = r
		defer func() { os.Stdin = stdin }()
		again, _, _, code := runCompose(t, "tk-a", "--target", "main", "--head", "abcdef12", "--body-file", "-")
		if code != 0 || again.Body != got.Body {
			t.Errorf("exit %d: %q", code, again.Body)
		}
	})
}

// A caller in another store than the bead's, here the city's, composes from the
// bead's store alone. gc routes the read by the bead's id to its rig's store,
// and the reads of the beads on its branch name no bead, so unpinned they would
// answer from the city's: the body would publish the city's bead and drop the
// rig's rider.
func TestPRComposeReadsTheBeadsOwnStore(t *testing.T) {
	stubCompose(t, "")
	t.Setenv("STUB_WHERE", `{"path":"/city/.beads","prefix":"hq"}`)
	t.Setenv("STUB_RIGS", `{"rigs":[{"name":"city","prefix":"hq","path":"/city"},{"name":"rig","prefix":"tk","path":"/rig"}]}`)
	t.Setenv("STUB_STORES", `{"/rig/.beads":[`+composeAnchor+`,`+
		`{"id":"tk-b","title":"Rider","status":"closed","created_at":"2026-02-01T00:00:00Z","metadata":{"fold_target":"polecat/tk-a"}}],`+
		`"/city/.beads":[{"id":"hq-x","title":"Another store's bead","status":"closed","created_at":"2026-02-02T00:00:00Z",`+
		`"metadata":{"fold_target":"polecat/tk-a"}}]}`)
	log := filepath.Join(t.TempDir(), "calls")
	t.Setenv("STUB_LOG", log)
	file := filepath.Join(t.TempDir(), "body.md")
	if err := os.WriteFile(file, []byte("Operator text.\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	got, _, _, code := runCompose(t, "tk-a", "--target", "main", "--head", "abcdef12", "--body-file", file)
	if code != 0 || got.BranchBeads != "written" || got.BranchBeadCount != 2 {
		t.Fatalf("exit %d: %+v", code, got)
	}
	if !strings.Contains(got.Body, "- `tk-b` — Rider\n") || strings.Contains(got.Body, "hq-x") {
		t.Errorf("the section lists the rig's rider and nothing from the city's store:\n%s", got.Body)
	}
	raw, err := os.ReadFile(log)
	if err != nil {
		t.Fatal(err)
	}
	lists := 0
	for _, call := range strings.Split(strings.TrimSpace(string(raw)), "\n") {
		if !strings.HasSuffix(call, " bd list") {
			continue
		}
		lists++
		if !strings.HasPrefix(call, "/rig/.beads ") {
			t.Errorf("a list named the store %q; want every list pinned to /rig/.beads", call)
		}
	}
	if lists != 4 {
		t.Errorf("the stub logged %d lists, want 4 (the bead, then its branch, fold_target and merged_target): %q", lists, raw)
	}
}

func TestPRComposeRefuses(t *testing.T) {
	stubCompose(t, "["+composeAnchor+"]")
	for name, args := range map[string][]string{
		"no head for the summary":         {"tk-a"},
		"no target for the summary":       {"tk-a", "--head", "x"},
		"an unknown section":              {"tk-a", "--target", "main", "--head", "x", "--sections", "summary,footer"},
		"a superseded PR with no head":    {"tk-a", "--target", "main", "--head", "x", "--opening", "--supersedes", "41"},
		"a superseded PR, not opening":    {"tk-a", "--target", "main", "--head", "x", "--supersedes", "41", "--superseded-head", "y"},
		"a superseded PR, a body to edit": {"tk-a", "--target", "main", "--head", "x", "--opening", "--body-file", "-", "--supersedes", "41", "--superseded-head", "y"},
		"no bead":                         {"--target", "main", "--head", "x"},
	} {
		if _, out, _, code := runCompose(t, args...); code != 1 || out != "" {
			t.Errorf("%s: exit %d, stdout %q", name, code, out)
		}
	}
	if _, out, errs, code := runCompose(t, "tk-gone", "--target", "main", "--head", "x"); code != 2 || out != "" || !strings.Contains(errs, "tk-gone") {
		t.Errorf("a bead the store does not hold: exit %d, %q, %q", code, out, errs)
	}
	if _, out, _, code := runCompose(t, "tk-a", "--target", "main", "--head", "x", "--body-file", filepath.Join(t.TempDir(), "absent")); code != 2 || out != "" {
		t.Errorf("a body that does not read: exit %d, %q", code, out)
	}
	t.Setenv("STUB_LIST_FAIL", "1")
	if _, out, _, code := runCompose(t, "tk-a", "--target", "main", "--head", "x"); code != 2 || out != "" {
		t.Errorf("a store that does not read: exit %d, %q", code, out)
	}
	t.Setenv("STUB_LIST_FAIL", "")
	t.Setenv("STUB_WHERE_FAIL", "1")
	if _, out, errs, code := runCompose(t, "tk-a", "--target", "main", "--head", "x"); code != 2 || out != "" || !strings.Contains(errs, "the store holding tk-a did not resolve") {
		t.Errorf("a store that does not resolve: exit %d, %q, %q", code, out, errs)
	}
}
