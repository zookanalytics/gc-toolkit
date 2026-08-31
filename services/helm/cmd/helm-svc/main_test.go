package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/board"
)

// TestDurationEnv covers the shared parser behind GC_HELM_CACHE_TTL and
// GC_HELM_PROBE_TIMEOUT: a Go duration, bare seconds, and the fallback for
// everything else.
func TestDurationEnv(t *testing.T) {
	const def = 7 * time.Second
	cases := []struct {
		name string
		env  string
		want time.Duration
	}{
		{"unset falls back", "", def},
		{"go duration", "30s", 30 * time.Second},
		{"go duration sub-second", "250ms", 250 * time.Millisecond},
		{"bare seconds", "45", 45 * time.Second},
		{"zero is honoured by the parser", "0", 0},
		{"negative duration falls back", "-5s", def},
		{"negative seconds falls back", "-5", def},
		{"unparseable falls back", "soon", def},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Setenv("GC_HELM_TEST_DURATION", c.env)
			if got := durationEnv("GC_HELM_TEST_DURATION", def); got != c.want {
				t.Errorf("durationEnv(%q) = %v, want %v", c.env, got, c.want)
			}
		})
	}
}

// TestCacheTTLKeepsZeroMeaningful guards the extraction of durationEnv: zero is
// a real setting for the cache (it disables it), so the shared parser must not
// coerce it away.
func TestCacheTTLKeepsZeroMeaningful(t *testing.T) {
	t.Setenv("GC_HELM_CACHE_TTL", "0")
	if got := cacheTTL(); got != 0 {
		t.Errorf("cacheTTL() = %v, want 0 — zero disables the cache and must survive", got)
	}
	t.Setenv("GC_HELM_CACHE_TTL", "")
	if got := cacheTTL(); got != defaultCacheTTL {
		t.Errorf("cacheTTL() = %v, want the default %v", got, defaultCacheTTL)
	}
}

// TestProbeTimeoutRejectsZero pins the one place the two knobs must differ. A
// zero cache TTL disables caching, which is useful; a zero probe deadline
// expires before any store can open, so EVERY probe would fail and the service
// would pin itself to the supervisor backend — permanently and silently losing
// the staleness lane, which is the exact failure selectSource exists to prevent.
func TestProbeTimeoutRejectsZero(t *testing.T) {
	for _, env := range []string{"0", "0s", "-1", "soon"} {
		t.Setenv("GC_HELM_PROBE_TIMEOUT", env)
		if got := probeTimeout(); got != defaultProbeTimeout {
			t.Errorf("probeTimeout() with %q = %v, want the default %v", env, got, defaultProbeTimeout)
		}
	}
	t.Setenv("GC_HELM_PROBE_TIMEOUT", "3s")
	if got := probeTimeout(); got != 3*time.Second {
		t.Errorf("probeTimeout() = %v, want 3s — a positive override must still win", got)
	}
}

// The CLI's --json output has ONE consumer, assets/scripts/tmux-pick-helm.sh,
// and the two tests below state its requirements.

// pickerReads are the tile fields tmux-pick-helm.sh dereferences, read off the
// script rather than listed here: a remembered list drifts out of step with the
// script without failing.
var pickerReads = regexp.MustCompile(`\.(held|severity|id|rig|title|frontier)\b`)

// emittedKeys serializes one tile through the CLI's own renderer and reads the
// real bytes rather than reflecting over the struct, so a stray omitempty is
// visible. The anchor is fully populated for the same reason: a zero-valued
// field would vanish and read as a missing key.
func emittedKeys(t *testing.T) []string {
	t.Helper()
	prio := 2
	owned := false
	a := board.Anchor{
		ID: "tk-parity", Title: "parity fixture", Kind: "convoy", Source: "convoy",
		Rig: "gc-toolkit", Prefix: "tk", Priority: &prio,
		UpdatedAt:   time.Date(2026, 8, 11, 15, 4, 5, 0, time.UTC),
		Description: "blocks sl-abc12",
		Owned:       &owned,
		Progress:    &board.Progress{Closed: 1, Total: 2},
		Takeaway:    "a headline", TakeawayAt: "2026-08-11T15:00:00Z", TakeawayBy: "host",
		WaitingOn: []string{"tk-w1"}, WaitingOnClosed: []string{"tk-w1"},
		Children: []board.Child{
			{ID: "tk-c1", Status: "open"},
			{ID: "tk-c2", Status: "in_progress", Assignee: "polecat-live"},
			{ID: "tk-c3", Status: "closed"},
			{ID: "tk-c4", Status: "open", Metadata: map[string]string{"gc.routed_to": "human"}},
		},
	}
	f := board.Facts{
		Visits:     map[string]bool{"tk-parity": true},
		OwnerState: map[string]string{"polecat-live": "active"},
		Prefixes:   []string{"tk", "sl"},
		RigNames:   []string{"gc-toolkit", "signal-loom"},
	}
	b := board.BuildBoard([]board.Anchor{a}, time.Date(2026, 8, 12, 0, 0, 0, 0, time.UTC), false, nil, f)

	var buf bytes.Buffer
	if rc := renderJSON(&buf, &buf, b.Tiles); rc != boardExitOK {
		t.Fatalf("renderJSON exited %d: %s", rc, buf.String())
	}
	var rows []map[string]json.RawMessage
	if err := json.Unmarshal(buf.Bytes(), &rows); err != nil {
		t.Fatalf("the CLI must emit a JSON ARRAY: %v\n%s", err, buf.String())
	}
	if len(rows) != 1 {
		t.Fatalf("expected 1 row, got %d", len(rows))
	}
	keys := make([]string, 0, len(rows[0]))
	for k := range rows[0] {
		keys = append(keys, k)
	}
	slices.Sort(keys)
	return keys
}

