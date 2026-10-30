// Package board is the Go port of the Helm board MODEL — the ranking and
// derivation logic that the bash proof-of-concept (assets/scripts/gc-helm.sh)
// computes in a single jq pass. It is deliberately free of I/O: a [Source]
// gathers raw [Anchor] data, and [BuildBoard] turns it into a ranked,
// deduplicated [Board].
//
// SCOPE. This started as the minimal subset proven by the tk-sy3vj spike,
// was widened by tk-x89rn (which restored [Anchor.UpdatedAt] and
// [Anchor.Metadata], and with them the real stale_days), and reached full
// gc-helm.sh parity in tk-134d7. [Tile] now carries every field the bash
// board's `--json` emits, in the same order, inside the envelope
// {generated_at, total, tiles}.
//
// PARITY (tk-134d7). The board is now ONE model with TWO renderers — the web
// dashboard and the `helm-svc board` CLI — so the field set here is the whole
// of gc-helm.sh's `--json` contract rather than the spike subset. Everything
// the bash board computes is computed here: the full rank weight (subtree size
// + priority + a capped cross-rig-ref count), the takeaway-driven NEEDS
// sentence, the stranded/empty/complete booleans, the `held` fact, and the
// in-flight/dead-owner join that distinguishes a slung bead being worked from
// one nobody has touched.
//
// Two of those are CROSS-ANCHOR joins rather than per-anchor facts, so they
// arrive in [Facts] beside the anchors instead of on [Anchor]: the live-workflow
// map and session liveness. `held` is read from the human gates and the
// conversations the gather admits as anchors of their own ([KindGate],
// [KindConversation]), which the board folds onto the beads they concern.
//
// The struct tags are an additive contract: the TypeScript frontend mirrors
// them, so fields may be added but never renamed or removed.
package board

import "time"

// Severity is the attention band of a tile. Higher bands dominate ranking.
type Severity string

const (
	SevHigh     Severity = "HIGH"     // stranded: open work with none in progress
	SevElevated Severity = "ELEVATED" // a human-gated decision (or, with staleness, an aged NORMAL)
	SevNormal   Severity = "NORMAL"   // healthy in-flight work
	SevLow      Severity = "LOW"      // empty or fully closed
	// SevDone is the terminal band: the anchor bead itself has closed. It is
	// not an attention level, so it ranks below every live band. A row ages out
	// only once the anchor has been closed longer than the DONE window; nothing
	// retires it early.
	SevDone Severity = "DONE"
)

// sevRank mirrors gc-helm.sh's `def sevrank`. It is the dominant term in
// rank_score, multiplied by 1e6 so the band always outweighs the weight and
// staleness terms.
func (s Severity) rank() int {
	switch s {
	case SevHigh:
		return 3
	case SevElevated:
		return 2
	case SevNormal:
		return 1
	case SevDone:
		// Negative so a DONE row sorts below every live band without shifting
		// the four existing ranks: rankScore adds at most rankTermCap to the
		// lane, which leaves the whole band at or below -1, and the lowest a
		// live row can reach is 0.
		return -1
	default: // SevLow and anything unknown
		return 0
	}
}

// Child is a rolled-up member of an anchor (epic child or convoy dependent).
// Only the status feeds the counts today; Assignee, UpdatedAt and Metadata are
// carried for parity with the model and are what the consumer beads spend (a
// dead-owner check, per-child staleness). A source that cannot
// read a field leaves it zero rather than approximating it.
type Child struct {
	ID        string            `json:"id"`
	Status    string            `json:"status"`
	Assignee  string            `json:"assignee,omitempty"`
	UpdatedAt time.Time         `json:"updated_at,omitzero"`
	Metadata  map[string]string `json:"metadata,omitempty"`
}

