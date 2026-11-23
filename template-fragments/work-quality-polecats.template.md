{{ define "work-quality-polecats" -}}

<!-- managed by the learning distiller; every entry carries its anchor. cap: 12 -->
<!-- Composed after work-quality-base by polecat and polecat-codex (via the
     polecat-doctrine fragment). Holds the authoring standards for the polecat
     class only; universal standards live in work-quality-base. -->

<!-- rule:tk-tketyk src:audit:tk-awa7hv adopted:2026-08-26 -->
- File work as a bead in the pass that names it, and put the bead id in the
  row that proposed it. A prose promise loses members of a set.

<!-- rule:tk-0slk80 src:visit:tk-rxeohl (operator ruling) adopted:2026-09-23 -->
- A design or implementation bead's deliverable is the behavior it decides
  or verifies, in the smallest form that runs. A spec-only or
  documentation-only change is a legitimate deliverable only when a tracked
  bead owns the work that will build it and the change names the cost of
  waiting. An untracked spec dump, or a fix that defers to nothing, is the
  anti-pattern. The discipline is the tracked deferral, not a ban on specs.

<!-- rule:tk-qenzk6e src:bead:tk-qjc4uaa, bead:tk-cxtkwyw, pr:#1008:comment:5983192498, visit:tk-z9vxelu, visit:tk-9adohq9 (operator feedback) adopted:2026-10-31 -->
- Before you add or keep a compatibility, legacy or transitional path, such
  as a fallback, a lenient mode, old logic kept beside its replacement, or a
  bridge's behavior preserved in the code that replaces it, name the caller
  or stored data that depends on it, check that its case occurs, and read
  what that caller does when the strict form refuses it. When nothing
  depends on it, build only the end state, and when a real case does, file
  the bead that removes the path in the same change, blocked by what retires
  the case and armed to dispatch when it lands.

<!-- rule:tk-clpl8jv src:pr:#1298:comment:4310526242, pr:#1298:comment:4310543583, pr:#1220:comment:4243955265, pr:#1262:comment:4286336787, pr:#1277:comment:4303601800 (operator feedback), visit:tk-ilmnzqh (operator ruling) adopted:2026-10-31 -->
- Before a change adds machinery, such as a script, a client for a
  service, a wrapper, a state or a sweep, find what the platform it builds
  on, the service's own SDK or an established library already provides for
  the job, cite it, and write code only for the gap it leaves. A design that
  needs the platform changed, or a state that only this repository can
  interpret, is a sign it uses the platform wrongly, so look for the fitting
  use before proposing either.

<!-- rule:tk-9t1wmrd src:pr:#259:comment:3742481090, pr:#1015:comment:4180705562, pr:#1269:comment:4286682920, pr:#1269:comment:4286636653, pr:#1269:comment:4290656675 (operator feedback) adopted:2026-10-31 -->
- Put guidance an agent acts on in the prompt, skill or formula description
  it reads when it acts, never in a docs page, and where that guidance names
  an act, give the exact command to run there. Where it asks the agent to
  choose, give the command that lists the current options and the criteria
  that decide among them, never one favored option or a number that stands
  in for the criterion.

<!-- rule:tk-karx6a2 src:visit:tk-weluos5 (operator ruling) adopted:2026-10-31 -->
- Before you give something a name, such as a set, a route, a command or
  a state, ask what the word already tells a reader: a rank, a reach wider
  than the thing, or the meaning another system in use gives the same
  word. When the thing does not share that meaning, choose a word for what
  it is, and leave a general name to the thing built to fill it.

<!-- rule:tk-v32d2u src:pr:#1384:comment:4470390219, pr:#1384:comment:4470363445, pr:#1386:comment:4470476725, pr:#1386:comment:4470429133, pr:#1386:comment:4470452596, pr:#1400:comment:4476283616, pr:#1400:comment:4476263949 (operator feedback) adopted:2026-11-17 -->
- Write each fact where it applies, and where a reader elsewhere needs
  it, name the file or symbol that owns it instead of retelling it, such
  as another script's cases, the callers a test lists or why a tool is
  installed. A comment says what the code beside it cannot say for
  itself, and a fact is stated a second time only where a reader with
  just that name to follow would miss something they need.

<!-- rule:tk-xxb1jh src:pr:#1045:comment:4212283570, pr:#1267:review:5539030669 (operator feedback), bead:tk-riu2z5n adopted:2026-11-23 -->
- When a test stands in for data another program writes, such as a tool's
  files, a command's output or a service's answers, build its fixture from
  that program's real output, recorded or sampled, and make a case that
  simulates its write change what the real write changes. A fixture built by
  hand carries only the shape its author knew, so it passes cases the real
  data fails.
{{ end }}
