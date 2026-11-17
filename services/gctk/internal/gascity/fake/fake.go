// Package fake is the runtime adapter's fake: it records each sling, cook,
// session wake, nudge, script call, doctor run, event and list read a domain
// asks for and answers as its test says, so a domain's rules about Gas City are
// tested in Go with no Gas City (docs/gctk-architecture.md, "The adapters").
package fake

import (
	"fmt"
	"slices"
	"sync"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
)

// Call is one script call: the script's name and its arguments.
type Call struct {
	Name string
	Args []string
}

// Runtime is an in-memory gascity.Runtime, safe for concurrent use.
type Runtime struct {
	// Formulas is the default formula each target's agent names itself, and
	// PackFormulas the one its pack's [agent_defaults] gives a target whose
	// agent names none, which the runtime reads only for a sling that names a
	// bead. A target neither names has no agent in the config, and ConfigErr
	// fails every read.
	Formulas, PackFormulas map[string]string
	ConfigErr              error
	// Root is the city's root, and RootErr fails the read of it.
	Root    string
	RootErr error
	// OnSling answers a sling, and nil answers exit 0. OnScript answers a script
	// call, and nil answers exit 0. OnCook answers a cook, and nil answers exit 0
	// with a root of its own. OnWake answers a session's wake and OnNudge its
	// nudge, and nil answers exit 0.
	OnSling  func(gascity.Sling) gascity.SlingResult
	OnScript func(Call) gascity.Result
	OnCook   func(gascity.Cook) gascity.CookResult
	OnWake   func(session string) gascity.Result
	OnNudge  func(Nudge) gascity.Result

	mu      sync.Mutex
	slings  []gascity.Sling
	asks    []gascity.Sling
	scripts []Call
	cooks   []gascity.Cook
	wakes   []string
	nudges  []Nudge
}

// Nudge is one nudge: the session nudged and the message.
type Nudge struct {
	Session, Message string
}

var _ gascity.Runtime = (*Runtime)(nil)

// Sling records s and answers it.
func (r *Runtime) Sling(s gascity.Sling) gascity.SlingResult {
	r.mu.Lock()
	r.slings = append(r.slings, s)
	on := r.OnSling
	r.mu.Unlock()
	if on != nil {
		return on(s)
	}
	return gascity.SlingResult{}
}

// Cook records c and answers it.
func (r *Runtime) Cook(c gascity.Cook) gascity.CookResult {
	r.mu.Lock()
	r.cooks = append(r.cooks, c)
	n := len(r.cooks)
	on := r.OnCook
	r.mu.Unlock()
	if on != nil {
		return on(c)
	}
	return gascity.CookResult{Root: fmt.Sprintf("cooked-%d", n)}
}

// Cooks returns each cook taken, in order.
func (r *Runtime) Cooks() []gascity.Cook {
	r.mu.Lock()
	defer r.mu.Unlock()
	return slices.Clone(r.cooks)
}

// DefaultFormula records s and answers from Formulas, else from PackFormulas
// when s names a bead.
func (r *Runtime) DefaultFormula(s gascity.Sling) (string, error) {
	r.mu.Lock()
	r.asks = append(r.asks, s)
	r.mu.Unlock()
	if r.ConfigErr != nil {
		return "", r.ConfigErr
	}
	if f, ok := r.Formulas[s.Target]; ok {
		return f, nil
	}
	f, ok := r.PackFormulas[s.Target]
	switch {
	case !ok:
		return "", fmt.Errorf("no agent in the city's config answers to %s", s.Target)
	case s.Bead == "":
		return "", fmt.Errorf("%s names no default formula of its own, and with no bead to name, gc sling --dry-run cannot say which its pack gives it", s.Target)
	}
	return f, nil
}

// Wake records the session's wake and answers it.
func (r *Runtime) Wake(session string) gascity.Result {
	r.mu.Lock()
	r.wakes = append(r.wakes, session)
	on := r.OnWake
	r.mu.Unlock()
	if on != nil {
		return on(session)
	}
	return gascity.Result{}
}

// Nudge records the nudge and answers it.
func (r *Runtime) Nudge(session, message string) gascity.Result {
	n := Nudge{Session: session, Message: message}
	r.mu.Lock()
	r.nudges = append(r.nudges, n)
	on := r.OnNudge
	r.mu.Unlock()
	if on != nil {
		return on(n)
	}
	return gascity.Result{}
}

// Wakes returns each session the domain woke, in order.
func (r *Runtime) Wakes() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return slices.Clone(r.wakes)
}

// Nudges returns each nudge the domain sent, in order.
func (r *Runtime) Nudges() []Nudge {
	r.mu.Lock()
	defer r.mu.Unlock()
	return slices.Clone(r.nudges)
}

// Script records the call and answers it.
func (r *Runtime) Script(name string, args ...string) gascity.Result {
	c := Call{Name: name, Args: slices.Clone(args)}
	r.mu.Lock()
	r.scripts = append(r.scripts, c)
	on := r.OnScript
	r.mu.Unlock()
	if on != nil {
		return on(c)
	}
	return gascity.Result{}
}

// CityRoot answers Root.
func (r *Runtime) CityRoot() (string, error) {
	if r.RootErr != nil {
		return "", r.RootErr
	}
	return r.Root, nil
}

// Slings returns every sling the domain made, in order.
func (r *Runtime) Slings() []gascity.Sling {
	r.mu.Lock()
	defer r.mu.Unlock()
	return slices.Clone(r.slings)
}

// Asks returns every sling the domain asked the default formula of, in order.
func (r *Runtime) Asks() []gascity.Sling {
	r.mu.Lock()
	defer r.mu.Unlock()
	return slices.Clone(r.asks)
}

// Scripts returns every script call the domain made, in order.
func (r *Runtime) Scripts() []Call {
	r.mu.Lock()
	defer r.mu.Unlock()
	return slices.Clone(r.scripts)
}
