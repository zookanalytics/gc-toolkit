package main

import (
	"context"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/source"
)

// `helm-svc probe` answers one question about the binary running it: can it
// read this city's bead stores? It is the readability check on its own, split
// out from `board` because the only other way to ask was to pay for a whole
// gather.
//
// WHY IT IS NOT `board`. The caller this exists for is a build gate deciding
// whether the artifact it published is worth serving — a 5-minute cooldown
// order, where a cross-rig gather (2.7s warm, and unbounded against a wedged
// Dolt) is too much to spend on a question answered by opening one store.
// [source.BeadsSource.Probe] opens exactly one, and the schema-mismatch error
// that motivates this is raised by that open.
//
// WHY A SUBCOMMAND RATHER THAN AN EXIT CODE ON `board`. `board` exits 3 for
// every gather failure, readable-store or not, and it renders. A gate needs the
// question without the render and without the cost.

const probeUsage = `Usage:
  helm-svc probe [--timeout=SECONDS]

  Report whether THIS BINARY can read the city's bead stores — the check the
  board's gather depends on, without the gather. One readable store is enough,
  matching what "helm-svc board" needs to render at all.

  --timeout=SECONDS  Bound the open (default: GC_HELM_PROBE_TIMEOUT, else 10).

Exit codes:
  0  a bead store opened — the board can gather
  2  usage error
  3  no bead store could be opened; the reason is on stderr
`

// probeExit* mirror the board's codes so a caller can switch on either
// identically: 3 is always "this binary could not read the city".
const (
	probeExitOK         = 0
	probeExitUsage      = 2
	probeExitUnreadable = 3
)

// probeStores is the seam the tests drive; production is
// [source.BeadsSource.Probe] over a freshly-opened source.
var probeStores = func(ctx context.Context) error {
	s := source.NewBeadsSource()
	defer func() { _ = s.Close() }()
	return s.Probe(ctx)
}

// runProbe returns a process exit code rather than calling os.Exit so it stays
// testable.
func runProbe(args []string, stdout, stderr io.Writer) int {
	timeout := probeTimeout()
	for len(args) > 0 {
		arg := args[0]
		args = args[1:]
		name, value, hasValue := strings.Cut(arg, "=")
		switch name {
		case "--timeout":
			if !hasValue {
				if len(args) == 0 {
					fmt.Fprintf(stderr, "helm-svc probe: --timeout requires a value\n\n%s", probeUsage)
					return probeExitUsage
				}
				value = args[0]
				args = args[1:]
			}
			n, err := strconv.Atoi(value)
			if err != nil || n <= 0 {
				fmt.Fprintf(stderr, "helm-svc probe: --timeout must be a positive integer, got %q\n\n%s", value, probeUsage)
				return probeExitUsage
			}
			timeout = time.Duration(n) * time.Second
		case "-h", "--help":
			fmt.Fprint(stdout, probeUsage)
			return probeExitOK
		default:
			fmt.Fprintf(stderr, "helm-svc probe: unknown flag %q\n\n%s", arg, probeUsage)
			return probeExitUsage
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	if err := probeStores(ctx); err != nil {
		// The reason is the whole value here — "schema version mismatch" is what
		// tells a gate that a rebuild, not a retry, is the remedy.
		fmt.Fprintf(stderr, "helm-svc probe: cannot read the city's bead stores: %v\n", err)
		return probeExitUnreadable
	}
	fmt.Fprint(stdout, "helm-svc probe: bead stores are readable\n")
	return probeExitOK
}

func probeMain(args []string) {
	os.Exit(runProbe(args, os.Stdout, os.Stderr))
}
