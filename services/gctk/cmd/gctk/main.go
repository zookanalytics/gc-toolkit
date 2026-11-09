// Command gctk is gc-toolkit's command-line interface: the documented,
// structured surface through which agents act on a city. Agents are its users.
// A person can run any command and it should make sense, but no command is
// shaped for ad-hoc human use. The command tree is internal/cli's, and
// docs/gctk-architecture.md is the shape it is built to.
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
// assets/scripts/lifecycle.sh, assets/scripts/merge.sh and
// assets/scripts/epic.sh are bridges: they only exec this binary, and refuse
// the call when there is none to run.
// pr-status-label.sh writes the status: and held: labels in shell and takes
// their values from `gctk pr status`, the one derivation the labels and the
// helm board share, so when the binary is absent or stale it leaves the labels
// unchanged rather than deriving them in shell.
package main

import (
	"os"
	"runtime/debug"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/cli"
)

func main() {
	os.Exit(cli.Run(os.Args[1:], version(), os.Stdout, os.Stderr))
}

// sourceRev is the identity `gc-build.sh gctk` stamps at link time: the tree
// hash of services/gctk at the commit it built from (`git rev-parse HEAD:./`),
// the identity doctor/check-cadence-live compares against the checkout.
// -X main.sourceRev=<hash>.
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
