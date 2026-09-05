package source

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/board"
)

var gatherNow = time.Date(2026, 8, 26, 12, 0, 0, 0, time.UTC)

// city writes status files into a throwaway city tree and returns its root.
func city(t *testing.T, files map[string]string) string {
	t.Helper()
	root := t.TempDir()
	for component, body := range files {
		dir := filepath.Join(root, servicesDir, component)
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, buildStatusFile), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func byComponent(rows []board.PackBuild) map[string]board.PackBuild {
	out := map[string]board.PackBuild{}
	for _, r := range rows {
		out[r.Component] = r
	}
	return out
}

func TestGatherReadsEveryComponent(t *testing.T) {
	root := city(t, map[string]string{
		"helm": `{"component":"helm","built_at":"2026-08-26T11:00:00Z","source_rev":"aaaa","binary_rev":"aaaa","last_build_rc":0,"restart_pending":false,"checked_at":"2026-08-26T11:58:00Z"}`,
		"gctk": `{"component":"gctk","built_at":"2026-08-25T09:00:00Z","source_rev":"cccc","binary_rev":"bbbb","last_build_rc":1,"restart_pending":false,"checked_at":"2026-08-26T11:58:00Z"}`,
	})
	rows := GatherPackHealth(root, gatherNow)
	if len(rows) != 2 {
		t.Fatalf("got %d rows, want 2", len(rows))
	}
	got := byComponent(rows)
	if got["helm"].Severity != board.SevNormal {
		t.Errorf("helm severity = %s, want NORMAL", got["helm"].Severity)
	}
	if got["gctk"].Severity != board.SevHigh {
		t.Errorf("gctk severity = %s, want HIGH (its last build failed)", got["gctk"].Severity)
	}
	if want := time.Date(2026, 8, 26, 11, 0, 0, 0, time.UTC); !got["helm"].BuiltAt.Equal(want) {
		t.Errorf("helm built_at = %s, want %s", got["helm"].BuiltAt, want)
	}
}

func TestNoCityAndNoFilesReadAsNothing(t *testing.T) {
	if rows := GatherPackHealth("", gatherNow); rows != nil {
		t.Errorf("an unknown city path returned %v, want nil", rows)
	}
	if rows := GatherPackHealth(t.TempDir(), gatherNow); rows != nil {
		t.Errorf("a city with no status files returned %v, want nil", rows)
	}
}

func TestAMalformedFileIsSkippedNotFatal(t *testing.T) {
	// One unreadable component must not cost the operator the other's row.
	root := city(t, map[string]string{
		"helm": `{ this is not json`,
		"gctk": `{"component":"gctk","source_rev":"dddd","binary_rev":"dddd","last_build_rc":0,"checked_at":"2026-08-26T11:59:00Z"}`,
	})
	rows := GatherPackHealth(root, gatherNow)
	if len(rows) != 1 || rows[0].Component != "gctk" {
		t.Fatalf("got %+v, want the one readable row", rows)
	}
}

func TestComponentFallsBackToItsDirectory(t *testing.T) {
	root := city(t, map[string]string{
		"gctk": `{"source_rev":"eeee","binary_rev":"eeee","last_build_rc":0,"checked_at":"2026-08-26T11:59:00Z"}`,
	})
	rows := GatherPackHealth(root, gatherNow)
	if len(rows) != 1 || rows[0].Component != "gctk" {
		t.Fatalf("got %+v, want a row named for its state root", rows)
	}
}

func TestAnUnparseableStampIsUnknownNotEpoch(t *testing.T) {
	// A zero time reads as "not known" everywhere downstream; 1970 would read as
	// a build order that stopped fifty years ago.
	root := city(t, map[string]string{
		"gctk": `{"component":"gctk","source_rev":"ffff","binary_rev":"ffff","last_build_rc":0,"checked_at":"not a time"}`,
	})
	rows := GatherPackHealth(root, gatherNow)
	if !rows[0].CheckedAt.IsZero() {
		t.Errorf("checked_at = %s, want the zero time", rows[0].CheckedAt)
	}
	if rows[0].Severity != board.SevNormal {
		t.Errorf("severity = %s (%q), want NORMAL", rows[0].Severity, rows[0].Detail)
	}
}

func TestAStoppedBuildOrderIsVisible(t *testing.T) {
	root := city(t, map[string]string{
		"helm": `{"component":"helm","source_rev":"aaaa","binary_rev":"aaaa","last_build_rc":0,"checked_at":"2026-08-25T12:00:00Z"}`,
	})
	rows := GatherPackHealth(root, gatherNow)
	if rows[0].Severity != board.SevElevated {
		t.Errorf("severity = %s (%q), want ELEVATED for a day-old check", rows[0].Severity, rows[0].Detail)
	}
}

func TestGatherCarriesTheProbeOutcomeIntoTheRow(t *testing.T) {
	// The record gc-helm-build.sh writes when a rebuild succeeds and its probe
	// fails: rc 0, matching revisions, nothing pending. Only probe_status
	// separates it from a healthy component, so the decode has to keep it.
	root := city(t, map[string]string{
		"helm": `{"component":"helm","built_at":"2026-08-26T11:00:00Z","source_rev":"aaaa","binary_rev":"aaaa","last_build_rc":0,"restart_pending":false,"probe_status":"unreadable","probe_detail":"beads schema 14 > binary 12","checked_at":"2026-08-26T11:58:00Z"}`,
	})
	rows := GatherPackHealth(root, gatherNow)
	if len(rows) != 1 {
		t.Fatalf("got %d rows, want 1", len(rows))
	}
	if rows[0].ProbeStatus != "unreadable" {
		t.Errorf("probe_status = %q, want unreadable", rows[0].ProbeStatus)
	}
	if rows[0].Severity != board.SevHigh {
		t.Errorf("severity = %s, want HIGH — a condemned binary must not read as current", rows[0].Severity)
	}
	if !strings.Contains(rows[0].Detail, "beads schema 14 > binary 12") {
		t.Errorf("detail %q must carry the probe's reason", rows[0].Detail)
	}
}

func TestGatherOnARecordWrittenBeforeProbeStatusExisted(t *testing.T) {
	// A status file left by the previous build order has no probe_status. It
	// must decode as the absent value and band exactly as it did before, not as
	// a condemned binary.
	root := city(t, map[string]string{
		"helm": `{"component":"helm","built_at":"2026-08-26T11:00:00Z","source_rev":"aaaa","binary_rev":"aaaa","last_build_rc":0,"restart_pending":false,"checked_at":"2026-08-26T11:58:00Z"}`,
	})
	rows := GatherPackHealth(root, gatherNow)
	if len(rows) != 1 || rows[0].ProbeStatus != "" || rows[0].Severity != board.SevNormal {
		t.Fatalf("got %+v, want one NORMAL row with no probe status", rows)
	}
}

// A service may declare a state root one level deeper than .gc/services/<name>
// (a pack that groups its services), and gc-helm-build.sh writes wherever
// `gc service list` reports. The reader must see that depth too, or the
// component silently vanishes from the board.
func TestGatherReadsAStateRootNestedOneLevelDeeper(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, servicesDir, "toolkit", "helm")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	body := `{"component":"","built_at":"2026-08-26T11:00:00Z","source_rev":"aaaa","binary_rev":"aaaa","last_build_rc":0,"restart_pending":false,"checked_at":"2026-08-26T11:58:00Z"}`
	if err := os.WriteFile(filepath.Join(dir, buildStatusFile), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	rows := GatherPackHealth(root, gatherNow)
	if len(rows) != 1 {
		t.Fatalf("got %d rows, want 1", len(rows))
	}
	if rows[0].Component != "helm" {
		t.Errorf("component = %q, want the state root's own name", rows[0].Component)
	}
}
