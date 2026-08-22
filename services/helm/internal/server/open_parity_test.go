package server

// Parity between [parseOpenStdout] and the sentences gc-helm.sh actually
// prints.
//
// WHY THIS EXISTS SEPARATELY FROM open_test.go. The cases there feed the parser
// strings a human typed while reading the script — which proves the regexes
// match what the author BELIEVED the script says. This one reads the script and
// feeds the parser the sentences it really contains, so a reworded echo is
// caught here rather than silently degrading every open to the unclassified
// "opened" outcome in front of an operator.
//
// The precedent for a Go test reading a sibling source file is
// web/contract_parity_test.go, which parses ../internal/board/model.go for the
// same class of reason: two things that must agree, with nothing between them
// that would fail on its own.

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// scriptPath is gc-helm.sh, relative to this package.
const scriptPath = "../../../../assets/scripts/gc-helm.sh"

// successEchoRE finds cmd_open's success sentences: the `echo` lines that
// report a visit. Both live in cmd_open and both are exit-0 paths.
var successEchoRE = regexp.MustCompile(`(?m)^\s*echo "\$PROG: visit .*"$`)

// shellVars are the expansions in those sentences, with stand-in values chosen
// to be distinguishable from one another.
var shellVars = strings.NewReplacer(
	"$PROG", "gc-helm",
	"$existing", "tk-old99",
	"$VISIT", "tk-new11",
	"$bead", "tk-abc12",
	"$POOL", "gc-toolkit/gc-toolkit.converse",
)

func TestParseOpenStdoutMatchesTheScriptsRealSentences(t *testing.T) {
	src, err := os.ReadFile(filepath.Clean(scriptPath))
	if err != nil {
		t.Fatalf("read %s: %v — this test must not silently stop guarding the parser", scriptPath, err)
	}

	lines := successEchoRE.FindAllString(string(src), -1)
	if len(lines) != 2 {
		// A third success sentence, or a renamed one, needs a parser branch and
		// a decision about which outcome it is — not a silent fallthrough.
		t.Fatalf("found %d visit-reporting echo lines in gc-helm.sh, want 2:\n%s",
			len(lines), strings.Join(lines, "\n"))
	}

	got := map[string]string{} // outcome -> visit id
	for _, raw := range lines {
		line := strings.TrimSpace(raw)
		line = strings.TrimPrefix(line, `echo "`)
		line = strings.TrimSuffix(line, `"`)
		sentence := shellVars.Replace(line)
		if strings.Contains(sentence, "$") {
			t.Fatalf("unexpanded shell variable in %q — add it to shellVars", sentence)
		}
		outcome, visit := parseOpenStdout(sentence)
		if outcome == "opened" {
			t.Errorf("the parser did not classify a real script sentence:\n  %s", sentence)
			continue
		}
		if prev, dup := got[outcome]; dup {
			t.Errorf("two sentences both classified as %q (%q and %q)", outcome, prev, visit)
		}
		got[outcome] = visit
	}

	if got["filed"] != "tk-new11" {
		t.Errorf(`filed -> visit %q, want "tk-new11"`, got["filed"])
	}
	if got["existing"] != "tk-old99" {
		t.Errorf(`existing -> visit %q, want "tk-old99"`, got["existing"])
	}
}

// The stderr prefix trim must match what the script actually prefixes, or the
// operator reads a tool name where a sentence should start.
func TestFirstStderrLineTrimsTheScriptsRealPrefixes(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{"gc-helm: open: bead not found: 'zz-nope1' — no rig.\n", "bead not found: 'zz-nope1' — no rig."},
		{"gc-helm: could not enumerate rigs\n", "could not enumerate rigs"},
		{"\n\ngc-helm: open: --reason requires a value\n", "--reason requires a value"},
		{"", ""},
		{"   \n", ""},
	} {
		if got := firstStderrLine(tc.in); got != tc.want {
			t.Errorf("firstStderrLine(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}
