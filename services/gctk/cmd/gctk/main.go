// Command gctk is gc-toolkit's command-line interface: the documented,
// structured surface through which agents act on a city. Agents are its users.
// A person can run any command and it should make sense, but no command is
// shaped for ad-hoc human use.
//
// SCOPE (services/gctk/README.md). gctk is where gc-toolkit's logic for acting
// on a city belongs, and each command is built for the long-term shape of the
// CLI. Logic gctk does not hold yet runs as shell scripts, among them the rest
// of the merge cadence: gate-ensure, pr-open, pr-facts and signoff. A
// dependency is taken or declined on its merits; keeping the binary free of
// them is not a goal.
//
// A shell script that only execs a gctk command is a bridge for callers that
// do not call gctk yet, and it goes away once they do. A bridge is not a
// contract gctk keeps: matching a script's flags and output byte for byte is
// not a goal, and neither are tests that pin usage text.
// assets/scripts/lifecycle.sh and assets/scripts/merge.sh are bridges: they
// only exec this binary, and refuse the call when there is none to run.
// pr-status-label.sh writes the status: label in shell and takes its value from
// `gctk pr-status`, the one derivation the label and the helm board share, so
// when the binary is absent or stale it leaves the label unchanged rather than
// deriving one in shell.
package main

import (
	"fmt"
	"os"
	"runtime/debug"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/cli"
)

const topUsage = `Usage:
  gctk lifecycle <verb> [flags]   anchor lifecycle transitions (lifecycle/lifecycle.toml)
  gctk merge [flags]              merge cadence arm 2 — the single writer of merged truth (assets/scripts/merge.sh)
  gctk pr-status <verb> [flags]   PR status working|merging|needs-review|needs-attention (services/gctk/prstatus)
  gctk rig <verb> [flags]         actions on the rig: run a check's command and record its result against the commit
  gctk version                    the revision this binary was built from

Run "gctk lifecycle", "gctk pr-status" or "gctk rig" for that subcommand's verbs.
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
	case "merge":
		return cli.Merge(args[1:], stdout, stderr)
	case "pr-status":
		return cli.PRStatus(args[1:], stdout, stderr)
	case "rig":
		return cli.Rig(args[1:], stdout, stderr)
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

// sourceRev is the identity `gc-build.sh gctk` stamps at link time: the tree
// hash of services/gctk at the commit it built from (`git rev-parse HEAD:./`),
// the identity gctk-resolve.sh and doctor/check-cadence-live compare against
// the checkout. -X main.sourceRev=<hash>.
var sourceRev string

// version reports the revision this binary was built from. It is what
// doctor/check-cadence-live compares against the checkout: a
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
