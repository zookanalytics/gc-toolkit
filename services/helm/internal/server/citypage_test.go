package server

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/cityboard"
)

// cityLog stands in for the city's event log: doctor's newest run, started at
// started, or its failure, and the count of reads.
type cityLog struct {
	mu      sync.Mutex
	reads   int
	started time.Time
	fail    error
}

func (l *cityLog) Newest(_ context.Context, typ string) (*cityboard.Event, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.reads++
	if l.fail != nil {
		return nil, l.fail
	}
	payload := `{"started":"` + l.started.Format(time.RFC3339) + `","completed":true,"failing":[{"name":"orphan-sessions","status":"warning","severity":"blocking","message":"18 orphaned session(s)","first_failed":"2026-11-16T22:18:18Z","streak":2}],"not_measured":[],"accepted":[],"monitors":[]}`
	return &cityboard.Event{Seq: 1, Type: typ, Payload: json.RawMessage(payload)}, nil
}

// cityMail stands in for the operator's mailbox: the count it answers, what it
// may miss, or its failure, and the count of reads.
type cityMail struct {
	mu      sync.Mutex
	reads   int
	waiting int
	short   string
	fail    error
}

func (m *cityMail) Count(context.Context) (int, string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.reads++
	if m.fail != nil {
		return 0, "", m.fail
	}
	return m.waiting, m.short, nil
}

func TestCityPageRoute(t *testing.T) {
	now := time.Date(2026, 11, 17, 1, 0, 0, 0, time.UTC)
	l := &cityLog{started: now.Add(-3 * time.Hour)}
	s := New(newFake(), time.Minute, WithCityPage(l, &cityMail{waiting: 130}, CityPageTTL))
	s.now = func() time.Time { return now }
	rr := get(t, s, "/helm/city")
	var resp cityboard.Response
	if rr.Code != http.StatusOK || json.Unmarshal(rr.Body.Bytes(), &resp) != nil {
		t.Fatalf("GET /helm/city = %d %s", rr.Code, rr.Body.String())
	}
	d := resp.City.Doctor
	if resp.ReadAt != "2026-11-17T01:00:00Z" || !d.Ran || !d.Late || d.Count != 1 || d.Failing[0].Name != "orphan-sessions" {
		t.Errorf("document = %+v", resp)
	}
	if m := resp.City.Mail; m != (cityboard.Mail{Counted: true, Waiting: 130}) {
		t.Errorf("mail = %+v, want 130 counted", m)
	}
}

// TestCityPageCaches holds the document to its time to live: one read serves
// every request inside it, a write route's success leaves it, and the first
// request past it reads again.
func TestCityPageCaches(t *testing.T) {
	now := time.Date(2026, 11, 17, 1, 0, 0, 0, time.UTC)
	l := &cityLog{started: now}
	s := New(newFake(), time.Minute, WithCityPage(l, &cityMail{}, CityPageTTL))
	s.now = func() time.Time { return now }
	for range 3 {
		if rr := get(t, s, "/helm/city"); rr.Code != http.StatusOK {
			t.Fatalf("status %d", rr.Code)
		}
	}
	s.invalidateBoard()
	s.now = func() time.Time { return now.Add(CityPageTTL - time.Second) }
	get(t, s, "/helm/city")
	if l.reads != 1 {
		t.Fatalf("four requests inside the time to live read %d times, want once", l.reads)
	}
	s.now = func() time.Time { return now.Add(CityPageTTL + time.Second) }
	get(t, s, "/helm/city")
	if l.reads != 2 {
		t.Fatalf("a request past the time to live read %d times in all, want twice", l.reads)
	}
}

// TestCityPageSaysAFailedRead holds a failed read to an error naming it, never
// a document drawn from nothing.
func TestCityPageSaysAFailedRead(t *testing.T) {
	s := New(newFake(), time.Minute, WithCityPage(&cityLog{fail: errors.New("the supervisor did not answer")}, &cityMail{}, CityPageTTL))
	rr := get(t, s, "/helm/city")
	if rr.Code != http.StatusBadGateway || !strings.Contains(rr.Body.String(), "the supervisor did not answer") {
		t.Fatalf("a failed read = %d %s, want 502 naming the failure", rr.Code, rr.Body.String())
	}
	if strings.Contains(rr.Body.String(), `"city"`) {
		t.Errorf("a failed read carried a document: %s", rr.Body.String())
	}
}

