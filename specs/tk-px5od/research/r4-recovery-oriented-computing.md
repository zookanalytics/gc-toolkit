# R4: Recovery-Oriented Computing and Cheap-Restart Patterns for AI-Assisted Development

## Summary

Recovery-Oriented Computing (ROC), launched by Patterson, Fox, Brewer, and collaborators at Berkeley and Stanford in 2002, inverted the dominant MTBF-maximization framing of dependability: since hardware, software, and humans all fail, optimize for **mean time to recovery** instead. The key insight — *if recovery is cheap, prefer to recover rather than prevent* — propagated through cattle-not-pets infrastructure, Kubernetes pod restarts, serverless cold starts, blue-green deploys, feature flags, Git, and the entire SRE/chaos-engineering canon. AI-assisted development sits squarely in this lineage: when an agent run costs cents and minutes, the right default for a confused or wedged agent is to discard the attempt and restart from a known-good prompt + repo state, the way Kubernetes restarts a pod. The Gas City Pack should borrow ROC's design discipline (crash-only modules, idempotent operations, fault injection, undo as a first-class affordance) — while taking the counter-arguments seriously: irreversible side effects, human attention as a non-restartable resource, and coordination costs that grow superlinearly with restart frequency.

## ROC Principles

The founding document is Patterson et al., *"Recovery-Oriented Computing (ROC): Motivation, Definition, Techniques, and Case Studies"* (UC Berkeley CS Tech Report UCB//CSD-02-1175, March 2002), with the popularization in Fox & Patterson, *"When Does Fast Recovery Trump High Reliability?"* (IEEE Computer, 2002 / 2003). The thesis: availability is `MTTF / (MTTF + MTTR)`, and Industry has hit diminishing returns on driving MTTF up, so attack the denominator. Concretely:

- **Recovery as a first-class design goal.** Treat the recovery path as the common case, not an exception handler. Test it as often as the happy path.
- **Microreboots.** Candea, Kawamoto, Fujiki, Friedman & Fox, *"Microreboot — A Technique for Cheap Recovery"* (OSDI 2004), showed that rebooting fine-grained components (EJBs in JBoss/JAGR) recovered 78% of faults in <1s, vs. tens of seconds for a full process restart. The lesson is granularity: make the smallest restartable unit small, and restart eagerly.
- **Crash-only software.** Candea & Fox, *"Crash-Only Software"* (HotOS IX, 2003), argue that if the only way to stop is to crash, then the recovery code is the *only* startup code — so it gets exercised constantly and stays correct. State must live in dedicated stores; components must be idempotent and retryable.
- **Three Rs: Rewind, Repair, Replay.** Brown & Patterson, *"Undo for Operators: Building an Undoable E-mail Store"* (USENIX ATC 2003), and Aaron Brown's thesis, *"A Recovery-Oriented Approach to Dependable Services: Repairing Past Errors with System-Wide Undo"* (UC Berkeley, December 2003), built an IMAP proxy that logged every verb, let an operator rewind state to a checkpoint, repair (apply a config change, install a patch, delete a virus), then replay the log forward — squashing or transforming events as needed.
- **Fault injection / FIT.** ROC made fault injection (FIT — Fault Injection Tooling) a continuous practice, not a one-off qualification step, foreshadowing chaos engineering by half a decade.
- **Undo for sysadmins.** Brown & Patterson, *"Rewind, Repair, Replay: Three Rs to Dependability"* (SIGOPS European Workshop, 2002), framed administrator error as the dominant failure mode and undo as the response.

## Spread to Industry

ROC's vocabulary did not always travel under its own name, but its design moves are everywhere:

- **Cattle, not pets.** Bias Parsons coined the phrase around 2012; it is a direct restatement of crash-only design at the host level. Pets are nursed back to health (high MTTF); cattle are shot and replaced (low MTTR).
- **Immutable infrastructure.** Chad Fowler's 2013 *"Trash Your Servers and Burn Your Code"* and the Packer/Terraform/AMI workflow operationalize "rebuild instead of repair." A bad host is terminated; the autoscaling group brings a fresh one up from a known image.
- **Kubernetes.** The pod is the microreboot unit; liveness probes are the fault detector; the ReplicaSet is the recovery controller. `kubectl delete pod` is a deliberate, sanctioned restart. The control loop *is* the ROC philosophy mechanized.
- **Serverless / FaaS.** Lambda functions are crash-only by construction: no in-process state survives, every invocation is a fresh interpreter, retries are first-class.
- **Feature flags as undo.** LaunchDarkly, Statsig, and the patterns described in Pete Hodgson's *"Feature Toggles"* (martinfowler.com, 2017) make a deploy reversible without a redeploy — the "rewind" of the three Rs.
- **Blue-green and canary deploys.** Humble & Farley, *Continuous Delivery* (2010), and Sato's blue-green write-up codify deploys as cheap, atomic switches with instant rollback.
- **Expand-contract (parallel-change) migrations.** Danilo Sato's pattern lets schema and API changes be undone at every step until the contract phase commits.
- **Git as undo-for-source.** `git reset`, `git revert`, `git reflog`, and the rebase workflow give developers per-keystroke rewind. The branch is the checkpoint; the commit is the log entry; merge is replay.

## SRE / DevOps Adaptations

Google SRE generalized ROC into a management practice. Ben Treynor Sloss's framing in Beyer, Jones, Petoff & Murphy, eds., *Site Reliability Engineering* (O'Reilly, 2016), introduces:

