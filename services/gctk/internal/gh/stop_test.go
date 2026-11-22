package gh_test

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
)

// A landing order's act is stopped at its bound with whatever GitHub call it is
// making (specs/tk-1tfzr71.149/design.md, section 5). A client Within a context
// runs the gh on PATH, here a fake that never answers, and the call returns
// once the context ends.
func TestACallStopsWhenItsContextEnds(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "gh"), []byte("#!/bin/sh\nexec sleep 30\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	ctx, cancel := context.WithTimeout(context.Background(), 300*time.Millisecond)
	defer cancel()

	start := time.Now()
	_, err := gh.New("github.com").Within(ctx).Login()
	if elapsed := time.Since(start); elapsed > 5*time.Second {
		t.Errorf("the call returned after %s, long past its context's end", elapsed.Round(time.Millisecond))
	}
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("a call stopped at its bound returned %v, want the bound's error", err)
	}
	if gh.Refused(err) {
		t.Fatalf("a stopped call read as GitHub's refusal: %v", err)
	}
}
