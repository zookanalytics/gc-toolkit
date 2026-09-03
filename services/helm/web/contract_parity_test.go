package web

// Parity between the Go board contract and its hand-written TypeScript mirror.
//
// src/contract.ts is written by hand because the /svc/ surface is not in the
// supervisor's OpenAPI document — there is no generated client to lean on. The
// failure mode that creates is silent: rename a Go field and the browser reads
// `undefined`, with nothing failing anywhere in between. These tests are what
// close that gap, so they are deliberately strict and deliberately loud.
//
// Two independent layers, because they catch different things:
//
//   TestContractParity reflects over the wire structs and parses contract.ts,
//   comparing field NAMES, TYPES and OPTIONALITY in both directions. It is the
//   check that catches a rename, a removal, or a Go field nobody mirrored.
//
//   TestBoardFixture pins a committed sample of the actual wire bytes. TypeScript
//   asserts the fixture against the contract at compile time (src/contract.fixture.ts),
//   so `npm run build` fails too — from the other side of the seam, without Go.
//
// Neither test knows anything about React. They guard the contract, not the app.

import (
	"encoding/json"
	"flag"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"reflect"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/board"
)

// updateFixture rewrites the committed fixture instead of comparing against it:
//
//	go test ./web -run TestBoardFixture -update
var updateFixture = flag.Bool("update", false, "rewrite src/board.fixture.json from the Go types")

const (
	contractPath = "src/contract.ts"
	fixturePath  = "src/board.fixture.json"
	modelPath    = "../internal/board/model.go"
)

// wireRoot is the one type the service serializes: the body of GET <mount>/helm.
// Everything reachable from it is part of the contract and must be mirrored;
// everything else (board.Anchor, board.Child — gather-side inputs to BuildBoard)
// is not. Adding a nested struct to the envelope automatically pulls it into
// these checks.
var wireRoot = reflect.TypeOf(board.Board{})

var timeType = reflect.TypeOf(time.Time{})

// --- the Go side -----------------------------------------------------------

// goField is one field of a wire struct as it appears on the wire.
type goField struct {
	name     string // the JSON tag name
	tsType   string // the TypeScript type that mirrors it
	optional bool   // the encoder may omit the key entirely
	origin   string // Go path, for error messages
}

// wireStructs walks the envelope and returns every struct that crosses the
// wire, keyed by Go type name. time.Time is excluded: it serializes as a string,
// not as an object, so it is a leaf here.
func wireStructs(t *testing.T) map[string]reflect.Type {
	t.Helper()
	out := map[string]reflect.Type{}
	var walk func(reflect.Type)
	walk = func(gt reflect.Type) {
		switch {
		case gt == timeType:
			return
		case gt.Kind() == reflect.Pointer, gt.Kind() == reflect.Slice, gt.Kind() == reflect.Array:
			walk(gt.Elem())
		case gt.Kind() == reflect.Map:
			walk(gt.Elem())
		case gt.Kind() == reflect.Struct:
			if _, seen := out[gt.Name()]; seen {
				return
			}
			out[gt.Name()] = gt
			for i := range gt.NumField() {
				if f := gt.Field(i); f.IsExported() && jsonName(f) != "" {
					walk(f.Type)
				}
			}
		}
	}
	walk(wireRoot)
	return out
}

// jsonName returns the wire name of a field, or "" when the encoder skips it.
func jsonName(f reflect.StructField) string {
	tag, ok := f.Tag.Lookup("json")
	if !ok {
		return f.Name // encoding/json falls back to the Go name
	}
	name, _, _ := strings.Cut(tag, ",")
	if name == "-" && !strings.Contains(tag, ",") {
		return ""
	}
	if name == "" {
		return f.Name
	}
	return name
}

