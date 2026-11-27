package review

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// A fresh look reads the whole review of a PR: every round of its run with
// the account of the rounds, the PR's earlier runs and how each ended, and the
// review's rules that changed under the PR. It writes its verdict, and its
// record files the question of a look that stops the review on the bead that
// owns the PR, notes the reading there, and marks the look's own step failed
// hard, so the loop ends at that round once the step closes failed
// (formula-spec-v2.md, section 3.1).

// LookRead is what a fresh look reads: its step, the account of the run's
// rounds up to the look's, and the PR's earlier runs.
type LookRead struct {
	Step    *Step
	Account Account
	Earlier []EarlierRun
}

// EarlierRun is another review run of the PR: its root, when it was poured,
// its first head, the account of its rounds, and how it ended, "" while it is
// open.
type EarlierRun struct {
	Root, Poured, Head string
	Account            Account
	How                string
}

// ReadLook reads what the fresh look id names judges. A step that is no look
// is a *NotARun, and a read that fails returns the store's error.
func ReadLook(l *ledger.Ledger, id string) (*LookRead, error) {
	st, err := ReadStep(l, id)
	if err != nil {
		return nil, err
	}
	if st.Output != OutputLook {
		return nil, &NotARun{ID: id, Why: fmt.Sprintf("it is the step %s, not a fresh look", st.Ref)}
	}
	out := &LookRead{Step: st, Account: Converge(st.Run, st.Iteration)}
	owner, err := one(l, st.Run.PRBead)
	if err != nil {
		return nil, err
	}
	edges, err := owner.Edges()
	if err != nil {
		return nil, &ledger.ReadError{ID: owner.ID, Reason: "its edges did not decode: " + err.Error()}
	}
	for _, e := range edges {
		if e.Type != ledger.EdgeBlocks || e.ID == st.Run.Root {
			continue
		}
		b, err := one(l, e.ID)
		if err != nil {
			return nil, err
		}
		if str(prBeadVar, b) != owner.ID || (str(rootBeadKey, b) != "" && str(rootBeadKey, b) != b.ID) {
			continue
		}
		run, err := ReadRun(l, b.ID)
		if err != nil {
			return nil, err
		}
		er := EarlierRun{Root: run.Root, Poured: b.CreatedAt(), Head: run.Head, Account: Converge(run, run.Latest())}
		if b.Status() == "closed" {
			end, err := Ended(l, run.Root)
			if err != nil {
				return nil, err
			}
			er.How = end.How
		}
		out.Earlier = append(out.Earlier, er)
	}
	slices.SortFunc(out.Earlier, func(a, b EarlierRun) int { return strings.Compare(a.Poured, b.Poured) })
	return out, nil
}

// FirstHead is the head the PR's review first judged that dir holds: the first
// head of the PR's earliest run that dir holds, else head, the head the look's
// round judged.
func (r *LookRead) FirstHead(dir, head string) string {
	for _, e := range r.Earlier {
		if e.Head != "" && git.HasCommit(dir, e.Head) {
			return e.Head
		}
	}
	if h := r.Step.Run.Head; h != "" && git.HasCommit(dir, h) {
		return h
	}
	return head
}

// Since is when the PR's first review run was poured, the earliest of its
// runs, the start of the window the pack's rules that changed are read over.
func (r *LookRead) Since(l *ledger.Ledger) (time.Time, error) {
	root, err := one(l, r.Step.Run.Root)
	if err != nil {
		return time.Time{}, err
	}
	first := root.CreatedAt()
	for _, e := range r.Earlier {
		if e.Poured != "" && e.Poured < first {
			first = e.Poured
		}
	}
	at, err := time.Parse(time.RFC3339Nano, first)
	if err != nil {
		return time.Time{}, &ledger.ReadError{ID: root.ID, Reason: fmt.Sprintf("its create time %q does not read as a time", first)}
	}
	return at, nil
}

// RuleChange is one commit that changed the review's rules: its object name,
// its date, its subject and the rules it touched.
type RuleChange struct {
	Commit, Date, Subject string
	Paths                 []string
}

// The review's rules a commit can change. A rig keeps its own at the root of
// its checkout: the agents' instructions, the check index and the guidance for
// each check, which a lane reads at the head it judges. The pack keeps the
// method of each check and the run's steps, which a step loads from the pack
// the city has installed.
var (
	rigRules  = []string{"AGENTS.md", "CLAUDE.md", "review-checks.toml", "docs/review-*.md"}
	packRules = []string{"skills/review-*", "formulas/mol-pr-review*.toml"}
)

