package source

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// mailCountAt is a MailCount that reads the server srv answers for city.
func mailCountAt(srv *httptest.Server, city string) *MailCount {
	return &MailCount{baseURL: srv.URL, city: city, client: srv.Client()}
}

// Count asks the route for the operator's mailbox and answers its total, the
// open messages read or unread, with nothing short when every store answered.
func TestCountAsksForTheOperatorsMailbox(t *testing.T) {
	var asked string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		asked = r.URL.Path + "?" + r.URL.RawQuery
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"total":130,"unread":121}`))
	}))
	defer srv.Close()
	n, short, err := mailCountAt(srv, "town").Count(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if asked != "/v0/city/town/mail/count?agent=human" {
		t.Errorf("asked %s", asked)
	}
	if n != 130 || short != "" {
		t.Errorf("Count = %d, %q; want 130 and nothing short", n, short)
	}
}

// A count some stores did not answer for is the count of those that did,
// with what it may miss.
func TestAPartialCountSaysWhatItMayMiss(t *testing.T) {
	for _, tc := range []struct{ body, want string }{
		{`{"total":4,"unread":4,"partial":true,"partial_errors":["mail provider docs: store_slow: read timed out"]}`, "mail provider docs: store_slow: read timed out"},
		{`{"total":4,"unread":4,"partial":true}`, "a store did not answer"},
	} {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			_, _ = w.Write([]byte(tc.body))
		}))
		n, short, err := mailCountAt(srv, "town").Count(context.Background())
		srv.Close()
		if err != nil || n != 4 || short != tc.want {
			t.Errorf("Count of %s = %d, %q, %v; want 4 and %q", tc.body, n, short, err, tc.want)
		}
	}
}

// A refusal names its status and the supervisor's detail, and an answer that
// holds no total is an error, never an empty mailbox.
func TestCountFailsLoudly(t *testing.T) {
	for _, tc := range []struct {
		name   string
		status int
		body   string
		want   string
	}{
		{"a refusal", http.StatusServiceUnavailable, `{"title":"Service Unavailable","status":503,"detail":"all mail providers failed: mail provider town: read timed out"}`, "answered HTTP 503: all mail providers failed: mail provider town: read timed out"},
		{"a proxy's page", http.StatusBadGateway, `<html>bad gateway</html>`, "answered HTTP 502"},
		{"no count", http.StatusOK, `<html>hello</html>`, "answered no count"},
		{"an object with no total", http.StatusOK, `{"unread":3}`, "answered no count"},
	} {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(tc.status)
			_, _ = w.Write([]byte(tc.body))
		}))
		n, _, err := mailCountAt(srv, "town").Count(context.Background())
		srv.Close()
		if err == nil || n != 0 || !strings.Contains(err.Error(), tc.want) {
			t.Errorf("%s: Count = %d, %v; want an error naming %q", tc.name, n, err, tc.want)
		}
	}
}

// With no city named, Count reads nothing and says why.
func TestCountNeedsACity(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Error("a count with no city asked the supervisor")
	}))
	defer srv.Close()
	if _, _, err := mailCountAt(srv, "").Count(context.Background()); err == nil || !strings.Contains(err.Error(), "no city") {
		t.Fatalf("err = %v", err)
	}
}