// goFields describes a wire struct the way contract.ts must declare it.
func goFields(t *testing.T, gt reflect.Type) []goField {
	t.Helper()
	var out []goField
	for i := range gt.NumField() {
		f := gt.Field(i)
		if f.Anonymous {
			t.Fatalf("%s.%s is an embedded field; the mirror rule (one Go struct, one TS interface) does not model promotion. Give it a name or flatten it.", gt.Name(), f.Name)
		}
		if !f.IsExported() {
			continue
		}
		name := jsonName(f)
		if name == "" {
			continue
		}
		tag := f.Tag.Get("json")
		// omitempty and omitzero both mean "the key may be absent", which is
		// exactly what a TypeScript optional property says.
		optional := strings.Contains(tag, ",omitempty") || strings.Contains(tag, ",omitzero")
		out = append(out, goField{
			name:     name,
			tsType:   tsTypeFor(t, f.Type, optional, gt.Name()+"."+f.Name),
			optional: optional,
			origin:   fmt.Sprintf("board.%s.%s `json:%q`", gt.Name(), f.Name, tag),
		})
	}
	return out
}

// tsTypeFor is the Go-type -> TypeScript-type mapping the mirror must follow.
//
// The subtle case is a nil slice or pointer. encoding/json writes `null` for
// one that is not omitted, but omits the key entirely when the tag says
// omitempty — so the same Go type maps to `T[] | null` in one position and an
// optional `T[]` in another. Getting that backwards is how a frontend ends up
// calling .map() on null, so it is mechanical here rather than a judgement call
// at the keyboard.
func tsTypeFor(t *testing.T, gt reflect.Type, omitted bool, where string) string {
	t.Helper()
	if gt == timeType {
		return "string" // RFC 3339
	}
	switch gt.Kind() {
	case reflect.String:
		// A named Go string type (board.Severity) mirrors as a TS type of the
		// same name; a plain string is just string.
		if n := gt.Name(); n != "" && n != "string" {
			return n
		}
		return "string"
	case reflect.Bool:
		return "boolean"
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64,
		reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64,
		reflect.Float32, reflect.Float64:
		return "number"
	case reflect.Slice, reflect.Array:
		elem := tsTypeFor(t, gt.Elem(), false, where)
		if omitted || gt.Kind() == reflect.Array {
			return elem + "[]"
		}
		return elem + "[] | null"
	case reflect.Map:
		return "Record<" + tsTypeFor(t, gt.Key(), false, where) + ", " + tsTypeFor(t, gt.Elem(), false, where) + ">"
	case reflect.Pointer:
		inner := tsTypeFor(t, gt.Elem(), false, where)
		if omitted {
			return inner
		}
		return inner + " | null"
	case reflect.Struct:
		return gt.Name()
	default:
		t.Fatalf("%s: no TypeScript mapping for Go kind %s. Extend tsTypeFor, and mirror it in %s.", where, gt.Kind(), contractPath)
		return ""
	}
}

// --- the TypeScript side ---------------------------------------------------

// tsField is one property parsed out of contract.ts.
type tsField struct {
	name     string
	tsType   string
	optional bool
	line     int
}

var (
	blockCommentRE = regexp.MustCompile(`(?s)/\*.*?\*/`)
	ifaceOpenRE    = regexp.MustCompile(`^export interface (\w+) \{$`)
	// One `name: type;` per line, with an optional trailing line comment. The
	// parser is strict by design: a property it cannot read is a hard failure,
	// never a silently skipped field.
	propRE     = regexp.MustCompile(`^(\w+)(\?)?:\s*(.+?);\s*(?://.*)?$`)
	severityRE = regexp.MustCompile(`(?s)export type Severity\s*=(.*?);`)
	wsRE       = regexp.MustCompile(`\s+`)
)

// readContract returns contract.ts with its comments blanked out.
func readContract(t *testing.T) string {
	t.Helper()
	b, err := os.ReadFile(contractPath)
	if err != nil {
		t.Fatalf("read %s: %v", contractPath, err)
	}
	// Blank block comments rather than deleting them, so the line numbers in
	// failure messages still point at the real line of the real file.
	return blockCommentRE.ReplaceAllStringFunc(string(b), func(s string) string {
		return strings.Repeat("\n", strings.Count(s, "\n"))
	})
}

