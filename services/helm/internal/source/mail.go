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

// MailCount counts the operator's mailbox through the supervisor's typed API,
// GET /v0/city/{city}/mail/count (humaHandleMailCount in
// internal/api/huma_handlers_mail.go at gastownhall/gascity bfe7a19cc2). Its
// total is the recipient's open messages, read or unread, the ones an archive
// has not closed (CountRecipients in internal/mail/beadmail/beadmail.go
// there). It is the city page's Mailbox (cityboard.Mailbox).
type MailCount struct {
	baseURL string
	city    string
	client  *http.Client
}

var _ cityboard.Mailbox = (*MailCount)(nil)

// operatorMailbox is the mailbox the page counts: Gas City's recipient for its
// alerts and its agents' escalations, which no session reads.
const operatorMailbox = "human"

// NewMailCount finds the supervisor and the city the way NewSupervisorSource
// does. Its client sets no time limit of its own, so the caller's context
// bounds each read.
func NewMailCount() *MailCount {
	return &MailCount{baseURL: discoverBaseURL(), city: discoverCity(), client: &http.Client{}}
}

// Count is how many messages wait in the operator's mailbox. Across the
// city's stores the route counts what each store answers, and names each one
// that did not; the count then comes with those names, as what it may miss.
func (m *MailCount) Count(ctx context.Context) (int, string, error) {
	if m.city == "" {
		return 0, "", errors.New("no city to count the mail of: GC_HELM_CITY, GC_SERVICE_URL_PREFIX, GC_CITY_PATH and GC_CITY name none")
	}
	q := url.Values{"agent": {operatorMailbox}}
	full := m.baseURL + "/v0/city/" + url.PathEscape(m.city) + "/mail/count?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, full, nil)
	if err != nil {
		return 0, "", err
	}
	resp, err := m.client.Do(req)
	if err != nil {
		return 0, "", fmt.Errorf("the supervisor's mail count did not answer: %w", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxMailCountAnswer))
	if err != nil {
		return 0, "", fmt.Errorf("the supervisor's mail count answer did not read: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return 0, "", fmt.Errorf("the supervisor's mail count answered HTTP %d%s", resp.StatusCode, problemDetail(body))
	}
	var c struct {
		Total         *int     `json:"total"`
		Partial       bool     `json:"partial"`
		PartialErrors []string `json:"partial_errors"`
	}
	if err := json.Unmarshal(body, &c); err != nil {
		return 0, "", fmt.Errorf("the supervisor's mail count answered no count: %w", err)
	}
	if c.Total == nil {
		return 0, "", errors.New("the supervisor's mail count answered no count: the answer holds no total")
	}
	short := ""
	if c.Partial {
		short = strings.Join(c.PartialErrors, "; ")
		if short == "" {
			short = "a store did not answer"
		}
	}
	return *c.Total, short, nil
}

// maxMailCountAnswer bounds the answer Count reads, a few numbers and the
// errors of the stores that did not answer.
const maxMailCountAnswer = 64 << 10
