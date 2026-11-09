// Package form is the terminal conversation form: the screen `gc-helm.sh
// engage` and `gc-helm.sh attach` hand a terminal to. One screen holds the
// subject, a new topic's rig, the model and a multiline question, while the
// subject's details, its open conversations and the city's rigs load in the
// background. Submitting saves the question as a conversation, starts its
// sitting without attaching, and reports each of the two as it lands. The
// return list shows the open conversations by topic and readiness and attaches
// to the one picked.
//
// The form writes nothing itself. Every read and write is a gc-helm.sh verb
// ([Script]), so what the form shows and files is what the command line shows
// and files.
package form

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/verbs"
)

// About is `gc-helm.sh conversations <ref> --json`: the subject a reference
// names, resolved as engage resolves it, and where a conversation about it would
// be held. A bare PR number more than one live anchor records answers
// Candidates instead.
type About struct {
	Ref           string         `json:"ref"`
	Subject       Subject        `json:"subject"`
	Gate          string         `json:"gate"`
	Conversation  string         `json:"conversation"`
	Closed        *Closed        `json:"closed"`
	Refusal       string         `json:"refusal"`
	Conversations []Conversation `json:"conversations"`
	Holds         []Hold         `json:"holds"`
	HoldsRead     bool           `json:"holds_read"`
	Candidates    []Candidate    `json:"candidates"`
}

// Subject is the bead a conversation is about.
type Subject struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	Status    string `json:"status"`
	IssueType string `json:"issue_type"`
	Rig       string `json:"rig"`
}

// Closed is a closed conversation the reference named.
type Closed struct {
	ID   string `json:"id"`
	Said string `json:"said"`
}

// Hold is what holds the subject: an open human gate, a blocker a person has
// to clear, or, with no ID, the PR's own review threads or blocked verdict.
type Hold struct {
	Held  string `json:"held"`
	ID    string `json:"id"`
	Title string `json:"title"`
}

// Candidate is one live anchor a PR number names.
type Candidate struct {
	ID     string `json:"id"`
	Rig    string `json:"rig"`
	Title  string `json:"title"`
	Status string `json:"status"`
}

// Conversation is one row of `conversations`: an open conversation, its state as
// engage reads it (live, queue or left), its live sitting's session, and its
// readiness.
type Conversation struct {
	ID           string   `json:"id"`
	Rig          string   `json:"rig"`
	Subject      string   `json:"subject"`
	SubjectTitle string   `json:"subject_title"`
	Title        string   `json:"title"`
	Status       string   `json:"status"`
	Holder       string   `json:"holder"`
	CreatedAt    string   `json:"created_at"`
	HandbackAt   string   `json:"handback_at"`
	State        string   `json:"state"`
	Readiness    string   `json:"readiness"`
	Session      *Session `json:"session"`
}

// Attached says whether a terminal is attached to the conversation's sitting.
func (c Conversation) Attached() bool { return c.Session != nil && c.Session.Attached }

// Session is the live sitting's session.
type Session struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	State     string `json:"state"`
	Attached  bool   `json:"attached"`
	CreatedAt string `json:"created_at"`
}

// The readiness values `conversations` gives a conversation.
const (
	Queued    = "queued"
	Starting  = "starting"
	Preparing = "preparing"
	Ready     = "ready"
	Ended     = "ended"
)

// City is `gc-helm.sh conversations --json`: every open conversation in the
// city's stores, the rigs a new topic can be filed in, and the rigs whose store
// could not be read, because it did not answer or its ledger is not there.
type City struct {
	Conversations []Conversation `json:"conversations"`
	Rigs          []Rig          `json:"rigs"`
	Unread        []string       `json:"unread"`
}

// Rig is a rig a new topic could be filed in.
type Rig struct {
	Name      string `json:"name"`
	Converse  bool   `json:"converse"`
	Suspended bool   `json:"suspended"`
}

// Hosts says whether a sitting can be held in the rig: it carries a converse
// template and is not suspended.
func (r Rig) Hosts() bool { return r.Converse && !r.Suspended }

// SaveRequest is a question to file as a conversation. Ref is the reference
// the destination was verified for: the subject as the operator typed it, or
// the gate the conversation replies to. Subject is the subject the form showed
// for it. A new topic leaves both empty and names its Rig. Conversation is set
// on a save again: the conversation an earlier save filed and did not complete,
// which this save completes rather than file another.
type SaveRequest struct {
	Ref          string
	Subject      string
	Rig          string
	Question     string
	Conversation string
}

// Saved is what `gc-helm.sh open --json` answers. Filed is false when a new
// subject was filed and its conversation was not. Filed with a conversation is a
// conversation that holds the question, even from a save that then failed, as
// when the store refused its reply onto the gate.
type Saved struct {
	Subject      string `json:"subject"`
	Conversation string `json:"conversation"`
	Filed        bool   `json:"filed"`
}

// Helm is what the form reads and writes, each call one gc-helm.sh verb.
type Helm interface {
	About(ctx context.Context, ref string) (About, error)
	City(ctx context.Context) (City, error)
	Save(ctx context.Context, req SaveRequest) (Saved, error)
	Start(ctx context.Context, conversation, model string) error
	// AttachCommand is the command that attaches the terminal to a
	// conversation's sitting, holding it in a new sitting first when it has
	// none: on model, or on engage's default when model is empty.
	AttachCommand(conversation, model string) *exec.Cmd
}

// Script runs gc-helm.sh at Path.
type Script struct {
	Path    string
	Timeout time.Duration
}

// lastLine is the last non-empty line of s: the sentence a gc-helm.sh refusal
// ends with.
func lastLine(s string) string {
	lines := strings.Split(strings.TrimSpace(s), "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		if l := strings.TrimSpace(lines[i]); l != "" {
			return l
		}
	}
	return ""
}