// mustWireStruct fails loudly rather than panicking on a nil reflect.Type, which
// is what a lookup for a type that has left the envelope would otherwise do.
func mustWireStruct(t *testing.T, name string) reflect.Type {
	t.Helper()
	gt, ok := wireStructs(t)[name]
	if !ok {
		t.Fatalf("board.%s is no longer reachable from board.%s — the wire contract changed shape, so this test needs rewriting, not deleting", name, wireRoot.Name())
	}
	return gt
}

// parseInterfaces reads the `export interface` declarations out of contract.ts.
func parseInterfaces(t *testing.T, src string) map[string][]tsField {
	t.Helper()
	out := map[string][]tsField{}
	open := ""
	for i, rawLine := range strings.Split(src, "\n") {
		line := strings.TrimSpace(rawLine)
		if line == "" || strings.HasPrefix(line, "//") || strings.HasPrefix(line, "*") {
			continue
		}
		if open == "" {
			if m := ifaceOpenRE.FindStringSubmatch(line); m != nil {
				if _, dup := out[m[1]]; dup {
					t.Fatalf("%s:%d: interface %s is declared twice", contractPath, i+1, m[1])
				}
				open = m[1]
				out[open] = []tsField{}
			}
			continue
		}
		if line == "}" {
			open = ""
			continue
		}
		m := propRE.FindStringSubmatch(line)
		if m == nil {
			t.Fatalf("%s:%d: cannot parse %q inside interface %s.\n"+
				"The parity check requires one `name: type;` per line so it can compare the mirror field by field. "+
				"Keep the declarations plain; put anything clever somewhere the wire contract does not live.",
				contractPath, i+1, line, open)
		}
		out[open] = append(out[open], tsField{
			name:     m[1],
			optional: m[2] == "?",
			tsType:   strings.TrimSpace(wsRE.ReplaceAllString(m[3], " ")),
			line:     i + 1,
		})
	}
	if open != "" {
		t.Fatalf("%s: interface %s is never closed", contractPath, open)
	}
	return out
}

// goSeverities reads the Severity constants straight out of model.go. Constants
// are invisible to reflection, so this parses the declaration — via go/ast, so
// prose in a doc comment cannot be mistaken for a band.
func goSeverities(t *testing.T) []string {
	t.Helper()
	file, err := parser.ParseFile(token.NewFileSet(), modelPath, nil, 0)
	if err != nil {
		t.Fatalf("parse %s: %v", modelPath, err)
	}
	var out []string
	for _, decl := range file.Decls {
		gen, ok := decl.(*ast.GenDecl)
		if !ok || gen.Tok != token.CONST {
			continue
		}
		for _, spec := range gen.Specs {
			vs, ok := spec.(*ast.ValueSpec)
			if !ok {
				continue
			}
			if id, ok := vs.Type.(*ast.Ident); !ok || id.Name != "Severity" {
				continue
			}
			for _, v := range vs.Values {
				lit, ok := v.(*ast.BasicLit)
				if !ok || lit.Kind != token.STRING {
					t.Fatalf("%s: a Severity constant is not a string literal; this parser cannot follow it", modelPath)
				}
				s, err := strconv.Unquote(lit.Value)
				if err != nil {
					t.Fatalf("%s: unquote %s: %v", modelPath, lit.Value, err)
				}
				out = append(out, s)
			}
		}
	}
	if len(out) == 0 {
		t.Fatalf("%s: found no Severity constants — the parity check would pass vacuously, so it fails instead", modelPath)
	}
	return out
}

// --- the checks ------------------------------------------------------------

