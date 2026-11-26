package session

import (
	"fmt"
	"path"
	"strings"

	"mvdan.cc/sh/v3/expand"
	"mvdan.cc/sh/v3/syntax"
)

// Every session in a city runs as the same user on one host, so a command that
// picks the processes it stops by their name or command line reaches every
// session's processes. That includes the caller's own, whose command line
// carries its prompt and with it the pack's script names. The kill guard reads
// the command an agent types into its shell tool and refuses such a kill.

// patternKillers pick the processes they signal by a name or a command line.
var patternKillers = map[string]bool{"killall": true, "pkill": true}

// wrappers run a command that one of their later words names.
var wrappers = map[string]bool{
	"command": true, "env": true, "exec": true, "nice": true, "nohup": true,
	"setsid": true, "sudo": true, "timeout": true, "xargs": true,
}

// shells run the script their -c option is given.
var shells = map[string]bool{"bash": true, "dash": true, "ksh": true, "sh": true, "zsh": true}

// maxScriptDepth bounds how deeply scripts given to a shell or to eval, inside
// one another, are read.
const maxScriptDepth = 4

// PatternKill names the pattern killer, pkill or killall, that a typed shell
// command runs, read as bash. It returns "" for a command that runs neither,
// and for one it cannot read: a command that does not parse, or one whose
// command name is built as it runs.
func PatternKill(command string) string {
	return scriptKills(command, 0)
}

// PatternKillRefusal is the kill guard's reason for refusing a call that runs
// killer, which names the ways a caller stops a process it started.
func PatternKillRefusal(killer string) string {
	return fmt.Sprintf("kill-guard: refused `%s`. It picks processes by their name or command line, "+
		"and every session on this host runs as the same user, so it can stop another session's run, "+
		"or this session itself. Stop only what you started, by what you recorded when you started it: "+
		"a background task by its task id (TaskStop in Claude Code), a process by its pid (`kill <pid>`), "+
		"and a process group by its id (`kill -- -<pgid>`). To find a process you did not record, list "+
		"processes by a path only your session uses, such as your worktree "+
		"(`ps -axo pid,pgid,command | grep -F -- <path>`), and kill the pid it shows. Never pick pids by "+
		"a pattern another session's command can match, such as `pgrep -f`.", killer)
}

// scriptKills names the pattern killer a script runs anywhere in it: in a list,
// a pipeline, a subshell, a substitution, a function or a clause's body.
func scriptKills(script string, depth int) string {
	if depth > maxScriptDepth {
		return ""
	}
	file, err := syntax.NewParser(syntax.Variant(syntax.LangBash)).Parse(strings.NewReader(script), "")
	if err != nil {
		return ""
	}
	found := ""
	syntax.Walk(file, func(n syntax.Node) bool {
		if call, ok := n.(*syntax.CallExpr); ok && found == "" {
			found = callKills(call.Args, depth)
		}
		return found == ""
	})
	return found
}

// callKills names the pattern killer a simple command runs, itself or through
// a wrapper. A wrapper's options take values whose count each wrapper decides,
// so every later word is read as the command it may run.
func callKills(words []*syntax.Word, depth int) string {
	name, ok := commandName(words)
	if !ok || !wrappers[name] {
		return runs(words, depth)
	}
	if name == "command" && looksUp(words[1:]) {
		return ""
	}
	for i := 1; i < len(words); i++ {
		if killer := runs(words[i:], depth); killer != "" {
			return killer
		}
	}
	return ""
}

// runs names the pattern killer that the command words names runs: the
// command itself, or a call in the script it is given as a shell or as eval.
func runs(words []*syntax.Word, depth int) string {
	name, ok := commandName(words)
	switch {
	case !ok:
		return ""
	case patternKillers[name]:
		return name
	case shells[name]:
		if script, ok := dashC(words[1:]); ok {
			return scriptKills(script, depth+1)
		}
	case name == "eval":
		parts := make([]string, 0, len(words)-1)
		for _, w := range words[1:] {
			parts = append(parts, scriptText(w))
		}
		return scriptKills(strings.Join(parts, " "), depth+1)
	}
	return ""
}

