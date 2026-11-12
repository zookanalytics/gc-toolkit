package cli

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// composeStub answers `gc bd list` from $STUB_ROWS, a JSON array of rows,
// keeping the rows each --metadata-field k=v names, so a composition reads its
// bead and the beads on its branch with no store. $STUB_LIST_FAIL fails every
// list.
const composeStub = `#!/bin/sh
[ "$2" = list ] || { echo unsupported >&2; exit 2; }
[ -z "$STUB_LIST_FAIL" ] || { echo "simulated list failure" >&2; exit 1; }
shift 2
filter='.'
while [ $# -gt 0 ]; do
  case "$1" in
    --metadata-field) shift; filter="$filter | map(select((.metadata[\"${1%%=*}\"] // \"\") == \"${1#*=}\"))" ;;
  esac
  shift
done
printf '%s' "$STUB_ROWS" | jq -c "$filter"
`

func stubCompose(t *testing.T, rows string) {
	t.Helper()
	bin := t.TempDir()
	if err := os.WriteFile(filepath.Join(bin, "gc"), []byte(composeStub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STUB_ROWS", rows)
	t.Setenv("STUB_LIST_FAIL", "")
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
	got, raw, _, code := runCompose(t, "tk-a", "--head", "abcdef1234567890", "--opening",
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
}

func TestPRComposeGatesGivenEmpty(t *testing.T) {
	stubCompose(t, "["+composeAnchor+"]")
	got, _, _, code := runCompose(t, "tk-a", "--head", "abcdef12", "--opening", "--gates", "", "--sections", "summary")
	if code != 0 || got.Summary != "written" || !strings.Contains(got.Body, "- Anchor declares no pre-open gate (`check_set=correctness`); opened at `abcdef12`.") {
		t.Errorf("exit %d: %+v", code, got)
	}
	got, _, _, code = runCompose(t, "tk-a", "--head", "abcdef12", "--opening", "--sections", "summary")
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
	got, _, _, code := runCompose(t, "tk-a", "--head", "abcdef12", "--body-file", file)
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
		again, _, _, code := runCompose(t, "tk-a", "--head", "abcdef12", "--body-file", "-")
		if code != 0 || again.Body != got.Body {
			t.Errorf("exit %d: %q", code, again.Body)
		}
	})
}

func TestPRComposeRefuses(t *testing.T) {
	stubCompose(t, "["+composeAnchor+"]")
	for name, args := range map[string][]string{
		"no head for the summary":         {"tk-a"},
		"an unknown section":              {"tk-a", "--head", "x", "--sections", "summary,footer"},
		"a superseded PR with no head":    {"tk-a", "--head", "x", "--opening", "--supersedes", "41"},
		"a superseded PR, not opening":    {"tk-a", "--head", "x", "--supersedes", "41", "--superseded-head", "y"},
		"a superseded PR, a body to edit": {"tk-a", "--head", "x", "--opening", "--body-file", "-", "--supersedes", "41", "--superseded-head", "y"},
		"no bead":                         {"--head", "x"},
	} {
		if _, out, _, code := runCompose(t, args...); code != 1 || out != "" {
			t.Errorf("%s: exit %d, stdout %q", name, code, out)
		}
	}
	if _, out, errs, code := runCompose(t, "tk-gone", "--head", "x"); code != 2 || out != "" || !strings.Contains(errs, "tk-gone") {
		t.Errorf("a bead the store does not hold: exit %d, %q, %q", code, out, errs)
	}
	if _, out, _, code := runCompose(t, "tk-a", "--head", "x", "--body-file", filepath.Join(t.TempDir(), "absent")); code != 2 || out != "" {
		t.Errorf("a body that does not read: exit %d, %q", code, out)
	}
	t.Setenv("STUB_LIST_FAIL", "1")
	if _, out, _, code := runCompose(t, "tk-a", "--head", "x"); code != 2 || out != "" {
		t.Errorf("a store that does not read: exit %d, %q", code, out)
	}
}
