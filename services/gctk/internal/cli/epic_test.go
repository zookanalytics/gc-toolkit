package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"testing"
)

// The create's filing runs through `gc bd` and is held end to end by
// assets/scripts/epic.test.sh, through the bridge the work skill calls. These
// cases hold the parse, the rule it applies before anything is filed, and how
// the create's exit and reply are read, including the replies the suite's
// stub store never gives.

func TestParseEpicCreate(t *testing.T) {
	cases := []struct {
		name string
		args []string
		want epicOpts
	}{
		{"a title and a hypothesis", []string{"Epic: x", "--hypothesis", "For whom, what, signal"},
			epicOpts{title: "Epic: x", fields: map[string]string{"epic_hypothesis": "For whom, what, signal"}}},
		{"every field, each in its key", []string{"T", "--handle", "h", "--hypothesis", "y", "--boundaries", "b",
			"--closure-condition", "c", "--indicators", "i"},
			epicOpts{title: "T", fields: map[string]string{"epic_handle": "h", "epic_hypothesis": "y",
				"epic_boundaries": "b", "epic_closure_condition": "c", "epic_indicators": "i"}}},
		{"the flags beside the fields", []string{"--parent", " tk-e ", "T", "-d", "Aim: a\nDone when: b", "--rig", "gc-toolkit"},
			epicOpts{title: "T", parent: "tk-e", description: "Aim: a\nDone when: b", rig: "gc-toolkit", fields: map[string]string{}}},
		{"--description is -d", []string{"T", "--description", "d"},
			epicOpts{title: "T", description: "d", fields: map[string]string{}}},
		{"a field of whitespace is a field not given", []string{"T", "--hypothesis", "  \n", "--handle", ""},
			epicOpts{title: "T", fields: map[string]string{}}},
		{"a field is trimmed", []string{"T", "--hypothesis", " y \n"},
			epicOpts{title: "T", fields: map[string]string{"epic_hypothesis": "y"}}},
	}
	for _, c := range cases {
		got, msg := parseEpicCreate(c.args)
		if msg != "" {
			t.Errorf("%s: parse refused: %s", c.name, msg)
			continue
		}
		if !reflect.DeepEqual(got, c.want) {
			t.Errorf("%s: got %+v, want %+v", c.name, got, c.want)
		}
	}
}

func TestParseEpicCreateRefusals(t *testing.T) {
	cases := []struct {
		args []string
		want string
	}{
		{nil, "no title"},
		{[]string{"  "}, "no title"},
		{[]string{"--hypothesis", "y"}, "no title"},
		{[]string{"T", "U"}, `a second title "U"`},
		{[]string{"T", "--type", "task"}, `unknown argument "--type"`},
		{[]string{"T", "--hypothesis"}, "flag --hypothesis needs a value"},
		{[]string{"T", "--handle", "a", "--handle", "b"}, "flag --handle given twice"},
		{[]string{"T", "-d", "a", "--description", "b"}, "flag --description given twice"},
	}
	for _, c := range cases {
		if _, msg := parseEpicCreate(c.args); !strings.Contains(msg, c.want) {
			t.Errorf("%q: parse said %q, want it to say %q", c.args, msg, c.want)
		}
	}
}

