package board

import (
	"fmt"
	"regexp"
	"sort"
	"strings"
	"time"
)

// rankSeverityMultiplier and rankWeightMultiplier keep the three rank_score
// terms in non-overlapping decimal lanes, exactly as gc-helm.sh does:
// severity (0-3) * 1e6 dominates, weight (capped < 1000) * 1e3 is the middle
// term, and the staleness tiebreaker (capped at 999) occupies the units. The
// caps below preserve that invariant.
const (
	rankSeverityMultiplier = 1_000_000
	rankWeightMultiplier   = 1_000
	rankTermCap            = 999
)

// staleThresholdDays mirrors gc-helm.sh's STALE_DAYS=14: a NORMAL anchor
// untouched for MORE than this many days is bumped to ELEVATED.
const staleThresholdDays = 14

// xrefCap mirrors gc-helm.sh's XREF_CAP=5: the most cross-rig references that
// can count toward an anchor's weight. Uncapped, one prose-heavy epic naming a
// dozen other rigs' beads would outrank a genuinely stranded frontier.
const xrefCap = 5

// staleDays is whole days since updatedAt, mirroring gc-helm.sh
// (`(($now - $upd) / 86400) | floor`). A zero updatedAt means the source could
// not read the field, which the bash treats as `$upd == null` → 0.
//
// The result is floored at 0. A negative value — a future updated_at, from clock
// skew between the writer and this process — occupies the units lane of
// rank_score, where it would borrow from the weight lane and could invert the
// band ordering the lane packing exists to guarantee. gc-helm.sh does not floor;
// it also does not run against a clock it did not set.
//
// There is deliberately no UPPER clamp here: rankScore caps its own term, so
// capping the reported value too would only lie to the reader about how old an
// ancient anchor is. The tile reports the real age; the rank lane stays bounded.
func staleDays(updatedAt, now time.Time) int {
	if updatedAt.IsZero() {
		return 0
	}
	return max(int(now.Sub(updatedAt)/(24*time.Hour)), 0)
}

// prioWeight mirrors gc-helm.sh's `def prio_w($p)`: max(0, 4-priority),
// with a nil/absent priority treated as the gather default (priority 3 → 1).
// P1→3, P2→2, P3→1, P4→0.
func prioWeight(priority *int) int {
	if priority == nil {
		return 1
	}
	return max(0, 4-*priority)
}

// ownerLive answers gc-helm.sh's `def owner_live($assignee)`: is the session
// that claimed this child still alive?
//
// Keyed off the session STATE per the witness orphan-liveness rule —
// archived/closed/absent all mean a dead owner, the canonical orphaned
// in-progress bead. An empty assignee is no owner at all, so also false. The
// bash never consults `.running`, which is null for an active session mid-churn
// and would false-flag a live polecat; neither does this, because [Facts]
// carries state only.
func (f Facts) ownerLive(assignee string) bool {
	if assignee == "" {
		return false
	}
	st, ok := f.OwnerState[assignee]
	if !ok {
		return false
	}
	return st != "archived" && st != "closed"
}

// wfLive answers gc-helm.sh's `def wf_live($id)`: is this child covered by a
// LIVE graph.v2 workflow?
//
// `gc sling` leaves the work bead at status=open/assignee=null and puts the
// in-flight state on the workflow, so this is the only way a polecat
// mid-implementation is visible at all. Liveness is re-derived HERE, against
// the session states in the same Facts, rather than trusted from the gather:
// the gather can only record which workflows were live when it ran, and a
// polecat that drained since must stop counting at once — otherwise the fix
// trades a false "stranded" for a false "in flight", the worse lie on a board
// whose job is to say what needs a human.
func (f Facts) wfLive(childID string) bool {
	for _, name := range f.Inflight[childID] {
		if f.ownerLive(name) {
			return true
		}
	}
	return false
}

// rollup is every count and id-list the derivation reads off an anchor's
// children — the block of `as $…` bindings in the middle of gc-helm.sh's jq
// pass, computed once so the branches below can all read from it.
type rollup struct {
	mTotal     int
	nClosed    int
	open       int
	inProgress int // RAW status count; 0 for a slung bead by construction
	assigned   int

	// liveHeads is the union of the two ways a child can be demonstrably
	// moving: claimed by a live session, OR covered by a live workflow. Unioned
	// by id, so a child matched both ways is counted once.
	liveHeads []string
	// deadOwnerHeads is claimed, owner dead, AND no live workflow behind it.
	// The workflow clause matters: a re-dispatched bead can carry a stale
	// assignee from the session that died while a live workflow works it now,
	// and calling that "dead owner" would be the same error in a new place.
	deadOwnerHeads []string
	// inFlightHeads is the part of liveHeads attributable to a workflow.
	inFlightHeads []string
	// openHeads is unclaimed/unowned open children MINUS anything a live
	// workflow already carries — those are not idle, they are in flight — and
	// MINUS parkedHeads, which are not idle either.
	openHeads []string
	// parkedHeads is the part of that set that carries its OWN board row under
	// a human-gated or parked kind. A child waiting on the operator is not work
	// nobody has picked up, so it must not be counted as idle.
	parkedHeads []string
}

