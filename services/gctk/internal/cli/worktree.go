package cli

import (
	"io"
	"time"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/worktree"
)

// gctk worktree salvage is the orphan-work-detect order's verb
// (docs/gctk-architecture.md, "The surface"), through the worktree package.

func newWorktreeCmd(stdout, stderr io.Writer) *cobra.Command {
	return group("worktree", "the work a dead session left in a rig",
		`The work a dead session left in a rig: each bead whose owner no live session
answers to, which the salvage reader finds (worktree salvage).`,
		newWorktreeSalvageCmd(stdout, stderr))
}

const worktreeSalvageLong = `The salvage reader's look over every rig's store, which the orphan-work-detect
order runs every 15 minutes. It reads gc session list --json once, then the
HQ and each rig gc rig list --json lists that is not suspended, and records one
Gas City event, gc-toolkit.orphan-work.found, when it finds a bead whose owner
no live session answers to. It writes no bead.

A bead is orphaned work when it is open or in progress, is of no kind bd's
default listing hides (a wisp, a template, a gate, or an agent, role or message
bead), names an owner by its gc.session_id, its assignee or its
gc.session_name, and no live session answers to any of them. A session answers
to its id, its name, its runtime session name, its alias and its agent name,
and to an identity no session carries exactly whose last path segment one of
them shares. Every listed session is live except one closed, archived or
failed-create. The reader leaves out:

  work in a PR on its way to its target: merge_result pre_open_gate or
    pull_request, or either value of the pending record,
    pull_request_pending and pull_request_head_changed
  a conversation: a task assigned to human, or to the sitting alias that
    names its own id
  a workflow's topology root: gc.kind workflow, scope or spec
  a bead a person holds: a human gate among the waits that hold it, its own
    or an ancestor's, or among its own waits that have not landed

A session list that does not read, or lists no session, judges nothing. The
event's payload holds:

  read     when the look read
  found    each bead found: rig, bead, status, assignee, session_id,
           session_name, work_dir and branch
  unread   each rig whose store did not read, and why, when one did not

` + lookHelpEnd

func newWorktreeSalvageCmd(stdout, stderr io.Writer) *cobra.Command {
	return &cobra.Command{
		Use:   "salvage",
		Short: "find each bead whose owner no live session answers to, and record them as one gc-toolkit.orphan-work.found event",
		Long:  worktreeSalvageLong,
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			s := &worktree.Salvage{City: gascity.New(), Open: ledger.OpenStore, Now: time.Now}
			out := s.Run()
			if out.Record == nil {
				return reportLook("worktree salvage", nil, "", false, false, out.Failures, stdout, stderr)
			}
			return reportLook("worktree salvage", out.Record, out.Record.Summary(), len(out.Record.Found) > 0, out.Recorded, out.Failures, stdout, stderr)
		},
	}
}
