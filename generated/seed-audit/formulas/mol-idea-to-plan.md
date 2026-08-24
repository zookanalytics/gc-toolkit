Formula: mol-idea-to-plan
Description: Full pipeline from vague idea to reviewed, beads-ready implementation plan.

This is the Gas City-compatible v2 planning workflow for Gastown.

Upstream's newer workflow uses convoy-style planning formulas, `gt formula run`,
`gt sling --prompt`, and `--mail-back`. Gas City does not ship those planning
shortcuts today, so this formula maps the same intent onto primitives we do
have:

- repo-local artifacts (`.prd-reviews/`, `.designs/`, `.plan-reviews/`)
- review task beads created with `gc bd create`
- parallel dispatch via `gc sling ... --on mol-review-leg`
- completion mail via `gc mail send`
- one human clarification gate in the live conversation
- final bead graph creation with `gc bd create` + `gc bd dep add`

Run this from a coordinator workspace that has the target repo checked out
(typically a crew worker, or a mayor who has already `cd`'d into the rig repo).

## Pipeline

1. Draft a PRD from the raw idea
2. Dispatch 6 PRD review legs in parallel
3. Ask the human one round of clarifying questions
4. Dispatch 6 design-exploration legs in parallel
5. Run 3 PRD-alignment rounds (2 legs each)
6. Run 3 plan self-review rounds (2 legs each)
7. Convert the refined plan into beads with dependencies

The goal is parity of outcome, not a verbatim port of upstream's convoy DSL.


Required vars:
  {{problem}}: Raw feature idea, problem statement, or request

Optional vars:
  {{binding_prefix}}: Import binding prefix for gastown agent identities, including trailing dot when bound. (default=)
  {{context}}: Additional context: constraints, prior decisions, related code, links, or examples (default=)
  {{review_formula}}: Formula used for dispatched review legs (default=mol-review-leg)
  {{review_target}}: Agent or pool that should execute review legs (for example, my-rig/{{binding_prefix}}polecat). Empty means derive $GC_RIG/{{binding_prefix}}polecat. (default=)

Steps (13):
  ├── mol-idea-to-plan.init-run: Initialize the planning run in the current repo
  ├── mol-idea-to-plan.draft-prd: Write a draft PRD from the raw idea [needs: mol-idea-to-plan.init-run]
  ├── mol-idea-to-plan.prd-review: Dispatch 6 PRD review legs in parallel and synthesize the result [needs: mol-idea-to-plan.draft-prd]
  ├── mol-idea-to-plan.human-clarify: Ask the human the consolidated PRD questions [needs: mol-idea-to-plan.prd-review]
  ├── mol-idea-to-plan.design-exploration: Dispatch 6 design legs and synthesize the initial design doc [needs: mol-idea-to-plan.human-clarify]
  ├── mol-idea-to-plan.prd-align-1: PRD alignment round 1: requirements and goals [needs: mol-idea-to-plan.design-exploration]
  ├── mol-idea-to-plan.prd-align-2: PRD alignment round 2: constraints and non-goals [needs: mol-idea-to-plan.prd-align-1]
  ├── mol-idea-to-plan.prd-align-3: PRD alignment round 3: user stories and open questions [needs: mol-idea-to-plan.prd-align-2]
  ├── mol-idea-to-plan.plan-review-1: Plan self-review round 1: completeness and sequencing [needs: mol-idea-to-plan.prd-align-3]
  ├── mol-idea-to-plan.plan-review-2: Plan self-review round 2: risk and scope-creep [needs: mol-idea-to-plan.plan-review-1]
  ├── mol-idea-to-plan.plan-review-3: Plan self-review round 3: testability and coherence [needs: mol-idea-to-plan.plan-review-2]
  ├── mol-idea-to-plan.create-beads: Convert the refined plan into beads and dependencies [needs: mol-idea-to-plan.plan-review-3]
  └── mol-idea-to-plan.workflow-finalize: Finalize workflow [needs: mol-idea-to-plan.create-beads]
