package source

import (
	"context"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

// TestSupervisorAPIReadsBelowTheCity holds the rig board's supervisor reader
// to the API's answers: a body decoded below the city's path, with the query
// encoded, a 404 as not found, any other failure as an error naming the API's
// detail, and a city it cannot name as an error before any request.
func TestSupervisorAPIReadsBelowTheCity(t *testing.T) {
	var got []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got = append(got, r.URL.RequestURI())
		switch r.URL.Path {
		case "/v0/city/mycity/orders/history":
			_, _ = w.Write([]byte(`{"entries":[{"created_at":"2026-11-16T17:00:00Z","labels":["exec"]}]}`))
		case "/v0/city/mycity/order/pr-poll:rig:gone":
			w.WriteHeader(http.StatusNotFound)
			_, _ = w.Write([]byte(`{"status":404,"detail":"order not found: pr-poll:rig:gone","code":"order-not-found"}`))
		case "/v0/city/mycity/order/pr-poll:rig:busy":
			w.WriteHeader(http.StatusServiceUnavailable)
			_, _ = w.Write([]byte(`{"status":503,"detail":"cache not live"}`))
		default:
			w.WriteHeader(http.StatusInternalServerError)
		}
	}))
	defer srv.Close()
	api := &SupervisorAPI{baseURL: srv.URL, city: "mycity", client: srv.Client()}
	ctx := context.Background()

	var history struct {
		Entries []struct {
			CreatedAt string   `json:"created_at"`
			Labels    []string `json:"labels"`
		} `json:"entries"`
	}
	found, err := api.JSON(ctx, &history, "/orders/history", url.Values{"scoped_name": {"pr-poll:rig:gc-toolkit"}, "limit": {"50"}})
	if err != nil || !found || len(history.Entries) != 1 || history.Entries[0].Labels[0] != "exec" {
		t.Fatalf("the history read = %v, %v, %+v", found, err, history)
	}
	if want := "/v0/city/mycity/orders/history?limit=50&scoped_name=pr-poll%3Arig%3Agc-toolkit"; got[0] != want {
		t.Errorf("asked %s, want %s", got[0], want)
	}

	var order struct{}
	if found, err := api.JSON(ctx, &order, "/order/"+url.PathEscape("pr-poll:rig:gone"), nil); found || err != nil {
		t.Errorf("a 404 = %v, %v, want not found and no error", found, err)
	}
	if _, err := api.JSON(ctx, &order, "/order/"+url.PathEscape("pr-poll:rig:busy"), nil); err == nil ||
		err.Error() != "GET /order/pr-poll:rig:busy: status 503: cache not live" {
		t.Errorf("a 503 = %v, want an error naming the detail", err)
	}
	if _, err := api.JSON(ctx, &order, "/elsewhere", nil); err == nil || err.Error() != "GET /elsewhere: status 500" {
		t.Errorf("a 500 with no body = %v, want an error naming the status", err)
	}

	asked := len(got)
	cityless := &SupervisorAPI{baseURL: srv.URL, client: srv.Client()}
	if _, err := cityless.JSON(ctx, &order, "/orders/history", nil); err == nil || !strings.Contains(err.Error(), "GC_HELM_CITY") {
		t.Errorf("no city = %v, want an error naming GC_HELM_CITY", err)
	}
	if len(got) != asked {
		t.Errorf("a reader with no city sent %d requests, want none", len(got)-asked)
	}
}
