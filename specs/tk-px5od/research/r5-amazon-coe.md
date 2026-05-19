# R5: Amazon COE and the Postmortem Tradition

## Summary

Amazon's Correction of Error (COE) is the most operationally disciplined member of a family of structured incident-review practices that includes Google's blameless postmortem, Etsy's debriefing facilitation, the US Army's After Action Review (AAR), NTSB accident investigation, and medical Morbidity & Mortality (M&M) conferences. What distinguishes COE is the combination of customer-impact-first framing, the Five Whys ladder enforced in writing, named action items with owners and due dates, and wide distribution as a learning corpus inside Amazon's narrative-memo culture. For AI-assisted development — where execution is cheap and oversight has migrated to intent and integration — COE is a strong default to borrow: when an agent does the wrong thing, the response should be a written, structured, distributed artifact that updates skills, gates, and examples, not a Slack thread that evaporates. The hard part is avoiding the known failure modes: ritual completion, "P3 forever" action items, and the linearity trap that Cook warned about in *How Complex Systems Fail*.

## The COE Practice in Detail

A COE is a written narrative, typically 3-6 pages, produced after any event that materially impacted customers or risked doing so. The canonical sections, drilled into anyone who has been on call at AWS or in a retail service team:

1. **Customer impact.** Quantified first, in customer-visible terms: how many customers, for how long, what they could not do. Dollars where applicable. Not "p99 latency rose to 800ms" but "12,400 sellers could not list ASINs for 47 minutes."
2. **Timeline.** Wall-clock events: detection, paging, mitigation steps, recovery. Includes what operators *believed* at each step, not just what was true. This is where you discover the monitoring gap — the gap between event T0 and detection Tdetect.
3. **Five Whys.** A literal ladder of questions, each "why" building on the previous answer, drilling from proximate cause to systemic cause. Done in writing, not in a meeting whiteboard. The expectation is that whys 4 and 5 surface a process or design flaw, not a person.
4. **Contributing factors.** Things that did not directly cause the event but made it worse or more likely: missing runbook, alarm not wired, dependency assumed-stateless that wasn't.
5. **Lessons learned.** Short, distributable. What anyone reading should take away.
6. **Action items.** Owner (named human), due date, ticket link, severity. Tracked to closure.

The COE is reviewed in a recurring forum — at AWS this was the weekly Operations Review and rolled up to Andy Jassy's staff meetings — where leaders read in silence, then question. The format mirrors the six-page narrative memo culture Bezos established (Bryar & Carr, *Working Backwards*, 2021, ch. 4): no bullets, no PowerPoint, full sentences, force the writer to actually think. A COE that is not well-written is sent back. The act of writing is the act of understanding.

The practice is anchored in three Leadership Principles. **Customer Obsession** demands the first section be impact, not infrastructure. **Ownership** demands a named owner per action item — never "the team will." **Dive Deep** demands the Five Whys actually go five levels, not stop at "human error." Werner Vogels has written publicly about this discipline ("10 Lessons from 10 Years of AWS," 2016); Brad Porter has described its operational mechanics in his Medium writing on Amazon's operational rigor.

## Comparison with Adjacent Traditions

**Google SRE blameless postmortem** (Beyer et al., *Site Reliability Engineering*, 2016, ch. 15) shares COE's core: timeline, root cause, action items, blameless framing. It is more explicit about psychological safety ("the postmortem is not punishment") and codifies a "postmortem of the month" reading culture. It is less customer-impact-first; impact is often expressed in SLO budget burned. It does not mandate the Five Whys; it allows freer causal analysis.

**Etsy's debriefing facilitation guide** (Allspaw, 2014; building on Allspaw's 2012 essay "Blameless PostMortems and a Just Culture") puts the weight on the *meeting*, not the document. The facilitator's job is to surface multiple operator accounts of "what did you think was happening?" — explicitly drawing on Dekker's New View of human error. The artifact is secondary; the conversation is primary. COE inverts this.

**US Army After Action Review** (FM 6-0, formerly FM 25-101) asks four questions: what was supposed to happen, what actually happened, why was there a difference, what will we do differently. Conducted immediately after the event, often standing, often in the field. Cadence and brevity are the distinctive features. AAR is to COE what a daily standup is to a quarterly review.

**NTSB accident investigation** is the heaviest sibling: months of investigation, public docket, formal probable-cause finding, recommendations binding on industry. The output is a regulatory artifact, not just an internal learning artifact. COE borrows the rigor without the legal weight.

