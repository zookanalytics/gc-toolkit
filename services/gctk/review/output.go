package review

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"regexp"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// A step of a review run writes its output once, before it closes, and Gas
// City keeps it as the step's gc.output_json. The write is native. What the
// review domain adds is the check before it: an output the pass rule would
// read as not written, or one that names another iteration, another head or a
// finding no lane raised, would spend an attempt on a step's slip, and a
// triage output whose checks are not an array stops the run, because its
// fan-out cannot read it. So the step's text runs gctk review output, which
// reads what the step wrote and prints it as the store keeps it, or refuses it
// with the reason, and the step writes what it printed.
//
// A correctness lane's approve carries the guidance-edit guard. A change that
// edits its own review guidance, review-checks.toml or a docs/review-*.md, was
// reviewed under that edit, since every reader takes the guidance at the commit
// it judges, so its approve names the edit to the person who approves the
// merge: it is refused until needs_you says what the edit changes about the
// review. Paths that cannot be listed leave the edit unchecked, and needs_you
// then says so, so the approver reads the diff for one.

// Shadow is what a shadow run's round would have written outside the run: the
// head's comment it posted nowhere, and each push, gate and bead it made none
// of, one line each.
type Shadow struct {
	Comment string   `json:"comment"`
	Writes  []string `json:"writes,omitempty"`
}

// OutputRequest is one step's output to check: the step's bead, the text the
// step wrote, the checkouts that can read the reviewed commit, for a shadow
// run's round each write it made none of, and the reader of the withdrawal
// filed on a bead for a head, open or closed, "" when none is, which the pr
// domain answers (pr.WithdrawalFor).
type OutputRequest struct {
	Step       string
	Raw        []byte
	Repos      []string
	Writes     []string
	Withdrawal func(bead, head string) (string, error)
}

// Refused is the error of an output the step must write again: why.
type Refused struct{ Why string }

func (e *Refused) Error() string { return e.Why }

func refuse(format string, args ...any) error { return &Refused{Why: fmt.Sprintf(format, args...)} }

// Output checks the output a step wrote and returns it as the store keeps it:
// compact JSON in the shape the step writes, naming the iteration it runs in.
// A read that fails returns the store's error.
func Output(l *ledger.Ledger, req OutputRequest) ([]byte, error) {
	st, err := ReadStep(l, req.Step)
	if err != nil {
		return nil, err
	}
	if st.Output == "" {
		return nil, refuse("%s (%s) is not a step that writes an output: triage, a lane and rule-and-repair do", st.ID, st.Ref)
	}
	var head struct {
		Review    *string `json:"review"`
		Iteration int     `json:"iteration"`
	}
	if err := json.Unmarshal(req.Raw, &head); err != nil {
		return nil, refuse("the output is not one JSON object: %v", err)
	}
	if head.Review == nil || *head.Review != st.Output {
		got := "none"
		if head.Review != nil {
			got = fmt.Sprintf("%q", *head.Review)
		}
		return nil, refuse("%s writes a %s output, so its review field reads %q, not %s", st.ID, st.Output, st.Output, got)
	}
	if head.Iteration != 0 && head.Iteration != st.Iteration {
		return nil, refuse("%s runs in iteration %d, and the output names iteration %d", st.ID, st.Iteration, head.Iteration)
	}
	run, n := st.Run, st.Iteration
	var v any
	switch st.Output {
	case OutputTriage:
		v, err = triageOutput(run, n, req)
	case OutputLane:
		v, err = laneOutput(run, n, req)
	case OutputRepair:
		v, err = repairOutput(l, run, n, req)
	}
	if err != nil {
		return nil, err
	}
	var b bytes.Buffer
	enc := json.NewEncoder(&b)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		return nil, err
	}
	return bytes.TrimRight(b.Bytes(), "\n"), nil
}

// decode reads raw into v in the shape, refusing a field the shape does not
// name, as the run's reader does.
func decode(raw []byte, v any, what string) error {
	if err := strict(string(raw), v); err != nil {
		return refuse("the %s output does not read in its shape (services/gctk/review/run.go): %v", what, err)
	}
	return nil
}