// rollUp derives every child-derived quantity for one anchor.
func rollUp(children []Child, f Facts) rollup {
	r := rollup{
		mTotal:         len(children),
		liveHeads:      []string{},
		deadOwnerHeads: []string{},
		inFlightHeads:  []string{},
		openHeads:      []string{},
		parkedHeads:    []string{},
	}

	live := make(map[string]bool, len(children))
	for _, c := range children {
		if c.Status == "closed" {
			r.nClosed++
			continue
		}
		r.open++
		if c.Status == "in_progress" {
			r.inProgress++
		}
		if c.Assignee != "" {
			r.assigned++
		}

		wf := f.wfLive(c.ID)
		claimed := c.Status == "in_progress" && f.ownerLive(c.Assignee)
		if claimed || wf {
			r.liveHeads = append(r.liveHeads, c.ID)
			live[c.ID] = true
		}
		if wf {
			r.inFlightHeads = append(r.inFlightHeads, c.ID)
		}
		if c.Status == "in_progress" && !f.ownerLive(c.Assignee) && !wf {
			r.deadOwnerHeads = append(r.deadOwnerHeads, c.ID)
		}
	}

	// Second pass: openHeads subtracts liveHeads, which is only complete once
	// every child has been classified. The parked split is taken from what
	// remains after that subtraction — a child that is moving is neither idle
	// nor parked, whatever markers it carries.
	for _, c := range children {
		if c.Status == "closed" {
			continue
		}
		if (c.Assignee == "" || c.Status != "in_progress") && !live[c.ID] {
			if hasOwnRow(c.Metadata) {
				r.parkedHeads = append(r.parkedHeads, c.ID)
				continue
			}
			r.openHeads = append(r.openHeads, c.ID)
		}
	}

	// Sort every head list. gc-helm.sh emits them in child-enumeration order,
	// which is whatever order the store returned the dependency rows in — so
	// the bash board's own output for these three fields is not stable run to
	// run, and neither would a port of it be. Sorting makes THIS board's wire
	// bytes deterministic, which is what a golden test and a polling frontend
	// both need. Parity against the bash board on these fields is therefore by
	// SET, not by sequence; every other field matches element for element.
	sort.Strings(r.liveHeads)
	sort.Strings(r.deadOwnerHeads)
	sort.Strings(r.inFlightHeads)
	sort.Strings(r.openHeads)
	sort.Strings(r.parkedHeads)
	return r
}

// idle is the open-child count with the ones parked for the operator taken out.
// It is what "stranded" and the frontier's count phrases mean by open; the wire
// keeps the honest total in [Tile.Open] and names the difference in
// [Tile.ParkedHeads]. With nothing parked it equals r.open.
func (r rollup) idle() int { return r.open - len(r.parkedHeads) }

// beadRef matches a bead id with one of the given prefixes: `<prefix>-<suffix>`
// where the suffix is 3-8 lowercase alphanumerics. Mirrors gc-helm.sh's
// `scan("(?:" + ($others|join("|")) + ")-[a-z0-9]{3,8}")`.
func beadRef(prefixes []string) *regexp.Regexp {
	quoted := make([]string, 0, len(prefixes))
	for _, p := range prefixes {
		if p != "" {
			quoted = append(quoted, regexp.QuoteMeta(p))
		}
	}
	if len(quoted) == 0 {
		return nil
	}
	return regexp.MustCompile(`(?:` + strings.Join(quoted, "|") + `)-[a-z0-9]{3,8}`)
}

// crossRigRefs is the DETERMINISTIC prose scan for bead ids belonging to OTHER
// rigs. Cross-rig work is forced into prose today (formal cross-rig dep edges
// are rare), and a stranded anchor that blocks another rig is more urgent, so
// the refs add weight.
//
// A decision carries no roll-up and is banded by what it IS, so gc-helm.sh
// skips the scan for it entirely; so does this.
//
// ONE DELIBERATE DIVERGENCE from the bash. With a single-rig city the "other
// prefixes" set is empty, and jq's `(?:)-[a-z0-9]{3,8}` then matches a bare
// `-abc` anywhere in the prose — every hyphenated word becomes a phantom
// cross-rig reference and silently inflates the weight lane. An empty prefix
// set yields no refs here instead.
func crossRigRefs(a Anchor, f Facts) []string {
	out := []string{}
	if a.Source == "decision" || a.Description == "" {
		return out
	}

	others := make([]string, 0, len(f.Prefixes))
	for _, p := range f.Prefixes {
		if p != a.Prefix {
			others = append(others, p)
		}
	}
	re := beadRef(others)
	if re == nil {
		return out
	}

	rigNames := make(map[string]bool, len(f.RigNames))
	for _, n := range f.RigNames {
		rigNames[n] = true
	}

	seen := map[string]bool{}
	for _, m := range re.FindAllString(a.Description, -1) {
		// A hit that is really a rig NAME is not a bead id: "signal-loom" must
		// not read as a `signal-` bead.
		if rigNames[m] || m == a.ID || seen[m] {
			continue
		}
		seen[m] = true
		out = append(out, m)
	}
	sort.Strings(out) // jq's `unique` sorts; keep the wire order identical.
	return out
}

