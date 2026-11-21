package cli

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/signal"
	"syscall"
)

// A look is a verb an order runs to read the city and record one Gas City
// event when it finds something: `session progress` and `refinery stuck`. Each
// prints the same way.

// lookHelpEnd closes a look's help: where its record goes and its exits.
const lookHelpEnd = `The record goes to standard output as the event carries it, and a summary
line to standard error.

exit: 0 every read answered, and the event was recorded when the look found
        something
      1 a read failed or the event was not recorded
      2 usage
      128+N stopped by signal N`

// stopOnSignal returns the context a look runs under, which a SIGTERM or
// SIGINT this process is sent ends, and release, which stops listening for
// them and returns the one that came, or 0 when none did. A look's store reads
// run in process groups of their own, out of reach of a signal sent to this
// process's group, which is how an order runner stops a look that outlives its
// timeout and how a terminal delivers Ctrl-C. They end when the look's context
// does, so a look stopped this way has ended them by the time it returns, and
// it then exits with 128 plus the signal, writing nothing more. A signal this
// process inherited as ignored stays ignored.
func stopOnSignal() (context.Context, func() syscall.Signal) {
	stop := make(chan os.Signal, 1)
	for _, s := range []os.Signal{syscall.SIGTERM, syscall.SIGINT} {
		if !signal.Ignored(s) {
			signal.Notify(stop, s)
		}
	}
	ctx, cancel := context.WithCancel(context.Background())
	var got os.Signal
	watched := make(chan struct{})
	go func() {
		defer close(watched)
		select {
		case got = <-stop:
			cancel()
		case <-ctx.Done():
		}
	}()
	return ctx, func() syscall.Signal {
		cancel()
		<-watched
		signal.Stop(stop)
		// A signal that arrived as the look finished is still this process's to
		// take.
		if got == nil {
			select {
			case got = <-stop:
			default:
			}
		}
		sig, _ := got.(syscall.Signal)
		return sig
	}
}

// reportLook prints a look's record on standard output, when it composed one,
// a summary line on standard error, saying whether the event was recorded,
// and each failure, and returns the look's exit.
func reportLook(verb string, record any, summary string, found, recorded bool, failures []string, stdout, stderr io.Writer) error {
	if record != nil {
		if err := json.NewEncoder(stdout).Encode(record); err != nil {
			fmt.Fprintf(stderr, "gctk %s: the record could not be printed: %v\n", verb, err)
		}
		state := "nothing recorded"
		switch {
		case recorded:
			state = "recorded"
		case found:
			state = "not recorded"
		}
		fmt.Fprintf(stderr, "gctk %s: %s; %s\n", verb, summary, state)
	}
	for _, f := range failures {
		fmt.Fprintf(stderr, "gctk %s: %s\n", verb, f)
	}
	if len(failures) > 0 {
		return exit(1)
	}
	return nil
}
