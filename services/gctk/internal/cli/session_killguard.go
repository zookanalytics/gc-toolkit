package cli

import (
	"encoding/json"
	"io"
	"os"

	"github.com/spf13/cobra"

	"github.com/zookanalytics/gc-toolkit/services/gctk/session"
)

// sessionKillGuardLong is kill-guard's help.
const sessionKillGuardLong = `Reads the payload of a PreToolUse hook on stdin, the one Claude Code and Codex
send before a shell call, and refuses the call when the command it runs is
pkill or killall. Every session in a city runs as the same user on one host, so
a kill that picks processes by their name or command line can stop another
session's run, or the calling session itself, whose command line carries its
prompt.

The refusal is the hook's deny object on stdout. Its reason names the ways to
stop a process the caller started: a background task by its task id, a process
by its pid (kill <pid>), and a process group by its id (kill -- -<pgid>).

The command is read as bash. pkill or killall refuses wherever the command runs
it: in a list, a pipeline, a subshell, a substitution, a function or a clause's
body, and in a script given to sh -c, bash -c, zsh -c or eval. Behind a wrapper
such as env, timeout, xargs or nohup, any later word that names one of them
refuses, because a wrapper's options take values the guard does not count.
Text that only names them passes: an argument such as grep's pattern, quoted
text and a here-document's body. So does a kill by a pid or a process group,
and a kill whose pids pgrep or ps finds, which the refusal steers away from.

A call the guard cannot read passes: a payload that is not a shell call, a
command that does not parse, and a command whose name is built as it runs. The
guard reads what is typed, so the calls a script makes are its own, and it is
not a sandbox.

exit: 0 whatever the payload holds, since the refusal travels in the JSON and a
        guard that cannot read its payload must never block a call
      2 usage`

// hookShellCall is the part of a PreToolUse payload the kill guard reads, which
// Claude Code and Codex both send for a shell call (docs/gh-origin-guard.md,
// "Codex").
type hookShellCall struct {
	ToolName  string `json:"tool_name"`
	ToolInput struct {
		Command string `json:"command"`
	} `json:"tool_input"`
}

// preToolUseDeny is the PreToolUse hook's object that refuses a call, which
// both providers read back with its reason.
type preToolUseDeny struct {
	HookSpecificOutput struct {
		HookEventName            string `json:"hookEventName"`
		PermissionDecision       string `json:"permissionDecision"`
		PermissionDecisionReason string `json:"permissionDecisionReason"`
	} `json:"hookSpecificOutput"`
}

func newSessionKillGuardCmd(stdout io.Writer) *cobra.Command {
	return &cobra.Command{
		Use:   "kill-guard",
		Short: "refuse a shell call that kills processes by their name or command line",
		Long:  sessionKillGuardLong,
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			raw, err := io.ReadAll(os.Stdin)
			if err == nil {
				killGuard(raw, stdout)
			}
			return nil
		},
	}
}

// killGuard prints the deny object for a shell call that runs a pattern
// killer, and nothing for any other payload.
func killGuard(raw []byte, stdout io.Writer) {
	var call hookShellCall
	if json.Unmarshal(raw, &call) != nil || call.ToolName != "Bash" {
		return
	}
	killer := session.PatternKill(call.ToolInput.Command)
	if killer == "" {
		return
	}
	var deny preToolUseDeny
	deny.HookSpecificOutput.HookEventName = "PreToolUse"
	deny.HookSpecificOutput.PermissionDecision = "deny"
	deny.HookSpecificOutput.PermissionDecisionReason = session.PatternKillRefusal(killer)
	enc := json.NewEncoder(stdout)
	enc.SetEscapeHTML(false)
	_ = enc.Encode(deny)
}
