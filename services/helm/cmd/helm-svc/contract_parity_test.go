package main

import (
	"bytes"
	"encoding/json"
	"os"
	"regexp"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/board"
)

// Parity between `helm-svc board --json` and `gc-helm.sh --json`.
//
// The two boards are two renderers over one model, but only the Go side is
// compiled: nothing stops the bash board's `--json` object from growing a field
// this one does not emit, or vice versa, and the failure is silent — a consumer
// reads `null` and behaves as though the fact were absent rather than
// unmirrored. assets/scripts/tmux-pick-helm.sh is the consumer that matters
// today; it reads the array shape and six of the fields.
//
// This is the same idea as web/contract_parity_test.go, which reflects over the
// Go structs and PARSES the other side's declaration (there, contract.ts). Here
// the other side is a jq object literal inside a shell script, so the test
// parses that. It is deliberately static:
//
//   - it does not run gc-helm.sh, so it needs no jq, no `gc`, and no live city;
//   - it does not compare live output, which depends on session liveness and
//     could not be deterministic.
//
// What a live run DOES prove — that the two agree field for field on real data
// — was verified when this landed (55 anchors, all 34 fields equal) and is
// recorded in specs/tk-134d7/. This test is what keeps them equal afterwards.

const (
	shBoardPath = "../../../../assets/scripts/gc-helm.sh"
	// emitMarker is the last line of the jq object literal gc-helm.sh builds
	// per anchor. Anchoring on rank_score rather than on a comment keeps the
	// parse tied to the code itself.
	emitMarker = "rank_score:"
)

// shEmittedKeys extracts the key set of gc-helm.sh's per-anchor `--json` object.
//
// The literal is the final `| { … }` of the RENDER jq program: it opens on a
// line that is exactly `| {` and closes at the matching `}`. Inside, every
// `name:` at the start of a key position is a wire field.
func shEmittedKeys(t *testing.T) []string {
	t.Helper()
	src, err := os.ReadFile(shBoardPath)
	if err != nil {
		t.Fatalf("read %s: %v\nThis test pins the CLI against the bash board; it cannot run without it.", shBoardPath, err)
	}
	lines := strings.Split(string(src), "\n")

	start := -1
	for i, ln := range lines {
		if strings.TrimSpace(ln) == "| {" {
			start = i
		}
		// Take the LAST such block that contains the emit marker below it.
		if start >= 0 && strings.Contains(ln, emitMarker) {
			break
		}
	}
	if start < 0 {
		t.Fatalf("could not find the `| {` that opens the per-anchor object in %s", shBoardPath)
	}

	// Walk to the matching close brace, tracking depth so a nested object does
	// not end the block early.
	var body []string
	depth := 0
	for i := start; i < len(lines); i++ {
		body = append(body, lines[i])
		depth += strings.Count(lines[i], "{") - strings.Count(lines[i], "}")
		if i > start && depth == 0 {
			break
		}
	}
	if depth != 0 {
		t.Fatalf("unbalanced braces in the per-anchor object of %s", shBoardPath)
	}

	// A key is `name:` appearing after `{` or `,` (possibly across a newline).
	// jq values contain colons too — `\(.a):\(.b)` inside a string, `if…then`
	// — so the position rule, not the colon alone, is what identifies a key.
	joined := strings.Join(body, "\n")
	keyRe := regexp.MustCompile(`(?m)(?:[{,]|^)\s*([a-z_][a-z0-9_]*)\s*:`)
	var keys []string
	seen := map[string]bool{}
	for _, m := range keyRe.FindAllStringSubmatch(joined, -1) {
		k := m[1]
		if seen[k] {
			continue
		}
		seen[k] = true
		keys = append(keys, k)
	}
	if len(keys) < 20 {
		t.Fatalf("parsed only %d keys from %s (%v) — the parser has drifted from the script", len(keys), shBoardPath, keys)
	}
	slices.Sort(keys)
	return keys
}

