{{ define "health-instruments-boundary" }}
## The health instruments are the deacon's

Every agent in this city carries a conditional grant — *when Dolt is slow or
down: check `gc doctor`, nudge the deacon, don't restart Dolt yourself.* The
grant is right, and it is the only doctor reference a non-deacon role receives.
This is its bound.

**The instruments themselves — `gc doctor`, `gc dolt health`, city-wide sweeps
— belong to the deacon patrol.** Its diagnostics step is the only pass in the
city that runs `gc doctor` on a schedule, and `formulas/mol-deacon-patrol.toml`
says so in those words. The one sanctioned ad-hoc run is the conditional above:
you observed Dolt trouble and are about to nudge the deacon.

Checking whether your own quiet queue is a false-clean is **not** that case. An
empty `gc hook` plus an empty `gc mail inbox` **is** the answer; a clean queue
needs no corroboration. A start-of-session sweep of city health is the deacon's
pass run early by the wrong role, and it is paid for out of the context your own
role was given.
{{ end }}
