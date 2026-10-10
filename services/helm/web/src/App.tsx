import { useCallback, useEffect, useMemo, useState } from 'react';
import type { CSSProperties } from 'react';
import { CitySignals, DrillPanel } from './drill';

import { TerminalTile } from './terminal/TerminalTile';
import { resolveTerminalBase, resolveTerminalSession } from './terminal/endpoint';
import { ActuateButton } from './actuate/ActuateButton';
import type { Board, PackBuild, Sitting, Tile } from './contract';

// The board shape lives in ./contract.ts — the hand-written mirror of the Go
// structs in internal/board, guarded by the parity check in
// contract_parity_test.go. Do not redeclare any part of the wire shape here;
// a second copy is the drift this app is built to avoid.

// The server caches each computed board for 45s, so polling faster than that
// only re-reads the same bytes. This surface is pull-only by charter: it
// refreshes in place and never notifies.
const REFRESH_MS = 30_000;

// The board arrives as ONE ranked list, and every row carries its dependency
// family in `tile.group_root` and the band it wants within that family in
// `tile.section`. Both are derived once, in the shared Go layer, so the CLI
// board and this app cannot each invent their own split; this file READS the
// fields, it does not re-derive them. The order the bands read in WITHIN a
// family is the derive layer's SectionOrder, mirrored here.
const SECTION_ORDER = ['review', 'gate', 'stalled', 'active', 'cleanup', 'done'] as const;

// Where the operator's collapsed-parent choice is kept. Collapse is a view
// state, not a board fact, so it lives client-side and persists across the 30s
// poll and the next visit: a parent keeps its "room" between glances, the
// durable-place principle this board is built on. The value is a JSON array of
// the collapsed parents' ids; absent means every parent is expanded, the
// information-complete default that hides nothing until the operator folds it.
const COLLAPSE_STORAGE_KEY = 'helm.board.collapsed';

// The one Tile.visit_state value the marker branches on (board.VisitEngaged).
// A held row carries 'engaged' or 'parked'; anything that is not 'engaged' —
// 'parked', or the '' a re-derivation slip could leave — reads as parked, the
// state that invites the operator to look rather than telling them it is handled.
const VISIT_ENGAGED = 'engaged';

// A sitting is finished when its visit bead closed; anything else is a
// conversation someone is still in. Reading the status rather than the presence
// of closed_at keeps a sitting whose stamp could not be read on the running
// side, which is the side that shows a row rather than hides one.
const isRunning = (s: Sitting): boolean => s.status !== 'closed';

// What a sitting CONCLUDED, or failing that what it is ABOUT: the takeaway wins,
// then the outcome reason (why a decision-close closed), then the subject's title
// (the topic), and the visit bead's own title only as a last resort. Mirrors the
// board service's Sitting.Headline so the sittings table and the per-row visit
// hover read one rule.
function sittingHeadline(s: Sitting): string {
  return s.takeaway || s.outcome_reason || s.subject_title || s.title;
}

// How long ago a stamp was, in the coarsest unit that still says something. An
// absent stamp is unknown, never "just now": the sitting whose timestamp the
// source could not read must not read as the freshest one.
function shortAge(stamp: string | undefined, now: number): string {
  if (!stamp) return '?';
  const ms = Date.parse(stamp);
  if (Number.isNaN(ms)) return '?';
  const mins = Math.max(0, Math.floor((now - ms) / 60_000));
  if (mins < 60) return `${mins}m`;
  const hours = Math.floor(mins / 60);
  if (hours < 48) return `${hours}h`;
  return `${Math.floor(hours / 24)}d`;
}

// Document-relative on purpose. The app is served under a runtime-city-named
// prefix (/v0/city/<city>/svc/helm/), so an absolute '/helm' would address the
// supervisor root and 404. Relative to the document, this is <mount>/helm.
const BOARD_URL = 'helm';

async function fetchBoard(signal: AbortSignal): Promise<Board> {
  const res = await fetch(BOARD_URL, {
    signal,
    headers: { Accept: 'application/json' },
  });
  if (!res.ok) {
    throw new Error(`board request failed: HTTP ${res.status}`);
  }
  return (await res.json()) as Board;
}

/**
 * Reads the bead to drill into on load, honouring a `?drill=` override. This is
 * the target end of a link from outside the board — a pull request, a message —
 * that resolves to a board ACTION rather than the board's front page: it opens
 * the row's drill panel, where the board moves (start a conversation) live.
 * Absent or blank opens nothing, the board's default.
 *
 * NOT validated here, for the reason resolveTerminalSession is not: the id
 * travels to the drill fetch and the open route, both of which check it against
 * the store server-side. A regex here would be a decorative copy that drifts
 * from the check that matters, over a string the client controls anyway.
 */
export function resolveDrillTarget(search: string): string | null {
  const raw = new URLSearchParams(search).get('drill');
  if (raw === null) return null;
  const trimmed = raw.trim();
  return trimmed === '' ? null : trimmed;
}

// The date the row started asking. `gc.takeaway_at` is when a sitting recorded
// what is owed; `updated_at` only bounds it from below, and a backend may read
// neither. Display only — the ORDER is the service's, and re-deriving it here
// is how the two would drift.
function owedSince(tile: Tile): string {
  // pr_owed_since first: on a merge anchor it is the only stamp that dates the
  // TURN. A wedged anchor is touched by every reconcile pass, so updated_at
  // reports the most neglected row as the freshest one.
  const stamp = tile.pr_owed_since ?? tile.takeaway_at ?? tile.updated_at;
  return stamp ? stamp.slice(0, 10) : 'unknown';
}

/** A merge anchor: the row the PR round-trip renders onto. */
function isPRRow(tile: Tile): boolean {
  return tile.pr_machine !== '';
}

