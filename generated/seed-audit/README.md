# generated/seed-audit — not rendered yet

This tree holds the rendered agent seed: the complete standing prompt of
every agent this pack configures and the compiled recipe of every formula,
plus an `INDEX.md` manifest — a committed, diffable audit of what each agent
actually receives at spawn.

A fresh checkout ships only this stub. The first render recreates the tree:

    assets/scripts/render-seed-audit.sh                # render once
    assets/scripts/render-seed-audit.sh --install-hook # wire the pre-commit
                                                       # hook that keeps it
                                                       # current from then on

`doctor/check-seed-audit-current` warns (never errors) while the tree is
absent, and verifies the recorded source digest once it exists.
