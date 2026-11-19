package memory

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/claudecode"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
)

// A Place is one memory directory the intake reads.
type Place struct {
	// Dir is the directory's real path, and Key the hex SHA-256 of it.
	Dir, Key string
	// Names are the rigs whose sessions keep memory there.
	Names []string
}

// Absent is a place whose memory directory is not there.
type Absent struct{ Name, Dir string }

// Unknown is a place whose memory directory the intake could not learn.
type Unknown struct{ Name, Why string }

// Places is where the city's sessions keep memory: one ask of Claude Code in
// each rig's checkout and the city's root.
type Places struct {
	Read    []Place
	Absent  []Absent
	Unknown []Unknown
	// Root is the city's root, Rigs the city's rigs, and State the root of the
	// intake's state.
	Root  string
	Rigs  []gascity.Rig
	State string
}

// Places asks Claude Code where a session started in each rig's checkout and in
// the city's root keeps its memory, and reads one place per real path. A row of
// the rig list that names no rig or no checkout is no place. A place Claude
// Code names no directory for, or whose answer is not a directory, is one it
// cannot learn. An error is a city whose root or rigs did not read.
func (in *Intake) Places() (Places, error) {
	root, err := in.Runtime.CityRoot()
	if err != nil {
		return Places{}, err
	}
	rigs, err := in.Runtime.Rigs()
	if err != nil {
		return Places{}, err
	}
	settings, err := in.Runtime.ClaudeSettings()
	if err != nil {
		return Places{}, err
	}
	p := Places{Root: root, Rigs: rigs, State: filepath.Join(append([]string{root}, stateDir...)...)}
	type ask struct{ name, dir string }
	var asks []ask
	seen := map[string]bool{}
	for _, r := range rigs {
		if r.Name != "" && r.Path != "" && !seen[r.Path] {
			seen[r.Path] = true
			asks = append(asks, ask{r.Name, r.Path})
		}
	}
	if !seen[root] {
		asks = append(asks, ask{"the city's root", root})
	}
	at := map[string]int{}
	for _, a := range asks {
		ans, err := in.Claude.MemoryDir(claudecode.Ask{Dir: a.dir, Settings: settings})
		if err != nil {
			p.Unknown = append(p.Unknown, Unknown{a.name, "Claude Code did not say where it keeps memory: " + err.Error()})
			continue
		}
		dir, why := placed(ans)
		switch {
		case why != "":
			p.Unknown = append(p.Unknown, Unknown{a.name, why})
		case dir == "":
			p.Absent = append(p.Absent, Absent{a.name, ans.Dir})
		default:
			if i, ok := at[dir]; ok {
				p.Read[i].Names = append(p.Read[i].Names, a.name)
				continue
			}
			at[dir] = len(p.Read)
			p.Read = append(p.Read, Place{Dir: dir, Key: sum(dir), Names: []string{a.name}})
		}
	}
	return p, nil
}

// placed is the real path of the directory an answer names, "" when nothing is
// there, or why the answer places no directory.
func placed(ans claudecode.Answer) (dir, why string) {
	version := ans.Version
	if version == "" {
		version = "of an unknown version"
	}
	switch {
	case ans.Dir == "":
		return "", "Claude Code " + version + " named no memory directory: its auto memory is off there, " +
			"or it no longer reports where memory is"
	case !filepath.IsAbs(ans.Dir):
		return "", fmt.Sprintf("Claude Code %s named %q, which is not an absolute path", version, ans.Dir)
	}
	real, err := filepath.EvalSymlinks(ans.Dir)
	if errors.Is(err, fs.ErrNotExist) {
		return "", ""
	}
	if err != nil {
		return "", fmt.Sprintf("the memory directory %s does not resolve: %v", ans.Dir, err)
	}
	if fi, err := os.Stat(real); err != nil || !fi.IsDir() {
		return "", fmt.Sprintf("the memory directory %s is not a directory", ans.Dir)
	}
	return real, ""
}

// state is the directory that holds p's list.
func (ps Places) state(p Place) string { return filepath.Join(ps.State, p.Key) }

// names is p's rigs, joined for a message.
func (p Place) names() string { return strings.Join(p.Names, ", ") }

// ByKey is the place whose key begins with key16.
func (ps Places) byKey(key16 string) (Place, bool) {
	for _, p := range ps.Read {
		if strings.HasPrefix(p.Key, key16) {
			return p, true
		}
	}
	return Place{}, false
}

// rigOf is the rig whose bead prefix begins id, the longest when several do,
// the store gc routes a read of id to.
func (ps Places) rigOf(id string) (gascity.Rig, bool) {
	var best gascity.Rig
	found := false
	for _, r := range ps.Rigs {
		if r.Prefix == "" || !strings.HasPrefix(id, r.Prefix+"-") {
			continue
		}
		if !found || len(r.Prefix) > len(best.Prefix) {
			best, found = r, true
		}
	}
	return best, found
}
