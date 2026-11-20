package cli

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"slices"
	"strings"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/listing"
	"github.com/zookanalytics/gc-toolkit/services/gctk/standing"
)

// `gctk bead stands <bead>...` answers where each bead stands and whose move it
// is, through the standing package, from one listing of the store
// (docs/gctk-architecture.md, "The bead stands contract"). The helm board's rig
// read asks the same package, so a bead reads alike on the board and here.

const beadStandsLong = `Prints where each bead named stands and whose move it is, from one listing
of the store: one JSON object per line, in the order named, each bead once.
The helm board's rig page asks the same rule for each row it draws.

{"id", "group", "rule", "ask", "names", "why", "advance", "stuck_on",
 "frontier"}

group is where the bead's work stands, in the board's words: waiting-on-you
when a person owes the next move, queued when the city takes it as things
stand, not-moving when nothing moves it as things stand, closed, and "" for a
bead with no move of its own, such as an epic with open members. rule is the
rule that placed it, the first that applies of closed, ask, own-wait,
further-along, parked, status, staying, answers, members, gate, in-flight,
scheduled and not-scheduled, and unread where a read could not answer the
part a rule needs, with why saying what it could not. ask is what a person
owes when the bead is itself the ask: question, conversation, pull-request,
routed-to-you or ruling, and "" otherwise. names are the beads the rule
names, each {"id", "title"}: the gate or the bead a person owes, the gate
that parks it, the question a conversation answers, or the beads it waits
on.

advance is how far the city carries an open bead without a person:
advancing, or stuck, with stuck_on {"id", "why"} naming the bead that stops
it, itself included, and the word that says why, its ask or the rule that
names that bead. A queued bead advances while every bead it waits on does,
and an epic or a Delivery the members rule places while every open member
does. frontier is where an open bead stands by what it waits on: ready when
nothing holds it, as gctk bead holds answers, advancing when every wait
behind that answer advances, and stuck when one does not. A closed bead's
advance and frontier are "" and its stuck_on is null.

A bead the store does not hold, and one with no standing of its own, such as
a convoy or a run's step, prints {"id", "error"}, and so does every bead
when a read fails.

--db names the store to read, a store's .beads directory, and every read of
the store names it with bd's own --db flag. Without it the command reads the
store gc routes a read of the first bead to, as gctk bead holds does. Every
read names that one store, so a bead named in another store is one this
store does not hold, and a wait into another store holds nothing.

exit: 0 every bead answered
      1 at least one bead was not, and its line carries the error
      2 usage`

func newBeadStandsCmd(stdout, stderr io.Writer) *cobra.Command {
	var db string
	cmd := &cobra.Command{
		Use:   "stands [--db <path>] <bead>...",
		Short: "where each bead stands and whose move it is: its group, the rule that placed it, what a person owes, the beads the rule names, and how far the city carries it",
		Long:  beadStandsLong,
		Args:  cobra.MinimumNArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			var ids []string
			for _, a := range args {
				id := strings.TrimSpace(a)
				if id == "" {
					return errors.New("name each bead by its id")
				}
				if !slices.Contains(ids, id) {
					ids = append(ids, id)
				}
			}
			return exit(beadStands(db, ids, stdout, stderr))
		},
	}
	cmd.Flags().StringVar(&db, "db", "", "the store to read, a store's .beads directory")
	return cmd
}

// standsLine is one bead's line.
type standsLine struct {
	ID       string      `json:"id"`
	Group    string      `json:"group"`
	Rule     string      `json:"rule"`
	Ask      string      `json:"ask"`
	Names    []standsRef `json:"names"`
	Why      string      `json:"why"`
	Advance  string      `json:"advance"`
	StuckOn  *stuckOn    `json:"stuck_on"`
	Frontier string      `json:"frontier"`
}

type standsRef struct {
	ID    string `json:"id"`
	Title string `json:"title"`
}

type stuckOn struct {
	ID  string `json:"id"`
	Why string `json:"why"`
}

// beadStands prints one line per bead, from one reading of them all, read from
// the store at db, or from the store gc routes the first bead to when db is
// empty.
func beadStands(db string, ids []string, stdout, stderr io.Writer) int {
	r, readErr := readStanding(db, ids)
	code := 0
	for _, id := range ids {
		var line any
		if readErr != nil {
			line, code = failedLine{ID: id, Error: readErr.Error()}, 1
		} else if l, ok := standsLineOf(r, id); ok {
			line = l
		} else {
			why := r.Unanswered(id)
			if why == "" {
				why = "the read did not answer it"
			}
			line, code = failedLine{ID: id, Error: why}, 1
		}
		raw, err := json.Marshal(line)
		if err != nil {
			fmt.Fprintf(stderr, "gctk bead stands: could not encode the answer for %s: %v\n", id, err)
			return 1
		}
		fmt.Fprintf(stdout, "%s\n", raw)
	}
	return code
}

// readStanding reads one listing of the store and asks standing about ids.
func readStanding(db string, ids []string) (*standing.Reading, error) {
	ls, err := listing.Read(context.Background(), db, ids...)
	if err != nil {
		return nil, err
	}
	return standing.Read(ids, ls)
}

// standsLineOf is a bead's line, and false for a bead the reading did not
// answer.
func standsLineOf(r *standing.Reading, id string) (standsLine, bool) {
	a, ok := r.Answer(id)
	if !ok {
		return standsLine{}, false
	}
	l := standsLine{ID: id, Group: string(a.Group), Rule: string(a.Rule), Ask: string(a.Ask), Names: []standsRef{},
		Why: a.Why}
	for _, n := range a.Names {
		l.Names = append(l.Names, standsRef{ID: n.ID, Title: n.Title})
	}
	if adv, ok := r.Advance(id); ok {
		l.Advance = "advancing"
		if !adv.Advancing {
			l.Advance, l.StuckOn = "stuck", &stuckOn{ID: adv.On, Why: adv.Why}
		}
	}
	if f, ok := r.Frontier(id); ok {
		l.Frontier = string(f)
	}
	return l, true
}
