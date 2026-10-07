package gcbd

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestScrubDeletesEveryC0Byte(t *testing.T) {
	// Every C0 byte (U+0000–U+001F) goes, LF included; DEL (0x7f) and ordinary
	// text stay, because JSON forbids raw only the C0 range inside a string.
	in := []byte("a\x00b\x1fc\td\ne\rf\x7fg")
	if got, want := string(Scrub(in)), "abcdef\x7fg"; got != want {
		t.Fatalf("Scrub = %q, want %q", got, want)
	}
}

// The scrubbers are interchangeable or they are not: a subcommand ported from a
// script must read every payload the script's `tr -d '\000-\037'` scrub let
// through, or the port refuses a bead its script read. A raw TAB, LF, or CR
// inside a string is invalid JSON, and both must strip it.
func TestScrubAcceptsWhatTheShellScrubAccepts(t *testing.T) {
	for _, tc := range []struct{ name, raw string }{
		{"raw tab in a JSON string", `[{"id":"b-1","notes":"col\tcol","metadata":{}}]`},
		{"raw LF in a JSON string", `[{"id":"b-1","notes":"line\nline","metadata":{}}]`},
		{"raw CR in a JSON string", `[{"id":"b-1","notes":"line\rline","metadata":{}}]`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			raw := []byte(strings.NewReplacer(`\t`, "\t", `\n`, "\n", `\r`, "\r").Replace(tc.raw))
			if err := json.Unmarshal(raw, &[]Bead{}); err == nil {
				t.Fatal("fixture is not actually invalid JSON; the scrubber would prove nothing")
			}
			var rows []Bead
			if err := json.Unmarshal(Scrub(raw), &rows); err != nil {
				t.Fatalf("scrubbed payload still will not decode: %v", err)
			}
			if len(rows) != 1 || rows[0].ID != "b-1" {
				t.Fatalf("decoded %+v, want one bead b-1", rows)
			}
		})
	}
}

func TestScrubMakesAControlLacedPayloadDecodable(t *testing.T) {
	// The shape that breaks a live `bd show --json`: a raw control byte inside a
	// string literal, which is invalid JSON until it is stripped.
	raw := []byte(`[{"id":"b-1","notes":"line\x01two","metadata":{}}]`)
	raw = []byte(strings.Replace(string(raw), `\x01`, "\x01", 1))
	if err := json.Unmarshal(raw, &[]Bead{}); err == nil {
		t.Fatal("fixture is not actually invalid JSON; the scrubber would prove nothing")
	}
	var rows []Bead
	if err := json.Unmarshal(Scrub(raw), &rows); err != nil {
		t.Fatalf("scrubbed payload still will not decode: %v", err)
	}
	if len(rows) != 1 || rows[0].ID != "b-1" {
		t.Fatalf("decoded %+v, want one bead b-1", rows)
	}
}

// decode is the Show path's decode, without the subprocess.
func decode(t *testing.T, payload string) *Bead {
	t.Helper()
	dec := json.NewDecoder(strings.NewReader(payload))
	dec.UseNumber()
	var rows []Bead
	if err := dec.Decode(&rows); err != nil {
		t.Fatalf("decode %s: %v", payload, err)
	}
	return &rows[0]
}

func TestMetaMirrorsJqToString(t *testing.T) {
	b := decode(t, `[{"id":"b","metadata":{
		"s":"text","n":12,"f":1.5,"t":true,"no":false,"null":null,"obj":{"k":"v"}}}]`)
	for _, tc := range []struct{ key, want string }{
		{"s", "text"},
		// A number keeps its literal spelling; jq's `//` treats false, like
		// null and an absent key, as the empty string.
		{"n", "12"},
		{"f", "1.5"},
		{"t", "true"},
		{"no", ""},
		{"null", ""},
		{"absent", ""},
		{"obj", `{"k":"v"}`},
	} {
		if got := b.Meta(tc.key); got != tc.want {
			t.Errorf("Meta(%q) = %q, want %q", tc.key, got, tc.want)
		}
	}
}

func TestStatusLowerAndStringAccessors(t *testing.T) {
	b := decode(t, `[{"id":"b","status":"CLOSED","assignee":null,"notes":"n"}]`)
	if got := b.StatusLower(); got != "closed" {
		t.Errorf("StatusLower = %q, want %q", got, "closed")
	}
	if got := b.AssigneeString(); got != "" {
		t.Errorf("AssigneeString = %q, want empty for null", got)
	}
	if got := b.NotesString(); got != "n" {
		t.Errorf("NotesString = %q, want %q", got, "n")
	}
}