func TestCityPageOff(t *testing.T) {
	s := New(newFake(), time.Minute)
	if rr := get(t, s, "/helm/city"); rr.Code != http.StatusServiceUnavailable {
		t.Errorf("without the city page = %d, want 503", rr.Code)
	}
}

// TestCityPageCountsTheMailAtMostOnceAMinute holds the mailbox's count to its
// own time to live: one count serves every request inside a minute, and the
// first request past it counts again while the doctor document stays cached.
func TestCityPageCountsTheMailAtMostOnceAMinute(t *testing.T) {
	now := time.Date(2026, 11, 17, 1, 0, 0, 0, time.UTC)
	l, box := &cityLog{started: now}, &cityMail{waiting: 7}
	s := New(newFake(), time.Minute, WithCityPage(l, box, CityPageTTL))
	s.now = func() time.Time { return now }
	for range 3 {
		get(t, s, "/helm/city")
	}
	s.now = func() time.Time { return now.Add(CityMailTTL - time.Second) }
	get(t, s, "/helm/city")
	if box.reads != 1 {
		t.Fatalf("four requests inside a minute counted %d times, want once", box.reads)
	}
	box.waiting = 3
	s.now = func() time.Time { return now.Add(CityMailTTL + time.Second) }
	rr := get(t, s, "/helm/city")
	var resp cityboard.Response
	if json.Unmarshal(rr.Body.Bytes(), &resp) != nil || box.reads != 2 || resp.City.Mail.Waiting != 3 {
		t.Fatalf("a request past the minute: %d counts, mail %+v; want a second count of 3", box.reads, resp.City.Mail)
	}
	if l.reads != 1 {
		t.Fatalf("the doctor document was read %d times, want once inside its own time to live", l.reads)
	}
}

// TestCityPageSaysACountThatDidNotRead answers the document with no number and
// the reason, and keeps that answer for its minute too, so a failing mailbox is
// asked no more often than a healthy one.
func TestCityPageSaysACountThatDidNotRead(t *testing.T) {
	now := time.Date(2026, 11, 17, 1, 0, 0, 0, time.UTC)
	box := &cityMail{fail: errors.New("the supervisor's mail count answered HTTP 503")}
	s := New(newFake(), time.Minute, WithCityPage(&cityLog{started: now}, box, CityPageTTL))
	s.now = func() time.Time { return now }
	for range 2 {
		rr := get(t, s, "/helm/city")
		var resp cityboard.Response
		if rr.Code != http.StatusOK || json.Unmarshal(rr.Body.Bytes(), &resp) != nil {
			t.Fatalf("GET /helm/city = %d %s", rr.Code, rr.Body.String())
		}
		if m := resp.City.Mail; m.Counted || m.Why != "the supervisor's mail count answered HTTP 503" || !resp.City.Doctor.Ran {
			t.Fatalf("a count that did not read: mail %+v, doctor ran %v", m, resp.City.Doctor.Ran)
		}
	}
	if box.reads != 1 {
		t.Fatalf("a failing mailbox was counted %d times inside a minute, want once", box.reads)
	}
}

// A service with no mailbox to count says so in place of a number.
func TestCityPageWithNoMailbox(t *testing.T) {
	now := time.Date(2026, 11, 17, 1, 0, 0, 0, time.UTC)
	s := New(newFake(), time.Minute, WithCityPage(&cityLog{started: now}, nil, CityPageTTL))
	s.now = func() time.Time { return now }
	var resp cityboard.Response
	if rr := get(t, s, "/helm/city"); rr.Code != http.StatusOK || json.Unmarshal(rr.Body.Bytes(), &resp) != nil {
		t.Fatalf("GET /helm/city = %d %s", rr.Code, rr.Body.String())
	}
	if m := resp.City.Mail; m.Counted || m.Why != "this service counts no mail" {
		t.Errorf("mail = %+v", m)
	}
}