// commandName is the base name of the command words names, when its first
// word reads the same however the call runs.
func commandName(words []*syntax.Word) (string, bool) {
	if len(words) == 0 {
		return "", false
	}
	s, ok := literal(words[0])
	if !ok || s == "" {
		return "", false
	}
	return path.Base(s), true
}

// dashC is the script a shell's -c option is given: the word after the first
// cluster of short options that holds c.
func dashC(args []*syntax.Word) (string, bool) {
	for i, w := range args {
		s, ok := literal(w)
		if ok && len(s) > 1 && s[0] == '-' && s[1] != '-' && strings.ContainsRune(s[1:], 'c') {
			if i+1 < len(args) {
				return scriptText(args[i+1]), true
			}
			return "", false
		}
	}
	return "", false
}

// scriptText is the script a word gives a shell or eval: its text, with each
// expansion standing as one opaque word, since its value is known only as the
// call runs.
func scriptText(w *syntax.Word) string {
	s, _ := wordText(w, opaqueWord)
	return s
}

// opaqueWord stands in a script's text for an expansion the guard cannot know.
const opaqueWord = "_"

// looksUp says whether command's options make it look a name up, as -v and -V
// do, rather than run it.
func looksUp(args []*syntax.Word) bool {
	for _, w := range args {
		s, ok := literal(w)
		if !ok || len(s) < 2 || s[0] != '-' || s == "--" {
			return false
		}
		if strings.ContainsAny(s[1:], "vV") {
			return true
		}
	}
	return false
}

// literal is a word's value when the word holds no expansion.
func literal(w *syntax.Word) (string, bool) {
	return wordText(w, "")
}

// wordText is the text a word gives the command it is passed to, quotes and
// backslashes resolved as the shell resolves them. An expansion stands as
// opaque, and with no opaque word given the word has no text the guard can
// know.
func wordText(w *syntax.Word, opaque string) (string, bool) {
	var b strings.Builder
	expansion := func() bool {
		b.WriteString(opaque)
		return opaque != ""
	}
	for _, part := range w.Parts {
		switch p := part.(type) {
		case *syntax.Lit:
			b.WriteString(unescape(p.Value, escapedOutsideQuotes))
		case *syntax.SglQuoted:
			b.WriteString(sglQuoted(p))
		case *syntax.DblQuoted:
			for _, inner := range p.Parts {
				lit, ok := inner.(*syntax.Lit)
				if !ok {
					if !expansion() {
						return "", false
					}
					continue
				}
				b.WriteString(unescape(lit.Value, escapedInDoubleQuotes))
			}
		default:
			if !expansion() {
				return "", false
			}
		}
	}
	return b.String(), true
}

// sglQuoted is the text a single-quoted part gives. A '...' part gives its text
// as typed. A $'...' part gives its text with its backslash escapes decoded,
// such as \n, \t and \x70, up to a decoded NUL byte, as the library's own
// expander reads it. The decode takes a config of its own, because Format with
// none writes to one the package shares.
func sglQuoted(p *syntax.SglQuoted) string {
	if !p.Dollar {
		return p.Value
	}
	s, _, _ := expand.Format(&expand.Config{}, p.Value, nil)
	s, _, _ = strings.Cut(s, "\x00")
	return s
}

// escapedOutsideQuotes says a backslash outside quotes escapes any character.
func escapedOutsideQuotes(rune) bool { return true }

// escapedInDoubleQuotes says whether a backslash inside double quotes escapes
// r, which it does only for $, `, ", \ and newline.
func escapedInDoubleQuotes(r rune) bool { return strings.ContainsRune("$`\"\\\n", r) }

// unescape resolves each backslash in s that escapes the character after it,
// as escaped says. A backslash before a newline joins two lines, so both go.
func unescape(s string, escaped func(rune) bool) string {
	if !strings.Contains(s, `\`) {
		return s
	}
	var b strings.Builder
	rs := []rune(s)
	for i := 0; i < len(rs); i++ {
		if rs[i] == '\\' && i+1 < len(rs) && escaped(rs[i+1]) {
			i++
			if rs[i] != '\n' {
				b.WriteRune(rs[i])
			}
			continue
		}
		b.WriteRune(rs[i])
	}
	return b.String()
}