/**
 * The pull request this row is about, as a link when one is open.
 *
 * Before the PR opens the branch is the identity, and it links to the branch's
 * GitHub tree view when the rig's repository is known — the common case among
 * wedged rows, not an edge one. A row that can name neither says so; it is the
 * anchor at a human state that records no branch, and there the absence is the
 * whole answer. The conversation lives in GitHub and the link is the one click
 * to it; the board never reproduces a comment thread.
 */
function PRLink({ tile }: { tile: Tile }) {
  if (!isPRRow(tile)) return null;
  if (tile.pr_number > 0 && tile.pr_url) {
    return (
      <a href={tile.pr_url} target="_blank" rel="noreferrer">
        PR #{tile.pr_number}
      </a>
    );
  }
  if (tile.pr_branch) {
    if (tile.pr_branch_url) {
      return (
        <a href={tile.pr_branch_url} target="_blank" rel="noreferrer">
          {tile.pr_branch}
        </a>
      );
    }
    return <span className="sub">{tile.pr_branch}</span>;
  }
  return <span className="sub">not open yet</span>;
}

/**
 * The PR phase indicator for a merge anchor. On a live row it names who must act
 * next, in the three values the GitHub status: label carries (working,
 * needs-review, needs-attention); on a closed row it names how the PR resolved,
 * in the board-only terminal states (merged, closed). A colored chip so the
 * answer reads at a glance; nothing rendered on a row with no phase.
 */
function PRPhaseChip({ tile }: { tile: Tile }) {
  if (!tile.pr_phase) return null;
  return <span className={`pr-phase pr-phase--${tile.pr_phase}`}>{tile.pr_phase}</span>;
}

/**
 * What the board could not read about the pull requests it holds.
 *
 * The coverage sentence's empty state is a contract: it states its coverage or
 * it states the error, never a blank. PR rows add a way for that to go quietly
 * wrong, because an axis nothing has recorded looks exactly like an axis with
 * nothing to say — so the all-clear is withheld while any position is unread.
 * `owed` is a boolean and cannot carry the third value the axes do.
 *
 * Closed rows are excluded, and they have to be: the DONE band's rows carry the
 * same axes as live ones, unknowns included, while `owed` already excludes
 * them. Counting them would withhold the all-clear over rows the queue is right
 * to omit, for as long as the done window holds them.
 */
function prCoverage(tiles: Tile[]): { rows: number; gaps: string[] } {
  const rows = tiles.filter((t) => isPRRow(t) && !t.closed_at);
  const gaps: string[] = [];
  const noPosition = rows.filter((t) => t.pr_machine === 'unknown').length;
  const noConversation = rows.filter((t) => t.pr_conversation === 'unknown').length;
  const noApproval = rows.filter((t) => t.pr_machine === 'settled' && t.pr_approval === 'unknown').length;
  if (noPosition > 0) {
    gaps.push(`${noPosition} of ${rows.length} have no position recorded by the merge cadence`);
  }
  if (noConversation > 0) {
    gaps.push(
      `${noConversation} cannot say where the conversation stands (the merge cadence has not recorded it)`,
    );
  }
  if (noApproval > 0) {
    gaps.push(`${noApproval} are green with no readable answer on whether GitHub wants a review`);
  }
  return { rows: rows.length, gaps };
}

// The pack-build strip: what each compiled component is serving, and whether it
// matches its sources.
//
// It sits above the anchors because it qualifies them. Nothing in the running
// system builds these binaries — the launchers exec what a build order
// published — so this very page can be rendered by a binary older than the
// sources that describe it, and every row below would look normal while doing
// it. Nothing else on the page can say so.
//
// Rows are unconditional whenever the city has any record at all: a strip that
// appears only on trouble is a strip nobody learns to read. A city with no
// record renders nothing rather than an invented all-clear.
function PackHealth({ rows }: { rows: PackBuild[] }) {
  if (rows.length === 0) return null;
  return (
    <section className="pack-health" aria-labelledby="pack-health-heading">
      <h2 id="pack-health-heading">pack builds</h2>
      <ul>
        {rows.map((row) => (
          <li key={row.component} className={`pack-health__row pack-health__row--${row.severity}`}>
            <span className="pack-health__sev">{row.severity}</span>
            <span className="pack-health__name">{row.component}</span>
            {/* `detail` is derived server-side so this view and the CLI cannot
                disagree about what a row means. Render it; never re-derive it. */}
            <span className="pack-health__detail">{row.detail}</span>
          </li>
        ))}
      </ul>
    </section>
  );
}

// The drill-in entry point, shared by every table. A button rather than a
// clickable row so it is reachable by keyboard and announced as an action.
function DrillOpen({
  id,
  label,
  onOpen,
}: {
  id: string;
  // What to show on the button. Defaults to the id; a caller passes the topic
  // (a subject's title) so a row reads as what it is about while still drilling
  // by id. The id stays reachable as the hover title whenever a label hides it.
  label?: string;
  onOpen: (id: string) => void;
}) {
  return (
    <button
      type="button"
      className="drill-open"
      onClick={() => onOpen(id)}
      title={label && label !== id ? id : undefined}
    >
      {label ?? id}
    </button>
  );
}

// A dependency family: the root anchor it hangs off, and the member tiles
// beneath it ordered by the move they want. Mirrors board.FamilyGroup in the Go
// layer.
type Family = { root: Tile; members: Tile[] };

// wantsPerson reports whether a row's next move is the operator's — the review
// and gate bands. The table marks these in place, with a ● in the band cell and
// a row highlight where the row already sits; it never reorders the board by
// them.
function wantsPerson(tile: Tile): boolean {
  return tile.section === 'review' || tile.section === 'gate';
}