// RulesChanged is each commit that changed the review's rules under the PR,
// each once. In the rig's checkout it is each commit on origin's copy of target
// that first, the head the PR's review first judged, does not carry. A lane
// reads the rig's rules at the head it judges, so such a commit reaches the
// review once the PR's branch carries it, whatever its date: a fast-forward or
// a merge lands a commit with the date it was made. In the pack's checkout it
// is each commit since since on what the checkout has checked out, from which
// the city installs the pack, and whose main lands each change as one commit
// dated when it landed. A pack that is no checkout of its own reads nothing,
// and a read that fails is an error.
func RulesChanged(rig, pack, target, first string, since time.Time) ([]RuleChange, error) {
	var out []RuleChange
	seen := map[string]bool{}
	read := func(dir string, paths []string, revs ...string) error {
		args := append([]string{"log", "--format=%x1e%H%x1f%cs%x1f%s", "--name-only"}, revs...)
		raw, err := git.Output(dir, append(append(args, "--"), paths...)...)
		if err != nil {
			return fmt.Errorf("the rules that changed in %s did not read: %w", dir, err)
		}
		for _, rec := range strings.Split(raw, "\x1e") {
			head, files, _ := strings.Cut(strings.TrimSpace(rec), "\n")
			parts := strings.Split(head, "\x1f")
			if len(parts) != 3 || seen[parts[0]] {
				continue
			}
			seen[parts[0]] = true
			c := RuleChange{Commit: parts[0], Date: parts[1], Subject: parts[2]}
			for _, f := range strings.Split(files, "\n") {
				if f = strings.TrimSpace(f); f != "" {
					c.Paths = append(c.Paths, f)
				}
			}
			out = append(out, c)
		}
		return nil
	}
	if rig != "" {
		if err := read(rig, rigRules, "^"+first, "origin/"+target); err != nil {
			return nil, err
		}
	}
	if top, ok := git.Toplevel(pack); ok && pack != "" {
		if err := read(top, packRules, "--since="+since.UTC().Format(time.RFC3339), "HEAD"); err != nil {
			return nil, err
		}
	}
	slices.SortStableFunc(out, func(a, b RuleChange) int { return strings.Compare(b.Date, a.Date) })
	return out, nil
}

