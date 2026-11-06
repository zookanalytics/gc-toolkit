package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// beadGCStub answers the two kinds of gc call `gctk bead` makes. A write (`bd
// update`, `bd close`, `bd create`, `bd dep`) prints $STUB_WRITE_OUT and
// $STUB_WRITE_ERR and exits $STUB_WRITE_RC, and writes nothing anywhere, so a
// write that exits 0 lands only as far as the rows the suite gives the read.
// The read-back (`bd list`) prints $STUB_ROWS and exits $STUB_LIST_RC. Every
// call goes to $STUB_LOG, one line each, every argument followed by "|".
const beadGCStub = `#!/bin/sh
{ printf 'gc|'; for a in "$@"; do printf '%s|' "$a"; done; echo; } >> "$STUB_LOG"
case "$1 $2" in
  "bd list")
    printf '%s\n' "$STUB_ROWS"
    exit "${STUB_LIST_RC:-0}" ;;
  "bd update"|"bd close"|"bd create"|"bd dep")
    [ -z "$STUB_WRITE_OUT" ] || printf '%s\n' "$STUB_WRITE_OUT"
    [ -z "$STUB_WRITE_ERR" ] || printf '%s\n' "$STUB_WRITE_ERR" >&2
    exit "${STUB_WRITE_RC:-0}" ;;
  *) echo "unsupported: $*" >&2; exit 2 ;;
esac
`

type beadRig struct {
	t   *testing.T
	log string
}

func newBeadRig(t *testing.T) *beadRig {
	t.Helper()
	bin := t.TempDir()
	if err := os.WriteFile(filepath.Join(bin, "gc"), []byte(beadGCStub), 0o755); err != nil {
		t.Fatal(err)
	}
	r := &beadRig{t: t, log: filepath.Join(t.TempDir(), "log")}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STUB_LOG", r.log)
	t.Setenv("STUB_ROWS", "[]")
	t.Setenv("STUB_LIST_RC", "0")
	t.Setenv("STUB_WRITE_OUT", "")
	t.Setenv("STUB_WRITE_ERR", "")
	t.Setenv("STUB_WRITE_RC", "0")
	return r
}

func (r *beadRig) run(args ...string) (int, string, string) {
	r.t.Helper()
	var out, errb bytes.Buffer
	rc := Bead(args, &out, &errb)
	return rc, out.String(), errb.String()
}

// calls returns the logged calls whose leading arguments are prefix, such as
// "gc|bd|list|".
func (r *beadRig) calls(prefix string) []string {
	r.t.Helper()
	raw, err := os.ReadFile(r.log)
	if err != nil && !os.IsNotExist(err) {
		r.t.Fatal(err)
	}
	var out []string
	for _, line := range strings.Split(string(raw), "\n") {
		if strings.HasPrefix(line, prefix) {
			out = append(out, line)
		}
	}
	return out
}

func TestBeadUpdateVerifyReadsTheSetKeysBackFromTheStoreTheWriteNamed(t *testing.T) {
	r := newBeadRig(t)
	t.Setenv("STUB_ROWS", `[{"id":"tk-1","status":"open","metadata":{"gc.superseded_by":"tk-2","gc.superseded_by_store":"rig:x"}}]`)
	rc, _, errOut := r.run("update", "tk-1", "--db", "/r/.beads", "--if-status", "open",
		"--set-metadata", "gc.superseded_by=tk-2", "--set-metadata", "gc.superseded_by_store=rig:x", "--verify")
	if rc != 0 {
		t.Fatalf("rc = %d, want 0; stderr: %s", rc, errOut)
	}
	writes := r.calls("gc|bd|update|")
	if len(writes) != 1 || writes[0] != "gc|bd|update|tk-1|--db|/r/.beads|--if-status|open|--set-metadata|gc.superseded_by=tk-2|--set-metadata|gc.superseded_by_store=rig:x|" {
		t.Errorf("the write gc bd got = %v, want the call's own flags with --verify taken off", writes)
	}
	reads := r.calls("gc|bd|list|")
	if len(reads) != 1 {
		t.Fatalf("reads = %v, want one", reads)
	}
	for _, want := range []string{"|--id|tk-1|", "|--all|", "|--include-gates|", "|--include-infra|", "|--include-templates|", "|--include-ephemeral|", "|--limit|0|", "|--json|", "|--db|/r/.beads|"} {
		if !strings.Contains(reads[0], want) {
			t.Errorf("the read %q does not carry %q", reads[0], want)
		}
	}
}

