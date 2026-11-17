package source

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// eventLogAt is an EventLog that reads the server srv answers for city.
func eventLogAt(srv *httptest.Server, city string) *EventLog {
	return &EventLog{baseURL: srv.URL, city: city, client: srv.Client()}
}

// Newest asks the route for the newest event of one type alone, with no
// window, and answers the first item it returns.
func TestNewestAsksForTheNewestEventOfAType(t *testing.T) {
	var asked string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		asked = r.URL.Path + "?" + r.URL.RawQuery
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"items":[{"seq":7,"type":"gc-toolkit.doctor.ran","ts":"2026-11-16T15:24:24.754008-07:00","actor":"gctk","message":"doctor ran","payload":{"started":"2026-11-16T22:21:54Z"}}],"total":1,"next_cursor":"v1:x"}`))
	}))
	defer srv.Close()
	e, err := eventLogAt(srv, "town").Newest(context.Background(), "gc-toolkit.doctor.ran")
	if err != nil {
		t.Fatal(err)
	}
	if asked != "/v0/city/town/events?limit=1&type=gc-toolkit.doctor.ran" {
		t.Errorf("asked %s", asked)
	}
	if e == nil || e.Seq != 7 || e.Actor != "gctk" || string(e.Payload) != `{"started":"2026-11-16T22:21:54Z"}` || e.Ts.UTC().Format("15:04:05") != "22:24:24" {
		t.Errorf("event = %+v", e)
	}
}

// A log that holds no event of the type answers nil and no error.
func TestNewestOfNoEventIsNil(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"items":[],"total":0}`))
	}))
	defer srv.Close()
	e, err := eventLogAt(srv, "town").Newest(context.Background(), "gc-toolkit.doctor.ran")
	if err != nil || e != nil {
		t.Fatalf("Newest = %+v, %v", e, err)
	}
}

// A refusal names its status and the supervisor's detail, and an answer that
// is no event list is an error, never an empty log.
func TestNewestFailsLoudly(t *testing.T) {
	for _, tc := range []struct {
		name   string
		status int
		body   string
		want   string
	}{
		{"a refusal", http.StatusNotFound, `{"type":"urn:gascity:error:city-not-found","title":"City Not Found","status":404,"detail":"not_found: city not found or not running: town"}`, "answered HTTP 404: not_found: city not found or not running: town"},
		{"a proxy's page", http.StatusBadGateway, `<html>bad gateway</html>`, "answered HTTP 502"},
		{"no list", http.StatusOK, `<html>hello</html>`, "answered no event list"},
	} {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(tc.status)
			_, _ = w.Write([]byte(tc.body))
		}))
		e, err := eventLogAt(srv, "town").Newest(context.Background(), "gc-toolkit.doctor.ran")
		srv.Close()
		if err == nil || e != nil || !strings.Contains(err.Error(), tc.want) {
			t.Errorf("%s: Newest = %+v, %v; want an error naming %q", tc.name, e, err, tc.want)
		}
	}
}

// With no city named, Newest reads nothing and says why.
func TestNewestNeedsACity(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Error("a log with no city asked the supervisor")
	}))
	defer srv.Close()
	if _, err := eventLogAt(srv, "").Newest(context.Background(), "x"); err == nil || !strings.Contains(err.Error(), "no city") {
		t.Fatalf("err = %v", err)
	}
}