**Medical M&M conferences** are weekly clinical case reviews. Historically protected by peer-review privilege; historically also famously prone to blame and hierarchy. The "Just Culture" reform movement (Marx, 2001; Dekker, *Just Culture*, 2007) is largely a response to M&M's failure modes.

**What's distinctive about COE**: it is *written first* (forcing thought), *customer-framed* (forcing relevance), *action-tracked* (forcing follow-through), and *widely circulated* (forcing learning beyond the team). Most other traditions do one or two of these well; COE insists on all four.

## What COE Gets Right (and Wrong)

**Right: customer-impact-first framing.** The first sentence of a COE is a customer sentence. This single rule prevents 80% of the drift toward "interesting engineering story, no business consequence" that other postmortem traditions tolerate. It also forces the writer to know who the customer actually is — a non-trivial discipline for platform teams.

**Right: action items with named owners and tracked closure.** Most postmortem cultures generate action items; few track them. Amazon's weekly Operations Reviews include rolling a list of open COE actions, with owners present. "P3 forever" exists but is visibly embarrassing.

**Right: wide distribution.** A COE is readable by anyone in the org. New hires read old COEs as onboarding. This builds an institutional memory that survives reorgs and attrition — a learning corpus, not an incident database.

**Right: writing as forcing function.** The narrative-memo rule (Bezos, 2017 shareholder letter; Bryar & Carr ch. 4) means a half-understood incident produces a half-coherent document, which is visibly bad. You cannot bullet-point your way out of confusion.

**Wrong/limited: the Five Whys can be dangerously linear.** Cook's *How Complex Systems Fail* (1998/2002) argues that complex-system failures are emergent from many small contributing factors, none of which is "the" cause. A literal Five Whys ladder can produce a single causal chain that feels satisfying but obscures the actual texture of the failure. Better COEs treat the Five Whys as one lens among several and lean on the contributing-factors section for the wider picture.

**Wrong/limited: blame leakage.** "Blameless" is the stated norm. In practice, when a named on-call engineer appears in the timeline making a wrong call, social blame attaches even if no formal blame does. Dekker's *Field Guide to Understanding 'Human Error'* (2014) calls this the persistence of the Old View under New View vocabulary. Strong COE cultures actively coach reviewers to ask "what made this the reasonable action at the time?" rather than "why did they do that?"

## AI-Dev Applications

The AI-agent COE answers: an agent did the wrong thing — wrong gate skipped, wrong escalation, missing context, hallucinated API, destructive action, silent failure. The trigger is not "production incident" but "agent produced an output that a reasonable reviewer would not have approved, and a human noticed (or should have)."

**Mandatory structure**, COE-derived:

1. **Intent impact.** What did the human ask for? What did the agent deliver? What is the gap, in the human's terms — not in tokens or tool calls?
2. **Trace timeline.** Prompts, tool calls, tool results, model decisions, gate evaluations. Include the agent's stated reasoning at each step (where available) — the analogue of "what the operator believed."
3. **Five Whys.** Why did the agent do X? Because the prompt said Y. Why did the prompt say Y? Because the skill template assumed Z. Why did the template assume Z? ... drilling toward a skill, gate, or example fix.
4. **Contributing factors.** Missing skill, missing example in the skill, weak gate, ambiguous instruction, stale context, tool description that misled.
5. **Lessons learned.** One paragraph another team could read.
6. **Action items.** Skill update (with PR link), new gate (with config diff), new few-shot example (with the canonical case), evaluation added to the regression suite. Owner: a named human, not "the agent team."

**Who writes it?** The human in the loop who caught it, with the agent drafting the timeline section from its own trace. The agent is a witness, not the author. Authorship by a human is the discipline.

**Cadence.** Two layers, mirroring AAR + COE: a per-event lightweight write-up (the AAR-style "what was supposed to happen, what happened, what we'll change") within a day; a periodic sweep (weekly or biweekly) reading the lightweight write-ups in batch and producing one or two full COEs on the patterns that recur. This avoids the 1000-COEs-nobody-reads scaling problem while preserving the ground-truth record.

**Feedback into agent behavior.** The action items should land as concrete artifacts: updated skill markdown, new gate in the harness, new example in the few-shot bank, new entry in an "anti-patterns" doc that gets included in the system prompt. A COE without a merged PR is incomplete. The Amazon equivalent of "ticket link required" is "commit hash required."