// A write that exits 0 and does not land is the case the command exists for:
// the store still holds the value the write was to replace.
func TestBeadUpdateVerifyExitsThreeForAWriteThatExitedZeroAndDidNotLand(t *testing.T) {
	r := newBeadRig(t)
	t.Setenv("STUB_ROWS", `[{"id":"tk-1","metadata":{"direct_landing_sha":"old"}}]`)
	rc, _, errOut := r.run("update", "tk-1", "--set-metadata", "direct_landing_sha=abc", "--verify")
	if rc != 3 {
		t.Fatalf("rc = %d, want 3", rc)
	}
	if !strings.Contains(errOut, `tk-1: direct_landing_sha reads "old", not "abc"`) {
		t.Errorf("stderr does not name what read back: %s", errOut)
	}
	t.Setenv("STUB_ROWS", `[{"id":"tk-1","metadata":{}}]`)
	if rc, _, errOut = r.run("update", "tk-1", "--set-metadata", "direct_landing_sha=abc", "--verify"); rc != 3 || !strings.Contains(errOut, "direct_landing_sha reads nothing") {
		t.Errorf("a key the store does not hold: rc = %d, stderr %s", rc, errOut)
	}
}

func TestBeadPassesARefusedWritesExitThroughAndReadsNothing(t *testing.T) {
	for _, code := range []string{"1", "4", "13"} {
		t.Run("exit "+code, func(t *testing.T) {
			r := newBeadRig(t)
			t.Setenv("STUB_WRITE_RC", code)
			t.Setenv("STUB_WRITE_ERR", "refused")
			rc, _, errOut := r.run("update", "tk-1", "--set-metadata", "k=v", "--verify")
			if want := map[string]int{"1": 1, "4": 4, "13": 13}[code]; rc != want {
				t.Errorf("rc = %d, want %d", rc, want)
			}
			if !strings.Contains(errOut, "refused") {
				t.Errorf("gc bd's stderr did not pass through: %q", errOut)
			}
			if reads := r.calls("gc|bd|list|"); len(reads) != 0 {
				t.Errorf("a refused write was read back: %v", reads)
			}
		})
	}
}

func TestBeadWithoutVerifyIsTheWriteAlone(t *testing.T) {
	r := newBeadRig(t)
	t.Setenv("STUB_WRITE_OUT", "updated tk-1")
	rc, out, _ := r.run("update", "tk-1", "--set-metadata", "k=v")
	if rc != 0 || !strings.Contains(out, "updated tk-1") {
		t.Errorf("rc = %d, stdout %q; want gc bd's own answer", rc, out)
	}
	if reads := r.calls("gc|bd|list|"); len(reads) != 0 {
		t.Errorf("a write without --verify was read back: %v", reads)
	}
}

// A pool can claim a bead right after its release and rewrite the route, the
// assignee and the session pins, so a release names the stamp it wrote as its
// witness, and the claim is no lost write.
func TestBeadVerifyKeyConfirmsOnlyTheKeysItNames(t *testing.T) {
	r := newBeadRig(t)
	t.Setenv("STUB_ROWS", `[{"id":"tk-1","status":"in_progress","assignee":"pool-1","metadata":{"gc.takeaway":"Parked","gc.takeaway_at":"2026-11-06T21:00:00Z","gc.session_id":"s-new"}}]`)
	rc, _, errOut := r.run("update", "tk-1", "--status=open", "--assignee=",
		"--set-metadata", "gc.takeaway=Parked", "--set-metadata", "gc.takeaway_at=2026-11-06T21:00:00Z",
		"--unset-metadata", "gc.session_id",
		"--verify-key", "gc.takeaway", "--verify-key", "gc.takeaway_at")
	if rc != 0 {
		t.Fatalf("rc = %d, want 0 for a stamp that read back under a claim; stderr: %s", rc, errOut)
	}
	if rc, _, errOut = r.run("update", "tk-1", "--status=open", "--set-metadata", "gc.takeaway=Parked", "--unset-metadata", "gc.session_id", "--verify-key", "gc.session_id"); rc != 3 || !strings.Contains(errOut, "gc.session_id still reads") {
		t.Errorf("an unset key named as the witness: rc = %d, stderr %s", rc, errOut)
	}
}

