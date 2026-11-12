package cli

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// storeStub answers the reads `gctk bead holds` makes from one store,
// $STUB_STORE, a JSON array of rows in a show's shape: `bd show` returns the
// rows named, each leaving out an edge whose far bead the store does not hold,
// and `bd list` returns the rows its --id, --has-metadata-key, --metadata-field
// and --all select, in a listing's shape, every edge kept. `bd blocked`
// answers $STUB_BLOCKED and `bd sql` $STUB_MARKS. $STUB_BLOCKED_RC fails the
// listing. `bd where` names /stub/.beads at prefix "st", and `rig list` names
// that store alone, so no store's prefix begins an id here. Each call logs the
// store it names with bd's --db, "-" for none, to $STUB_DB_LOG.
const storeStub = `#!/bin/sh
db=-
if [ "$1" = bd ] && [ "$2" = --db ]; then db="$3"; shift 3; set -- bd "$@"; fi
[ -z "$STUB_DB_LOG" ] || printf '%s\n' "$db" >> "$STUB_DB_LOG"
case "$1 $2" in
"bd show")
  shift 2
  ids=""
  for a in "$@"; do case "$a" in --*) ;; *) ids="$ids,$a" ;; esac; done
  printf '%s' "$STUB_STORE" | jq -c --arg ids "$ids" '
    . as $all | ($ids | split(",") | map(select(. != ""))) as $want
    | [ .[] | select(.id as $i | any($want[]; . == $i))
        | .dependencies = [ (.dependencies // [])[] | select(.id as $d | any($all[]; .id == $d)) ] ]' ;;
"bd list")
  shift 2
  ids=""; hk=""; mf=""; all=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --id) ids="$2"; shift ;;
      --has-metadata-key) hk="$2"; shift ;;
      --metadata-field) mf="$2"; shift ;;
      --all) all=1 ;;
    esac
    shift
  done
  printf '%s' "$STUB_STORE" | jq -c --arg ids "$ids" --arg hk "$hk" --arg mf "$mf" --arg all "$all" '
    [ .[] | select($all == "1" or .status != "closed")
      | select($ids == "" or (.id as $i | any($ids | split(",")[]; . == $i)))
      | select($hk == "" or ((.metadata // {}) | has($hk)))
      | select($mf == "" or (($mf | split("=")) as [$k, $v] | (.metadata // {})[$k] == $v))
      | .id as $self
      | .dependencies = [ (.dependencies // [])[] | {issue_id: $self, depends_on_id: .id, type: .dependency_type} ] ]' ;;
"bd blocked") printf '%s\n' "${STUB_BLOCKED:-[]}"; exit "${STUB_BLOCKED_RC:-0}" ;;
"bd where") printf '%s\n' '{"path":"/stub/.beads","prefix":"st"}' ;;
"rig list") printf '%s\n' '{"rigs":[{"name":"stub","prefix":"st","path":"/stub"}]}' ;;
"bd sql") printf '%s\n' "${STUB_MARKS:-[]}" ;;
*) echo "stub gc: no answer for $*" >&2; exit 2 ;;
esac
`