// lastJSON decodes the last JSON value gc-helm.sh printed on stdout into v.
// The verbs print one compact object, and a stdout that is not a JSON stream
// (a notice line ahead of it) is read for its last line that opens an object.
func lastJSON(stdout string, v any) error {
	var last json.RawMessage
	dec := json.NewDecoder(strings.NewReader(stdout))
	for {
		var m json.RawMessage
		if err := dec.Decode(&m); err != nil {
			break
		}
		last = m
	}
	if last == nil {
		lines := strings.Split(strings.TrimSpace(stdout), "\n")
		for i := len(lines) - 1; i >= 0 && last == nil; i-- {
			if l := strings.TrimSpace(lines[i]); strings.HasPrefix(l, "{") {
				last = json.RawMessage(l)
			}
		}
	}
	if last == nil {
		return errors.New("no JSON answer")
	}
	return json.Unmarshal(last, v)
}

// run executes `sh <Path> <args...>`. A run that exits non-zero is an error
// carrying the refusal gc-helm.sh printed, and the stdout it printed first.
func (s Script) run(ctx context.Context, args ...string) (string, error) {
	t := s.Timeout
	if t <= 0 {
		t = verbs.DefaultTimeout
	}
	res, err := verbs.Exec(ctx, "sh", "", t, append([]string{s.Path}, args...)...)
	if err != nil {
		return res.Stdout, err
	}
	if res.ExitCode != 0 {
		why := lastLine(res.Stderr)
		if why == "" {
			why = fmt.Sprintf("gc-helm.sh %s exited %d", args[0], res.ExitCode)
		}
		return res.Stdout, &Refusal{Code: res.ExitCode, Why: why}
	}
	return res.Stdout, nil
}

// Refusal is a verb that exited non-zero, and the sentence it gave.
type Refusal struct {
	Code int
	Why  string
}

func (r *Refusal) Error() string { return r.Why }

// About runs `conversations <ref> --json`.
func (s Script) About(ctx context.Context, ref string) (About, error) {
	var a About
	out, err := s.run(ctx, "conversations", ref, "--json")
	if err != nil {
		return a, err
	}
	if err := lastJSON(out, &a); err != nil {
		return a, fmt.Errorf("gc-helm.sh conversations %s: %w", ref, err)
	}
	return a, nil
}

// City runs `conversations --json`. A store that could not be read exits 4
// after the list, which is still the list.
func (s Script) City(ctx context.Context) (City, error) {
	var c City
	out, err := s.run(ctx, "conversations", "--json")
	var r *Refusal
	if err != nil && !(errors.As(err, &r) && r.Code == 4 && strings.TrimSpace(out) != "") {
		return c, err
	}
	if jerr := lastJSON(out, &c); jerr != nil {
		if err != nil {
			return c, err
		}
		return c, fmt.Errorf("gc-helm.sh conversations: %w", jerr)
	}
	return c, nil
}

// Save runs open: `open --new-subject --rig <rig> --reason <question> --json`
// for a new topic, or `open <ref> --allow-duplicate --if-subject <subject>
// --reason <question> --json`, since a question the operator brings is a
// concern of its own, and open refuses a reference that names another subject
// than the one the form showed. The question rides as one argv element,
// unchanged. A new subject filed whose conversation was not comes back with the
// error, so a retry files onto that subject, and so does a conversation filed
// whose save then failed. A save again names that conversation with
// `--conversation <id>`, and open completes it wherever it stands, files
// nothing, and refuses one it cannot complete.
func (s Script) Save(ctx context.Context, req SaveRequest) (Saved, error) {
	var sv Saved
	args := []string{"open"}
	switch {
	case req.Ref == "" && req.Conversation != "":
		return sv, fmt.Errorf("conversation %s was saved again with no subject, so the save has nothing to complete it on", req.Conversation)
	case req.Ref == "":
		args = append(args, "--new-subject", "--rig", req.Rig)
	case req.Subject == "":
		return sv, fmt.Errorf("no subject was shown for %s, so the save has nothing to file against", req.Ref)
	default:
		args = append(args, req.Ref, "--allow-duplicate", "--if-subject", req.Subject)
		if req.Conversation != "" {
			args = append(args, "--conversation", req.Conversation)
		}
	}
	args = append(args, "--reason", req.Question, "--json")
	out, err := s.run(ctx, args...)
	if jerr := lastJSON(out, &sv); jerr != nil && err == nil {
		return sv, fmt.Errorf("gc-helm.sh open: %w", jerr)
	}
	if err == nil && (!sv.Filed && sv.Conversation == "") {
		return sv, errors.New("gc-helm.sh open answered without a conversation")
	}
	return sv, err
}

// Start runs `engage <conversation> --no-input --no-attach --model <model>`:
// the sitting is spawned and bound, and nothing attaches.
func (s Script) Start(ctx context.Context, conversation, model string) error {
	args := []string{"engage", conversation, "--no-input", "--no-attach"}
	if model != "" {
		args = append(args, "--model", model)
	}
	_, err := s.run(ctx, args...)
	return err
}

// AttachCommand is `engage <conversation> --no-input [--model <model>]`,
// engage's attach: it waits for the sitting to start, attaches, and prints how
// the sitting ended once the terminal comes back. engage attaches a live
// sitting whatever its model, and spawns a conversation no live sitting holds
// on the model, so --model decides only that spawn.
func (s Script) AttachCommand(conversation, model string) *exec.Cmd {
	args := []string{s.Path, "engage", conversation, "--no-input"}
	if model != "" {
		args = append(args, "--model", model)
	}
	return exec.Command("sh", args...)
}
