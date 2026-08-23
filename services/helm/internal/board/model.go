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

// Progress is a convoy's self-reported roll-up, mirroring the `progress` object
// on `gc convoy list --json`.
type Progress struct {
	Closed int `json:"closed"`
	Total  int `json:"total"`
}

// Tile is one rendered row of the board — the additive contract mirrored by the
// frontend and emitted verbatim by `helm-svc board --json`.
//
// FIELD ORDER IS THE BASH OBJECT LITERAL'S ORDER, deliberately.
// encoding/json emits struct fields in declaration order, so keeping this
// sequence aligned with gc-helm.sh's `{ id:…, rig:…, … }` means the two boards
// serialize the same keys in the same sequence and a human can diff the two
// outputs line for line. Renaming or removing a field breaks both the
// TypeScript mirror and the CLI contract; adding one is safe if it is added to
// the bash literal in the same position.
type Tile struct {
	ID       string   `json:"id"`
	Rig      string   `json:"rig"`
	Kind     string   `json:"kind"`
	Title    string   `json:"title"`
	Severity Severity `json:"severity"`

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
	Frontier  string    `json:"frontier"`
	Needs     string    `json:"needs"`
	RankScore int       `json:"rank_score"`
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
	// Prefixes is every rig's issue prefix; RigNames is every rig's name. The
	// cross-rig-ref scan looks for OTHER rigs' prefixes in an anchor's prose and
	// discards any hit that is really a rig name (so "signal-loom" is not read
	// as a "signal-" bead id).
	Prefixes []string
	RigNames []string
}

// Board is the envelope returned by the service. Tiles are sorted by rank_score
// descending and deduplicated by id; Total is the count before any row cap.
type Board struct {
	GeneratedAt   time.Time `json:"generated_at"`
	Total         int       `json:"total"`
	Tiles         []Tile    `json:"tiles"`
	Partial       bool      `json:"partial,omitempty"`
	PartialErrors []string  `json:"partial_errors,omitempty"`
}