// Anchor is one raw gather result before derivation — the Go analogue of a line
// in gc-helm.sh's anchors.ndjson. A [Source] produces these; [BuildBoard]
// consumes them.
//
// UpdatedAt drives stale_days (and through it the NORMAL→ELEVATED stale bump);
// a zero value means the source could not read it and staleness reads as 0,
// exactly as gc-helm.sh treats a null updated_at. Metadata is what a source
// SELECTS the `human` and `parked` kinds by, and is also where the three
// takeaway fields below are read from.
//
// Description is carried for ONE purpose: the cross-rig-ref scan, which reads
// bead ids belonging to other rigs out of the prose. It is never rendered.
type Anchor struct {
	ID          string            `json:"id"`
	Title       string            `json:"title"`
	Kind        string            `json:"kind"`   // epic | decision | convoy | unowned | human | parked | merge | review | rework | gate | conversation
	Source      string            `json:"source"` // same string as Kind; drives derivation branches
	Rig         string            `json:"rig"`
	Prefix      string            `json:"prefix"`
	Priority    *int              `json:"priority,omitempty"`
	UpdatedAt   time.Time         `json:"updated_at,omitzero"`
	Description string            `json:"description,omitempty"`
	Metadata    map[string]string `json:"metadata,omitempty"`
	Children    []Child           `json:"children,omitempty"`

	// ClosedAt is set only for an anchor whose own bead has CLOSED, and is
	// what puts the row in the terminal DONE band. A zero value means the
	// anchor is live, which is every anchor the open queries return, so a
	// source that gathers no closed anchors renders no DONE band at all.
	ClosedAt time.Time `json:"closed_at,omitzero"`

	// Owned distinguishes a convoy that an owning bead accounts for from the
	// orphan exception (kind "unowned"). nil for every non-convoy kind, which
	// is what keeps the wire field null rather than a misleading false.
	Owned *bool `json:"owned,omitempty"`

	// The takeaway triple: the LLM-authored headline a converse sitting leaves
	// on a bead, plus its provenance. Read from gc.takeaway / gc.takeaway_at /
	// gc.takeaway_by. An anchor with a takeaway spends it as its NEEDS
	// sentence, which is the whole reason the field is gathered.
	Takeaway   string `json:"takeaway,omitempty"`
	TakeawayAt string `json:"takeaway_at,omitempty"`
	TakeawayBy string `json:"takeaway_by,omitempty"`

	// Notes carries the bead's notes field so a recommendation row can spend the
	// first-reaction card (Understanding / Found / Proposal / Decision needed)
	// the disposition wrote there. The takeaway is one frozen line; the card is
	// the reasoning and the options behind it, which is what an operator needs to
	// Accept or redirect. It reaches the wire only as Tile.Recommendation, and
	// only on an acceptable row — computeTile reads it beside the accept
	// affordance.
	Notes string `json:"notes,omitempty"`

	// WaitingOn is the ids this bead depends on by a `blocks` edge, and
	// WaitingOnClosed the subset of those the source found already closed.
	//
	// For a `parked` subject these are the work a converse sitting routed out
	// of the conversation. A takeaway is one frozen string — "routed; nothing
	// further needed here" reads the same the day it is written and a week
	// after the work merged — so the wait has to exist as an EDGE for anything
	// to re-ask it (tk-2plde). The derivation is in computeTile; nothing about
	// it is stored, so no state has to be cleared when a blocker lands.
	//
	// Both are ids, not a boolean, because the source knows the blockers and
	// the derivation must be able to say how many are still outstanding.
	// A blocker the source could not resolve at all is simply absent from
	// WaitingOnClosed, which reads as still-waiting — the quiet direction.
	WaitingOn       []string `json:"waiting_on,omitempty"`
	WaitingOnClosed []string `json:"waiting_on_closed,omitempty"`

	// Blockers is the same `blocks` edge set as WaitingOn, carrying the fields
	// the derivation discriminates on: the route, which separates a pool-routed
	// rework or review child (machine `progressing`) from an ordinary
	// prerequisite and from the human gate that makes an anchor `asking`; the
	// title, which is the gate's question; the creation instant, which is when
	// an unanswered gate's turn began; and a gate's await type, key and close
	// reason, which Accept's conditions read ([readAcceptance]).
	//
	// The source reads them for the kinds whose waits the derivation spends
	// ([source.needsWaitingEdges]), a recommendation's parked bead among them,
	// open and closed alike, so a recommendation's closed gate is here with its
	// answer.
	//
	// It is the SAME read as WaitingOn, not a second one —
	// [source.waitingFromEdges] produces both from one dependency query — so an
	// anchor whose edges could not be read reports the empty set here and
	// WaitingUnknown below, exactly as it does for the id slices.
	Blockers []Blocker `json:"blockers,omitempty"`

	// WaitingUnknown says the source could not establish this anchor's waits,
	// so the empty WaitingOn above is an absence of knowledge rather than a
	// proof that nothing is outstanding.
	//
	// The beads source sets it when its dependency read fails, or when the
	// hydration that resolves the blockers does. That read is one batched query
	// per rig and status pass ([source.BeadsSource.attachEdges]), so a single
	// failure marks every anchor of the pass whose kind reads waits
	// ([source.needsWaitingEdges]). Epic and convoy are among those kinds: they
	// read their `blocks` edges for the dependency-family grouping, so a failed
	// read flags them too. The supervisor backend sets it on every
	// metadata-keyed row it serves, because it cannot resolve a blocker's
	// status ([source.SupervisorSource.metadataAnchorFor]).
	//
	// An unread wait set and an empty one are not interchangeable. A blocker
	// that was read but has not closed is already handled — it is absent from
	// WaitingOnClosed and so counts as outstanding, the quiet direction. An
	// unreadable EDGE SET has no such fallback: it looks exactly like a row
	// with no waits, which is the state [ruled] reads as "every recorded wait
	// has landed". Without this flag a Dolt timeout on that read would satisfy
	// that clause vacuously and stand an answered human-gated row down, telling
	// the operator to close or extend a question whose routed work may still
	// be open.
	//
	// Only [ruled] and [ruledInFlight] read the flag, and both refuse a row
	// that carries it, so the row falls through to the un-ruled arm. The family
	// grouping reads WaitingOn and never this flag. So on an epic or a convoy
	// the flag matters only when the row is routed to the operator. Both
	// readers apply only to rows [humanGated] accepts, and for an epic or a
	// convoy that route is the only way in.
	WaitingUnknown bool `json:"waiting_unknown,omitempty"`

	// Reviews is the anchor's review beads, open and closed: each carries
	// task_kind=review and names this anchor in anchor_bead. A lane's green
	// derives from them ([laneGreen]). The beads source gathers them for a live
	// merge anchor at pre_open_gate, the one row whose stall signal reads a
	// lane's green, the way bd-lib.sh reads an anchor's children in a store
	// marked joined: the live ones by anchor_bead, and the closed ones through
	// the anchor's inbound edges ([source.BeadsSource.readReviews]).
	//
	// ReviewsUnknown says the source could not read them, so an empty Reviews
	// is an absence of knowledge, not a lane no review backs. The beads source
	// sets it in a store not marked joined, where the edges do not answer for
	// the closed reviews, and when a read the reviews come from fails. The
	// supervisor backend reads no closed bead and sets it on every
	// metadata-keyed row it serves.
	Reviews        []Child `json:"reviews,omitempty"`
	ReviewsUnknown bool    `json:"reviews_unknown,omitempty"`

	// Subjects is the beads a human gate or a conversation concerns, read off
	// its own edges: for a gate ([KindGate]), each bead that waits on it
	// through a `blocks` edge; for a conversation ([KindConversation]), the one
	// bead its `tracks` edge names. The fold moves the row onto each subject
	// that has a row of its own ([foldWrappers]). Empty on every other kind, and
	// on a gate whose dependents could not be read, which keeps a row of its own
	// so no open gate is off the board.
	Subjects []string `json:"subjects,omitempty"`

	// RepliesTo is the human gates a conversation's `replies-to` edges name:
	// the gates its sitting answers. Empty on every other kind.
	RepliesTo []string `json:"replies_to,omitempty"`

	// Assignee is who holds a conversation: `human` while it waits in the
	// operator's queue, and its sitting's alias while a sitting holds it. The
	// gather sets it on a conversation only.
	Assignee string `json:"assignee,omitempty"`
}

