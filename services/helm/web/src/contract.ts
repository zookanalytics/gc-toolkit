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
 * from the `GET <mount>/helm` response body — `board.Board` and `board.Tile`.
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
export type Severity = 'HIGH' | 'ELEVATED' | 'NORMAL' | 'LOW';

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
  /** Open work with nothing live in it and no open visit. */
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
  /** Idle open children — unclaimed, and not carried by a live workflow. */
  open_heads: string[] | null;
  dead_owner_heads: string[] | null;
  /** The LLM-authored headline a converse sitting left. `null`, not absent, when there is none. */
  takeaway: string | null;
  takeaway_at: string | null;
  takeaway_by: string | null;
  /** RFC 3339. Omitted (Go `omitzero`) when the source could not read it. */
  updated_at?: string;
  frontier: string;
  needs: string;
  rank_score: number;
}

/**
 * Board is the envelope returned at `<mount>/helm`. Tiles arrive sorted by
 * `rank_score` descending and deduplicated by `id`; `total` is the count before
 * any row cap.
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
  /** True when one or more rigs did not answer; the board is incomplete. */
  partial?: boolean;
  partial_errors?: string[];
}
