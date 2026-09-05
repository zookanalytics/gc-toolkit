/**
 * The Helm board contract — the TypeScript mirror of the Go structs in
 * `services/helm/internal/board/model.go`.
 *
 * This file is HAND-WRITTEN on purpose. The `/svc/` surface is not part of the
 * supervisor's OpenAPI document, so there is no generated client and no codegen
 * step to hang a type off. What makes hand-mirroring safe is the rule stated in
 * model.go's package doc: the struct tags are an ADDITIVE contract — fields may
 * be added, never renamed or removed. Adding a field cannot break a client that
 * has not mirrored it yet.
 *
 * What keeps it honest is `contract_parity_test.go`, one directory up. It
 * reflects over the Go structs and parses this file, and fails `go test ./...`
 * when the two disagree about a field's name, its type, or whether it is
 * optional. Without that check a hand-written mirror drifts silently — a
 * renamed Go field just becomes `undefined` at runtime, in a browser, with no
 * error anywhere. Treat a parity failure as "update this file in the same
 * change", not as a flaky test.
 *
 * SCOPE: the wire only. These interfaces mirror exactly the Go types reachable
 * from the `GET <mount>/helm` response body: the `board.Board` envelope and the
 * structs nested under it — `board.Tile`, `board.Sitting`, and
 * `board.PackBuild`. Reachability from the envelope is the rule, not this list:
 * a struct added under `board.Board` joins the contract automatically.
 * `board.Anchor` and `board.Child` carry JSON tags too, but they are the
 * gather-side input to `BuildBoard` and never cross the wire, so mirroring them
 * here would invent a contract the service does not serve. The parity test
 * enforces that boundary in both directions: every `export interface` in this
 * file must correspond to a Go wire struct, and vice versa. UI-only types
 * belong in the component that needs them, not here.
 */

/**
 * Severity is the attention band of a tile; higher bands dominate ranking.
 *
 * The parity test checks these members against the `Severity` constants in
 * model.go, so a new band added on the Go side fails the build here until it is
 * mirrored. Consumers may switch exhaustively on this union — but note that the
 * Go type is a plain string type, so an unknown value is representable on the
 * wire even though it is not representable here.
 */
export type Severity = 'HIGH' | 'ELEVATED' | 'NORMAL' | 'LOW' | 'DONE';

/**
 * Tile is one rendered row of the board.
 *
 * The field set and its order mirror the `--json` object gc-helm.sh emits, so
 * the dashboard and the `helm-svc board` CLI describe a row the same way. Every
 * `*_heads` / `cross_rig_refs` list is always emitted (`[]` when empty) even
 * though the mechanical Go mapping widens it to `| null`; narrow before
 * iterating.
 */
export interface Tile {
  id: string;
  rig: string;
  kind: string;
  title: string;
  severity: Severity;
  /**
   * The next move on this row is a PERSON'S: an unanswered human gate, or a
   * parked conversation whose recorded waits have all landed. Not derivable
   * from `severity`, which is coarse and shared — a one-bead demand bands
   * ELEVATED while a stranded container bands HIGH, so rank alone always sorts
   * the operator's own queue underneath the city's.
   */
  owed: boolean;
  /** Rank proxy: subtree size + priority weight + capped cross-rig refs. */
  weight: number;
  /** An open visit bead names this anchor — a conversation is holding it. */
  held: boolean;
  n_closed: number;
  m_total: number;
  open: number;
  /**
   * RAW status count, honestly 0 for a slung bead whose work never leaves
   * `status=open`. Use `in_progress_live` to ask "is anything moving".
   */
  in_progress: number;
  assigned: number;
  /** Children demonstrably moving: claimed by a live session, OR under a live workflow. */
  in_progress_live: number;
  /** Claimed, owner gone, and no live workflow behind it. */
  in_progress_dead: number;
  dead_owner: boolean;
  /** The part of `in_progress_live` attributable to a workflow rather than a claim. */
  in_flight: number;
  in_flight_heads: string[] | null;
  /** Convoys only: `false` marks the unowned-convoy orphan exception. `null` for every other kind. */
  owned: boolean | null;
  /**
   * Open work with nothing live in it, no open visit, and no UNANSWERED human
   * gate — the three ways a row's silence is already accounted for. A bead
   * routed to the operator is not stranded; once the ruling is recorded the
   * gate is discharged and open children under it are ordinary idle work again.
   */
  stranded: boolean;
  empty: boolean;
  complete: boolean;
  /** The convoy's own closed/total claim disagrees with the rolled-up membership. */
  progress_mismatch: boolean;
  /**
   * Whole days since the anchor was last updated. 0 both when the anchor was
   * touched today and when the source could not read `updated_at` at all —
   * which is why the timestamp travels alongside: absent `updated_at` means
   * unknown, present means genuinely fresh.
   */
  stale_days: number;
  priority: number | null;
  /** Bead ids belonging to OTHER rigs, scanned out of the anchor's prose. */
  cross_rig_refs: string[] | null;
  /** Idle open children — unclaimed, not carried by a live workflow, and not parked. */
  open_heads: string[] | null;
  dead_owner_heads: string[] | null;
  /**
   * Open children that carry a board row of their own — routed to the operator,
   * or holding a takeaway. Split out of `open_heads` so a parent cannot report
   * a child that is waiting on a ruling as work nobody has picked up. `open`
   * still counts them.
   */
  parked_heads: string[] | null;
  /**
   * Beads this row depends on by a `blocks` edge, and the subset still open.
   * On a parked conversation these are the work a sitting routed out of it:
   * `disposition_due` is true once every one of them has closed, which is the
   * board's only way to tell a finished topic from a live hold (tk-2plde).
   */
  waiting_on: string[] | null;
  waiting_on_open: string[] | null;
  disposition_due: boolean;
  /** The LLM-authored headline a converse sitting left. `null`, not absent, when there is none. */
  takeaway: string | null;
  takeaway_at: string | null;
  takeaway_by: string | null;
  /** RFC 3339. Omitted (Go `omitzero`) when the source could not read it. */
  updated_at?: string;
  /**
   * `closed_at` is present exactly on a `DONE` row and carries when the anchor
   * closed. A closed anchor keeps a place on the board instead of leaving it
   * the moment it is answered, so this is also the band's order: most recently
   * closed first.
   */
  closed_at?: string;
  frontier: string;
  needs: string;
  rank_score: number;