// waitingSplit returns an anchor's `blocks` blockers and the subset of them
// still outstanding, mirroring gc-helm.sh's $waiting / $waiting_open.
//
// A blocker is discharged only on a POSITIVE closed from the source. One it
// could not resolve — a store in another rig, an `external:` reference, a read
// that failed — is absent from WaitingOnClosed and therefore counted open. That
// is the quiet direction on purpose: a missed promotion costs a glance, while a
// false "everything landed" invites the operator to dispose of a subject whose
// work is still in flight.
//
// Both slices are non-nil so the wire shape matches jq's `[]`, which emits an
// empty array rather than a null.
func waitingSplit(a Anchor) (all, open []string) {
	all = make([]string, 0, len(a.WaitingOn))
	open = make([]string, 0, len(a.WaitingOn))
	closed := make(map[string]bool, len(a.WaitingOnClosed))
	for _, id := range a.WaitingOnClosed {
		closed[id] = true
	}
	seen := make(map[string]bool, len(a.WaitingOn))
	for _, id := range a.WaitingOn {
		if id == "" || seen[id] {
			continue
		}
		seen[id] = true
		all = append(all, id)
		if !closed[id] {
			open = append(open, id)
		}
	}
	sort.Strings(all) // jq's `unique` sorts; keep the wire order identical.
	sort.Strings(open)
	return all, open
}

// humanGated is "no agent will take this — it moves only when a human moves
// it". The two kinds that say so by BEING what they are, plus the marker that
// says so on an ordinary bead.
//
// The third clause is not redundant with the second. A bead carrying BOTH
// `gc.routed_to=human` and a `gc.takeaway` is gathered twice on purpose, once
// per marker, and the two rows are reconciled by BuildBoard's id-dedup, which
// keeps the HIGHER band. So any rule that lowers the `human` row is silently
// undone by its `parked` twin unless the twin is recognised as the same
// human-gated bead — which is what reading the marker off the anchor does.
func humanGated(a Anchor) bool {
	return a.Source == "decision" || a.Source == "human" ||
		a.Metadata[mdRoutedTo] == routedHuman
}

// The two metadata markers that make an ordinary bead an anchor in its own
// right — the gather selects the `human` and `parked` kinds by exactly these
// (source.metadataAnchors). The board restates them because the gather imports
// the board and not the reverse; a marker added on one side has to be added on
// the other, or the two disagree about which beads have a row.
const (
	mdRoutedTo  = "gc.routed_to"
	mdTakeaway  = "gc.takeaway"
	routedHuman = "human"
)

// hasOwnRow reports whether a bead carrying this metadata is an anchor in its
// own right, and therefore carries its ask on a row of its own rather than as
// idle work under its parent.
//
// Presence, not truthiness, for the takeaway — the same reading
// source.metadataAnchor.matches uses, so a blanked takeaway still counts.
func hasOwnRow(md map[string]string) bool {
	if md == nil {
		return false
	}
	if md[mdRoutedTo] == routedHuman {
		return true
	}
	_, ok := md[mdTakeaway]
	return ok
}

// ruled is the STAND-DOWN state: a human-gated row that has already been
// answered, and whose recorded waits have all landed.
//
// A decision or a human-routed bead is banded by what it IS, and what it is
// never changes while the bead is open — so the row asked for the operator on
// the day it was filed and went on asking after they answered it. Measured
// 2026-08-23: seven ELEVATED rows on a 62-row board carried a takeaway
// recording their own ruling, one of them (tk-z130v) for THIRTY DAYS. Nothing
// else in the city re-reads a takeaway, and converse never closes a subject by
// contract, so no other actor could ever retire them.
//
// The shape is the one `parked` already has (dispositionDue below, tk-2plde):
// derived per render from state the bead already carries, storing nothing, so
// nothing has to be cleared when it changes and a re-opened question stands
// back up by itself.
//
// The wait clause is what keeps it honest — "answered" is not "answered and
// the work landed". A decision whose `--waiting-on` edge is still open has not
// finished being a decision, so it keeps its band. Those edges are gathered for
// these kinds precisely so this clause can fire; without them it would be a
// guard that guards nothing.
//
// And the clause counts only when the source actually READ those edges. An
// empty waitingOpen means "every recorded wait has landed" if and only if the
// waits were legible; when the dependency query failed it means nothing at
// all, and the row keeps the band it already had. That asymmetry is the whole
// point of the wait clause: NOT standing a row down costs the operator a
// glance, while standing one down on an unread graph invites them to close or
// extend a question whose routed work is still open — the exact fail-open the
// clause exists to prevent (tk-fhd705).
func ruled(a Anchor, takeaway string, waitingOpen []string) bool {
	return humanGated(a) && takeaway != "" &&
		!a.WaitingUnknown && len(waitingOpen) == 0
}

