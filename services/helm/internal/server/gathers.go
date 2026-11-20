package server

import (
	"context"
	"errors"
	"sync"
	"time"
)

// gatherTimeout bounds one gather. A healthy gather is a few seconds; this is
// generous slack that still cuts off a supervisor that has begun timing out
// every call, so a coalesced flight cannot run unbounded.
const gatherTimeout = 30 * time.Second

// ErrStopping is the failure of a gather the server's stop ended, and of one
// asked for after it.
var ErrStopping = errors.New("the board is stopping")

// gathers is every gather the server has in flight, and the stop that ends
// them. A rig's store read runs in a process group of its own, out of reach of
// a signal sent to this process's group, and kills that group only when its
// context ends (rigboard.Read). So the process ends its reads itself: the stop
// ends every gather's context and waits for each gather to return, which a
// read does only once the processes it started are killed.
type gathers struct {
	// stopping ends at the stop, with ErrStopping as its cause. mu orders each
	// gather's start against it, so a gather either starts before the stop,
	// and the stop waits for it, or is refused.
	stopping context.Context
	stop     context.CancelCauseFunc
	mu       sync.Mutex
	running  sync.WaitGroup
}

func newGathers() *gathers {
	ctx, cancel := context.WithCancelCause(context.Background())
	return &gathers{stopping: ctx, stop: cancel}
}

// start begins one gather and returns the context it runs on, and done, which
// its caller calls once the gather has returned. The context drops ctx's
// cancellation, so one client leaving does not end a gather other requests
// wait on, and it ends at gatherTimeout or at the server's stop. After the
// stop, start begins nothing and returns ErrStopping.
func (g *gathers) start(ctx context.Context) (context.Context, func(), error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	if g.stopping.Err() != nil {
		return nil, nil, ErrStopping
	}
	g.running.Add(1)
	gctx, cancel := context.WithCancelCause(context.WithoutCancel(ctx))
	unhook := context.AfterFunc(g.stopping, func() { cancel(ErrStopping) })
	gctx, cancelTimeout := context.WithTimeout(gctx, gatherTimeout)
	return gctx, func() {
		unhook()
		cancelTimeout()
		cancel(nil)
		g.running.Done()
	}, nil
}

// halt ends every gather in flight and returns once each has returned.
func (g *gathers) halt() {
	g.mu.Lock()
	g.stop(ErrStopping)
	g.mu.Unlock()
	g.running.Wait()
}

// StopGathers ends every gather in flight and returns once each has returned,
// so a process that calls it before it exits leaves no store read running. A
// request waiting on a gather it ends answers that the board is stopping, and
// a gather asked for after it fails at once with ErrStopping.
func (s *Server) StopGathers() { s.gathers.halt() }