  /**
   * The PR round-trip, as two independent axes rather than one enum. They move
   * independently and are often true at once — an anchor can carry a review the
   * cadence dispatched AND an unanswered comment from the operator — so one
   * field would have to pick, and either pick hides the other.
   *
   * A row is a MERGE ANCHOR's, not a pull request's. An anchor at
   * `pre_open_gate` has a branch, a gate set and a machine axis with no PR
   * number yet, so `pr_number` is a field on the row and never the selector;
   * it is `0` until the PR opens. Every field is `''` (or `0`) on a row that is
   * not a merge anchor at all, which is a different answer from `'unknown'`.
   */
  pr_number: number;
  /** The operator's way into GitHub, which is where the conversation stays. */
  pr_url: string;
  /**
   * The branch the anchor's work sits on — the row's identity for the whole
   * span before a number exists, which is where most wedged anchors are. A
   * field of its own rather than a read out of `frontier`, which is prose and
   * is not rendered on every table. `''` when the anchor records no branch.
   */
  pr_branch: string;
  /**
   * What the merge cadence can do next: `'progressing'`, `'settled'`,
   * `'wedged-exception'`, `'wedged-veto'`, or `'unknown'`.
   *
   * `'unknown'` is a RENDERED value, never a fallback to the quiet end — the
   * same choice `waiting_unknown` makes on the gather side. A missing key means
   * the cadence has not recorded a position yet, which is a fact about the city
   * rather than an all-clear, and it counts against the section's coverage.
   */
  pr_machine: string;
  /**
   * Where the exchange with the operator stands. Reads `'unknown'` on every row
   * today: its other values all resolve to acknowledgement watermarks nothing
   * records yet, and every failed guess resolves to silence — the one answer
   * that tells the operator to stop looking. It ships now so this contract does
   * not change shape when the watermarks land.
   */
  pr_conversation: string;
  /**
   * Whether GitHub is withholding the merge for a human review: `'required'`,
   * `'met'`, `'not_required'`, or `'unknown'`. Read from the recorded review
   * decision, which is GitHub's own requirement rather than the city's gate
   * set — a repository can require a review `check_set` never declared.
   *
   * `'required'` covers a standing `changes_requested` too, so a pull request
   * GitHub is blocking never renders as one it will let through. That row is
   * not `owed` by the operator, though: answering a rejecting review is the
   * city's move.
   */
  pr_approval: string;
  /**
   * RFC 3339. When the operator's turn began — the clock the owed partition is
   * ranked by, taken as the EARLIEST instant among the causes the row currently
   * holds. Omitted (Go `omitzero`) when nothing makes the row owed, and omitted
   * when the only candidate cause reads `'unknown'`: an unreadable input
   * belongs in the coverage sentence, not in a clock reporting the wait as new.
   *
   * Not `updated_at`, which a wedged anchor's every reconcile pass touches.
   */
  pr_owed_since?: string;
}