// dispositionDue is the state the waiting edges exist to express: a parked
// conversation that WAS waiting on something, every piece of which has landed.
// The takeaway still says what the sitting decided at dispatch time, and
// nothing else in the city re-reads it, so this is the only thing that can
// notice the wait ended (tk-2plde).
//
// NOT for a human-gated subject, including the `parked` TWIN of one. The
// promotion exists to lift a row out of the parked LOW FLOOR, where nobody
// would ever look at it again; a human-gated bead was never in that floor, and
// once [ruled] answers for the same state it says the same thing — dispose of
// this — at the volume the operator asked for. Letting both fire would put an
// ELEVATED duplicate of every stood-down row back on the board, and the dedup
// would keep it.
//
// It needs no unreadable-edges clause of its own. This promotion fires only on
// a row that HAS recorded waits, so an anchor whose edge read failed — which
// carries none — can never reach it. [ruled] needs the clause precisely
// because it fires on the empty set.
func dispositionDue(a Anchor, waiting, waitingOpen []string) bool {
	return a.Source == "parked" && len(waiting) > 0 && len(waitingOpen) == 0 &&
		!humanGated(a)
}

// severity mirrors gc-helm.sh's band derivation.
//
// The three metadata/shape-keyed kinds are placed AHEAD of the count branches
// on purpose: a CHILDLESS one has no roll-up to band on, so the band must come
// from what the bead IS, and falling through would read it as an empty anchor.
//
//   - `unowned` is HIGH: under the everything-is-owned law an unowned
//     non-machine convoy is exactly the orphan the observer exists to catch.
//   - `human` is ELEVATED for the same reason a decision is: gc.routed_to=human
//     means no agent will take it. Read off the MARKER ([humanGated]), not the
//     kind, so the `parked` TWIN of a human-routed bead bands with its sibling
//     — the two rows are one bead, and a dedup between rows that disagree
//     arbitrates by rank rather than by which row is truer. Open children under
//     a human-routed bead do not falsify what it says about itself: it never
//     claimed to want nothing, it claimed to want the operator, and nobody can
//     pick that work up until the operator answers.
//     Both stand DOWN once [ruled] — the row was answered,
//     and a recorded ruling that keeps asking is the loudest kind of noise. A
//     ruled row that DECOMPOSED is banded by its roll-up instead, exactly as a
//     decomposed `parked` subject is: "answered" is a claim about the bead, and
//     open work hanging under it falsifies the claim (tk-a9k0l).
//   - `parked` is LOW for the opposite reason — the conversation reached a
//     takeaway and wants nothing, it only has to stay FINDABLE, so the band
//     floor keeps it out of the contest whatever its priority or age. UNLESS
//     it was waiting on work that has since landed, which is a disposition the
//     operator owes and so is banded with the other human-gated rows: the
//     floor is what made a finished topic indistinguishable from a live hold
//     (tk-2plde). And UNLESS it has CHILDREN, in which case it is banded by
//     them like any other roll-up anchor — "wants nothing" is a claim about
//     the bead, and open work hanging under it falsifies the claim. That is
//     the canonical converse shape: the sitting files the work it routes as a
//     CHILD of the subject, and beads refuses a parent→descendant `blocks`
//     edge, so those subjects have no waiting edges at all (tk-a9k0l,
//     tk-2cyxo). A roll-up whose children have all closed lands back on LOW
//     through the r.open == 0 branch below.
//
// STRANDED (HIGH) is open work with nothing LIVE in it and no open visit. Three
// things make that different from the naive "0 in progress": inProgressLive
// counts a slung bead whose movement lives on its workflow, `held` means a
// conversation is holding the anchor — attention is already on it, so silence
// in the child beads is not abandonment — and a child parked for the operator
// is a question already asked on its own row, so [rollup.idle] excludes it. An
// anchor whose every open child is parked that way falls through to NORMAL:
// the asks are all live, none of them are its own.
func severity(a Anchor, r rollup, held bool, stale int, dispDue, isRuled bool) Severity {
	var sev0 Severity
	inProgressLive := len(r.liveHeads)
	switch {
	case a.Source == "unowned":
		sev0 = SevHigh
	case isRuled && r.mTotal == 0:
		sev0 = SevLow
	case !isRuled && humanGated(a):
		sev0 = SevElevated
	case dispDue:
		sev0 = SevElevated
	case a.Source == "parked" && r.mTotal == 0:
		sev0 = SevLow
	case r.mTotal == 0:
		sev0 = SevLow
	case r.open == 0:
		sev0 = SevLow
	case r.idle() > 0 && inProgressLive == 0 && !held:
		sev0 = SevHigh
	case len(r.deadOwnerHeads) > 0:
		sev0 = SevElevated
	default:
		sev0 = SevNormal
	}
	if sev0 == SevNormal && stale > staleThresholdDays {
		return SevElevated
	}
	return sev0
}

