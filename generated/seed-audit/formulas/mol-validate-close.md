Formula: mol-validate-close
Description: Validating closer — the downstream half of a first reaction's `close`
disposition. A first reaction runs on a cheap model and never closes a bead; when
it concludes there is nothing to do it routes the bead here, and this workflow,
run by a capable pool, re-checks that conclusion against live state and closes
the bead when it holds or escalates to the operator when it does not.

## The contract

1. **The subject arrives as the input convoy's single tracked member.** Each
   step re-derives it in its own shell (`gc convoy status {{convoy_id}}`), the
   way every graph.v2 worker does.
2. **Validate before you close.** `gc.first_reaction_reason` is the reaction's
   claim, not a verdict — re-derive it. Read the bead's universe and confirm the
   thing it says is already fixed is fixed, or that the bead names nothing left
   to do. A close is only as good as the check behind it.
3. **Close only when fully confident; otherwise escalate.** Confident that there
   is nothing to do: close the subject with `gc.work_outcome=no-op` and a note
   recording what you checked. Any doubt — the premise does not hold, there is
   real work, or the call is the operator's — leaves the bead OPEN and files a
   visit. This workflow is authorized to close the SUBJECT, which is the one
   bead it closes, and only on its own confident check. It never closes a bead
   that carries a `merge_result` (that is the refinery's, closed on a verified
   merge); such a bead escalates.
4. **Close your own step beads** through assets/scripts/step-close.sh, which
   resolves by (gc.root_bead_id, gc.step_ref); never a GC_*BEAD_ID env var,
   which does not track the current step after a claim.


Steps (3):
  ├── mol-validate-close.load-context: Read the subject and the reaction's close brief
  ├── mol-validate-close.validate-and-resolve: Validate the no-work conclusion, then close or escalate [needs: mol-validate-close.load-context]
  └── mol-validate-close.workflow-finalize: Finalize workflow [needs: mol-validate-close.validate-and-resolve]