// sectionRank is a section's position in SECTION_ORDER; an unknown one sorts
// after every known band, matching the derive layer's GroupByFamily.
function sectionRank(section: string): number {
  const i = SECTION_ORDER.indexOf(section as (typeof SECTION_ORDER)[number]);
  return i === -1 ? SECTION_ORDER.length : i;
}

// groupByFamily buckets the ranked list into dependency families by reading
// tile.group_root — the split the derive layer already made. Families read in
// the input's order (owed-first, so the oldest-owed family leads); within a
// family the root is the header and the members read in SECTION_ORDER. This is
// the TypeScript twin of board.GroupByFamily, kept trivial so the two cannot
// diverge: the hard decision — which root a tile climbs to — was made on the wire.
function groupByFamily(tiles: Tile[]): Family[] {
  const order: string[] = [];
  const members = new Map<string, Tile[]>();
  for (const tile of tiles) {
    const root = tile.group_root || tile.id;
    const bucket = members.get(root);
    if (bucket) bucket.push(tile);
    else {
      members.set(root, [tile]);
      order.push(root);
    }
  }
  return order.map((root) => {
    const fam = members.get(root)!;
    const rootTile = fam.find((t) => t.id === root) ?? fam[0];
    const rest = fam
      .filter((t) => t !== rootTile)
      .sort((a, b) => sectionRank(a.section) - sectionRank(b.section));
    return { root: rootTile, members: rest };
  });
}

// The "N/M" progress cell. "—" means the row owns no child set at all — a
// decision never does, and a human/parked bead does exactly when it decomposed
// — rather than a set that happens to be empty, which the counts would report
// as 0/0 (the tk-a9k0l distinction).
function progressCell(tile: Tile): string {
  if (tile.m_total === 0 && (tile.kind === 'decision' || tile.kind === 'human' || tile.kind === 'parked')) {
    return '—';
  }
  return `${tile.n_closed}/${tile.m_total}`;
}

// The whole board is ONE table. Dependency structure is its top-level axis: a
// family whose root has members renders that root as a group row leading a nested
// tree of its members; a single-item family renders as one plain row. `kind`
// carries which of the three a row is, `depth` how far it sits in its family tree
// (the root at 0), and `isParent` whether it heads a sub-group of its own.
type RowKind = 'group' | 'member' | 'loose';
type BoardRow = { tile: Tile; kind: RowKind; depth: number; isParent: boolean };

// flattenFamilies lays the grouped families out as the table's rows. A family
// with members leads with its root as a `group` row, then walks the containment
// tree the wire's `group_parent` edges describe — each member nested under its
// immediate parent and indented by its depth — so a sub-epic renders as a
// sub-group above its own children rather than as a flat sibling beside them. A
// root with no members stands alone as a `loose` row. Sibling order and family
// order are preserved from groupByFamily (owed families first, oldest first,
// members in SECTION_ORDER), so the board is never reordered by which rows want a
// person; nesting only regroups a family's rows under their parents.
function flattenFamilies(families: Family[]): BoardRow[] {
  const rows: BoardRow[] = [];
  for (const fam of families) appendFamilyTree(rows, fam);
  return rows;
}

// appendFamilyTree emits one family: its root, then its members as a depth-first
// pre-order walk of the containment tree. Each member climbs to the parent named
// by its `group_parent`; a member whose parent is empty, is itself, or names no
// tile in this family attaches directly under the family root, so a board that
// has not stamped `group_parent` degrades to a flat one-level list, and a
// malformed edge never drops a row. A cycle among members (only a malformed
// graph forms one) never reaches the root through the walk, so those
// members are appended under the root afterward.
function appendFamilyTree(rows: BoardRow[], { root, members }: Family): void {
  if (members.length === 0) {
    rows.push({ tile: root, kind: 'loose', depth: 0, isParent: false });
    return;
  }
  const inFamily = new Set<string>([root.id, ...members.map((m) => m.id)]);
  const childrenOf = new Map<string, Tile[]>();
  for (const m of members) {
    let parent = m.group_parent;
    if (!parent || parent === m.id || !inFamily.has(parent)) parent = root.id;
    const kids = childrenOf.get(parent);
    if (kids) kids.push(m);
    else childrenOf.set(parent, [m]);
  }
  const hasKids = (id: string): boolean => (childrenOf.get(id)?.length ?? 0) > 0;
  rows.push({ tile: root, kind: 'group', depth: 0, isParent: true });
  const visited = new Set<string>([root.id]);
  const walk = (parentId: string, depth: number): void => {
    for (const kid of childrenOf.get(parentId) ?? []) {
      if (visited.has(kid.id)) continue;
      visited.add(kid.id);
      rows.push({ tile: kid, kind: 'member', depth, isParent: hasKids(kid.id) });
      walk(kid.id, depth + 1);
    }
  };
  walk(root.id, 1);
  for (const m of members) {
    if (visited.has(m.id)) continue;
    visited.add(m.id);
    rows.push({ tile: m, kind: 'member', depth: 1, isParent: hasKids(m.id) });
  }
}

// visibleRows drops the rows beneath a collapsed parent. flattenFamilies emits a
// pre-order walk carrying each row's depth, so a collapsed parent's descendants
// are exactly the rows that follow it with a greater depth, up to the next row at
// its own depth or shallower. Filtering here — after the families are laid out —
// leaves family order, sibling order, and the owed-first partition untouched: a
// collapse hides rows, it never reorders them, so the #878/#911 ordering holds.
function visibleRows(rows: BoardRow[], collapsed: ReadonlySet<string>): BoardRow[] {
  const out: BoardRow[] = [];
  // The depth below which rows are hidden while inside a collapsed subtree.
  // Infinity hides nothing; a collapsed parent at depth d sets it to d, hiding
  // every deeper row until one at depth ≤ d resets it. A collapsed parent that
  // is itself hidden by a collapsed ancestor is skipped before it can widen the
  // window, so nested folds collapse under the shallowest one.
  let hideBelow = Infinity;
  for (const row of rows) {
    if (row.depth > hideBelow) continue;
    hideBelow = Infinity;
    out.push(row);
    if (row.isParent && collapsed.has(row.tile.id)) hideBelow = row.depth;
  }
  return out;
}

