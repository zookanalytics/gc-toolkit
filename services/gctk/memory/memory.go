// Package memory is the learning loop's second intake: the agent memory notes
// the feedback distiller judges beside its observations
// (specs/tk-zlot608.2/design.md). It finds each memory directory by asking
// Claude Code, lists the notes due for the judge, records each decision on a
// list kept per directory, and ends a note's wait once what it waits on is
// done. The judging is the distiller's, by the learning-distill skill.
//
// A unit is a whole note, or an entry of a collection note (hub-*.md) that
// carries text of its own. The index, MEMORY.md, is never judged.
package memory

import (
	"crypto/sha256"
	"encoding/hex"
	"regexp"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/claudecode"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// Intake reads and keeps the city's memory directories.
type Intake struct {
	// Runtime names the city's root, its rigs and the settings file its Claude
	// sessions start with.
	Runtime gascity.Runtime
	// Claude answers where a session started in a place keeps its memory.
	Claude claudecode.Claude
	// Store opens the ledger over the store whose .beads directory is db.
	Store func(db string) (*ledger.Ledger, error)
	// Now is the clock, time.Now when nil.
	Now func() time.Time
	// LockWait is how long a write waits for another run's lock on a
	// directory's state.
	LockWait time.Duration
}

// The two kinds of unit.
const (
	Note  = "note"
	Entry = "entry"
)

// The files a directory holds that the intake reads by name.
const (
	indexName = "MEMORY.md"
	hubPrefix = "hub-"
)

// stateDir is the intake's state under the city's root: one directory per
// memory directory, named for the SHA-256 of its real path.
var stateDir = []string{".gc", "runtime", "packs", "gc-toolkit", "memory-intake"}

// useMark begins the line that asks a note's users to record the days they use
// it, and useLine is that line.
const (
	useMark = "<!-- memory-intake: use -->"
	useLine = useMark + " When this note steers your work and holds no used line for today, add one at its end: " +
		"used <YYYY-MM-DD>: <what it changed>"
)

// useRecord matches a line that records a day a note was used.
var useRecord = regexp.MustCompile(`^(- )?used [0-9]{4}-[0-9]{2}-[0-9]{2}`)

func (in *Intake) now() time.Time {
	if in.Now != nil {
		return in.Now().UTC()
	}
	return time.Now().UTC()
}

func (in *Intake) today() string { return in.now().Format(time.DateOnly) }

// sum is the hex SHA-256 of text.
func sum(text string) string {
	h := sha256.Sum256([]byte(text))
	return hex.EncodeToString(h[:])
}

// oneLine is s with each control character a space, cut to 240 runes, for a
// value the list keeps in one field.
func oneLine(s string) string {
	s = strings.Map(func(r rune) rune {
		if r < 0x20 || r == 0x7f {
			return ' '
		}
		return r
	}, s)
	if r := []rune(s); len(r) > 240 {
		s = string(r[:240])
	}
	return s
}