// triageOutput checks triage's output. A head ruled material keeps the
// approvals given before it only until the landing order carries out the
// withdrawal triage files for it, so the output stands only once that
// withdrawal is on the bead that owns the PR, open or closed. A shadow run
// files none, so its ruling stands alone.
func triageOutput(run *Run, n int, req OutputRequest) (*Triage, error) {
	var t Triage
	if err := decode(req.Raw, &t, OutputTriage); err != nil {
		return nil, err
	}
	t.Iteration = n
	if want := run.HeadOf(n); t.Head != want {
		return nil, refuse("iteration %d judges %s, and the output names the head %q", n, want, t.Head)
	}
	seen := map[string]bool{}
	for _, p := range t.Checks {
		switch {
		case !ValidName(p.Check):
			return nil, refuse("a pick names the check %q, which is not a check's name", p.Check)
		case seen[strings.ToLower(p.Check)]:
			return nil, refuse("the check %s is picked twice", p.Check)
		case p.Head != t.Head:
			return nil, refuse("the %s pick names the head %q, not the head triage judged, %s", p.Check, p.Head, t.Head)
		}
		seen[strings.ToLower(p.Check)] = true
	}
	if t.Checks == nil {
		t.Checks = []Pick{}
	}
	if t.Material && !run.Shadow {
		if req.Withdrawal == nil {
			return nil, errors.New("no reader of withdrawals was given, so a material ruling cannot be checked")
		}
		id, err := req.Withdrawal(run.PRBead, t.Head)
		if err != nil {
			return nil, err
		}
		if id == "" {
			return nil, refuse("triage rules %s material, and no withdrawal for it is filed on %s: withdraw the approvals "+
				"given before it (review-run.sh withdraw), then write the output", t.Head, run.PRBead)
		}
	}
	return &t, nil
}

func laneOutput(run *Run, n int, req OutputRequest) (*Lane, error) {
	var ln Lane
	if err := decode(req.Raw, &ln, OutputLane); err != nil {
		return nil, err
	}
	ln.Iteration = n
	it := run.Iterations[n]
	if it == nil || it.Triage == nil {
		return nil, refuse("triage has written nothing in iteration %d, so no lane runs there", n)
	}
	if !slices.ContainsFunc(it.Triage.Checks, func(p Pick) bool { return strings.EqualFold(p.Check, ln.Check) }) {
		return nil, refuse("triage did not pick %q in iteration %d", ln.Check, n)
	}
	if ln.Head != it.Triage.Head {
		return nil, refuse("the %s lane of iteration %d reviews %s, and the output names the head %q", ln.Check, n, it.Triage.Head, ln.Head)
	}
	if ln.Verdict != VerdictApprove && ln.Verdict != VerdictRequestChanges {
		return nil, refuse("the verdict reads %q, not %s or %s", ln.Verdict, VerdictApprove, VerdictRequestChanges)
	}
	ids := map[string]bool{}
	blocking := 0
	for i := range ln.Findings {
		f := &ln.Findings[i]
		switch {
		case strings.TrimSpace(f.ID) == "":
			return nil, refuse("a finding names no id, so no ruling can answer it")
		case ids[f.ID]:
			return nil, refuse("the finding id %s is used twice", f.ID)
		case strings.TrimSpace(f.Locus) == "" || strings.TrimSpace(f.Message) == "":
			return nil, refuse("finding %s needs its locus and its message", f.ID)
		}
		ids[f.ID] = true
		if why := contract(f, ln.Check); why != "" {
			return nil, refuse("finding %s: %s", f.ID, why)
		}
		if f.Severity != "P2" {
			blocking++
		}
	}
	switch {
	case ln.Verdict == VerdictApprove && blocking > 0:
		return nil, refuse("an approve carries no blocking finding, and this set carries %d: a P0, a P1 or a finding with no grade", blocking)
	case ln.Verdict == VerdictRequestChanges && blocking == 0:
		return nil, refuse("request-changes needs a blocking finding, and this set carries none; when only P2s remain, the lane approves")
	}
	if ln.Findings == nil {
		ln.Findings = []Finding{}
	}
	if why := visual(&ln); why != "" {
		return nil, refuse("%s", why)
	}
	if strings.EqualFold(ln.Check, "correctness") && ln.Verdict == VerdictApprove && strings.TrimSpace(ln.NeedsYou) == "" {
		edits, err := GuidanceEdits(IndexSources{Repos: req.Repos}, run.Target, ln.Head)
		switch {
		case err != nil:
			ln.NeedsYou = fmt.Sprintf("The paths this change touches could not be listed (%v), so whether it edits its own review "+
				"guidance (review-checks.toml, docs/review-*.md) is unchecked; read its diff for such an edit before you approve the merge.", err)
		case len(edits) > 0:
			return nil, refuse("this change edits its own review guidance (%s), and its review ran under that edit, since every "+
				"reader takes the guidance at the commit it judges. A correctness approve names the edit to the person who approves "+
				"the merge: write needs_you saying what the edit changes about the review", strings.Join(edits, ", "))
		}
	}
	return &ln, nil
}