// descendantsByParent maps each parent id to the tiles beneath it at every level,
// read off the same pre-order row list by the same depth rule visibleRows uses.
// A summarizing header reads its subtree's shape and state from these so the
// operator can grasp a family without scanning each descendant — and, when the
// parent is collapsed, without any descendant row on screen at all.
function descendantsByParent(rows: BoardRow[]): Map<string, Tile[]> {
  const map = new Map<string, Tile[]>();
  for (let i = 0; i < rows.length; i++) {
    const parent = rows[i];
    if (!parent.isParent) continue;
    const kids: Tile[] = [];
    for (let j = i + 1; j < rows.length && rows[j].depth > parent.depth; j++) {
      kids.push(rows[j].tile);
    }
    map.set(parent.tile.id, kids);
  }
  return map;
}

// The attention shape of a subtree: how many descendants want the operator, and
// the spread across the attention bands in SECTION_ORDER. Both are read from the
// same wire fields a row renders — `owed` and `section` — so a header summarizes
// exactly what its rows say and never re-derives their state. Zero-count bands
// are dropped; the order is the table's own.
function summarizeSubtree(descendants: Tile[]): {
  owed: number;
  bands: { section: string; count: number }[];
} {
  let owed = 0;
  const counts = new Map<string, number>();
  for (const t of descendants) {
    if (t.owed) owed += 1;
    counts.set(t.section, (counts.get(t.section) ?? 0) + 1);
  }
  const bands = SECTION_ORDER.filter((s) => counts.has(s)).map((section) => ({
    section,
    count: counts.get(section) as number,
  }));
  return { owed, bands };
}

// The summarizing half of a parent header. The needs-you count is the one signal
// a collapse must never swallow, so it shows whenever the subtree has an owed
// descendant, folded or not — "unmissable yet calm": the board's own amber, a
// count, no klaxon. The per-band breakdown shows only when the parent is
// collapsed, because an expanded parent already has its rows below carrying it;
// folding the subtree is what makes the breakdown the only view of it.
function FamilySummary({ descendants, collapsed }: { descendants: Tile[]; collapsed: boolean }) {
  if (descendants.length === 0) return null;
  const { owed, bands } = summarizeSubtree(descendants);
  if (owed === 0 && !collapsed) return null;
  return (
    <span className="family-summary">
      {owed > 0 && (
        <span className="family-summary__owed">
          <span aria-hidden="true">● </span>
          {owed} need{owed === 1 ? 's' : ''} you
        </span>
      )}
      {collapsed && (
        <span className="family-summary__shape">
          {bands.map(({ section, count }) => (
            <span key={section} className="family-summary__band">
              {count} {section}
            </span>
          ))}
        </span>
      )}
    </span>
  );
}

// The visit marker: a visible, self-evident chip on a row an open visit holds. It
// says at a glance which of the two states the visit is in — PARKED (filed and
// waiting for the operator) or ENGAGED (a live sitting is in it right now) — in a
// word, a colour and an icon, read straight off tile.visit_state (derived once in
// the Go layer, never re-derived here). The chip is a real button so it is
// keyboard-reachable and announced as interactive; hovering or focusing it
// reveals a details card naming the sittings on the bead — each one's headline,
// its outcome or state, and the session to attach to. The details live in this
// card rather than a native `title` tooltip because a native tooltip has no
// visible affordance and stays invisible until an exact hover lands on a
// one-character glyph. The card is non-interactive text, so it needs no click
// to open or dismiss.
function VisitMarker({ tile, sittings }: { tile: Tile; sittings: Sitting[] }) {
  const engaged = tile.visit_state === VISIT_ENGAGED;
  const word = engaged ? 'in session' : 'waiting';
  const heading = engaged ? 'In session — being worked right now' : 'Parked — waiting for you';
  const label = engaged
    ? 'visit in session — a live conversation is on this row now; hover or focus for details'
    : 'visit parked — waiting for you; hover or focus for details';
  const cardId = `visit-card-${tile.id}`;
  return (
    <span className={`visit-marker visit-marker--${engaged ? 'engaged' : 'parked'}`}>
      <button type="button" className="visit-chip" aria-label={label} aria-describedby={cardId}>
        <span className="visit-chip__icon" aria-hidden="true">
          {engaged ? '◉' : '○'}
        </span>
        <span className="visit-chip__text">visit · {word}</span>
      </button>
      {/* Non-interactive detail, revealed on hover or focus of the chip (CSS).
          role=tooltip + aria-describedby hands the same text to a screen reader
          as the button's description, so the details are reachable without a
          pointer. */}
      <span role="tooltip" id={cardId} className="visit-card">
        <span className="visit-card__heading">{heading}</span>
        {sittings.length > 0 ? (
          sittings.map((s) => (
            <span key={s.id} className="visit-card__sitting">
              {sittingHeadline(s)}
              <span className="visit-card__meta">
                {' · '}
                {s.outcome || (isRunning(s) ? 'running' : 'closed')}
                {s.session ? ` · ${s.session}` : ''}
              </span>
            </span>
          ))
        ) : (
          <span className="visit-card__meta">an open visit holds this row</span>
        )}
      </span>
    </span>
  );
}

