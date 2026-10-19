# Foundation

gc-toolkit is a pack for Gas City, the multi-agent runtime, that gets work done by relentlessly focusing on high-bandwidth human interaction.

AI changed the cost of work. Agent iteration, parallel exploration, and self-critique are cheap. Human attention is scarce, context-bound, and not restartable on demand. gc-toolkit turns that asymmetry into operating discipline: agents do the cheap work before they interrupt, the surface makes judgment easier rather than transferring work back to the operator, and every lesson compounds into the pack so attention is never spent twice.

## Scope

**Mandate.** What gc-toolkit is, what it believes, whom it serves, and the goals it answers to.

**Boundaries.** How the pack realizes these beliefs is [architecture.md](architecture.md). What the goals ask of a change, from the operator's side, is [product-goals.md](product-goals.md).

## Core Beliefs

**Human attention is the budget.** Attention is genuinely scarce and not restartable on demand.

**Agents earn every interaction.** Make it count: do the cheap work, plan ahead, and frame the choice. Every interruption justifies the attention it claims.

**Agents improve.** Lessons come from doing; the system carries them across restarts so the next conversation starts smarter.

**Agents make their edges visible.** Looking smart and being smart are different. Legible agents show which.

**Decisions have a home.** Documentation is the system's memory. What's written survives; what isn't, doesn't.

**The pack borrows before it invents.** Most coordination problems aren't new, and many AI-era patterns are already published. gc-toolkit aggregates and cites; reinvention is the fallback when nothing fits.

## Boundaries

gc-toolkit uses Gas City as shipped. A pack is prose, config, thin glue and surfaces. Judgment lives in prompts, flow in formulas, mechanics in the platform, and visualization in surfaces. A surface is a visualization tailored to the pack, such as the helm board. These tests decide what belongs in the pack:

1. **Prose and config are free.** Prompts, skills, checklists, formulas, orders and work queries need no warrant.
2. **A pack noun needs a warrant.** A pack noun is a kind of object or state the pack defines for itself, such as a bead kind or a lifecycle state. Its warrant is a dated record that names the platform primitive it stands in for and the trigger that retires it. When Gas City ships that primitive, migrating onto it is scheduled work. A converter between a pack noun and a platform noun is the sign that the trigger was missed.
3. **Glue composes native calls.** It may not add semantics that native mechanisms already express, such as claim leases, assignment, continuation groups and waits. Glue may be one call that runs a series of native steps, so that every agent takes them the same way and none spends its context assembling them.
4. **Surfaces render platform objects.** A surface never mints objects of its own.

A claim that Gas City cannot express something carries the date it was made. Before it justifies anything, it is re-verified against Gas City's current upstream documentation. It is answered by re-expressing or reshaping the feature, never by a wrapper, a fork, or a campaign to change Gas City.

gc-toolkit will not add process for its own sake. Review legs are partners, not walls; consults are for judgment, not ritual; metrics must trigger corrective action or they are noise.

gc-toolkit will not treat cheap restart as root cause. Re-rolling an agent until a plausible diff appears launders defects into reviewer fatigue. The right answer is to make the failure legible and improve the pack.

## Who It Is For

gc-toolkit codifies a set of principles for working with AI-era agents, currently realized on Gas City but applicable to any multi-agent engine. It's for operators who want agent labor to feel abundant without making human judgment feel cheap. It fits teams and solo operators who value durable records, explicit handoffs, and agents that can act autonomously while making their edges visible. Good gc-toolkit work leaves the next contributor with fewer questions, better artifacts, and a clearer sense of what the system believes.

## Goals

### G1. Fewer escalations over time, each one higher-value
As the system accumulates patterns, it escalates less; what does escalate is heavier and demands richer engagement.

### G2. Equip the human to make the best decision
Thorough exploration plus clear presentation means attention pays off; the best consults catalyze ideas neither side started with.

### G3. Past decisions hold across handoffs
Future contributors inherit a citeable, binding record; they don't have to re-explore what's been settled.