// Print writes what the look reads: the account and the rule's reading at its
// round, every round of the run with each finding and its ruling, the PR's
// earlier runs, the rules that changed as RulesChanged read them from first and
// since, the PR's change in the rig's checkout, and the output to write.
func (r *LookRead) Print(w io.Writer, rules []RuleChange, first string, since time.Time, repo string) {
	st, run, n := r.Step, r.Step.Run, r.Step.Iteration
	head := run.HeadOf(n)
	if it := run.Iterations[n]; it != nil && it.Triage != nil {
		head = it.Triage.Head
	}
	fmt.Fprintf(w, "look %s at round %d of review run %s on %s\n", st.ID, n, run.Root, run.PRBead)
	fmt.Fprintf(w, "PR %s: %s into %s, round %d judged %s\n", st.PR(), st.Branch, run.Target, n, head)
	fmt.Fprintf(w, "account: %s\n", r.Account.Line())
	switch {
	case r.Account.Last:
		fmt.Fprintf(w, "rule: round %d is the run's last by its bound, so the look stops the review\n", n)
	case r.Account.Forced != "":
		fmt.Fprintf(w, "rule: it forces a question, as %s, so the look sends the review on only by naming the rules "+
			"below that caused the counts\n", r.Account.Forced)
	default:
		fmt.Fprintln(w, "rule: it forces no question at this round, so the look decides")
	}
	fmt.Fprintln(w, "== Each round of this run")
	for m := 1; m <= n; m++ {
		it := run.Iterations[m]
		if it == nil || it.Triage == nil {
			continue
		}
		rd, _ := r.Account.round(m)
		pushed := "nothing"
		if it.Repair != nil && it.Repair.Pushed != "" {
			pushed = it.Repair.Pushed
		}
		fmt.Fprintf(w, "round %d at %s: %s, pushed %s\n", m, it.Triage.Head, mustFix(rd.MustFix), pushed)
		var rulings []Ruling
		if it.Repair != nil {
			rulings = it.Repair.Rulings
		}
		for _, ln := range it.Lanes {
			fmt.Fprintf(w, "  lane %s: %s\n", ln.Check, ln.Verdict)
			for _, f := range ln.Findings {
				fmt.Fprintf(w, "    %s %s %s: %s\n", f.ID, orNone([]string{f.Severity}), f.Locus, oneLine(f.Message))
				if ru, ok := rulingOf(rulings, func(x Ruling) bool { return x.rulesFinding(ln.Check, f.ID) }); ok {
					var b strings.Builder
					explainRuling(&b, ru)
					fmt.Fprint(w, "  "+b.String())
					if ru.Restates != nil {
						fmt.Fprintf(w, "      back after a fix: it restates %s\n", ru.Restates)
					}
				}
			}
		}
		for _, ru := range rulings {
			if ru.Ask != "" {
				var b strings.Builder
				explainRuling(&b, ru)
				fmt.Fprint(w, b.String())
			}
		}
		if it.Look != nil && m < n {
			fmt.Fprintf(w, "  fresh look: %s: %s\n", it.Look.Verdict, oneLine(it.Look.Reading))
		}
	}
	fmt.Fprintf(w, "== Earlier runs on %s\n", run.PRBead)
	if len(r.Earlier) == 0 {
		fmt.Fprintln(w, "none")
	}
	for _, e := range r.Earlier {
		how := e.How
		if how == "" {
			how = "it is still open"
		}
		fmt.Fprintf(w, "run %s poured %s at %s: must-fix by round %s; %s\n", e.Root, e.Poured, e.Head,
			orNone([]string{e.Account.Counts()}), how)
	}
	fmt.Fprintln(w, "== The review's rules that changed under the PR")
	if first != "" {
		fmt.Fprintf(w, "on origin/%s: each commit that %s, the head the PR's review first judged, does not carry\n",
			run.Target, first)
	} else {
		fmt.Fprintf(w, "on origin/%s: none read, as no checkout here holds the round's head\n", run.Target)
	}
	fmt.Fprintf(w, "in the pack: each commit since the PR's first run was poured, %s\n", since.UTC().Format(time.RFC3339))
	if len(rules) == 0 {
		fmt.Fprintln(w, "none")
	}
	for _, c := range rules {
		fmt.Fprintf(w, "%s %s %s (%s)\n", c.Commit, c.Date, c.Subject, strings.Join(c.Paths, ", "))
	}
	fmt.Fprintln(w, "== The PR's change at the head the round judged")
	if repo != "" {
		fmt.Fprintf(w, "git -C %s log --format='%%h %%s' origin/%s..%s\n", repo, run.Target, head)
		fmt.Fprintf(w, "git -C %s diff origin/%s...%s\n", repo, run.Target, head)
	} else {
		fmt.Fprintf(w, "no checkout here holds %s, so read the PR at %s\n", head, st.PR())
	}
	fmt.Fprintln(w, "== The output to write, one JSON object, then record it with --file")
	example := Look{Review: OutputLook, Iteration: n, Head: head, Verdict: LookContinue + " or " + LookStop,
		Reading:        "why the findings keep coming, and whether that points to the PR's approach being wrong overall",
		Recommendation: "for a stop: what you recommend the person rule, and why",
		Question:       "for a stop: the one question for the person, with the options and what each costs",
		Rules:          []string{"each commit above the reading gives as the cause of the counts"}}
	raw, _ := json.Marshal(example)
	fmt.Fprintln(w, string(raw))
}

// LookRecord is what a look's record did: the look as its step keeps it, the
// gate that puts its question to a person, "" for a look that sends the review
// on, and whether it noted the look on the bead that owns the PR.
type LookRecord struct {
	Look  Look
	Step  string
	Bead  string
	Gate  string
	Noted bool
}

// LookUnrecorded is a look's record whose write did not land, with why. What
// landed before it stands, and the record run again makes the rest.
type LookUnrecorded struct{ Why string }

func (e *LookUnrecorded) Error() string { return e.Why }

