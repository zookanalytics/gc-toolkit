// Package gascity is gctk's runtime adapter: Gas City as gctk reaches it apart
// from its store, which internal/gcbd reaches (docs/gctk-architecture.md, "The
// adapters"). It runs `gc sling`, reads the formula a sling to an agent pours
// when it names none, names the city's root, and runs the pack's scripts that
// ask a person. A domain reaches them only through Runtime. City is the city
// gctk runs in, and gascity/fake records what a domain asked and answers as its
// test says, so a domain's rules are tested in Go with no Gas City.
package gascity

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"sync"
)

// Runtime is Gas City as one gctk process reaches it.
type Runtime interface {
	// Sling runs one `gc sling` and returns what it answered.
	Sling(s Sling) SlingResult
	// DefaultFormula is the formula sling s pours when it names none: the
	// default sling formula the city's config gives the agent s.Target
	// addresses, its own or else the one its pack's [agent_defaults] gives it.
	// It is empty when that agent has neither, and an error when the answer
	// does not read or no agent in the config answers to s.Target. It reads
	// s.Rig, s.Target and s.Bead.
	DefaultFormula(s Sling) (string, error)
	// Script runs one of the pack's scripts, by its file name in the pack's
	// scripts directory, and returns what it answered.
	Script(name string, args ...string) Result
	// CityRoot is the city's root directory, the one that holds its .gc.
	CityRoot() (string, error)
}

// Sling is one `gc sling <target> <bead> --on <formula> --title <title>`,
// with gc's --rig when Rig names one.
type Sling struct {
	Rig, Target, Bead, Formula, Title string
}

// Result is what a command answered: its exit code and its output, standard
// output and standard error together. Code is -1 when it did not run, and Err
// then says why.
type Result struct {
	Code   int
	Output string
	Err    error
}

// SlingResult is a sling's Result. Live is the workflows gc sling named when it
// refused the pour because a live workflow already works the bead, which it
// answers with exit 3 alone (sourceworkflow.ConflictError, read in
// cmd/gc/cmd_sling.go at gastownhall/gascity 8d2fb3120c).
type SlingResult struct {
	Result
	Live []string
}

// City is the Gas City gctk runs in, reached through `gc` on PATH and the
// pack's scripts directory GCTK_SCRIPTS_DIR names.
type City struct {
	bin        string
	scriptsDir string

	once   sync.Once
	agents []agent
	cfgErr error
}

var _ Runtime = (*City)(nil)

// New returns the city gctk runs in.
func New() *City {
	return &City{bin: "gc", scriptsDir: os.Getenv("GCTK_SCRIPTS_DIR")}
}

// Sling runs the sling in gctk's own process group, so whatever stops gctk's
// group, such as an order's timeout, stops the sling with it. Its standard
// input reads nothing.
func (c *City) Sling(s Sling) SlingResult {
	args := []string{"sling"}
	if s.Rig != "" {
		args = append(args, "--rig", s.Rig)
	}
	args = append(args, s.Target, s.Bead, "--on", s.Formula, "--title", s.Title)
	r := run(c.bin, args...)
	out := SlingResult{Result: r}
	if r.Code == 3 {
		out.Live = liveWorkflows(r.Output, s.Bead)
	}
	return out
}

// conflictLine opens the line gc sling prints for each source bead whose live
// workflows refuse a pour (printSourceWorkflowConflictLines in
// cmd/gc/cmd_sling.go): "gc sling: source bead <bead> already has live
// workflow(s): <id>,<id>".
const conflictLine = "gc sling: source bead "

// liveWorkflows is the workflows output names as live on bead, each once.
func liveWorkflows(output, bead string) []string {
	var out []string
	sc := bufio.NewScanner(strings.NewReader(output))
	for sc.Scan() {
		rest, ok := strings.CutPrefix(strings.TrimSpace(sc.Text()), conflictLine)
		if !ok {
			continue
		}
		named, ids, ok := strings.Cut(rest, " already has live workflow(s): ")
		if !ok || named != bead {
			continue
		}
		for _, id := range strings.Split(ids, ",") {
			if id = strings.TrimSpace(id); id != "" && !slices.Contains(out, id) {
				out = append(out, id)
			}
		}
	}
	return out
}

// agent is one agent the city's config names: the rig directory it serves, its
// name, and, when Own is set, the default sling formula it names itself, which
// may be empty.
type agent struct {
	Dir, Name, Formula string
	Own                bool
}