// TestContractParity is the check the hand-written mirror exists for: it fails
// when contract.ts and the Go wire structs disagree.
func TestContractParity(t *testing.T) {
	ifaces := parseInterfaces(t, readContract(t))
	structs := wireStructs(t)

	// Both directions of the type set. An unmirrored Go struct means the
	// frontend cannot describe part of the payload; an extra interface means
	// contract.ts has grown a type the wire does not carry, which is the other
	// way this file rots.
	for name := range structs {
		if _, ok := ifaces[name]; !ok {
			t.Errorf("%s declares no `export interface %s`, but board.%s crosses the wire. Mirror it.", contractPath, name, name)
		}
	}
	for name := range ifaces {
		if _, ok := structs[name]; !ok {
			t.Errorf("%s declares `export interface %s`, which mirrors no Go type reachable from board.%s. "+
				"contract.ts is the wire only — move UI-only types to the component that needs them.",
				contractPath, name, wireRoot.Name())
		}
	}

	for name, gt := range structs {
		got, ok := ifaces[name]
		if !ok {
			continue // already reported above
		}
		want := goFields(t, gt)

		byName := make(map[string]tsField, len(got))
		for _, f := range got {
			if _, dup := byName[f.name]; dup {
				t.Errorf("%s:%d: interface %s declares %q twice", contractPath, f.line, name, f.name)
			}
			byName[f.name] = f
		}

		for _, w := range want {
			g, ok := byName[w.name]
			if !ok {
				t.Errorf("interface %s is missing %q (%s).\n"+
					"The contract is additive-only: a Go field must be mirrored in the same change, and may never be renamed or removed.",
					name, w.name, w.origin)
				continue
			}
			if g.tsType != w.tsType {
				t.Errorf("%s:%d: %s.%s is %q, want %q (%s)", contractPath, g.line, name, w.name, g.tsType, w.tsType, w.origin)
			}
			if g.optional != w.optional {
				verb := map[bool]string{true: "optional (`?`)", false: "required (no `?`)"}
				t.Errorf("%s:%d: %s.%s is %s, want %s (%s) — the Go tag decides: omitempty/omitzero means the key can be absent.",
					contractPath, g.line, name, w.name, verb[g.optional], verb[w.optional], w.origin)
			}
			delete(byName, w.name)
		}
		for leftover, f := range byName {
			t.Errorf("%s:%d: interface %s declares %q, which board.%s does not emit. "+
				"Either it was renamed on the Go side (rename is forbidden — the field must stay) or it never existed.",
				contractPath, f.line, name, leftover, name)
		}
	}
}

// TestSeverityParity checks the string union against the Go constants. A band
// added in Go and not mirrored here leaves every exhaustive switch in the
// frontend quietly wrong, so it fails the build instead.
func TestSeverityParity(t *testing.T) {
	m := severityRE.FindStringSubmatch(readContract(t))
	if m == nil {
		t.Fatalf("%s: no `export type Severity = ...;` declaration found", contractPath)
	}
	var got []string
	for _, part := range strings.Split(m[1], "|") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		got = append(got, strings.Trim(part, `'"`))
	}
	want := goSeverities(t)

	sortedGot, sortedWant := append([]string(nil), got...), append([]string(nil), want...)
	sort.Strings(sortedGot)
	sort.Strings(sortedWant)
	if !reflect.DeepEqual(sortedGot, sortedWant) {
		t.Errorf("Severity union is %v, want %v (from the Severity constants in %s)", got, want, modelPath)
	}
}

