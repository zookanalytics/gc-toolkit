// Package record is the arm on a bead armed to start by itself: the keys it is
// stored in, which this package owns, the arm they decode to, and every write
// to them (docs/gctk-architecture.md, "The ledger"). The arm's verbs and its
// start ask it, in services/gctk/arm, and so does waits, for the arm gctk bead
// holds prints. It asks no other domain.
//
// The keys keep the spellings the arms already in the stores carry, so an arm
// written before this package owned them reads as one written after.
// Readers outside gctk's bead domain still read them as they did, under the
// debt docs/gctk-architecture.md records.
package record

import (
	"encoding/json"
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
	argsKey = ledger.Declare("gc.dispatch_when_ready_args", ledger.String,
		`The formula the arm pours, as the JSON array of sling arguments that names it: ["--on","<formula>"] `+
			`or ["--on=<formula>"], or [] or absent for the target's default formula, read at each start. `+
			"Any other value is a record the start reports as malformed and slings nothing on.")
	armedByKey = ledger.Declare("gc.dispatch_when_ready_armed_by", ledger.String,
		"Who armed the bead.")
	armedAtKey = ledger.Declare("gc.dispatch_when_ready_armed_at", ledger.String,
		"When the bead was armed, in RFC 3339 UTC. The title of every root the start pours for the arm "+
			"carries it, in the token arm:<bead>@<armed at>.")
	reasonKey = ledger.Declare("gc.dispatch_when_ready_reason", ledger.String,
		"Why the bead was armed, as free text.")
	failCountKey = ledger.Declare("gc.dispatch_when_ready_fail_count", ledger.String,
		"The sling attempts the start has made on the arm, as a decimal integer, raised in one write before "+
			"each sling. At the cap, GC_MAX_DISPATCH_SLING_FAILURES (3 by default), the start asks a person "+
			"instead of slinging. Absent means none.")
)

// Arm is a bead's arm, each field as the store holds it, which is what gctk
// bead holds prints: the pool or agent it slings to, the sling arguments that
// name its formula, why and by whom it was armed and when, and the attempts
// made on it. Its methods are the values the start acts on, decoded from them.
type Arm struct {
	Target    string `json:"target,omitempty"`
	Args      string `json:"args,omitempty"`
	Reason    string `json:"reason,omitempty"`
	ArmedBy   string `json:"armed_by,omitempty"`
	ArmedAt   string `json:"armed_at,omitempty"`
	FailCount string `json:"fail_count,omitempty"`

	formula   string
	attempts  int
	malformed string
}

// Formula is the formula the arm names, empty when it names none, so a start
// pours the target's default.
func (a *Arm) Formula() string { return a.formula }

// Attempts is the sling attempts made on the arm.
func (a *Arm) Attempts() int { return a.attempts }

// Capped reports whether the attempts have reached the cap, at which a start
// asks a person instead of slinging.
func (a *Arm) Capped() bool { return a.attempts >= Cap() }

// Malformed says why the stored arm does not decode, and is empty when it
// does. A start slings no malformed arm.
func (a *Arm) Malformed() string { return a.malformed }

// Of is the bead's arm, nil when it carries none: an arm is the presence of its
// target.
func Of(r *ledger.Record) *Arm {
	target, held, _ := targetKey.Get(r) // a String key's stored text always decodes
	if !held {
		return nil
	}
	a := &Arm{Target: target}
	for _, f := range []struct {
		k   ledger.Key[string]
		dst *string
	}{{argsKey, &a.Args}, {reasonKey, &a.Reason}, {armedByKey, &a.ArmedBy}, {armedAtKey, &a.ArmedAt},
		{failCountKey, &a.FailCount}} {
		*f.dst, _, _ = f.k.Get(r)
	}
	var bad []string
	if strings.TrimSpace(a.Target) == "" {
		bad = append(bad, "it names no target")
	}
	if strings.TrimSpace(a.ArmedAt) == "" {
		bad = append(bad, "it records no arm time, which the token on its pours is made from")
	}
	var err error
	if a.formula, err = formulaOf(a.Args); err != nil {
		bad = append(bad, err.Error())
	}
	if a.attempts, err = attemptsOf(a.FailCount); err != nil {
		bad = append(bad, err.Error())
	}
	a.malformed = strings.Join(bad, "; ")
	return a
}

// formulaOf is the formula a stored argument list names: --on and its value, or
// --on=<formula>, or none for an empty or absent list. Any other value is no arm
// the start can pour.
func formulaOf(text string) (string, error) {
	if strings.TrimSpace(text) == "" {
		return "", nil
	}
	var args []string
	if err := json.Unmarshal([]byte(text), &args); err != nil {
		return "", fmt.Errorf("its sling arguments %q do not decode as a JSON array of strings", text)
	}
	switch {
	case len(args) == 0:
		return "", nil
	case len(args) == 2 && args[0] == "--on" && strings.TrimSpace(args[1]) != "":
		return strings.TrimSpace(args[1]), nil
	case len(args) == 1 && strings.HasPrefix(args[0], "--on=") && strings.TrimSpace(args[0][len("--on="):]) != "":
		return strings.TrimSpace(args[0][len("--on="):]), nil
	}
	return "", fmt.Errorf("its sling arguments %s name no formula alone, and an arm pours a formula and passes nothing else", text)
}

// attemptsOf is a stored count of attempts, none when it is absent.
func attemptsOf(text string) (int, error) {
	if strings.TrimSpace(text) == "" {
		return 0, nil
	}
	n, err := strconv.Atoi(strings.TrimSpace(text))
	if err != nil || n < 0 {
		return 0, fmt.Errorf("its attempts %q are not a count", text)
	}
	return n, nil
}

// Present reports whether the bead carries any of the arm's keys, an arm or a
// part one left.
func Present(r *ledger.Record) bool {
	for _, k := range []ledger.Key[string]{targetKey, argsKey, armedByKey, armedAtKey, reasonKey, failCountKey} {
		if _, held, _ := k.Get(r); held {
			return true
		}
	}
	return false
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
func Set(w *ledger.Write, target, formula, reason, armedBy, armedAt string) {
	args, _ := json.Marshal([]string{"--on", formula}) // a list of strings always encodes
	targetKey.Set(w, target)
	argsKey.Set(w, string(args))
	armedByKey.Set(w, armedBy)
	armedAtKey.Set(w, armedAt)
	reasonKey.Set(w, reason)
	failCountKey.Clear(w)
}

// SetAttempts adds the count of attempts to w.
func SetAttempts(w *ledger.Write, n int) { failCountKey.Set(w, strconv.Itoa(n)) }

// Clear adds the removal of the whole arm to w.
func Clear(w *ledger.Write) {
	for _, k := range []ledger.Key[string]{targetKey, argsKey, armedByKey, armedAtKey, reasonKey, failCountKey} {
		k.Clear(w)
	}
}