// TestPickerFieldsPresent: every field the picker dereferences has to be on the
// wire. Dropping one fails silently — jq's `//` fallbacks render "?" columns
// and nothing errors.
func TestPickerFieldsPresent(t *testing.T) {
	src, err := os.ReadFile("../../../../assets/scripts/tmux-pick-helm.sh")
	if err != nil {
		t.Fatalf("read the picker: %v", err)
	}
	var want []string
	for _, m := range pickerReads.FindAllStringSubmatch(string(src), -1) {
		if !slices.Contains(want, m[1]) {
			want = append(want, m[1])
		}
	}
	if len(want) == 0 {
		t.Fatal("found no tile field reads in the picker — the regex or the script changed shape")
	}

	have := emittedKeys(t)
	for _, k := range want {
		if !slices.Contains(have, k) {
			t.Errorf("tmux-pick-helm.sh dereferences .%s and the CLI does not emit it", k)
		}
	}
	// `live` is retired and the picker no longer reads it; it must not return.
	if slices.Contains(have, "live") {
		t.Error("`live` is retired; see internal/board/model.go")
	}
}

// TestCLIEmitsArrayNotEnvelope pins the SHAPE, which a field-set check cannot
// see. The picker runs `jq 'length'` and `.[]` over this output; the service's
// {generated_at,total,tiles} envelope would make every row invisible while
// still parsing cleanly.
func TestCLIEmitsArrayNotEnvelope(t *testing.T) {
	var buf bytes.Buffer
	if rc := renderJSON(&buf, &buf, nil); rc != boardExitOK {
		t.Fatalf("renderJSON exited %d", rc)
	}
	var arr []any
	if err := json.Unmarshal(buf.Bytes(), &arr); err != nil {
		t.Fatalf("an empty board must still be a JSON array: %v (%q)", err, buf.String())
	}
	if len(arr) != 0 {
		t.Fatalf("want an empty array, got %d rows", len(arr))
	}
	// `[]`, not `null`: the picker treats a null as an error and shows nothing,
	// where an empty array is the legitimate "nothing floats" answer.
	if strings.TrimSpace(buf.String()) == "null" {
		t.Error("an empty board serialized as null; tmux-pick-helm.sh reads that as a failure")
	}
}

// boardWithAnOwedRow builds the contest the partition exists for: a stranded
// container that outranks a one-bead demand owed to the operator.
func boardWithAnOwedRow(partial bool) board.Board {
	kids := make([]board.Child, 0, 200)
	for i := 0; i < 200; i++ {
		kids = append(kids, board.Child{ID: fmt.Sprintf("tk-c%d", i), Status: "open"})
	}
	now := time.Date(2026, 6, 30, 12, 0, 0, 0, time.UTC)
	anchors := []board.Anchor{
		{ID: "tk-container", Title: "big stranded epic", Kind: "epic", Source: "epic",
			Rig: "gc-toolkit", Prefix: "tk", UpdatedAt: now, Children: kids},
		{ID: "tk-owed", Title: "waiting on a person", Kind: "human", Source: "human",
			Rig: "gc-toolkit", Prefix: "tk", UpdatedAt: now,
			Metadata:       map[string]string{"gc.routed_to": "human"},
			WaitingUnknown: true},
	}
	var errs []string
	if partial {
		errs = []string{"signal-loom: store unreadable"}
	}
	return board.BuildBoard(anchors, now, partial, errs, board.Facts{})
}