- **Error budgets.** If 99.9% availability is the SLO, you have 0.1% to spend on risk — including deliberate restarts, deploys, and chaos. Error budgets monetize cheap recovery: you can afford to fail because you've explicitly priced it in.
- **Blameless postmortems.** Allspaw, *"Blameless PostMortems and a Just Culture"* (Etsy Code as Craft, 2012), and Dekker's *Field Guide to Understanding Human Error* shift the focus from "who caused this" to "what made the recovery slow." This is ROC for the sociotechnical system.
- **Incident command.** Borrowed from FEMA's ICS, codified at PagerDuty and Google. The incident commander's job is to choose between rollback, roll-forward, and mitigation — i.e., to wield the recovery toolkit.
- **Runbook automation.** Every manual recovery step is a candidate for codification; the runbook *is* the replay log of the three Rs.
- **GameDays and chaos engineering.** Jesse Robbins's GameDays at Amazon (mid-2000s), Netflix's Chaos Monkey (2011) and Simian Army, and Rosenthal & Jones, *Chaos Engineering: System Resiliency in Practice* (O'Reilly, 2020), are continuous fault injection in production — the direct descendant of ROC's FIT. Gremlin productized this. The Principles of Chaos (principlesofchaos.org) explicitly cite "build confidence in the system's capability to withstand turbulent conditions."
- **Release engineering.** Nygard, *Release It!* (Pragmatic, 2007; 2nd ed. 2018), gave the field its stability patterns: bulkheads, circuit breakers, timeouts, steady state — all assume that components will fail and the system must absorb and recover.

## AI-Dev Applications

When agent execution is cheap, the ROC playbook ports almost line-for-line:

- **Microreboot the agent, not the human.** If a coding agent is wedged on a confused subgoal, the cheapest move is `Ctrl-C`, discard the chat, restart from the same prompt against the same Git SHA. Treat the chat session as a pod: stateless, restartable, replaceable. The Gas City Pack should make this the default reflex, not a last resort.
- **Crash-only agent design.** Agents should externalize all state (scratchpad files in the repo, structured plan documents, TODO lists checked into a branch) so a fresh agent can pick up where the dead one left off. No durable in-context memory; the *artifact* — PR draft, design doc, COE/postmortem, scratch branch — *is* the recovery state. This mirrors Candea & Fox's separation of "data stores" from "components."
- **Cheap-redo.** Re-running an agent with a slightly tweaked prompt is the AI equivalent of a microreboot. Branch the conversation; keep the n-best result. Multi-sample with rerank is just FIT for prompts.
- **Cheap-undo for deployed change.** The AI version of the undo button is: every agent-authored change ships behind a feature flag, lands as a revertable squash commit, and is gated by a canary. `git revert <sha> && deploy` is the rewind; the flag flip is the rewind-without-deploy. Aaron Brown's three-Rs map cleanly: rewind = revert/flag-off, repair = next agent run with the failure context appended to the prompt, replay = re-deploy with the fix.
- **Recovery as first-class in agent harness design.** Treat "agent gave up / looped / hallucinated" as the common case. Build the harness so the recovery path (escalate to human, restart with reduced scope, fall back to deterministic tool) is exercised every run.
- **Fault injection for prompts.** The chaos-engineering analogue is adversarial prompts, deliberately corrupted tool outputs, and randomized context truncation, run as part of CI for agent workflows.
- **Error budgets for autonomy.** Allocate a fraction of agent runs to allowed-to-fail experiments; when the budget is spent, tighten oversight. This gives a principled answer to "how autonomous should this agent be today?"

The Gas City Pack thesis — oversight migrates to intent (front) and integration (back) — fits this exactly: cheap-restart frees humans from the middle of the loop, but the *front* (was the goal right?) and the *back* (did the artifact land safely, and can we undo it?) are precisely the two ROC affordances that need human judgment.

## Counter-Arguments and Limits

The steel-man critique:

- **Irreversible side effects.** Sending email, charging a card, posting to a public channel, dropping a production table, opening a port to the internet, paying out a bounty — none are undoable in software. ROC was always honest about this; Brown's undoable email service required a *proxy* layer that delayed external SMTP delivery to keep undo possible. AI agents that act on the real world need explicit reversibility budgets and quarantine zones, not just optimistic restart.
- **Coordination failures.** A microreboot in a distributed system can be cheap locally but expensive globally — cache stampedes, retry storms, thundering herds. Nygard's *Release It!* documents how local cheap-restart causes cascade failures. AI multi-agent systems will have analogues: a restarted agent re-doing tool calls can blow rate limits, double-charge APIs, or duplicate PRs.
- **Latency-sensitive paths.** Cold starts in serverless are the canonical failure of pure crash-only thinking. For agents, "just re-run from scratch" can mean re-loading 200K tokens of context — minutes of latency that breaks the human's flow even when the dollar cost is low.
- **Human attention is not restartable.** This is the most important caveat for the Gas City Pack. The human reviewing an agent's third restart is not the same human as the first time; trust erodes, vigilance drops, and review quality decays. Cheap restarts can launder a real problem (a wrong spec) into a series of plausible-but-wrong attempts that exhaust the reviewer. Token cost is cheap; reviewer attention is the actual scarce resource. ROC assumed the operator was a *system*, not a person being asked to read four PRs in a row.
- **Side effects on attention and queue depth.** Each restart also produces artifacts (chats, branches, draft PRs) that compete for shelf space in human working memory and in the team's review queue. Blast radius for an AI restart includes notification noise, CI minutes, and reviewer load — none captured by "the agent run cost $0.40."
- **State that lives in the model.** Crash-only requires externalizing state. But an agent's "understanding" of a problem mid-conversation is a real asset; throwing it away and restarting can be a regression, not a recovery. The discipline must be: externalize *enough* state (plan docs, decisions log) that the restart is genuinely cheap, not nominally cheap.
- **The "just restart" anti-pattern.** Operators famously over-use reboots to mask deeper issues. AI engineering will see the same: re-rolling the dice on a flaky agent until it produces a plausible diff, rather than fixing the prompt, the tools, or the spec. Cheap restart without root-cause discipline is technical debt with a friendly UX.

The synthesis: borrow ROC's *design moves* (externalized state, idempotency, fault injection, undo as a primitive, recovery on the happy path) but keep its *honesty* about what cannot be undone — and add a new constraint ROC didn't face, that the human in the loop has finite, non-restartable attention.

## References

**Foundational ROC**

- Patterson, D., Brown, A., Broadwell, P., Candea, G., Chen, M., Cutler, J., Enriquez, P., Fox, A., Kiciman, E., Merzbacher, M., Oppenheimer, D., Sastry, N., Tetzlaff, W., Traupman, J., Treuhaft, N. *"Recovery-Oriented Computing (ROC): Motivation, Definition, Techniques, and Case Studies."* UC Berkeley CS Tech Report UCB//CSD-02-1175, March 2002.
- Fox, A., and Patterson, D. *"When Does Fast Recovery Trump High Reliability?"* Proc. 2nd Workshop on Evaluating and Architecting System Dependability, 2002. (Republished in IEEE Computer.)
- Candea, G., and Fox, A. *"Crash-Only Software."* HotOS IX, 2003.
- Candea, G., Kawamoto, S., Fujiki, Y., Friedman, G., and Fox, A. *"Microreboot — A Technique for Cheap Recovery."* OSDI 2004.
- Brown, A., and Patterson, D. *"Rewind, Repair, Replay: Three Rs to Dependability."* 10th ACM SIGOPS European Workshop, 2002.
- Brown, A., and Patterson, D. *"Undo for Operators: Building an Undoable E-mail Store."* USENIX Annual Technical Conference, 2003.
- Brown, A. B. *"A Recovery-Oriented Approach to Dependable Services: Repairing Past Errors with System-Wide Undo."* PhD dissertation, UC Berkeley, December 2003 (Tech Report UCB/CSD-04-1304).

**Industry Practice**

- Fowler, C. *"Trash Your Servers and Burn Your Code: Immutable Infrastructure and Disposable Components."* 2013.
- Hodgson, P. *"Feature Toggles (aka Feature Flags)."* martinfowler.com, 2017.
- Sato, D. *"BlueGreenDeployment."* martinfowler.com, 2014. *"ParallelChange."* martinfowler.com, 2014.
- Humble, J., and Farley, D. *Continuous Delivery.* Addison-Wesley, 2010.
- Burns, B., Beda, J., Hightower, K. *Kubernetes: Up and Running.* O'Reilly (3rd ed., 2022).

**SRE / DevOps / Resilience**

- Beyer, B., Jones, C., Petoff, J., Murphy, N. R., eds. *Site Reliability Engineering: How Google Runs Production Systems.* O'Reilly, 2016. (Treynor Sloss foreword on error budgets.)
- Beyer, B., Murphy, N. R., Rensin, D. K., Kawahara, K., Thorne, S., eds. *The Site Reliability Workbook.* O'Reilly, 2018.
- Nygard, M. *Release It! Design and Deploy Production-Ready Software.* Pragmatic Bookshelf, 2007; 2nd ed. 2018.
- Rosenthal, C., and Jones, N. *Chaos Engineering: System Resiliency in Practice.* O'Reilly, 2020.
- Basiri, A., Behnam, N., de Rooij, R., Hochstein, L., Kosewski, L., Reynolds, J., Rosenthal, C. *"Chaos Engineering."* IEEE Software, 33(3), 2016.
- Allspaw, J. *"Blameless PostMortems and a Just Culture."* Etsy Code as Craft, 2012.
- Allspaw, J. *"Trade-Offs Under Pressure: Heuristics and Observations of Teams Resolving Internet Service Outages."* MSc thesis, Lund University, 2015.
- Dekker, S. *The Field Guide to Understanding 'Human Error'.* Ashgate, 3rd ed. 2014.
- Principles of Chaos Engineering. principlesofchaos.org.

