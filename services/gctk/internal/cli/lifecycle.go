package cli

import (
	"encoding/json"
	"fmt"
	"io"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/lifecycle"
)

// `gctk lifecycle` is the port of assets/scripts/lifecycle.sh: THE writer of
// anchor lifecycle transitions. The CLI is contract-preserving — same verbs,
// same flags, same exit codes, same stdout grammar — because its callers
// (pr-open, merge, pr-facts, mol-refinery-patrol) treat it as an opaque command
// and must not notice which language answers.
//
// Exits: 0 ok; 1 illegal edge / --expect mismatch / bd refusal / usage;
// 2 post-write verification mismatch (or unreadable bead).
//
// CAVEAT (docs/gascity-routing-model.md row 46): clearing an assignee on a bead
// another actor holds in_progress is refused by bd, and the refusal drops the
// WHOLE atomic update — a caller that passes --assignee "" must hold the claim.

// prog is the name every message carries. It stays "lifecycle" rather than
// becoming "gctk": the callers grep these lines, and the subcommand is what
// they invoked.
const prog = "lifecycle"

const lifecycleUsage = `usage: gctk lifecycle transition <bead-id> --to <state> [--expect <state>] [--set k=v]... [--unset k]... [--assignee <a>] [--route <pool>] [--close] [--append-notes <text>] [--json]
       gctk lifecycle state <bead-id>
       gctk lifecycle reopen <bead-id>   # repair a bead closed on a non-closed merge_result
       gctk lifecycle --dump-machine     # the declared machine, for the lifecycle.toml drift test
`

// Lifecycle dispatches the subcommand's verbs. It returns a process exit code
// rather than exiting, so the whole surface stays testable in-process.
func Lifecycle(args []string, stdout, stderr io.Writer) int {
	verb := ""
	if len(args) > 0 {
		verb = args[0]
	}
	switch verb {
	case "transition":
		return cmdTransition(args[1:], stdout, stderr)
	case "state":
		return cmdState(args[1:], stdout, stderr)
	case "reopen":
		return cmdReopen(args[1:], stdout, stderr)
	case "--dump-machine":
		return dumpMachine(stdout)
	default:
		fmt.Fprint(stderr, lifecycleUsage)
		return 1
	}
}

// dumpMachine prints the declared machine in one greppable line-oriented form.
// It exists for the drift test: lifecycle.toml and this binary must agree, and
// the comparison has to read both without a TOML parser on either side.
func dumpMachine(stdout io.Writer) int {
	fmt.Fprintf(stdout, "states %s\n", strings.Join(lifecycle.States, " "))
	fmt.Fprintf(stdout, "human_states %s\n", strings.Join(lifecycle.HumanStates, " "))
	fmt.Fprintf(stdout, "detached_states %s\n", strings.Join(lifecycle.DetachedStates, " "))
	fmt.Fprintf(stdout, "park_route %s\n", lifecycle.ParkRoute)
	fmt.Fprintf(stdout, "closed_states %s\n", strings.Join(lifecycle.ClosedStates, " "))
	for _, e := range lifecycle.Transitions {
		fmt.Fprintf(stdout, "transition %s>%s\n", e.From, e.To)
	}
	return 0
}

// stateOf reads a bead's current state. An absent merge_result is "unanchored";
// a value the machine does not declare returns ok=false with the raw value, so
// the caller can name it in the refusal.
func stateOf(b *gcbd.Bead) (string, bool) {
	mr := b.Meta("merge_result")
	if mr == "" {
		return "unanchored", true
	}
	if lifecycle.IsState(mr) && mr != "unanchored" {
		return mr, true
	}
	return mr, false
}

func cmdState(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 || args[0] == "" {
		fmt.Fprintf(stderr, "%s: state needs a bead id\n", prog)
		return 1
	}
	id := args[0]
	bead := gcbd.New().Show(id)
	if bead == nil {
		fmt.Fprintf(stderr, "%s: %s unreadable — cannot answer its state\n", prog, id)
		return 2
	}
	st, ok := stateOf(bead)
	if !ok {
		fmt.Fprintf(stderr, "%s: %s carries undeclared merge_result '%s' — not a state lifecycle.toml declares\n", prog, id, st)
		return 1
	}
	fmt.Fprintf(stdout, "%s\n", st)
	return 0
}