// weight is the rank PROXY: subtree size + priority weight + a capped cross-rig
// ref count. Intentionally crude — blast radius, not an LLM judgement.
func weight(r rollup, priority *int, xrefs []string) int {
	return r.mTotal + prioWeight(priority) + min(len(xrefs), xrefCap)
}

// rankScore is sevrank*1e6 + weight*1e3 + min(stale,999). The weight is capped
// so it can never bleed into the severity lane; stale arrives already clamped
// to the units lane by [staleDays].
func rankScore(sev Severity, w, stale int) int {
	return sev.rank()*rankSeverityMultiplier +
		min(w, rankTermCap)*rankWeightMultiplier +
		min(stale, rankTermCap)
}

// frontier is the one-line human summary. Display-only; it does not feed
// rank_score. The kinds that describe themselves do so instead of reporting a
// roll-up they do not have.
func frontier(a Anchor, r rollup, held bool, waitingOpen []string, dispDue, isRuled bool) string {
	inProgressLive := len(r.liveHeads)
	dead := len(r.deadOwnerHeads)
	parked := len(r.parkedHeads)
	deadSfx := ""
	if dead > 0 {
		deadSfx = fmt.Sprintf(" · %d stuck (dead owner)", dead)
	}
	// An undifferentiated "N open" cannot separate unassigned beads from ones
	// finished and waiting on a ruling, so the phrases below count the IDLE
	// remainder and name the parked ones apart from it.
	parkedSfx := ""
	if parked > 0 {
		parkedSfx = fmt.Sprintf(" · %d parked for the operator", parked)
	}

	switch {
	case a.Source == "unowned":
		return "unowned convoy — no owning bead"
	// Parallel to the parked phrase below, and for the same reason: the row is
	// reporting what it IS, because it has no roll-up to report instead. A
	// ruled row that decomposed skips this and reports its counts.
	case isRuled && r.mTotal == 0:
		return "ruled — takeaway recorded"
	case !isRuled && a.Source == "decision":
		return "human-gated decision"
	// The marker, not the kind, for the reason [severity] gives: a bead's
	// `human` and `parked` rows are one bead and must not describe it two ways.
	case !isRuled && humanGated(a):
		return "routed to the operator — no agent will take it"
	case dispDue:
		return "parked · blocker landed"
	case a.Source == "parked" && len(waitingOpen) > 0:
		return fmt.Sprintf("parked · waiting on %d", len(waitingOpen))
	// A NAMED wait outranks the roll-up below: the sitting stated it, and that
	// is why the row is quiet. Under it, a parked subject that decomposed
	// reports its frontier through the same count phrases as every other
	// roll-up anchor, so the phrase explains the band those counts just gave it.
	case a.Source == "parked" && r.mTotal == 0:
		return "conversation parked — takeaway recorded"
	case r.mTotal == 0:
		return "empty — no children"
	case r.open == 0:
		return fmt.Sprintf("all %d closed · 0 open", r.mTotal)
	case r.idle() == 0 && parked > 0 && inProgressLive == 0 && dead == 0:
		return fmt.Sprintf("%d parked for the operator · nothing idle", parked)
	case inProgressLive == 0 && dead > 0 && !held:
		return fmt.Sprintf("%d open · %d stuck (dead owner)", r.idle(), dead) + parkedSfx
	case inProgressLive == 0 && held:
		return fmt.Sprintf("%d open · in conversation", r.idle()) + deadSfx + parkedSfx
	case inProgressLive == 0:
		return fmt.Sprintf("%d open · 0 in flight (stranded)", r.idle()) + parkedSfx
	default:
		return fmt.Sprintf("%d open · %d in flight", r.idle(), inProgressLive) + deadSfx + parkedSfx
	}
}

// collapseWS mirrors jq's `gsub("[[:space:]]+";" ") | gsub("^ | $";"")`: a
// takeaway is free prose and a stray newline would break the terminal table.
var wsRun = regexp.MustCompile(`\s+`)

func collapseWS(s string) string {
	return strings.TrimSpace(wsRun.ReplaceAllString(s, " "))
}

