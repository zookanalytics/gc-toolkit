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
// sentence, the stranded/empty/complete/progress_mismatch booleans, the `held`
// visit fact, and the in-flight/dead-owner join that distinguishes a slung
// bead being worked from one nobody has touched.
//
// Three of those are CROSS-ANCHOR joins rather than per-anchor facts, so they
// arrive in [Facts] beside the anchors instead of on [Anchor]: visit presence,
// the live-workflow map, and session liveness. gc-helm.sh passes the same three
// into its render as --argjson visits/inflight/ownermap; [Facts] is that
// argument list, typed.
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
	// not an attention level, so it ranks below every live band. A row leaves
	// it on `gc-helm dismiss`, or once the anchor has been closed longer than
	// the gather's window reaches back.
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
// dead-owner check, per-child staleness, the visit glyph). A source that cannot
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
	Kind        string            `json:"kind"`   // epic | decision | convoy | unowned | human | parked
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

	// Progress is the convoy's OWN closed/total claim, as `gc convoy list`
	// reports it. It is compared against the rolled-up child counts to derive
	// progress_mismatch; nothing renders it directly.
	Progress *Progress `json:"progress,omitempty"`

	// The takeaway triple: the LLM-authored headline a converse sitting leaves
	// on a bead, plus its provenance. Read from gc.takeaway / gc.takeaway_at /
	// gc.takeaway_by. An anchor with a takeaway spends it as its NEEDS
	// sentence, which is the whole reason the field is gathered.
	Takeaway   string `json:"takeaway,omitempty"`
	TakeawayAt string `json:"takeaway_at,omitempty"`
	TakeawayBy string `json:"takeaway_by,omitempty"`

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
	// the PR round-trip derivation discriminates on: the route, which separates
	// a pool-routed rework or review child (machine `progressing`) from an
	// ordinary prerequisite and from the demand bead that makes an anchor
	// `asking`; the title, which is the demand's authored headline; and the
	// creation instant, which is when an unanswered demand's turn began.
	//
	// It is the SAME read as WaitingOn, not a second one — [source.waitingEdges]
	// produces both from one dependency query — so an anchor whose edges could
	// not be read reports the empty set here and WaitingUnknown below, exactly
	// as it does for the id slices.
	Blockers []Blocker `json:"blockers,omitempty"`

	// WaitingUnknown says the source could not READ this anchor's edges at
	// all: the per-anchor dependency query itself failed, so the empty
	// WaitingOn above is an absence of knowledge rather than a proof that
	// nothing is outstanding.
	//
	// The two are not interchangeable, and only one consumer can tell them
	// apart. An unresolved BLOCKER is already handled — it is absent from
	// WaitingOnClosed and so counts as outstanding, the quiet direction. An
	// unreadable EDGE SET has no such fallback: it looks exactly like a row
	// with no waits, which is the state [ruled] reads as "every recorded wait
	// has landed". Without this flag a per-anchor Dolt timeout would satisfy
	// that clause vacuously and stand an answered human-gated row down,
	// telling the operator to close or extend a question whose routed work may
	// still be open (tk-fhd705).
	//
	// Only the kinds that spend the edges pay the read, so this stays false
	// for an epic or a convoy: they never asked, so nothing about them is
	// unknown.
	WaitingUnknown bool `json:"waiting_unknown,omitempty"`
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
	// IssueType is what the bead IS. A `decision` is a demand by construction,
	// the way the board's own `decision` kind is.
	IssueType string    `json:"issue_type,omitempty"`
	CreatedAt time.Time `json:"created_at,omitzero"`
}

// Progress is a convoy's self-reported roll-up, mirroring the `progress` object
// on `gc convoy list --json`.
type Progress struct {
	Closed int `json:"closed"`
	Total  int `json:"total"`
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
	// or a parked conversation whose recorded waits have all landed. It is not
	// derivable from the band — severity is coarse and shared, so a one-bead
	// demand (ELEVATED) sorts below a stranded container (HIGH) and rank alone
	// can never put the operator's queue first. [OperatorQueue] is the partition.
	Owed bool `json:"owed"`

	// Weight is the rank PROXY: subtree size + priority weight + a capped
	// cross-rig-ref count. It is the middle lane of rank_score.
	Weight int `json:"weight"`
	// Held is visit presence: an open visit bead names this anchor in its
	// gc.continuation_group, so a conversation is holding it. A held anchor is
	// never stranded — the conversation IS the attention it would be flagged
	// for lacking.
	Held bool `json:"held"`

	NClosed int `json:"n_closed"`
	MTotal  int `json:"m_total"`
	Open    int `json:"open"`
	// InProgress is the RAW status count — honestly 0 for a slung bead, whose
	// work never leaves status=open. InProgressLive is the count that answers
	// "is anything actually moving", under both mechanisms.
	InProgress int `json:"in_progress"`
	Assigned   int `json:"assigned"`

	InProgressLive int  `json:"in_progress_live"`
	InProgressDead int  `json:"in_progress_dead"`
	DeadOwner      bool `json:"dead_owner"`

	// InFlight is the part of InProgressLive attributable to a live graph.v2
	// workflow rather than to a claimed child, surfaced so the join can be
	// audited without re-deriving it.
	InFlight      int      `json:"in_flight"`
	InFlightHeads []string `json:"in_flight_heads"`

	Owned *bool `json:"owned"`

	Stranded         bool `json:"stranded"`
	Empty            bool `json:"empty"`
	Complete         bool `json:"complete"`
	ProgressMismatch bool `json:"progress_mismatch"`

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
	// Five of the six are read off the bead. The board computes nothing about a
	// merge anchor that the cadence has not already decided: reading the
	// conversation for the open pull requests costs about twenty seconds
	// against a 45-second cache TTL, and a cold `gh pr list` reports
	// mergeStateStatus=UNKNOWN for two thirds of them.

	// PRNumber is 0 before the PR opens; PRURL is the operator's way into
	// GitHub, which is where the conversation stays.
	PRNumber int    `json:"pr_number"`
	PRURL    string `json:"pr_url"`

	// PRMachine is what the merge cadence can do with this anchor on its next
	// pass: progressing, settled, wedged-exception, wedged-veto, or unknown.
	//
	// `unknown` is a rendered value, not a fallback to the quiet end — the same
	// choice [Anchor.WaitingUnknown] already makes, and for the same reason. An
	// unreadable axis and a clear one are not interchangeable, and a missing
	// key means the cadence has not written one yet, which is a fact about the
	// city rather than an all-clear.
	PRMachine string `json:"pr_machine"`

	// PRConversation is where the exchange with the operator stands. It reads
	// `unknown` on every row today: its other values all resolve to
	// acknowledgement watermarks that do not exist yet, and a surface that
	// guesses is wrong in the one direction that matters — every failed
	// derivation looks like silence, which is the answer that tells the
	// operator to stop looking. It ships now so the wire contract does not
	// change shape when the watermarks land.
	PRConversation string `json:"pr_conversation"`

	// PRApproval is whether GitHub is withholding the merge for a human review:
	// required, met, not_required, or unknown. Read from the recorded posture,
	// which is GitHub's own requirement rather than the city's gate set — a
	// repository can require a review that check_set never declared, and keyed
	// on the gate set a green pull request nobody has approved reads as settled
	// and nobody's move.
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
}