// kv splits a --set argument the way the shell's ${v%%=*} / ${v#*=} pair did:
// on the FIRST '=', and an argument with no '=' at all yields itself for both
// halves.
func kv(arg string) (key, value string) {
	i := strings.Index(arg, "=")
	if i < 0 {
		return arg, arg
	}
	return arg[:i], arg[i+1:]
}

// transitionResult is the --json payload. Field ORDER is the contract: the jq
// object literal it replaces emitted id, from, to, ok in that sequence, and
// encoding/json follows declaration order.
type transitionResult struct {
	ID   string `json:"id"`
	From string `json:"from"`
	To   string `json:"to"`
	OK   bool   `json:"ok"`
}

type transitionOpts struct {
	to          string
	expect      string
	route       string
	routeSet    bool
	assignee    string
	assigneeSet bool
	closeIt     bool
	notes       string
	notesSet    bool
	asJSON      bool
	sets        []string
	unsets      []string
}

// parseTransition consumes the flag list. A flag whose value is missing takes
// the empty string and ends the scan; the shell it replaces looped forever on
// that input, which is not a contract worth reproducing.
func parseTransition(args []string) (transitionOpts, error) {
	var o transitionOpts
	next := func(i int) (string, int) {
		if i+1 < len(args) {
			return args[i+1], i + 2
		}
		return "", len(args)
	}
	for i := 0; i < len(args); {
		switch args[i] {
		case "--to":
			o.to, i = next(i)
		case "--expect":
			o.expect, i = next(i)
		case "--set":
			var v string
			v, i = next(i)
			o.sets = append(o.sets, v)
		case "--unset":
			var v string
			v, i = next(i)
			o.unsets = append(o.unsets, v)
		case "--assignee":
			o.assignee, i = next(i)
			o.assigneeSet = true
		case "--route":
			o.route, i = next(i)
			o.routeSet = true
		case "--close":
			o.closeIt = true
			i++
		case "--append-notes":
			o.notes, i = next(i)
			o.notesSet = true
		case "--json":
			o.asJSON = true
			i++
		default:
			return o, fmt.Errorf("unknown argument '%s'", args[i])
		}
	}
	return o, nil
}

