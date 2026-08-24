package server

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/closed"
	"github.com/zookanalytics/gc-toolkit/services/helm/internal/source"
)

// GET /helm/closed — what reached a disposition inside a window, and why.
//
// This is the board's missing half. Every anchor gather filters on status open,
// so a subject whose sitting concluded LEAVES the board and nothing afterwards
// says what was decided. See internal/closed for why the answer is per-visit,
// why it is pull-only, and why it writes nothing.
//
// NOT CACHED, unlike GET /helm. The board is one standing question re-asked on
// every glance, so a TTL is free; this is an explicit window, and a cached
// answer would be the previous `?since=` returned without saying so.

// handleClosed serves the closed-dispositions view.
//
// It answers 501 rather than 404 when the source cannot supply the view at all
// — under GC_HELM_SOURCE=supervisor the loopback API has neither metadata on
// its list endpoints nor a closed-after filter — so an operator who calls the
// route learns why instead of thinking it does not exist. That is the same
// degradation rule POST /helm/open follows for a missing visit tool.
func (s *Server) handleClosed(w http.ResponseWriter, r *http.Request) {
	cs, ok := s.src.(source.ClosedSource)
	if !ok {
		writeClosedError(w, http.StatusNotImplemented,
			"closed dispositions are unavailable under this source backend: it cannot select visits by metadata or bound a window server-side (try GC_HELM_SOURCE=beads)")
		return
	}

	sinceSpec := r.URL.Query().Get("since")
	if sinceSpec == "" {
		sinceSpec = defaultSinceSpec
	}
	since, err := closed.ParseSince(sinceSpec)
	if err != nil {
		// A bad window is a CLIENT error, and it must not be silently widened
		// to the default: an operator who asked for "2w" and got 24h back would
		// read a short list as a quiet fortnight.
		writeClosedError(w, http.StatusBadRequest, err.Error())
		return
	}

	limit, err := closedLimit(r.URL.Query().Get("limit"))
	if err != nil {
		writeClosedError(w, http.StatusBadRequest, err.Error())
		return
	}

	now := s.now().UTC()
	cutoff := now.Add(-since)
	rows, err := cs.GatherClosed(r.Context(), cutoff)
	if err != nil {
		// 502, never an empty list. On this surface "nothing was decided" and
		// "we could not look" are opposite answers, and only one of them means
		// the window was quiet.
		log.Printf("helm: closed gather failed: %v", err)
		writeClosedError(w, http.StatusBadGateway, "closed dispositions unavailable: "+err.Error())
		return
	}

	view := closed.Build(closed.Input{
		Rows:   rows,
		Now:    now,
		Since:  sinceSpec,
		Cutoff: cutoff,
		Limit:  limit,
	})
	w.Header().Set("Content-Type", "application/json")
	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(false) // matches handleBoard
	if err := enc.Encode(view); err != nil {
		log.Printf("helm: encode closed failed: %v", err)
	}
}

// defaultSinceSpec is the window an unparameterised request gets. It is the
// SPELLING rather than the duration so the response echoes back what the client
// effectively asked for.
const defaultSinceSpec = "24h"

// closedLimit parses ?limit=, where absent means the default cap and 0 means
// uncapped — the same two-valued convention `--limit` carries on both CLIs. A
// typo is refused rather than ignored: a silently-dropped limit renders a
// differently-sized list than the caller asked for, and this list's length is
// the answer.
func closedLimit(raw string) (int, error) {
	if raw == "" {
		return closed.DefaultMaxRows, nil
	}
	n, err := strconv.Atoi(raw)
	if err != nil || n < 0 {
		return 0, fmt.Errorf("limit must be a non-negative integer (got %q)", raw)
	}
	return n, nil
}

func writeClosedError(w http.ResponseWriter, code int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": msg})
}