// The leading markers on a row. wants-person is a person's next move (review or
// gate); it is already spelled by the band word and the row tint, so its ● stays
// a decorative echo. A visit is the other signal, and the two co-occur — a review
// row a conversation is holding — so they render side by side rather than
// collapsing into one glyph: the ● first, then the visit chip that carries the
// state and the details.
function RowMarker({ tile, sittings }: { tile: Tile; sittings: Sitting[] }) {
  return (
    <>
      {wantsPerson(tile) && (
        <span className="wants-person" aria-hidden="true">
          ●{' '}
        </span>
      )}
      {tile.held && <VisitMarker tile={tile} sittings={sittings} />}
    </>
  );
}

// One row of the unified table. Every row carries the same columns; the grouping
// treatment reads from the row shape (a row that heads a group — the family root
// or a nested sub-epic — leads with a disclosure control, a header title, and a
// summary of its subtree, and every row is indented by its depth in the family
// tree) and the attention highlight rides the row in place: a ● and a tint where
// a row's next move is the operator's (wantsPerson), a tint on a row an open
// visit is holding (held).
function AnchorRow({
  row,
  drilled,
  onOpen,
  onActuated,
  sittingsBySubject,
  descendants,
  collapsed,
  onToggleCollapse,
}: {
  row: BoardRow;
  drilled: boolean;
  onOpen: (id: string) => void;
  // Called after a board write lands, so the acted-on row re-gathers rather than
  // waiting out the poll interval. App passes its refresh.
  onActuated: () => void;
  // The sittings on each bead, keyed by subject id, for the per-row visit hover.
  sittingsBySubject: Map<string, Sitting[]>;
  // This row's subtree tiles (empty for a leaf), for the header summary.
  descendants: Tile[];
  // Whether this parent is folded. Meaningless on a leaf, which never collapses.
  collapsed: boolean;
  // Fold or unfold this parent's subtree.
  onToggleCollapse: (id: string) => void;
}) {
  const { tile, kind, depth, isParent } = row;
  const person = wantsPerson(tile);
  const className =
    [
      `row-${kind}`,
      person ? 'row-wants-person' : '',
      tile.held ? 'row-held' : '',
      tile.section === 'done' ? 'row-done' : '',
      drilled ? 'drilled' : '',
    ]
      .filter(Boolean)
      .join(' ') || undefined;
  return (
    <tr className={className}>
      <td>
        <RowMarker tile={tile} sittings={sittingsBySubject.get(tile.id) ?? []} />
        <span className="band">{tile.section}</span>
      </td>
      <td>
        <DrillOpen id={tile.id} onOpen={onOpen} />
      </td>
      <td>{tile.rig}</td>
      <td>{tile.kind}</td>
      <td>
        <PRPhaseChip tile={tile} />
        <PRLink tile={tile} />
      </td>
      <td className="title-cell" style={{ '--depth': depth } as CSSProperties}>
        {isParent ? (
          <span className="title-lead">
            {/* The one navigable affordance that makes a parent a header, not an
                indented title: a real button so it is keyboard-reachable and
                announced with its expanded state. It folds the subtree below it;
                the summary beside it is what the fold leaves legible. */}
            <button
              type="button"
              className="disclosure"
              aria-expanded={!collapsed}
              aria-label={`${collapsed ? 'expand' : 'collapse'} ${tile.title}`}
              onClick={() => onToggleCollapse(tile.id)}
            >
              <span className="disclosure__icon" aria-hidden="true">
                {collapsed ? '▸' : '▾'}
              </span>
            </button>
            <span className="family-title">{tile.title}</span>
            <FamilySummary descendants={descendants} collapsed={collapsed} />
          </span>
        ) : (
          <span className="title-lead">
            {/* A leaf cannot fold, but it reserves the disclosure's width so its
                title lines up under its siblings' rather than shifting left. */}
            <span className="disclosure disclosure--leaf" aria-hidden="true" />
            {tile.title}
          </span>
        )}
      </td>
      <td>{progressCell(tile)}</td>
      <td>{tile.frontier}</td>
      <td>
        {tile.needs}
        {/* Accept is the one board-row actuation, mirroring the CLI board's
            "accept ▸" marker (cmd/helm-svc/board.go). It shows only when the wire
            says the row is acceptable — a recommendation whose visit is un-engaged
            — and dispatches accept_formula at the subject then dismisses the visit.
            Discuss and Dismiss live in the drill panel, the way the CLI keeps them
            as separate verbs off the marked row. */}
        {tile.acceptable && (
          <>
            {' '}
            <ActuateButton
              verb="accept"
              beadId={tile.id}
              formula={tile.accept_formula}
              compact
              onDone={onActuated}
            />
          </>
        )}
        {/* The card behind the Accept — the Proposal and Decision-needed an
            operator weighs — folded into a disclosure so the row stays a
            one-line scan until opened at the decision point. The wire carries it
            only on an acceptable row, so its presence is the gate. */}
        {tile.recommendation && (
          <details className="recommendation">
            <summary>recommendation</summary>
            <pre>{tile.recommendation}</pre>
          </details>
        )}
      </td>
      <td>{tile.section === 'done' ? '' : owedSince(tile)}</td>
    </tr>
  );
}

