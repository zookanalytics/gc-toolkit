package rigboard

// The rig's line saying when GitHub was last asked about its pull requests
// (Response.Asked). The rig's pr-poll order asks GitHub, once a pass, whether
// each pull request the rig's beads own moved, and a pass that could not ask
// about every one of them exits non-zero. The line is the start of the newest
// pass that exited 0, read from Gas City's record of the order's runs through
// the supervisor's API. A pass in which nothing moved writes nothing to a pull
// request's bead, but for one whose merge state GitHub had not computed, so Gas
// City's record of the run is all it leaves, and the
// record closes when the run ends, where the rig's listing reads live beads.

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"slices"
	"strconv"
	"time"
)

// Supervisor reads the city's supervisor API: one GET of path, below
// /v0/city/{city}, with query, its JSON body decoded into out. It reports
// whether the API holds what path names, false for an answer of 404, and
// returns an error for any other answer that is not a success, or a body that
// does not decode. The service passes the reader internal/source holds, and a
// test passes a fake.
type Supervisor interface {
	JSON(ctx context.Context, out any, path string, query url.Values) (found bool, err error)
}

// pollOrder is the pack's order that asks GitHub whether each owned pull
// request moved (orders/pr-poll.toml). Gas City names a rig's copy of it
// pr-poll:rig:<rig>.
const pollOrder = "pr-poll"

// staleAfter is how many of the order's intervals the newest pass that exited 0
// may age before the line reads stale.
const staleAfter = 3

// historyLimit is how many of the order's newest runs the line reads. Gas City
// keeps a run's record for [beads.policies.order_tracking] delete_after_close
// after the run closes, 7 days unless the city sets it, and the bound keeps
// such a history from being listed whole. A history whose newest runs all
// failed reads as no pass since the oldest of them.
const historyLimit = 50

// orderRecord is the order as GET /order/{name} answers it, after the city's
// [[orders.overrides]].
type orderRecord struct {
	Interval string `json:"interval"`
	Enabled  bool   `json:"enabled"`
}

// orderRun is one run of the order as GET /orders/history lists it.
type orderRun struct {
	CreatedAt string   `json:"created_at"`
	Labels    []string `json:"labels"`
}

// exitedZero reports whether the run's command exited 0. Gas City labels the
// record of an exec order's run with how the run ended, one label: exec when
// its command exited 0, exec-failed when it did not, and exec-env-failed when
// its environment could not be built. A run still going carries none. The
// history's exit_code is a convergence gate's, which no exec order's run
// records.
func (r orderRun) exitedZero() bool { return slices.Contains(r.Labels, "exec") }

// ReadAsked reads when GitHub was last asked about the rig's pull requests and
// judges the line at now. It reads the order's run history first, which lists
// no run for an order the city does not hold, so a 404 there is an error, and a
// 404 for the order that follows means the city holds no such order. A read
// that fails gives the unread line, since the rig's document stands without it.
func ReadAsked(ctx context.Context, api Supervisor, rig string, now time.Time) Asked {
	scoped := pollOrder + ":rig:" + rig
	var history struct {
		Entries []orderRun `json:"entries"`
	}
	query := url.Values{"scoped_name": {scoped}, "limit": {strconv.Itoa(historyLimit)}}
	found, err := api.JSON(ctx, &history, "/orders/history", query)
	if err == nil && !found {
		err = errors.New("the supervisor answered 404")
	}
	if err != nil {
		return unread(fmt.Errorf("read the run history of %s: %w", scoped, err))
	}
	var order orderRecord
	found, err = api.JSON(ctx, &order, "/order/"+url.PathEscape(scoped), nil)
	if err != nil {
		return unread(fmt.Errorf("read the order %s: %w", scoped, err))
	}
	if !found || !order.Enabled {
		return Asked{State: AskedStateUnwatched}
	}
	interval, err := time.ParseDuration(order.Interval)
	if err != nil || interval <= 0 {
		return unread(fmt.Errorf("the order %s runs at no interval: %q", scoped, order.Interval))
	}
	return judgeAsked(history.Entries, interval, now)
}

// judgeAsked gives the line for the runs the history listed, at now.
func judgeAsked(runs []orderRun, interval time.Duration, now time.Time) Asked {
	var newest, oldest time.Time
	for _, r := range runs {
		at, err := time.Parse(time.RFC3339Nano, r.CreatedAt)
		if err != nil {
			return unread(fmt.Errorf("a run of %s started at %q, which is not a time", pollOrder, r.CreatedAt))
		}
		if oldest.IsZero() || at.Before(oldest) {
			oldest = at
		}
		if r.exitedZero() && at.After(newest) {
			newest = at
		}
	}
	switch {
	case !newest.IsZero() && now.Sub(newest) > staleAfter*interval:
		return Asked{State: AskedStateStale, At: stamp(newest)}
	case !newest.IsZero():
		return Asked{State: AskedStateAsked, At: stamp(newest)}
	case !oldest.IsZero():
		return Asked{State: AskedStateNotAsked, Since: stamp(oldest)}
	default:
		return Asked{State: AskedStateNotAsked}
	}
}

func unread(err error) Asked { return Asked{State: AskedStateUnread, Error: err.Error()} }

func stamp(t time.Time) string { return t.UTC().Format(time.RFC3339) }