// fixtureBoard is the sample the fixture is generated from. Every field of every
// wire struct is populated, including the optional ones — an optional field left
// out of the fixture is a field the TypeScript check cannot see. The second tile
// deliberately omits `updated_at` to exercise the absent case (a source that
// could not read the timestamp), which is why the coverage check below unions
// the tiles instead of demanding every tile be complete.
func fixtureBoard() board.Board {
	no := false
	p1, p3 := 1, 3
	takeaway := "the drill-in plane needs an operator decision on tile density"
	takeawayAt := "2026-08-07T09:31:00Z"
	takeawayBy := "host"

	return board.Board{
		GeneratedAt: time.Date(2026, 8, 11, 15, 4, 5, 0, time.UTC),
		Total:       3,
		// One sitting of each half, so the fixture exercises both the running
		// shape (no outcome, no close stamp) and the finished one.
		Sittings: []board.Sitting{
			{
				ID:       "tk-vst01",
				Rig:      "gc-toolkit",
				Subject:  "tk-eemvf",
				Title:    "visit: tk-eemvf — tile density",
				Status:   "in_progress",
				Session:  "gc-toolkit__converse-1",
				OpenedAt: time.Date(2026, 8, 11, 14, 40, 0, 0, time.UTC),
			},
			{
				ID:       "tk-vst02",
				Rig:      "gascity",
				Subject:  "gt-1a2b3",
				Title:    "visit: gt-1a2b3 — the convoy is complete",
				Status:   "closed",
				Outcome:  "diagnosed",
				Session:  "gascity__converse-2",
				OpenedAt: time.Date(2026, 8, 11, 9, 12, 0, 0, time.UTC),
				ClosedAt: time.Date(2026, 8, 11, 9, 48, 0, 0, time.UTC),
				Takeaway: "the roll-up was right; the convoy's own progress claim was stale",
			},
		},
		Tiles: []board.Tile{
			{
				ID:       "tk-eemvf",
				Rig:      "gc-toolkit",
				Kind:     "epic",
				Title:    "Attention Canvas — spatial in-canvas operator dashboard",
				Severity: board.SevHigh,

				Weight: 14,
				Held:   true,

				NClosed:    3,
				MTotal:     11,
				Open:       8,
				InProgress: 2,
				Assigned:   3,

				InProgressLive: 1,
				InProgressDead: 1,
				DeadOwner:      true,

				InFlight:      1,
				InFlightHeads: []string{"tk-eemvf.3"},

				Owned: nil,

				Stranded:         false,
				Empty:            false,
				Complete:         false,
				ProgressMismatch: false,

				StaleDays:      4,
				Priority:       &p1,
				CrossRigRefs:   []string{"sl-9k2mq"},
				OpenHeads:      []string{"tk-eemvf.5", "tk-eemvf.6"},
				DeadOwnerHeads: []string{"tk-eemvf.4"},
				// The populated case: one of the eight open children is parked,
				// so the frontier below reports seven idle and names the eighth.
				ParkedHeads: []string{"tk-eemvf.7"},

				Takeaway:   &takeaway,
				TakeawayAt: &takeawayAt,
				TakeawayBy: &takeawayBy,

				UpdatedAt: time.Date(2026, 8, 7, 9, 30, 0, 0, time.UTC),
				Frontier:  "7 open · 1 in flight · 1 stuck (dead owner) · 1 parked for the operator",
				Needs:     takeaway,
				RankScore: 3014004,
			},
			{
				ID:       "gt-1a2b3",
				Rig:      "gascity",
				Kind:     "convoy",
				Title:    "A convoy whose source could not read updated_at",
				Severity: board.SevLow,

				Weight: 3,
				Held:   false,

				NClosed:    2,
				MTotal:     2,
				Open:       0,
				InProgress: 0,
				Assigned:   0,

				InProgressLive: 0,
				InProgressDead: 0,
				DeadOwner:      false,

				InFlight:      0,
				InFlightHeads: []string{},

				// A convoy is the one kind that carries `owned`; false marks the
				// orphan exception, and the fixture pins BOTH pointer states so
				// the TypeScript `boolean | null` is exercised either way.
				Owned: &no,

				Stranded:         false,
				Empty:            false,
				Complete:         true,
				ProgressMismatch: true,

				StaleDays:      0,
				Priority:       &p3,
				CrossRigRefs:   []string{},
				OpenHeads:      []string{},
				DeadOwnerHeads: []string{},
				ParkedHeads:    []string{},

				// The absent case for the takeaway triple: null, never omitted.
				Takeaway:   nil,
				TakeawayAt: nil,
				TakeawayBy: nil,

				Frontier:  "all 2 closed · 0 open",
				Needs:     "all 2 closed — graduate",
				RankScore: 3000,
			},
			// A merge anchor: the PR round-trip's row. Wedged at the convergence
			// cap's exception, which is the live shape six of the seven wedged
			// anchors carried when the surface was designed — and with no PR
			// number, because that is the state most of them were in. It pins
			// the whole axis field set, including the zero `pr_number` a
			// pre-open row carries and the `pr_owed_since` the queue is ranked
			// by, so the TypeScript side sees every one of them.
			{
				ID:       "tk-01n5cc",
				Rig:      "gc-toolkit",
				Kind:     "human",
				Title:    "Write the city's own review posture back to GitHub",
				Severity: board.SevElevated,

				Owed:   true,
				Weight: 3,
				Held:   false,

				NClosed:    0,
				MTotal:     0,
				Open:       0,
				InProgress: 0,
				Assigned:   0,

				InProgressLive: 0,
				InProgressDead: 0,
				DeadOwner:      false,

				InFlight:      0,
				InFlightHeads: []string{},

				Owned: nil,

				Stranded:         false,
				Empty:            false,
				Complete:         false,
				ProgressMismatch: false,

				StaleDays:      3,
				Priority:       &p1,
				CrossRigRefs:   []string{},
				OpenHeads:      []string{},
				DeadOwnerHeads: []string{},
				ParkedHeads:    []string{},

				Takeaway:   nil,
				TakeawayAt: nil,
				TakeawayBy: nil,

				UpdatedAt: time.Date(2026, 8, 11, 14, 55, 0, 0, time.UTC),
				Frontier:  "polecat/tk-01n5cc · owed 3d",
				Needs:     "wedged: the review cap parked this anchor — a ruling releases it, a new commit does not",
				RankScore: 2003003,

				// No PR number: the branch is pushed and gated, and nothing has
				// opened a pull request for it, so the branch is what names the
				// row wherever a surface has to identify it.
				PRNumber:       0,
				PRURL:          "",
				PRBranch:       "polecat/tk-01n5cc",
				PRMachine:      board.MachineWedgedException,
				PRConversation: board.ConversationUnknown,
				PRApproval:     board.AxisUnknown,
				// Three days before the board was generated, and held there by
				// every reconcile pass in between.
				PROwedSince: time.Date(2026, 8, 8, 11, 2, 0, 0, time.UTC),
			},
			// The DONE row: an anchor whose own bead has closed. It is here to
			// carry closed_at — the one field only this band ever sets — into
			// the TypeScript check, which cannot see a field no tile populates.
			{
				ID:       "tk-9tbbk",
				Rig:      "gc-toolkit",
				Kind:     "parked",
				Title:    "A conversation the operator watched close",
				Severity: board.SevDone,

				Weight: 1,
				Held:   false,

				NClosed:    1,
				MTotal:     1,
				Open:       0,
				InProgress: 0,
				Assigned:   0,

				InProgressLive: 0,
				InProgressDead: 0,
				DeadOwner:      false,

				InFlight:      0,
				InFlightHeads: []string{},

				Owned: nil,

				Stranded:         false,
				Empty:            false,
				Complete:         true,
				ProgressMismatch: false,

				StaleDays:      1,
				Priority:       &p3,
				CrossRigRefs:   []string{},
				OpenHeads:      []string{},
				DeadOwnerHeads: []string{},
				ParkedHeads:    []string{},

				Takeaway:   nil,
				TakeawayAt: nil,
				TakeawayBy: nil,

				UpdatedAt: time.Date(2026, 8, 10, 9, 0, 0, 0, time.UTC),
				ClosedAt:  time.Date(2026, 8, 10, 9, 30, 0, 0, time.UTC),
				Frontier:  "closed 1d ago",
				Needs:     "closed — dismiss to clear",
				RankScore: -1_000_000 + 998, // the DONE lane: closed 1 day ago
			},
		},
		Partial:       true,
		PartialErrors: []string{"rig shutupandlisten: context canceled"},

		// The three shapes a build row takes: one current, one whose build
		// failed and left an older binary serving, and one whose binary builds
		// but cannot read the stores. The last two are the states the strip
		// exists for, so a fixture without them would let the failing branches
		// of the mirror go unchecked — and probe_status and probe_detail are
		// carried by no other row, which is the only way TypeScript sees them.
		PackHealth: []board.PackBuild{
			{
				Component:      "gctk",
				BuiltAt:        time.Date(2026, 8, 10, 4, 2, 1, 0, time.UTC),
				SourceRev:      "9f1c0b7e5a4d3c2b1a09876543210fedcba98765",
				BinaryRev:      "1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d",
				LastBuildRC:    1,
				RestartPending: false,
				CheckedAt:      time.Date(2026, 8, 11, 15, 0, 0, 0, time.UTC),
				Severity:       board.SevHigh,
				Detail:         "last build FAILED (rc 1); still serving 1a2b3c4d5e6f",
			},
			{
				Component:      "dolt-probe",
				BuiltAt:        time.Date(2026, 8, 11, 14, 40, 0, 0, time.UTC),
				SourceRev:      "9f1c0b7e5a4d3c2b1a09876543210fedcba98765",
				BinaryRev:      "9f1c0b7e5a4d3c2b1a09876543210fedcba98765",
				LastBuildRC:    0,
				RestartPending: false,
				ProbeStatus:    "unreadable",
				ProbeDetail:    "rig shutupandlisten: dial tcp 127.0.0.1:3306: connect: connection refused",
				CheckedAt:      time.Date(2026, 8, 11, 15, 0, 0, 0, time.UTC),
				Severity:       board.SevHigh,
				Detail: "9f1c0b7e5a4d CANNOT read the city's bead stores — the board will not render: " +
					"rig shutupandlisten: dial tcp 127.0.0.1:3306: connect: connection refused",
			},
			{
				Component:      "helm",
				BuiltAt:        time.Date(2026, 8, 11, 14, 55, 0, 0, time.UTC),
				SourceRev:      "9f1c0b7e5a4d3c2b1a09876543210fedcba98765",
				BinaryRev:      "9f1c0b7e5a4d3c2b1a09876543210fedcba98765",
				LastBuildRC:    0,
				RestartPending: false,
				ProbeStatus:    "ok",
				CheckedAt:      time.Date(2026, 8, 11, 15, 0, 0, 0, time.UTC),
				Severity:       board.SevNormal,
				Detail:         "current at 9f1c0b7e5a4d",
			},
		},
	}
}