// A compact, always-visible key for the row markers and the state tints, so the
// glyphs and colours the table spends are legible without hunting for what they
// mean. It states what each mark MEANS and reuses the classes the rows use, so a
// sample cannot drift from the thing it explains.
function Legend() {
  return (
    <p className="legend" aria-label="key to the row markers and tints">
      <span className="legend__title">key</span>
      <span className="legend__item">
        <span className="wants-person" aria-hidden="true">
          ●
        </span>{' '}
        needs you
      </span>
      <span className="legend__item">
        <span className="visit-marker--parked" aria-hidden="true">
          ○
        </span>{' '}
        visit waiting for you
      </span>
      <span className="legend__item">
        <span className="visit-marker--engaged" aria-hidden="true">
          ◉
        </span>{' '}
        visit in session
      </span>
      <span className="legend__item">
        <span className="legend__swatch legend__swatch--wants" aria-hidden="true" /> row needs you
      </span>
      <span className="legend__item">
        <span className="legend__swatch legend__swatch--held" aria-hidden="true" /> a visit holds it
      </span>
      <span className="legend__item legend__item--done">closed rows dimmed</span>
    </p>
  );
}

// The board as one table. A closed row keeps its place below the live ones and
// leaves only by ageing out on the window clock, so the note under the table
// states that bound once for every DONE row rather than repeating it per family.
function AnchorsTable({
  rows,
  drillTarget,
  onOpen,
  onActuated,
  sittingsBySubject,
  descByParent,
  collapsed,
  onToggleCollapse,
  anyCollapsed,
  onExpandAll,
}: {
  rows: BoardRow[];
  drillTarget: string | null;
  onOpen: (id: string) => void;
  onActuated: () => void;
  sittingsBySubject: Map<string, Sitting[]>;
  // Each parent's subtree tiles, for the header summaries.
  descByParent: Map<string, Tile[]>;
  // The folded parents; a row is collapsed when its id is in here.
  collapsed: ReadonlySet<string>;
  onToggleCollapse: (id: string) => void;
  // Whether any parent is folded, so the escape hatch shows only when it can act.
  anyCollapsed: boolean;
  onExpandAll: () => void;
}) {
  if (rows.length === 0) return null;
  const hasDone = rows.some((r) => r.tile.section === 'done');
  return (
    <section className="anchors" aria-labelledby="anchors-heading">
      <h2 id="anchors-heading">anchors</h2>
      {/* The one global control: unfold everything, so a row folded away and
          forgotten is always one click from view. Shown only when something is
          folded — a board with nothing collapsed has nothing to expand. */}
      {anyCollapsed && (
        <button type="button" className="expand-all" onClick={onExpandAll}>
          expand all
        </button>
      )}
      <Legend />
      <table>
        <thead>
          <tr>
            <th>band</th>
            <th>id</th>
            <th>rig</th>
            <th>kind</th>
            <th>pr</th>
            <th>title</th>
            <th>progress</th>
            <th>frontier</th>
            <th>needs</th>
            <th>owed since</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <AnchorRow
              key={row.tile.id}
              row={row}
              drilled={row.tile.id === drillTarget}
              onOpen={onOpen}
              onActuated={onActuated}
              sittingsBySubject={sittingsBySubject}
              descendants={descByParent.get(row.tile.id) ?? []}
              collapsed={collapsed.has(row.tile.id)}
              onToggleCollapse={onToggleCollapse}
            />
          ))}
        </tbody>
      </table>
      {hasDone && (
        <p className="sub anchors-note">
          A closed row keeps its place below the live ones and leaves only by ageing out, once it
          has been closed longer than <code>GC_HELM_DONE_WINDOW</code> (default 7d, <code>0</code>{' '}
          off).
        </p>
      )}
    </section>
  );
}

