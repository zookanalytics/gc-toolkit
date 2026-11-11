package rigboard

// The document one rig's read builds: every row the pages draw, once each, and
// the four pages as lists of row ids. Go decides every group, signal, count,
// ask, section and order in it, and the page lays it out and filters it. The
// page's TypeScript types are generated from this file
// (web/src/rigboard/document.gen.ts), and TestPageTypesAreCurrent fails when
// that file is stale.

// Response is what the rig's route answers: the document, and the time its
// gather finished beside it. The document depends on the store's answers
// alone, so two reads of an unchanged store give the same document.
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
	// NeedsYou is the Needs you page.
	NeedsYou NeedsYou `json:"needs_you"`
	// WorkQueue is the Work queue page: its sections in order, each listed
	// only when it holds a row.
	WorkQueue []Section `json:"work_queue"`
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
	// Ask is the kind of ask the row is, empty when it is none.
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
	// pack's words (prstatus.Reasons).
	Reasons []Reason `json:"reasons,omitempty"`
	// PullRequest is the facts of the bead's pull request, when it has one.
	PullRequest *PullRequest `json:"pull_request,omitempty"`
	// Counts are an epic's or a Delivery's work at any depth beneath it, by
	// group. Gates, conversations and decisions are not counted. Closed work
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
	// Asks are the asks that stop this row's work, which the Epics and Work
	// queue pages draw as its children.
	Asks []string `json:"asks"`
	// Holds is, for an ask, the work it holds, which the Needs you page draws
	// as its children.
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

// Counts are a container's work by group.
type Counts struct {
	WaitingOnYou int `json:"waiting_on_you"`
	Queued       int `json:"queued"`
	NotMoving    int `json:"not_moving"`
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

// EpicEntry is one epic on the Epics page: its own asks, its Deliveries, and
// the work under it that no Delivery holds, in the four groups.
type EpicEntry struct {
	ID         string          `json:"id"`
	Asks       []string        `json:"asks"`
	Deliveries []DeliveryEntry `json:"deliveries"`
	Groups     []GroupList     `json:"groups"`
	// Unread is the work under it a reader could not answer, in no group.
	Unread []string `json:"unread"`
}

// DeliveryEntry is one Delivery under its epic: its own asks and its work in
// the four groups.
type DeliveryEntry struct {
	ID     string      `json:"id"`
	Asks   []string    `json:"asks"`
	Groups []GroupList `json:"groups"`
	Unread []string    `json:"unread"`
}

// GroupList is the rows of one group, in priority order and then oldest
// first. A group with no row is not listed.
type GroupList struct {
	Group Group    `json:"group"`
	IDs   []string `json:"ids"`
}

// NeedsYou is the Needs you page. Count is the asks that hold or concern work
// under an epic, each counted once, and it reaches zero when none does.
type NeedsYou struct {
	Count int `json:"count"`
	// InConversation is every ask a conversation answers, under an epic or
	// not.
	InConversation []string `json:"in_conversation"`
	// NoConversationYet is the other asks under each epic they hold or
	// concern work under, epics in priority order. An ask under two epics is
	// listed under each.
	NoConversationYet []EpicAsks `json:"no_conversation_yet"`
	// NoEpic is the asks no conversation answers that hold or concern no work
	// under an epic. No ask under no epic is counted, in conversation or not.
	NoEpic []string `json:"no_epic"`
}

// EpicAsks is the asks under one epic.
type EpicAsks struct {
	Epic string   `json:"epic"`
	Asks []string `json:"asks"`
}

// Section is one section of the Work queue: its rows, or its parts.
type Section struct {
	Name  string    `json:"name"`
	Rows  []Entry   `json:"rows"`
	Parts []Section `json:"parts,omitempty"`
}

// Entry is one row of a section, with the rows drawn beneath it: a gate with
// the work it holds.
type Entry struct {
	ID       string   `json:"id"`
	Children []string `json:"children,omitempty"`
}

// PriorityGroup is the rows of one priority.
type PriorityGroup struct {
	Priority int      `json:"priority"`
	IDs      []string `json:"ids"`
}
