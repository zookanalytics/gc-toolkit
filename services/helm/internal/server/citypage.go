package server

import (
	"context"
	"log"
	"net/http"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/cityboard"
)

// The city page's route: GET /helm/city answers the city's document, what
// doctor's newest recorded run found (internal/cityboard). The answer is
// cached whole for its time to live, with one read at a time however many
// requests wait on it, by the cache the rig board keeps. The board's write
// routes change no doctor run, so a write leaves it cached.

// CityPageTTL is how long the city's document is served before the next read
// reads the event log again. The newest doctor run changes once an hour, so
// the page shows a new run within five minutes of its record.
const CityPageTTL = 5 * time.Minute

// cityPage is the city page's read and its cache.
type cityPage struct {
	log  cityboard.Log
	docs *keyedCache[cityboard.Response]
}

// WithCityPage enables the city page's route, reading doctor's runs from log.
// A nil log leaves the route answering 503.
func WithCityPage(log cityboard.Log, ttl time.Duration) Option {
	return func(s *Server) {
		if log == nil {
			return
		}
		now := func() time.Time { return s.now() }
		s.cityPage = &cityPage{log: log, docs: newKeyedCache[cityboard.Response](ttl, now)}
	}
}

func (s *Server) handleCity(w http.ResponseWriter, r *http.Request) {
	cp := s.cityPage
	if cp == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "the city page is not enabled in this service")
		return
	}
	resp, err := cp.docs.get(r.Context(), "", func(ctx context.Context) (cityboard.Response, error) {
		doc, err := cityboard.Read(ctx, cp.log, s.now())
		if err != nil {
			return cityboard.Response{}, err
		}
		return cityboard.Response{ReadAt: s.now().UTC().Format(time.RFC3339), City: doc}, nil
	})
	if err != nil {
		log.Printf("helm: city page read failed: %v", err)
		writeJSONError(w, http.StatusBadGateway, "the city page could not be read: "+err.Error())
		return
	}
	writeJSON(w, http.StatusOK, resp)
}