// The store the command reads: an epic its gate parks, a member under it, a
// bead blocked on its own open blocker with an edge into another store and an
// arm, a member a live workflow past load-context works, and a bead with a
// waits-for edge of its own.
const holdsStore = `[
 {"id":"gate","status":"open","issue_type":"gate","await_type":"human","title":"park the epic"},
 {"id":"epic","status":"open","issue_type":"epic","dependencies":[{"id":"gate","dependency_type":"blocks","title":"park the epic","status":"open"}]},
 {"id":"member","status":"open","dependencies":[{"id":"epic","dependency_type":"parent-child","status":"open"}]},
 {"id":"blocker","status":"in_progress","title":"the work it waits on"},
 {"id":"done","status":"closed","closed_at":"2026-11-02T08:00:00Z"},
 {"id":"own","status":"open","metadata":{"gc.dispatch_when_ready":"rig/rig.polecat","gc.dispatch_when_ready_args":"[\"--on\",\"mol-polecat-work\"]"},
  "dependencies":[{"id":"blocker","dependency_type":"blocks","title":"the work it waits on","status":"in_progress"},{"id":"done","dependency_type":"blocks","status":"closed","closed_at":"2026-11-02T08:00:00Z"},{"id":"xx-9","dependency_type":"blocks","status":"open"}]},
 {"id":"worked","status":"open","dependencies":[{"id":"epic","dependency_type":"parent-child","status":"open"}]},
 {"id":"cv","status":"open","issue_type":"convoy","dependencies":[{"id":"worked","dependency_type":"tracks","status":"open"}]},
 {"id":"root","status":"in_progress","metadata":{"gc.kind":"workflow","gc.formula_contract":"graph.v2","gc.input_convoy_id":"cv"}},
 {"id":"lc","status":"closed","metadata":{"gc.root_bead_id":"root","gc.step_ref":"mol-polecat-work.load-context"}},
 {"id":"impl","status":"in_progress","metadata":{"gc.root_bead_id":"root","gc.step_ref":"mol-polecat-work.implement"}},
 {"id":"spawner","status":"closed","closed_at":"2026-11-08T09:00:00Z"},
 {"id":"waiter","status":"open","dependencies":[{"id":"spawner","dependency_type":"waits-for","status":"closed","closed_at":"2026-11-08T09:00:00Z"}]}
]`

const holdsBlocked = `[
 {"id":"epic","blocked_by":["gate"]},
 {"id":"member","blocked_by":["epic"]},
 {"id":"worked","blocked_by":["epic"]},
 {"id":"own","blocked_by":["blocker"]}
]`

const holdsMarks = `[{"id":"epic"},{"id":"member"},{"id":"worked"},{"id":"own"},{"id":"waiter"}]`

