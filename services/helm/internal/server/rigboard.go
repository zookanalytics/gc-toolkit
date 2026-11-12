package server

import (
	"context"
	"errors"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/rigboard"
	"golang.org/x/sync/singleflight"
)

// The rig board's routes: GET /helm/rigs lists the city's rigs, and
// GET /helm/rigs/{rig} answers one rig's document. Each answer is cached whole
// by the same rule the board's cache keeps: a time to live, one gather of a
// key at a time, and every key dropped when a write route succeeds, since a
// write changes what the store answers. The drop also lets the next request
// gather beside a gather that began before the write, whose answer stays out
// of the cache.

// RigBoardTTL is how long one rig's document is served before the next read
// gathers again. One read of the gc-toolkit rig, the city's largest store,
// measured 2.9 s, so a minute keeps the read under a tenth of the time while a
// page is open.
const RigBoardTTL = 60 * time.Second

// errNoRig answers a rig the city does not list.
var errNoRig = errors.New("the city lists no such rig")

// rigBoard is the rig board's reads and their cache: gc lists the rigs, and
// read reads one rig's store and builds its document.
type rigBoard struct {
	gc   rigboard.GC
	read func(ctx context.Context, rig rigboard.Rig) (rigboard.Document, error)
	rigs *keyedCache[rigList]
	docs *keyedCache[rigboard.Response]
}

// rigList is the city's rigs as one read gave them, and when.
type rigList struct {
	readAt string
	rigs   []rigboard.Rig
}

// rigList answers the city's rigs from the cache while it is fresh.
func (s *Server) rigList(ctx context.Context) (rigList, error) {
	rb := s.rigBoard
	return rb.rigs.get(ctx, "", func(ctx context.Context) (rigList, error) {
		list, err := rigboard.ReadRigs(ctx, rb.gc)
		if err != nil {
			return rigList{}, err
		}
		return rigList{readAt: s.now().UTC().Format(time.RFC3339), rigs: list}, nil
	})
}

// WithRigBoard enables the rig board's routes, listing the city's rigs
// through gc and reading each rig's store through gctk's listing. A nil gc
// leaves them answering 503.
func WithRigBoard(gc rigboard.GC, ttl time.Duration) Option {
	return func(s *Server) {
		if gc == nil {
			return
		}
		now := func() time.Time { return s.now() }
		s.rigBoard = &rigBoard{gc: gc, read: rigboard.Read,
			rigs: newKeyedCache[rigList](ttl, now), docs: newKeyedCache[rigboard.Response](ttl, now)}
	}
}

func (s *Server) handleRigs(w http.ResponseWriter, r *http.Request) {
	rb := s.rigBoard
	if rb == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "the rig board is not enabled in this service")
		return
	}
	list, err := s.rigList(r.Context())
	if err != nil {
		log.Printf("helm: rig list failed: %v", err)
		writeJSONError(w, http.StatusBadGateway, "the rig list could not be read: "+err.Error())
		return
	}
	out := rigboard.Rigs{ReadAt: list.readAt, Rigs: []string{}}
	for _, rig := range list.rigs {
		out.Rigs = append(out.Rigs, rig.Name)
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) handleRig(w http.ResponseWriter, r *http.Request) {
	rb := s.rigBoard
	if rb == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "the rig board is not enabled in this service")
		return
	}
	name := r.PathValue("rig")
	doc, err := rb.docs.get(r.Context(), name, func(ctx context.Context) (rigboard.Response, error) {
		list, err := s.rigList(ctx)
		if err != nil {
			return rigboard.Response{}, err
		}
		for _, rig := range list.rigs {
			if rig.Name == name {
				board, err := rb.read(ctx, rig)
				if err != nil {
					return rigboard.Response{}, err
				}
				return rigboard.Response{ReadAt: s.now().UTC().Format(time.RFC3339), Board: board}, nil
			}
		}
		return rigboard.Response{}, errNoRig
	})
	switch {
	case errors.Is(err, errNoRig):
		writeJSONError(w, http.StatusNotFound, name+": "+err.Error())
	case err != nil:
		log.Printf("helm: rig %s read failed: %v", name, err)
		writeJSONError(w, http.StatusBadGateway, "the "+name+" board could not be read: "+err.Error())
	default:
		writeJSON(w, http.StatusOK, doc)
	}
}

func writeJSONError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

// keyedCache holds one answer per key for a time to live. A miss gathers once
// however many requests wait on it, outside the lock, and an invalidate that
// lands during a gather keeps that gather's answer out of the cache, so a
// write is never undone by a read that began before it.
type keyedCache[T any] struct {
	ttl     time.Duration
	now     func() time.Time
	mu      sync.Mutex
	entries map[string]cached[T]
	// asked is every key a read has asked for, so an invalidate can forget a
	// gather in flight for a key that holds no answer yet.
	asked  map[string]bool
	gen    uint64
	flight singleflight.Group
}

type cached[T any] struct {
	value  T
	expiry time.Time
}

func newKeyedCache[T any](ttl time.Duration, now func() time.Time) *keyedCache[T] {
	return &keyedCache[T]{ttl: ttl, now: now, entries: map[string]cached[T]{}, asked: map[string]bool{}}
}

func (c *keyedCache[T]) fresh(key string) (T, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	e, ok := c.entries[key]
	if ok && c.ttl > 0 && c.now().Before(e.expiry) {
		return e.value, true
	}
	var zero T
	return zero, false
}

// get answers key from the cache while it is fresh, and otherwise gathers it.
// The gather runs on a context detached from the request's, so one client
// leaving does not cancel the gather the others wait on, and gatherTimeout
// bounds it. A rig's read stops its store calls when that bound runs out
// (rigboard.Read), so a gather that has returned leaves none running.
func (c *keyedCache[T]) get(ctx context.Context, key string, gather func(context.Context) (T, error)) (T, error) {
	if v, ok := c.fresh(key); ok {
		return v, nil
	}
	c.mu.Lock()
	c.asked[key] = true
	c.mu.Unlock()
	v, err, _ := c.flight.Do(key, func() (any, error) {
		if v, ok := c.fresh(key); ok {
			return v, nil
		}
		c.mu.Lock()
		startGen := c.gen
		c.mu.Unlock()
		gctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), gatherTimeout)
		defer cancel()
		v, err := gather(gctx)
		if err != nil {
			return v, err
		}
		c.mu.Lock()
		defer c.mu.Unlock()
		if c.gen == startGen {
			c.entries[key] = cached[T]{value: v, expiry: c.now().Add(c.ttl)}
		}
		return v, nil
	})
	if err != nil {
		var zero T
		return zero, err
	}
	return v.(T), nil
}

// invalidate drops every key, and forgets each gather in flight, so a read
// that arrives after a write gathers again.
func (c *keyedCache[T]) invalidate() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.entries = map[string]cached[T]{}
	c.gen++
	for k := range c.asked {
		c.flight.Forget(k)
	}
}
