package gcbd

import (
	"encoding/json"
	"fmt"
	"regexp"
	"slices"
	"strings"
	"time"
)

// actorName is the form of an actor a write query can hold: the characters a
// session id, an alias or an agent's name carries, so no quote can end the
// query's literal. It is the guard assets/scripts/seat-progress.sh puts on the
// identity it reads.
var actorName = regexp.MustCompile(`^[A-Za-z0-9._/-]+$`)

// lastWritesQuery is the newest created_at per actor across the store's
// events and wisp_events tables, the write log bd keeps for its permanent
// rows and its wisps, for the actors in the list it is given.
const lastWritesQuery = "SELECT actor, MAX(t) AS newest FROM (" +
	"SELECT actor, MAX(created_at) AS t FROM events WHERE actor IN (%[1]s) GROUP BY actor " +
	"UNION ALL SELECT actor, MAX(created_at) AS t FROM wisp_events WHERE actor IN (%[1]s) GROUP BY actor" +
	") AS w GROUP BY actor"

// LastWrites reads, in one `gc bd sql`, the newest write the store records
// under each actor named, from its events and its wisp_events tables. An actor
// the store records no write by is left out. A name a query cannot hold, a read
// that fails, and a row that does not read are each a *ReadError, never an
// empty answer.
func (c *Client) LastWrites(actors []string) (map[string]time.Time, error) {
	names := slices.Compact(slices.Sorted(slices.Values(actors)))
	out := map[string]time.Time{}
	if len(names) == 0 {
		return out, nil
	}
	quoted := make([]string, len(names))
	for i, a := range names {
		if !actorName.MatchString(a) {
			return nil, &ReadError{Reason: fmt.Sprintf("the actor %q carries a character the write query cannot hold", a)}
		}
		quoted[i] = "'" + a + "'"
	}
	raw, err := c.strictArray("bd", "sql", "--json", fmt.Sprintf(lastWritesQuery, strings.Join(quoted, ",")))
	if err != nil {
		return nil, err
	}
	var rows []struct {
		Actor  string  `json:"actor"`
		Newest *string `json:"newest"`
	}
	if err := json.Unmarshal(raw, &rows); err != nil {
		return nil, &ReadError{Reason: "the write log's rows did not decode: " + err.Error()}
	}
	for _, r := range rows {
		if r.Newest == nil {
			continue
		}
		t, err := time.Parse(time.RFC3339Nano, *r.Newest)
		if err != nil || !slices.Contains(names, r.Actor) {
			return nil, &ReadError{Reason: fmt.Sprintf("the write log answered a row that does not read: actor %q, newest %q", r.Actor, *r.Newest)}
		}
		out[r.Actor] = t.UTC()
	}
	return out, nil
}