// Blocker is one `blocks` dependency of an anchor, as the gather read it.
//
// Gather-side only: it never crosses the wire. What reaches a consumer is the
// derived axis, not the graph the axis was read off.
type Blocker struct {
	ID     string `json:"id"`
	Title  string `json:"title"`
	Status string `json:"status"`
	// RoutedTo is gc.routed_to. A value naming a POOL means an automated actor
	// is due to claim this blocker; "human" and the empty string both mean no
	// actor will, and the two are not distinguished here because neither makes
	// the anchor `progressing`.
	RoutedTo string `json:"routed_to,omitempty"`
	// IssueType is what the bead IS. A `decision` asks a person by
	// construction, the way the board's own `decision` kind does, and so does
	// a `gate` whose AwaitType is `human`.
	IssueType string `json:"issue_type,omitempty"`
	// Assignee is who holds the child. It lets the derivation ask whether a
	// pool-routed review or rework is actually being WORKED — claimed by a live
	// session — rather than merely routed to a pool nothing is draining. Routed
	// and live are different facts, and only the second makes a pre-open gate a
	// healthy hold rather than a stall. On a human gate it is the person the
	// gate is assigned to, whose it is to clear.
	Assignee  string    `json:"assignee,omitempty"`
	CreatedAt time.Time `json:"created_at,omitzero"`
	UpdatedAt time.Time `json:"updated_at,omitzero"`
	// AwaitType and AwaitID are a gate's await type and key. A gate whose
	// await type is `human` is a human gate; its await id is the situation key
	// it was filed under, `first-reaction` for a recommendation's gate.
	AwaitType string `json:"await_type,omitempty"`
	AwaitID   string `json:"await_id,omitempty"`
	// CloseReason is the answer a closed gate was resolved with.
	CloseReason string `json:"close_reason,omitempty"`
}