// needs is the one-glance answer for a human.
//
// The LLM-authored takeaway sentence WINS when one exists — that is the whole
// point of gathering it, and it is why this branch sits ahead of every state
// phrase. Otherwise a terse deterministic STATE phrase, never a bead-id list:
// the mechanical heads (open_heads, cross_rig_refs) are --json-only so the
// human table stays explanatory and cannot emit a raw or truncated bead id.
func needs(a Anchor, r rollup, held bool, takeaway string, dispDue, isRuled bool) string {
	// The disposition phrase OUTRANKS the takeaway, and only here. Every other
	// row spends its takeaway as NEEDS because the sentence is the best answer
	// available; on this row the sentence is precisely what has gone stale —
	// it was written when the work was dispatched and still says so. The
	// takeaway itself stays on the wire for anyone who wants to read what the
	// sitting concluded.
	if dispDue {
		return "blocker landed — dispose or resume"
	}
	// A ruled row spends its NEEDS on the DISPOSITION for the same reason, and
	// with the same trade. The takeaway is not stale here — it is the ruling —
	// but NEEDS answers "what does this row want from me", and what a ruled row
	// wants is to be closed or re-opened, not re-read. The ruling itself stays
	// on the wire in `takeaway`, where nothing truncates it; in the terminal
	// table it was the column's longest cells (n=20 over the 140-char cap on
	// the 2026-08-23 board, max 1343) and the least actionable.
	//
	// Only while the row has no roll-up. A ruled row with children reports the
	// takeaway and is banded by those children, so the two halves of it agree.
	if isRuled && r.mTotal == 0 {
		return "ruled — close or extend"
	}
	if takeaway != "" {
		return takeaway
	}
	// Below here the takeaway is empty, so isRuled is false by construction and
	// the decision/human branches need no guard of their own.
	inProgressLive := len(r.liveHeads)
	dead := len(r.deadOwnerHeads)

	switch {
	case a.Source == "unowned":
		return "unowned — assign an owning bead"
	case a.Source == "decision":
		return "operator decision"
	case humanGated(a):
		return "operator action"
	case a.Source == "parked" && r.mTotal == 0:
		return "resume: prefix+a, then the bead id"
	case r.mTotal == 0:
		return "no children — decompose or assign"
	case r.open == 0:
		if a.Source == "convoy" {
			return fmt.Sprintf("all %d closed — graduate", r.mTotal)
		}
		return fmt.Sprintf("all %d closed — close or extend", r.mTotal)
	// Ahead of the dead-owner and idle phrases: this row has no ask of its own
	// left, so "assign or visit" would name the wrong bead.
	case r.idle() == 0 && len(r.parkedHeads) > 0 && inProgressLive == 0 && dead == 0:
		return fmt.Sprintf("%d parked for the operator — rule on those rows", len(r.parkedHeads))
	case inProgressLive == 0 && dead > 0 && !held:
		return "dead owner — recover or reassign"
	case inProgressLive == 0 && held:
		return "open to join"
	case inProgressLive == 0:
		return "decomposed, idle — assign or visit"
	case dead > 0:
		return fmt.Sprintf("in flight — %d stuck, recover", dead)
	case held:
		return "in flight (in conversation)"
	default:
		return "in flight"
	}
}