// TestDefaultViewIsTheQueue: bare `helm-svc board` answers with the operator's
// queue and nothing else, and --all is the only way to the overview. The
// container outranks the demand, so on one globally ranked list the demand is
// the row that gets buried.
func TestDefaultViewIsTheQueue(t *testing.T) {
	b := boardWithAnOwedRow(false)
	if b.Tiles[0].ID != "tk-owed" {
		t.Fatalf("fixture: the owed row leads the board, got %s", b.Tiles[0].ID)
	}

	def := selectView(b, false, board.DefaultMaxRows)
	if len(def.rows) != 1 || def.rows[0].ID != "tk-owed" {
		t.Errorf("the default view is the queue alone: got %d rows %v", len(def.rows), def.rows)
	}
	if def.unprovable {
		t.Error("a whole gather with a non-empty queue is provable")
	}

	all := selectView(b, true, board.DefaultMaxRows)
	if len(all.rows) != 2 {
		t.Errorf("--all is the overview: want both rows, got %d", len(all.rows))
	}
}

// TestOverviewLeadsWithTheHighestRankedRow: `--all` is the RANKED city
// overview, and Board.Tiles reaches it partitioned owed-first — the queue's
// order, and the one the overview exists to sit behind. Sorting back to rank
// before the cap is what keeps each view answering its own question; without
// it the overview both leads with the queue and drops the lowest-ranked rows
// the hoist pushed past the limit.
func TestOverviewLeadsWithTheHighestRankedRow(t *testing.T) {
	b := boardWithAnOwedRow(false)
	if len(b.Tiles) != 2 || b.Tiles[0].ID != "tk-owed" {
		t.Fatalf("fixture: the wire is partitioned owed-first, got %v", tileIDs(b.Tiles))
	}
	if b.Tiles[1].RankScore <= b.Tiles[0].RankScore {
		t.Fatalf("fixture no longer sets up the contest: the container must outrank the demand (%d vs %d)",
			b.Tiles[1].RankScore, b.Tiles[0].RankScore)
	}

	all := selectView(b, true, board.DefaultMaxRows).rows
	if got := tileIDs(all); !slices.Equal(got, []string{"tk-container", "tk-owed"}) {
		t.Errorf("--all is ranked, highest first: got %v", got)
	}

	def := selectView(b, false, board.DefaultMaxRows).rows
	if got := tileIDs(def); !slices.Equal(got, []string{"tk-owed"}) {
		t.Errorf("...and the queue still answers with the demand: got %v", got)
	}
}

func tileIDs(tiles []board.Tile) []string {
	out := make([]string, 0, len(tiles))
	for _, t := range tiles {
		out = append(out, t.ID)
	}
	return out
}

// TestEmptyQueueFromAPartialGatherIsNotAnAnswer: the rows that would have
// contradicted "nothing is owed by you" are exactly the ones an unread store
// was holding, so the empty queue exits 3 rather than rendering an all-clear.
// The overview keeps its own contract — an empty --all is still an empty --all.
func TestEmptyQueueFromAPartialGatherIsNotAnAnswer(t *testing.T) {
	whole := board.BuildBoard(nil, time.Now(), false, nil, board.Facts{})
	if selectView(whole, false, 0).unprovable {
		t.Error("an empty queue from a WHOLE gather is a real answer")
	}

	partial := board.BuildBoard(nil, time.Now(), true, []string{"signal-loom: store unreadable"}, board.Facts{})
	if !selectView(partial, false, 0).unprovable {
		t.Error("an empty queue from a PARTIAL gather proves nothing")
	}
	if selectView(partial, true, 0).unprovable {
		t.Error("--all carries no emptiness contract of its own")
	}

	// A partial gather that still produced a queue renders it: those rows were
	// read, and runBoard's PARTIAL line says what was not.
	if selectView(boardWithAnOwedRow(true), false, 0).unprovable {
		t.Error("a non-empty queue renders even when the gather was partial")
	}
}

// TestEmptyQueueRendersItsCoverage: "nothing is owed by you" is a claim about
// every store in the city, so the sentence carries what it was checked against
// rather than leaving the surface blank.
func TestEmptyQueueRendersItsCoverage(t *testing.T) {
	var buf bytes.Buffer
	b := board.BuildBoard(nil, time.Now(), false, nil, board.Facts{})
	renderQueue(&buf, b, nil, time.Now().UTC(), 5)
	out := buf.String()
	for _, want := range []string{"Nothing is owed by you", "5 rigs checked", "--all"} {
		if !strings.Contains(out, want) {
			t.Errorf("the empty queue must say %q:\n%s", want, out)
		}
	}
}