func repairOutput(l *ledger.Ledger, run *Run, n int, req OutputRequest) (*Repair, error) {
	var rp Repair
	if err := decode(req.Raw, &rp, OutputRepair); err != nil {
		return nil, err
	}
	rp.Iteration = n
	it := run.Iterations[n]
	if it == nil || it.Triage == nil {
		return nil, refuse("triage has written nothing in iteration %d, so there is nothing to rule", n)
	}
	if rp.Head != it.Triage.Head {
		return nil, refuse("iteration %d judged %s, and the output names the head %q", n, it.Triage.Head, rp.Head)
	}
	asks, err := AsksOn(l, run.PRBead)
	if err != nil {
		return nil, err
	}
	declined := earlierDeclines(run, n)
	subjects := map[string]bool{}
	for _, r := range rp.Rulings {
		if err := checkRuling(r, it, asks, declined, run.Shadow); err != nil {
			return nil, err
		}
		if subjects[strings.ToLower(r.Subject())] {
			return nil, refuse("%s is ruled twice", r.Subject())
		}
		subjects[strings.ToLower(r.Subject())] = true
	}
	for _, ln := range it.Lanes {
		for _, f := range ln.Findings {
			if !subjects[strings.ToLower(Ruling{Check: ln.Check, Finding: f.ID}.Subject())] {
				return nil, refuse("%s finding %s is not ruled", ln.Check, f.ID)
			}
		}
	}
	for _, a := range asks {
		if a.Takeable() && !subjects[strings.ToLower(Ruling{Ask: a.ID}.Subject())] {
			return nil, refuse("ask %s is open and nothing holds it, so the round rules it", a.ID)
		}
	}
	switch {
	case rp.Pushed != "" && run.Shadow:
		return nil, refuse("a shadow run pushes nothing, and the output names the push %s", rp.Pushed)
	case rp.Pushed != "" && !git.IsObjectID(rp.Pushed):
		return nil, refuse("the push %q is not a full object name", rp.Pushed)
	}
	if rp.Rulings == nil {
		rp.Rulings = []Ruling{}
	}
	switch {
	case run.Shadow:
		rp.Shadow = &Shadow{Writes: req.Writes}
		draft := *run
		draft.Iterations = maps.Clone(run.Iterations)
		withRepair := *it
		withRepair.Repair = &rp
		draft.Iterations[n] = &withRepair
		rp.Shadow.Comment = Comment(&draft, n, asks)
	case rp.Shadow != nil:
		return nil, refuse("only a shadow run's round writes what it would have written")
	}
	return &rp, nil
}

// contract is why a lane's finding breaks the finding contract, "" when it
// keeps it, with its grade written upper-case: a grade is P0, P1 or P2, and
// every correctness finding carries one; a graded finding names its category
// and its failure scenario; a P0 or a P1 carries a verification that opens
// CONFIRMED or PLAUSIBLE and then the evidence; and a candidate whose
// verification is REFUTED is no finding at any grade. A P2 does not block, and
// a finding with no grade does.
func contract(f *Finding, check string) string {
	f.Severity = strings.ToUpper(strings.TrimSpace(f.Severity))
	verification := strings.TrimSpace(f.Verification)
	switch g := f.Severity; {
	case g != "" && g != "P0" && g != "P1" && g != "P2":
		return fmt.Sprintf("its severity reads %q, not P0, P1 or P2", g)
	case g == "" && strings.EqualFold(check, "correctness"):
		return "it has no severity, and every correctness finding is graded"
	case g != "" && (strings.TrimSpace(f.Category) == "" || strings.TrimSpace(f.FailureScenario) == ""):
		return "a graded finding names its category and its failure_scenario"
	case refutedVerification.MatchString(verification):
		return "its verification is REFUTED, and a refuted candidate is not a finding: leave it out, and keep its refutation in the trail"
	case (g == "P0" || g == "P1") && !confirmedVerification.MatchString(verification):
		return fmt.Sprintf("a %s carries a verification that opens CONFIRMED or PLAUSIBLE and then the evidence", g)
	}
	return ""
}

// visual is why a lane's visual decision does not stand, "" when it does,
// with each modality written lower-case. The demo check records its decision
// on every verdict: none when the change needs no visual, which leaves the
// check nothing to block on and so goes with an approve only, else the
// modality delivered. A fallback names the modality that fits and could not be
// produced here, screenshot or video, which costs more than the one delivered:
// repo-artifact, then screenshot, then video. No other check records one.
func visual(ln *Lane) string {
	ln.Visual = strings.ToLower(strings.TrimSpace(ln.Visual))
	ln.VisualFallbackFrom = strings.ToLower(strings.TrimSpace(ln.VisualFallbackFrom))
	if !strings.EqualFold(ln.Check, "demo") {
		if ln.Visual != "" || ln.VisualFallbackFrom != "" {
			return fmt.Sprintf("only the demo check records a visual decision, and this lane is %s", ln.Check)
		}
		return ""
	}
	cost := map[string]int{"repo-artifact": 1, "screenshot": 2, "video": 3}
	switch {
	case ln.Visual == "":
		return "the demo check records its visual decision on every verdict: none, repo-artifact, screenshot or video"
	case ln.Visual != "none" && cost[ln.Visual] == 0:
		return fmt.Sprintf("the visual reads %q, not none, repo-artifact, screenshot or video", ln.Visual)
	case ln.Visual == "none" && ln.Verdict != VerdictApprove:
		return "a visual of none says the change needs no visual, which leaves the demo check nothing to block on, so it goes with an approve only"
	case ln.VisualFallbackFrom == "":
		return ""
	case ln.VisualFallbackFrom != "screenshot" && ln.VisualFallbackFrom != "video":
		return fmt.Sprintf("the visual fallback reads %q, not screenshot or video, the modality that fits", ln.VisualFallbackFrom)
	case ln.Visual == "none":
		return "a fallback names the modality a delivered visual stands in for, and a visual of none delivers none"
	case cost[ln.Visual] >= cost[ln.VisualFallbackFrom]:
		return fmt.Sprintf("a fallback is cheaper than the modality it stands in for, so %s cannot be a fallback from %s", ln.Visual, ln.VisualFallbackFrom)
	}
	return ""
}

