# gc-toolkit North Star

gc-toolkit is an opinionated Gas City pack for taking intent to implemented
work while spending the fewest possible human steps and making every remaining
human step high-bandwidth.

It exists because AI changed the cost of work. Agent execution, retries,
parallel exploration, and self-critique are cheap. Human attention is scarce,
context-bound, and not restartable on demand. gc-toolkit turns that asymmetry
into operating discipline: agents should do more of the cheap work before they
interrupt, and when they do interrupt, the surface should make judgment easier,
not merely transfer work back to the operator.

## Core Beliefs

**Human attention is the budget.** Every agent, formula, skill, channel, and
convention has to justify its attention claim. If an addition neither removes a
human step nor makes a remaining human step easier to perform, it does not
belong.

**The human owns the clock.** The pack should be ready when the operator turns
to it and quiet when they do not. Waiting time is agent time: use it to deepen
analysis, build alternatives, verify work, and prepare better artifacts.

**Agents should bring opinions, options, and evidence.** A useful consult is
not a vague question and not a buffet of undigested possibilities. The agent
frames the problem, explores the design space, states its recommendation, and
shows enough evidence that the human can recognize, challenge, or redirect the
work quickly.

**Decisions live in durable artifacts.** Chat can negotiate a decision, but it
is not where the decision should live. Architecture choices, roadmap changes,
accepted patterns, escalations, and lessons learned should end in beads,
docs, ADRs, skills, formulas, tests, or other artifacts future agents can read.

**The pack learns through merged change.** Retrospection only matters when it
changes the system that will run next time. AARs, COEs, audits, and review
findings must close into prompts, skills, gates, docs, evals, or code. Coaching
without retention is ceremony.

**Automation drifts unless audited.** Agents can be productive and wrong at the
same time. gc-toolkit expects drift in prompts, skills, conventions, silent
decisions, and review surfaces. Finding drift is not failure; failing to look
for it is.

**Convention carries the common path.** Gas City is configuration-first, but
gc-toolkit should make the right shape easy to recognize: schema-2 packs,
convention-discovered agents, reusable skills, formula workflows, beads as the
work unit, and pack overrides instead of forks.

## Boundaries

gc-toolkit will not fork or replace Gas City or Gastown. It augments them with
pack-local opinions, patches, agents, skills, and conventions.

gc-toolkit will not add process for its own sake. Review legs are partners, not
walls; consults are for judgment, not ritual; metrics must trigger corrective
action or they are noise.

gc-toolkit will not treat cheap restart as root cause. Re-rolling an agent until
a plausible diff appears launders defects into reviewer fatigue. The right
answer is to make the failure legible and improve the pack.

gc-toolkit will not hide project knowledge in private memory or transient chat.
Useful context belongs where future agents and operators can find it.

## Who It Is For

gc-toolkit is for operators running multi-agent software work who want agent
labor to feel abundant without making human judgment feel cheap. It fits teams
and solo operators who value durable records, explicit handoffs, low-friction
dispatch, and agents that can act autonomously while still making their edges
visible. Good gc-toolkit work leaves the next contributor with fewer questions,
better artifacts, and a clearer sense of what the system believes.

## Source Anchors

This distills the working foundation in `docs/foundation.md` and the
pack thesis in `docs/roadmap.md`, with supporting direction from
`specs/tk-px5od/marching-orders.md`, `specs/tk-px5od/roadmap.md`,
`specs/tk-px5od/selection-menu.md`, `docs/gas-city-pack-v2.md`, and
`docs/gas-city-reference.md`.