// TestBoardFlagParsing pins that the overview needs an explicit flag.
func TestBoardFlagParsing(t *testing.T) {
	o, err := parseBoardArgs(nil)
	if err != nil {
		t.Fatalf("no args: %v", err)
	}
	if o.all {
		t.Error("bare `board` is the queue, not the overview")
	}
	if o, err = parseBoardArgs([]string{"--all", "--json"}); err != nil || !o.all || !o.json {
		t.Errorf("--all --json: all=%v json=%v err=%v", o.all, o.json, err)
	}
}

// TestTheQueueIsNotRationedLikeTheOverview: `parked` rows draw on a small
// separate budget in the OVERVIEW because they are floored to LOW and would
// otherwise be pushed off the end of a ranked board. A parked row that is also
// owed to the operator is not a straggler — it is a conversation waiting on
// them — so spending that budget on the queue would cut the queue's own tail.
func TestTheQueueIsNotRationedLikeTheOverview(t *testing.T) {
	now := time.Date(2026, 6, 30, 12, 0, 0, 0, time.UTC)
	var anchors []board.Anchor
	for i := 0; i < board.DefaultMaxParked+5; i++ {
		anchors = append(anchors, board.Anchor{
			ID: fmt.Sprintf("tk-p%02d", i), Title: "parked on the operator", Kind: "parked", Source: "parked",
			Rig: "gc-toolkit", Prefix: "tk", UpdatedAt: now,
			Metadata:       map[string]string{"gc.routed_to": "human", "gc.takeaway": "answer me"},
			Takeaway:       "answer me",
			WaitingUnknown: true,
		})
	}
	b := board.BuildBoard(anchors, now, false, nil, board.Facts{})
	if !b.Tiles[0].Owed {
		t.Fatalf("fixture: a parked row routed to the operator is owed")
	}
	if got := len(selectView(b, false, board.DefaultMaxRows).rows); got != len(anchors) {
		t.Errorf("the queue kept %d of %d rows owed to the operator", got, len(anchors))
	}
	if got := len(selectView(b, true, board.DefaultMaxRows).rows); got != board.DefaultMaxParked {
		t.Errorf("the overview still rations parked rows: kept %d, want %d", got, board.DefaultMaxParked)
	}
}

// The picker's own behaviour is pinned in assets/scripts/tmux-pick-helm.test.sh.
// What only this side can pin is the seam between them: the picker's failure arm
// has to fire on the code THIS package emits, and the shell suite can only spell
// that code as a literal.

const pickerPath = "../../../../assets/scripts/tmux-pick-helm.sh"

// runPicker drives the picker with a helm-svc that emits stdout and exits code,
// and returns every tmux invocation it made, one per line.
func runPicker(t *testing.T, stdout string, code int, args ...string) string {
	t.Helper()
	if _, err := exec.LookPath("jq"); err != nil {
		t.Skip("the picker shells out to jq")
	}
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "bin"), 0o755); err != nil {
		t.Fatal(err)
	}
	calls, svc := filepath.Join(dir, "tmux-calls"), filepath.Join(dir, "svc-args")
	write := func(path, body string) {
		if err := os.WriteFile(path, []byte(body), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	write(filepath.Join(dir, "bin", "helm-svc"), fmt.Sprintf(
		"#!/bin/sh\nprintf '%%s\\n' \"$*\" >> %q\ncat <<'JSON'\n%s\nJSON\nexit %d\n",
		svc, stdout, code))
	write(filepath.Join(dir, "tmux"), fmt.Sprintf("#!/bin/sh\nprintf '%%s\\n' \"$*\" >> %q\n", calls))

	cmd := exec.Command("sh", append([]string{pickerPath}, args...)...)
	cmd.Env = append(os.Environ(),
		"PATH="+dir+string(os.PathListSeparator)+os.Getenv("PATH"),
		"GC_SERVICE_STATE_ROOT="+dir,
	)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("picker exited %v: %s", err, out)
	}
	got, err := os.ReadFile(calls)
	if err != nil {
		t.Fatalf("the picker made no tmux call at all: %v", err)
	}
	if _, err := os.ReadFile(svc); err != nil {
		t.Fatalf("the picker never ran helm-svc: %v", err)
	}
	return string(got)
}

// A failed gather must not reach the operator as an empty menu. The picker
// spells the code as a literal, so nothing on its side notices if this package
// renumbers boardExitGather; driving it with the constant is what closes that.
func TestPickerFailureArmFiresOnTheBoardsOwnExitCode(t *testing.T) {
	got := runPicker(t, "", boardExitGather)
	if strings.Contains(got, "display-menu") {
		t.Errorf("a failed gather must not open a menu:\n%s", got)
	}
	if !strings.Contains(got, "BOARD UNREADABLE") {
		t.Errorf("the failure has to be named on screen:\n%s", got)
	}
	if strings.Contains(got, "nothing needs you") {
		t.Errorf("a failed gather is not an all-clear:\n%s", got)
	}
}