func holds(t *testing.T, args ...string) ([]map[string]any, int) {
	t.Helper()
	bin := t.TempDir()
	if err := os.WriteFile(filepath.Join(bin, "gc"), []byte(storeStub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STUB_STORE", holdsStore)
	if os.Getenv("STUB_BLOCKED") == "" {
		t.Setenv("STUB_BLOCKED", holdsBlocked)
	}
	t.Setenv("STUB_MARKS", holdsMarks)
	var out, errbuf bytes.Buffer
	code := Run(append([]string{"bead", "holds"}, args...), "", &out, &errbuf)
	var lines []map[string]any
	for _, l := range strings.Split(strings.TrimSpace(out.String()), "\n") {
		if l == "" {
			continue
		}
		var m map[string]any
		if err := json.Unmarshal([]byte(l), &m); err != nil {
			t.Fatalf("a line is not one JSON object: %q: %v", l, err)
		}
		lines = append(lines, m)
	}
	return lines, code
}

// The command prints one record per bead, in the order named, each once, with
// every field the contract names, through the store adapter's real reads.
func TestBeadHoldsPrintsOneRecordPerBead(t *testing.T) {
	lines, code := holds(t, "member", "own", "worked", "waiter", "member")
	if code != 0 || len(lines) != 4 {
		t.Fatalf("exit %d with %d lines; want 0 with one line per bead", code, len(lines))
	}
	want := []struct{ id, status, inFlight string }{
		{"member", "held", ""},
		{"own", "blocked", ""},
		{"worked", "clear", "workflow root past load-context"},
		{"waiter", "unjudged", ""},
	}
	for i, w := range want {
		l := lines[i]
		if l["id"] != w.id || l["status"] != w.status || l["in_flight"] != w.inFlight {
			t.Errorf("line %d = %v; want %s %s, in flight %q", i, l, w.id, w.status, w.inFlight)
		}
		for _, k := range []string{"waits", "pending", "last_landed", "arm", "foreign"} {
			if _, ok := l[k]; !ok {
				t.Errorf("%s's record has no %s", w.id, k)
			}
		}
	}
	raw, _ := json.Marshal(lines[1])
	for _, s := range []string{
		`"waits":[{"id":"blocker","status":"in_progress","title":"the work it waits on","type":"blocks"}]`,
		`"last_landed":"2026-11-02T08:00:00Z"`,
		`"foreign":[{"id":"xx-9","type":"blocks"}]`,
		`"target":"rig/rig.polecat"`,
	} {
		if !strings.Contains(string(raw), s) {
			t.Errorf("own's record %s lacks %s", raw, s)
		}
	}
	if raw, _ := json.Marshal(lines[0]["waits"]); string(raw) != `[{"ancestor":"epic","await_type":"human","id":"gate","issue_type":"gate","status":"open","title":"park the epic","type":"blocks"}]` {
		t.Errorf("member's waits = %s; want the epic's gate", raw)
	}
}

// A bead the store does not hold, and every bead when a read fails, prints its
// error and no status, and the command exits 1.
func TestBeadHoldsAReadThatFails(t *testing.T) {
	lines, code := holds(t, "ghost", "own")
	if code != 1 || len(lines) != 2 || lines[0]["error"] == nil || lines[0]["status"] != nil || lines[1]["status"] != "blocked" {
		t.Errorf("exit %d, lines %v; want 1, ghost's error and own's answer", code, lines)
	}
	t.Setenv("STUB_BLOCKED", "{}")
	t.Setenv("STUB_BLOCKED_RC", "1")
	lines, code = holds(t, "member", "own")
	if code != 1 || len(lines) != 2 {
		t.Fatalf("exit %d, lines %v; want 1 and a line for each bead", code, lines)
	}
	for _, l := range lines {
		if l["error"] == nil || l["status"] != nil {
			t.Errorf("%v: want an error and no status", l)
		}
	}
}

func TestBeadHoldsUsageErrors(t *testing.T) {
	for _, args := range [][]string{{}, {" "}} {
		var out, errbuf bytes.Buffer
		if code := Run(append([]string{"bead", "holds"}, args...), "", &out, &errbuf); code != 2 || out.Len() != 0 {
			t.Errorf("bead holds %q = exit %d, out %q; want a usage error", args, code, out.String())
		}
	}
}

// --db names the store every read of the command makes, and without it every
// read names the store gc resolves, which one read of gc bd where asks first.
func TestBeadHoldsReadsTheNamedStore(t *testing.T) {
	for _, tc := range []struct {
		name  string
		args  []string
		store string
		first string
	}{
		{"named", []string{"--db", "/rig/.beads", "own"}, "/rig/.beads", "/rig/.beads"},
		// The store gc resolves, then the stores, since no prefix begins "own".
		{"resolved", []string{"own"}, "/stub/.beads", "-"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			log := filepath.Join(t.TempDir(), "db")
			t.Setenv("STUB_DB_LOG", log)
			lines, code := holds(t, tc.args...)
			if code != 0 || len(lines) != 1 || lines[0]["status"] != "blocked" {
				t.Fatalf("exit %d, lines %v; want 0 and own blocked", code, lines)
			}
			raw, err := os.ReadFile(log)
			if err != nil {
				t.Fatal(err)
			}
			calls := strings.Split(strings.TrimSpace(string(raw)), "\n")
			lead := 1
			if tc.first == "-" {
				lead = 2
			}
			if len(calls) < lead+4 || calls[0] != tc.first || calls[lead-1] != tc.first {
				t.Fatalf("the stub logged %q; want the first %d read(s) to name %s, then the listing, the rows, the blocked set and its marks", calls, lead, tc.first)
			}
			for i, db := range calls[lead:] {
				if db != tc.store {
					t.Errorf("read %d named the store %q; want %s", i+1, db, tc.store)
				}
			}
		})
	}
}