var (
	refutedVerification   = regexp.MustCompile(`(?i)^REFUTED([^[:alnum:]]|$)`)
	confirmedVerification = regexp.MustCompile(`(?i)^(CONFIRMED|PLAUSIBLE)[^[:alnum:]]+[^[:space:]]`)
)

// checkRuling is why one ruling of iteration it's round does not stand: a
// subject no lane raised and no ask the round can take, a ruling outside the
// set, a must-fix with no fixing commit, a commit on a ruling that changes no
// code, a question with no gate, and a fix for an ask an earlier round of the
// run declined, which a later ruling of its own overrules only through an ask
// that carries it.
func checkRuling(r Ruling, it *Iteration, asks []Ask, declined map[string]string, shadow bool) error {
	switch {
	case r.Ask != "" && (r.Check != "" || r.Finding != ""):
		return refuse("a ruling names the ask %s and a lane's finding at once", r.Ask)
	case r.Ask != "":
		if !slices.ContainsFunc(asks, func(a Ask) bool { return a.ID == r.Ask && a.Takeable() }) {
			return refuse("%s is not an ask the round can take: open on the bead, with nothing holding it", r.Subject())
		}
	case r.Check == "" || r.Finding == "":
		return refuse("a ruling names neither an ask nor a lane's check and finding")
	default:
		ln, ok := lane(it, r.Check)
		if !ok || !slices.ContainsFunc(ln.Findings, func(f Finding) bool { return f.ID == r.Finding }) {
			return refuse("no lane of this iteration raised %s", r.Subject())
		}
	}
	if !slices.Contains(rulings, r.Ruling) {
		return refuse("%s is ruled %q, which is not a ruling (%s)", r.Subject(), r.Ruling, strings.Join(rulings, ", "))
	}
	switch {
	case r.Ruling == RulingMustFix && shadow && r.Commit != "":
		return refuse("a shadow run fixes nothing, and %s names the commit %s", r.Subject(), r.Commit)
	case r.Ruling == RulingMustFix && !shadow && !git.IsObjectID(r.Commit):
		return refuse("%s is ruled must-fix and names no commit that fixes it (a full object name)", r.Subject())
	case r.Ruling != RulingMustFix && r.Commit != "":
		return refuse("%s is ruled %s, which changes no code, and names the commit %s", r.Subject(), r.Ruling, r.Commit)
	case r.Ruling == RulingQuestion && !shadow && strings.TrimSpace(r.Gate) == "":
		return refuse("%s is put to a person and names no gate", r.Subject())
	case r.Ruling != RulingQuestion && r.Gate != "":
		return refuse("%s is ruled %s and names the gate %s, which only a question goes to", r.Subject(), r.Ruling, r.Gate)
	case strings.TrimSpace(r.Reason) == "":
		return refuse("%s is ruled %s with no reason", r.Subject(), r.Ruling)
	}
	if was, ok := declined[r.Ask]; ok && r.Ask != "" && r.Ruling == RulingMustFix {
		return refuse("an earlier round of this run ruled %s %s, so no repair changes code for it; a ruling that overrules that "+
			"comes as an ask of its own, which the round rules must-fix", r.Subject(), was)
	}
	return nil
}

// earlierDeclines is each ask an earlier round of the run ruled declined or
// deferred, with that ruling.
func earlierDeclines(run *Run, n int) map[string]string {
	out := map[string]string{}
	for _, m := range slices.Sorted(maps.Keys(run.Iterations)) {
		rp := run.Iterations[m].Repair
		if m >= n || rp == nil {
			continue
		}
		for _, r := range rp.Rulings {
			if r.Ask != "" && (r.Ruling == RulingDeclined || r.Ruling == RulingDeferred) {
				out[r.Ask] = r.Ruling
			}
		}
	}
	return out
}