func TestEpicRefusal(t *testing.T) {
	hyp := map[string]string{"epic_hypothesis": "y"}
	cases := []struct {
		name       string
		o          epicOpts
		parentType string
		refused    bool
		says       []string
	}{
		{"an epic with no parent and a hypothesis is filed", epicOpts{title: "T", fields: hyp}, "", false, nil},
		{"an epic with no parent and no hypothesis is refused", epicOpts{title: "T", fields: map[string]string{"epic_handle": "h"}}, "",
			true, []string{"it has no parent", "--hypothesis", "is not an epic, and its work is ordinary flow"}},
		{"an epic under a task is an epic of its own", epicOpts{title: "T", parent: "tk-t", fields: map[string]string{}}, "task",
			true, []string{"its parent tk-t is a task, not an epic"}},
		{"a parent of no recorded type is no epic", epicOpts{title: "T", parent: "tk-x", fields: map[string]string{}}, "",
			true, []string{"its parent tk-x is a bead of no recorded type, not an epic"}},
		{"a Delivery with no hypothesis is filed", epicOpts{title: "Delivery: d", parent: "tk-e", fields: map[string]string{}}, "epic", false, nil},
		{"a Delivery takes no contract field", epicOpts{title: "Delivery: d", parent: "tk-e",
			fields: map[string]string{"epic_handle": "h", "epic_indicators": "i"}}, "epic",
			true, []string{"tk-e is an epic", "this is a Delivery", "but it was given --handle and --indicators"}},
		{"an epic under an epic with a hypothesis of its own is filed", epicOpts{title: "T", parent: "tk-e",
			fields: map[string]string{"epic_hypothesis": "y", "epic_handle": "h"}}, "epic", false, nil},
	}
	for _, c := range cases {
		why := epicRefusal(c.o, c.parentType)
		if (why != "") != c.refused {
			t.Errorf("%s: refusal = %q, want refused=%v", c.name, why, c.refused)
			continue
		}
		for _, s := range c.says {
			if !strings.Contains(why, s) {
				t.Errorf("%s: refusal %q does not say %q", c.name, why, s)
			}
		}
	}
}

func TestEpicDispatch(t *testing.T) {
	cases := []struct {
		args []string
		code int
	}{
		{nil, epicExitUsage},
		{[]string{"close"}, epicExitUsage},
		{[]string{"--help"}, epicExitDone},
		{[]string{"create", "--help"}, epicExitDone},
		{[]string{"create"}, epicExitUsage},
	}
	for _, c := range cases {
		var out, errb bytes.Buffer
		if got := Epic(c.args, &out, &errb); got != c.code {
			t.Errorf("Epic(%q) = %d, want %d (stderr %q)", c.args, got, c.code, errb.String())
		}
		if !strings.Contains(out.String()+errb.String(), "gctk epic create <title>") {
			t.Errorf("Epic(%q) printed no usage", c.args)
		}
	}
}

// epicGCStub answers `gc bd create` with $EPIC_STUB_REPLY on stdout,
// $EPIC_STUB_ERR on stderr and exit $EPIC_STUB_RC, and records its argv and
// its stdin.
const epicGCStub = `#!/bin/sh
printf '%s\n' "$*" >> "$EPIC_STUB_ARGV"
cat > "$EPIC_STUB_STDIN"
printf '%s' "$EPIC_STUB_REPLY"
[ -z "$EPIC_STUB_ERR" ] || printf '%s\n' "$EPIC_STUB_ERR" >&2
exit "$EPIC_STUB_RC"
`

func stubEpicGC(t *testing.T, reply string, rc int, errText string) (argvFile, stdinFile string) {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "gc"), []byte(epicGCStub), 0o755); err != nil {
		t.Fatal(err)
	}
	argvFile, stdinFile = filepath.Join(dir, "argv"), filepath.Join(dir, "stdin")
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("EPIC_STUB_ARGV", argvFile)
	t.Setenv("EPIC_STUB_STDIN", stdinFile)
	t.Setenv("EPIC_STUB_REPLY", reply)
	t.Setenv("EPIC_STUB_RC", strconv.Itoa(rc))
	t.Setenv("EPIC_STUB_ERR", errText)
	return argvFile, stdinFile
}

