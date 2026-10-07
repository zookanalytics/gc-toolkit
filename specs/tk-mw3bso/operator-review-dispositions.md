# PR#788 operator review dispositions

Review 5258073554 (johnzook, `changes_requested`) left four inline threads on
`agents/proactive/prompt.template.md` and `formulas/mol-first-reaction.toml`.
All four are answered by the same de-duplication: the proactive prompt template
carries doctrine and `mol-first-reaction` carries the mechanics, so each rule
states once.

| Thread | Location | The point | Disposition |
|---|---|---|---|
| 4055001220 | prompt.template.md:87 | The origin paragraph defends against a behavior the agent has no default to do — an operator-filed bead is triaged like any other unless something tells it otherwise. | Code. Removed the origin paragraph; the disposition rule reads "each triaged on its merits" with no origin call-out. |
| 4055002909 | prompt.template.md:112 | The dispose code-block comments re-describe the prose above them, `#` prefix aside. | Code. Removed the dispose code blocks from the prompt; the four exits are named as doctrine and the exact commands live in `mol-first-reaction`'s `advance-and-drain` step. |
| 4055007683 | prompt.template.md:127 | A restatement of `close` should be clear that there is nothing to do and nothing to communicate to the operator. | Code. `close` now reads "nothing left to do and nothing the operator needs to see" in both the prompt and the formula rubric. |
| 4055013439 | mol-first-reaction.toml:173 | The formula rubric duplicates the prompt template, and the duplication is broader than this change. | Code. The prompt no longer re-spells the mechanics, so the formula is the single home for the dispose commands. `tools/proactive-first-reaction-fixture.sh` asserted the same command strings against both surfaces — the mechanism that held the duplication in place — so its prompt assertions now check that the exits are named, while the command assertions stay against the formula alone. |

The `gate-visit` block travelled with the mechanics: the prompt shipped a marked
copy inside the removed code block, so `assets/scripts/gate-visit.test.sh` no
longer sweeps prompts — the formula and script copies carry every shipped
instance.
