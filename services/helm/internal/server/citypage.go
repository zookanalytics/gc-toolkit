package server

import (
	"context"
	"log"
	"net/http"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/cityboard"
)

// The city page's route: GET /helm/city answers the city's document, what
// doctor's newest recorded run found and how many messages wait in the
// operator's mailbox (internal/cityboard). Each part is cached for its own
// time to live, with one read at a time however many requests wait on it, by
// the cache the rig board keeps. The board's write routes change no doctor
// run and no mail, so a write leaves both cached.

// CityPageTTL is how long the city's document is served before the next read
// reads the event log again. The newest doctor run changes once an hour. An
// open page shows a new run at most this long plus its read interval
// (CITY_REFRESH_MS in web/src/cityboard/CityPage.tsx) after its record.
const CityPageTTL = 5 * time.Minute

// CityMailTTL is how long the mailbox's count is served before the next read
// counts it again, so however many pages are open, the mailbox is counted at
// most once a minute.
const CityMailTTL = time.Minute

// cityPage is the city page's reads and their caches.
type cityPage struct {
	log  cityboard.Log
	docs *keyedCache[cityboard.Response]
	box  cityboard.Mailbox
	mail *keyedCache[cityboard.Mail]
}

// WithCityPage enables the city page's route, reading doctor's runs from log,
// cached for ttl, and the operator's mailbox from box, cached for CityMailTTL.
// A nil log leaves the route answering 503, and a nil box leaves the page
// saying it counts no mail.
func WithCityPage(log cityboard.Log, box cityboard.Mailbox, ttl time.Duration) Option {
	return func(s *Server) {
		if log == nil {
			return
		}
		now := func() time.Time { return s.now() }
		s.cityPage = &cityPage{log: log, docs: newKeyedCache[cityboard.Response](ttl, now),
			box: box, mail: newKeyedCache[cityboard.Mail](CityMailTTL, now)}
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
	resp.City.Mail = cp.count(r.Context())
	writeJSON(w, http.StatusOK, resp)
}

// count is the operator's mailbox as the page counts it, from its own cache.
// Its read always answers, a count that did not read with why, so the cache
// keeps a failure too and a failing mailbox is asked again only once its
// answer is a minute old.
func (cp *cityPage) count(ctx context.Context) cityboard.Mail {
	if cp.box == nil {
		return cityboard.Mail{Why: "this service counts no mail"}
	}
	m, err := cp.mail.get(ctx, "", func(ctx context.Context) (cityboard.Mail, error) {
		return cityboard.ReadMail(ctx, cp.box), nil
	})
	if err != nil {
		return cityboard.Mail{Why: err.Error()}
	}
	return m
}