// goEmittedKeys is the key set one tile actually serializes through the CLI's
// own renderer, so the test reads the real bytes rather than reflecting over
// the struct: a bad `omitempty` is exactly the kind of drift it must catch.
func goEmittedKeys(t *testing.T) []string {
	t.Helper()
	// A fully-populated anchor: an omitzero/omitempty field left at its zero
	// value would vanish and read as a missing key rather than as a bug here.
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
		Children: []board.Child{
			{ID: "tk-c1", Status: "open"},
			{ID: "tk-c2", Status: "in_progress", Assignee: "polecat-live"},
			{ID: "tk-c3", Status: "closed"},
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

// TestCLIFieldParityWithBashBoard is the check: the two boards emit the SAME
// per-row field set. A field added to one and not the other fails here, naming
// which side is behind.
func TestCLIFieldParityWithBashBoard(t *testing.T) {
	sh := shEmittedKeys(t)
	go_ := goEmittedKeys(t)

	if slices.Equal(sh, go_) {
		return
	}
	for _, k := range sh {
		if !slices.Contains(go_, k) {
			t.Errorf("gc-helm.sh emits %q and `helm-svc board --json` does not.\n"+
				"Add it to board.Tile (and mirror it in web/src/contract.ts), or the CLI is a lossy view of the same board.", k)
		}
	}
	for _, k := range go_ {
		if !slices.Contains(sh, k) {
			t.Errorf("`helm-svc board --json` emits %q and gc-helm.sh does not.\n"+
				"Add it to the jq object literal in %s in the same change, or the two boards have forked.", k, shBoardPath)
		}
	}
}

// TestCLIEmitsArrayNotEnvelope pins the shape, which is the half of the contract
// a field-set check cannot see. tmux-pick-helm.sh runs `jq 'length'` and `.[]`
// over this output; the service's {generated_at,total,tiles} envelope would
// make every row invisible while still parsing cleanly.
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

// TestPickerFieldsPresent names the SIX fields assets/scripts/tmux-pick-helm.sh
// actually dereferences. The parity test above would catch their removal too,
// but only while the bash board still has them — this one states the consumer's
// requirement directly, so retiring gc-helm.sh later cannot quietly retire the
// contract with it.
func TestPickerFieldsPresent(t *testing.T) {
	// tmux-pick-helm.sh:80-82 reads: .live, .severity, .id, .rig, .title, .frontier
	// `.live` is deliberately NOT in the contract — the host mechanism it
	// described is gone, and the picker already defaults it (`.live//"cold"`).
	want := []string{"severity", "id", "rig", "title", "frontier"}
	have := goEmittedKeys(t)
	for _, k := range want {
		if !slices.Contains(have, k) {
			t.Errorf("tmux-pick-helm.sh dereferences .%s and the CLI does not emit it", k)
		}
	}
	if slices.Contains(have, "live") {
		t.Error("`live` is the retired hot/warm/cold host field; it must not come back (see internal/board/model.go)")
	}
}

// TestCapRowsSplitBudget pins the row cap the CLI applies: parked rows draw on
// their OWN budget instead of competing for the attention slots, which is what
// stops a board full of real attention items from hiding every parked bead.
func TestCapRowsSplitBudget(t *testing.T) {
	var tiles []board.Tile
	for i := 0; i < 5; i++ {
		tiles = append(tiles, board.Tile{ID: "a" + string(rune('0'+i)), Kind: "epic"})
	}
	for i := 0; i < 5; i++ {
		tiles = append(tiles, board.Tile{ID: "p" + string(rune('0'+i)), Kind: "parked"})
	}

	got := board.CapRows(tiles, 2, 3)
	if len(got) != 5 {
		t.Fatalf("limit 2 + parked 3 = 5 rows, got %d", len(got))
	}
	var epics, parked int
	for _, tl := range got {
		if tl.Kind == "parked" {
			parked++
		} else {
			epics++
		}
	}
	if epics != 2 || parked != 3 {
		t.Errorf("split budget: %d attention + %d parked, want 2 + 3", epics, parked)
	}
	if n := len(board.CapRows(tiles, 0, 3)); n != 10 {
		t.Errorf("limit 0 means uncapped for BOTH kinds: got %d rows, want 10", n)
	}
}

// TestParseBoardArgs covers the flag surface, including the fail-closed cases:
// a bad limit must be a usage error, never a silently-ignored flag that renders
// a differently-sized board than the caller asked for.
func TestParseBoardArgs(t *testing.T) {
	t.Run("defaults", func(t *testing.T) {
		o, err := parseBoardArgs(nil)
		if err != nil {
			t.Fatal(err)
		}
		if o.json || o.limit != -1 || o.timeout != defaultBoardTimeout {
			t.Errorf("defaults: %+v", o)
		}
	})
	t.Run("both limit spellings", func(t *testing.T) {
		for _, args := range [][]string{{"--limit=7"}, {"--limit", "7"}} {
			o, err := parseBoardArgs(args)
			if err != nil || o.limit != 7 {
				t.Errorf("%v -> limit=%d err=%v", args, o.limit, err)
			}
		}
	})
	t.Run("limit 0 is uncapped, not unset", func(t *testing.T) {
		o, err := parseBoardArgs([]string{"--limit=0"})
		if err != nil || o.limit != 0 {
			t.Errorf("limit=%d err=%v", o.limit, err)
		}
	})
	t.Run("rejections", func(t *testing.T) {
		for _, args := range [][]string{
			{"--limit=-1"}, {"--limit=abc"}, {"--limit"}, {"--nope"}, {"board"},
		} {
			if _, err := parseBoardArgs(args); err == nil {
				t.Errorf("%v must be a usage error", args)
			}
		}
	})
	t.Run("refresh is accepted and inert", func(t *testing.T) {
		if _, err := parseBoardArgs([]string{"--refresh", "--json"}); err != nil {
			t.Errorf("--refresh must be accepted for bash-board flag compatibility: %v", err)
		}
	})
}

// TestRenderTableColumns pins the human view's shape: rune-counted padding (the
// board is full of ·, — and ●, and byte-counting would ragged every column that
// holds one) and the em-dash placeholder for the kinds that carry no roll-up.
func TestRenderTableColumns(t *testing.T) {
	tiles := []board.Tile{
		{ID: "tk-1", Rig: "gc-toolkit", Kind: "epic", Severity: board.SevHigh,
			NClosed: 3, MTotal: 11, Frontier: "8 open · 0 in flight (stranded)", Needs: "assign or visit", Held: true},
		{ID: "tk-2", Rig: "gc-toolkit", Kind: "parked", Severity: board.SevLow,
			Frontier: "conversation parked — takeaway recorded", Needs: "resume"},
	}
	var buf bytes.Buffer
	renderTable(&buf, board.Board{Total: 2, Tiles: tiles}, tiles, time.Date(2026, 8, 12, 1, 2, 3, 0, time.UTC), 4)
	out := buf.String()

	for _, want := range []string{
		"gc-helm — cross-rig human-attention board",
		"2026-08-12T01:02:03Z · 4 rigs · 2 anchors (live)",
		"3/11", // an epic reports its roll-up
	} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in:\n%s", want, out)
		}
	}
	if !strings.Contains(out, "●") {
		t.Error("a held row must carry the ● glyph")
	}

	// Every data row must start at the same column for ID, whatever glyphs the
	// preceding cells contain.
	var idCols []int
	for _, ln := range strings.Split(out, "\n") {
		if i := strings.Index(ln, "tk-"); i > 0 {
			idCols = append(idCols, len([]rune(ln[:i])))
		}
	}
	if len(idCols) != 2 || idCols[0] != idCols[1] {
		t.Errorf("ID column is ragged across rows: %v\n%s", idCols, out)
	}

	// A parked row has no roll-up to report, so a count would be a fabricated
	// 0/0 rather than a fact.
	if !strings.Contains(out, "—") {
		t.Error("a parked row must show the em-dash placeholder, not 0/0")
	}
	if strings.Contains(out, "0/0") {
		t.Error("no row should print a fabricated 0/0 count")
	}
}

// TestEmptyBoardSaysSo: zero anchors is a legitimate answer and must read as
// one. The failure mode it guards is the opposite reading — a gather that could
// not look reported as "nothing needs you" — which runBoard keeps distinct by
// exiting 3 without rendering at all.
func TestEmptyBoardSaysSo(t *testing.T) {
	var buf bytes.Buffer
	renderTable(&buf, board.Board{Total: 0}, nil, time.Now(), 4)
	if !strings.Contains(buf.String(), "Nothing floats") {
		t.Errorf("an empty board says so explicitly:\n%s", buf.String())
	}
}