// renderFixture marshals the sample the way the service does — SetEscapeHTML
// (false), matching server.handleBoard — but indented, because a committed
// golden nobody can read in a diff is a golden nobody reviews.
func renderFixture(t *testing.T) []byte {
	t.Helper()
	var buf strings.Builder
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "  ")
	if err := enc.Encode(fixtureBoard()); err != nil {
		t.Fatalf("encode fixture: %v", err)
	}
	return []byte(buf.String())
}

// TestBoardFixture keeps the committed fixture equal to what the Go types emit
// today. src/contract.fixture.ts asserts that same file against the TypeScript
// contract at compile time, so between them a renamed or dropped Go field fails
// twice: here (the fixture is stale) and in `npm run build` (the regenerated
// fixture no longer satisfies the mirror).
func TestBoardFixture(t *testing.T) {
	want := renderFixture(t)

	if *updateFixture {
		if err := os.WriteFile(fixturePath, want, 0o644); err != nil {
			t.Fatalf("write %s: %v", fixturePath, err)
		}
		t.Logf("rewrote %s", fixturePath)
		return
	}

	got, err := os.ReadFile(fixturePath)
	if err != nil {
		t.Fatalf("read %s: %v\nRegenerate it: go test ./web -run TestBoardFixture -update", fixturePath, err)
	}
	if string(got) != string(want) {
		t.Errorf("%s is stale — it no longer matches what the Go types emit.\n"+
			"Regenerate it (go test ./web -run TestBoardFixture -update), then run `npm run build` in web/: "+
			"if the change was a rename or a removal, TypeScript will reject the new fixture, which is the point.\n"+
			"--- committed ---\n%s\n--- from the Go types ---\n%s", fixturePath, got, want)
	}
}