func TestBeadRefusesAWitnessTheWriteDoesNotWrite(t *testing.T) {
	r := newBeadRig(t)
	for _, args := range [][]string{
		{"update", "tk-1", "--set-metadata", "k=v", "--verify-key", "other"},
		{"update", "tk-1", "--title", "x", "--verify"},
		{"close", "tk-1", "--verify-key", "k"},
		{"update", "--set-metadata", "k=v", "tk-1", "--verify"},
		{"dep", "add", "tk-1", "--verify"},
		{"create", "--title", "x", "--metadata", "not-json", "--verify"},
	} {
		if rc, _, errOut := r.run(args...); rc != 2 || !strings.Contains(errOut, "nothing was run") {
			t.Errorf("%v: rc = %d, stderr %q; want a usage refusal", args, rc, errOut)
		}
	}
	if calls := r.calls("gc|"); len(calls) != 0 {
		t.Errorf("a refused call ran gc: %v", calls)
	}
}

// An update that writes no metadata is confirmed by the other fields it
// writes, such as the priority a settle writes to a batch of beads.
func TestBeadUpdateWithoutMetadataIsConfirmedByWhatElseItWrites(t *testing.T) {
	r := newBeadRig(t)
	t.Setenv("STUB_ROWS", `[{"id":"tk-1","priority":0},{"id":"tk-2","priority":0}]`)
	if rc, _, errOut := r.run("update", "tk-1", "tk-2", "--priority", "P0", "--verify"); rc != 0 {
		t.Fatalf("rc = %d, want 0; stderr: %s", rc, errOut)
	}
	t.Setenv("STUB_ROWS", `[{"id":"tk-1","priority":0},{"id":"tk-2","priority":2}]`)
	rc, _, errOut := r.run("update", "tk-1", "tk-2", "--priority", "0", "--verify")
	if rc != 3 || !strings.Contains(errOut, "tk-2: priority reads 2, not 0") || strings.Contains(errOut, "tk-1:") {
		t.Errorf("rc = %d, stderr %q; want tk-2 alone named", rc, errOut)
	}
	t.Setenv("STUB_ROWS", `[{"id":"tk-1","metadata":{},"notes":"before\nIntake: routed at P0"}]`)
	if rc, _, errOut := r.run("update", "tk-1", "--unset-metadata", "gc.recommended_formula", "--append-notes", "Intake: routed at P0", "--verify"); rc != 0 {
		t.Errorf("an unset and a note that read back: rc = %d, stderr %s", rc, errOut)
	}
	t.Setenv("STUB_ROWS", `[{"id":"tk-1","metadata":{},"notes":"before"}]`)
	if rc, _, errOut := r.run("update", "tk-1", "--append-notes", "Intake: routed at P0", "--verify"); rc != 3 || !strings.Contains(errOut, "notes do not carry") {
		t.Errorf("a note that did not land: rc = %d, stderr %s", rc, errOut)
	}
}

// bd stores a --set-metadata text of null, true, false or a number as that JSON
// value, so each reads back as the text written, and a number reads back equal
// to the text naming it.
func TestBeadVerifyReadsTypedValuesAsTheTextWritten(t *testing.T) {
	r := newBeadRig(t)
	t.Setenv("STUB_ROWS", `[{"id":"tk-1","metadata":{"n":42,"f":false,"t":true,"z":null,"s":"007","d":1.5,"e":""}}]`)
	rc, _, errOut := r.run("update", "tk-1", "--set-metadata", "n=42", "--set-metadata", "f=false",
		"--set-metadata", "t=true", "--set-metadata", "z=null", "--set-metadata", "s=007",
		"--set-metadata", "d=1.50", "--set-metadata", "e=", "--verify")
	if rc != 0 {
		t.Fatalf("rc = %d, want 0; stderr: %s", rc, errOut)
	}
	t.Setenv("STUB_ROWS", `[{"id":"tk-1","metadata":{"f":""}}]`)
	if rc, _, _ := r.run("update", "tk-1", "--set-metadata", "f=false", "--verify"); rc != 3 {
		t.Errorf("an empty value read back for false: rc = %d, want 3", rc)
	}
}

