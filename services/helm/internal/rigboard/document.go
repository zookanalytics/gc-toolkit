package rigboard

// The document one rig's read builds: every row the pages draw, once each, and
// the four pages as lists of row ids. Two views make up the pages. Needs you is
// one entry per need, with the work it holds beneath it, and the Work queue is
// the work in the order it is expected to land. The Epics page shows both for
// each epic and each Delivery, with its closed work, and the Needs you and Work
// queue pages show them across the rig. Go decides every group, signal, count,
// need and order in it, and the page lays it out and filters it. The page's
// TypeScript types are generated from this file (web/src/rigboard/document.gen.ts),
// and TestPageTypesAreCurrent fails when that file is stale.

// Response is what the rig's route answers: the document, and the time its
// gather finished beside it. The document depends on the store's answers and,
// for each pull request on Gas Town's pending record, on GitHub's, so two
// reads of an unchanged store and an unchanged GitHub give the same document.
type Response struct {
	ReadAt string   `json:"read_at"`
	Board  Document `json:"board"`
}

// Rigs is what the rig list route answers: the city's rigs by name, each the
// address of a page.
type Rigs struct {
	ReadAt string   `json:"read_at"`
	Rigs   []string `json:"rigs"`
}

// Document is one rig's board.
type Document struct {
	Rig string `json:"rig"`
	// Rows holds every object a page draws, by bead id. A page draws an object
	// the same way wherever it appears.
	Rows map[string]Row `json:"rows"`
	// Epics is the Epics page: every open epic of the rig, in priority order.
	Epics []EpicEntry `json:"epics"`
	// NeedsYou is the Needs you page: every need in the rig, and how many of
	// them count.
	NeedsYou NeedsYou `json:"needs_you"`
	// WorkQueue is the Work queue page: every open piece of work in the rig
	// that does not carry hold:mayor.
	WorkQueue WorkQueue `json:"work_queue"`
	// Unprioritized is the Unprioritized page: every open bead that carries
	// hold:mayor, grouped by priority, newest first in each.
	Unprioritized []PriorityGroup `json:"unprioritized"`
}

// Kind is what a row is.
type Kind string

const (
	KindEpic         Kind = "epic"
	KindDelivery     Kind = "delivery"
	KindWork         Kind = "work"
	KindGate         Kind = "gate"
	KindDecision     Kind = "decision"
	KindConversation Kind = "conversation"
)

// Row is one object, as every page draws it.
type Row struct {
	ID        string `json:"id"`
	Kind      Kind   `json:"kind"`
	Priority  int    `json:"priority"`
	Title     string `json:"title"`
	Status    string `json:"status"`
	CreatedAt string `json:"created_at"`
	Assignee  string `json:"assignee,omitempty"`
	// Signal is the row's state in words, from the table in table.go, and Note
	// is what the table gives beside it: the gate's title for a row a gate
	// holds, the assignee of work in flight, how a closed bead closed. A
	// signal names the bead it waits on when it waits on one.
	Signal string `json:"signal"`
	Note   string `json:"note,omitempty"`
	// Group is the row's group, empty when no group holds it.
	Group Group `json:"group,omitempty"`
	// Ask is what the row asks of a person, empty when it is no need, as it is
	// for work held for the Product Owner. A row that is a need is drawn as one
	// wherever it appears, tagged with its ask, and a Needs you view counts it
	// by its kind (Need).
	Ask Ask `json:"ask,omitempty"`
	// Line2 is an epic's hypothesis, a Delivery's aim, or the message of a
	// gate, a decision or a conversation, less its first line when that line
	// is the title. A piece of work has none.
	Line2 string `json:"line2,omitempty"`
	// Line3 names the beads the table puts on the row's third line: what a
	// wait further along ends on, or each wait that holds work nobody is
	// scheduled to do.
	Line3 []Ref `json:"line3,omitempty"`
	// Reasons are what holds a pull request a person owes a move on, in the
	// pack's words (prstatus.Reasons, or prstatus.RenderReasons over the
	// evaluator's answer for a pull request on Gas Town's pending record).
	Reasons []Reason `json:"reasons,omitempty"`
	// PullRequest is the facts of the bead's pull request, when it has one.
	PullRequest *PullRequest `json:"pull_request,omitempty"`
	// Counts are what an epic or a Delivery holds at any depth beneath it: the
	// needs that hold or concern it, and its work by where it sits. Closed work
	// counts as far as the read gathers it: the closed members of each open
	// epic and Delivery and of each closed epic among them, and none beneath a
	// bead that is not an epic.
	Counts *Counts `json:"counts,omitempty"`
	// Contract is an epic's contract and its latest ruling.
	Contract *Contract `json:"contract,omitempty"`
	// Waits are what the bead waits on, each wait behind its status, and
	// WaitedOnBy the open beads whose own waits name it.
	Waits      []Ref `json:"waits"`
	WaitedOnBy []Ref `json:"waited_on_by"`
	// Holds is, for a need, every bead it holds through any chain of waits
	// (prstatus.Holding's answer), less work held for the Product Owner, which
	// the Unprioritized page alone lists: its work in the Work queue's order,
	// then the epics and Deliveries it holds.
	Holds []string `json:"holds"`
	// Conversation is, for a question, the open conversation that answers it.
	Conversation string `json:"conversation,omitempty"`
	// Anchored are the open beads that carry anchor_bead naming this one: its
	// reviews, reworks, validations and findings, which have no row of their
	// own.
	Anchored []Ref `json:"anchored,omitempty"`
}