// TestFixtureCoversEveryField stops the fixture from decaying into a check that
// passes because it exercises nothing. TypeScript can only catch a field the
// fixture actually carries: an optional field that is never populated is
// invisible to it. So every wire key must appear somewhere in the fixture.
func TestFixtureCoversEveryField(t *testing.T) {
	var decoded map[string]json.RawMessage
	if err := json.Unmarshal(renderFixture(t), &decoded); err != nil {
		t.Fatalf("decode fixture: %v", err)
	}

	assertCovers(t, "Board", mustWireStruct(t, "Board"), keysOf(decoded))

	var tiles []map[string]json.RawMessage
	if err := json.Unmarshal(decoded["tiles"], &tiles); err != nil {
		t.Fatalf("decode fixture tiles: %v", err)
	}
	if len(tiles) == 0 {
		t.Fatal("the fixture carries no tiles, so it exercises none of the Tile contract")
	}
	union := map[string]bool{}
	for _, tile := range tiles {
		for k := range tile {
			union[k] = true
		}
	}
	assertCovers(t, "Tile", mustWireStruct(t, "Tile"), union)

	var sittings []map[string]json.RawMessage
	if err := json.Unmarshal(decoded["sittings"], &sittings); err != nil {
		t.Fatalf("decode fixture sittings: %v", err)
	}
	if len(sittings) == 0 {
		t.Fatal("the fixture carries no sittings, so it exercises none of the Sitting contract")
	}
	sittingKeys := map[string]bool{}
	for _, s := range sittings {
		for k := range s {
			sittingKeys[k] = true
		}
	}
	assertCovers(t, "Sitting", mustWireStruct(t, "Sitting"), sittingKeys)

	// pack_health is OPTIONAL on the wire, which is exactly why it needs its own
	// arm: an absent key is a fixture that exercises none of PackBuild, and every
	// one of its own optional fields would then be invisible to TypeScript too.
	// An absent key fails here rather than being skipped.
	raw, ok := decoded["pack_health"]
	if !ok {
		t.Fatal("the fixture carries no pack_health key, so it exercises none of the PackBuild contract")
	}
	var packHealth []map[string]json.RawMessage
	if err := json.Unmarshal(raw, &packHealth); err != nil {
		t.Fatalf("decode fixture pack_health: %v", err)
	}
	if len(packHealth) == 0 {
		t.Fatal("the fixture carries no pack builds, so it exercises none of the PackBuild contract")
	}
	packKeys := map[string]bool{}
	for _, row := range packHealth {
		for k := range row {
			packKeys[k] = true
		}
	}
	assertCovers(t, "PackBuild", mustWireStruct(t, "PackBuild"), packKeys)
}

func keysOf(m map[string]json.RawMessage) map[string]bool {
	out := make(map[string]bool, len(m))
	for k := range m {
		out[k] = true
	}
	return out
}

func assertCovers(t *testing.T, name string, gt reflect.Type, present map[string]bool) {
	t.Helper()
	for _, f := range goFields(t, gt) {
		if !present[f.name] {
			t.Errorf("the fixture never carries %s.%s (%s), so the TypeScript check cannot see it. "+
				"Populate it in fixtureBoard() with a non-zero value, then regenerate: go test ./web -run TestBoardFixture -update",
				name, f.name, f.origin)
		}
	}
}