func TestEpicCreateFiling(t *testing.T) {
	create := []string{"create", "Epic: x", "--hypothesis", "For whom, what, signal", "-d", "about it"}
	run := func() (string, string, int) {
		var out, errb bytes.Buffer
		code := Epic(create, &out, &errb)
		return out.String(), errb.String(), code
	}

	t.Run("an exit 0 whose reply names the bead is the epic filed, in one create", func(t *testing.T) {
		argv, stdin := stubEpicGC(t, `{"id":"tk-n","title":"Epic: x"}`, 0, `gc bd: answering from the rig "r" store`)
		out, errText, code := run()
		if code != epicExitDone || out != "tk-n\n" {
			t.Fatalf("create = (%q, %d), want (tk-n, %d); stderr %q", out, code, epicExitDone, errText)
		}
		want := `bd create Epic: x -t epic --body-file - --metadata {"epic_hypothesis":"For whom, what, signal"} --json` + "\n"
		if got, _ := os.ReadFile(argv); string(got) != want {
			t.Errorf("gc ran %q, want the one create %q", got, want)
		}
		if body, _ := os.ReadFile(stdin); string(body) != "about it" {
			t.Errorf("the create's stdin was %q, want the description", body)
		}
		if !strings.Contains(errText, "filed tk-n, an epic carrying epic_hypothesis") {
			t.Errorf("stderr %q does not say what it filed", errText)
		}
	})

	// bd's error object, as cmd/bd/errors.go's jsonStdoutError prints it
	// for a create that fails in the write.
	bdErrorReply := func(message string) string {
		return "{\n  \"error\": " + strconv.Quote(message) + ",\n  \"schema_version\": 1\n}\n"
	}
	notice := `gc bd: answering from the rig "r" store`
	cases := []struct {
		name, reply string
		rc          int
		errText     string
		code        int
		says        []string
	}{
		{"a commit bd could not confirm leaves whether it was filed unknown, with bd's error",
			bdErrorReply("write commit result indeterminate after connection loss (not retried to avoid double-apply): " +
				"commit write tx: invalid connection: write commit result indeterminate"), 1, notice,
			epicExitUnknown, []string{"bd's create exited 1: write commit result indeterminate after connection loss",
				"so whether the epic was filed is unknown", "look for it by its title before filing it again"}},
		{"a refusal in bd's error object is read the same way, since its reply is the lost commit's",
			bdErrorReply("validation failed: field exceeds maximum length"), 1, notice,
			epicExitUnknown, []string{"bd's create exited 1: validation failed: field exceeds maximum length",
				"look for it by its title before filing it again"}},
		{"a non-zero exit prints no id, even when the reply names one", `{"id":"tk-n"}`, 4,
			"gc bd: managed Dolt unreachable; bd fell back to on-disk auto-import mode.",
			epicExitUnknown, []string{"exited 4", "managed Dolt unreachable", "look for it by its title before filing it again"}},
		{"a failure with no reply leaves whether it was filed unknown", ``, 1, "gc: create failed after the write",
			epicExitUnknown, []string{"exited 1", "create failed after the write", "look for it by its title"}},
		{"an exit 0 that names no bead leaves whether it was filed unknown", `not json`, 0, "",
			epicExitUnknown, []string{"exited 0 and its reply named no bead", "look for it by its title"}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			stubEpicGC(t, c.reply, c.rc, c.errText)
			out, errText, code := run()
			if code != c.code || out != "" {
				t.Fatalf("create = (%q, %d), want no id and exit %d; stderr %q", out, code, c.code, errText)
			}
			for _, s := range c.says {
				if !strings.Contains(errText, s) {
					t.Errorf("stderr %q does not say %q", errText, s)
				}
			}
			if strings.Contains(errText, "nothing was filed") {
				t.Errorf("stderr %q says nothing was filed after a create ran", errText)
			}
		})
	}
}

func TestEpicReply(t *testing.T) {
	cases := []struct{ out, id, bdError string }{
		{`{"id":"tk-n","title":"T"}`, "tk-n", ""},
		{`[{"id":"tk-n"}]`, "tk-n", ""},
		{`{"error":"no such parent"}`, "", "no such parent"},
		{`{"error":"  "}`, "", ""},
		{`{"id":""}`, "", ""},
		{`[]`, "", ""},
		{``, "", ""},
		{`not json`, "", ""},
		{`"tk-n"`, "", ""},
	}
	for _, c := range cases {
		if id, bdError := epicReply([]byte(c.out)); id != c.id || bdError != c.bdError {
			t.Errorf("epicReply(%q) = (%q, %q), want (%q, %q)", c.out, id, bdError, c.id, c.bdError)
		}
	}
}
