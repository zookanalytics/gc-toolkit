package cli

import (
	"fmt"
	"io"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/lane"
)

// `gctk lane-state` is assets/scripts/lane-state.sh's CLI: same verb, same
// flags, same exit codes (0 green, 1 not green or usage, 2 the store would not
// read), same stderr lines, and nothing ever on stdout. lane-state.sh hands its
// call here through gctk-resolve.sh and keeps its own shell as the fallback, so
// lane-state.test.sh is the acceptance bar and runs against both. The
// derivation itself is internal/lane, which `gctk merge` calls in-process.

// laneStateProg is the name every warning carries. It stays "lane-state": the
// callers grep these lines, and the script is what they invoked.
const laneStateProg = "lane-state"

// laneStateUsage keeps the script's own name: the line is the contract its
// callers see, and the shell fallback prints exactly this one.
const laneStateUsage = "usage: lane-state.sh green --anchor <id> --lane <lane> [--no-remote]\n"

// newLaneDeps builds the store and the GitHub fallback the command derives
// from. A variable so a test drives LaneState against gcbdtest.Fake and fake
// remotes without a subprocess.
var newLaneDeps = func() (gcbd.Store, lane.Remote) {
	return gcbd.New(), lane.Remote{Origin: lane.GitOrigin{}, Approver: lane.GHApprover{}}
}

// LaneState dispatches the subcommand's verbs, returning a process exit code so
// the surface stays testable in-process. stdout is never written.
func LaneState(args []string, _, stderr io.Writer) int {
	if len(args) == 0 {
		fmt.Fprint(stderr, laneStateUsage)
		return 1
	}
	switch args[0] {
	case "green":
		return laneStateGreen(args[1:], stderr)
	default:
		fmt.Fprintf(stderr, "%s: unknown verb '%s'\n", laneStateProg, args[0])
		fmt.Fprint(stderr, laneStateUsage)
		return 1
	}
}

// laneStateGreen parses cmd_green's flags exactly as the shell did: a
// value-taking flag takes whatever token follows it, and one with no token at
// all (`shift 2` failing) is the usage line alone, exit 1.
func laneStateGreen(args []string, stderr io.Writer) int {
	anchor, laneName, noRemote := "", "", false
	for i := 0; i < len(args); {
		switch args[i] {
		case "--anchor", "--lane":
			if i+1 >= len(args) {
				fmt.Fprint(stderr, laneStateUsage)
				return 1
			}
			if args[i] == "--anchor" {
				anchor = args[i+1]
			} else {
				laneName = args[i+1]
			}
			i += 2
		case "--no-remote":
			noRemote = true
			i++
		default:
			fmt.Fprintf(stderr, "%s: unknown arg '%s'\n", laneStateProg, args[i])
			fmt.Fprint(stderr, laneStateUsage)
			return 1
		}
	}
	if anchor == "" || laneName == "" {
		fmt.Fprintf(stderr, "%s: green needs --anchor and --lane\n", laneStateProg)
		return 1
	}

	store, remote := newLaneDeps()
	v, err := lane.Green(store, remote, anchor, laneName, noRemote)
	if err != nil {
		fmt.Fprintf(stderr, "%s: %v\n", laneStateProg, err)
	}
	return int(v)
}
