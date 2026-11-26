package cli

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/rig"
)

// markGCStub answers the gc calls the pre-existing verbs and the carrier make.
// `bd list --id <id>` prints the rows of $STUB_STORE, a JSON array of listing
// rows, whose id is <id>, and fails for an id $STUB_LIST_FAIL names. `bd update`
// keeps the one --set-metadata pair it is given, or fails with STUB_UPDATE_RC.
// Every call is logged, one argv per line, and any other call fails.
const markGCStub = `#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_GC_LOG"
[ "$1" = bd ] || { echo "unexpected gc call: $*" >&2; exit 9; }
case "$2" in
  list)
    id=""; prev=""
    for a in "$@"; do [ "$prev" = --id ] && id=$a; prev=$a; done
    case " ${STUB_LIST_FAIL:-} " in *" $id "*) echo "list of $id failed" >&2; exit 1 ;; esac
    printf '%s' "$STUB_STORE" | jq -c --arg id "$id" '[.[] | select(.id == $id)]' ;;
  update)
    if [ "${STUB_UPDATE_RC:-0}" != 0 ]; then echo "update refused" >&2; exit "$STUB_UPDATE_RC"; fi
    shift 3
    while [ $# -gt 0 ]; do
      if [ "$1" = --set-metadata ]; then
        printf '%s' "${2%%=*}" > "$STUB_DIR/meta.key"
        printf '%s' "${2#*=}" > "$STUB_DIR/meta.value"
        shift 2
      else
        shift
      fi
    done ;;
  *) echo "unexpected gc call: $*" >&2; exit 9 ;;
esac
`

// row is one listing row of the stub's store.
func row(id, status string, meta map[string]string, edges ...[2]string) map[string]any {
	r := map[string]any{"id": id, "status": status, "metadata": meta}
	var deps []map[string]string
	for _, e := range edges {
		deps = append(deps, map[string]string{"issue_id": id, "type": e[0], "depends_on_id": e[1]})
	}
	if deps != nil {
		r["dependencies"] = deps
	}
	return r
}

// newMarkFixture is a rig fixture with lint's fail recorded at HEAD, and the
// mark stub as its gc.
func newMarkFixture(t *testing.T) (*rigFixture, *rig.Record) {
	t.Helper()
	f := newRigFixture(t)
	if err := os.WriteFile(filepath.Join(f.stub, "gc"), []byte(markGCStub), 0o755); err != nil {
		t.Fatal(err)
	}
	if code, _, errs := f.call("lint", "--command", "exit 1"); code != 1 {
		t.Fatalf("recording lint's fail = %d:\n%s", code, errs)
	}
	return f, f.record("lint", f.head())
}

func (f *rigFixture) store(rows ...map[string]any) {
	f.t.Helper()
	raw, err := json.Marshal(rows)
	if err != nil {
		f.t.Fatal(err)
	}
	f.t.Setenv("STUB_STORE", string(raw))
}

func (f *rigFixture) markValue(record *rig.Record, trackers ...string) string {
	f.t.Helper()
	raw, err := json.Marshal(map[string]any{"commit": f.head(), "record": record, "trackers": trackers})
	if err != nil {
		f.t.Fatal(err)
	}
	return string(raw)
}

func TestRigPreExistingAnswersWhetherTheMarkHolds(t *testing.T) {
	f, fail := newMarkFixture(t)
	marked := map[string]string{"rig_check_pre_existing.lint": f.markValue(fail, "tk-t1")}
	f.store(row("tk-w", "in_progress", marked), row("tk-t1", "open", nil))
	code, out, errs := f.call("pre-existing", "lint", "--bead", "tk-w")
	if code != 0 || out != "pre-existing, tracked by tk-t1\n" {
		t.Fatalf("an open tracker = %d %q:\n%s", code, out, errs)
	}
	for _, id := range []string{"tk-w", "tk-t1"} {
		if len(f.gcCalls("bd list --id "+id+" ")) == 0 {
			t.Errorf("no read of %s alone, which gc routes by its id: %q", id, f.gcCalls(""))
		}
	}

	f.store(row("tk-w", "in_progress", marked), row("tk-t1", "closed", nil))
	code, out, _ = f.call("pre-existing", "lint", "--bead", "tk-w")
	if code != 1 || !strings.Contains(out, "names no open tracker") || !strings.Contains(out, "merge the base in") {
		t.Errorf("a closed tracker = %d %q, want 1 and why", code, out)
	}

	t.Setenv("STUB_LIST_FAIL", "tk-t1")
	code, out, _ = f.call("pre-existing", "lint", "--bead", "tk-w")
	if code != 4 || !strings.Contains(out, "tk-t1 did not read") {
		t.Errorf("a tracker that does not read = %d %q, want 4 and unread", code, out)
	}
	t.Setenv("STUB_LIST_FAIL", "")

	f.store(row("tk-w", "in_progress", nil))
	if code, out, _ := f.call("pre-existing", "lint", "--bead", "tk-w"); code != 1 || out != "" {
		t.Errorf("no mark = %d %q, want 1 and nothing printed", code, out)
	}
}

