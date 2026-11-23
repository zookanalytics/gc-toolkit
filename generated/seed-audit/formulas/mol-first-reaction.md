Formula: mol-first-reaction
Description: First reaction — one proactive worker reads a freshly filed bead once, writes a
first-reaction card into its notes and disposes it through one exit: route it to
a pool or to the named agent whose work it is, recommend an action the operator
can accept, hold it on an edge, hand a confident no-op to a validating closer,
or put a question to the operator as a human gate. A reaction never closes the
bead, and code it produces takes the gated `mr` path only.

`gctk reaction sling <bead>` slings this formula on the bead, once its
refusals pass, to the proactive pool the roster names in the rig:
`gc sling <rig>/<binding>.proactive <bead> --on mol-first-reaction`, where
`<binding>` is the name the city imports the pack under. The run is the
reaction's lease, Gas City's run cancel is its stop, and gc sling refuses a
second live run on the bead, so a reaction happens once at a time.

## The contract

1. **The subject arrives as the input convoy's single tracked member.** The
   step derives it in its own shell (`gc convoy status {{convoy_id}}`), the way
   every graph.v2 worker does.
2. **Check before you read.** The subject's state can change between the sling
   and the claim, so the step's first act asks the sling's refusals again, and
   any refusal ends the run with nothing written.
3. **The reaction is the proactive prompt's.** The card, the exits and the
   judgment between them live in agents/proactive/prompt.template.md; this
   formula holds the run's mechanics.
4. **Close your own step** through assets/scripts/claim-close.sh, then drain.


Variables:
  {{binding_prefix}}: The binding the city imports the pack under, with its trailing dot. A step drops the dot to call the pack's own scripts as gc <binding> scripts-dir prints them. Gas City's sling adds it to every pour it makes; a pour that names none takes this default. (default=gc-toolkit.)

Steps (2):
  ├── mol-first-reaction.react: React once to the subject and dispose it
  └── mol-first-reaction.workflow-finalize: Finalize workflow [needs: mol-first-reaction.react]