// DefaultFormula reads `gc config show --json` once per process. An agent
// answers to s.Target when its directory is the part of s.Target before its
// last slash, none when s.Target has none, and its name is the rest, or the
// rest's last dot-separated part, since a pack's agent is addressed by its
// binding and its name (ParseQualifiedName and BindingQualifiedName in
// internal/config/config.go at gastownhall/gascity 8d2fb3120c), and the
// config's JSON carries no binding. Two agents that answer with different
// formulas of their own are no answer. The JSON carries only an agent's own
// default: the one its pack's [agent_defaults] gives it, which gc sling pours
// when the agent names none, is a runtime-only field it leaves out
// (InheritedDefaultSlingFormula and EffectiveDefaultSlingFormula in
// internal/config/config.go at 8d2fb3120c). So when an agent that answers names
// none of its own, Gas City's dry run of the sling says which it pours.
func (c *City) DefaultFormula(s Sling) (string, error) {
	c.once.Do(func() { c.agents, c.cfgErr = c.readAgents() })
	if c.cfgErr != nil {
		return "", c.cfgErr
	}
	dir, name := "", s.Target
	if i := strings.LastIndex(s.Target, "/"); i >= 0 {
		dir, name = s.Target[:i], s.Target[i+1:]
	}
	var formulas []string
	matched, inherits := false, false
	for _, a := range c.agents {
		if a.Dir != dir || (a.Name != name && !strings.HasSuffix(name, "."+a.Name)) {
			continue
		}
		matched = true
		if !a.Own {
			inherits = true
		} else if !slices.Contains(formulas, a.Formula) {
			formulas = append(formulas, a.Formula)
		}
	}
	switch {
	case !matched:
		return "", fmt.Errorf("no agent in the city's config answers to %s", s.Target)
	case inherits:
		return c.dryRunFormula(s)
	case len(formulas) > 1:
		return "", fmt.Errorf("the agents in the city's config that answer to %s name different default formulas (%s)", s.Target, strings.Join(formulas, ", "))
	}
	return formulas[0], nil
}

// dryRunFormula is the default formula `gc sling --dry-run` says sling s pours.
// Its preview prints the formula EffectiveDefaultSlingFormula resolves, and its
// --json form prints none (dryRunSingle and dryRunBatch in cmd/gc/cmd_sling.go
// at gastownhall/gascity 8d2fb3120c). Without --force the preview stops at a
// bead a live workflow already works, before it prints the formula
// (dryRunReportBlockingWorkflow there). A dry run executes nothing.
func (c *City) dryRunFormula(s Sling) (string, error) {
	if s.Bead == "" {
		return "", fmt.Errorf("%s names no default formula of its own, and with no bead to name, gc sling --dry-run cannot say which its pack gives it", s.Target)
	}
	args := []string{"sling"}
	if s.Rig != "" {
		args = append(args, "--rig", s.Rig)
	}
	args = append(args, s.Target, s.Bead, "--dry-run", "--force")
	r := run(c.bin, args...)
	if r.Code != 0 {
		return "", fmt.Errorf("%s names no default formula of its own, and gc sling --dry-run did not say which its pack gives it: %s", s.Target, r.why())
	}
	f, ok := dryRunDefault(r.Output)
	if !ok {
		return "", fmt.Errorf("%s names no default formula of its own, and gc sling --dry-run's preview did not read: %s", s.Target, r.Tail())
	}
	return f, nil
}

// The lines of a dry run's preview that dryRunDefault reads: the heading over
// the default formula, for a bead or for each open child of a container, the
// formula's line under it, and the preview's last line.
const (
	defaultHeading      = "Default formula:"
	defaultChildHeading = "Default formula (per open child):"
	formulaLine         = "  Formula: "
	previewEnd          = "No side effects executed (--dry-run)."
)

// dryRunDefault reads the formula a dry run's preview pours by default: the
// formula line under its default formula heading, or empty when a preview that
// reached its last line has no such heading. ok is false for a preview that
// stops short of its last line, a heading with no formula line under it, or two
// headings.
func dryRunDefault(preview string) (formula string, ok bool) {
	lines := strings.Split(strings.ReplaceAll(preview, "\r\n", "\n"), "\n")
	ended := false
	for i, l := range lines {
		switch l {
		case previewEnd:
			ended = true
		case defaultHeading, defaultChildHeading:
			if formula != "" || i+1 == len(lines) {
				return "", false
			}
			f, found := strings.CutPrefix(lines[i+1], formulaLine)
			if f = strings.TrimSpace(f); !found || f == "" {
				return "", false
			}
			formula = f
		}
	}
	if !ended {
		return "", false
	}
	return formula, true
}