func TestRigPreExistingMarksTheFail(t *testing.T) {
	f, fail := newMarkFixture(t)
	f.store(row("tk-w", "in_progress", nil), row("tk-a", "open", nil), row("tk-b", "blocked", nil))
	code, out, errs := f.call("pre-existing", "lint", "--bead", "tk-w", "--commit", f.head(), "--tracker", "tk-b tk-a")
	if code != 0 || !strings.Contains(out, "tk-w marks lint's fail at "+f.head()+" pre-existing, tracked by tk-a, tk-b") {
		t.Fatalf("a mark = %d %q:\n%s", code, out, errs)
	}
	key, _ := os.ReadFile(filepath.Join(f.stub, "meta.key"))
	value, _ := os.ReadFile(filepath.Join(f.stub, "meta.value"))
	var m rig.Mark
	if string(key) != "rig_check_pre_existing.lint" || json.Unmarshal(value, &m) != nil ||
		m.Commit != f.head() || !slices.Equal(m.Trackers, []string{"tk-a", "tk-b"}) {
		t.Fatalf("the write set %s=%s", key, value)
	}
	var written rig.Record
	if err := json.Unmarshal(m.Record, &written); err != nil || written != *fail {
		t.Errorf("the mark's record = %s, want %+v", m.Record, *fail)
	}

	_ = os.Remove(f.gcLog)
	f.store(row("tk-w", "in_progress", nil), row("tk-a", "closed", nil, [2]string{"supersedes", "tk-batch"}),
		row("tk-batch", "open", nil))
	code, _, errs = f.call("pre-existing", "lint", "--bead", "tk-w", "--commit", f.head(), "--tracker", "tk-a")
	if code != 1 || !strings.Contains(errs, "mark the fail against tk-batch") || len(f.gcCalls("bd update")) > 0 {
		t.Errorf("a folded tracker = %d:\n%s\nwant 1, the bead to mark against, and no write", code, errs)
	}

	f.store(row("tk-w", "in_progress", nil), row("tk-a", "open", nil))
	t.Setenv("STUB_UPDATE_RC", "1")
	if code, _, errs := f.call("pre-existing", "lint", "--bead", "tk-w", "--commit", f.head(), "--tracker", "tk-a"); code != 4 ||
		!strings.Contains(errs, "did not land") {
		t.Errorf("a write that does not land = %d:\n%s", code, errs)
	}
}

func TestRigPreExistingUsageErrors(t *testing.T) {
	f, _ := newMarkFixture(t)
	for _, args := range [][]string{
		{"pre-existing", "lint"},
		{"pre-existing", "lint", "--bead", ""},
		{"pre-existing", "serve", "--bead", "tk-w"},
		{"pre-existing", "lint", "--bead", "tk-w", "--commit", f.head()},
		{"pre-existing", "lint", "--bead", "tk-w", "--commit", "abc123", "--tracker", "tk-a"},
		{"pre-existing", "lint", "--bead", "tk-w", "--commit", f.head(), "--tracker", "tk-a;rm"},
		{"pre-existing", "lint", "--bead", "tk-w", "--commit", f.head(), "--tracker", " , "},
	} {
		if code, _, _ := f.call(args...); code != 2 {
			t.Errorf("%v = %d, want 2", args, code)
		}
	}
	if calls := f.gcCalls("bd "); len(calls) > 0 {
		t.Errorf("a usage error reached the store: %q", calls)
	}
}

func TestBeadCarrierPrintsTheOpenBeadThatCarriesTheWork(t *testing.T) {
	f, _ := newMarkFixture(t)
	call := func(args ...string) (int, string, string) {
		var out, errb bytes.Buffer
		code := Run(append([]string{"bead", "carrier"}, args...), "", &out, &errb)
		return code, out.String(), errb.String()
	}
	f.store(row("tk-t", "closed", nil, [2]string{"supersedes", "tk-batch"}), row("tk-batch", "open", nil),
		row("tk-dangling", "closed", nil, [2]string{"duplicates", "tk-gone"}))
	if code, out, errs := call("tk-t"); code != 0 || out != "tk-batch\n" {
		t.Errorf("a folded bead = %d %q:\n%s", code, out, errs)
	}
	if code, out, errs := call("tk-batch"); code != 0 || out != "tk-batch\n" {
		t.Errorf("an open bead = %d %q:\n%s", code, out, errs)
	}
	code, out, errs := call("tk-dangling")
	if code != 0 || out != "" || !strings.Contains(errs, "tk-dangling names tk-gone as its successor, but the store holds no such bead") {
		t.Errorf("a dangling edge = %d %q:\n%s", code, out, errs)
	}
	t.Setenv("STUB_LIST_FAIL", "tk-batch")
	if code, out, _ := call("tk-t"); code != 1 || out != "" {
		t.Errorf("a read that fails = %d %q, want 1 and nothing printed", code, out)
	}
	if code, _, _ := call(); code != 2 {
		t.Errorf("no bead = %d, want 2", code)
	}
}
