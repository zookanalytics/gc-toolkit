package source

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/board"
)

// The build orders leave one status file per compiled component, under that
// component's service state root. Reading it is deliberately the cheapest thing
// on the gather: one glob and a handful of small JSON files, no subprocess and
// no git. The build order already paid for the revisions; this only reports
// them.
//
// The file is the ONLY input. Re-deriving staleness here — stat the binary,
// walk the sources — would be a second implementation of the question the build
// order already answers, and the two would disagree the moment one of them was
// fixed.

// buildStatusFile is the per-component file name, and servicesDir the directory
// the build orders write their state roots under.
const (
	buildStatusFile = "build-status.json"
	servicesDir     = ".gc/services"
)

// packBuildFile is the on-disk shape. It is decoded separately from
// [board.PackBuild] so the wire type can carry derived fields the file does not.
type packBuildFile struct {
	Component      string `json:"component"`
	BuiltAt        string `json:"built_at"`
	SourceRev      string `json:"source_rev"`
	BinaryRev      string `json:"binary_rev"`
	LastBuildRC    int    `json:"last_build_rc"`
	RestartPending bool   `json:"restart_pending"`
	ProbeStatus    string `json:"probe_status"`
	ProbeDetail    string `json:"probe_detail"`
	CheckedAt      string `json:"checked_at"`
}

// GatherPackHealth reads every component's build status under cityPath. It is
// best-effort in the same way the rest of the gather is: an unreadable or
// malformed file is skipped rather than failing the board, because a board that
// refuses to render teaches the operator less than a board missing one row.
//
// An empty cityPath, or a city with no status files, returns nil — which is the
// correct answer for a city whose build orders have never run, and renders as no
// section at all rather than as a fabricated all-clear.
func GatherPackHealth(cityPath string, now time.Time) []board.PackBuild {
	if cityPath == "" {
		return nil
	}
	// A service's state root must sit under .gc/services/ but may be nested
	// one level deeper (a pack that groups its services), and gc-helm-build.sh
	// writes wherever `gc service list` reports; both depths are read so a
	// grouped component does not vanish from the board.
	var matches []string
	for _, pattern := range []string{
		filepath.Join(cityPath, servicesDir, "*", buildStatusFile),
		filepath.Join(cityPath, servicesDir, "*", "*", buildStatusFile),
	} {
		m, err := filepath.Glob(pattern)
		if err != nil {
			continue
		}
		matches = append(matches, m...)
	}
	if len(matches) == 0 {
		return nil
	}
	sort.Strings(matches)

	rows := make([]board.PackBuild, 0, len(matches))
	for _, path := range matches {
		raw, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		var f packBuildFile
		if err := json.Unmarshal(raw, &f); err != nil {
			continue
		}
		component := f.Component
		if component == "" {
			// Fall back to the directory that holds it: the state root is named
			// for the component, so a file that forgot to say what it describes
			// is still placed.
			component = filepath.Base(filepath.Dir(path))
		}
		builtAt, _ := parseStamp(f.BuiltAt)
		checkedAt, _ := parseStamp(f.CheckedAt)
		rows = append(rows, board.PackBuild{
			Component:      component,
			BuiltAt:        builtAt,
			SourceRev:      f.SourceRev,
			BinaryRev:      f.BinaryRev,
			LastBuildRC:    f.LastBuildRC,
			RestartPending: f.RestartPending,
			ProbeStatus:    f.ProbeStatus,
			ProbeDetail:    f.ProbeDetail,
			CheckedAt:      checkedAt,
		})
	}
	if len(rows) == 0 {
		return nil
	}
	return board.DerivePackHealth(rows, now)
}