func cmdTransition(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 || args[0] == "" {
		fmt.Fprintf(stderr, "%s: transition needs a bead id\n", prog)
		return 1
	}
	id := args[0]
	o, err := parseTransition(args[1:])
	if err != nil {
		fmt.Fprintf(stderr, "%s: %v\n", prog, err)
		return 1
	}
	if o.to == "" {
		fmt.Fprintf(stderr, "%s: transition needs --to <state>\n", prog)
		return 1
	}
	if !lifecycle.IsState(o.to) {
		fmt.Fprintf(stderr, "%s: '%s' is not a declared state\n", prog, o.to)
		return 1
	}
	// status and merge_result move together: a close on a non-terminal state (or
	// a terminal state left open) is the closed-means-landed violation (I5).
	if o.closeIt && !lifecycle.IsClosedState(o.to) {
		fmt.Fprintf(stderr, "%s: --close refused with --to %s — '%s' is not a closed state (closed_states: %s); a closed bead on a non-terminal merge_result is invisible to every open-bead consumer\n",
			prog, o.to, o.to, strings.Join(lifecycle.ClosedStates, " "))
		return 1
	}
	if !o.closeIt && lifecycle.IsClosedState(o.to) {
		fmt.Fprintf(stderr, "%s: --to %s requires --close — a closed state must close in the same atomic write, or the bead is left open+%s\n", prog, o.to, o.to)
		return 1
	}
	for _, s := range o.sets {
		switch k, _ := kv(s); k {
		case "merge_result":
			fmt.Fprintf(stderr, "%s: merge_result is written by --to, never by --set\n", prog)
			return 1
		case "gc.routed_to":
			fmt.Fprintf(stderr, "%s: route via --route, never by --set\n", prog)
			return 1
		}
	}

	client := gcbd.New()
	bead := client.Show(id)
	if bead == nil {
		fmt.Fprintf(stderr, "%s: %s unreadable — refusing to transition blind\n", prog, id)
		return 2
	}
	cur, ok := stateOf(bead)
	if !ok {
		fmt.Fprintf(stderr, "%s: %s carries undeclared merge_result '%s'; repair it before transitioning\n", prog, id, cur)
		return 1
	}
	if o.expect != "" && cur != o.expect {
		fmt.Fprintf(stderr, "%s: %s is '%s', not the expected '%s'; transition refused\n", prog, id, cur, o.expect)
		return 1
	}
	if !lifecycle.EdgeLegal(cur, o.to) {
		fmt.Fprintf(stderr, "%s: illegal edge %s -> %s for %s (declared machine: lifecycle/lifecycle.toml)\n", prog, cur, o.to, id)
		return 1
	}
	// The transition's declared routing rides in the same atomic update. Setting
	// routeSet also puts gc.routed_to under the post-write verification below,
	// so a route that fails to clear surfaces as an unverified transition rather
	// than as a silent pool offer. A bead already resting on the park route
	// keeps it: clearing it would retract a bead a person still owns.
	if !o.routeSet {
		switch {
		case lifecycle.IsHumanState(o.to):
			o.route, o.routeSet = "human", true
		case lifecycle.IsDetachedState(o.to):
			if bead.Meta("gc.routed_to") != lifecycle.ParkRoute {
				o.route, o.routeSet = "", true
			}
		}
	}

	var updateArgs []string
	if o.to == "unanchored" {
		updateArgs = append(updateArgs, "--unset-metadata", "merge_result")
	} else {
		updateArgs = append(updateArgs, "--set-metadata", "merge_result="+o.to)
	}
	for _, s := range o.sets {
		updateArgs = append(updateArgs, "--set-metadata", s)
	}
	for _, k := range o.unsets {
		updateArgs = append(updateArgs, "--unset-metadata", k)
	}
	if o.routeSet {
		updateArgs = append(updateArgs, "--set-metadata", "gc.routed_to="+o.route)
	}
	if o.assigneeSet {
		updateArgs = append(updateArgs, "--assignee="+o.assignee)
	}
	if o.closeIt {
		updateArgs = append(updateArgs, "--status=closed")
	}
	if o.notesSet {
		updateArgs = append(updateArgs, "--append-notes", o.notes)
	}

	// ONE atomic write carrying every field of the transition.
	out, err := client.Update(id, updateArgs...)
	if err != nil {
		fmt.Fprintf(stderr, "%s: %s %s -> %s refused by bd (rc=%d): %s\n", prog, id, cur, o.to, gcbd.ExitCode(err), out)
		return 1
	}

	// Re-read and verify every written field; a write that reported success but
	// did not land must never be reported as a transition.
	bead = client.Show(id)
	if bead == nil {
		fmt.Fprintf(stderr, "%s: %s %s -> %s written but the read-back failed; UNVERIFIED\n", prog, id, cur, o.to)
		return 2
	}
	var bad strings.Builder
	got := bead.Meta("merge_result")
	if o.to == "unanchored" {
		if got != "" {
			fmt.Fprintf(&bad, " merge_result='%s'(want absent)", got)
		}
	} else if got != o.to {
		fmt.Fprintf(&bad, " merge_result='%s'(want '%s')", got, o.to)
	}
	for _, s := range o.sets {
		k, v := kv(s)
		if g := bead.Meta(k); g != v {
			fmt.Fprintf(&bad, " %s='%s'(want '%s')", k, g, v)
		}
	}
	for _, k := range o.unsets {
		if g := bead.Meta(k); g != "" {
			fmt.Fprintf(&bad, " %s='%s'(want unset)", k, g)
		}
	}
	if o.routeSet {
		if g := bead.Meta("gc.routed_to"); g != o.route {
			fmt.Fprintf(&bad, " gc.routed_to='%s'(want '%s')", g, o.route)
		}
	}
	if o.assigneeSet {
		if g := bead.AssigneeString(); g != o.assignee {
			fmt.Fprintf(&bad, " assignee='%s'(want '%s')", g, o.assignee)
		}
	}
	if o.closeIt {
		if g := bead.StatusLower(); g != "closed" {
			fmt.Fprintf(&bad, " status='%s'(want closed)", g)
		}
	}
	if o.notesSet && o.notes != "" {
		if !strings.Contains(bead.NotesString(), o.notes) {
			bad.WriteString(" notes(missing appended text)")
		}
	}
	if bad.Len() > 0 {
		fmt.Fprintf(stderr, "%s: %s %s -> %s wrote but did NOT verify:%s\n", prog, id, cur, o.to, bad.String())
		return 2
	}

	if o.asJSON {
		enc := json.NewEncoder(stdout)
		enc.SetEscapeHTML(false)
		if err := enc.Encode(transitionResult{ID: id, From: cur, To: o.to, OK: true}); err != nil {
			fmt.Fprintf(stderr, "%s: %s %s -> %s landed but could not be reported as JSON: %v\n", prog, id, cur, o.to, err)
			return 2
		}
		return 0
	}
	fmt.Fprintf(stdout, "%s: %s %s -> %s\n", prog, id, cur, o.to)
	return 0
}