// Ref names a bead a row refers to.
type Ref struct {
	ID    string `json:"id"`
	Title string `json:"title"`
}

// Reason is one thing that holds a pull request: the held: value it stands
// for and what it is, a bead when ID names one.
type Reason struct {
	Held  string `json:"held"`
	ID    string `json:"id,omitempty"`
	Title string `json:"title"`
}

// PullRequest is a bead's pull request in the pack's words: its number and
// link, where it stands (working, merging, needs-review, needs-attention), and
// what holds it.
type PullRequest struct {
	Number string   `json:"number"`
	URL    string   `json:"url,omitempty"`
	State  string   `json:"state,omitempty"`
	Held   []string `json:"held,omitempty"`
}

// Counts are what a container holds. Needs counts each need that holds or
// concerns it once, of the needs that count (NeedsYou), and reaches zero as
// the operator acts. Queue, NotScheduled and Closed count its work by where it
// sits.
type Counts struct {
	Needs        int `json:"needs"`
	Queue        int `json:"queue"`
	NotScheduled int `json:"not_scheduled"`
	Closed       int `json:"closed"`
}

// Contract is the contract an epic carries and its latest ruling, each field
// as the epic records it (docs/epic-stewardship.md).
type Contract struct {
	Handle           string `json:"handle,omitempty"`
	Hypothesis       string `json:"hypothesis,omitempty"`
	Boundaries       string `json:"boundaries,omitempty"`
	ClosureCondition string `json:"closure_condition,omitempty"`
	Indicators       string `json:"indicators,omitempty"`
	Ruling           string `json:"ruling,omitempty"`
	RulingReason     string `json:"ruling_reason,omitempty"`
	RulingAt         string `json:"ruling_at,omitempty"`
}

// EpicEntry is one epic on the Epics page: the two views of the work it holds
// nearest, its closed work, and its Deliveries. Work whose parent-child edges
// reach more than one epic or Delivery is listed under each.
type EpicEntry struct {
	ID         string          `json:"id"`
	Needs      NeedsYou        `json:"needs"`
	Queue      WorkQueue       `json:"queue"`
	Closed     []string        `json:"closed"`
	Deliveries []DeliveryEntry `json:"deliveries"`
}

// DeliveryEntry is one Delivery under an epic it sits under: the two views of
// the work it holds nearest, and its closed work.
type DeliveryEntry struct {
	ID     string    `json:"id"`
	Needs  NeedsYou  `json:"needs"`
	Queue  WorkQueue `json:"queue"`
	Closed []string  `json:"closed"`
}

// Need is one entry of a Needs you view: a need, its kind, and the beads it
// holds that the view covers, its work in the Work queue's order and then the
// epics and Deliveries it holds. A view lists its needs in the order of the
// first bead each holds in the Work queue, so the top need is the one holding
// up the front of the queue. A need that is itself queued work counts its own
// place too. A need that holds no queued work comes after those that do, by
// the first unscheduled work it holds, and one that holds no work at all comes
// last, by priority, then oldest, then id.
type Need struct {
	ID    string   `json:"id"`
	Kind  NeedKind `json:"kind"`
	Holds []string `json:"holds"`
}

// NeedsYou is a Needs you view: the Needs you page over the whole rig, and the
// view of each epic and Delivery over the needs that hold or concern the work
// it holds nearest. It lists every need it covers, each once and in the order
// a view lists them, the needs that count first.
//
// A need does not count when what it is about is parked or waits for the
// Product Owner. It is parked itself when it, or an epic or Delivery above it,
// waits on a park, a gate that is no human gate. A gate, a decision or a
// conversation does not count when every bead it holds or is about is parked,
// is a need that does not count, or carries hold:mayor, the Unprioritized
// page's work. A need that is about nothing else counts, and so does a pull
// request or other work that is itself a need, unless it is parked itself.
//
// Count is the needs that count, and it reaches zero only when nothing that
// counts needs you. Kinds is how many of them are of each kind: Pull request,
// Question, Conversation waits for you, In conversation and Ruling, each one
// zero included, then Routed to you when one counts. Counted lists the needs
// that count, and NotCounted the needs that do not.
type NeedsYou struct {
	Count      int         `json:"count"`
	Kinds      []KindCount `json:"kinds"`
	Counted    []Need      `json:"counted"`
	NotCounted []Need      `json:"not_counted"`
}

// KindCount is how many of a view's needs that count are of one kind.
type KindCount struct {
	Kind  NeedKind `json:"kind"`
	Count int      `json:"count"`
}

// WorkQueue is a Work queue view: the work in the order it is expected to land
// (services/gctk/queue). Queue is the work the city takes as things stand: by
// bd graph's execution layers, what can go now first, and within a layer in
// the order the pool claims ready work, priority, then oldest, then id.
// NotScheduled comes after it, in the same order: work the city takes none of
// as things stand, since nobody has scheduled it or a hold label holds it, as
// queue reads its row, and work that waits on such work. Unread is the work a
// reader could not answer, in priority order and then oldest first.
type WorkQueue struct {
	Queue        []string `json:"queue"`
	NotScheduled []string `json:"not_scheduled"`
	Unread       []string `json:"unread"`
}

// PriorityGroup is the rows of one priority.
type PriorityGroup struct {
	Priority int      `json:"priority"`
	IDs      []string `json:"ids"`
}
