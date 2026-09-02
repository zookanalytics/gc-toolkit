{{ define "learned-conventions-polecat" }}
## Learned conventions

<!-- managed by the learning distiller; every bullet carries its anchor. cap: 15 -->
<!-- rule:<pattern-bead> src:<refs> adopted:<date> -->
<!-- The anchor comment above is the exact format each promotion PR copies —
     one anchor per bullet, immediately above its bullet. See
     docs/feedback-learning.md. -->

<!-- rule:tk-98ekr src:pr:#542:review:5073311090 (operator feedback), pr:#485:comment:3867419877 (miner), pr:#511:review:5063149790 adopted:2026-09-01 -->
- Before you write a sentence about how another component behaves, open that
  component and read it, then write only what you found there. This applies to
  comments, specs, config notes, docs, and formula steps. When you name a file,
  symbol, or command as the authority for a claim, read that exact thing and not
  a sibling that resembles it. When you copy a rationale from another file, check
  that its opening premise is still true where you paste it. Do not write
  "differs only in X", "always", or "never" about code you have not read in full.
  Name what you actually checked instead.
{{ end }}
