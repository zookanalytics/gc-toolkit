// Package fake is the runtime adapter's fake: it records each sling and script
// call a domain makes and answers as its test says, so a domain's rules about
// Gas City are tested in Go with no Gas City (docs/gctk-architecture.md, "The
// adapters").
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
	// Formulas is each target's default formula. A target it does not name has
	// no agent in the config, and ConfigErr fails every read of it.
	Formulas  map[string]string
	ConfigErr error
	// Root is the city's root, and RootErr fails the read of it.
	Root    string
	RootErr error
	// OnSling answers a sling, and nil answers exit 0. OnScript answers a script
	// call, and nil answers exit 0.
	OnSling  func(gascity.Sling) gascity.SlingResult
	OnScript func(Call) gascity.Result

	mu      sync.Mutex
	slings  []gascity.Sling
	scripts []Call
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

// DefaultFormula answers from Formulas.
func (r *Runtime) DefaultFormula(target string) (string, error) {
	if r.ConfigErr != nil {
		return "", r.ConfigErr
	}
	f, ok := r.Formulas[target]
	if !ok {
		return "", fmt.Errorf("no agent in the city's config answers to %s", target)
	}
	return f, nil
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

// Scripts returns every script call the domain made, in order.
func (r *Runtime) Scripts() []Call {
	r.mu.Lock()
	defer r.mu.Unlock()
	return slices.Clone(r.scripts)
}