// cmdReopen repairs a bead closed while its merge_result is a NON-closed state:
// status=open, merge_result untouched. Human-invoked only
// (docs/authority-map.md).
func cmdReopen(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 || args[0] == "" {
		fmt.Fprintf(stderr, "%s: reopen needs a bead id\n", prog)
		return 1
	}
	id := args[0]
	if len(args) > 1 {
		fmt.Fprintf(stderr, "%s: reopen takes no options — it only sets status=open\n", prog)
		return 1
	}
	client := gcbd.New()
	bead := client.Show(id)
	if bead == nil {
		fmt.Fprintf(stderr, "%s: %s unreadable — refusing to reopen blind\n", prog, id)
		return 2
	}
	st, ok := stateOf(bead)
	if !ok {
		fmt.Fprintf(stderr, "%s: %s carries undeclared merge_result '%s'; repair it before reopening\n", prog, id, st)
		return 1
	}
	status := bead.StatusLower()
	if status != "closed" {
		fmt.Fprintf(stderr, "%s: %s is not closed (status='%s') — nothing to repair\n", prog, id, status)
		return 1
	}
	if st == "unanchored" {
		fmt.Fprintf(stderr, "%s: %s is closed with no merge_result — a closed unanchored bead is legal; reopen refused\n", prog, id)
		return 1
	}
	if lifecycle.IsClosedState(st) {
		fmt.Fprintf(stderr, "%s: %s is closed as '%s', a closed state — that close is legitimate; reopen refused\n", prog, id, st)
		return 1
	}

	out, err := client.Update(id, "--status=open")
	if err != nil {
		fmt.Fprintf(stderr, "%s: %s reopen refused by bd (rc=%d): %s\n", prog, id, gcbd.ExitCode(err), out)
		return 1
	}
	// Same read-back discipline as transition: verify status flipped and
	// merge_result stayed put before reporting the repair.
	bead = client.Show(id)
	if bead == nil {
		fmt.Fprintf(stderr, "%s: %s reopen written but the read-back failed; UNVERIFIED\n", prog, id)
		return 2
	}
	var bad strings.Builder
	if g := bead.StatusLower(); g != "open" {
		fmt.Fprintf(&bad, " status='%s'(want open)", g)
	}
	if g := bead.Meta("merge_result"); g != st {
		fmt.Fprintf(&bad, " merge_result='%s'(want '%s' unchanged)", g, st)
	}
	if bad.Len() > 0 {
		fmt.Fprintf(stderr, "%s: %s reopen wrote but did NOT verify:%s\n", prog, id, bad.String())
		return 2
	}
	fmt.Fprintf(stdout, "%s: %s reopened — status closed -> open, merge_result '%s' unchanged\n", prog, id, st)
	return 0
}
