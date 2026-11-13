// Package record is the arm on a bead armed to start by itself: the keys it is
// stored in, which this package owns, the arm they decode to, and every write
// to them (docs/gctk-architecture.md, "The ledger"). The arm's verbs and its
// start ask it, in services/gctk/arm, and so does waits, for the arm gctk bead
// holds prints. It asks no other domain.
//
// The keys keep the spellings deferred-dispatch.sh stored them under, so an
// arm written before this package owned them reads as one written after.
// Readers outside gctk's bead domain still read them as they did, under the
// debt docs/gctk-architecture.md records.
package record

import (
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

var (
	targetKey = ledger.Declare("gc.dispatch_when_ready", ledger.String,
		"The pool or agent an armed bead is slung to once nothing holds it. Its presence is the arm. "+
			"gctk bead arm writes it with the rest of the arm, and gctk bead disarm and the start clear them together.",
		ledger.Warrant("deferred-dispatch-residual"))
	argsKey = ledger.Declare("gc.dispatch_when_ready_args", ledger.JSON[[]string](),
		`The formula the arm pours, as the sling arguments that name it: ["--on","<formula>"], `+
			`or ["--on=<formula>"], or [] or absent for the target's default formula, read at each start. `+
			"Any other value is a record the start reports as malformed and slings nothing on.")
	armedByKey = ledger.Declare("gc.dispatch_when_ready_armed_by", ledger.String,
		"Who armed the bead.")
	armedAtKey = ledger.Declare("gc.dispatch_when_ready_armed_at", ledger.String,
		"When the bead was armed, in RFC 3339 UTC. The title of every root the start pours for the arm "+
			"carries it, in the token arm:<bead>@<armed at>.")
	reasonKey = ledger.Declare("gc.dispatch_when_ready_reason", ledger.String,
		"Why the bead was armed, as free text.")
	failCountKey = ledger.Declare("gc.dispatch_when_ready_fail_count", count,
		"The sling attempts the start has made on the arm, raised in one write before each sling. "+
			"At the cap, GC_MAX_DISPATCH_SLING_FAILURES (3 by default), the start asks a person instead of slinging. "+
			"Absent means none.")
)

// count is the codec of a count of attempts, stored as a decimal integer.
var count = ledger.Codec[int]{
	Type: "int",
	Decode: func(s string) (int, error) {
		n, err := strconv.Atoi(strings.TrimSpace(s))
		if err != nil || n < 0 {
			return 0, fmt.Errorf("%q is not a count of attempts", s)
		}
		return n, nil
	},
	Encode: func(n int) (string, error) { return strconv.Itoa(n), nil },
}

// Arm is a bead's arm, decoded: the pool or agent it slings to, the formula it
// names, empty when it names none, so a start pours the target's default, why
// and by whom it was armed and when, the attempts made on it, and whether they
// have reached the cap. Malformed says why the stored arm does not decode, and
// is empty when it does. A start slings no malformed arm.
type Arm struct {
	Target    string `json:"target"`
	Formula   string `json:"formula,omitempty"`
	Reason    string `json:"reason,omitempty"`
	ArmedBy   string `json:"armed_by,omitempty"`
	ArmedAt   string `json:"armed_at,omitempty"`
	FailCount int    `json:"fail_count"`
	Capped    bool   `json:"capped"`
	Malformed string `json:"malformed,omitempty"`
}

// Of is the bead's arm, nil when it carries none: an arm is the presence of its
// target.
func Of(r *ledger.Record) *Arm {
	target, held, _ := targetKey.Get(r) // a String key's stored text always decodes
	if !held {
		return nil
	}
	a := &Arm{Target: strings.TrimSpace(target)}
	a.Reason, _, _ = reasonKey.Get(r)
	a.ArmedBy, _, _ = armedByKey.Get(r)
	at, _, _ := armedAtKey.Get(r)
	a.ArmedAt = strings.TrimSpace(at)
	var bad []string
	if a.Target == "" {
		bad = append(bad, "it names no target")
	}
	if a.ArmedAt == "" {
		bad = append(bad, "it records no arm time, which the token on its pours is made from")
	}
	args, _, err := argsKey.Get(r)
	if err != nil {
		bad = append(bad, err.Error())
	} else if a.Formula, err = formulaOf(args); err != nil {
		bad = append(bad, err.Error())
	}
	n, _, err := failCountKey.Get(r)
	if err != nil {
		bad = append(bad, err.Error())
	}
	a.FailCount = n
	a.Capped = n >= Cap()
	a.Malformed = strings.Join(bad, "; ")
	return a
}

// formulaOf is the formula a stored argument list names: --on and its value, or
// --on=<formula>, or none for an empty list. Any other list is no arm the start
// can pour.
func formulaOf(args []string) (string, error) {
	switch {
	case len(args) == 0:
		return "", nil
	case len(args) == 2 && args[0] == "--on" && strings.TrimSpace(args[1]) != "":
		return strings.TrimSpace(args[1]), nil
	case len(args) == 1 && strings.HasPrefix(args[0], "--on=") && strings.TrimSpace(args[0][len("--on="):]) != "":
		return strings.TrimSpace(args[0][len("--on="):]), nil
	}
	return "", fmt.Errorf("its sling arguments %q name no formula alone, and an arm pours a formula and passes nothing else", args)
}

// Present reports whether the bead carries any of the arm's keys, an arm or a
// part one left.
func Present(r *ledger.Record) bool {
	for _, held := range []bool{has(targetKey, r), has(argsKey, r), has(armedByKey, r), has(armedAtKey, r),
		has(reasonKey, r), has(failCountKey, r)} {
		if held {
			return true
		}
	}
	return false
}

func has[T any](k ledger.Key[T], r *ledger.Record) bool {
	_, held, _ := k.Get(r)
	return held
}

// Cap is the attempts at which a start asks a person instead of slinging:
// GC_MAX_DISPATCH_SLING_FAILURES, or 3 when it is unset or not a whole number.
func Cap() int {
	n, err := strconv.Atoi(strings.TrimSpace(os.Getenv("GC_MAX_DISPATCH_SLING_FAILURES")))
	if err != nil || n < 0 {
		return 3
	}
	return n
}

// Armed selects the beads that carry an arm.
func Armed() ledger.Selection { return ledger.Carrying(targetKey) }

// Ready reads the armed beads the store reports ready under rule, by bd's own
// readiness.
func Ready(l *ledger.Ledger, rule ledger.ServeRule) ([]*ledger.Record, error) {
	return ledger.Ready(l, targetKey, rule)
}

// Set adds the arm to w: its target, the formula it pours, why and by whom it
// was armed and when, and no attempts.
func Set(w *ledger.Write, a Arm) {
	targetKey.Set(w, a.Target)
	argsKey.Set(w, []string{"--on", a.Formula})
	armedByKey.Set(w, a.ArmedBy)
	armedAtKey.Set(w, a.ArmedAt)
	reasonKey.Set(w, a.Reason)
	failCountKey.Clear(w)
}

// SetAttempts adds the count of attempts to w.
func SetAttempts(w *ledger.Write, n int) { failCountKey.Set(w, n) }

// Clear adds the removal of the whole arm to w.
func Clear(w *ledger.Write) {
	for _, clear := range []func(*ledger.Write){targetKey.Clear, argsKey.Clear, armedByKey.Clear,
		armedAtKey.Clear, reasonKey.Clear, failCountKey.Clear} {
		clear(w)
	}
}