// Sitting is one converse sitting — the visit bead a conversation runs inside —
// as the board reports it. Sittings are NOT tiles: a tile is an anchor that
// wants something, while a sitting is an event in the conversation record, so
// they ride the envelope beside the ranked list rather than competing in it.
//
// The board carries every open sitting and those closed inside the recent
// window (source.sittingWindow). Both halves answer one question the ranked
// table cannot: which conversations are running now, and what the ones that
// just ended concluded.
type Sitting struct {
	ID  string `json:"id"`
	Rig string `json:"rig"`
	// Subject is the anchor this conversation is about, from the visit's
	// gc.continuation_group — the same field Facts.Visits keys Tile.Held on.
	Subject string `json:"subject"`
	Title   string `json:"title"`
	// Status is the visit bead's own status. A sitting is finished when this
	// reads "closed" and running under any other value: a CLAIMED visit is a
	// held conversation, which is why liveStatuses admits in_progress.
	Status string `json:"status"`

	// Outcome is gc.outcome, the one-word justification converse stamps on a
	// visit before closing it (folded, moot, benign, diagnosed, cut-short, or
	// the word a held sitting signs off with). It is stamped per VISIT and
	// never rewritten, which is what makes it attributable to this sitting
	// alone. Empty on a running sitting, and on a closed one whose writer did
	// not stamp it.
	Outcome string `json:"outcome"`
	// Session is the converse session that ran the sitting (gc.session_name),
	// which is what an operator attaches to while it is still open.
	Session string `json:"session"`

	// OpenedAt is when the conversation STARTED — gc.claimed_at, falling back
	// to the bead's creation time for a visit that was never claimed. ClosedAt
	// is zero while the sitting runs. The pair is also the span the takeaway
	// below is attributed by.
	OpenedAt time.Time `json:"opened_at,omitzero"`
	ClosedAt time.Time `json:"closed_at,omitzero"`

	// Takeaway is the headline THIS sitting left on its subject, or empty.
	//
	// The takeaway lives on the SUBJECT, not on the visit, and each sitting
	// overwrites the last one's. So it is carried only when gc.takeaway_at
	// falls inside this sitting's own span: a subject visited three times has
	// one takeaway, and hanging it on all three rows would credit two sittings
	// with a conclusion they did not reach. Sittings that overlap on one
	// subject can both claim a stamp inside their span; the visit claim
	// serializes them in practice, and the failure is a duplicated headline
	// rather than a wrong one.
	Takeaway string `json:"takeaway"`
}

// Facts are the CROSS-ANCHOR joins one gather pass produces alongside the
// anchors — the typed form of the three --argjson maps gc-helm.sh hands its
// render. A zero Facts is legal and means "the gather could not supply these":
// every anchor then reads as unheld, with nothing in flight and no owner
// liveness known.
type Facts struct {
	// Visits holds the ids of anchors an open visit bead names.
	Visits map[string]bool
	// Inflight maps a WORK-BEAD id — an anchor's CHILD, not the anchor — to the
	// session names of the live graph.v2 workflows standing over it. The gather
	// resolves each live workflow root through its input convoy to that
	// convoy's single tracked member, and that member is the key.
	Inflight map[string][]string
	// OwnerState maps a session name AND its alias to that session's state, so
	// a child's assignee can be resolved whichever form it was written in.
	OwnerState map[string]string
	// Sittings are the converse sittings the same visit read produced — every
	// open one, plus those closed inside the recent window. Visits above is the
	// per-anchor boolean derived from them; this is the record itself, which
	// [BuildBoard] orders and passes through to the envelope.
	Sittings []Sitting
	// Prefixes is every rig's issue prefix; RigNames is every rig's name. The
	// cross-rig-ref scan looks for OTHER rigs' prefixes in an anchor's prose and
	// discards any hit that is really a rig name (so "signal-loom" is not read
	// as a "signal-" bead id).
	Prefixes []string
	RigNames []string
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
}