func (c *City) readAgents() ([]agent, error) {
	r := run(c.bin, "config", "show", "--json")
	if r.Code != 0 {
		return nil, fmt.Errorf("gc config show did not read the city's config: %s", r.why())
	}
	var shown struct {
		Config struct {
			Agents []struct {
				Name                string  `json:"Name"`
				Dir                 string  `json:"Dir"`
				DefaultSlingFormula *string `json:"DefaultSlingFormula"`
			} `json:"Agents"`
		} `json:"config"`
	}
	if err := json.Unmarshal([]byte(r.Output), &shown); err != nil {
		return nil, fmt.Errorf("gc config show's answer did not decode: %v", err)
	}
	out := make([]agent, 0, len(shown.Config.Agents))
	for _, a := range shown.Config.Agents {
		ag := agent{Dir: a.Dir, Name: a.Name}
		if a.DefaultSlingFormula != nil {
			ag.Formula, ag.Own = strings.TrimSpace(*a.DefaultSlingFormula), true
		}
		out = append(out, ag)
	}
	return out, nil
}

// Script runs the script from the directory GCTK_SCRIPTS_DIR names, which the
// pack's caller of gctk sets, as gctk-resolve.sh does for a bridge.
func (c *City) Script(name string, args ...string) Result {
	if c.scriptsDir == "" {
		return Result{Code: -1, Err: errors.New("GCTK_SCRIPTS_DIR names no pack scripts directory, so " + name + " cannot be run")}
	}
	return run(filepath.Join(c.scriptsDir, name), args...)
}

// CityRoot is GC_CITY_PATH, GC_CITY or GC_CITY_ROOT, the first that names an
// absolute directory holding .gc, else the path `gc rig list --json` gives the
// city's HQ rig, the chain Accept's lock reads (city_root in
// assets/scripts/gc-helm.sh).
func (c *City) CityRoot() (string, error) {
	for _, v := range []string{"GC_CITY_PATH", "GC_CITY", "GC_CITY_ROOT"} {
		if p := os.Getenv(v); filepath.IsAbs(p) && isDir(filepath.Join(p, ".gc")) {
			return p, nil
		}
	}
	r := run(c.bin, "rig", "list", "--json")
	if r.Code != 0 {
		return "", fmt.Errorf("no city root: GC_CITY_PATH, GC_CITY and GC_CITY_ROOT name none, and gc rig list did not read: %s", r.why())
	}
	var list struct {
		Rigs []struct {
			Path string `json:"path"`
			HQ   bool   `json:"hq"`
		} `json:"rigs"`
	}
	if err := json.Unmarshal([]byte(r.Output), &list); err != nil {
		return "", fmt.Errorf("no city root: gc rig list's answer did not decode: %v", err)
	}
	for _, rig := range list.Rigs {
		if rig.HQ && rig.Path != "" && isDir(filepath.Join(rig.Path, ".gc")) {
			return rig.Path, nil
		}
	}
	return "", errors.New("no city root: GC_CITY_PATH, GC_CITY and GC_CITY_ROOT name none, and gc rig list names no HQ rig holding .gc")
}

func isDir(p string) bool {
	fi, err := os.Stat(p)
	return err == nil && fi.IsDir()
}

// run runs bin with args, its standard input reading nothing, and returns its
// exit code and its output.
func run(bin string, args ...string) Result {
	cmd := exec.Command(bin, args...)
	var out bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &out
	err := cmd.Run()
	var ee *exec.ExitError
	switch {
	case err == nil:
		return Result{Code: 0, Output: out.String()}
	case errors.As(err, &ee):
		return Result{Code: ee.ExitCode(), Output: out.String()}
	default:
		return Result{Code: -1, Output: out.String(), Err: err}
	}
}

// why is a result's failure in one line: why it did not run, or its exit and
// its output's last line.
func (r Result) why() string {
	if r.Err != nil {
		return r.Err.Error()
	}
	return fmt.Sprintf("exit %d: %s", r.Code, r.Tail())
}

// Tail is the last line of the output that is not blank, "it printed nothing"
// when none is.
func (r Result) Tail() string {
	lines := strings.Split(strings.TrimSpace(r.Output), "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		if l := strings.TrimSpace(lines[i]); l != "" {
			return l
		}
	}
	return "it printed nothing"
}

// Failure is why a result is a failure, in one line, empty for exit 0.
func (r Result) Failure() string {
	if r.Err == nil && r.Code == 0 {
		return ""
	}
	return r.why()
}
