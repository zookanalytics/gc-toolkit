package cli

import (
	"encoding/json"
	"fmt"
	"io"
)

// A look is a verb an order runs to read the city and record one Gas City
// event when it finds something: `worktree salvage`, `session progress` and
// `refinery stuck`. Each prints the same way.

// lookHelpEnd closes a look's help: where its record goes and its exits.
const lookHelpEnd = `The record goes to standard output as the event carries it, and a summary
line to standard error.

exit: 0 every read answered, and the event was recorded when the look found
        something
      1 a read failed or the event was not recorded
      2 usage
      128+N stopped by signal N`

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
