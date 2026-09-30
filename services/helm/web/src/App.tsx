import { useCallback, useEffect, useMemo, useState } from 'react';
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

// A sitting is finished when its visit bead closed; anything else is a
// conversation someone is still in. Reading the status rather than the presence
// of closed_at keeps a sitting whose stamp could not be read on the running
// side, which is the side that shows a row rather than hides one.
const isRunning = (s: Sitting): boolean => s.status !== 'closed';

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
 * The phase indicator: who must act on this merge anchor next, in the same three
 * values the GitHub status: label carries. A colored chip so the answer reads at
 * a glance; nothing rendered on a row with no phase.
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
      `${noConversation} cannot say where the conversation stands (the acknowledgement watermarks are not built yet)`,
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
// family whose root has members renders that root as a group row with its
// members indented one level beneath it; a single-item family renders as one
// plain row. `kind` carries which of the three a row is.
type RowKind = 'group' | 'member' | 'loose';
type BoardRow = { tile: Tile; kind: RowKind };

// flattenFamilies lays the grouped families out as the table's rows: a root with
// members leads its family as a `group` row and its members follow as `member`
// rows; a root with none stands alone as a `loose` row. The order is preserved
// from groupByFamily, which preserved it from the wire — owed families first,
// oldest first, members in SECTION_ORDER — so the board is never reordered by
// which rows want a person.
function flattenFamilies(families: Family[]): BoardRow[] {
  const rows: BoardRow[] = [];
  for (const { root, members } of families) {
    if (members.length > 0) {
      rows.push({ tile: root, kind: 'group' });
      for (const m of members) rows.push({ tile: m, kind: 'member' });
    } else {
      rows.push({ tile: root, kind: 'loose' });
    }
  }
  return rows;
}

// One row of the unified table. Every row carries the same columns; `kind` sets
// the grouping treatment (a group row's title reads as a header; a member's is
// indented one level) and the attention highlight rides the row in place: a ●
// and a tint where a row's next move is the operator's (wantsPerson), a tint on
// a row an open visit is holding (held).
function AnchorRow({
  row,
  drilled,
  onOpen,
  onActuated,
}: {
  row: BoardRow;
  drilled: boolean;
  onOpen: (id: string) => void;
  // Called after a board write lands, so the acted-on row re-gathers rather than
  // waiting out the poll interval. App passes its refresh.
  onActuated: () => void;
}) {
  const { tile, kind } = row;
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
        {person && (
          <span className="wants-person" aria-hidden="true">
            ●{' '}
          </span>
        )}
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
      <td className="title-cell">
        {kind === 'group' ? <span className="family-title">{tile.title}</span> : tile.title}
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
      </td>
      <td>{tile.section === 'done' ? '' : owedSince(tile)}</td>
    </tr>
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
}: {
  rows: BoardRow[];
  drillTarget: string | null;
  onOpen: (id: string) => void;
  onActuated: () => void;
}) {
  if (rows.length === 0) return null;
  const hasDone = rows.some((r) => r.tile.section === 'done');
  return (
    <section className="anchors" aria-labelledby="anchors-heading">
      <h2 id="anchors-heading">anchors</h2>
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
                <td>{s.takeaway || s.outcome_reason || s.subject_title || s.title}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </section>
  );
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

  const refresh = useCallback(() => setReloadToken((n) => n + 1), []);

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
        rows={boardRows}
        drillTarget={drillTarget}
        onOpen={setDrillTarget}
        onActuated={refresh}
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