/**
 * Sitting is one converse sitting — the visit bead a conversation runs inside.
 *
 * Sittings are not tiles and are not ranked against them: a tile is an anchor
 * that wants something, a sitting is an event in the conversation record. The
 * board carries every running sitting plus those closed inside the service's
 * recent window (`GC_HELM_SITTINGS_WINDOW`, a day by default).
 */
export interface Sitting {
  id: string;
  rig: string;
  /** The anchor the conversation is about — the same id `held` keys on. */
  subject: string;
  title: string;
  /** The visit bead's status. `'closed'` is finished; anything else is running. */
  status: string;
  /**
   * The one-word justification a sitting closed on (`gc.outcome`: folded,
   * moot, benign, diagnosed, cut-short, the word a held sitting signs off with,
   * or `dismissed` when the operator ends it from the board). Normally empty
   * while a sitting is still running, with one exception: a board dismissal
   * that stamped the outcome but could not close the visit leaves a running
   * sitting reading `dismissed` until it is closed or signed off over.
   */
  outcome: string;
  /** The converse session that ran it — what an operator attaches to. */
  session: string;
  /** RFC 3339. Omitted when the source could not read the stamp. */
  opened_at?: string;
  /** RFC 3339. Omitted while the sitting is still running. */
  closed_at?: string;
  /**
   * The headline THIS sitting left on its subject, or `''`. A takeaway lives on
   * the subject and each sitting overwrites the last one's, so the service
   * hands it only to the sitting that was running when it was stamped — a
   * subject visited three times has two sittings that did not write it.
   */
  takeaway: string;
}

/**
 * PackBuild is one compiled component's build state, as its out-of-band build
 * order last left it.
 *
 * Nothing in the running system builds these binaries — the launchers exec what
 * a build order published — so a component can serve a binary older than its
 * sources indefinitely. `source_rev` and `binary_rev` diverge exactly when a
 * build failed and the last good binary kept serving; `checked_at` is the only
 * field a quiet tick moves, so it is the only one that can say the build order
 * itself has stopped.
 *
 * `severity` and `detail` are DERIVED on the Go side so this view and the
 * `helm-svc board` CLI cannot disagree about what a row means. Render them;
 * do not re-derive them from the raw fields.
 */
export interface PackBuild {
  component: string;
  /** RFC 3339. Omitted when no build has been recorded. */
  built_at?: string;
  /** The revision the last build tick saw in the sources. */
  source_rev: string;
  /** The revision the binary now on disk was built from. */
  binary_rev: string;
  /** Exit status of the last build ATTEMPT; 0 for success. */
  last_build_rc: number;
  /** A published binary nothing is running yet — built, but not serving. */
  restart_pending: boolean;
  /**
   * What `helm-svc probe` said about this binary: "ok", "unreadable", or
   * "unprobed" when no city was resolved to ask about. A binary that compiles
   * but cannot read the stores it serves renders no board, which the revisions
   * alone cannot say.
   */
  probe_status?: string;
  /** The probe's one-line reason. Empty unless `probe_status` is "unreadable". */
  probe_detail?: string;
  /** RFC 3339. When the build order last ran at all, successful or not. */
  checked_at?: string;
  severity: Severity;
  detail: string;
}

/**
 * Board is the envelope returned at `<mount>/helm`. Tiles arrive deduplicated
 * by `id` and PARTITIONED: every `owed` row first, oldest-owed first, then
 * everything else by `rank_score` descending. `total` is the count before any
 * row cap.
 *
 * The partition is on the wire rather than left to each renderer because
 * `rank_score` cannot express it — severity is coarse and shared, so the term
 * that really orders the list is subtree size, and a demand owed by a person
 * has a subtree of one. Filter on `owed` to take just the queue.
 */
export interface Board {
  /** RFC 3339. */
  generated_at: string;
  total: number;
  /**
   * `null`, not `[]`, when the board is empty — Go marshals a nil slice as
   * `null` and this field carries no `omitempty`, so the key is always present.
   * Narrow it (`board.tiles ?? []`) before iterating.
   */
  tiles: Tile[] | null;
  /**
   * The conversation record: running sittings first (longest-running first),
   * then the recently closed (most recent first). `null` rather than `[]` when
   * empty, exactly like `tiles` — narrow before iterating.
   */
  sittings: Sitting[] | null;
  /** True when one or more rigs did not answer; the board is incomplete. */
  partial?: boolean;
  partial_errors?: string[];
  /**
   * The build state of the pack's compiled components. Absent in a city whose
   * build orders have never run — which is why it is optional rather than an
   * empty array: no rows means nothing was measured, not that all is well.
   */
  pack_health?: PackBuild[];
}
