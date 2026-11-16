package fake

import (
	"context"
	"slices"
	"sync"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
)

// Roster is the city's sessions, rigs and agents in memory, as gc lists them,
// safe for concurrent use. Each Err field fails its read when set.
type Roster struct {
	SessionList []gascity.Session
	RigList     []gascity.Rig
	AgentList   []gascity.Agent

	SessionsErr, RigsErr, AgentsErr error

	mu    sync.Mutex
	reads []string
}

// Sessions records the read and answers the session list.
func (r *Roster) Sessions(context.Context) ([]gascity.Session, error) {
	r.read("sessions")
	if r.SessionsErr != nil {
		return nil, r.SessionsErr
	}
	return slices.Clone(r.SessionList), nil
}

// Rigs records the read and answers the rig list.
func (r *Roster) Rigs(context.Context) ([]gascity.Rig, error) {
	r.read("rigs")
	if r.RigsErr != nil {
		return nil, r.RigsErr
	}
	return slices.Clone(r.RigList), nil
}

// Agents records the read and answers the agent list.
func (r *Roster) Agents(context.Context) ([]gascity.Agent, error) {
	r.read("agents")
	if r.AgentsErr != nil {
		return nil, r.AgentsErr
	}
	return slices.Clone(r.AgentList), nil
}

func (r *Roster) read(what string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.reads = append(r.reads, what)
}

// Reads returns each list read, by what it read, in order.
func (r *Roster) Reads() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return slices.Clone(r.reads)
}