// The conversation record: what is being talked about right now, and what the
// sittings that just ended concluded.
//
// A section rather than rows in a ranked table: a sitting is an event, not a
// demand, and ranking it against a stranded epic would be answering a question
// nobody asked. The bands say what needs doing; this says what is being said.
function Sittings({ sittings, now, onOpen }: { sittings: Sitting[]; now: number; onOpen: (id: string) => void }) {
  if (sittings.length === 0) return null;
  const running = sittings.filter(isRunning).length;

  return (
    <section className="sittings" aria-labelledby="sittings-heading">
      <h2 id="sittings-heading">converse sittings</h2>
      <p className="sub">
        {running} running · {sittings.length - running} closed recently. A running sitting is a
        conversation someone is still in; a closed one shows the outcome it closed on, and a
        running one shows an outcome only when a board dismissal stamped it without closing the
        visit. The takeaway shows on the sitting that wrote it.
      </p>
      <table>
        <thead>
          <tr>
            <th>state</th>
            <th>sitting</th>
            <th>rig</th>
            <th>subject</th>
            <th>age</th>
            <th>outcome</th>
            <th>headline</th>
          </tr>
        </thead>
        <tbody>
          {sittings.map((s) => {
            const live = isRunning(s);
            return (
              <tr key={s.id} className={live ? 'sitting-running' : undefined}>
                <td>{live ? 'running' : 'closed'}</td>
                <td>{s.id}</td>
                <td>{s.rig}</td>
                <td>
                  {/* The subject is an anchor, so it drills in like any tile id;
                      the label is its title (the topic) so the row says what it
                      is about, falling back to the id when the title is unread. */}
                  <DrillOpen id={s.subject} label={s.subject_title || s.subject} onOpen={onOpen} />
                </td>
                <td>{shortAge(live ? s.opened_at : s.closed_at, now)}</td>
                {/* A running sitting usually has no outcome, and the em dash is
                    that absence rather than an empty string. The exception is a
                    board dismissal that stamped gc.outcome but could not close
                    the visit: it leaves a running row honestly reading
                    "dismissed", the signal that the sitting is stuck open and
                    needs a manual close. */}
                <td>{s.outcome || '—'}</td>
                {/* The takeaway is what the sitting concluded; with none, a
                    dedup close shows its outcome reason (why it closed), then
                    the subject's title (the topic) rather than the visit bead's
                    own generic title, which says nothing. */}
                <td>{sittingHeadline(s)}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </section>
  );
}

// The collapsed set as last persisted. A missing or unreadable value is an empty
// set — every parent expanded — because the safe default of this board is to
// hide nothing: a storage that cannot be read must not fold a subtree the
// operator never folded. Malformed entries are dropped rather than trusted.
function loadCollapsed(): Set<string> {
  try {
    const raw = window.localStorage.getItem(COLLAPSE_STORAGE_KEY);
    if (!raw) return new Set();
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return new Set();
    return new Set(parsed.filter((x): x is string => typeof x === 'string'));
  } catch {
    return new Set();
  }
}

// Persist the collapsed set. A storage that refuses — private mode, quota, no
// localStorage at all — just means the fold does not outlive this session; the
// in-memory state still drives the view, so the write failing is silent by
// design rather than an error the operator must see.
function persistCollapsed(ids: ReadonlySet<string>): void {
  try {
    window.localStorage.setItem(COLLAPSE_STORAGE_KEY, JSON.stringify([...ids]));
  } catch {
    // Intentionally ignored; see the doc comment above.
  }
}

export function App() {
  const [board, setBoard] = useState<Board | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [reloadToken, setReloadToken] = useState(0);
  // The tile being drilled into, or null. A tile's id IS a bead id, which is
  // all the drill plane needs to open it.
  const [drillTarget, setDrillTarget] = useState<string | null>(() =>
    resolveDrillTarget(window.location.search),
  );
  // The rig the operator narrowed the view to, or '' for all rigs.
  const [rigFilter, setRigFilter] = useState<string>('');
  // The folded parents, seeded from storage so a fold survives a refresh and the
  // next visit. Every write goes through the two setters below, which keep
  // storage in step, so the board never persists a set it is not showing.
  const [collapsed, setCollapsed] = useState<Set<string>>(() => loadCollapsed());

  const refresh = useCallback(() => setReloadToken((n) => n + 1), []);

  const toggleCollapse = useCallback((id: string) => {
    setCollapsed((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      persistCollapsed(next);
      return next;
    });
  }, []);

  const expandAll = useCallback(() => {
    setCollapsed(() => {
      const next = new Set<string>();
      persistCollapsed(next);
      return next;
    });
  }, []);

  // Read once: these overrides are launch-time knobs, and re-reading them on
  // every render would tear the terminal down whenever the board refreshes.
  const terminalBase = useMemo(() => resolveTerminalBase(window.location.search), []);
  const terminalSession = useMemo(() => resolveTerminalSession(window.location.search), []);

  useEffect(() => {
    const controller = new AbortController();
    setLoading(true);
    fetchBoard(controller.signal)
      .then((next) => {
        setBoard(next);
        setError(null);
      })
      .catch((err: unknown) => {
        if (controller.signal.aborted) return;
        setError(err instanceof Error ? err.message : String(err));
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });
    return () => controller.abort();
  }, [reloadToken]);

  useEffect(() => {
    const timer = window.setInterval(refresh, REFRESH_MS);
    return () => window.clearInterval(timer);
  }, [refresh]);

  const tiles = board?.tiles ?? [];
  const sittings = board?.sittings ?? [];

  // The rig filter is a client-side view over rows the board already carries:
  // every tile and sitting names its rig, so the options are those names and
  // selecting one narrows what renders. It does not re-gather and does not touch
  // the cross-rig completeness signal — `board.partial` is a fact about the
  // whole city and stays whole below, so a one-rig view never reads as an
  // all-clear the city has not earned.
  const rigOptions = useMemo(() => {
    const names = new Set<string>();
    for (const t of tiles) if (t.rig) names.add(t.rig);
    for (const s of sittings) if (s.rig) names.add(s.rig);
    return [...names].sort();
  }, [tiles, sittings]);
  // A selection the current board no longer offers falls back to all rigs, so a
  // rig ageing off the board cannot strand the view on an empty filter.
  const effectiveRig = rigFilter && rigOptions.includes(rigFilter) ? rigFilter : '';
  const visibleTiles = useMemo(
    () => (effectiveRig ? tiles.filter((t) => t.rig === effectiveRig) : tiles),
    [tiles, effectiveRig],
  );
  const visibleSittings = effectiveRig ? sittings.filter((s) => s.rig === effectiveRig) : sittings;

  // Sitting ages are measured from the board's OWN generated_at, so a tab left
  // open does not age every row past what the gather actually saw. A board
  // without a readable stamp falls back to the wall clock.
  const renderedAt = useMemo(() => {
    const t = board ? Date.parse(board.generated_at) : NaN;
    return Number.isNaN(t) ? Date.now() : t;
  }, [board]);

  // Group the visible rows into dependency families by reading tile.group_root —
  // the split the derive layer already made. The wire order (owed rows first,
  // oldest first) is preserved, so the oldest-owed family leads; within a family
  // the members read in SECTION_ORDER.
  const families = useMemo(() => groupByFamily(visibleTiles), [visibleTiles]);
  // The one table's rows: each family flattened to a group row plus indented
  // members, or a single loose row. The grouping split is groupByFamily's; this
  // only shapes it for the table.
  const boardRows = useMemo(() => flattenFamilies(families), [families]);
  // Each parent's subtree, derived from the full row list before any fold, so a
  // collapsed header still summarizes the descendants it is hiding.
  const descByParent = useMemo(() => descendantsByParent(boardRows), [boardRows]);
  // The rows actually rendered: the full list minus anything under a folded
  // parent. Order is untouched — this filters, never reorders.
  const visibleBoardRows = useMemo(() => visibleRows(boardRows, collapsed), [boardRows, collapsed]);
  // Whether any CURRENTLY-SHOWN parent is folded, so the expand-all escape hatch
  // appears only when it would do something. A stale id left in the set by a
  // parent that has since left the board does not count.
  const anyCollapsed = useMemo(
    () => boardRows.some((r) => r.isParent && collapsed.has(r.tile.id)),
    [boardRows, collapsed],
  );

  // Sittings keyed by the bead they are about, so each row shows the visit(s)
  // holding it without re-scanning the list per row. Keyed off the full sittings
  // list, not the rig-filtered one, so a shown row always finds its own.
  const sittingsBySubject = useMemo(() => {
    const bySubject = new Map<string, Sitting[]>();
    for (const s of sittings) {
      const list = bySubject.get(s.subject);
      if (list) list.push(s);
      else bySubject.set(s.subject, [s]);
    }
    return bySubject;
  }, [sittings]);

  const owed = visibleTiles.filter((t) => t.owed);
  const coverage = prCoverage(visibleTiles);
  // Live rows are everything but the DONE band — what "needs attention" counts.
  const liveCount = visibleTiles.filter((t) => t.section !== 'done').length;
  const doneCount = visibleTiles.length - liveCount;
  // The rows that are live and NOT already in the owed cover-sheet's count.
  // "No other anchors need attention" is a claim about these, not about a board
  // whose only live rows are the ones the queue just named.
  const otherLive = visibleTiles.filter((t) => !t.owed && t.section !== 'done');

  return (
    <main>
      <header>
        <h1>helm</h1>
        <p className="sub">
          {board
            ? `${owed.length ? `${owed.length} owed · ` : ''}${liveCount} anchors${
                doneCount ? ` · ${doneCount} closed` : ''
              } · generated ${board.generated_at}`
            : loading
              ? 'loading the board…'
              : 'no board'}
        </p>
        <button type="button" onClick={refresh} disabled={loading}>
          {loading ? 'refreshing…' : 'refresh'}
        </button>
        {/* Offered only when there is more than one rig to choose between; a
            single-rig city has nothing to filter. This narrows the view, not
            the gather — the partial-board signal below is unchanged by it. */}
        {rigOptions.length > 1 && (
          <p className="rig-filter">
            <label htmlFor="rig-filter">filter by rig</label>{' '}
            <select
              id="rig-filter"
              value={effectiveRig}
              onChange={(event) => setRigFilter(event.currentTarget.value)}
            >
              <option value="">all rigs</option>
              {rigOptions.map((name) => (
                <option key={name} value={name}>
                  {name}
                </option>
              ))}
            </select>
          </p>
        )}
        <CitySignals />
      </header>

      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}

      {board?.partial && (
        <p className="warn" role="status">
          Partial board — some rigs did not answer
          {board.partial_errors?.length ? `: ${board.partial_errors.join('; ')}` : '.'}
        </p>
      )}

      {/* The queue status, and the only section that renders unconditionally.
          "Nothing is owed by you" is the most consequential sentence on this
          page and it is also what every failure path produces by default, so
          this states its COVERAGE or states the error — never a blank space
          that reads as an all-clear nobody earned. The owed ROWS themselves
          are in the review and gate bands below, oldest-owed first; this
          section is the queue's cover sheet, not a second copy of it. */}
      <section className="owed" aria-labelledby="owed-heading">
        <h2 id="owed-heading">owed by you</h2>
        {!board ? (
          <p className="sub" role="status">
            {error
              ? 'The board could not be read, so nothing here is proven clear.'
              : 'reading the board…'}
          </p>
        ) : owed.length === 0 ? (
          <p className="sub" role="status">
            {board.partial
              ? 'Nothing is owed by you — but some rigs did not answer, so this is not an all-clear.'
              : coverage.gaps.length > 0
                ? `Nothing readable is owed by you — but this is NOT an all-clear. Every store answered; of ${coverage.rows} pull requests, ${coverage.gaps.join('; ')}.`
                : coverage.rows > 0
                  ? `Nothing is owed by you. Every store answered; ${coverage.rows} pull requests read, all with a position.`
                  : 'Nothing is owed by you. Every store answered.'}
          </p>
        ) : (
          <p className="sub" role="status">
            {owed.length} owed by you, oldest first — in the review and gate bands below.
          </p>
        )}
      </section>

      <PackHealth rows={board?.pack_health ?? []} />

      {board && otherLive.length === 0 && !error && (
        <p>{owed.length > 0 ? 'No other anchors need attention.' : 'No anchors need attention.'}</p>
      )}

      <AnchorsTable
        rows={visibleBoardRows}
        drillTarget={drillTarget}
        onOpen={setDrillTarget}
        onActuated={refresh}
        sittingsBySubject={sittingsBySubject}
        descByParent={descByParent}
        collapsed={collapsed}
        onToggleCollapse={toggleCollapse}
        anyCollapsed={anyCollapsed}
        onExpandAll={expandAll}
      />

      <Sittings sittings={visibleSittings} now={renderedAt} onOpen={setDrillTarget} />

      {/* One terminal, not one per anchor — and that is now a LAYOUT decision,
          not a wiring limit. The city still runs a single ttyd, but its attach
          target is chosen per connection (`?arg=`, tk-rbf9r) rather than baked
          into the systemd unit, so this tile can be pointed at any live session
          and `?session=` does exactly that. What remains open is how many
          terminals a board should show and how they are arranged, which is the
          design handoff on tk-mw9qz — see the Terminal section of
          services/helm/README.md.

          What is deliberately NOT wired here is drill-target -> session: the
          board contract carries no session for a tile (contract.ts), and
          inventing a name from a bead's rig would be a guess that the guard
          would then refuse. Naming that mapping is part of tk-mw9qz. */}
      <TerminalTile
        label={terminalSession ?? 'city terminal'}
        base={terminalBase}
        session={terminalSession}
      />
      <DrillPanel beadId={drillTarget} onClose={() => setDrillTarget(null)} />
    </main>
  );
}