func TestBeadVerifyFailsClosedOnAReadThatShowsNothing(t *testing.T) {
	r := newBeadRig(t)
	t.Setenv("STUB_ROWS", `[{"id":"tk-1","metadata":{"k":"v"}}]`)
	t.Setenv("STUB_LIST_RC", "1")
	if rc, _, errOut := r.run("update", "tk-1", "--set-metadata", "k=v", "--verify"); rc != 3 || !strings.Contains(errOut, "tk-1 could not be read back") {
		t.Errorf("a read that exited 1: rc = %d, stderr %s", rc, errOut)
	}
	t.Setenv("STUB_LIST_RC", "0")
	t.Setenv("STUB_ROWS", `[{"id":"tk-other","metadata":{"k":"v"}}]`)
	if rc, _, errOut := r.run("update", "tk-1", "--set-metadata", "k=v", "--verify"); rc != 3 || !strings.Contains(errOut, "tk-1 did not read back") {
		t.Errorf("a read with no row for the bead: rc = %d, stderr %s", rc, errOut)
	}
}

func TestBeadCloseVerifyReadsTheBeadClosed(t *testing.T) {
	r := newBeadRig(t)
	t.Setenv("STUB_ROWS", `[{"id":"tk-1","status":"closed"}]`)
	if rc, _, errOut := r.run("close", "tk-1", "--reason", "done", "--verify"); rc != 0 {
		t.Fatalf("rc = %d, want 0; stderr: %s", rc, errOut)
	}
	if writes := r.calls("gc|bd|close|"); len(writes) != 1 || writes[0] != "gc|bd|close|tk-1|--reason|done|" {
		t.Errorf("the close gc bd got = %v", writes)
	}
	t.Setenv("STUB_ROWS", `[{"id":"tk-1","status":"open"}]`)
	if rc, _, errOut := r.run("close", "tk-1", "--reason", "done", "--verify"); rc != 3 || !strings.Contains(errOut, `status reads "open", not "closed"`) {
		t.Errorf("a close that did not land: rc = %d, stderr %s", rc, errOut)
	}
}

// A list row carries the bead's raw edges, an edge onto another store's bead
// among them, so an edge reads back by its far end and its kind.
func TestBeadDepVerifyReadsTheEdgeOffTheBeadsOwnRow(t *testing.T) {
	r := newBeadRig(t)
	t.Setenv("STUB_ROWS", `[{"id":"tk-c","dependencies":[{"issue_id":"tk-c","depends_on_id":"gf-gate","type":"replies-to"}]}]`)
	if rc, _, errOut := r.run("dep", "add", "tk-c", "gf-gate", "--type", "replies-to", "--verify"); rc != 0 {
		t.Fatalf("rc = %d, want 0; stderr: %s", rc, errOut)
	}
	if rc, _, errOut := r.run("dep", "add", "tk-c", "gf-gate", "--verify"); rc != 3 || !strings.Contains(errOut, "no blocks edge onto gf-gate") {
		t.Errorf("an add with no --type reads back as blocks: rc = %d, stderr %s", rc, errOut)
	}
	if writes := r.calls("gc|bd|dep|add|"); len(writes) != 2 || writes[0] != "gc|bd|dep|add|tk-c|gf-gate|--type|replies-to|" {
		t.Errorf("the adds gc bd got = %v", writes)
	}
	if rc, _, errOut := r.run("dep", "remove", "tk-c", "gf-gate", "--verify"); rc != 3 || !strings.Contains(errOut, "an edge onto gf-gate still reads back") {
		t.Errorf("a remove whose edge still reads back: rc = %d, stderr %s", rc, errOut)
	}
	t.Setenv("STUB_ROWS", `[{"id":"tk-c","dependencies":[]}]`)
	if rc, _, errOut := r.run("dep", "remove", "tk-c", "gf-gate", "--verify"); rc != 0 {
		t.Errorf("a remove whose edge is gone: rc = %d, stderr %s", rc, errOut)
	}
}

