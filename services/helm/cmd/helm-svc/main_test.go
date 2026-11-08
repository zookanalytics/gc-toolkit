package main

import (
	"bytes"
	"encoding/json"
	"fmt"
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

// TestJSONOutputIsTheTilesArray pins the --json SHAPE. A caller counts the rows
// with `jq length` and walks them with `.[]`, so the service's
// {generated_at,total,tiles} envelope would turn every board into one row while
// still parsing cleanly, and an empty board has to be `[]`, the legitimate
// "nothing floats" answer, rather than a `null` that reads as a failure.
func TestJSONOutputIsTheTilesArray(t *testing.T) {
	var buf bytes.Buffer
	if rc := renderJSON(&buf, &buf, []board.Tile{{ID: "tk-1"}}); rc != boardExitOK {
		t.Fatalf("renderJSON exited %d: %s", rc, buf.String())
	}
	var rows []map[string]json.RawMessage
	if err := json.Unmarshal(buf.Bytes(), &rows); err != nil {
		t.Fatalf("--json must be a JSON ARRAY: %v\n%s", err, buf.String())
	}
	if len(rows) != 1 {
		t.Fatalf("want the one row, got %d", len(rows))
	}
	if _, ok := rows[0]["pack_health"]; ok || strings.Contains(buf.String(), "pack_health") {
		t.Errorf("--json grew the envelope's pack_health key:\n%s", buf.String())
	}

	buf.Reset()
	if rc := renderJSON(&buf, &buf, nil); rc != boardExitOK {
		t.Fatalf("renderJSON exited %d", rc)
	}
	var arr []any
	if err := json.Unmarshal(buf.Bytes(), &arr); err != nil {
		t.Fatalf("an empty board must still be a JSON array: %v (%q)", err, buf.String())
	}
	if len(arr) != 0 || strings.TrimSpace(buf.String()) != "[]" {
		t.Errorf("an empty board prints [], got %q", buf.String())
	}
}

// TestBoardWithoutJSONNamesTheWebPage: the board has no terminal view, so a
// call without --json says where the board is and prints nothing. It answers
// before the gather. The city path below names a directory with no bead stores,
// where a call that reads the stores exits 3, as the --json control shows.
func TestBoardWithoutJSONNamesTheWebPage(t *testing.T) {
	t.Setenv("GC_HELM_CITY_PATH", t.TempDir())
	for _, args := range [][]string{nil, {"--all"}, {"--limit=5"}} {
		var out, errOut bytes.Buffer
		if rc := runBoard(args, &out, &errOut); rc != boardExitUsage {
			t.Errorf("board %v exited %d, want %d before any gather:\n%s", args, rc, boardExitUsage, errOut.String())
		}
		if out.Len() != 0 {
			t.Errorf("board %v printed to stdout:\n%s", args, out.String())
		}
		for _, want := range []string{"no terminal view", "web page", "/svc/helm/", "--json"} {
			if !strings.Contains(errOut.String(), want) {
				t.Errorf("board %v must say %q:\n%s", args, want, errOut.String())
			}
		}
	}

	var out, errOut bytes.Buffer
	if rc := runBoard([]string{"--json"}, &out, &errOut); rc != boardExitGather {
		t.Errorf("control: --json reads the stores, and a city with none exits %d, got %d:\n%s",
			boardExitGather, rc, errOut.String())
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
		errs = []string{"rig-a: store unreadable"}
	}
	return board.BuildBoard(anchors, now, partial, errs, board.Facts{})
}

// TestDefaultViewIsTheQueue: `helm-svc board --json` answers with the
// operator's queue and nothing else, and --all is the only way to the overview. The
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
// was holding, so the empty queue exits 3 rather than printing an empty array.
// The overview keeps its own contract — an empty --all is still an empty --all.
func TestEmptyQueueFromAPartialGatherIsNotAnAnswer(t *testing.T) {
	whole := board.BuildBoard(nil, time.Now(), false, nil, board.Facts{})
	if selectView(whole, false, 0).unprovable {
		t.Error("an empty queue from a WHOLE gather is a real answer")
	}

	partial := board.BuildBoard(nil, time.Now(), true, []string{"rig-a: store unreadable"}, board.Facts{})
	if !selectView(partial, false, 0).unprovable {
		t.Error("an empty queue from a PARTIAL gather proves nothing")
	}
	if selectView(partial, true, 0).unprovable {
		t.Error("--all carries no emptiness contract of its own")
	}

	// A partial gather that still produced a queue prints it: those rows were
	// read.
	if selectView(boardWithAnOwedRow(true), false, 0).unprovable {
		t.Error("a non-empty queue prints even when the gather was partial")
	}
}

// TestBoardFlagParsing pins that the overview needs an explicit flag.
func TestBoardFlagParsing(t *testing.T) {
	o, err := parseBoardArgs(nil)
	if err != nil {
		t.Fatalf("no args: %v", err)
	}
	if o.all {
		t.Error("`board` without --all is the queue, not the overview")
	}
	if o, err = parseBoardArgs([]string{"--all", "--json"}); err != nil || !o.all || !o.json {
		t.Errorf("--all --json: all=%v json=%v err=%v", o.all, o.json, err)
	}
}

// TestTheQueueAndOverviewCapDifferently: the queue stays FLAT and owed-first, so
// CapQueue keeps every owed row up to the limit — a parked row owed to the
// operator is a conversation waiting on them, not a straggler to ration. The
// overview groups by dependency family, so CapFamilies keeps WHOLE families up to
// a row budget, never splitting one.
func TestTheQueueAndOverviewCapDifferently(t *testing.T) {
	now := time.Date(2026, 6, 30, 12, 0, 0, 0, time.UTC)
	var anchors []board.Anchor
	for i := 0; i < 20; i++ {
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
	// Each parked conversation is its own family, so a small overview budget caps
	// to that many whole families — here 5 of the 20.
	if got := len(selectView(b, true, 5).rows); got != 5 {
		t.Errorf("the overview caps whole families to its budget: kept %d, want 5", got)
	}
}
