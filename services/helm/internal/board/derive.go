package board

import (
	"fmt"
	"regexp"
	"sort"
	"strconv"
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
	mdDemandFor = "gc.demand_for"
	routedHuman = "human"
	// mdAnchorBead is the merge anchor a review or rework child names — the
	// family root it hangs off, used by the grouping walk as a direct edge.
	mdAnchorBead = "anchor_bead"
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

// The kinds an in-flight review or rework child surfaces under. They are the
// task_kind the source selects them by (source.reviewReworkAnchor), restated
// here because the derivation bands them: a review or rework child is a
// childless leaf that joins its merge anchor's family through the `blocks` edge
// it carries, so it must not fall to the empty-LOW arm meant for a decomposed
// container that lost its children.
const (
	kindReview = "review"
	kindRework = "rework"
)

// isReviewReworkKind reports whether a source is an in-flight review or rework
// child.
func isReviewReworkKind(source string) bool {
	return source == kindReview || source == kindRework
}

// isDemand reports whether the anchor is a DEMAND: a bead `gc-helm demand`
// filed to carry what a person owes, naming the work it blocks in
// `gc.demand_for`.
//
// A demand is stamped with a `gc.takeaway` like any other human-gated row, and
// on this one row that headline is the QUESTION rather than an answer to it —
// the verb puts the authored ask there so the board has a sentence to show.
// The demand bead also carries no blocker of its own; it IS the blocker, and
// the edge points at it from the gated work. So both halves of [ruled] are
// satisfied the moment the demand is filed, and the row would stand down on
// its first render, before anyone had read it.
//
// A demand is answered by being CLOSED, which is what makes the gated work
// ready. Until then it is owed, whatever it recorded about itself.
func isDemand(a Anchor) bool {
	return a.Metadata[mdDemandFor] != ""
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
// finished being a decision, so [ruled] does not fire and [ruledInFlight] holds
// its band instead, reading it as work in progress rather than as a settled
// ruling owed a disposition. Those edges are gathered for these kinds precisely
// so this clause can fire; without them it would be a guard that guards nothing.
//
// And the clause counts only when the source actually READ those edges. An
// empty waitingOpen means "every recorded wait has landed" if and only if the
// waits were legible; when the dependency query failed it means nothing at
// all, and the row keeps the band it already had. That asymmetry is the whole
// point of the wait clause: NOT standing a row down costs the operator a
// glance, while standing one down on an unread graph invites them to close or
// extend a question whose routed work is still open — the exact fail-open the
// clause exists to prevent (tk-fhd705).
//
// The third clause guards the other direction. Both of the above read a
// takeaway as an answer somebody already gave; on a demand row it is the
// question itself, so [isDemand] takes that row back out.
func ruled(a Anchor, takeaway string, waitingOpen []string) bool {
	return humanGated(a) && takeaway != "" && !isDemand(a) &&
		!a.WaitingUnknown && len(waitingOpen) == 0
}

// ruledInFlight is [ruled]'s in-progress twin: a human-gated row that has been
// answered, but whose ruling slung work that is still open. It is ruled — the
// operator decided and is owed nothing right now — but not settled, because a
// recorded wait has not landed. [ruled] holds the band for the settled case,
// where a disposition is owed; this holds it for the in-flight one, so a
// ruled-and-slung row bands as work in progress rather than as an un-ruled
// human gate.
//
// It shares [ruled]'s guards for the same reasons: a demand's takeaway is the
// question, not an answer, and an unread wait graph cannot prove work is in
// flight — so both fall through to the un-ruled arm, which keeps asking.
func ruledInFlight(a Anchor, takeaway string, waitingOpen []string) bool {
	return humanGated(a) && takeaway != "" && !isDemand(a) &&
		!a.WaitingUnknown && len(waitingOpen) > 0
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
func severity(a Anchor, r rollup, held bool, stale int, dispDue, isRuled, isRuledInFlight, stalledGate bool) Severity {
	// A closed anchor is not competing for attention, so no attention branch
	// below applies to it and none of them may run: a closed epic with open
	// children would otherwise band HIGH and sit at the top of the board.
	if !a.ClosedAt.IsZero() {
		return SevDone
	}
	var sev0 Severity
	inProgressLive := len(r.liveHeads)
	switch {
	case a.Source == "unowned":
		sev0 = SevHigh
	// A review or rework child is a childless leaf — the merge anchor it blocks
	// carries the roll-up. It bands NORMAL as in-flight work; the anchor, not the
	// child, is where a stalled gate surfaces (preOpenCodexStall). Placed ahead of
	// the count branches so a childless leaf does not fall to the empty-LOW arm.
	case isReviewReworkKind(a.Source):
		sev0 = SevNormal
	case isRuled && r.mTotal == 0:
		sev0 = SevLow
	// A ruled row whose slung work is still open is in progress, not an
	// un-answered gate: it bands as in-flight work, below the ELEVATED an
	// un-ruled human gate gets and above the LOW a settled ruling sinks to.
	// Childless like the settled arm; a decomposed one is banded by its roll-up
	// through the count branches, exactly as a decomposed ruled row is.
	case isRuledInFlight && r.mTotal == 0:
		sev0 = SevNormal
	case !isRuled && !isRuledInFlight && humanGated(a):
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
		sev0 = SevElevated
	}
	// A stalled pre-open codex gate is at least ELEVATED. Childless it would
	// otherwise land in the LOW branch above and sink to the bottom, where a
	// stalled gate is indistinguishable from a settled one; the bump never lowers
	// a row that a stronger branch already banded HIGH or ELEVATED.
	if stalledGate && (sev0 == SevLow || sev0 == SevNormal) {
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
//
// The DONE band is scored differently, because the two live lanes answer a
// question it does not have. Blast radius and staleness rank rows by how badly
// they want a human; a closed row wants nothing. What orders it is recency —
// most-recently-closed first — so the row the operator just watched close sits
// at the top of the band rather than wherever its old weight left it.
// closedDays is passed already floored by [staleDays]; the inverted term stays
// inside the units lane, so the whole band still lands at or below -1 and can
// never reach a live row's floor of 0.
func rankScore(sev Severity, w, stale, closedDays int) int {
	if sev == SevDone {
		return sev.rank()*rankSeverityMultiplier + (rankTermCap - min(closedDays, rankTermCap))
	}
	return sev.rank()*rankSeverityMultiplier +
		min(w, rankTermCap)*rankWeightMultiplier +
		min(stale, rankTermCap)
}

// frontier is the one-line human summary. Display-only; it does not feed
// rank_score. The kinds that describe themselves do so instead of reporting a
// roll-up they do not have.
func frontier(a Anchor, r rollup, held bool, takeaway string, waitingOpen []string, dispDue, isRuled, isRuledInFlight bool,
	closedDays int, owedSince, now time.Time) string {
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
	case !a.ClosedAt.IsZero():
		return "closed " + agePhrase(closedDays)
	case a.Source == "unowned":
		return "unowned convoy — no owning bead"
	case a.Source == kindReview:
		return "in review"
	case a.Source == kindRework:
		return "in rework"
	// Parallel to the parked phrase below, and for the same reason: the row is
	// reporting what it IS, because it has no roll-up to report instead. A
	// ruled row that decomposed skips this and reports its counts.
	case isRuled && r.mTotal == 0:
		return "ruled — takeaway recorded"
	// A ruled row whose slung work is still open reports that its ruling is
	// being acted on — distinct from the settled phrase above and from the
	// un-ruled arm below. Childless like the settled case; a decomposed one
	// reports its counts.
	case isRuledInFlight && r.mTotal == 0:
		return "ruled — work in flight"
	case !isRuled && !isRuledInFlight && a.Source == "decision":
		return "human-gated decision"
	// A merge anchor names the pull request instead, and OUTRANKS the
	// human-routed phrase below, which is not a competing fact but a less
	// specific version of the same one: a wedged anchor is routed to a person
	// precisely because no agent will take it, and the operator still has to
	// know WHICH pull request that is.
	//
	// Only while the anchor names one. An anchor at a human state can carry
	// merge_result with no branch and no number, and there the naming is not
	// more specific than the phrase below but emptier than it.
	//
	// And only over a phrase that says WHO holds the row. The identity is the
	// specific version of "routed to a person"; it is not a version of
	// "a blocker landed", which is news the identity does not carry, so the
	// disposition phrase further down keeps its row. NEEDS already orders the
	// two that way, ahead of everything.
	case isMergeAnchor(a) && !dispDue && prIdentity(a) != "":
		return prFrontier(a, owedSince, now)
	// The marker, not the kind, for the reason [severity] gives: a bead's
	// `human` and `parked` rows are one bead and must not describe it two ways.
	case !isRuled && !isRuledInFlight && humanGated(a):
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
		// The phrase is a CLAIM about what the sitting left behind, so it may
		// not be made on a row that left nothing — NEEDS says the same thing
		// one column over, and the two must not contradict each other.
		if takeaway == "" {
			return "conversation parked — no takeaway recorded"
		}
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
func needs(a Anchor, r rollup, held bool, takeaway string, dispDue, isRuled bool,
	machine, approval string, ask *Blocker, prIsOwed bool, stallReason string) string {
	// A closed anchor outranks even the takeaway. The sentence a sitting left
	// describes what the row wanted while it was live; a closed row wants
	// nothing now — it ages out of the DONE band on its own once it has been
	// closed longer than the window. The takeaway itself stays on the wire.
	if !a.ClosedAt.IsZero() {
		return "closed — ages out"
	}
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
	// A stalled pre-open codex gate names the gate and why it is stuck, ahead of
	// the merge-anchor position phrase below: the position is exactly what has
	// gone stale ("in the merge cadence" while no review runs), and stallReason is
	// non-empty only for that shape, so this case cannot fire on any other row.
	case stallReason != "":
		return preOpenStallNeeds(stallReason)
	case a.Source == "unowned":
		return "unowned — assign an owning bead"
	case a.Source == kindReview:
		return "review in flight"
	case a.Source == kindRework:
		return "rework in flight"
	case a.Source == "decision":
		return "operator decision"
	// A merge anchor whose POSITION is what puts it in the queue answers with
	// that position, and outranks the human-routed phrase below: a wedged or
	// asked-about anchor is routed to a person precisely because nothing else
	// will move it, so "no question recorded" would deny the one question the
	// row is carrying.
	//
	// Only then. A person also routes an anchor the cadence is happily working
	// — for a reason the machine axis knows nothing about — and there the
	// position is not the ask but a denial of it: a row in the operator's own
	// queue reading "in the merge cadence" says an agent has it. The empty
	// takeaway under a hand-set route is the finding on those rows, and the
	// phrase below is the one that names it.
	case isMergeAnchor(a) && prIsOwed:
		return prNeeds(machine, approval, ask)
	// The two kinds a PERSON put here. On these the empty takeaway is itself
	// the finding — whoever routed or parked the row never recorded what is
	// owed — so the phrase names that rather than reading like a valid ask a
	// silent row cannot support.
	case humanGated(a):
		return "routed to you — no question recorded"
	case a.Source == "parked" && r.mTotal == 0:
		return "parked for you — no question recorded"
	// Nobody is owed this one, so it reports where the cadence has it. Ahead of
	// the roll-up phrases below because a merge anchor does not decompose: its
	// children are the rework and review beads the cadence files, and
	// "no children — decompose or assign" would ask for work that is not the
	// row's to do.
	case isMergeAnchor(a):
		return prNeeds(machine, approval, ask)
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

// agePhrase renders whole days as the terminal table's age idiom. It exists so
// the DONE band answers "when" without a timestamp column: the row's own
// closed_at is on the wire for anything that wants the instant.
func agePhrase(days int) string {
	if days == 0 {
		return "today"
	}
	return fmt.Sprintf("%dd ago", days)
}

// --- the PR round-trip (specs/tk-q0ml23) --------------------------------------

// The two axes and the approval clause, as the wire spells them. The machine
// values are lifecycle/lifecycle.toml's [machine_axis].machines; lifecycle.test.sh
// fails on drift between the two lists.
const (
	MachineProgressing     = "progressing"
	MachineSettled         = "settled"
	MachineWedgedException = "wedged-exception"
	MachineWedgedVeto      = "wedged-veto"

	// AxisUnknown is a RENDERED value on both axes, never a fallback to the
	// quiet end. An unreadable axis and a clear one are not interchangeable,
	// and only the gather can tell them apart — the same rule
	// [Anchor.WaitingUnknown] already applies to an unreadable edge set.
	AxisUnknown = "unknown"

	// ConversationUnknown is what every row reads today. The other values all
	// resolve to acknowledgement watermarks that do not exist yet, and a guess
	// resolves to silence, which is the one answer that tells the operator to
	// stop looking.
	ConversationUnknown = AxisUnknown

	ApprovalRequired    = "required"
	ApprovalMet         = "met"
	ApprovalNotRequired = "not_required"
)

// The anchor metadata the axes are read from.
const (
	mdMergeResult = "merge_result"
	mdCheckSet    = "check_set"
	mdPRMachine   = "pr.machine"
	mdPRPosture   = "pr_posture"
	mdPRNumber    = "pr_number"
	mdPRURL       = "pr_url"
	mdBranch      = "branch"

	// The posture vocabulary pr-facts.sh records, mirroring
	// lifecycle/lifecycle.toml [posture].postures.
	postureChangesRequested = "changes_requested"
	postureCommented        = "commented"
	postureApproved         = "approved"
	postureReviewRequired   = "review_required"
	postureNone             = "none"
)

// isMergeAnchor reports whether this row is a merge anchor at all. Only those
// carry the PR axes; every other row leaves them EMPTY rather than `unknown`,
// because "not a pull request" and "a pull request whose position could not be
// read" are different answers and only the second counts against coverage.
func isMergeAnchor(a Anchor) bool { return a.Metadata[mdMergeResult] != "" }

// splitDated reads the <value>@<oid>@<since> shape lifecycle.sh writes. The
// instant lives INSIDE the value rather than in a key beside it, so a reader
// that trusts the value has already trusted the instant; a value in any other
// shape yields ok=false and is treated as unread.
func splitDated(v string) (value, oid string, since time.Time, ok bool) {
	parts := strings.Split(v, "@")
	if len(parts) != 3 || parts[0] == "" || parts[1] == "" {
		return "", "", time.Time{}, false
	}
	ts, err := time.Parse(time.RFC3339, parts[2])
	if err != nil {
		return "", "", time.Time{}, false
	}
	return parts[0], parts[1], ts, true
}

func isWedge(v string) bool {
	return v == MachineWedgedException || v == MachineWedgedVeto
}

func knownMachine(v string) bool {
	return v == MachineProgressing || v == MachineSettled || isWedge(v)
}

// poolRouted reports whether an open blocker has an automated actor behind it.
//
// The ROUTE is the discriminator, and both halves of that matter. Keying on
// `anchor_bead` would be too narrow: only review children carry it, while the
// rework children that hold an anchor between rounds carry `source_review_bead`
// or nothing. Reading every open blocker would be too wide the other way: an
// anchor also blocks on ordinary prerequisites and on the demand bead that
// makes it `asking`, and no pool will claim either. signoff.sh and pr-facts.sh
// both stamp the route on the child and read it back before reporting it
// dispatched, so it is exactly the beads a pool can take.
func poolRouted(b Blocker) bool {
	return b.Status != "closed" && b.RoutedTo != "" && b.RoutedTo != routedHuman
}

// demand reports whether an open blocker is something a PERSON owes.
//
// Read with the board's own vocabulary: a ruling only the operator can give is
// a `decision`, and anything else a person holds carries the route that says
// so. Either way no automated actor will close it, which is what makes the
// anchor `asking` rather than busy.
//
// The route clause is deliberately wider than the `decision` type alone. An
// anchor parked for the operator is a person's to answer whether or not that
// wait has been expressed as a decision bead, so narrowing this to the type
// would hide every wait that has not been. The row names what it is waiting
// on, so a reader can see that two rows in the queue share one cause.
//
// A visit never reaches here: escalate.sh attaches one with a `tracks` edge, so
// it is not a blocker at all.
func demand(b Blocker) bool {
	return b.Status != "closed" &&
		(b.IssueType == "decision" || b.RoutedTo == routedHuman)
}

// prMachine is what the merge cadence can do with this anchor on its next pass.
//
// Read off the bead, with ONE live upgrade. A recorded wedge always stands: it
// is the stronger statement, and an operator who loses sight of a wedge has
// lost the row this surface exists to show. Below that, an open pool-routed
// blocker means an actor is due to act whatever the last gate pass recorded —
// that half of the derivation is a bead read the gather already makes, while
// the marker-versus-live-head half needs a `git ls-remote` the render path must
// not do, which is why the cadence records it.
func prMachine(a Anchor, blockers []Blocker) string {
	if !isMergeAnchor(a) {
		return ""
	}
	v, _, _, ok := splitDated(a.Metadata[mdPRMachine])
	if ok && isWedge(v) {
		return v
	}
	for _, b := range blockers {
		if poolRouted(b) {
			return MachineProgressing
		}
	}
	if ok && knownMachine(v) {
		return v
	}
	return AxisUnknown
}

// prApproval answers one question: is GitHub withholding the merge for a human
// review? It reads the posture pr-facts.sh records off the review decision it
// already fetches, and the mapping is TOTAL over the posture's value set,
// because a partial one leaves the rest to be invented.
//
//	review_required, changes_requested -> required
//	approved                           -> met
//	commented, none                    -> not_required
//
// `not_required` has to be reachable from an ordinary row: most pull requests
// carry no protection rule and no review, so if `none` fell through to unknown
// the field would report a gap that is not there and hold the coverage sentence
// open forever. `changes_requested` is `required` because the requirement
// stands and is unmet, and a pull request GitHub is blocking must never render
// as one it will let through.
//
// The reference head is the one pr.machine was last recorded at — the newest
// head the merge cadence actually resolved. A posture pinned to any other head
// was read before the cadence moved on and says nothing about the current one,
// which is the "pinned to a head that is no longer live" case. The board learns
// the live head this way rather than by asking GitHub, which the render path
// must not do.
func prApproval(a Anchor) string {
	if !isMergeAnchor(a) {
		return ""
	}
	posture, postureHead, _, postureOK := splitDated(a.Metadata[mdPRPosture])
	_, machineHead, _, machineOK := splitDated(a.Metadata[mdPRMachine])
	if !postureOK || !machineOK || postureHead != machineHead {
		return AxisUnknown
	}
	switch posture {
	case postureReviewRequired, postureChangesRequested:
		return ApprovalRequired
	case postureApproved:
		return ApprovalMet
	case postureCommented, postureNone:
		return ApprovalNotRequired
	}
	return AxisUnknown
}

// askingDemand is the open demand bead this anchor is waiting on, or nil.
//
// `asking` needs no key of its own: it IS the edge, and closing the bead is
// what ends the state.
// The OLDEST demand wins, because it is the one whose turn started first and
// the queue is ordered by how long a row has been owed.
func askingDemand(blockers []Blocker) *Blocker {
	var oldest *Blocker
	for i := range blockers {
		b := &blockers[i]
		if !demand(*b) {
			continue
		}
		if oldest == nil || (!b.CreatedAt.IsZero() &&
			(oldest.CreatedAt.IsZero() || b.CreatedAt.Before(oldest.CreatedAt))) {
			oldest = b
		}
	}
	return oldest
}

// prOwed applies the owed rule to a merge anchor, and dates it.
//
// A row is owed by the operator when the machine axis is wedged, when the city
// is asking and waiting on an answer, or when the cadence is done and GitHub is
// holding the merge for a review nobody has given. A standing
// `changes_requested` is excluded on purpose: the requirement is unmet, and
// `pr_approval` says so, but ANSWERING a rejecting review is the city's move.
// It returns to the operator as `review_required` once the fix moves the head.
//
// since is the EARLIEST instant among the causes the row currently holds. A row
// wedged three days ago and asked about an hour ago has been owed for three
// days, and the queue ranks it there. No single stage of the cadence evaluates
// the whole rule, so no single writer could keep one owed-since key honest;
// each cause is dated instead by the writer that already decides it, and a
// cause whose input reads unknown contributes no instant at all — an unreadable
// input belongs in the coverage sentence, not in a clock reporting the wait as
// new.
func prOwed(a Anchor, machine, approval string, ask *Blocker) (bool, time.Time) {
	if !isMergeAnchor(a) {
		return false, time.Time{}
	}
	var since time.Time
	note := func(t time.Time) {
		if t.IsZero() {
			return
		}
		if since.IsZero() || t.Before(since) {
			since = t
		}
	}
	owed := false

	if isWedge(machine) {
		owed = true
		// A head move is what releases a wedge, so the instant rides the
		// head-pinned key that records it.
		if _, _, at, ok := splitDated(a.Metadata[mdPRMachine]); ok {
			note(at)
		}
	}
	if ask != nil {
		owed = true
		// A demand still holds its question after the branch advances, so it is
		// read at the bead's own created_at rather than at a head-pinned key.
		note(ask.CreatedAt)
	}
	if machine == MachineSettled && approval == ApprovalRequired {
		if posture, _, at, ok := splitDated(a.Metadata[mdPRPosture]); ok &&
			posture != postureChangesRequested {
			owed = true
			// A new commit is a new thing to approve, so this one is
			// head-pinned too.
			note(at)
		}
	}
	return owed, since
}

// PRCoverage is what the board could and could not read about the pull requests
// it holds — the counts the owed section states alongside its store coverage.
//
// That section's empty state is a contract: it renders its coverage or it
// renders the error, never a blank. PR rows add a way for it to go quietly
// wrong that beads alone did not have, because an axis nothing has recorded
// looks exactly like an axis with nothing to say.
type PRCoverage struct {
	// Rows is every LIVE merge anchor on the board, owed or not. A closed
	// anchor keeps its axes so the DONE band can render them, but an unread
	// position on a row nobody will act on is not a gap in what the operator
	// needs to see.
	Rows int
	// MachineUnknown is the rows whose position the merge cadence has not
	// recorded. A missing key is a fact about the city, not an all-clear.
	MachineUnknown int
	// ConversationUnknown is the rows whose exchange with the operator cannot
	// be read. In this phase that is every row: the values depend on
	// acknowledgement watermarks nothing records yet.
	ConversationUnknown int
	// ApprovalUnanswered is the SETTLED rows whose approval clause could not be
	// read. Those are the rows where the question "is GitHub holding this for a
	// human?" is both live and unanswerable, which is exactly the shape that
	// would otherwise read as nobody's move.
	ApprovalUnanswered int
}

// Complete reports whether every PR row on the board had a readable position.
// [Tile.Owed] is a boolean and cannot carry the third value the axes do, so an
// unread input has to surface as coverage rather than as a false negative on
// the row — which is why an empty queue is only an all-clear when this holds.
func (c PRCoverage) Complete() bool {
	return c.MachineUnknown == 0 && c.ConversationUnknown == 0 && c.ApprovalUnanswered == 0
}

// Coverage counts the PR rows across the WHOLE board, not just the queue. The
// sentence it feeds is printed when the queue is empty, and a row missing from
// an empty queue is precisely the row that might have belonged in it.
//
// Closed rows are the exception, and they have to be, because the queue and
// this count have to empty together. The gather makes a second pass at closed
// anchors to fill the DONE band, and those rows carry the same axes as live
// ones — including the unknowns. [Tile.Owed] already excludes them, so counting
// them here would withhold the all-clear over rows the queue is right to omit,
// for as long as the done window holds them.
func Coverage(tiles []Tile) PRCoverage {
	var c PRCoverage
	for _, t := range tiles {
		if t.PRMachine == "" || !t.ClosedAt.IsZero() {
			continue // not a merge anchor, or closed: nothing left to cover
		}
		c.Rows++
		if t.PRMachine == AxisUnknown {
			c.MachineUnknown++
		}
		if t.PRConversation == AxisUnknown {
			c.ConversationUnknown++
		}
		if t.PRMachine == MachineSettled && t.PRApproval == AxisUnknown {
			c.ApprovalUnanswered++
		}
	}
	return c
}

// prNumber reads the anchor's recorded PR number, 0 before the PR opens.
func prNumber(a Anchor) int {
	n, err := strconv.Atoi(strings.TrimSpace(a.Metadata[mdPRNumber]))
	if err != nil || n < 0 {
		return 0
	}
	return n
}

// prConversation is where the exchange with the operator stands. Every merge
// anchor reads `unknown` in this phase: `outstanding`, `covered` and `answered`
// all resolve to acknowledgement watermarks nothing records yet, and building
// them before those land means guessing. Every failed guess resolves to
// "nothing has been said", which is the one answer that tells the operator to
// stop looking. The field ships now so the wire contract does not change shape
// when the watermarks do land.
func prConversation(a Anchor) string {
	if !isMergeAnchor(a) {
		return ""
	}
	return ConversationUnknown
}

// prFrontier identifies the pull request and says how long the turn has been
// running. The queue is ordered by that age and nothing else, so the row has to
// carry it: an operator scanning a sorted list cannot see the sort key.
//
// A row nothing is owed on prints no age. Zero is not "owed since the epoch"
// and not "owed for no time" — it is the absence of a cause, and inventing a
// duration for it would report a wait that is not happening.
func prFrontier(a Anchor, owedSince, now time.Time) string {
	id := prIdentity(a)
	if owedSince.IsZero() {
		return id
	}
	return id + " · owed " + humanSince(owedSince, now)
}

// prIdentity names the pull request: its number once one is open, the branch
// before that, and the EMPTY string when the anchor records neither. The branch
// is an ordinary case rather than a fallback, because most wedged anchors have
// no pull request open at all.
//
// The empty string is what keeps [frontier] honest. An anchor at a human state
// carries merge_result and can carry nothing else, and a row's one summary line
// is worth more spent on who holds it than on naming an absence.
func prIdentity(a Anchor) string {
	if n := prNumber(a); n > 0 {
		return fmt.Sprintf("PR #%d", n)
	}
	return prBranch(a)
}

// prBranch is the branch half of [prIdentity], on its own so the wire can carry
// it as data. It is gated on the anchor being a merge anchor for the reason the
// other axes are: an ordinary work bead carries `branch` too, and a row that is
// not a pull request's must answer "" rather than name one.
func prBranch(a Anchor) string {
	if !isMergeAnchor(a) {
		return ""
	}
	return a.Metadata[mdBranch]
}

// humanSince is a coarse age for a queue ordered by it. Days once there is a
// day to report, hours below that, and "just now" below an hour: the queue
// spans days, and a minute-accurate figure on a three-day wedge is noise
// pretending to be precision.
func humanSince(t, now time.Time) string {
	d := now.Sub(t)
	switch {
	case d < time.Hour:
		return "just now"
	case d < 24*time.Hour:
		return fmt.Sprintf("%dh", int(d.Hours()))
	default:
		return fmt.Sprintf("%dd", int(d.Hours()/24))
	}
}

// prNeeds is a merge anchor's one-glance ask, in the order an operator can act
// on: a wedge names its shape and its release, a question names itself, an
// unmet approval names the one thing that would land the row, and a row nothing
// is owed on says who has it. `unknown` says the cadence has not recorded a
// position, which is a fact about the city rather than an all-clear.
func prNeeds(machine, approval string, ask *Blocker) string {
	switch {
	case machine == MachineWedgedException:
		return "wedged: the review cap parked this anchor — a ruling releases it, a new commit does not"
	case machine == MachineWedgedVeto:
		return "wedged: a standing CHANGES_REQUESTED with the rework rounds spent"
	case ask != nil:
		if t := collapseWS(ask.Title); t != "" {
			return "asking: " + t
		}
		return "asking — waiting on an answer"
	case machine == MachineSettled && approval == ApprovalRequired:
		return "green, waiting on your review"
	case machine == MachineProgressing:
		return "in the merge cadence"
	case machine == MachineSettled:
		return "green — waiting on the merge pass"
	default:
		return "position unknown — the merge cadence has recorded none"
	}
}

// The pre-open codex gate the stall signal reads. mergeResultPreOpenGate is the
// merge_result of an anchor parked at that gate, before any PR exists;
// checkSetCodex is the only gate set this city runs there; mdCheckPrefix+the set
// names the gate marker (check.codex); and checkGreen is the settled marker value
// on which pre-open-resolve opens the PR.
const (
	mergeResultPreOpenGate = "pre_open_gate"
	checkSetCodex          = "codex"
	mdCheckPrefix          = "check."
	checkGreen             = "green"

	stallReasonNeverReviewed       = "never-reviewed"
	stallReasonFindingsOpen        = "findings-open"
	stallReasonReviewedNotAdvanced = "reviewed-not-advanced"
)

// preOpenStaleThresholdDays is how long a pre-open codex gate may hold before the
// board reads it as STALLED rather than in-flight. Three days is the floor below
// which a hold is still plausibly a fresh, healthy park. It is deliberately far
// tighter than staleThresholdDays: that clock stale-bumps an already-NORMAL row,
// while a childless pre-open gate bands LOW and never reaches the bump at all.
const preOpenStaleThresholdDays = 3

// preOpenCodexStall reports whether a merge anchor is stuck at the pre-open codex
// gate with nothing moving it, and dates the stall for the owed clock.
//
// It fires only on the bare held shape — the one prOwed leaves with no cause of
// its own. A recorded wedge, a demand, or a settled-and-unapproved position each
// already owns the row: prOwed dates it and prNeeds names it. This adds a cause
// for what is left, the anchor whose position reads "in the merge cadence" (a
// stale progressing marker) or "position unknown" while no review is actually
// running. The caller keeps the stronger surfacings — disposition, ruling,
// takeaway, human route — out by not calling here for them.
//
// A LIVE review or rework suppresses it; a routed-but-unclaimed one does not.
// Routed-ness alone is what prMachine already reads as "progressing", and a pool
// nothing is draining is exactly the invisible stall this signal exists to show,
// so the suppression turns on a live worker, not on a route.
//
// since is the anchor's own updated_at: the signal fires only once that is old,
// and a genuinely stalled anchor is touched by nothing, so the last-touch instant
// is when it went quiet. An anchor a reconcile pass still writes is fresh and
// never reaches the threshold, which is the correct non-fire.
func preOpenCodexStall(a Anchor, machine string, blockers []Blocker, stale int, f Facts) (stalled bool, since time.Time, reason string) {
	if a.Metadata[mdMergeResult] != mergeResultPreOpenGate || a.Metadata[mdCheckSet] != checkSetCodex {
		return false, time.Time{}, ""
	}
	// A recorded wedge already owns the row — owed, dated, named — so leave it to
	// prOwed/prNeeds rather than restating it in weaker words.
	if isWedge(machine) {
		return false, time.Time{}, ""
	}
	// The gate has gone green: pre-open-resolve opens the PR on its next pass, so
	// the anchor is about to leave this state, not stalled in it. The lane marker
	// carries a bare state word, so a settled gate is an exact "green".
	if a.Metadata[mdCheckPrefix+checkSetCodex] == checkGreen {
		return false, time.Time{}, ""
	}
	// A live review or rework is the healthy hold — something is moving it.
	if liveReviewOrRework(blockers, f) {
		return false, time.Time{}, ""
	}
	if stale < preOpenStaleThresholdDays {
		return false, time.Time{}, ""
	}
	return true, a.UpdatedAt, preOpenStallReason(blockers)
}

// liveReviewOrRework reports whether an open review or rework child of a merge
// anchor is actually being WORKED: one the cadence titled "Review …"/"Rework …"
// whose worker is a live session, or which a live workflow stands over.
//
// It reads the title shape, not gc.routed_to. A real mol-review child is not
// route-stamped — `gc sling` leaves the child open and puts the in-flight state
// on the workflow, visible only through [Facts.Inflight] — and a rework child
// carries no task_kind either, so a route key would miss exactly the live
// reviews this suppression exists to honor and read them as stalls.
// preOpenStallReason reads the same titles. A review or rework no live session is
// draining is NOT in flight — that is the dead-pool hold the stall signal exists
// to surface — so liveness, not the child's mere existence, is the gate.
func liveReviewOrRework(blockers []Blocker, f Facts) bool {
	for _, b := range blockers {
		if !isReviewOrRework(b) {
			continue
		}
		if f.ownerLive(b.Assignee) || f.wfLive(b.ID) {
			return true
		}
	}
	return false
}

// isReviewOrRework reports whether a blocker is one of the cadence's open review
// or rework children — the beads that legitimately hold a merge anchor at the
// pre-open gate while one runs. signoff.sh and pr-facts.sh title them "Review …"
// and "Rework …"; the title is the discriminator because neither the route nor
// the type identifies the pair (a mol-review child is not route-stamped and a
// rework child carries no task_kind).
func isReviewOrRework(b Blocker) bool {
	return b.Status != "closed" &&
		(strings.HasPrefix(b.Title, "Review ") || strings.HasPrefix(b.Title, "Rework "))
}

// preOpenStallReason names WHY the gate is stuck, for the NEEDS line. It reads
// the blocker titles the cadence writes (signoff.sh / pr-facts.sh file "Review
// branch …" / "Review PR#…" and "Rework branch …"): an open rework child means
// findings are filed and unaddressed; a review that has run with no open rework
// means the branch was reviewed but never advanced to a PR; neither means no
// review has run at all. It is a best-effort hint, so it degrades to
// never-reviewed rather than guessing when a title does not match.
func preOpenStallReason(blockers []Blocker) string {
	openRework, reviewed := false, false
	for _, b := range blockers {
		switch {
		case strings.HasPrefix(b.Title, "Rework "):
			if b.Status != "closed" {
				openRework = true
			} else {
				reviewed = true // a rework exists only after a review filed findings
			}
		case strings.HasPrefix(b.Title, "Review "):
			reviewed = true
		}
	}
	switch {
	case openRework:
		return stallReasonFindingsOpen
	case reviewed:
		return stallReasonReviewedNotAdvanced
	default:
		return stallReasonNeverReviewed
	}
}

// preOpenStallNeeds is the NEEDS sentence for a stalled pre-open codex gate. It
// names the codex gate rather than reading "in the merge cadence"; the age rides
// the frontier's owed clock, so it is not repeated here.
func preOpenStallNeeds(reason string) string {
	switch reason {
	case stallReasonFindingsOpen:
		return "codex gate stalled — findings open, none in flight"
	case stallReasonReviewedNotAdvanced:
		return "codex gate stalled — reviewed, not advanced"
	default:
		return "codex gate stalled — no review has run"
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

// --- the attention-type sections --------------------------------------------
//
// A section bands a row by the KIND of move it wants, a different axis from
// [Severity]'s how-badly: the band says whether to review, answer, rescue,
// watch, or dispose of the row. It is a small fixed set the operator reads in
// one order, so a column of unlike things — a pull request, a decision, a
// stranded epic, a finished conversation — resolves into a handful of intents
// rather than one flat rank.
//
// One row lands in exactly one section, and [classifySection] is the total
// mapping. It reads the tile's already-derived facts rather than re-deriving
// them, so the band cannot disagree with the frontier and needs computed from
// the same state.
const (
	SectionReview  = "review"  // a pull request wants the operator
	SectionGate    = "gate"    // a person must answer: decision, demand, human-route, disposition
	SectionStalled = "stalled" // open work with nothing moving it, or an unowned convoy
	SectionActive  = "active"  // healthy in-flight roll-up work
	SectionCleanup = "cleanup" // a finished, empty or ruled row to dispose of
	SectionDone    = "done"    // the anchor's own bead has closed
)

// SectionOrder is the order a surface reads the bands in — most-pressing first.
// Review and gate are the operator's own moves and lead; stalled is the loudest
// health signal under them; active is the city working normally; cleanup and
// done are the quiet tail. A renderer iterates this, never an ad-hoc list, so
// the CLI and the dashboard cannot present the bands in two different orders.
var SectionOrder = []string{
	SectionReview, SectionGate, SectionStalled, SectionActive, SectionCleanup, SectionDone,
}

// classifySection places a tile in its attention band. The order of the arms is
// the precedence: a live pull request is review even when it is also owed, a
// closed row is done whatever else it carries, and the owed test comes before
// the health tests because a demand the operator owes is not "stalled work" —
// it is the operator's move.
//
// It is a function of the finished [Tile] on purpose, so the visit fold can
// re-run it after flipping a folded subject to owed without re-deriving the
// anchor. Every input is a field the tile already carries: PRMachine is
// non-empty exactly on a merge anchor, and Stranded/DeadOwner/Kind/Owed/Severity
// are the same booleans severity() and computeTile() set.
func classifySection(t Tile) string {
	switch {
	case t.Severity == SevDone:
		return SectionDone
	case t.PRMachine != "":
		// A merge anchor is a pull request's row whether the cadence is working
		// it or it is wedged on the operator; the round-trip axes carry which.
		return SectionReview
	case t.Owed:
		// Owed is humanGated-and-unruled, disposition-due, or a PR owed by the
		// operator; the PR case already went to review, so what is left is a
		// person's answer on a bead.
		return SectionGate
	case t.Stranded || t.DeadOwner || t.Kind == "unowned":
		return SectionStalled
	case t.Severity == SevLow:
		// Empty, complete, ruled, or a childless parked conversation — nothing is
		// asking, the row only wants disposing of or ages out on its own.
		return SectionCleanup
	case len(t.ParkedHeads) > 0 && t.Open == len(t.ParkedHeads) && t.InProgressLive == 0:
		// Every open child is parked for the operator and nothing else is moving.
		// The parent is not active work — it is waiting on the operator to rule
		// those child rows — so it bands gate rather than masquerading as
		// in-flight.
		return SectionGate
	default:
		return SectionActive
	}
}

// computeTile derives a single tile from an anchor. now is the board's
// generation instant, shared by every tile so one board never mixes staleness
// measured against two different clock reads.
func computeTile(a Anchor, now time.Time, f Facts) Tile {
	r := rollUp(a.Children, f)
	held := f.Visits[a.ID]
	stale := staleDays(a.UpdatedAt, now)
	closedDays := staleDays(a.ClosedAt, now)
	xrefs := crossRigRefs(a, f)
	waiting, waitingOpen := waitingSplit(a)
	takeaway := collapseWS(a.Takeaway)
	dispDue := dispositionDue(a, waiting, waitingOpen)
	isRuled := ruled(a, takeaway, waitingOpen)
	isRuledInFlight := ruledInFlight(a, takeaway, waitingOpen)

	machine := prMachine(a, a.Blockers)
	approval := prApproval(a)
	ask := askingDemand(a.Blockers)
	prIsOwed, owedSince := prOwed(a, machine, approval, ask)

	// A pre-open codex gate that nothing is advancing — no live review, no
	// in-flight rework, past the staleness floor — bands LOW when childless, its
	// position reading "in the merge cadence" indistinguishably from a healthy
	// hold. Give it an owed cause so it carries its age and leaves the floor. Only
	// for the bare held shape, though: a disposition, a ruling, a takeaway, a
	// human route, or an open demand already owns the row and names it — the
	// demand as its own `asking: <title>`, the operator's actual question — so
	// those are excluded before the gate is read, not overwritten with the gate's
	// generic wording.
	stalled, stalledReason := false, ""
	if a.ClosedAt.IsZero() && !dispDue && !isRuled && !humanGated(a) && takeaway == "" && ask == nil {
		var stalledSince time.Time
		stalled, stalledSince, stalledReason = preOpenCodexStall(a, machine, a.Blockers, stale, f)
		if stalled {
			prIsOwed = true
			if owedSince.IsZero() || (!stalledSince.IsZero() && stalledSince.Before(owedSince)) {
				owedSince = stalledSince
			}
		}
	}

	sev := severity(a, r, held, stale, dispDue, isRuled, isRuledInFlight, stalled)
	w := weight(r, a.Priority, xrefs)

	// progress_mismatch: the convoy's own closed/total claim disagrees with the
	// membership actually rolled up. Only meaningful where the source supplied
	// a progress object.
	mismatch := a.Progress != nil &&
		(a.Progress.Total != r.mTotal || a.Progress.Closed != r.nClosed)

	t := Tile{
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
		//
		// A CLOSED anchor is never owed, whatever markers it still carries. The
		// queue is ordered by how long a demand has waited, so admitting one
		// would hoist it above every live demand — the exact opposite of the
		// terminal band [rankScore] floors it into. It gates every cause,
		// the merge anchor's included.
		Owed: a.ClosedAt.IsZero() && ((humanGated(a) && !isRuled && !isRuledInFlight) || dispDue || prIsOwed),

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
		// to the operator has the operator's. Once ruled — settled, or with
		// slung work still in flight — the gate is discharged and open children
		// under it are ordinary idle work again, so the exemption ends exactly
		// where the band's does.
		Stranded: r.mTotal > 0 && r.idle() > 0 && len(r.liveHeads) == 0 && !held &&
			!(humanGated(a) && !isRuled && !isRuledInFlight),
		Empty: r.mTotal == 0 && a.Source != "decision" && a.Source != "unowned" &&
			a.Source != "human" && a.Source != "parked" && a.Source != "merge" &&
			!isReviewReworkKind(a.Source),
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
		ClosedAt:  a.ClosedAt,
		Frontier:  frontier(a, r, held, takeaway, waitingOpen, dispDue, isRuled, isRuledInFlight, closedDays, owedSince, now),
		Needs:     needs(a, r, held, takeaway, dispDue, isRuled, machine, approval, ask, prIsOwed, stalledReason),
		RankScore: rankScore(sev, w, stale, closedDays),

		PRNumber:       prNumber(a),
		PRURL:          a.Metadata[mdPRURL],
		PRBranch:       prBranch(a),
		PRMachine:      machine,
		PRConversation: prConversation(a),
		PRApproval:     approval,
		PROwedSince:    owedSince,
	}
	// The band is a function of the finished tile, so the visit fold can re-run
	// it after flipping a folded subject to owed. ClusterKey stays empty here;
	// it needs the whole board to know a template recurs, so BuildBoard sets it.
	t.Section = classifySection(t)
	return t
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

	sort.SliceStable(tiles, func(i, j int) bool { return rankFirst(tiles[i], tiles[j]) })

	seen := make(map[string]struct{}, len(tiles))
	deduped := make([]Tile, 0, len(tiles))
	for _, t := range tiles {
		if _, dup := seen[t.ID]; dup {
			continue
		}
		seen[t.ID] = struct{}{}
		deduped = append(deduped, t)
	}

	// Fold visit and demand WRAPPERS into the subject they concern, so one
	// attention item is one row. This runs on the deduped set — after the twin
	// reconcile, before the owed partition — because a wrapper folds only onto a
	// subject that has a row, and both facts are settled by here.
	folded := foldWrappers(deduped, anchors)

	// Stamp each row's dependency family — the group it renders under. This runs
	// on the folded set, so a dropped wrapper is neither a family root nor a
	// member, and it reads the anchors' parent-child and blocks edges to climb
	// each row to its top-most tile.
	assignGroupRoots(folded, anchors)

	// Tag rows that are instances of one recurring template. This is last of the
	// derivation passes because it keys on the FINAL section and needs, which the
	// fold above can change.
	tagClusters(folded)

	sort.SliceStable(folded, func(i, j int) bool { return owedFirst(folded[i], folded[j]) })

	return Board{
		GeneratedAt:   now.UTC(),
		Total:         len(folded),
		Tiles:         folded,
		Sittings:      orderSittings(facts.Sittings),
		Partial:       partial,
		PartialErrors: partialErrors,
	}
}

// clusterThreshold is how many rows must share one section-and-needs before the
// board folds them into a single grouped entry. Two identical asks are a
// coincidence a reader absorbs at a glance; at three the repetition is a
// template worth collapsing. A separate entry per member is still on the wire;
// only the RENDER collapses, so nothing tooling reads is lost.
const clusterThreshold = 3

// foldWrappers collapses row-doubling. A visit bead (task_kind=visit, tracking
// its subject in gc.continuation_group) and a demand bead (gc.demand_for naming
// the work it gates) each carry gc.routed_to=human, so each is gathered as its
// OWN human anchor — a second row for an attention item its subject already
// carries. The doubling is deliberate graph structure (a tracks edge keeps the
// visit claimable; beads refuses a parent->descendant blocks edge, forcing the
// demand to be a sibling), so it cannot be fixed in the graph; the renderer
// recognises the edges instead.
//
// When the subject has a row of its own, the wrapper's ask moves onto it and the
// wrapper's row is dropped: the subject becomes `owed` and carries what the
// wrapper asked, and a folded visit also leaves it `held`. When the subject has
// NO row — a wrapper can name a plain bead that is no anchor — the wrapper stays,
// because dropping it would erase the only trace of the attention; its needs is
// rewritten from its own title so the kept row states the ask instead of the
// empty "routed to you — no question recorded".
func foldWrappers(tiles []Tile, anchors []Anchor) []Tile {
	anchorByID := make(map[string]Anchor, len(anchors))
	for _, a := range anchors {
		if _, ok := anchorByID[a.ID]; !ok {
			anchorByID[a.ID] = a
		}
	}
	idx := make(map[string]int, len(tiles))
	for i := range tiles {
		idx[tiles[i].ID] = i
	}
	// A wrapper whose subject is itself a wrapper must not fold onto a row that is
	// about to be dropped, so decide every drop first, then apply the folds.
	isWrapper := func(id string) bool {
		if a, ok := anchorByID[id]; ok {
			_, _, _, w := wrapperTarget(a)
			return w
		}
		return false
	}
	asks := make(map[string][]foldedAsk) // subject id -> the asks folded onto it
	drop := make(map[string]bool)
	for i := range tiles {
		a, ok := anchorByID[tiles[i].ID]
		if !ok {
			continue
		}
		subj, ask, kind, ok := wrapperTarget(a)
		if !ok {
			continue
		}
		// A CLOSED wrapper is a finished conversation, not a live ask. Leaving it
		// in the DONE band is right; folding it onto a subject would mark that
		// subject owed on the strength of a visit that already ended.
		if !tiles[i].ClosedAt.IsZero() {
			continue
		}
		if j, has := idx[subj]; has && subj != a.ID && !isWrapper(subj) && tiles[j].ClosedAt.IsZero() {
			asks[subj] = append(asks[subj], foldedAsk{ask: ask, kind: kind, owedSince: owedSince(tiles[i])})
			drop[a.ID] = true
		} else if ask != "" {
			// Kept wrapper: no LIVE subject row carries this attention, so the
			// wrapper states the ask itself. The ask is the NEEDS — the only
			// prose column the CLI board prints — and the TITLE names the
			// wrapper's kind and subject, so a surface that prints both columns
			// (the web board renders title beside needs) does not repeat the
			// same sentence in each. The raw title is "<kind>: <subject> —
			// <ask>", of which visitAsk already recovered the tail as the ask.
			tiles[i].Title = kind + ": " + subj
			tiles[i].Needs = ask
			tiles[i].Section = classifySection(tiles[i])
		}
	}
	for subj, folded := range asks {
		applyFold(&tiles[idx[subj]], folded)
	}
	if len(drop) == 0 {
		return tiles
	}
	out := make([]Tile, 0, len(tiles)-len(drop))
	for _, t := range tiles {
		if drop[t.ID] {
			continue
		}
		out = append(out, t)
	}
	return out
}

// wrapperTarget reports the subject a wrapper row concerns, the ask it carries,
// and its kind (wrapperVisit or wrapperDemand), or ok=false for an ordinary row.
// A visit points at its subject through gc.continuation_group; a demand through
// gc.demand_for. The kind matters at the fold: a demand is not visit presence,
// so it must not stamp Tile.Held.
func wrapperTarget(a Anchor) (subject, ask, kind string, ok bool) {
	if a.Metadata == nil {
		return "", "", "", false
	}
	if a.Metadata["task_kind"] == "visit" {
		if subj := a.Metadata[mdContinuationGroup]; subj != "" {
			return subj, visitAsk(a.Title), wrapperVisit, true
		}
		return "", "", "", false
	}
	if subj := a.Metadata[mdDemandFor]; subj != "" {
		// The authored question rides on the takeaway of a demand; its title is
		// the fallback for one filed without.
		ask := collapseWS(a.Takeaway)
		if ask == "" {
			ask = collapseWS(a.Title)
		}
		return subj, ask, wrapperDemand, true
	}
	return "", "", "", false
}

const (
	wrapperVisit  = "visit"
	wrapperDemand = "demand"
)

// mdContinuationGroup is the visit metadata key naming the subject a visit holds
// — the same field Facts.Visits keys Tile.Held on.
const mdContinuationGroup = "gc.continuation_group"

// visitAsk recovers the human ask from a visit's title. escalate.sh titles a
// visit "visit: <subject-id> — <message>", and the message is the ask; the
// label and the id prefix are noise on the subject's row. The id-prefix strip is
// bounded to a short span so a message that itself contains " — " keeps it.
func visitAsk(title string) string {
	s := collapseWS(title)
	s = strings.TrimSpace(strings.TrimPrefix(s, "visit:"))
	for _, sep := range []string{" — ", " - "} {
		if i := strings.Index(s, sep); i >= 0 && i <= 16 {
			s = strings.TrimSpace(s[i+len(sep):])
			break
		}
	}
	if s == "" {
		return collapseWS(title)
	}
	return s
}

// foldedAsk is one wrapper's contribution to the subject it folds onto: the ask
// text, the wrapper kind (Held is visit presence, so a demand must not set it),
// and the wrapper's own owed-since so the subject's owed clock can date the ask
// that created it rather than the subject's last touch.
type foldedAsk struct {
	ask       string
	kind      string
	owedSince time.Time
}

// applyFold moves one or more wrapper asks onto a subject tile. The subject is
// now owed — a person is asked to look at it — and its needs states the ask, so
// the one surviving row says both what the row is and what is wanted of it. Held
// is visit presence, so only a folded VISIT stamps it; a demand leaves it as the
// visit facts found it. The owed clock takes the earliest ask instant folded in,
// so the queue dates the row by when the ask began; an existing earlier instant,
// such as a merge anchor's PR clock, is kept rather than moved forward. A merge
// anchor also keeps its own PR needs: the pull-request position is the more
// specific ask and the wrapper only adds that a person is on it.
func applyFold(t *Tile, folded []foldedAsk) {
	t.Owed = true
	asks := make([]string, 0, len(folded))
	for _, f := range folded {
		asks = append(asks, f.ask)
		if f.kind == wrapperVisit {
			t.Held = true
		}
		if !f.owedSince.IsZero() && (t.PROwedSince.IsZero() || f.owedSince.Before(t.PROwedSince)) {
			t.PROwedSince = f.owedSince
		}
	}
	if t.PRMachine == "" {
		switch len(asks) {
		case 0:
		case 1:
			t.Needs = asks[0]
		default:
			t.Needs = fmt.Sprintf("%d× — %s", len(asks), strings.Join(asks, " · "))
		}
	}
	t.Section = classifySection(*t)
}

// tagClusters stamps ClusterKey on every row that is one of at least
// clusterThreshold rows sharing a section and a needs sentence. The DONE band is
// left alone: it is already capped and recency-ordered, and its rows are not
// attention the grouping exists to thin.
//
// A row carrying a TAKEAWAY never clusters, however many share its needs. The
// takeaway is per-bead content the operator has to read one at a time, and
// folding those rows into a count-plus-id-list loses it. This holds whether the
// takeaway is a unique LLM sentence or a deterministic one a script templated
// across anchors (a signoff-cap headline) that recurs identically across beads.
// Only a deterministic STATE phrase, which no bead authored, clusters; those the
// renderer folds with per-bead context, not an id soup.
func tagClusters(tiles []Tile) {
	type key struct{ section, needs string }
	clusterable := func(t Tile) bool {
		return t.Section != SectionDone && t.Needs != "" && t.Takeaway == nil
	}
	count := make(map[key]int, len(tiles))
	for _, t := range tiles {
		if !clusterable(t) {
			continue
		}
		count[key{t.Section, t.Needs}]++
	}
	for i := range tiles {
		if !clusterable(tiles[i]) {
			continue
		}
		if count[key{tiles[i].Section, tiles[i].Needs}] >= clusterThreshold {
			tiles[i].ClusterKey = tiles[i].Needs
		}
	}
}

// SectionGroup is one attention band and the tiles in it, in the order the
// caller ranked them. It is a RENDER helper, not a wire type: the section lives
// on each [Tile], and this only buckets a ranked slice so a surface iterates
// bands rather than re-deriving the split.
type SectionGroup struct {
	Key   string
	Tiles []Tile
}

// GroupBySection buckets tiles into the fixed [SectionOrder], preserving the
// caller's within-section order. An empty band is omitted. A tile whose section
// is not in the order (a value a newer derivation added) is appended under its
// own key after the known bands, so an unrecognised section shows rather than
// vanishing.
func GroupBySection(tiles []Tile) []SectionGroup {
	buckets := make(map[string][]Tile)
	for _, t := range tiles {
		buckets[t.Section] = append(buckets[t.Section], t)
	}
	out := make([]SectionGroup, 0, len(SectionOrder))
	for _, k := range SectionOrder {
		if len(buckets[k]) > 0 {
			out = append(out, SectionGroup{Key: k, Tiles: buckets[k]})
			delete(buckets, k)
		}
	}
	extra := make([]string, 0, len(buckets))
	for k := range buckets {
		extra = append(extra, k)
	}
	sort.Strings(extra)
	for _, k := range extra {
		out = append(out, SectionGroup{Key: k, Tiles: buckets[k]})
	}
	return out
}

// --- the dependency-family grouping ------------------------------------------
//
// A family is one top-level anchor and every tile that hangs off it by a
// parent-child or a `blocks` edge. Grouping by family is the board's primary
// axis; the attention band orders and highlights WITHIN a family. The grouping
// key is derived once here, shared by both renderers, so the CLI table and the
// dashboard cannot each invent their own split — exactly as [Section] is.

// assignGroupRoots stamps [Tile.GroupRoot] on every tile: the id of the
// top-most tile its edges climb to, or its own id when it climbs to nothing.
//
// Two edges climb: the parent-child edge (the anchor that rolls this tile up)
// and the blocked edge (the anchor this tile `blocks`, read off that anchor's
// WaitingOn). The walk keys on the EDGES, not on [Tile.Kind], so a convoy that
// renders `unowned` groups as the convoy it is — its `tracks` children are its
// family.
//
// Three cases the one-root rule settles, so a bead appears in exactly one
// family:
//
//   - A bead in two families — a child of one anchor and a blocker of another,
//     or a blocker of two. The parent-child edge (containment) is preferred over
//     a blocked edge, and among edges of the same kind the lowest anchor id wins.
//     Deterministic, and stated here so the rendered family cannot flap.
//   - A blocker that is itself a top-level family head. It stays the root of its
//     OWN family: a tile with tile children never climbs a blocked edge, so a
//     top-level epic that also blocks another anchor roots its own family and is
//     only a reference in the family it blocks. It CAN still climb a parent-child
//     edge — a nested epic joins its parent's family.
//   - A cross-rig (or otherwise danging) edge whose other end has no tile on this
//     board leaves the tile a root: the family is what this board can see.
//
// It runs on the FINAL tile set — after the visit/demand fold — so a dropped
// wrapper is neither root nor member, and only edges between surviving tiles
// count.
func assignGroupRoots(tiles []Tile, anchors []Anchor) {
	tileSet := make(map[string]bool, len(tiles))
	for i := range tiles {
		tileSet[tiles[i].ID] = true
	}
	// childParents[id] is the anchors that roll `id` up as a parent-child child;
	// blockedParents[id] is the anchors `id` blocks. hasTileChildren marks a tile
	// that heads a family, which is what stops it climbing a blocked edge. Edges
	// are unioned across the (possibly twinned) anchor rows for one id.
	childParents := map[string]map[string]bool{}
	blockedParents := map[string]map[string]bool{}
	hasTileChildren := map[string]bool{}
	addEdge := func(m map[string]map[string]bool, from, to string) {
		if from == to {
			return
		}
		if m[from] == nil {
			m[from] = map[string]bool{}
		}
		m[from][to] = true
	}
	for i := range anchors {
		a := anchors[i]
		if !tileSet[a.ID] {
			continue
		}
		for _, c := range a.Children {
			if tileSet[c.ID] {
				addEdge(childParents, c.ID, a.ID)
				hasTileChildren[a.ID] = true
			}
		}
		for _, wid := range a.WaitingOn {
			if tileSet[wid] {
				addEdge(blockedParents, wid, a.ID)
			}
		}
		// A review or rework child names its merge anchor directly in
		// metadata.anchor_bead. It also `blocks` that anchor, so the WaitingOn
		// climb above usually already links them — but the anchor_bead edge
		// resolves the child even when the anchor's edge gather was partial.
		if ab := a.Metadata[mdAnchorBead]; ab != "" && tileSet[ab] {
			addEdge(blockedParents, a.ID, ab)
		}
	}

	// parentFor picks the single anchor a tile climbs to, applying the one-root
	// rule: parent-child before blocked, lowest id within a kind, and no blocked
	// climb for a family head. "" means the tile is a root.
	lowest := func(m map[string]bool) string {
		best := ""
		for p := range m {
			if best == "" || p < best {
				best = p
			}
		}
		return best
	}
	parentFor := func(id string) string {
		if p := lowest(childParents[id]); p != "" {
			return p
		}
		if hasTileChildren[id] {
			return ""
		}
		return lowest(blockedParents[id])
	}

	// resolve climbs from a tile to its root, memoized. A cycle — which only a
	// malformed blocks graph could form — roots at the lowest id among its
	// members, so the answer does not depend on which tile the walk started from.
	memo := make(map[string]string, len(tiles))
	resolve := func(start string) string {
		var order []string
		seen := map[string]int{}
		cur := start
		for {
			if r, ok := memo[cur]; ok {
				for _, id := range order {
					memo[id] = r
				}
				return r
			}
			if idx, ok := seen[cur]; ok {
				root := order[idx]
				for _, id := range order[idx:] {
					if id < root {
						root = id
					}
				}
				for _, id := range order {
					memo[id] = root
				}
				return root
			}
			seen[cur] = len(order)
			order = append(order, cur)
			p := parentFor(cur)
			if p == "" {
				for _, id := range order {
					memo[id] = cur
				}
				return cur
			}
			cur = p
		}
	}
	for i := range tiles {
		tiles[i].GroupRoot = resolve(tiles[i].ID)
	}
}

// FamilyGroup is one dependency family: the root anchor it hangs off, and the
// member tiles beneath it in [SectionOrder]. It is a RENDER helper, not a wire
// type — [Tile.GroupRoot] is the wire fact, and this only buckets a ranked slice
// so a surface iterates families rather than re-deriving the split.
type FamilyGroup struct {
	// Root is the family's top-most anchor — the block header. It is the tile
	// whose id equals the shared GroupRoot.
	Root Tile
	// Members are the rest of the family, ordered by [SectionOrder] so the
	// most-pressing member leads. Empty for a family that is only its root.
	Members []Tile
}

// GroupByFamily buckets tiles into families, in the first-appearance order of
// each family in the input — so a caller that passes a rank-ordered slice gets
// families led by their strongest member, and one member's rank decides where
// the whole family sits. Within a family the members are ordered by
// [SectionOrder], the root taken out as the header.
//
// A tile whose GroupRoot names no tile in the input (which cannot happen for a
// board [assignGroupRoots] stamped, but can for a hand-built slice) heads its
// own family from its first member, so no row is dropped.
func GroupByFamily(tiles []Tile) []FamilyGroup {
	order := make([]string, 0)
	members := map[string][]Tile{}
	for _, t := range tiles {
		root := t.GroupRoot
		if root == "" {
			root = t.ID
		}
		if _, ok := members[root]; !ok {
			order = append(order, root)
		}
		members[root] = append(members[root], t)
	}
	out := make([]FamilyGroup, 0, len(order))
	for _, root := range order {
		fam := members[root]
		var head Tile
		found := false
		rest := make([]Tile, 0, len(fam))
		for _, t := range fam {
			if !found && t.ID == root {
				head, found = t, true
				continue
			}
			rest = append(rest, t)
		}
		if !found {
			head, rest = fam[0], fam[1:]
		}
		sort.SliceStable(rest, func(i, j int) bool {
			return sectionRank(rest[i].Section) < sectionRank(rest[j].Section)
		})
		out = append(out, FamilyGroup{Root: head, Members: rest})
	}
	return out
}

// sectionRank is a section's position in [SectionOrder]; an unknown section
// sorts after every known one, matching [GroupBySection]'s handling of a band a
// newer derivation added.
func sectionRank(section string) int {
	for i, s := range SectionOrder {
		if s == section {
			return i
		}
	}
	return len(SectionOrder)
}

// ClusterRow is one rendered line: a single tile, or the head of a cluster with
// every member behind it. Members has length one for an unclustered row.
type ClusterRow struct {
	Tile    Tile
	Members []Tile
}

// ClusterRows folds a section's tiles into render lines. Rows sharing a
// non-empty ClusterKey become ONE line whose Members are all of them, placed
// where the first member fell; an empty key is always its own line. The order of
// the input is preserved, so the caller's rank still decides where each line and
// each cluster head sits.
func ClusterRows(tiles []Tile) []ClusterRow {
	out := make([]ClusterRow, 0, len(tiles))
	at := make(map[string]int) // cluster key -> index in out
	for _, t := range tiles {
		if t.ClusterKey == "" {
			out = append(out, ClusterRow{Tile: t, Members: []Tile{t}})
			continue
		}
		if i, ok := at[t.ClusterKey]; ok {
			out[i].Members = append(out[i].Members, t)
			continue
		}
		at[t.ClusterKey] = len(out)
		out = append(out, ClusterRow{Tile: t, Members: []Tile{t}})
	}
	return out
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
// rankFirst is the board's severity-then-size-then-staleness order, ties broken
// by id ascending. [BuildBoard] ranks with it, the dedup resolves duplicates by
// it, and [CityOverview] restores it — one definition, so the overview cannot
// drift from the order the dedup already spent.
func rankFirst(a, b Tile) bool {
	if a.RankScore != b.RankScore {
		return a.RankScore > b.RankScore
	}
	return a.ID < b.ID
}

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

// owedSince is when the row started asking, in decreasing order of how
// directly the stamp dates the TURN.
//
// PROwedSince first, and on a merge anchor it is the only honest answer:
// gc.takeaway_at is absent there, and updated_at is touched by every reconcile
// pass, so falling through to it would file the three-day wedge behind the one
// raised an hour ago — the exact inversion the queue exists to prevent.
//
// Then gc.takeaway_at, the moment a sitting authored what is owed. updated_at
// only bounds the wait from below, and none of the three may be readable.
func owedSince(t Tile) time.Time {
	if !t.PROwedSince.IsZero() {
		return t.PROwedSince
	}
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

// CityOverview is the partition behind `--all`: every tile, in [rankFirst]
// order.
//
// Board.Tiles leaves [BuildBoard] partitioned owed-first, which is the default
// view's order and the opposite of the question the overview answers. Feeding
// that slice to [CapFamilies] costs twice: the overview leads with the operator's
// queue instead of the city's highest-ranked row, and the cap then drops
// whatever the hoisted queue pushed past the limit.
func CityOverview(tiles []Tile) []Tile {
	out := make([]Tile, len(tiles))
	copy(out, tiles)
	sort.SliceStable(out, func(i, j int) bool { return rankFirst(out[i], out[j]) })
	return out
}

// DefaultMaxRows mirrors gc-helm.sh's GC_HELM_MAX_ROWS=50. DefaultMaxDone is the
// separate budget for the terminal band, which the overview groups into its own
// closed-anchor families.
const (
	DefaultMaxRows = 50
	DefaultMaxDone = 10
)

// CapFamilies bounds the grouped overview WITHOUT ever splitting a family, so a
// member is never shown without the root that heads it. It admits whole families
// in the input's order (rank order, so the strongest-led families come first),
// counts the live rows of the admitted ones against limit, and rations the
// terminal DONE families — each a closed anchor — against maxDone. limit<=0
// means uncapped.
//
// DONE families get their own budget so a week of closures cannot crowd out the
// live board. A family is counted as DONE by its ROOT: a live family with a
// closed member still spends the live budget, which is right — the operator is
// looking at the live anchor, not the closed child.
func CapFamilies(tiles []Tile, limit, maxDone int) []Tile {
	if limit <= 0 {
		return tiles
	}
	out := make([]Tile, 0, len(tiles))
	liveRows, doneFamilies := 0, 0
	for _, f := range GroupByFamily(tiles) {
		rows := append([]Tile{f.Root}, f.Members...)
		if f.Root.Severity == SevDone {
			if doneFamilies >= maxDone {
				continue
			}
			doneFamilies++
		} else {
			if liveRows >= limit {
				continue
			}
			liveRows += len(rows)
		}
		out = append(out, rows...)
	}
	return out
}

// CapQueue bounds the operator's queue. limit<=0 means uncapped.
//
// The queue stays FLAT and owed-first — it is not grouped into families — so it
// is a straight head-truncation, not [CapFamilies]. A parked row here is not a
// straggler to ration but a conversation waiting on the operator that earned its
// place by age, so the queue keeps every owed row up to the limit in order.
func CapQueue(tiles []Tile, limit int) []Tile {
	if limit <= 0 || len(tiles) <= limit {
		return tiles
	}
	return tiles[:limit]
}