// A create's witness is everything it names, and the reply reaches the caller
// whatever the read found, so a caller can close a bead that did not read back
// whole.
func TestBeadCreateVerifyReadsTheNewBeadBackAndKeepsTheReply(t *testing.T) {
	r := newBeadRig(t)
	t.Setenv("STUB_WRITE_OUT", `[{"id":"tk-new"}]`)
	t.Setenv("STUB_ROWS", `[{"id":"tk-new","assignee":"human","metadata":{"target":"integration/tk-x","n":3},"dependencies":[{"depends_on_id":"tk-subj","type":"tracks"},{"depends_on_id":"tk-epic","type":"parent-child"}]}]`)
	rc, out, errOut := r.run("create", "-t", "task", "--title", "t", "--deps", "tracks:tk-subj", "--parent", "tk-epic",
		"--assignee", "human", "--metadata", `{"target":"integration/tk-x","n":3}`, "--verify")
	if rc != 0 {
		t.Fatalf("rc = %d, want 0; stderr: %s", rc, errOut)
	}
	if !strings.Contains(out, `"tk-new"`) {
		t.Errorf("the reply did not reach stdout: %q", out)
	}
	if writes := r.calls("gc|bd|create|"); len(writes) != 1 || !strings.HasSuffix(writes[0], "|--json|") {
		t.Errorf("a verified create asks gc bd for JSON: %v", writes)
	}
	t.Setenv("STUB_ROWS", `[{"id":"tk-new","assignee":"human","metadata":{},"dependencies":[]}]`)
	rc, out, errOut = r.run("create", "-t", "task", "--title", "t", "--deps", "tracks:tk-subj", "--assignee", "human", "--json", "--verify")
	if rc != 3 || !strings.Contains(errOut, "no tracks edge onto tk-subj") || !strings.Contains(out, `"tk-new"`) {
		t.Errorf("a create whose edge did not read back: rc = %d, stdout %q, stderr %s", rc, out, errOut)
	}
	t.Setenv("STUB_WRITE_OUT", `{"error":"nope"}`)
	if rc, _, errOut := r.run("create", "--title", "t", "--verify"); rc != 3 || !strings.Contains(errOut, "names no bead") {
		t.Errorf("a reply with no id: rc = %d, stderr %s", rc, errOut)
	}
}

// An explicit blocks: dep makes the target wait on the new bead, so the edge
// is read off the target's row.
func TestBeadCreateReadsAnExplicitBlocksDepOffItsTarget(t *testing.T) {
	r := newBeadRig(t)
	t.Setenv("STUB_WRITE_OUT", `{"id":"tk-gate"}`)
	t.Setenv("STUB_ROWS", `[{"id":"tk-gate"},{"id":"tk-subj","dependencies":[{"depends_on_id":"tk-gate","type":"blocks"}]}]`)
	if rc, _, errOut := r.run("create", "--title", "g", "--deps", "blocks:tk-subj", "--verify"); rc != 0 {
		t.Fatalf("rc = %d, want 0; stderr: %s", rc, errOut)
	}
	if reads := r.calls("gc|bd|list|"); len(reads) != 1 || !strings.Contains(reads[0], "|--id|tk-gate,tk-subj|") {
		t.Errorf("both beads are read in one list: %v", reads)
	}
}

// A blocks edge onto a bead another store holds is stored and holds nothing,
// so the edge reads back only with its far end read back from the same store.
func TestBeadBlocksEdgeReadsBackOnlyWithItsFarEndInTheStore(t *testing.T) {
	r := newBeadRig(t)
	t.Setenv("STUB_ROWS", `[{"id":"tk-sub","dependencies":[{"depends_on_id":"gf-child","type":"blocks"}]}]`)
	rc, _, errOut := r.run("dep", "add", "tk-sub", "gf-child", "--type=blocks", "--verify")
	if rc != 3 || !strings.Contains(errOut, "gf-child does not read back from this store, so the edge holds nothing") {
		t.Errorf("a blocks edge onto another store's bead: rc = %d, stderr %s", rc, errOut)
	}
	if reads := r.calls("gc|bd|list|"); len(reads) != 1 || !strings.Contains(reads[0], "|--id|tk-sub,gf-child|") {
		t.Errorf("the far end is read in the same list: %v", reads)
	}
	t.Setenv("STUB_ROWS", `[{"id":"tk-sub","dependencies":[{"depends_on_id":"tk-child","type":"blocks"}]},{"id":"tk-child"}]`)
	if rc, _, errOut := r.run("dep", "add", "tk-sub", "tk-child", "--type=blocks", "--verify"); rc != 0 {
		t.Errorf("a blocks edge with its far end in the store: rc = %d, stderr %s", rc, errOut)
	}
	t.Setenv("STUB_ROWS", `[{"id":"tk-c","dependencies":[{"depends_on_id":"gf-gate","type":"replies-to"}]}]`)
	if rc, _, errOut := r.run("dep", "add", "tk-c", "gf-gate", "--type", "replies-to", "--verify"); rc != 0 {
		t.Errorf("a reply, which holds nothing, needs no far end: rc = %d, stderr %s", rc, errOut)
	}
}