// Tile is one rendered row of the board — the additive contract mirrored by the
// frontend and emitted verbatim by `helm-svc board --json`.
//
// FIELD ORDER IS PART OF THE CONTRACT. encoding/json emits struct fields in
// declaration order, so the sequence below is what every consumer sees.
// Renaming or removing a field breaks the TypeScript mirror and the CLI
// contract; adding one at the end is safe.
type Tile struct {
	ID       string   `json:"id"`
	Rig      string   `json:"rig"`
	Kind     string   `json:"kind"`
	Title    string   `json:"title"`
	Severity Severity `json:"severity"`

	// Owed marks a row whose next move is a PERSON'S: an unanswered human gate,
	// a conversation waiting for the operator, or a parked subject whose
	// recorded waits have all landed. It is not
	// derivable from the band — severity is coarse and shared, so a one-bead
	// question (ELEVATED) sorts below a stranded container (HIGH) and rank alone
	// can never put the operator's queue first. [OperatorQueue] is the partition.
	Owed bool `json:"owed"`

	// Weight is the rank PROXY: subtree size + priority weight + a capped
	// cross-rig-ref count. It is the middle lane of rank_score.
	Weight int `json:"weight"`
	// Held says the operator's side holds this bead: an open human gate blocks
	// it, an acceptance an earlier Accept left unfinished keeps it, or an open
	// conversation tracks it. A held anchor is never stranded, because the
	// question or the conversation IS the attention it would be flagged for
	// lacking.
	Held bool `json:"held"`
	// SittingState refines Held: SittingInSession when a conversation that
	// tracks this bead is held by a live session right now, SittingWaiting on
	// any other held row, which waits for the operator. Empty on a row nothing
	// holds (Held is false), the same not-applicable empty a closed row's Phase
	// carries. It is derived here rather than in the browser because it reads
	// each conversation's holder against the session list.
	SittingState string `json:"sitting_state"`

	NClosed int `json:"n_closed"`
	MTotal  int `json:"m_total"`
	Open    int `json:"open"`
	// InProgress is the RAW status count — honestly 0 for a slung bead, whose
	// work never leaves status=open. InProgressLive is the count that answers
	// "is anything actually moving": a child the city is working (claimed by a
	// live owner, or covered by a live workflow) PLUS a live workflow over the
	// anchor's OWN bead — the common sling shape, where the work bead is the
	// anchor and its molecule stands over it rather than under a child.
	InProgress int `json:"in_progress"`
	Assigned   int `json:"assigned"`

	InProgressLive int  `json:"in_progress_live"`
	InProgressDead int  `json:"in_progress_dead"`
	DeadOwner      bool `json:"dead_owner"`

	// InFlight is the part of InProgressLive attributable to a live graph.v2
	// workflow rather than to a claimed child — a child the workflow carries, or
	// the anchor's own bead when a workflow stands over it — surfaced so the join
	// can be audited without re-deriving it. Equal to len(InFlightHeads).
	InFlight      int      `json:"in_flight"`
	InFlightHeads []string `json:"in_flight_heads"`

	Owned *bool `json:"owned"`

	Stranded bool `json:"stranded"`
	Empty    bool `json:"empty"`
	Complete bool `json:"complete"`

	// StaleDays is whole days since the anchor was last updated, and UpdatedAt
	// is the timestamp it came from. Both are 0/zero when the source cannot read
	// updated_at — indistinguishable, on the wire, from an anchor touched today.
	// That ambiguity is why UpdatedAt is carried alongside: absent means unknown,
	// present means genuinely fresh.
	StaleDays      int      `json:"stale_days"`
	Priority       *int     `json:"priority"`
	CrossRigRefs   []string `json:"cross_rig_refs"`
	OpenHeads      []string `json:"open_heads"`
	DeadOwnerHeads []string `json:"dead_owner_heads"`

	// ParkedHeads is the open children that carry a board row of their OWN —
	// routed to the operator, or holding a takeaway. They are split out of
	// OpenHeads so a parent cannot report a child that is waiting on a ruling
	// as work nobody has picked up. Open still counts them; this names which
	// ones they are.
	ParkedHeads []string `json:"parked_heads"`

	// WaitingOn is every bead this row depends on by a `blocks` edge;
	// WaitingOnOpen is the subset that has NOT closed. DispositionDue is the
	// state the pair exists to express: a parked conversation that was waiting
	// on something, all of which has now landed. It is no longer "wants
	// nothing" — it wants a disposition, so it leaves the LOW floor.
	//
	// A blocker whose status could not be resolved counts as OPEN, so an
	// unreadable graph keeps the pre-fix quiet row rather than inviting the
	// operator to dispose of a subject whose work is still in flight. The
	// harder case — the edge read failing outright, which yields no blocker to
	// count either way — is carried separately as Anchor.WaitingUnknown and
	// never reaches the wire, because these two arrays stay a report of what
	// was actually read.
	WaitingOn      []string `json:"waiting_on"`
	WaitingOnOpen  []string `json:"waiting_on_open"`
	DispositionDue bool     `json:"disposition_due"`

	// The takeaway triple is null-when-absent rather than omitted: the key is
	// part of the contract, and a consumer distinguishes "no takeaway" from
	// "field gone" by the null.
	Takeaway   *string `json:"takeaway"`
	TakeawayAt *string `json:"takeaway_at"`
	TakeawayBy *string `json:"takeaway_by"`

	UpdatedAt time.Time `json:"updated_at,omitzero"`
	// ClosedAt is non-zero exactly on a DONE row and carries when the anchor
	// closed. It also orders the band: most-recently-closed first, so the row
	// the operator just watched close is the one at the top of it.
	ClosedAt  time.Time `json:"closed_at,omitzero"`
	Frontier  string    `json:"frontier"`
	Needs     string    `json:"needs"`
	RankScore int       `json:"rank_score"`

	// --- the PR round-trip (specs/tk-q0ml23) -------------------------------
	//
	// Where a pull request sits in its round-trip with the operator, as two
	// independent axes rather than one enum. They move independently and are
	// true at once often enough that one field would have to pick: an anchor
	// can carry a review the cadence dispatched AND an unanswered comment from
	// the operator, and reporting either one hides the other.
	//
	// A row is a MERGE ANCHOR's, not a pull request's. An anchor at
	// pre_open_gate has a branch, a gate set and a machine axis with no PR
	// number yet, and most wedged anchors are in exactly that state, so
	// PRNumber is a field on the row and never the selector.
	//
	// Every value here is read off beads: the board computes nothing about a
	// merge anchor that the cadence has not already decided, and the render path
	// makes no GitHub call.

	// PRNumber is 0 before the PR opens; PRURL is the operator's way into
	// GitHub, which is where the conversation stays.
	//
	// PRBranch is the identity for the whole span before there is a number,
	// and it is a field of its own because a surface cannot recover it from
	// [Tile.Frontier]: that line is prose, and it is not on every table. A row
	// that can name neither carries both empty, which is the anchor at a human
	// state that records no branch.
	PRNumber int    `json:"pr_number"`
	PRURL    string `json:"pr_url"`
	PRBranch string `json:"pr_branch"`

	// PRMachine is what the merge cadence can do with this anchor on its next
	// pass: progressing, settled, blocked, or unknown.
	//
	// `blocked` is a hold no automated actor will clear and no review verdict is
	// owed on — an unresolved required review thread, a base gone BEHIND, or an
	// unrouted blocker. The operator is owed it, distinct from `settled`, and its
	// cause rides `pr.machine_reason`, surfaced in the row's `needs`.
	//
	// `unknown` is a rendered value, not a fallback to the quiet end — the same
	// choice [Anchor.WaitingUnknown] already makes, and for the same reason. An
	// unreadable axis and a clear one are not interchangeable, and a missing
	// key means the cadence has not written one yet, which is a fact about the
	// city rather than an all-clear.
	PRMachine string `json:"pr_machine"`

	// PRConversation is where the exchange with the operator stands: quiet,
	// outstanding, answered, asking, or unknown. asking is an open human gate
	// on the anchor; quiet, outstanding and answered are read off the position
	// pr-facts.sh records against the acknowledgement watermarks and the routing
	// disposition — answered once the routed fix unit closes (a rework child
	// landing, a gate resolved), not on a bare head move. covered is not reachable yet — it waits
	// on a comment-to-bead link nothing records — so an utterance the city is
	// working reads the coarser outstanding. `unknown` is a rendered value, not a
	// fallback to the quiet end: an unread axis and a clear one are not
	// interchangeable.
	PRConversation string `json:"pr_conversation"`

	// PRApproval is whether this pull request still owes an external approval
	// before it can merge: required, met, or unknown. Approval is a universal
	// merge rule (merge.sh holds every open PR until a non-city APPROVED review
	// stands, and one given at any commit stands until dismissed), so only
	// `approved` is met and every other posture owes one — the field is the
	// city's rule, not GitHub's protection set, so a PR on an integration/* base
	// or in a rule-less repo still reads `required`.
	//
	// A separate field rather than a fourth machine value, because a PR can
	// need an approval while the cadence is still progressing, and folding the
	// two would make the axis pick again.
	PRApproval string `json:"pr_approval"`

	// PROwedSince is when the operator's turn began — the clock [owedFirst]
	// ranks the queue by. Zero when nothing makes the row owed, and zero when
	// the only candidate cause reads unknown: an unreadable input belongs in
	// the coverage sentence, not in a clock reporting the wait as new.
	//
	// Not UpdatedAt. A wedged anchor is touched by every reconcile pass, so
	// ordering by that sorts the most neglected rows last.
	PROwedSince time.Time `json:"pr_owed_since,omitzero"`

	// --- the attention-type band and the cluster key -----------------------
	//
	// Two derived classifications the renderers group by, on the wire for the
	// same reason [Owed] is: the split is not recoverable from the coarse
	// [Severity] band, and putting it here is what keeps the CLI table and the
	// dashboard from each inventing their own client-side split.

	// Section is the KIND of attention a row wants, orthogonal to Severity's
	// how-badly: review (a pull request), gate (a person must answer), stalled
	// (open work nothing is moving), active (healthy in-flight), cleanup (a
	// finished or empty row to dispose of), done (the anchor itself closed). One
	// row lands in exactly one section; [classifySection] is the total mapping,
	// and [SectionOrder] is the order a surface reads them in.
	Section string `json:"section"`

	// ClusterKey groups rows that are instances of ONE template — the same
	// [Needs] sentence recurring across many beads, such as a repeated gate or
	// signoff ask. It is the shared Needs string, set only when at least
	// [clusterThreshold] rows in the SAME section carry it, and empty otherwise;
	// a renderer folds every row sharing a key into one entry that names the
	// count and lists the members.
	// Empty is the common case — a row with an LLM-authored takeaway is unique
	// and never clusters — so the field is omitted when it does not apply.
	ClusterKey string `json:"cluster_key,omitempty"`

	// GroupRoot is the id of the family this row belongs to — the top-most anchor
	// its parent-child and blocked edges climb to, equal to the row's OWN id when
	// it climbs to nothing. Every tile carries one, so a surface buckets families
	// the way both renderers already bucket [Section]. Dependency structure is the
	// board's primary grouping axis and the attention band orders and highlights
	// WITHIN a family; [GroupByFamily] is that partition.
	GroupRoot string `json:"group_root"`

	// GroupParent is the id of this row's IMMEDIATE parent — the one anchor its
	// edges climb to a single level up, empty when it climbs to nothing. GroupRoot
	// names the top of the family tree; GroupParent names the next step toward it,
	// so a surface renders the family as the nested containment tree it is — a
	// sub-epic beneath its parent, that sub-epic's own children beneath it —
	// instead of one flat member list under the top root. Both come from the same
	// per-tile parent walk in [assignGroupRoots]: GroupRoot follows it to the top,
	// GroupParent reports its first step.
	GroupParent string `json:"group_parent"`

	// Acceptable marks a recommendation row a person can Accept: resolve the
	// recommendation's human gate and dispatch the formula at the bead, no
	// sitting required. It holds while all three of Accept's conditions do
	// ([readAcceptance]): the bead carries a gc.recommended_formula; the
	// recommendation's gate, the human gate under the key first-reaction, is
	// open and unassigned, or closed with an acceptance an earlier Accept did
	// not finish; and no other open human gate blocks the bead. A live sitting
	// does not withhold it. Discuss (engage) is always available; Accept is the
	// extra move a recommendation row offers.
	Acceptable bool `json:"acceptable"`

	// AcceptFormula is the gc.recommended_formula Accept would dispatch, named on
	// the wire so a surface can say WHAT accepting does without re-reading the
	// subject bead. Empty exactly when Acceptable is false.
	AcceptFormula string `json:"accept_formula"`

	// PRBranchURL is the GitHub tree-view link for [PRBranch], or empty when the
	// row has no branch or the rig's repository could not be resolved. The render
	// path makes no GitHub call, so the repository is learned from a pr_url the
	// board already holds: every anchor in one rig targets that rig's repository,
	// so any row carrying a pull request URL names it for the rig's pre-PR rows
	// too. A rig the board holds no pull request URL for keeps the bare branch.
	PRBranchURL string `json:"pr_branch_url"`

	// PRPhase is this merge anchor's PR status. On a live anchor it is what stands
	// between the PR and landing — `working`, `needs-review`, or
	// `needs-attention` — the same status: taxonomy pr-status-label.sh projects
	// to the GitHub PR list, so the board and the label read one vocabulary
	// rather than two. On a closed anchor it is the PR's resolved state,
	// `merged` or `closed`, so a done row names how its PR ended rather than
	// freezing on its last live value. Empty on a non-merge row.
	PRPhase string `json:"pr_phase"`

	// Phase is this bead's liveness in the shared tri-state vocabulary —
	// `working`, `needs-review`, or `needs-attention` — and the word the frontier
	// leads with on every live row. It begins as the per-bead value
	// [prstatus.Derive] names from the same inputs PRPhase reads: holds, an open
	// human gate, posture, the draft stage, and for a merge anchor its open
	// rework/review children, or for any other bead the live-workflow signal
	// standing over it. A bead's board liveness and its GitHub `status:` label
	// come from that one core. A row WITH child tiles then takes their rolled-up
	// state in place of that per-bead value
	// ([aggregatePhases]): an epic's frontier is its children's frontier.
	//
	// Phase and PRPhase are therefore two independent axes. PRPhase is the PR
	// round-trip value and is never rolled up. Phase equals it on a merge anchor
	// with no child tiles — the common case, because a merge anchor's rework and
	// review children hang off it by a blocked/anchor_bead edge the roll-up does
	// not climb — and diverges from it on a merge anchor that ALSO has
	// parent-child child tiles, whose Phase becomes their roll-up. The one place
	// the two cannot disagree is a blocked machine verdict, which lifts both to
	// needs-attention together.
	//
	// Empty on a terminal (closed) row, where the live vocabulary has no answer,
	// the same not-applicable empty PRPhase leaves off a non-merge row.
	Phase string `json:"phase"`

	// Recommendation is the first-reaction card from the subject bead's notes —
	// the Proposal and Decision-needed sections an operator weighs to Accept or
	// redirect — carried verbatim so the decision point shows WHY, not only the
	// one-line takeaway that reaches Needs. Null-when-absent like the takeaway
	// triple, and non-null exactly on an acceptable row (see computeTile): the
	// accept affordance and the reasoning behind it ride the wire together.
	Recommendation *string `json:"recommendation"`

	// AcceptWithheld names the open human gates that hold Accept back, on a row
	// that meets Accept's first two conditions and fails the third: each gate's
	// title, or `N× — a · b` over several, the way Needs names gates. The bead's
	// next step waits for every gate that blocks it, so Accept waits until the
	// recommendation's gate is the last; Discuss answers the others. Null on
	// every other row.
	AcceptWithheld *string `json:"accept_withheld"`

	// GatesInSession names the open human gates on this row that a live
	// sitting's conversation replies to, the way Needs names gates: the gates
	// being answered now. It is set on every row such a gate folds onto, so a
	// bead whose gate an epic's sitting answers shows it though no conversation
	// tracks the bead. Null on a row with none.
	GatesInSession *string `json:"gates_in_session"`
}