func TestMetaOnNilBeadIsEmpty(t *testing.T) {
	var b *Bead
	if got := b.Meta("anything"); got != "" {
		t.Errorf("Meta on a nil bead = %q, want empty", got)
	}
}

// The scripts read `gc bd show ... | scrub | jq '.[0] // empty'` with no
// pipefail: a payload printed beside a non-zero exit is a bead there. Show must
// agree, or a read-back whose `gc` also warned reports as UNVERIFIED (exit 2) a
// transition the script it replaces reported as landed.
func TestShowReadsThePayloadWhateverGcExitsWith(t *testing.T) {
	bin := t.TempDir()
	stub := "#!/bin/sh\necho '[{\"id\":\"b-1\",\"status\":\"open\",\"metadata\":{\"merge_result\":\"pull_request\"}}]'\nexit 1\n"
	if err := os.WriteFile(filepath.Join(bin, "gc"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	b := New().Show("b-1")
	if b == nil {
		t.Fatal("Show = nil for a payload printed beside exit 1; the scripts' read would have read it")
	}
	if got := b.Meta("merge_result"); got != "pull_request" {
		t.Errorf("merge_result = %q, want pull_request", got)
	}
	// A gc that cannot run at all is still unreadable.
	if err := os.Chmod(filepath.Join(bin, "gc"), 0o644); err != nil {
		t.Fatal(err)
	}
	if New().Show("b-1") != nil {
		t.Error("Show != nil when gc could not be started")
	}
}

// List decodes the array `gc bd list` prints, and fails CLOSED (ok=false) on
// anything that is not an array — the same signal the scripts got from
// `jq -e 'type == "array"'`. An empty selection is `[]`: rows nil, ok true.
func TestListDecodesArrayAndFailsClosed(t *testing.T) {
	writeGC := func(t *testing.T, body string) {
		t.Helper()
		bin := t.TempDir()
		if err := os.WriteFile(filepath.Join(bin, "gc"), []byte("#!/bin/sh\n"+body), 0o755); err != nil {
			t.Fatal(err)
		}
		t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	}

	t.Run("two rows", func(t *testing.T) {
		writeGC(t, `echo '[{"id":"k1","metadata":{"task_kind":"rework"}},{"id":"k2","metadata":{}}]'`)
		rows, ok := New().List("--metadata-field", "task_kind=rework")
		if !ok || len(rows) != 2 {
			t.Fatalf("List = (%d rows, ok=%v), want (2, true)", len(rows), ok)
		}
	})

	t.Run("empty selection is ok", func(t *testing.T) {
		writeGC(t, `echo '[]'`)
		rows, ok := New().List()
		if !ok || len(rows) != 0 {
			t.Fatalf("List on [] = (%d rows, ok=%v), want (0, true)", len(rows), ok)
		}
	})

	t.Run("a non-array fails closed", func(t *testing.T) {
		// bd show returns an object when nothing resolves; a list that answered
		// that way must not read as an empty result.
		writeGC(t, `echo '{"error":"nope"}'`)
		if _, ok := New().List(); ok {
			t.Error("List on an object = ok true; want ok false (fail closed)")
		}
	})

	t.Run("gc that cannot run fails closed", func(t *testing.T) {
		bin := t.TempDir() // no gc in it
		t.Setenv("PATH", bin)
		if _, ok := New().List(); ok {
			t.Error("List with no gc on PATH = ok true; want ok false")
		}
	})

	// bd_list's contract, which merge.sh reads every list through: a store
	// error mid-query can print an empty or partial array and exit 1, and a
	// caller that read it would merge on that partial view.
	t.Run("a non-zero exit fails closed whatever was printed", func(t *testing.T) {
		writeGC(t, "echo '[]'\nexit 1\n")
		if _, ok := New().List(); ok {
			t.Error("List on [] beside exit 1 = ok true; want ok false (bd_list fails a non-zero exit)")
		}
		writeGC(t, "echo '[{\"id\":\"k1\",\"metadata\":{}}]'\nexit 1\n")
		if _, ok := New().List(); ok {
			t.Error("List on a row beside exit 1 = ok true; want ok false")
		}
	})

	t.Run("a bare null or empty stdout fails closed", func(t *testing.T) {
		writeGC(t, "echo 'null'\n")
		if _, ok := New().List(); ok {
			t.Error("List on null = ok true; want ok false (null is not an array)")
		}
		writeGC(t, "exit 0\n")
		if _, ok := New().List(); ok {
			t.Error("List on empty stdout = ok true; want ok false")
		}
	})

	// `jq -e 'type == "array"'` fails the whole stream on `[]garbage`, so bytes
	// after the array make the read unreadable at exit 0 too: the rows ahead of
	// them are a view cut short, whether or not the array was empty.
	t.Run("anything after the array fails closed", func(t *testing.T) {
		for _, arr := range []string{`[]`, `[{"id":"k1","metadata":{}}]`} {
			for _, tail := range []string{`garbage`, `{"id":"k2","metad`, `[]`} {
				writeGC(t, "printf '%s\\n' '"+arr+tail+"'\n")
				if _, ok := New().List(); ok {
					t.Errorf("List on %s%s = ok true; want ok false", arr, tail)
				}
			}
		}
		// The control: whitespace after the array is no tail.
		writeGC(t, "printf '[{\"id\":\"k1\",\"metadata\":{}}]  \\n\\n'\n")
		if rows, ok := New().List(); !ok || len(rows) != 1 {
			t.Errorf("List on an array and trailing whitespace = (%d rows, ok=%v), want (1, true)", len(rows), ok)
		}
	})
}

// DepList shares List's decode and its strict exit contract: an edge probe that
// failed is not "no dependencies".
func TestDepListFailsClosedLikeList(t *testing.T) {
	writeGC := func(t *testing.T, body string) {
		t.Helper()
		bin := t.TempDir()
		if err := os.WriteFile(filepath.Join(bin, "gc"), []byte("#!/bin/sh\n"+body), 0o755); err != nil {
			t.Fatal(err)
		}
		t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	}
	writeGC(t, "echo '[{\"id\":\"blk\",\"status\":\"open\",\"metadata\":{}}]'\n")
	rows, ok := New().DepList("a", "--direction=down", "-t", "blocks", "--json")
	if !ok || len(rows) != 1 || rows[0].ID != "blk" {
		t.Fatalf("DepList = (%+v, ok=%v), want one row blk", rows, ok)
	}
	writeGC(t, "echo '[]'\nexit 1\n")
	if _, ok := New().DepList("a"); ok {
		t.Error("DepList on [] beside exit 1 = ok true; want ok false")
	}
	writeGC(t, "echo 'not-json'\n")
	if _, ok := New().DepList("a"); ok {
		t.Error("DepList on garbage = ok true; want ok false")
	}
	for _, out := range []string{`[]garbage`, `[{"id":"blk","status":"open","metadata":{}}]garbage`} {
		writeGC(t, "printf '%s\\n' '"+out+"'\n")
		if _, ok := New().DepList("a"); ok {
			t.Errorf("DepList on %s = ok true; want ok false (bytes after the array)", out)
		}
	}
}

// Show is the lenient read, the shell's `gc bd show ... | jq -c '.[0] // empty'`
// with jq's exit unread: jq prints the first array's row before it reaches the
// bytes after it. The same bytes fail List's strict read.
func TestShowReadsTheFirstArrayWhateverFollowsIt(t *testing.T) {
	t.Setenv("GC_NO_API", "1")
	bin := t.TempDir()
	stub := "#!/bin/sh\nprintf '%s\\n' '[{\"id\":\"b-1\",\"status\":\"open\",\"metadata\":{}}]garbage'\n"
	if err := os.WriteFile(filepath.Join(bin, "gc"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	if b := New().Show("b-1"); b == nil || b.ID != "b-1" {
		t.Fatalf("Show = %+v, want bead b-1: the shell's read prints it before the garbage", b)
	}
	if _, ok := New().List(); ok {
		t.Error("List on the same bytes = ok true; want ok false")
	}
}

// jq's `.status // "open"` substitutes only for a null or absent status. An
// empty string is a status of its own, and a liveness test keyed on the
// substitution must not read it as open.
func TestStatusLowerOrSubstitutesOnlyForNullOrAbsent(t *testing.T) {
	for _, tc := range []struct{ name, row, want string }{
		{"absent", `[{"id":"b"}]`, "open"},
		{"null", `[{"id":"b","status":null}]`, "open"},
		{"empty string", `[{"id":"b","status":""}]`, ""},
		{"set", `[{"id":"b","status":"IN_PROGRESS"}]`, "in_progress"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := decode(t, tc.row).StatusLowerOr("open"); got != tc.want {
				t.Errorf("StatusLowerOr(open) = %q, want %q", got, tc.want)
			}
		})
	}
	if got := decode(t, `[{"id":"b","status":null}]`).StatusLower(); got != "" {
		t.Errorf("StatusLower on a null status = %q, want empty", got)
	}
}
