package source

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/cityboard"
)

// EventLog reads the city's event log through the supervisor's typed API,
// GET /v0/city/{city}/events. It is the city page's Log (cityboard.Log).
type EventLog struct {
	baseURL string
	city    string
	client  *http.Client
}

var _ cityboard.Log = (*EventLog)(nil)

// NewEventLog finds the supervisor and the city the way NewSupervisorSource
// does. Its client sets no time limit of its own, so the caller's context
// bounds each read: a read that finds no recent match scans the log's
// archives, which takes seconds on a long log (fetchEventPageAscending in
// internal/api/huma_handlers_events.go at gastownhall/gascity 5f7cd988a6).
func NewEventLog() *EventLog {
	return &EventLog{baseURL: discoverBaseURL(), city: discoverCity(), client: &http.Client{}}
}

// Newest is the newest event of type typ in the city's log, nil when the log
// holds none. The route answers the newest match first and limit=1 asks for it
// alone (humaHandleEventList there). The read names no since, so it finds the
// newest event however long ago it was recorded. The route's answer always
// holds an items list, an empty one when no event matches, so an answer with
// none is a failed read, never an empty log.
func (l *EventLog) Newest(ctx context.Context, typ string) (*cityboard.Event, error) {
	if l.city == "" {
		return nil, errors.New("no city to read the event log of: GC_HELM_CITY, GC_SERVICE_URL_PREFIX, GC_CITY_PATH and GC_CITY name none")
	}
	q := url.Values{"type": {typ}, "limit": {"1"}}
	full := l.baseURL + "/v0/city/" + url.PathEscape(l.city) + "/events?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, full, nil)
	if err != nil {
		return nil, err
	}
	resp, err := l.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("the supervisor's event log did not answer: %w", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxEventAnswer))
	if err != nil {
		return nil, fmt.Errorf("the supervisor's event log answer did not read: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("the supervisor's event log answered HTTP %d%s", resp.StatusCode, problemDetail(body))
	}
	var env struct {
		Items *[]cityboard.Event `json:"items"`
	}
	if err := json.Unmarshal(body, &env); err != nil {
		return nil, fmt.Errorf("the supervisor's event log answered no event list: %w", err)
	}
	if env.Items == nil {
		return nil, errors.New("the supervisor's event log answered no event list: the answer holds no items")
	}
	if len(*env.Items) == 0 {
		return nil, nil
	}
	return &(*env.Items)[0], nil
}

// maxEventAnswer bounds the answer Newest reads. One event is a few kilobytes,
// and Gas City's event readers take lines of up to a megabyte
// (internal/events/reader.go at gastownhall/gascity 5f7cd988a6).
const maxEventAnswer = 2 << 20

// problemDetail is the detail of the supervisor's problem answer, which names
// why it refused, as ": <detail>", or "" when the body carries none.
func problemDetail(body []byte) string {
	var p struct {
		Detail string `json:"detail"`
	}
	if json.Unmarshal(body, &p) != nil || strings.TrimSpace(p.Detail) == "" {
		return ""
	}
	return ": " + strings.TrimSpace(p.Detail)
}