// Sitting is one converse sitting — the conversation task a sitting runs on —
// as the board reports it. Sittings are NOT tiles: a tile is an anchor that
// wants something, while a sitting is an event in the conversation record, so
// they ride the envelope beside the ranked list rather than competing in it.
//
// The board carries every open conversation and those closed inside the recent
// window (source.sittingWindow). Both halves answer one question the ranked
// table cannot: which conversations are running now, and what the ones that
// just ended concluded. A closed conversation keeps the assignee and the edges
// it had while open, so the gather finds it by the same shape.
type Sitting struct {
	ID  string `json:"id"`
	Rig string `json:"rig"`
	// Subject is the bead this conversation is about: the one bead its
	// `tracks` edge names.
	Subject string `json:"subject"`
	Title   string `json:"title"`
	// Status is the conversation task's own status. A sitting is finished when
	// this reads "closed" and running under any other value: a conversation in
	// the operator's queue is open, and one a sitting has claimed is
	// in_progress.
	Status string `json:"status"`

	// OutcomeReason is the conversation task's close reason, the one-line
	// sentence its ending wrote: the headline a sign-off settled on, or the
	// operator's dismissal. Empty on a running sitting.
	OutcomeReason string `json:"outcome_reason"`
	// Session is the converse session that ran the sitting (gc.session_name),
	// which is what an operator attaches to while it is still open.
	Session string `json:"session"`

	// OpenedAt is when the conversation STARTED — gc.claimed_at, falling back
	// to the task's creation time for a conversation no sitting has claimed.
	// ClosedAt is zero while the sitting runs. The pair is also the span the
	// takeaway below is attributed by.
	OpenedAt time.Time `json:"opened_at,omitzero"`
	ClosedAt time.Time `json:"closed_at,omitzero"`

	// Takeaway is the headline THIS sitting left on its subject, or empty.
	//
	// The takeaway lives on the SUBJECT, not on the conversation, and each
	// sitting overwrites the last one's. So it is carried only when
	// gc.takeaway_at falls inside this sitting's own span: a subject discussed
	// three times has one takeaway, and hanging it on all three rows would
	// credit two sittings with a conclusion they did not reach. Sittings that
	// overlap on one subject can both claim a stamp inside their span; the
	// conversation's claim serializes them in practice, and the failure is a
	// duplicated headline rather than a wrong one.
	Takeaway string `json:"takeaway"`

	// SubjectTitle is the title of the SUBJECT bead — the row's topic, what the
	// conversation is about. It is read in the same batch as the takeaway
	// (source.attributeTakeaways), so a row can say what it concerns even when
	// nothing was concluded on it. Empty when the subject could not be read,
	// which the [Topic] and [Headline] helpers fall back on the id or the
	// conversation's title for. It carries the whole title; a renderer clips it
	// to its column.
	SubjectTitle string `json:"subject_title"`
}

