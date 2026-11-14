package gh_test

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
)

// A cached client's reads ask gh to answer from its own response cache, and
// its merge requests ask GitHub, since a cached answer to a request is no
// answer to this one.
func TestACachedClientsReadsTakeGhsCache(t *testing.T) {
	c, r := client(
		[2]string{"user", `{"login":"zook-bot","id":1}`},
		[2]string{"mergePullRequest", `{"data":{"x":{}}}`},
	)
	cached := c.Cached(5 * time.Minute)
	if _, err := cached.Login(); err != nil {
		t.Fatal(err)
	}
	if err := cached.MergePullRequest("PR_kw1", "abc"); err != nil {
		t.Fatal(err)
	}
	if _, err := c.Login(); err != nil {
		t.Fatal(err)
	}
	if got := strings.Join(r.calls[0].args, " "); got != "api --hostname github.com user --cache 5m0s" {
		t.Errorf("the cached read asks %q", got)
	}
	if got := strings.Join(r.calls[1].args, " "); strings.Contains(got, "--cache") {
		t.Errorf("the merge request %q takes a cached answer", got)
	}
	if got := strings.Join(r.calls[2].args, " "); got != "api --hostname github.com user" {
		t.Errorf("the client Cached copied from asks %q", got)
	}
	for _, age := range []time.Duration{0, -time.Minute, 500 * time.Millisecond} {
		c, r := client([2]string{"user", `{"login":"zook-bot","id":1}`})
		if _, err := c.Cached(age).Login(); err != nil {
			t.Fatal(err)
		}
		if got := strings.Join(r.calls[0].args, " "); got != "api --hostname github.com user" {
			t.Errorf("Cached(%s) reads %q, want a read that asks GitHub", age, got)
		}
	}
}

// stubGH puts a gh on PATH that runs body.
func stubGH(t *testing.T, body string) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "gh"), []byte("#!/bin/sh\n"+body), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	return dir
}

// A call through a client with a context ends when the context does, with the
// context's cause, and the whole process group it started is gone by then: a
// stop that killed gh alone would leave a child it started holding the call's
// output.
func TestAClientWithAContextStopsItsCalls(t *testing.T) {
	dir := stubGH(t, "sleep 30 &\necho $$ > \"$STUB_GROUP\"\nwait\n")
	group := filepath.Join(dir, "group")
	t.Setenv("STUB_GROUP", group)

	const deadline = 500 * time.Millisecond
	ctx, cancel := context.WithTimeout(context.Background(), deadline)
	defer cancel()
	start := time.Now()
	_, err := gh.NewContext(ctx, "github.com").Login()
	took := time.Since(start)
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Errorf("Login = %v, want the deadline's error", err)
	}
	if took > deadline+1500*time.Millisecond {
		t.Errorf("Login returned %s after it began, past its %s deadline", took, deadline)
	}
	raw, err := os.ReadFile(group)
	if err != nil {
		return // the deadline came before the stub started, so no call ran
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(raw)))
	if err != nil {
		t.Fatalf("the stub wrote %q as its process group", raw)
	}
	gone := time.Now().Add(5 * time.Second)
	for syscall.Kill(-pid, 0) == nil {
		if time.Now().After(gone) {
			_ = syscall.Kill(-pid, syscall.SIGKILL)
			t.Fatalf("the call's process group %d outlived the call", pid)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

// A context that is already done starts no call.
func TestADoneContextStartsNoCall(t *testing.T) {
	dir := stubGH(t, "touch \"$STUB_RAN\"\necho '{\"login\":\"zook-bot\"}'\n")
	ran := filepath.Join(dir, "ran")
	t.Setenv("STUB_RAN", ran)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := gh.NewContext(ctx, "github.com").Login(); !errors.Is(err, context.Canceled) {
		t.Errorf("Login = %v, want the cancellation", err)
	}
	if _, err := os.Stat(ran); err == nil {
		t.Error("the call started after its context was done")
	}
	// The same stub answers a client whose context runs.
	got, err := gh.NewContext(context.Background(), "github.com").Login()
	if err != nil || got != "zook-bot" {
		t.Fatalf("Login = %q, %v, want zook-bot", got, err)
	}
}
