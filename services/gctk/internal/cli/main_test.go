package cli

import (
	"os"
	"testing"
)

// The cli suites drive the lifecycle and pr status gathering paths through a
// stubbed `gc` on PATH — the same `gc bd` seam the shell acceptance exercises.
// GC_NO_API=1 keeps the read seam on that subprocess path, so the stub answers
// rather than a live supervisor the ambient session happens to point at; the
// supervisor-API read path is covered in internal/gcbd and internal/daemon, and
// the pr status anchor row's read through it by
// TestPRStatusAnchorRowIsTheSupervisorsCopy, which turns GC_NO_API off against
// a fake supervisor.
func TestMain(m *testing.M) {
	if err := os.Setenv("GC_NO_API", "1"); err != nil {
		panic(err)
	}
	os.Exit(m.Run())
}