// Topic is what a sitting is about, for a surface that shows one cell of it: the
// subject bead's title, falling back to the subject id when the gather could not
// read the title. Never empty on a real sitting — the row always says at least
// the id it stands on, so a bare id is the floor rather than the whole of it.
func (s Sitting) Topic() string {
	if s.SubjectTitle != "" {
		return s.SubjectTitle
	}
	return s.Subject
}

// Headline is what a sitting CONCLUDED, or failing that what it is ABOUT. The
// takeaway is the conversation's own one-line conclusion and wins whenever one
// was attributed. A closed sitting that left no takeaway shows its close reason
// next, the sentence naming why it closed, such as the operator's dismissal, so
// the row reads as a decision rather than a blank. Without either the row shows
// the subject's title — the topic — and the conversation's own title is the
// last resort, for a subject the gather could not read at all.
func (s Sitting) Headline() string {
	if s.Takeaway != "" {
		return s.Takeaway
	}
	if s.OutcomeReason != "" {
		return s.OutcomeReason
	}
	if s.SubjectTitle != "" {
		return s.SubjectTitle
	}
	return s.Title
}

// Facts are the CROSS-ANCHOR joins one gather pass produces alongside the
// anchors. A zero Facts is legal and means "the gather could not supply these":
// nothing is then in flight, no owner liveness is known, and no conversation
// reads as in session.
type Facts struct {
	// Inflight maps a work-bead id to the session names of the live graph.v2
	// workflows standing over it. The gather resolves each live workflow root
	// through its input convoy, and the key is that convoy's single tracked
	// member. The gather does not know which beads are anchors, so a key is
	// whatever bead the sling tracked. The board looks up three kinds of id:
	// an anchor's child ([rollUp]), a review or rework bead blocking a merge
	// anchor ([liveReviewOrRework]), and the anchor's own bead
	// ([Facts.anchorInFlight]). The anchor's own bead is the key when the anchor
	// is itself the slung work bead and its molecule stands over it rather than
	// under a child. [Facts.wfLive] re-checks each session's liveness at derive
	// time.
	Inflight map[string][]string
	// OwnerState maps a session name AND its alias to that session's state, so
	// a child's assignee, or a conversation's holder, can be resolved whichever
	// form it was written in. A key a live session shares with an ended one
	// holds the live one's state ([SessionEnded]).
	OwnerState map[string]string
	// Sittings are the converse sittings the gather read: every open
	// conversation, plus those closed inside the recent window. [BuildBoard]
	// orders them and passes them through to the envelope. The fold reads the
	// open conversations from their anchors ([KindConversation]), not from here.
	Sittings []Sitting
	// Prefixes is every rig's issue prefix; RigNames is every rig's name. The
	// cross-rig-ref scan looks for OTHER rigs' prefixes in an anchor's prose and
	// discards any hit that is really a rig name (so "signal-loom" is not read
	// as a "signal-" bead id).
	Prefixes []string
	RigNames []string

	// human indexes the gates and conversations by the beads they concern.
	// [BuildBoard] builds it from the anchors before it derives any tile.
	human humanIndex
}

// Board is the envelope returned by the service. Tiles are deduplicated by id
// and ordered by [owedFirst] — the operator's queue, oldest-owed first, then
// everything else by rank_score descending. Total is the count before any row
// cap. Tile.Owed is where the two partitions meet, so a consumer that wants
// only one of them does not have to re-derive the boundary.
type Board struct {
	GeneratedAt time.Time `json:"generated_at"`
	Total       int       `json:"total"`
	Tiles       []Tile    `json:"tiles"`
	// Sittings is the conversation record beside the ranked list: running
	// sittings first, then the recently closed. Like Tiles it is `null` rather
	// than `[]` when empty, so a consumer narrows before iterating.
	Sittings      []Sitting `json:"sittings"`
	Partial       bool      `json:"partial,omitempty"`
	PartialErrors []string  `json:"partial_errors,omitempty"`

	// PackHealth is the build state of the pack's compiled components. It is
	// not derived from the anchors and does not participate in ranking — it
	// rides the envelope because it answers a question about the board itself:
	// whether the binary rendering it is the one the sources describe.
	PackHealth []PackBuild `json:"pack_health,omitempty"`
}
