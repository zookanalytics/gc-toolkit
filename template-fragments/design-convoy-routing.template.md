{{ define "design-convoy-routing" }}
{{/* Elected by the roles that route work: converse recommends, mechanik slings. */ -}}
## Choosing a design-convoy

A design-convoy (`mol-design-convoy`) stands up an owned integration convoy for
one initiative. A design child lands its doc on the convoy's integration branch,
implementation builds there, and the whole unit graduates to the default branch
as one reviewed PR. Choose the route for a follow-up by asking, in order:

1. Is there executable work at all? No: a bare visit (`mol-visit`). A judgment
   or decision the operator owns, with nothing to build, has nothing to
   dispatch.
2. Does the work need a design settled before or beside the build, and is it
   large or high-blast-radius enough that one holistic review beats scattered
   PRs? Yes: a design-convoy, so design and implementation land as one reviewed
   unit and the design gate catches a wrong shape before it is built. No: a
   plain work bead on the default one-child convoy, one PR to the default
   branch.

`design_gated` defaults to `true`, which holds implementation until the operator
approves the design's PR. `docs/design-convoy.md` describes the gates and when
all-in-one (`--var design_gated=false`) fits.
{{ end }}
