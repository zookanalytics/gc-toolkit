package claudecode

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// stub writes a claude onto a fresh PATH directory that logs its argv, its
// working directory and its environment, then runs body, and returns the
// adapter over it and the log's path.
func stub(t *testing.T, body string) (*CLI, string) {
	t.Helper()
	dir := t.TempDir()
	log := filepath.Join(dir, "log")
	script := "#!/bin/sh\n" +
		"{ printf 'cwd=%s\\n' \"$PWD\"; for a in \"$@\"; do printf 'arg=%s\\n' \"$a\"; done; env | sed 's/^/env=/'; } > " + log + "\n" +
		body + "\n"
	bin := filepath.Join(dir, "claude")
	if err := os.WriteFile(bin, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	return &CLI{bin: bin, timeout: 10 * time.Second}, log
}

func logged(t *testing.T, log string) string {
	t.Helper()
	raw, err := os.ReadFile(log)
	if err != nil {
		t.Fatal(err)
	}
	return string(raw)
}

// The init record answers even when a hook's record comes first and the turn
// after it fails.
func TestMemoryDirReadsTheInitRecord(t *testing.T) {
	c, _ := stub(t, `echo '{"type":"system","subtype":"hook_started"}'
echo '{"type":"system","subtype":"init","claude_code_version":"9.9.9","memory_paths":{"auto":"/m/memory/"}}'
echo 'not json'
exit 1`)
	ans, err := c.MemoryDir(Ask{Dir: t.TempDir()})
	if err != nil || ans.Dir != "/m/memory/" || ans.Version != "9.9.9" {
		t.Fatalf("MemoryDir = %+v, %v; want /m/memory/ from 9.9.9", ans, err)
	}
}

// A record with no memory_paths answers an empty directory, not an error.
func TestMemoryDirAnswersNoDirectoryWhenTheRecordNamesNone(t *testing.T) {
	c, _ := stub(t, `echo '{"type":"system","subtype":"init","claude_code_version":"9.9.9"}'`)
	ans, err := c.MemoryDir(Ask{Dir: t.TempDir()})
	if err != nil || ans.Dir != "" || ans.Version != "9.9.9" {
		t.Fatalf("MemoryDir = %+v, %v; want no directory from 9.9.9", ans, err)
	}
}

func TestMemoryDirFailsWithNoInitRecord(t *testing.T) {
	c, _ := stub(t, `echo 'Invalid API key' >&2; exit 1`)
	_, err := c.MemoryDir(Ask{Dir: t.TempDir()})
	if err == nil || !strings.Contains(err.Error(), "exit 1: Invalid API key") {
		t.Fatalf("MemoryDir error = %v; want the exit and the last line of stderr", err)
	}
}

// An ask that does not answer in time is stopped with SIGTERM, which lets
// Claude Code finish writing its config file, not killed outright. A bound
// that passes before the stub has set its trap shows nothing, as it can on a
// loaded host, so the ask runs again with a longer one.
func TestMemoryDirEndsAnAskThatDoesNotAnswer(t *testing.T) {
	c, log := stub(t, `l="$(dirname "$0")/log"
trap 'echo stopped >> "$l"; exit 143' TERM
echo trapped >> "$l"
while :; do sleep 0.05; done`)
	for c.timeout = 200 * time.Millisecond; ; c.timeout *= 2 {
		os.Remove(log)
		start := time.Now()
		_, err := c.MemoryDir(Ask{Dir: t.TempDir()})
		if err == nil || !strings.Contains(err.Error(), "did not answer within") {
			t.Fatalf("MemoryDir error = %v; want a timeout", err)
		}
		if over := time.Since(start) - c.timeout; over > 5*time.Second {
			t.Errorf("the ask ran %s past its bound", over)
		}
		raw, _ := os.ReadFile(log)
		got := string(raw)
		switch {
		case strings.Contains(got, "stopped\n"):
			return
		case strings.Contains(got, "trapped\n"):
			t.Fatalf("the ask was not stopped with SIGTERM:\n%s", got)
		case c.timeout >= 6400*time.Millisecond:
			t.Fatalf("the stub had not set its trap when a bound of %s passed:\n%s", c.timeout, got)
		}
	}
}

// The ask runs in the directory named, with the city's settings and its hooks
// off as one --settings value, on the cheapest model with no transcript, its
// standard input empty, and without the variables of the session that runs it.
func TestMemoryDirAsksAsASessionOfItsOwn(t *testing.T) {
	c, log := stub(t, `read line && echo "stdin=$line" >> "$(dirname "$0")/log"
echo '{"type":"system","subtype":"init","memory_paths":{"auto":"/m/"}}'`)
	dir := t.TempDir()
	settings := filepath.Join(t.TempDir(), "settings.json")
	if err := os.WriteFile(settings, []byte(`{"autoMemoryDirectory":"/elsewhere","hooks":{"SessionStart":[]}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("CLAUDECODE", "1")
	t.Setenv("CLAUDE_CODE_SESSION_ID", "s")
	t.Setenv("CLAUDE_CODE_ENTRYPOINT", "cli")
	t.Setenv("CLAUDE_CODE_MESSAGING_SOCKET", "/tmp/s.sock")
	t.Setenv("CLAUDE_CONFIG_DIR", "/cfg")
	if _, err := c.MemoryDir(Ask{Dir: dir, Settings: settings}); err != nil {
		t.Fatal(err)
	}
	got := logged(t, log)
	real, _ := filepath.EvalSymlinks(dir)
	for _, want := range []string{"cwd=" + real, "arg=-p", "arg=--no-session-persistence", "arg=--strict-mcp-config",
		"arg=haiku", "arg=--max-turns", "env=CLAUDE_CONFIG_DIR=/cfg"} {
		if !strings.Contains(got, want+"\n") {
			t.Errorf("the ask's log lacks %q:\n%s", want, got)
		}
	}
	for _, gone := range []string{"env=CLAUDECODE=", "env=CLAUDE_CODE_SESSION_ID=", "env=CLAUDE_CODE_ENTRYPOINT=",
		"env=CLAUDE_CODE_MESSAGING_SOCKET=", "stdin="} {
		if strings.Contains(got, gone) {
			t.Errorf("the ask's log holds %q:\n%s", gone, got)
		}
	}
	var passed map[string]any
	for _, l := range strings.Split(got, "\n") {
		if v, ok := strings.CutPrefix(l, "arg={"); ok {
			if err := json.Unmarshal([]byte("{"+v), &passed); err != nil {
				t.Fatal(err)
			}
		}
	}
	if passed["disableAllHooks"] != true || passed["autoMemoryDirectory"] != "/elsewhere" || passed["hooks"] == nil {
		t.Errorf("--settings = %v; want the file's settings with disableAllHooks", passed)
	}
}

func TestMemoryDirTakesHooksOffWithNoSettingsFile(t *testing.T) {
	for _, file := range []string{"", filepath.Join(t.TempDir(), "absent.json")} {
		got, err := askSettings(file)
		if err != nil || got != `{"disableAllHooks":true}` {
			t.Errorf("askSettings(%q) = %s, %v", file, got, err)
		}
	}
	bad := filepath.Join(t.TempDir(), "bad.json")
	if err := os.WriteFile(bad, []byte(`[1]`), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := askSettings(bad); err == nil {
		t.Error("a settings file that holds no object asked anyway")
	}
}

// recordsBirth skips a test where dir's filesystem does not record when a
// directory was made, since the ask then removes nothing.
func recordsBirth(t *testing.T, dir string) {
	t.Helper()
	if _, ok := born(dir); !ok {
		t.Skipf("the filesystem of %s does not record when a directory was made", dir)
	}
}

// The directories the ask made are removed up to the first that holds
// anything, and a directory beside them stays.
func TestMemoryDirRemovesWhatTheAskMade(t *testing.T) {
	root := t.TempDir()
	recordsBirth(t, root)
	keep := filepath.Join(root, "projects", "other")
	if err := os.MkdirAll(keep, 0o755); err != nil {
		t.Fatal(err)
	}
	made := filepath.Join(root, "projects", "p", "memory")
	c, _ := stub(t, `mkdir -p '`+made+`'
echo '{"type":"system","subtype":"init","memory_paths":{"auto":"`+made+`/"}}'`)
	if _, err := c.MemoryDir(Ask{Dir: t.TempDir()}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(root, "projects", "p")); !os.IsNotExist(err) {
		t.Errorf("the project directory the ask made stayed: %v", err)
	}
	if _, err := os.Stat(keep); err != nil {
		t.Errorf("a directory beside it went: %v", err)
	}
}

// A directory made before the ask stays, though making and removing the
// memory directory in it moved its modification time past the ask's start,
// and so does an empty memory directory made before the ask.
func TestRemoveMadeKeepsWhatPredatesTheAsk(t *testing.T) {
	root := t.TempDir()
	recordsBirth(t, root)
	parent, found := filepath.Join(root, "projects", "p"), filepath.Join(root, "found", "memory")
	for _, d := range []string{parent, found} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	// A filesystem's clock can tick as coarsely as 10ms, so wait out a tick
	// before the directory the ask makes.
	time.Sleep(20 * time.Millisecond)
	made := filepath.Join(parent, "memory")
	if err := os.Mkdir(made, 0o755); err != nil {
		t.Fatal(err)
	}
	began, _ := born(made)
	if b, _ := born(parent); !b.Before(began) {
		t.Fatalf("the parent was made at %s, not before the directory in it at %s", b, began)
	}
	removeMade(made, began)
	if _, err := os.Stat(made); !os.IsNotExist(err) {
		t.Errorf("the memory directory the ask made stayed: %v", err)
	}
	if _, err := os.Stat(parent); err != nil {
		t.Errorf("the empty directory made before the ask went: %v", err)
	}
	removeMade(found, began)
	if _, err := os.Stat(found); err != nil {
		t.Errorf("an empty memory directory the ask found went: %v", err)
	}
}

// A directory reached through a link is removed by its real path, and the link
// stays.
func TestMemoryDirRemovesNoLink(t *testing.T) {
	root := t.TempDir()
	recordsBirth(t, root)
	target := filepath.Join(root, "target")
	if err := os.MkdirAll(filepath.Join(target, "p", "memory"), 0o755); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(root, "link")
	if err := os.Symlink(target, link); err != nil {
		t.Fatal(err)
	}
	removeMade(filepath.Join(link, "p", "memory"), time.Now().Add(-time.Minute))
	if _, err := os.Lstat(link); err != nil {
		t.Errorf("the link went: %v", err)
	}
	if _, err := os.Stat(filepath.Join(target, "p")); !os.IsNotExist(err) {
		t.Errorf("the directories under the link stayed: %v", err)
	}
}
