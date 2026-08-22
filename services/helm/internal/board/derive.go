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
	// workflow already carries — those are not idle, they are in flight.
	openHeads []string
}

// rollUp derives every child-derived quantity for one anchor.
func rollUp(children []Child, f Facts) rollup {
	r := rollup{
		mTotal:         len(children),
		liveHeads:      []string{},
		deadOwnerHeads: []string{},
		inFlightHeads:  []string{},
		openHeads:      []string{},
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
	// every child has been classified.
	for _, c := range children {
		if c.Status == "closed" {
			continue
		}
		if (c.Assignee == "" || c.Status != "in_progress") && !live[c.ID] {
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
	return r
}

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

// dispositionDue is the state the waiting edges exist to express: a parked
// conversation that WAS waiting on something, every piece of which has landed.
// The takeaway still says what the sitting decided at dispatch time, and
// nothing else in the city re-reads it, so this is the only thing that can
// notice the wait ended (tk-2plde).
func dispositionDue(a Anchor, waiting, waitingOpen []string) bool {
	return a.Source == "parked" && len(waiting) > 0 && len(waitingOpen) == 0
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
//     means no agent will take it.
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
// STRANDED (HIGH) is open work with nothing LIVE in it and no open visit. Two
// things make that different from the naive "0 in progress": inProgressLive
// counts a slung bead whose movement lives on its workflow, and `held` means a
// conversation is holding the anchor — attention is already on it, so silence
// in the child beads is not abandonment.
func severity(a Anchor, r rollup, held bool, stale int, dispDue bool) Severity {
	var sev0 Severity
	inProgressLive := len(r.liveHeads)
	switch {
	case a.Source == "unowned":
		sev0 = SevHigh
	case a.Source == "decision", a.Source == "human":
		sev0 = SevElevated
	case dispDue:
		sev0 = SevElevated
	case a.Source == "parked" && r.mTotal == 0:
		sev0 = SevLow
	case r.mTotal == 0:
		sev0 = SevLow
	case r.open == 0:
		sev0 = SevLow
	case r.open > 0 && inProgressLive == 0 && !held:
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
func frontier(a Anchor, r rollup, held bool, waitingOpen []string, dispDue bool) string {
	inProgressLive := len(r.liveHeads)
	dead := len(r.deadOwnerHeads)
	deadSfx := ""
	if dead > 0 {
		deadSfx = fmt.Sprintf(" · %d stuck (dead owner)", dead)
	}

	switch {
	case a.Source == "unowned":
		return "unowned convoy — no owning bead"
	case a.Source == "decision":
		return "human-gated decision"
	case a.Source == "human":
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
	case inProgressLive == 0 && dead > 0 && !held:
		return fmt.Sprintf("%d open · %d stuck (dead owner)", r.open, dead)
	case inProgressLive == 0 && held:
		return fmt.Sprintf("%d open · in conversation", r.open) + deadSfx
	case inProgressLive == 0:
		return fmt.Sprintf("%d open · 0 in flight (stranded)", r.open)
	default:
		return fmt.Sprintf("%d open · %d in flight", r.open, inProgressLive) + deadSfx
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
func needs(a Anchor, r rollup, held bool, takeaway string, dispDue bool) string {
	// The disposition phrase OUTRANKS the takeaway, and only here. Every other
	// row spends its takeaway as NEEDS because the sentence is the best answer
	// available; on this row the sentence is precisely what has gone stale —
	// it was written when the work was dispatched and still says so. The
	// takeaway itself stays on the wire for anyone who wants to read what the
	// sitting concluded.
	if dispDue {
		return "blocker landed — dispose or resume"
	}
	if takeaway != "" {
		return takeaway
	}
	inProgressLive := len(r.liveHeads)
	dead := len(r.deadOwnerHeads)

	switch {
	case a.Source == "unowned":
		return "unowned — assign an owning bead"
	case a.Source == "decision":
		return "operator decision"
	case a.Source == "human":
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
	dispDue := dispositionDue(a, waiting, waitingOpen)
	sev := severity(a, r, held, stale, dispDue)
	w := weight(r, a.Priority, xrefs)
	takeaway := collapseWS(a.Takeaway)

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

		Stranded: r.mTotal > 0 && r.open > 0 && len(r.liveHeads) == 0 && !held,
		Empty: r.mTotal == 0 && a.Source != "decision" && a.Source != "unowned" &&
			a.Source != "human" && a.Source != "parked",
		Complete:         r.mTotal > 0 && r.open == 0,
		ProgressMismatch: mismatch,

		StaleDays:      stale,
		Priority:       a.Priority,
		CrossRigRefs:   xrefs,
		OpenHeads:      r.openHeads,
		DeadOwnerHeads: r.deadOwnerHeads,

		WaitingOn:      waiting,
		WaitingOnOpen:  waitingOpen,
		DispositionDue: dispDue,

		Takeaway:   nilIfEmpty(takeaway),
		TakeawayAt: nilIfEmpty(a.TakeawayAt),
		TakeawayBy: nilIfEmpty(a.TakeawayBy),

		UpdatedAt: a.UpdatedAt,
		Frontier:  frontier(a, r, held, waitingOpen, dispDue),
		Needs:     needs(a, r, held, takeaway, dispDue),
		RankScore: rankScore(sev, w, stale),
	}
}

// BuildBoard derives every tile, ranks by rank_score descending, and
// deduplicates by id keeping the highest-ranked occurrence (so a bead matched
// by two gathers appears once, in its higher band). Ties break by id ascending
// for deterministic output. now stamps GeneratedAt. partial/partialErrors
// propagate cross-rig degradation.
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

	return Board{
		GeneratedAt:   now.UTC(),
		Total:         len(deduped),
		Tiles:         deduped,
		Partial:       partial,
		PartialErrors: partialErrors,
	}
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
