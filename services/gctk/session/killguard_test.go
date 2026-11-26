package session

import (
	"strings"
	"testing"
)

// The guard refuses pkill and killall wherever a typed command runs them, and
// passes a kill by a recorded pid or process group, text that only names them,
// and a command it cannot read.
func TestPatternKill(t *testing.T) {
	cases := []struct {
		name, command, want string
	}{
		// The two commands, however they are reached.
		{"pkill by command line", `pkill -f 'tools/run-tests.sh'`, "pkill"},
		{"killall by name", `killall node`, "killall"},
		{"pkill alone", `pkill`, "pkill"},
		{"a path to pkill", `/usr/bin/pkill -f x`, "pkill"},
		{"an escaped name", `\pkill -f x`, "pkill"},
		{"a quoted name", `'pkill' -f x`, "pkill"},
		{"after a cd", `cd /tmp && pkill -f 'sleep 30'`, "pkill"},
		{"after a semicolon", `true; killall -9 sleep`, "killall"},
		{"on a later line", "echo start\npkill -f x", "pkill"},
		{"in a pipeline", `pgrep -f x | xargs pkill`, "pkill"},
		{"in a subshell", `(pkill -f x)`, "pkill"},
		{"in a command substitution", `echo "$(pkill -f x)"`, "pkill"},
		{"in a backquoted substitution", "echo `pkill -f x`", "pkill"},
		{"in an assignment's substitution", `out=$(pkill -f x)`, "pkill"},
		{"in an if body", `if true; then pkill -f x; fi`, "pkill"},
		{"in a loop body", `for p in a b; do pkill -f "$p"; done`, "pkill"},
		{"in a function body", `stop() { pkill -f x; }; stop`, "pkill"},
		{"in the background", `pkill -f x &`, "pkill"},
		{"timed", `time pkill -f x`, "pkill"},
		{"negated", `! pkill -f x`, "pkill"},
		{"in an unquoted here-document's substitution", "cat <<EOF\n$(pkill -f x)\nEOF", "pkill"},
		{"behind env", `env -i PATH=/bin pkill -f x`, "pkill"},
		{"behind sudo with a valued option", `sudo -u root pkill -f x`, "pkill"},
		{"behind timeout", `timeout -k 5 30 killall node`, "killall"},
		{"behind nohup", `nohup pkill -f x &`, "pkill"},
		{"behind exec", `exec pkill -f x`, "pkill"},
		{"behind command", `command pkill -f x`, "pkill"},
		{"behind xargs with an option", `echo x | xargs -I{} pkill -f {}`, "pkill"},
		{"behind two wrappers", `nohup timeout 5 pkill -f x`, "pkill"},
		{"in a bash -c script", `bash -c 'pkill -f x'`, "pkill"},
		{"in an sh -c script", `sh -c "killall x"`, "killall"},
		{"in a zsh -lc script", `zsh -lc 'cd /tmp && pkill -f x'`, "pkill"},
		{"in a -c script with an expansion", `bash -c "pkill -f $NAME"`, "pkill"},
		{"in a -c script behind a wrapper", `timeout 60 bash -c 'pkill -f x'`, "pkill"},
		{"in a -c script inside a -c script", `bash -c "sh -c 'pkill -f x'"`, "pkill"},
		{"in a -c script after --", `bash -c -- 'pkill -f x'`, "pkill"},
		{"in a -c script after -", `sh -c - 'killall x'`, "killall"},
		{"in a -c script after another option", `bash -c -e 'pkill -f x'`, "pkill"},
		{"in a -c script after an option's value", `bash -o pipefail -c 'pkill -f x'`, "pkill"},
		{"in a -c script after -c and an option's value", `bash -c -o pipefail 'pkill -f x'`, "pkill"},
		{"in a -c script after a cluster's value", `bash -eo pipefail -c 'pkill -f x'`, "pkill"},
		{"in a -c script after bash's -O and its value", `bash -O extglob -c 'pkill -f x'`, "pkill"},
		{"in a -c script after zsh's -O, which takes no value", `zsh -O -c 'pkill -f x'`, "pkill"},
		{"in a -c script after --rcfile and its file", `bash --rcfile x.rc -c 'pkill -f x'`, "pkill"},
		{"in an eval", `eval "pkill -f x"`, "pkill"},
		{"in an eval of several words", `eval pkill -f x`, "pkill"},
		{"an ANSI-C quoted name", `$'pkill' -f x`, "pkill"},
		{"an ANSI-C quoted name with an escape", `$'\x70kill' -f x`, "pkill"},
		{"on a later line of an ANSI-C quoted -c script", `bash -c $'echo starting\npkill -f x'`, "pkill"},
		{"on a later line of an ANSI-C quoted eval", `eval $'true\nkillall x'`, "killall"},
		{"in env's split string", `env -S "pkill -f x"`, "pkill"},
		{"in env's split string in the option's word", `env -S"killall node"`, "killall"},
		{"in env's long split option", `env --split-string="pkill -f x"`, "pkill"},
		{"in env's long split option's next word", `env --split-string 'pkill -f x'`, "pkill"},
		{"in env's split string after an option's value", `env -u FOO -S 'pkill -f x'`, "pkill"},
		{"in env's split string after a cluster", `env -iS 'PATH=/bin pkill -f x'`, "pkill"},
		{"after env's options in its split string", `env -S '-i PATH=/bin pkill -f x'`, "pkill"},
		{"in env's split string split at \\_", `env -S 'pkill\_-f\_x'`, "pkill"},
		{"in env's split string with a quoted part", `env -S '"pk"ill -f x'`, "pkill"},
		{"in a -c script in env's split string", `env -S 'sh -c "pkill -f x"'`, "pkill"},
		{"on a later line of a -c script in env's split string", `env -S 'sh -c "echo a\npkill -f x"'`, "pkill"},
		{"in a -c script after env's split string", `env -S 'sh -c' 'pkill -f x'`, "pkill"},
		{"in env's split string behind another wrapper", `nohup env -S 'pkill -f x'`, "pkill"},
		{"in env's split string inside another", `env -S 'env -S "pkill -f x"'`, "pkill"},

		// A kill by what the caller recorded.
		{"kill by pid", `kill 12345`, ""},
		{"kill by signal and pid", `kill -TERM 12345`, ""},
		{"kill by process group", `kill -TERM -- -4321`, ""},
		{"kill by a recorded pid", `kill "$PID"`, ""},
		{"kill a job", `kill %1`, ""},
		{"a liveness check", `kill -0 "$PID" && echo alive`, ""},

		// Text that only names the commands.
		{"a grep for pkill", `grep -rn pkill docs/`, ""},
		{"an echo of killall", `echo killall`, ""},
		{"a commit message", `git commit -m "refuse pkill; killall too"`, ""},
		{"a note", `gc bd update tk-x --append-notes "never pkill -f by pattern"`, ""},
		{"a quoted here-document body", "cat > notes.md <<'EOF'\npkill -f x\nkillall y\nEOF", ""},
		{"an unquoted here-document body", "cat > notes.md <<EOF\npkill -f x\nEOF", ""},
		{"a comment", `true # pkill -f x`, ""},
		{"a lookup by command -v", `command -v pkill`, ""},
		{"a manual page", `man pkill`, ""},
		{"a which", `which killall`, ""},
		{"an argument of a -c script", `bash -c 'echo pkill'`, ""},
		{"an argument of a shell's script", `bash script.sh -c "pkill -f x"`, ""},
		{"an argument of a shell's script after --", `bash -- script.sh -c 'pkill -f x'`, ""},
		{"an argument of a shell's script after an option's value", `sh -o errexit run.sh -c 'killall x'`, ""},
		{"an ANSI-C quoted argument", `echo $'pkill -f x'`, ""},
		{"a backslash and n in a single-quoted -c script", `bash -c 'echo starting\npkill -f x'`, ""},
		{"a process listing", `ps -axo pid,pgid,command | grep -F -- /work/tree`, ""},
		{"a pgrep by worktree", `pgrep -f "/work/tree/"`, ""},
		{"a quoted argument in env's split string", `env -S 'grep -e "pkill -f"'`, ""},
		{"a comment in env's split string", `env -S 'echo hi # pkill -f x'`, ""},
		{"text after a \\c in env's split string", `env -S 'echo hi \c pkill -f x'`, ""},
		{"a value env sets", `env NOTE='pkill -f x' make check`, ""},

		// What the guard cannot read passes.
		{"a name built as the call runs", `$KILLER -f x`, ""},
		{"a script built as the call runs", `bash -c "$SCRIPT"`, ""},
		{"a name env's split string builds as the call runs", `env -S '${KILLER} -f x'`, ""},
		{"a command that does not parse", `pkill -f 'unterminated`, ""},
		{"an empty command", ``, ""},
		{"a -c with no script", `bash -c`, ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := PatternKill(c.command); got != c.want {
				t.Errorf("PatternKill(%q) = %q, want %q", c.command, got, c.want)
			}
		})
	}
}

// Scripts nested past the depth bound are not read, so a command cannot hold
// the guard in a parse without end.
func TestPatternKillBoundsNestedScripts(t *testing.T) {
	inner := "pkill -f x"
	for range maxScriptDepth + 2 {
		inner = "eval " + shellQuote(inner)
	}
	if got := PatternKill(inner); got != "" {
		t.Errorf("a pkill nested %d scripts deep was read: %q", maxScriptDepth+2, got)
	}
	shallow := "eval " + shellQuote("eval "+shellQuote("pkill -f x"))
	if got := PatternKill(shallow); got != "pkill" {
		t.Errorf("a pkill nested two scripts deep = %q, want pkill", got)
	}
}

// The refusal names the command it refused and each way to stop a process the
// caller started.
func TestPatternKillRefusalNamesTheWays(t *testing.T) {
	reason := PatternKillRefusal("killall")
	for _, want := range []string{"`killall`", "TaskStop", "`kill <pid>`", "`kill -- -<pgid>`", "`pgrep -f`"} {
		if !strings.Contains(reason, want) {
			t.Errorf("the refusal does not name %s:\n%s", want, reason)
		}
	}
}

// shellQuote quotes s as one single-quoted shell word.
func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}
