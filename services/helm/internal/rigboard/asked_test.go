package rigboard

import (
	"context"
	"encoding/json"
	"errors"
	"net/url"
	"strings"
	"testing"
	"time"
)

// supervisorAnswer is what the fake supervisor answers for one path: a JSON
// body, a 404, or an error.
type supervisorAnswer struct {
	body     string
	notFound bool
	err      error
}

// fakeSupervisor answers the rig board's GETs by path, and records each
// request's path and query.
type fakeSupervisor struct {
	answers map[string]supervisorAnswer
	asked   []string
}

func (f *fakeSupervisor) JSON(_ context.Context, out any, path string, query url.Values) (bool, error) {
	req := path
	if len(query) > 0 {
		req += "?" + query.Encode()
	}
	f.asked = append(f.asked, req)
	a, ok := f.answers[path]
	switch {
	case !ok:
		return false, errors.New("the fake supervisor answers no " + path)
	case a.err != nil:
		return false, a.err
	case a.notFound:
		return false, nil
	}
	return true, json.Unmarshal([]byte(a.body), out)
}

// pollAt is the instant the tests read the line at.
var pollAt = time.Date(2026, 11, 16, 17, 0, 0, 0, time.UTC)

// run is one history entry for a run that started ago before pollAt, carrying
// the outcome label its end left, none for a run still going.
func run(ago time.Duration, outcome string) string {
	labels := []string{"order-run:pr-poll:rig:gc-toolkit", "order-tracking"}
	if outcome != "" {
		labels = append([]string{outcome}, labels...)
	}
	b, _ := json.Marshal(map[string]any{
		"bead_id":     "tk-wisp-1",
		"scoped_name": "pr-poll:rig:gc-toolkit",
		"created_at":  pollAt.Add(-ago).Format(time.RFC3339Nano),
		"labels":      labels,
	})
	return string(b)
}

// supervisorWith answers the order pr-poll:rig:gc-toolkit at interval, enabled,
// with a history of runs, newest first as Gas City lists them.
func supervisorWith(interval string, runs ...string) *fakeSupervisor {
	return &fakeSupervisor{answers: map[string]supervisorAnswer{
		"/order/pr-poll:rig:gc-toolkit": {body: `{"name":"pr-poll","scoped_name":"pr-poll:rig:gc-toolkit","type":"exec","trigger":"cooldown","interval":"` + interval + `","enabled":true,"rig":"gc-toolkit"}`},
		"/orders/history":               {body: `{"entries":[` + strings.Join(runs, ",") + `]}`},
	}}
}

func TestReadAskedJudgesTheNewestPassThatExitedZero(t *testing.T) {
	at := func(ago time.Duration) string { return pollAt.Add(-ago).Format(time.RFC3339) }
	cases := []struct {
		name     string
		interval string
		runs     []string
		want     Asked
	}{
		{
			name:     "a recent pass that exited 0",
			interval: "2m",
			runs:     []string{run(time.Minute, "exec"), run(3*time.Minute, "exec")},
			want:     Asked{State: AskedStateAsked, At: at(time.Minute)},
		},
		{
			name:     "the newest pass failed after an older one exited 0",
			interval: "2m",
			runs:     []string{run(time.Minute, "exec-failed"), run(3*time.Minute, "exec")},
			want:     Asked{State: AskedStateAsked, At: at(3 * time.Minute)},
		},
		{
			name:     "a pass that could not build its environment counts as failed",
			interval: "2m",
			runs:     []string{run(time.Minute, "exec-env-failed"), run(5*time.Minute, "exec")},
			want:     Asked{State: AskedStateAsked, At: at(5 * time.Minute)},
		},
		{
			name:     "a pass still going leaves the line at the last one that exited 0",
			interval: "2m",
			runs:     []string{run(10*time.Second, ""), run(2*time.Minute, "exec")},
			want:     Asked{State: AskedStateAsked, At: at(2 * time.Minute)},
		},
		{
			name:     "a pass exactly three intervals old",
			interval: "2m",
			runs:     []string{run(6*time.Minute, "exec")},
			want:     Asked{State: AskedStateAsked, At: at(6 * time.Minute)},
		},
		{
			name:     "a pass older than three intervals",
			interval: "2m",
			runs:     []string{run(time.Minute, "exec-failed"), run(3*time.Minute, "exec-failed"), run(6*time.Minute+time.Second, "exec")},
			want:     Asked{State: AskedStateStale, At: at(6*time.Minute + time.Second)},
		},
		{
			name:     "the city's interval for the order sets the three",
			interval: "5m",
			runs:     []string{run(14*time.Minute, "exec")},
			want:     Asked{State: AskedStateAsked, At: at(14 * time.Minute)},
		},
		{
			name:     "every pass the history holds failed",
			interval: "2m",
			runs:     []string{run(time.Minute, "exec-failed"), run(29*time.Minute, "exec-failed")},
			want:     Asked{State: AskedStateNotAsked, Since: at(29 * time.Minute)},
		},
		{
			name:     "an empty history",
			interval: "2m",
			want:     Asked{State: AskedStateNotAsked},
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := ReadAsked(context.Background(), supervisorWith(c.interval, c.runs...), "gc-toolkit", pollAt)
			if got != c.want {
				t.Errorf("ReadAsked = %+v, want %+v", got, c.want)
			}
		})
	}
}

