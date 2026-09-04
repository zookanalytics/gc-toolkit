package cli

import (
	"encoding/json"
	"fmt"
	"io"
	"strings"
	"time"
	"unicode/utf8"

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

const lifecycleUsage = `usage: gctk lifecycle transition <bead-id> --to <state> [--expect <state>] [--set k=v]... [--set-dated k=<value>@<oid>]... [--unset k]... [--assignee <a>] [--route <pool>] [--takeaway <text>] [--close] [--append-notes <text>] [--json]
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
	fmt.Fprintf(stdout, "takeaway_max %d\n", lifecycle.TakeawayMax)
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

// squeezeSpace collapses every run of POSIX whitespace to one space and trims
// the ends, which is what `tr -s '[:space:]' ' '` plus the shell's one-space
// trims did. It runs BEFORE the empty check: whitespace normalizes to nothing,
// and the flag's presence alone is not a takeaway.
func squeezeSpace(s string) string {
	isSpace := func(r rune) bool {
		switch r {
		case ' ', '\t', '\n', '\v', '\f', '\r':
			return true
		}
		return false
	}
	var b strings.Builder
	prevSpace := false
	for _, r := range s {
		if isSpace(r) {
			prevSpace = true
			continue
		}
		if prevSpace && b.Len() > 0 {
			b.WriteByte(' ')
		}
		prevSpace = false
		b.WriteRune(r)
	}
	return b.String()
}

// normalizeTakeaway applies the two gates the board's NEEDS cell imposes,
// returning the text to write or the lines that refuse it.
//
// The flag's presence is not a takeaway: whitespace normalizes to nothing, and
// an empty one writes the exact row the park guard refuses — the board renders a
// person-routed row carrying no takeaway as having no question recorded.
// gc-helm.sh, the other writer of that cell, refuses it the same way.
//
// Over the cap it REJECTS rather than truncating: only the author knows which
// clause is the headline. The length is CODEPOINTS, which is what both renderers
// measure — counting bytes would refuse a takeaway well inside the cap the
// moment it carried an em dash.
func normalizeTakeaway(s string) (string, []string) {
	s = squeezeSpace(s)
	if s == "" {
		return "", []string{
			"--takeaway is empty; it renders as the board's NEEDS cell, and a row with an empty one reads as 'routed to you — no question recorded'",
			"give it the one sentence the operator needs, or drop the flag.",
		}
	}
	if n := utf8.RuneCountInString(s); n > lifecycle.TakeawayMax {
		return "", []string{
			fmt.Sprintf("--takeaway is %d chars; the cap is %d", n, lifecycle.TakeawayMax),
			"it renders as the board's NEEDS cell — one line, read at a glance. Cut it to the single sentence the operator needs and put the rest in --append-notes.",
		}
	}
	return s, nil
}

// now is the clock the @<since> component is stamped from. A variable so a test
// can pin it; every caller reads UTC.
var now = func() time.Time { return time.Now().UTC() }

// datedSince is the `since` write rule, in one place so two writers cannot
// disagree about when a turn began: keep the existing instant while both the
// value and the oid hold, and stamp the current one when either differs. A
// value not already in the three-component shape has no instant to keep.
func datedSince(have, want string) string {
	if rest, ok := strings.CutPrefix(have, want+"@"); ok {
		if rest != "" && !strings.Contains(rest, "@") {
			return rest
		}
	}
	return now().Format("2006-01-02T15:04:05Z")
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
	dated       []string
	unsets      []string
	takeaway    string
	takeawaySet bool
}

// parseTransition consumes the flag list. A value-taking flag with no following
// token is a malformed invocation and returns an error: the empty string it
// would otherwise take drops --expect's compare-and-swap guard, so a truncated
// command must fail rather than transition unguarded. An explicitly supplied
// empty argument (--assignee '' clears the assignee) is a real token and is
// preserved.
func parseTransition(args []string) (transitionOpts, error) {
	var o transitionOpts
	var missing string // a flag consumed with no value token following it
	next := func(i int) (string, int) {
		if i+1 < len(args) {
			return args[i+1], i + 2
		}
		missing = args[i]
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
		case "--set-dated":
			var v string
			v, i = next(i)
			o.dated = append(o.dated, v)
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
		case "--takeaway":
			o.takeaway, i = next(i)
			o.takeawaySet = true
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
	if missing != "" {
		return o, fmt.Errorf("flag %s needs a value", missing)
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
	// `unanchored` is the one exception: lifecycle.toml declares its status
	// "open|closed", so it MAY close (the terminal a non-anchor takes) without
	// being a closed_state that MUST close. The two guards split on exactly that.
	if o.closeIt && !lifecycle.IsClosedState(o.to) && o.to != "unanchored" {
		fmt.Fprintf(stderr, "%s: --close refused with --to %s — '%s' is not a closed state (closed_states: %s) and not unanchored; a closed bead on a non-terminal merge_result is invisible to every open-bead consumer\n",
			prog, o.to, o.to, strings.Join(lifecycle.ClosedStates, " "))
		return 1
	}
	if !o.closeIt && lifecycle.IsClosedState(o.to) {
		fmt.Fprintf(stderr, "%s: --to %s requires --close — a closed state must close in the same atomic write, or the bead is left open+%s\n", prog, o.to, o.to)
		return 1
	}
	// `merged` carries the evidence its own definition names: lifecycle.toml
	// declares [states.merged] meaning = "landed; merged_sha recorded". Require
	// that sha in the same atomic write, so the state cannot be entered with no
	// landing to point at — the closed-implies-landed violation
	// doctor/check-closed-implies-landed reports after the fact, refused here at
	// the write instead. Every sanctioned writer (merge.sh, pr-facts.sh,
	// mol-refinery-patrol) already passes --set merged_sha=<oid>; what this
	// refuses is the bead with no PR that never had one, whose terminal is
	// `--to unanchored --close`, not a false landing.
	if o.to == "merged" {
		haveSha := false
		for _, s := range o.sets {
			if k, v := kv(s); k == "merged_sha" && v != "" {
				haveSha = true
			}
		}
		if !haveSha {
			fmt.Fprintf(stderr, "%s: --to merged requires --set merged_sha=<oid> — 'merged' means 'landed; merged_sha recorded' (lifecycle.toml), so it cannot be entered without the landing that defines it. A bead with no PR has not landed: close it with '%s transition %s --to unanchored --close' (a closed unanchored bead is legal), not --to merged\n", prog, prog, id)
			return 1
		}
	}
	// A human state is a bead waiting on a person, so it must name one. An
	// omitted --route takes the default; an EMPTY one is the write that leaves a
	// bead waiting on nobody — no queue holds it and no invariant can name it.
	if lifecycle.IsHumanState(o.to) {
		if !o.routeSet {
			o.route, o.routeSet = lifecycle.ParkRoute, true
		}
		if o.route == "" {
			fmt.Fprintf(stderr, "%s: --to %s requires a route — '%s' is a human state (human_states: %s) and an empty gc.routed_to leaves the bead waiting on nobody\n",
				prog, o.to, o.to, strings.Join(lifecycle.HumanStates, " "))
			return 1
		}
	}
	for _, s := range append(append([]string{}, o.sets...), o.dated...) {
		switch k, _ := kv(s); k {
		case "merge_result":
			fmt.Fprintf(stderr, "%s: merge_result is written by --to, never by --set\n", prog)
			return 1
		case "gc.routed_to":
			fmt.Fprintf(stderr, "%s: route via --route, never by --set\n", prog)
			return 1
		case "gc.takeaway", "gc.takeaway_at", "gc.takeaway_by", "gc.takeaway_settled":
			fmt.Fprintf(stderr, "%s: the takeaway stamp is written by --takeaway, never by --set\n", prog)
			return 1
		}
	}
	// A dated key's ARGUMENT carries the two components its writer decided; this
	// command owns the third. Refusing a malformed one here is what keeps the
	// preserve rule decidable: it compares on value and oid, and cannot find them
	// in a value that does not have exactly those two parts.
	for _, d := range o.dated {
		if !strings.Contains(d, "=") {
			fmt.Fprintf(stderr, "%s: --set-dated '%s' is not k=<value>@<oid>\n", prog, d)
			return 1
		}
		_, dv := kv(d)
		if strings.Count(dv, "@") != 1 || strings.HasSuffix(dv, "@") {
			fmt.Fprintf(stderr, "%s: --set-dated '%s' must carry exactly <value>@<oid>; lifecycle.sh appends the @<since>\n", prog, d)
			return 1
		}
	}
	// A key written by --set/--set-dated must be named once on the set side and
	// not also unset. The update assembly (below) appends every --set, then the
	// resolved --set-dated, then every --unset, so a key named twice on the set
	// side, or set and unset together, resolves by argument order and the
	// post-write read-back can never verify a value it was told to write twice or
	// to both write and clear. Both shapes reach the closed-with-no-landing (I5)
	// state this transition refuses: `--to merged --set merged_sha=<oid> --set
	// merged_sha=` and `--to merged --set merged_sha=<oid> --unset merged_sha`
	// each satisfy the merged_sha guard above on the first token, then a later
	// empty set or the unset wins. Repeated --unset of one key is idempotent — it
	// lands the same absence in any order — so it stays allowed. Reject the
	// ambiguity before any write rather than leave the bead half-applied.
	var setKeys []string
	for _, s := range append(append([]string{}, o.sets...), o.dated...) {
		k, _ := kv(s)
		setKeys = append(setKeys, k)
	}
	for i := range setKeys {
		for j := i + 1; j < len(setKeys); j++ {
			if setKeys[i] == setKeys[j] {
				fmt.Fprintf(stderr, "%s: '%s' is set more than once (--set/--set-dated) — the write applies them in order, so the surviving value turns on argument order and the read-back can never verify; set each key once\n", prog, setKeys[i])
				return 1
			}
		}
		for _, uk := range o.unsets {
			if setKeys[i] == uk {
				fmt.Fprintf(stderr, "%s: '%s' is both set and unset in one call — the write applies --set then --unset, so the result depends on argument order and can never verify; drop one\n", prog, setKeys[i])
				return 1
			}
		}
	}
	if o.takeawaySet {
		text, refusal := normalizeTakeaway(o.takeaway)
		if refusal != nil {
			for _, line := range refusal {
				fmt.Fprintf(stderr, "%s: %s\n", prog, line)
			}
			return 1
		}
		o.takeaway = text
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
	// --to unanchored --close unsets merge_result AND closes in one write. That
	// is a bead's terminal only from a state that is not a live anchor:
	// "unanchored" (a task that never anchored a PR) or "held" (a sitting whose
	// ruling concluded). Every other state with an edge to unanchored is a live
	// merge anchor the cadence drives, or a PR-derived human state a person must
	// repair and re-engage; the same call would clear its merge_result and close
	// it in one write, dropping it from the open-anchor readers still waiting on
	// it while recording a terminal it never reached (I5). Those reach unanchored
	// by their own edge, which leaves the bead open, and close from there. Keyed
	// on the CURRENT state read off the bead, so an omitted --expect is held to
	// the same rule as a named one.
	if o.closeIt && o.to == "unanchored" && cur != "unanchored" && cur != "held" {
		fmt.Fprintf(stderr, "%s: --close refused: %s is '%s' — a one-step --to unanchored --close is the terminal only from 'unanchored' or 'held', and '%s' is a live or human-queued anchor whose merge_result this would clear while closing it, hiding it from every open-anchor reader. Take it to unanchored by its own edge (which leaves it open), then close.\n", prog, id, cur, cur)
		return 1
	}
	// A bead already resting on the park route keeps it. No pool claims that
	// value, and clearing it would retract a bead a person still owns. Setting
	// routeSet also puts gc.routed_to under the post-write verification below,
	// so a route that fails to clear surfaces as an unverified transition rather
	// than as a silent pool offer. A human state never reaches here: the guard
	// above set routeSet on arguments alone.
	if !o.routeSet && lifecycle.IsDetachedState(o.to) {
		if bead.Meta("gc.routed_to") != lifecycle.ParkRoute {
			o.route, o.routeSet = "", true
		}
	}

	// The unheld half of the same property. An anchor's assignee is the polecat
	// handoff pointer, and mol-refinery-patrol's find-work enumerates by it: a
	// bead carrying a merge_result found in that queue is flagged, never taken,
	// so a survivor sits there for the life of the anchor with nothing converging
	// it. Setting assigneeSet puts the clear under the post-write read-back, the
	// same way the route arm does.
	//
	// Only at status=open. That is the status every detached state declares, and
	// it is the term of bd's anti-steal guard that decides whether the edit lands
	// at all: against an in_progress bead the clear is refused and takes the whole
	// atomic update down with it. A live claim there is the retraction this must
	// not perform. An assignee already empty emits no flag, so a healthy
	// transition issues the same bd call it always did.
	if !o.assigneeSet && lifecycle.IsDetachedState(o.to) {
		if bead.AssigneeString() != "" && bead.StatusLower() == "open" {
			o.assignee, o.assigneeSet = "", true
		}
	}

	// A park must NAME what is owed. The helm board spends an anchor's
	// gc.takeaway as its NEEDS sentence and, finding none on a row routed to a
	// person, reports that nobody recorded a question — so a route to the park
	// sentinel without a takeaway hands the operator a row it cannot read. The
	// sentence rides the same atomic write as the route; a bead that already
	// carries one satisfies this, which is the sitting that stamped its hold
	// before transitioning. Only the WRITE is guarded: a call that names the park
	// route a bead already rests on establishes no park, so it leaves the question
	// with whoever asked it. Observers do exactly that — gate-ensure.sh and
	// merge.sh pass gc.routed_to back so recording a verdict cannot clear a route
	// they never looked at — and a wedged anchor is the park they most need to
	// record.
	if o.routeSet && o.route == lifecycle.ParkRoute && !o.takeawaySet {
		if bead.Meta("gc.takeaway") == "" && bead.Meta("gc.routed_to") != lifecycle.ParkRoute {
			fmt.Fprintf(stderr, "%s: --route %s needs --takeaway \"<text>\" — %s carries no gc.takeaway, and the board renders a person-routed row with an empty takeaway as 'routed to you — no question recorded'\n",
				prog, lifecycle.ParkRoute, id)
			return 1
		}
	}

	// Resolve each dated key against the bead already in hand, appending the
	// instant, then let it ride the ordinary --set path: one atomic write, and the
	// post-write verification below checks the whole three-component value.
	for _, d := range o.dated {
		dk, dwant := kv(d)
		o.sets = append(o.sets, dk+"="+dwant+"@"+datedSince(bead.Meta(dk), dwant))
	}

	// A transition that would change nothing performs no write. The observer arms
	// re-assert a verdict they already recorded on most anchors of every pass, and
	// each re-assertion costs an update plus the read-back that verifies it — two
	// store subprocesses per anchor, on a cadence whose whole budget is store
	// subprocesses. Skipping is safe because the comparison is made against the
	// bead this transition already re-read: matching it is the same evidence the
	// post-write read-back collects, gathered before the write instead of after.
	//
	// Only a pure re-assertion qualifies. --append-notes accumulates, --takeaway
	// stamps a fresh instant, and --close and --assignee move fields this
	// comparison does not cover, so any of them writes unconditionally. The
	// validation above — --expect, edge legality, the park guard — has already run
	// and is not what is being skipped: an illegal edge is still refused, and an
	// edge that is legal but idle is what returns here.
	if !o.notesSet && !o.takeawaySet && !o.closeIt && !o.assigneeSet && cur == o.to {
		idle := true
		for _, sv := range o.sets {
			k, v := kv(sv)
			if bead.Meta(k) != v {
				idle = false
				break
			}
		}
		if idle {
			for _, k := range o.unsets {
				if bead.Meta(k) != "" {
					idle = false
					break
				}
			}
		}
		if idle && o.routeSet && bead.Meta("gc.routed_to") != o.route {
			idle = false
		}
		if idle {
			return reportTransition(stdout, stderr, o.asJSON, id, cur, o.to)
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
	takeawayAt := ""
	if o.takeawaySet {
		takeawayAt = now().Format("2006-01-02T15:04:05Z")
		// gc.takeaway_settled goes empty with every headline this writer stamps.
		// A transition's takeaway names a park or an end, never a subject that
		// settled itself while staying live, and the disposition of the sitting
		// before it must not answer for this one (lifecycle.toml [holds]).
		updateArgs = append(updateArgs,
			"--set-metadata", "gc.takeaway="+o.takeaway,
			"--set-metadata", "gc.takeaway_at="+takeawayAt,
			"--set-metadata", "gc.takeaway_by="+prog,
			"--set-metadata", "gc.takeaway_settled=")
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
	// Every field of the takeaway stamp, not just the text a person reads.
	// The timestamp dates the wait: helm orders the operator's queue by it, and
	// attributes a takeaway to the sitting whose span contains it, dropping one it
	// cannot date. The writer is the provenance readers discriminate on to tell a
	// sitting's decision from a park's own sentence. A stamp that lands in part
	// leaves a headline the board can neither place nor attribute, so it is a
	// failed transition and not a recorded one.
	//
	// The settled-key is verified CLEARED rather than merely written: a
	// transition's takeaway names a park or an end, and a value inherited from an
	// earlier sitting reads as this headline's own disposition, which is what
	// doctor/check-wait-is-an-edge answers from.
	if o.takeawaySet {
		if g := bead.Meta("gc.takeaway"); g != o.takeaway {
			fmt.Fprintf(&bad, " gc.takeaway='%s'(want '%s')", g, o.takeaway)
		}
		if g := bead.Meta("gc.takeaway_at"); g != takeawayAt {
			fmt.Fprintf(&bad, " gc.takeaway_at='%s'(want '%s')", g, takeawayAt)
		}
		if g := bead.Meta("gc.takeaway_by"); g != prog {
			fmt.Fprintf(&bad, " gc.takeaway_by='%s'(want '%s')", g, prog)
		}
		if g := bead.Meta("gc.takeaway_settled"); g != "" {
			fmt.Fprintf(&bad, " gc.takeaway_settled='%s'(want cleared)", g)
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

	return reportTransition(stdout, stderr, o.asJSON, id, cur, o.to)
}

// reportTransition writes the one line a caller reads. Both exits use it — the
// idle re-assertion that wrote nothing and the transition that wrote — because
// a caller cannot tell the two apart and must not have to.
func reportTransition(stdout, stderr io.Writer, asJSON bool, id, from, to string) int {
	if asJSON {
		enc := json.NewEncoder(stdout)
		enc.SetEscapeHTML(false)
		if err := enc.Encode(transitionResult{ID: id, From: from, To: to, OK: true}); err != nil {
			fmt.Fprintf(stderr, "%s: %s %s -> %s landed but could not be reported as JSON: %v\n", prog, id, from, to, err)
			return 2
		}
		return 0
	}
	fmt.Fprintf(stdout, "%s: %s %s -> %s\n", prog, id, from, to)
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
