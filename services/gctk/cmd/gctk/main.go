// Command gctk is the compiled data plane of the merge cadence.
//
// SCOPE (specs/2026-08-review-gates/gctk-promotion.md). Shell stays the pack's
// lingua franca: anything an agent pastes, anything that must read as
// documentation, anything under ~150 lines. gctk takes the merge-cadence
// cluster alone — highest stakes, pure data-plane, and already invoked by its
// callers as an opaque CLI, so the language behind the command is invisible to
// them.
//
// Each subcommand keeps the byte-identical CLI of the script it replaces: same
// flags, same exit codes, same stdout grammar. The scripts' own .test.sh
// stub-harness suites are the acceptance bar, and they pass unmodified because
// gctk shells out to gc/bd/gh exactly as the scripts did rather than linking
// the beads library. Same observability, same stubs, same permissions surface.
//
// Ported so far: lifecycle. The rest of the cluster (gate-ensure, pr-open,
// merge, pr-facts, convoy-graduate, signoff) still runs as shell, and
// assets/scripts/lifecycle.sh remains as the fallback for a city whose gctk
// build has not landed yet.
package main

import (
	"fmt"
	"os"
	"runtime/debug"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/cli"
)

const topUsage = `Usage:
  gctk lifecycle <verb> [flags]   anchor lifecycle transitions (lifecycle/lifecycle.toml)
  gctk version                    the revision this binary was built from

Run "gctk lifecycle" for that subcommand's verbs.
`

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

func run(args []string, stdout, stderr *os.File) int {
	if len(args) == 0 {
		fmt.Fprint(stderr, topUsage)
		return 2
	}
	switch args[0] {
	case "lifecycle":
		return cli.Lifecycle(args[1:], stdout, stderr)
	case "version":
		fmt.Fprintln(stdout, version())
		return 0
	case "-h", "--help", "help":
		fmt.Fprint(stdout, topUsage)
		return 0
	default:
		fmt.Fprintf(stderr, "gctk: unknown subcommand %q\n\n%s", args[0], topUsage)
		return 2
	}
}

// sourceRev is the identity gc-gctk-build.sh stamps at link time: the tree
// hash of services/gctk at the commit it built from (`git rev-parse HEAD:./`),
// the same value it records as binary_rev. -X main.sourceRev=<hash>.
var sourceRev string

// version reports the revision this binary was built from. It is what
// lifecycle.sh and doctor/check-cadence-live compare against the checkout: a
// cadence running a binary built from other sources is the failure mode the
// build order's ~5m lag makes possible, and the operator has no other way to
// see it. The build order's stamp wins because it names the module's own
// sources; the toolchain's VCS stamp (a commit hash) is the fallback for a
// build made by hand.
//
// A build with neither — `go build` outside a repository, or with
// -buildvcs=false — reports "unknown" rather than inventing a revision.
func version() string {
	if sourceRev != "" {
		return sourceRev
	}
	info, ok := debug.ReadBuildInfo()
	if !ok {
		return "unknown"
	}
	rev, dirty := "", false
	for _, s := range info.Settings {
		switch s.Key {
		case "vcs.revision":
			rev = s.Value
		case "vcs.modified":
			dirty = s.Value == "true"
		}
	}
	if rev == "" {
		return "unknown"
	}
	if dirty {
		return rev + "-dirty"
	}
	return rev
}