// TestReadAskedAsksForTheRigsOrder holds the reads to the rig's copy of the
// order: its run history first, then the order itself.
func TestReadAskedAsksForTheRigsOrder(t *testing.T) {
	api := supervisorWith("2m", run(time.Minute, "exec"))
	ReadAsked(context.Background(), api, "gc-toolkit", pollAt)
	want := []string{
		"/orders/history?limit=50&scoped_name=pr-poll%3Arig%3Agc-toolkit",
		"/order/pr-poll:rig:gc-toolkit",
	}
	if strings.Join(api.asked, " ") != strings.Join(want, " ") {
		t.Errorf("asked %q, want %q", api.asked, want)
	}
}

// TestReadAskedSaysARigNoPassWatches holds a rig whose city runs no enabled
// pr-poll order to the unwatched line, whatever its history holds.
func TestReadAskedSaysARigNoPassWatches(t *testing.T) {
	missing := supervisorWith("2m")
	missing.answers["/order/pr-poll:rig:gc-toolkit"] = supervisorAnswer{notFound: true}
	disabled := supervisorWith("2m", run(time.Minute, "exec"))
	disabled.answers["/order/pr-poll:rig:gc-toolkit"] = supervisorAnswer{body: `{"interval":"2m","enabled":false}`}
	for name, api := range map[string]*fakeSupervisor{"no such order": missing, "the order is disabled": disabled} {
		if got := ReadAsked(context.Background(), api, "gc-toolkit", pollAt); got != (Asked{State: AskedStateUnwatched}) {
			t.Errorf("%s: ReadAsked = %+v, want unwatched", name, got)
		}
	}
}

// TestReadAskedSaysAReadThatFailed holds each read that fails to the unread
// line, naming why, and never to a time or to unwatched.
func TestReadAskedSaysAReadThatFailed(t *testing.T) {
	cases := map[string]struct {
		edit func(*fakeSupervisor)
		want string
	}{
		"the history does not answer": {
			edit: func(f *fakeSupervisor) {
				f.answers["/orders/history"] = supervisorAnswer{err: errors.New("GET /orders/history: status 503: cache not live")}
			},
			want: "read the run history of pr-poll:rig:gc-toolkit: GET /orders/history: status 503: cache not live",
		},
		"the history answers 404, as for a city the supervisor does not serve": {
			edit: func(f *fakeSupervisor) {
				f.answers["/orders/history"] = supervisorAnswer{notFound: true}
				f.answers["/order/pr-poll:rig:gc-toolkit"] = supervisorAnswer{notFound: true}
			},
			want: "read the run history of pr-poll:rig:gc-toolkit: the supervisor answered 404",
		},
		"the order does not answer": {
			edit: func(f *fakeSupervisor) {
				f.answers["/order/pr-poll:rig:gc-toolkit"] = supervisorAnswer{err: errors.New("GET /order/pr-poll:rig:gc-toolkit: context deadline exceeded")}
			},
			want: "read the order pr-poll:rig:gc-toolkit: GET /order/pr-poll:rig:gc-toolkit: context deadline exceeded",
		},
		"the order runs at no interval": {
			edit: func(f *fakeSupervisor) {
				f.answers["/order/pr-poll:rig:gc-toolkit"] = supervisorAnswer{body: `{"trigger":"cron","schedule":"*/2 * * * *","enabled":true}`}
			},
			want: `the order pr-poll:rig:gc-toolkit runs at no interval: ""`,
		},
		"a run's start is not a time": {
			edit: func(f *fakeSupervisor) {
				f.answers["/orders/history"] = supervisorAnswer{body: `{"entries":[{"created_at":"yesterday","labels":["exec"]}]}`}
			},
			want: `a run of pr-poll started at "yesterday", which is not a time`,
		},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			api := supervisorWith("2m", run(time.Minute, "exec"))
			c.edit(api)
			got := ReadAsked(context.Background(), api, "gc-toolkit", pollAt)
			if got != (Asked{State: AskedStateUnread, Error: c.want}) {
				t.Errorf("ReadAsked = %+v, want unread with %q", got, c.want)
			}
		})
	}
}