**Avoiding ritual completion.** Three guards: (a) a senior reviewer reads every COE and asks one hard question in writing; (b) a quarterly meta-review reads the last quarter's COEs looking for repeats — repeats are the real signal; (c) action items have a closure SLA and a visible aging dashboard.

## Counter-Arguments and Failure Modes

**Ritual completion vs. real learning.** The deepest failure mode. A team writes COEs because the process requires it; nobody changes behavior. Symptom: action items closed by "we discussed this" or "added to backlog." Counter: require a code/config diff for closure, and read closed action items in the meta-review.

**"P3 forever."** Action items get filed at a priority that guarantees they will never be done. AWS has historically fought this by elevating COE actions automatically after N weeks unaddressed, and by including aging in the operations review. Without that mechanism, the action-item field becomes theater.

**Blame leakage despite blameless framing.** Dekker's distinction between Old View ("bad apples") and New View ("the system made this the rational action") requires active facilitation. A blameless template with a blameful reviewer produces blameful COEs. For agent COEs the temptation is to blame the model — "the model hallucinated" — which is the AI equivalent of "human error": a stop-thinking phrase. Push past it.

**Cargo-culting without culture.** Adopting the COE template without the weekly review forum, the senior-reader discipline, the writing standard, and the wide distribution produces a Word doc that nobody reads. Bryar & Carr are explicit that the narrative-memo culture only works because the room actually reads in silence and actually questions.

**Scaling problems.** A large org generates more COEs than anyone can read. Amazon partly solves this with rollups and themed reviews; many teams do not. For agent COEs, where event volume can be very high, the AAR/COE two-layer split is essential.

**Five Whys as linear.** Cook's *How Complex Systems Fail* point 3: "catastrophe requires multiple failures — single point failures are not enough." A linear ladder by construction tells a single-cause story. Treat the Five Whys as a starting heuristic, not the analysis. Pair with a contributing-factors enumeration and, for serious events, a STAMP- or CAST-style systems analysis (Leveson).

**The agent-specific risk: the COE corpus becomes training data for the next failure.** If past COEs are included in agent context, the agent may learn to avoid the *specific* surface forms of past failures while missing the underlying pattern — the equivalent of teaching to the test. Periodic adversarial evaluation against held-out failure modes is the counter.

## References

- Allspaw, J. (2012). "Blameless PostMortems and a Just Culture." Code as Craft (Etsy engineering blog).
- Allspaw, J. (2014). *Etsy Debriefing Facilitation Guide for Blameless Postmortems*. Etsy.
- Beyer, B., Jones, C., Petoff, J., & Murphy, N. R. (Eds.). (2016). *Site Reliability Engineering: How Google Runs Production Systems*. O'Reilly. Chapter 15: "Postmortem Culture: Learning from Failure."
- Bezos, J. (1997-2020). Amazon shareholder letters. Particularly 2017 ("six-page narratively structured memos") and 2015 ("Type 1 vs. Type 2 decisions").
- Bryar, C. & Carr, B. (2021). *Working Backwards: Insights, Stories, and Secrets from Inside Amazon*. St. Martin's Press. Chapter 4 on the narrative memo; chapters on operational rigor and the WBR.
- Cook, R. I. (1998, rev. 2002). "How Complex Systems Fail." Cognitive Technologies Laboratory, University of Chicago.
- Dekker, S. (2007). *Just Culture: Balancing Safety and Accountability*. Ashgate.
- Dekker, S. (2014). *The Field Guide to Understanding 'Human Error'* (3rd ed.). Ashgate.
- Leveson, N. (2011). *Engineering a Safer World: Systems Thinking Applied to Safety*. MIT Press. (STAMP/CAST methodology.)
- Marx, D. (2001). "Patient Safety and the 'Just Culture': A Primer for Health Care Executives." Columbia University.
- Porter, B. Public writing on Amazon operational practices (Medium, various; see also AWS re:Invent talks on operational excellence).
- US Department of the Army. (1993, updated). *FM 25-101 / FM 6-0: Training the Force / Commander and Staff Organization and Operations* — including the After Action Review methodology. See also TC 25-20, *A Leader's Guide to After-Action Reviews*.
- Vogels, W. (2016). "10 Lessons from 10 Years of Amazon Web Services." All Things Distributed. See also Vogels' writing on "you build it, you run it" and operational ownership.
- NTSB. *Aviation Investigation Manual* and published accident reports (e.g., AAR-10/03, US Airways 1549) as exemplars of the regulatory-grade investigation tradition.

