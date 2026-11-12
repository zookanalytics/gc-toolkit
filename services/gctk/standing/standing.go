// Package standing holds the standing kinds: the task_kind values whose bead
// is a standing record. A standing record is open, unrouted and unassigned by
// design, and it never closes. No worker claims it, and it is neither work nor
// an ask.
//
// kinds.json is the one definition of the list, and it names what each kind's
// record is and what files it. The package embeds it for the Go readers, and
// the pack's jq readers read the same file through
// assets/scripts/standing-kinds.sh, so a kind added there reaches every reader
// at once. assets/scripts/standing-kinds.test.sh fails when a reader carries a
// list of its own.
//
// The package sits outside internal/ so the helm board, a separate module, can
// ask it.
package standing

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"slices"
	"strings"
)

//go:embed kinds.json
var definition []byte

// kinds is every standing kind kinds.json names, sorted.
var kinds = mustParse(definition)

// mustParse reads the definition: a JSON object whose keys are the kinds, each
// with a description of its record. The file is compiled in, so a definition
// that does not read is a defect of the build, refused before any reader can
// take it for an empty list.
func mustParse(raw []byte) []string {
	out, err := parse(raw)
	if err != nil {
		panic(fmt.Sprintf("standing: kinds.json %v", err))
	}
	return out
}

// parse is the definition's kinds, sorted, or why it does not read. Every kind
// and every description must hold text, since an empty kind would name every
// bead that carries no task_kind as standing.
func parse(raw []byte) ([]string, error) {
	var byKind map[string]string
	if err := json.Unmarshal(raw, &byKind); err != nil {
		return nil, fmt.Errorf("does not read as an object of kinds: %w", err)
	}
	if len(byKind) == 0 {
		return nil, fmt.Errorf("names no kind")
	}
	out := make([]string, 0, len(byKind))
	for k, what := range byKind {
		if k == "" {
			return nil, fmt.Errorf("names an empty kind")
		}
		if strings.TrimSpace(what) == "" {
			return nil, fmt.Errorf("does not say what a %s record is", k)
		}
		out = append(out, k)
	}
	slices.Sort(out)
	return out, nil
}

// Kinds is every standing kind, sorted.
func Kinds() []string { return slices.Clone(kinds) }

// Is reports whether a bead whose task_kind holds kind is a standing record.
// The match is exact, as is_standing_kind in standing-kinds.sh makes it.
func Is(kind string) bool { return slices.Contains(kinds, kind) }