// RecordLook checks the output a fresh look wrote, then records it, each write
// one that a run again makes no different: a stop's question goes to a human
// gate on the bead that owns the PR under LookQuestionKey, which filer files
// or finds open there; the look's step takes the look as its output, and for a
// stop Gas City's hard failure record; and the bead that owns the PR is noted
// with the look, stamped at. Each rule the look names is one of changed, the
// review's rules that changed under the PR, as the look's read printed them
// (RulesChanged). An output that does not stand returns its *Refused, a read
// that fails the store's error, and a write that does not land a
// *LookUnrecorded, after the writes before it landed.
func RecordLook(l *ledger.Ledger, req OutputRequest, changed []RuleChange, filer Gates, at time.Time) (*LookRecord, error) {
	raw, err := Output(l, req)
	if err != nil {
		return nil, err
	}
	var lk Look
	if err := json.Unmarshal(raw, &lk); err != nil {
		return nil, err
	}
	for _, c := range lk.Rules {
		if !slices.ContainsFunc(changed, func(rc RuleChange) bool { return rc.Commit == c }) {
			return nil, refuse("the rule %s is none of the review's rules that changed under the PR, which the look's read prints", c)
		}
	}
	st, err := ReadStep(l, req.Step)
	if err != nil {
		return nil, err
	}
	run, n := st.Run, st.Iteration
	out := &LookRecord{Step: st.ID, Bead: run.PRBead}
	acct := Converge(run, n)
	if lk.Verdict == LookStop {
		if filer == nil {
			return nil, fmt.Errorf("no gate filer was given, so the look's question reaches no person")
		}
		if err := filer.File(run.PRBead, LookQuestionKey, lookMessage(st, acct, lk)); err != nil {
			return nil, &LookUnrecorded{Why: fmt.Sprintf("the look's question did not land on %s: %v", run.PRBead, err)}
		}
		gate, err := openGate(l, run.PRBead, LookQuestionKey)
		if err != nil {
			return nil, err
		}
		lk.Gate, out.Gate = gate, gate
	}
	var b bytes.Buffer
	enc := json.NewEncoder(&b)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(lk); err != nil {
		return nil, err
	}
	w := l.Write(st.ID)
	w.StepOutput(strings.TrimRight(b.String(), "\n"))
	if lk.Verdict == LookStop {
		w.FailureRecord("hard", fmt.Sprintf("the review is not converging, so its fresh look at round %d put it to a person%s",
			n, through(out.Gate)))
	}
	if err := l.Commit(w); err != nil {
		return out, &LookUnrecorded{Why: fmt.Sprintf("the look's output did not land on %s: %v", st.ID, err)}
	}
	out.Look = lk
	nw := l.Write(run.PRBead)
	nw.Note(lookNote(st, acct, lk, at))
	if err := l.Commit(nw); err != nil {
		return out, &LookUnrecorded{Why: fmt.Sprintf("the look's output landed and its note on %s did not: %v", run.PRBead, err)}
	}
	out.Noted = true
	return out, nil
}

// through is " through <gate>", or "" for no gate.
func through(gate string) string {
	if gate == "" {
		return ""
	}
	return " through " + gate
}

// openGate is the open human gate under key that holds bead, "" when none
// does. A read that fails returns the store's error.
func openGate(l *ledger.Ledger, bead, key string) (string, error) {
	owner, err := one(l, bead)
	if err != nil {
		return "", err
	}
	edges, err := owner.Edges()
	if err != nil {
		return "", &ledger.ReadError{ID: owner.ID, Reason: "its edges did not decode: " + err.Error()}
	}
	for _, e := range edges {
		if e.Type != ledger.EdgeBlocks {
			continue
		}
		g, err := one(l, e.ID)
		if err != nil {
			return "", err
		}
		if strings.EqualFold(g.IssueType(), "gate") && g.AwaitType() == "human" && g.AwaitID() == key && g.Status() != "closed" {
			return g.ID, nil
		}
	}
	return "", nil
}

// lookMessage is the question a look that stops the review puts to a person:
// what stopped and why, the look's question, its recommendation and reading,
// the counts, and how an answer reaches the PR.
func lookMessage(st *Step, acct Account, lk Look) string {
	run := st.Run
	why := "a fresh look found it is not converging on its current path"
	switch {
	case acct.Last:
		why = "its round is the run's last by its bound"
	case acct.Forced != "":
		why = "it is not converging, as " + acct.Forced
	}
	return fmt.Sprintf("The review of %s stopped at round %d for your answer, because %s.\n\n%s\n\nRecommendation: %s\n\n"+
		"Why the findings keep coming: %s\n\nMust-fix findings by round: %s. Each round's comment on the PR carries its "+
		"findings and rulings (review run %s).\n\nAnswer here, or comment on the PR: a run the landing order pours for a "+
		"comment filed after this gate rules it and can settle this question. Clearing this gate has the landing order "+
		"pour a fresh run.", st.PR(), st.Iteration, why, Punctuated(lk.Question), Punctuated(lk.Recommendation),
		Punctuated(lk.Reading), acct.Counts(), run.Root)
}

// lookNote is the look's entry in the notes of the bead that owns the PR.
func lookNote(st *Step, acct Account, lk Look, at time.Time) string {
	var b strings.Builder
	fmt.Fprintf(&b, "## Fresh look at round %d of review run %s (%s)\n", st.Iteration, st.Run.Root, at.UTC().Format(time.RFC3339))
	fmt.Fprintf(&b, "Must-fix findings by round: %s.\n", acct.Counts())
	if lk.Verdict == LookStop {
		fmt.Fprintf(&b, "Stopped for a person's answer%s: %s\nRecommendation: %s\n", through(lk.Gate), oneLine(lk.Question),
			oneLine(lk.Recommendation))
	} else {
		b.WriteString("Goes on to the next round.\n")
	}
	fmt.Fprintf(&b, "Reading: %s", oneLine(lk.Reading))
	if len(lk.Rules) > 0 {
		fmt.Fprintf(&b, "\nRules that changed on the target, given as the cause: %s", strings.Join(lk.Rules, ", "))
	}
	return b.String()
}
