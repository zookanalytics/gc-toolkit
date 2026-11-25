package cli

import (
	"bytes"
	"os"
	"strings"
	"testing"
)

// Whatever follows the bead is the note, read as no flag, so a note that
// starts as a Markdown list or as frontmatter does lands as written, through
// the command's own parser. A flag goes before the bead.
func TestBeadNoteTakesANoteThatStartsWithADash(t *testing.T) {
	for _, args := range [][]string{
		{"tk-sub", "- Keep the old endpoint"},
		{"--db", "", "tk-sub", "---\nname: the note"},
	} {
		log, store := stubCity(t, []byte("[]"))
		if args[0] == "--db" {
			args[1] = store
		}
		text := args[len(args)-1]
		var out, errb bytes.Buffer
		if code := Run(append([]string{"bead", "note"}, args...), "test", &out, &errb); code != 0 {
			t.Fatalf("the note %q exited %d: %s", text, code, errb.String())
		}
		raw, err := os.ReadFile(log)
		if err != nil {
			t.Fatal(err)
		}
		if !strings.Contains(string(raw), "update tk-sub --append-notes "+text+"\n") {
			t.Errorf("the store took no append of %q:\n%s", text, raw)
		}
		if got := strings.TrimSpace(out.String()); got != "noted tk-sub" {
			t.Errorf("standard output is %q, want the line that says the note landed", got)
		}
	}
}
