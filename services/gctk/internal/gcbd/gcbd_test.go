package gcbd

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestScrubKeepsOnlyLF(t *testing.T) {
	in := []byte("a\x00b\x1fc\td\ne\rf")
	if got, want := string(Scrub(in)), "abcd\nef"; got != want {
		t.Fatalf("Scrub = %q, want %q", got, want)
	}
}

// The scrubbers are interchangeable or they are not: lifecycle.sh execs this
// binary when one is available and falls back to shell when it is not, so a
// payload one accepts and the other rejects is a difference the caller cannot
// see. Raw TAB and CR are the two bytes where the implementations last drifted.
func TestScrubAcceptsWhatTheShellFallbackAccepts(t *testing.T) {
	for _, tc := range []struct{ name, raw string }{
		{"raw tab in a JSON string", `[{"id":"b-1","notes":"col\tcol","metadata":{}}]`},
		{"raw CR in a JSON string", `[{"id":"b-1","notes":"line\rline","metadata":{}}]`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			raw := []byte(strings.NewReplacer(`\t`, "\t", `\r`, "\r").Replace(tc.raw))
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

// The shell fallback reads `gc bd show ... | scrub | jq '.[0] // empty'` with
// no pipefail: a payload printed beside a non-zero exit is a bead there. Show
// must agree, or a read-back whose `gc` also warned reports a landed
// transition as UNVERIFIED (exit 2) from one implementation and as a
// transition from the other.
func TestShowReadsThePayloadWhateverGcExitsWith(t *testing.T) {
	bin := t.TempDir()
	stub := "#!/bin/sh\necho '[{\"id\":\"b-1\",\"status\":\"open\",\"metadata\":{\"merge_result\":\"pull_request\"}}]'\nexit 1\n"
	if err := os.WriteFile(filepath.Join(bin, "gc"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	b := New().Show("b-1")
	if b == nil {
		t.Fatal("Show = nil for a payload printed beside exit 1; the shell fallback would have read it")
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