// nilIfEmpty renders an absent string field as a JSON null rather than "". The
// takeaway triple is always-present-but-nullable in the bash contract, and a
// consumer tells "no takeaway" from "field gone" by the null.
func nilIfEmpty(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

// computeTile derives a single tile from an anchor. now is the board's
// generation instant, shared by every tile so one board never mixes staleness
// measured against two different clock reads.
func computeTile(a Anchor, now time.Time, f Facts) Tile {
	r := rollUp(a.Children, f)
	held := f.Visits[a.ID]
	stale := staleDays(a.UpdatedAt, now)
	xrefs := crossRigRefs(a, f)
	waiting, waitingOpen := waitingSplit(a)
	takeaway := collapseWS(a.Takeaway)
	dispDue := dispositionDue(a, waiting, waitingOpen)
	isRuled := ruled(a, takeaway, waitingOpen)
	sev := severity(a, r, held, stale, dispDue, isRuled)
	w := weight(r, a.Priority, xrefs)

	// progress_mismatch: the convoy's own closed/total claim disagrees with the
	// membership actually rolled up. Only meaningful where the source supplied
	// a progress object.
	mismatch := a.Progress != nil &&
		(a.Progress.Total != r.mTotal || a.Progress.Closed != r.nClosed)

	return Tile{
		ID:       a.ID,
		Rig:      a.Rig,
		Kind:     a.Kind,
		Title:    a.Title,
		Severity: sev,

		// The two states in which a PERSON, not an agent, holds the next move.
		// Read from the same predicates severity uses, not from the band it
		// produces: `unowned` is checked first there and would swallow a
		// human-routed convoy, and the stale bump can lift an ordinary row into
		// the same band without any person owing anything.
		Owed: (humanGated(a) && !isRuled) || dispDue,

		Weight: w,
		Held:   held,

		NClosed:    r.nClosed,
		MTotal:     r.mTotal,
		Open:       r.open,
		InProgress: r.inProgress,
		Assigned:   r.assigned,

		InProgressLive: len(r.liveHeads),
		InProgressDead: len(r.deadOwnerHeads),
		DeadOwner:      len(r.deadOwnerHeads) > 0,

		InFlight:      len(r.inFlightHeads),
		InFlightHeads: r.inFlightHeads,

		Owned: a.Owned,

		// An UNANSWERED human gate is excluded for the same reason `held` is:
		// stranded means open work nobody's attention is on, and a row routed
		// to the operator has the operator's. Once [ruled] the gate is
		// discharged and open children under it are ordinary idle work again,
		// so the exemption ends exactly where the band's does.
		Stranded: r.mTotal > 0 && r.idle() > 0 && len(r.liveHeads) == 0 && !held &&
			!(humanGated(a) && !isRuled),
		Empty: r.mTotal == 0 && a.Source != "decision" && a.Source != "unowned" &&
			a.Source != "human" && a.Source != "parked",
		Complete:         r.mTotal > 0 && r.open == 0,
		ProgressMismatch: mismatch,

		StaleDays:      stale,
		Priority:       a.Priority,
		CrossRigRefs:   xrefs,
		OpenHeads:      r.openHeads,
		DeadOwnerHeads: r.deadOwnerHeads,
		ParkedHeads:    r.parkedHeads,

		WaitingOn:      waiting,
		WaitingOnOpen:  waitingOpen,
		DispositionDue: dispDue,

		Takeaway:   nilIfEmpty(takeaway),
		TakeawayAt: nilIfEmpty(a.TakeawayAt),
		TakeawayBy: nilIfEmpty(a.TakeawayBy),

		UpdatedAt: a.UpdatedAt,
		Frontier:  frontier(a, r, held, waitingOpen, dispDue, isRuled),
		Needs:     needs(a, r, held, takeaway, dispDue, isRuled),
		RankScore: rankScore(sev, w, stale),
	}
}

// BuildBoard derives every tile, ranks by rank_score descending, deduplicates
// by id keeping the highest-ranked occurrence (so a bead matched by two gathers
// appears once, in its higher band), and then PARTITIONS: the operator's queue
// ahead of the city overview, per [owedFirst]. Ties break by id ascending for
// deterministic output. now stamps GeneratedAt. partial/partialErrors propagate
// cross-rig degradation.
//
// facts carries the three cross-anchor joins (visits, in-flight workflows,
// session liveness); a zero value is legal and yields a board with no held or
// in-flight signal — narrower, not wrong.
func BuildBoard(anchors []Anchor, now time.Time, partial bool, partialErrors []string, facts Facts) Board {
	tiles := make([]Tile, 0, len(anchors))
	for _, a := range anchors {
		tiles = append(tiles, computeTile(a, now, facts))
	}

	sort.SliceStable(tiles, func(i, j int) bool {
		if tiles[i].RankScore != tiles[j].RankScore {
			return tiles[i].RankScore > tiles[j].RankScore
		}
		return tiles[i].ID < tiles[j].ID
	})

	seen := make(map[string]struct{}, len(tiles))
	deduped := make([]Tile, 0, len(tiles))
	for _, t := range tiles {
		if _, dup := seen[t.ID]; dup {
			continue
		}
		seen[t.ID] = struct{}{}
		deduped = append(deduped, t)
	}

	sort.SliceStable(deduped, func(i, j int) bool { return owedFirst(deduped[i], deduped[j]) })

	return Board{
		GeneratedAt:   now.UTC(),
		Total:         len(deduped),
		Tiles:         deduped,
		Sittings:      orderSittings(facts.Sittings),
		Partial:       partial,
		PartialErrors: partialErrors,
	}
}

// orderSittings sorts the conversation record: running sittings first, oldest
// start first, then the closed ones, most recently closed first.
//
// Running before closed because only a running sitting can still be joined.
// Oldest-first WITHIN the running group because the sitting that has been open
// longest is the one worth a look — a conversation nobody ended is how a
// converse session wedges — while a newest-first list would bury it under
// whatever started since. The closed group is the opposite question, "what just
// concluded", so it reads newest-first.
//
// Ordering here rather than in a renderer is what keeps the terminal board and
// the dashboard showing the same sequence. Both spend the order; neither may
// invent one.
func orderSittings(in []Sitting) []Sitting {
	if len(in) == 0 {
		return nil
	}
	out := make([]Sitting, len(in))
	copy(out, in)
	sort.SliceStable(out, func(i, j int) bool {
		a, b := out[i], out[j]
		if ar, br := a.running(), b.running(); ar != br {
			return ar
		}
		if a.running() {
			if !a.OpenedAt.Equal(b.OpenedAt) {
				return a.OpenedAt.Before(b.OpenedAt)
			}
		} else if !a.ClosedAt.Equal(b.ClosedAt) {
			return a.ClosedAt.After(b.ClosedAt)
		}
		return a.ID < b.ID
	})
	return out
}

// running reports whether this sitting is still holding its conversation. The
// test is on the status the visit bead actually carries, so a status the city
// grows later reads as running rather than as finished — the direction that
// shows a row instead of hiding it.
func (s Sitting) running() bool { return s.Status != "closed" }

// DefaultMaxSittings bounds the closed half of the conversation record in a
// rendered view. Running sittings are never elided: there are as many of them
// as the city has converse sessions, and each one is a live conversation.
const DefaultMaxSittings = 12

// CapSittings keeps every running sitting and the maxClosed most recently
// closed, returning the kept rows and how many closed rows were dropped. It
// assumes the [orderSittings] order, which is the only order the board emits.
//
// The count is returned rather than swallowed so a renderer can say the list
// was shortened. A quiet truncation would read as "these are all the sittings
// there were", which is the one thing an elided list must not imply.
func CapSittings(in []Sitting, maxClosed int) (kept []Sitting, dropped int) {
	if maxClosed <= 0 {
		return in, 0
	}
	kept = make([]Sitting, 0, len(in))
	closed := 0
	for _, s := range in {
		if s.running() {
			kept = append(kept, s)
			continue
		}
		if closed >= maxClosed {
			dropped++
			continue
		}
		closed++
		kept = append(kept, s)
	}
	return kept, dropped
}

// owedFirst orders the board: the operator's queue ahead of everything else,
// oldest-owed first inside it, and the established rank order everywhere else.
//
// PARTITION BEFORE RANK, because rank cannot express this. rank_score is
// severity, then subtree size, then staleness; severity is coarse and shared
// between stranded, unowned and human-gated rows, so the term that actually
// orders the board is SIZE — and a demand owed by a person has a subtree near 1
// where a container has hundreds. One global sort therefore files the
// operator's own queue underneath the city's, every time, whatever the bands
// say.
//
// Inside the queue, size is not the question either. It is a list of decisions,
// so age is the order. A row nothing on the wire can date sorts LAST: an
// unknown age is not evidence of a long wait, and the supervisor backend reads
// no updated_at at all, so treating unknown as oldest would put every row from
// that backend ahead of every dated one.
//
// Apply it STABLY and after the dedup. A bead admitted under two kinds carries
// the same id in both rows and ties every test below, so only the rank order
// the dedup already resolved can decide which of the two survives.
func owedFirst(a, b Tile) bool {
	if a.Owed != b.Owed {
		return a.Owed
	}
	if !a.Owed {
		return false
	}
	sa, sb := owedSince(a), owedSince(b)
	if sa.IsZero() != sb.IsZero() {
		return !sa.IsZero()
	}
	if !sa.Equal(sb) {
		return sa.Before(sb)
	}
	return a.ID < b.ID
}

// owedSince is when the row started asking. gc.takeaway_at is the moment a
// sitting authored what is owed, which is the true start of the wait;
// updated_at only bounds it from below, and neither may be readable.
func owedSince(t Tile) time.Time {
	if t.TakeawayAt != nil {
		if ts, err := time.Parse(time.RFC3339, *t.TakeawayAt); err == nil {
			return ts
		}
	}
	return t.UpdatedAt
}

// OperatorQueue is the partition the board answers with by DEFAULT — the rows
// [Tile.Owed] marks, in [owedFirst] order. The city overview stays available
// behind an explicit `--all`.
func OperatorQueue(tiles []Tile) []Tile {
	out := make([]Tile, 0, len(tiles))
	for _, t := range tiles {
		if t.Owed {
			out = append(out, t)
		}
	}
	sort.SliceStable(out, func(i, j int) bool { return owedFirst(out[i], out[j]) })
	return out
}

// DefaultMaxRows and DefaultMaxParked mirror gc-helm.sh's GC_HELM_MAX_ROWS=50
// and GC_HELM_MAX_PARKED=15.
const (
	DefaultMaxRows   = 50
	DefaultMaxParked = 15
)

// CapRows applies gc-helm.sh's SPLIT row cap and returns one globally ranked
// slice. limit<=0 means uncapped (both kinds), which is what tooling asks for.
//
// A single rank-ordered cap would silently undo half of what the `parked` kind
// is for. Parked is band-floored to LOW, so it sorts last by construction, and
// the operator's own surface asks for 36 rows (tmux-pick-helm.sh) against a
// board whose attention bands alone fill most of that — so every parked row
// falls off the end, and a bead added to the gather specifically so it could be
// FOUND is once again absent from the board the operator actually reads.
//
// So the budgets are separate: attention rows keep the whole of limit (their
// budget is not reduced by parked existing) and parked rows draw on maxParked.
// The two slices are re-merged by rank_score, so the output stays one ranked
// array and the --json shape is unchanged.
func CapRows(tiles []Tile, limit, maxParked int) []Tile {
	if limit <= 0 {
		return tiles
	}
	out := make([]Tile, 0, min(len(tiles), limit+maxParked))
	var attention, parked int
	for _, t := range tiles {
		if t.Kind == "parked" {
			if parked >= maxParked {
				continue
			}
			parked++
		} else {
			if attention >= limit {
				continue
			}
			attention++
		}
		out = append(out, t)
	}
	// tiles arrives ranked and the filter above preserves that order, so the
	// re-merge gc-helm.sh does with an explicit sort is already done.
	return out
}

// CapQueue bounds the operator's queue. limit<=0 means uncapped.
//
// Deliberately not [CapRows]. That split exists because `parked` rows are
// band-floored to LOW and would otherwise be pushed off the end of a
// rank-ordered board, so it rations them against a small separate budget. In
// this partition a parked row is not a straggler — it is a conversation waiting
// on the operator, and it earned its place by age — so that budget would cut
// the queue precisely where it carries the most.
func CapQueue(tiles []Tile, limit int) []Tile {
	if limit <= 0 || len(tiles) <= limit {
		return tiles
	}
	return tiles[:limit]
}
