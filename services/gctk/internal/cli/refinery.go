package cli

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/refinery"
)

// gctk refinery stuck is the refinery-queue-detect order's verb
// (docs/gctk-architecture.md, "The surface"), through the refinery package.

func newRefineryCmd(stdout, stderr io.Writer) *cobra.Command {
	return group("refinery", "a rig's refinery queue",
		`A rig's refinery queue: the one item a refinery session takes next (refinery
next), and each handoff that has sat there unprepared, held by nothing, past
the time a handoff takes to turn over (refinery stuck).`,
		newRefineryNextCmd(stdout, stderr), newRefineryStuckCmd(stdout, stderr))
}

const refineryNextLong = `The refinery's search, which a refinery session's gc hook --claim runs as
its work query (agents/refinery/agent.toml). It reads the beads assigned to
$GC_AGENT in the store gc resolves here, open or in progress, and prints the
one the session takes next as a JSON array of one row, as gc hook --claim reads
a work query's row, or [] when it takes none. Each bead it leaves, and why, goes
to stderr.

Gas City starts a refinery session for a bead assigned to it that is ready or
in progress, so the search leaves no such bead as that demand:

  - a bead in progress is a claim a session left, taken first; one something
    holds goes back to open, so the wait decides when it is taken
  - a bead something holds (gctk bead holds) waits until its waits land, but a
    conversation or an ask on its PR holds only the merge, so it is taken
  - a bead with no branch is taken as it is, for the session to read
  - a bead whose branch another open bead works on is made to wait on that
    bead, by a blocks edge, so it turns ready when that bead closes; when that
    bead waits on it, bd refuses the edge as a cycle, so it waits on the live
    runs that work that bead instead
  - a patrol wisp left assigned to the refinery from before a session took one
    item and ended is closed, since Gas City counts it as demand

Among the rest it takes a rework child handed back before its anchor, then
the highest priority, then the oldest. A write it cannot make is named on
stderr as WARN, and leaves its bead demand for the next session.

exit: 0 answered, a bead or none · 1 GC_AGENT is empty, or a read did not
      answer, so nothing is taken`

func newRefineryNextCmd(stdout, stderr io.Writer) *cobra.Command {
	return &cobra.Command{
		Use:   "next",
		Short: "print the one item a refinery session takes next, as its work query, and make each bead it leaves wait",
		Long:  refineryNextLong,
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			say := func(format string, a ...any) { fmt.Fprintf(stderr, "gctk refinery next: "+format+"\n", a...) }
			agent := strings.TrimSpace(os.Getenv("GC_AGENT"))
			if agent == "" {
				say("GC_AGENT is empty, and an empty assignee filter is no filter, so nothing is taken")
				return exit(1)
			}
			l, err := ledger.Open("")
			if err != nil {
				say("the store did not open, so nothing is taken: %v", err)
				return exit(1)
			}
			var self []string
			for _, v := range []string{"GC_SESSION_NAME", "GC_SESSION_ID", "GC_AGENT", "GC_ALIAS"} {
				if s := strings.TrimSpace(os.Getenv(v)); s != "" {
					self = append(self, s)
				}
			}
			city := gascity.New()
			search := &refinery.Search{Ledger: l, Refinery: agent, Self: self,
				Sessions: func() ([]gascity.Session, error) { return city.Sessions(context.Background()) }}
			ans, err := search.Next()
			if err != nil {
				say("%v, so nothing is taken", err)
				return exit(1)
			}
			for _, left := range ans.Left {
				if left.Wrote != "" {
					say("left %s: %s; %s", left.ID, left.Why, left.Wrote)
				} else {
					say("left %s: %s", left.ID, left.Why)
				}
			}
			for _, f := range ans.Failures {
				say("WARN %s", f)
			}
			rows := []*refinery.Item{}
			if ans.Take != nil {
				rows = append(rows, ans.Take)
			}
			out, err := json.Marshal(rows)
			if err != nil {
				return err
			}
			fmt.Fprintf(stdout, "%s\n", out)
			return nil
		},
	}
}

const refineryStuckLong = `The refinery queue's look, which the refinery-queue-detect order runs every 30
minutes. For each rig gc rig list --json lists that is not suspended, the HQ
aside, it reads the open beads assigned to the agent named refinery that gc
agent list --json names in the rig, and records one Gas City event,
gc-toolkit.refinery-queue.stuck, when it finds a handoff stuck there. It writes
no bead. A rig whose roster names no refinery is a queue that cannot be read.

A handoff is a bead of no kind bd's default listing hides (a wisp, a template,
a gate, or an agent, role or message bead), and no epic, that carries a branch
and no merge_result. It is stuck when its last write is more than four hours
old, nothing holds it (gctk bead holds answers clear), and the close of the
last wait that held it is more than four hours old too. A handoff turns over
within a poll interval, and a rebase or rework task once the fix pool claims
it, so one past that bound is not churn.

A rig list or an agent list that does not read judges nothing. The event's
payload holds:

  read     when the look read
  stuck    each handoff found: rig, bead, refinery, and since, the later of
           its last write and the close of the last wait that held it
  unread   each rig whose queue, its address, or what holds a handoff past
           the bound did not read, and why, when one did not

` + lookHelpEnd

func newRefineryStuckCmd(stdout, stderr io.Writer) *cobra.Command {
	return &cobra.Command{
		Use:   "stuck",
		Short: "find each refinery handoff that has sat unprepared past four hours, held by nothing, and record them as one gc-toolkit.refinery-queue.stuck event",
		Long:  refineryStuckLong,
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			q := &refinery.Queue{City: gascity.New(), Open: ledger.OpenStore, Now: time.Now}
			ctx, release := stopOnSignal()
			out := q.Run(ctx)
			if sig := release(); sig != 0 {
				return exit(128 + int(sig))
			}
			if out.Record == nil {
				return reportLook("refinery stuck", nil, "", false, false, out.Failures, stdout, stderr)
			}
			return reportLook("refinery stuck", out.Record, out.Record.Summary(), len(out.Record.Stuck) > 0, out.Recorded, out.Failures, stdout, stderr)
		},
	}
}
