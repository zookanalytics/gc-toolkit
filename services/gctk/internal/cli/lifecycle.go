package cli

import (
	"encoding/json"
	"fmt"
	"io"
	"regexp"
	"slices"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/lifecycle"
)

// `gctk lifecycle` is the plain write of a bead's merge_result, and the only
// implementation of assets/scripts/lifecycle.sh, which execs it. It checks no
// edge between values: the doctor checks the beads after the write
// (doctor/check-closed-implies-landed among them). The CLI is the script's
// contract, same flags, same exit codes, same stdout grammar, because its
// callers invoke lifecycle.sh as an opaque command.
//
// Exits: 0 ok; 1 --expect mismatch / bd refusal / usage; 2 the bead could not
// be read before the write, or a landed write could not be reported as JSON.
//
// CAVEAT (docs/gascity/routing-model.md, "Clearing an assignee can be refused"):
// clearing an assignee on a bead another actor holds in_progress is refused by
// bd, and the refusal drops the WHOLE atomic update — a caller that passes
// --assignee "" must hold the claim.

// prog is the name every message carries. It stays "lifecycle" rather than
// becoming "gctk": the callers grep these lines, and the subcommand is what
// they invoked.
const prog = "lifecycle"

const lifecycleUsage = `usage: gctk lifecycle transition <bead-id> --to <value> [--expect <value>] [--set k=v]... [--set-dated k=<value>@<oid>]... [--unset k]... [--assignee <a>] [--route <rig>/<agent> | --keep-route] [--takeaway <text>] [--close] [--append-notes <text>] [--json]
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
	default:
		fmt.Fprint(stderr, lifecycleUsage)
		return 1
	}
}

// currentOf reads the merge_result a bead carries, with "unanchored" for none,
// the name --to and --expect give an absent value.
func currentOf(b *gcbd.Bead) string {
	if mr := b.Meta("merge_result"); mr != "" {
		return mr
	}
	return "unanchored"
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

// objectID matches a full git object id, SHA-1 or SHA-256. merged_sha holds
// one, or else the unverified:PR#<n> sentinel a record writes when the
// merge-commit read comes back empty, and the sentinel names no commit.
var objectID = regexp.MustCompile(`^([0-9a-f]{40}|[0-9a-f]{64})$`)

// landingOf reads the landing a transition into `merged` records. The commit is
// the merged_sha this call sets, when that value is an object id. The branch is
// the merged_target this call sets, else the one the bead carries; the direct
// landing passes it. Either is empty when the landing does not name it.
func landingOf(sets []string, bead *gcbd.Bead) (commit, branch string) {
	branch = bead.Meta("merged_target")
	for _, s := range sets {
		switch k, v := kv(s); k {
		case "merged_sha":
			commit = v
		case "merged_target":
			branch = v
		}
	}
	if !objectID.MatchString(commit) {
		commit = ""
	}
	return commit, branch
}

// callerWrite reports whether this call sets or clears key itself, and the
// value it leaves there: the value it sets, or empty for a clear.
func callerWrite(sets, unsets []string, key string) (value string, ok bool) {
	for _, s := range sets {
		if k, v := kv(s); k == key {
			return v, true
		}
	}
	return "", slices.Contains(unsets, key)
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

// normalizeTakeaway applies the two gates a bead's headline takes, returning
// the text to write or the lines that refuse it.
//
// The flag's presence is not a takeaway: whitespace normalizes to nothing, and
// an empty one would overwrite the headline a bead carries with nothing, under
// a fresh date and author. The takeaway package, the other writer of the
// headline, refuses it the same way.
//
// Over the cap it REJECTS rather than truncating: only the author knows which
// clause is the headline. The length is CODEPOINTS, as lifecycle.Headline
// counts it — counting bytes would refuse a takeaway well inside the cap the
// moment it carried an em dash.
func normalizeTakeaway(s string) (string, []string) {
	s = squeezeSpace(s)
	if s == "" {
		return "", []string{
			"--takeaway is empty; it is the bead's headline, and an empty one tells the operator nothing",
			"give it the one sentence the operator needs, or drop the flag.",
		}
	}
	if n := utf8.RuneCountInString(s); n > lifecycle.TakeawayMax {
		return "", []string{
			fmt.Sprintf("--takeaway is %d chars; the cap is %d", n, lifecycle.TakeawayMax),
			"it is the bead's headline — one line, read at a glance. Cut it to the single sentence the operator needs and put the rest in --append-notes.",
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
	keepRoute   bool
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
// empty argument (--assignee "" clears the assignee) is a real token and is
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
		case "--keep-route":
			o.keepRoute = true
			i++
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
		fmt.Fprintf(stderr, "%s: transition needs --to <value>\n", prog)
		return 1
	}
	// --keep-route writes no route at all, so it cannot also name one.
	if o.keepRoute && o.routeSet {
		fmt.Fprintf(stderr, "%s: --keep-route and --route ask for opposite things: --keep-route leaves gc.routed_to as the bead carries it\n", prog)
		return 1
	}
	// gc.routed_to is matched as an exact string by every pool claim, so a route
	// that is not <rig>/<agent> reaches no pool: the bead stays ready and is
	// offered to nobody. Every --route caller shares this writer, so the shape is
	// enforced here once. A bare name such as `human` is refused like any other:
	// a person's wait is the human gate filed on the bead, never a route. An
	// empty --route clears the route, so it is exempt.
	if o.routeSet && o.route != "" && !strings.Contains(o.route, "/") {
		fmt.Fprintf(stderr, "%s: --route '%s' is not rig-qualified; gc.routed_to is matched as an exact string, so a bare name routes to nobody and the bead sits forever. Use <rig>/<agent>, or file a human gate on the bead (human-gate.sh) for a wait on a person.\n",
			prog, o.route)
		return 1
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
	// This read governs the write: --expect's compare-and-swap, the dated-value
	// resolution, and the idle-skip below all decide from it, and nothing
	// re-checks the backing store at write time. So it takes Show, the
	// authoritative read, and never the daemon's cache: a stale read would let
	// --expect pass against an old value.
	bead := client.Show(id)
	if bead == nil {
		fmt.Fprintf(stderr, "%s: %s unreadable — refusing to transition blind\n", prog, id)
		return 2
	}
	cur := currentOf(bead)
	if o.expect != "" && cur != o.expect {
		fmt.Fprintf(stderr, "%s: %s is '%s', not the expected '%s'; transition refused\n", prog, id, cur, o.expect)
		return 1
	}
	// The executor identity goes with the assignee. gc.session_id and
	// gc.session_name name the session that claimed the bead, so they belong to
	// the assignee and go with it whenever a write clears the assignee. A survivor is residue the moment the
	// bead next carries a route (doctor/executor-identity-residue reports it) and
	// a stale orphan-recovery pin the runtime resolves a dead owner from.
	// --unset-metadata bypasses bd's anti-steal guard, so no status gate is
	// needed; if the assignee clear beside it is refused on an in_progress bead,
	// the whole update rolls back and the pins stay with the live claim that
	// still owns them. They ride the same write as the route and assignee arms.
	if o.assigneeSet && o.assignee == "" {
		for _, pin := range []string{"gc.session_id", "gc.session_name"} {
			has := false
			for _, u := range o.unsets {
				if u == pin {
					has = true
					break
				}
			}
			if !has {
				o.unsets = append(o.unsets, pin)
			}
		}
	}

	// Resolve each dated key against the bead already in hand, appending the
	// instant, then let it ride the ordinary --set path: one atomic write carries
	// the whole three-component value.
	for _, d := range o.dated {
		dk, dwant := kv(d)
		o.sets = append(o.sets, dk+"="+dwant+"@"+datedSince(bead.Meta(dk), dwant))
	}

	// A transition that would change nothing performs no write. The observer arms
	// re-assert a verdict they already recorded on most anchors of every pass, and
	// each re-assertion costs an update, a store subprocess per anchor, on a
	// cadence whose whole budget is store subprocesses. Skipping is safe because
	// the comparison is made against the bead this transition already re-read,
	// which carries every value the write would set.
	//
	// Only a pure re-assertion qualifies. --append-notes accumulates, --takeaway
	// stamps a fresh instant, and --close and --assignee move fields this
	// comparison does not cover, so any of them writes unconditionally. --expect
	// has already run and is not what is being skipped.
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

	// A write of `merged` is a landing, and a landed bead carries no live
	// objection: a rejection or a hold reason still on it now contradicts the
	// record — a merged bead that still reads "do not merge". Clear every
	// live-objection marker here, at the one writer every landing of it passes
	// through, so a caller or a field added later cannot reintroduce the
	// divergence by listing some fields and forgetting others. Deduped against
	// the caller's own --unset list so the clear is never written twice.
	if o.to == "merged" {
		for _, obj := range []string{"rejection_reason", "blocked_reason"} {
			seen := false
			for _, u := range o.unsets {
				if u == obj {
					seen = true
					break
				}
			}
			if !seen {
				o.unsets = append(o.unsets, obj)
			}
		}
	}

	// The work record rides the landing. `merged` is the one state that says the
	// work shipped, and the runtime's work-record gate reads that from three keys
	// on the close this transition performs: gc.work_outcome, gc.work_commit and
	// gc.work_branch. The landing this write records supplies all three. The
	// outcome is shipped, the commit is merged_sha, and the branch is
	// merged_target, the branch that commit landed on. Deriving them here, at the
	// one writer every landing passes through, means no caller can close a landed
	// bead with an empty record.
	//
	// The record is derived whole or not at all. The bead can already hold part
	// of one: workspace-setup stamps gc.work_branch with the branch the work was
	// cut on. A landing that names only one of the commit and the branch would
	// pair it with whatever the bead holds for the other, such as the merge
	// commit with the polecat branch, and the gate would read that pair as
	// unreachable. The unverified:PR#<n> sentinel names no commit, and a bead
	// that reaches merged without a merged_target names no branch, so both leave
	// the record as it was. A key the caller sets or clears itself keeps the
	// caller's value either way.
	if o.to == "merged" {
		commit, branch := landingOf(o.sets, bead)
		if commit != "" && branch != "" {
			for _, w := range [][2]string{
				{"gc.work_outcome", "shipped"},
				{"gc.work_commit", commit},
				{"gc.work_branch", branch},
			} {
				if _, own := callerWrite(o.sets, o.unsets, w[0]); !own {
					o.sets = append(o.sets, w[0]+"="+w[1])
				}
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
	if o.takeawaySet {
		takeawayAt := now().Format("2006-01-02T15:04:05Z")
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

	// ONE atomic write carrying every field of the transition. Its exit says
	// whether the transition landed: bd refuses a write it does not commit with a
	// non-zero exit, and gc bd passes that exit through.
	out, err := client.Update(id, updateArgs...)
	if err != nil {
		fmt.Fprintf(stderr, "%s: %s %s -> %s refused by bd (rc=%d): %s\n", prog, id, cur, o.to, gcbd.ExitCode(err), out)
		return 1
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
