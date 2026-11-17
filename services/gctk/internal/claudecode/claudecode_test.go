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
// Claude Code finish writing its config file, not killed outright.
func TestMemoryDirEndsAnAskThatDoesNotAnswer(t *testing.T) {
	c, log := stub(t, `trap 'echo stopped >> "$(dirname "$0")/log"; exit 143' TERM
while :; do sleep 0.05; done`)
	c.timeout = 200 * time.Millisecond
	start := time.Now()
	_, err := c.MemoryDir(Ask{Dir: t.TempDir()})
	if err == nil || !strings.Contains(err.Error(), "did not answer within") {
		t.Fatalf("MemoryDir error = %v; want a timeout", err)
	}
	if time.Since(start) > 5*time.Second {
		t.Errorf("the ask ran %s past its bound", time.Since(start))
	}
	if got := logged(t, log); !strings.Contains(got, "stopped\n") {
		t.Errorf("the ask was not stopped with SIGTERM:\n%s", got)
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

// The directories the ask made are removed up to the first that holds
// anything or predates the ask, and a directory the ask found stays.
func TestMemoryDirRemovesWhatTheAskMade(t *testing.T) {
	root := t.TempDir()
	keep := filepath.Join(root, "projects", "other")
	if err := os.MkdirAll(keep, 0o755); err != nil {
		t.Fatal(err)
	}
	made := filepath.Join(root, "projects", "p", "memory")
	c, _ := stub(t, `mkdir -p '`+made+`'
echo '{"type":"system","subtype":"init","memory_paths":{"auto":"`+made+`/"}}'`)
	old := time.Now().Add(-time.Hour)
	if err := os.Chtimes(filepath.Join(root, "projects"), old, old); err != nil {
		t.Fatal(err)
	}
	if _, err := c.MemoryDir(Ask{Dir: t.TempDir()}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(root, "projects", "p")); !os.IsNotExist(err) {
		t.Errorf("the project directory the ask made stayed: %v", err)
	}
	if _, err := os.Stat(keep); err != nil {
		t.Errorf("a directory beside it went: %v", err)
	}

	found := filepath.Join(root, "found", "memory")
	if err := os.MkdirAll(found, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(found, old, old); err != nil {
		t.Fatal(err)
	}
	c, _ = stub(t, `echo '{"type":"system","subtype":"init","memory_paths":{"auto":"`+found+`/"}}'`)
	if _, err := c.MemoryDir(Ask{Dir: t.TempDir()}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(found); err != nil {
		t.Errorf("an empty memory directory the ask found went: %v", err)
	}
}

// A directory reached through a link is removed by its real path, and the link
// stays.
func TestMemoryDirRemovesNoLink(t *testing.T) {
	root := t.TempDir()
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
