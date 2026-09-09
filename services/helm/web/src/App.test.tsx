import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { App } from './App';
import type { Board, PackBuild, Sitting, Tile } from './contract';

// The board arrives as one ranked list; every row carries the attention BAND it
// belongs to in `tile.section` (and, when it is one of several sharing a
// template, `tile.cluster_key`). The app groups by reading those fields — it
// never re-derives the split — so these fixtures set `section` the way the
// derive layer would, and the tests address each band by its heading.
function tile(over: Partial<Tile> & Pick<Tile, 'id' | 'kind' | 'title' | 'severity'>): Tile {
  return {
    rig: 'gc-toolkit',
    owed: false,
    weight: 0,
    held: false,
    n_closed: 0,
    m_total: 0,
    open: 0,
    in_progress: 0,
    assigned: 0,
    in_progress_live: 0,
    in_progress_dead: 0,
    dead_owner: false,
    in_flight: 0,
    in_flight_heads: [],
    owned: null,
    stranded: false,
    empty: false,
    complete: false,
    progress_mismatch: false,
    stale_days: 0,
    priority: null,
    cross_rig_refs: [],
    open_heads: [],
    dead_owner_heads: [],
    parked_heads: [],
    waiting_on: [],
    waiting_on_open: [],
    disposition_due: false,
    takeaway: null,
    takeaway_at: null,
    takeaway_by: null,
    frontier: '',
    needs: '',
    rank_score: 0,
    // A row that is not a merge anchor: EMPTY axes, not 'unknown'. "Not a pull
    // request" and "a pull request whose position could not be read" are
    // different answers, and only the second is a gap in coverage.
    pr_number: 0,
    pr_url: '',
    pr_branch: '',
    pr_machine: '',
    pr_conversation: '',
    pr_approval: '',
    section: 'active',
    ...over,
  };
}

/**
 * A merge anchor row, as the board derives one: it bands `review` whatever the
 * cadence recorded. The default is the shape that put this surface in the
 * backlog — wedged at the convergence cap's park, with no pull request open.
 */
function prTile(over: Partial<Tile> & Pick<Tile, 'id'>): Tile {
  return tile({
    kind: 'human',
    title: 'a merge anchor',
    severity: 'ELEVATED',
    owed: true,
    section: 'review',
    pr_branch: `polecat/${over.id}`,
    pr_machine: 'wedged-exception',
    pr_conversation: 'unknown',
    pr_approval: 'unknown',
    pr_owed_since: '2026-08-08T11:02:00Z',
    needs: 'wedged: the review cap parked this anchor — a ruling releases it, a new commit does not',
    ...over,
  });
}

// The two halves of the conversation record: one sitting still running, one
// closed with the outcome and the takeaway it left.
const SITTINGS: Sitting[] = [
  {
    id: 'tk-vst01',
    rig: 'gc-toolkit',
    subject: 'tk-epic',
    title: 'visit: tk-epic — what the canvas owes the operator',
    status: 'in_progress',
    outcome: '',
    session: 'gc-toolkit__converse-1',
    opened_at: '2026-08-21T18:34:00Z',
    takeaway: '',
  },
  {
    id: 'tk-vst02',
    rig: 'gc-toolkit',
    subject: 'tk-yps55',
    title: 'visit: tk-yps55 — the raw script path',
    status: 'closed',
    outcome: 'diagnosed',
    session: 'gc-toolkit__converse-2',
    opened_at: '2026-08-21T17:20:00Z',
    closed_at: '2026-08-21T17:54:00Z',
    takeaway: 'the path was the launcher’s, not the board’s',
  },
];

const BOARD: Board = {
  generated_at: '2026-08-21T19:14:00Z',
  total: 6,
  sittings: SITTINGS,
  tiles: [
    // Owed rows lead the wire (contract.ts), so the fixture is in wire order.
    // A bead a person owes with no question recorded → the gate band.
    tile({
      id: 'tk-jgq6s',
      kind: 'human',
      title: 'Disposition: 1 anchorless open PR remains (#88)',
      severity: 'ELEVATED',
      owed: true,
      section: 'gate',
      takeaway_at: '2026-07-04T09:00:00Z',
      frontier: 'routed to the operator — no agent will take it',
      needs: 'routed to you — no question recorded',
      rank_score: 2_003_011,
    }),
    // A stranded epic → the stalled band.
    tile({
      id: 'tk-epic',
      kind: 'epic',
      title: 'Attention Canvas',
      severity: 'HIGH',
      m_total: 2,
      open: 2,
      stranded: true,
      section: 'stalled',
      frontier: '2 open · 0 in-progress (stranded)',
      needs: 'decomposed, idle — assign or visit',
      rank_score: 3_005_003,
    }),
    // A quiet parked conversation → the cleanup band.
    tile({
      id: 'tk-yps55',
      kind: 'parked',
      title: "gc-toolkit's helm returns the raw script path",
      severity: 'LOW',
      section: 'cleanup',
      frontier: 'conversation parked — no takeaway recorded',
      needs: 'parked for you — no question recorded',
      rank_score: 2_001,
    }),
    // Parked by kind, but the work it was waiting on has closed — it owes a
    // disposition now, so the derive layer marks it owed and bands it gate.
    tile({
      id: 'tk-dispo',
      kind: 'parked',
      title: 'routed — fix+guard ruled, nothing further needed here',
      severity: 'ELEVATED',
      owed: true,
      section: 'gate',
      waiting_on: ['tk-hgmob'],
      waiting_on_open: [],
      disposition_due: true,
      frontier: 'parked · blocker landed',
      needs: 'blocker landed — dispose or resume',
      rank_score: 2_002_001,
    }),
    // Parked by kind, and the work the sitting routed is its own OPEN child, so
    // the subject is not quiet — the roll-up strands it into the stalled band.
    tile({
      id: 'tk-z9nln',
      kind: 'parked',
      title: 'audit the gc-toolkit workflow and write the composition-seam doc',
      severity: 'HIGH',
      n_closed: 1,
      m_total: 2,
      open: 1,
      stranded: true,
      section: 'stalled',
      open_heads: ['tk-wvrga'],
      frontier: '1 open · 0 in flight (stranded)',
      needs: 'kept open as the seat for the strategic conversation',
      rank_score: 3_005_000,
    }),
    // A parked subject whose own bead has CLOSED → the done band, kept off every
    // live band even though it is `parked` by kind.
    tile({
      id: 'tk-9tbbk',
      kind: 'parked',
      title: 'the takeaway cap conversation',
      severity: 'DONE',
      section: 'done',
      closed_at: '2026-08-20T19:14:00Z',
      frontier: 'closed 1d ago',
      needs: 'closed — ages out',
      rank_score: -999_002,
    }),
  ],
};

beforeEach(() => {
  // The board read is the only request this test answers. The terminal tile
  // probes its endpoint on mount and the drill plane has no provider here, so
  // everything else is deliberately a 404 — neither is what is under test.
  vi.stubGlobal(
    'fetch',
    vi.fn(async (input: RequestInfo | URL) => {
      const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
      if (new URL(url, 'http://localhost/').pathname.endsWith('/helm')) {
        return new Response(JSON.stringify(BOARD), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      }
      return new Response('{}', { status: 404, headers: { 'Content-Type': 'application/json' } });
    }),
  );
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

// Address each band by its heading, never by position.
const band = (name: string): HTMLElement => screen.getByRole('region', { name });
const queryBand = (name: string): HTMLElement | null => screen.queryByRole('region', { name });
const owedCover = (): HTMLElement => screen.getByRole('region', { name: 'owed by you' });

// A bead a person owes reaches the board (before tk-2v08m a gather keyed on
// issue type could not see `gc.routed_to=human` on a task), and it surfaces in
// the gate band — one of the two bands the operator's queue leads with — rather
// than buried in a flat rank under every container.
it('surfaces the operator-owned bead in the gate band', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/anchorless open PR/)).toBeTruthy());

  const row = within(band('gate')).getByText(/anchorless open PR/).closest('tr');
  expect(row).not.toBeNull();
  expect(within(row as HTMLElement).getByText('routed to you — no question recorded')).toBeTruthy();
  expect(within(row as HTMLElement).getByText('2026-07-04')).toBeTruthy();

  // It is in the gate band, not the stalled overview; the stranded epic it
  // would outrank nowhere leads that band instead.
  expect(within(band('stalled')).queryByText(/anchorless open PR/)).toBeNull();
  expect(within(band('stalled')).getByText('Attention Canvas')).toBeTruthy();
});

// The bands read in a fixed order: the operator's own moves (review, gate)
// before the city's health (stalled, active) before the quiet tail.
it('orders the bands review, gate, stalled', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText('Attention Canvas')).toBeTruthy());

  const regions = screen.getAllByRole('region').map((r) => r.getAttribute('aria-labelledby'));
  const gate = regions.indexOf('section-gate');
  const stalled = regions.indexOf('section-stalled');
  expect(gate).toBeGreaterThanOrEqual(0);
  expect(stalled).toBeGreaterThan(gate);
});

// The never-blank contract. "Nothing is owed by you" is this page's most
// consequential sentence and the default output of every failure path, so the
// cover-sheet states its coverage or states the error — it is never empty.
it('states its coverage when nothing is owed', async () => {
  const nothingOwed: Board = { ...BOARD, total: 1, tiles: [BOARD.tiles![1]] };
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => new Response(JSON.stringify(nothingOwed), { status: 200 })),
  );

  render(<App />);
  await waitFor(() => expect(screen.getByText('Attention Canvas')).toBeTruthy());
  expect(within(owedCover()).getByText(/Every store answered/)).toBeTruthy();
});

it('refuses to call a partial gather an all-clear', async () => {
  const partial: Board = { ...BOARD, total: 1, tiles: [BOARD.tiles![1]], partial: true };
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => new Response(JSON.stringify(partial), { status: 200 })),
  );

  render(<App />);
  await waitFor(() => expect(screen.getByText('Attention Canvas')).toBeTruthy());
  expect(within(owedCover()).getByText(/not an all-clear/)).toBeTruthy();
  expect(within(owedCover()).queryByText(/Every store answered/)).toBeNull();
});

// A quiet parked conversation is FINDABLE without competing for rank with
// stranded epics: it gets the cleanup band, and carries its own ask.
it('lists a quiet parked conversation in the cleanup band', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/helm returns the raw script path/)).toBeTruthy());

  const row = within(band('cleanup')).getByText(/helm returns the raw script path/).closest('tr');
  expect(row).not.toBeNull();
  expect(within(row as HTMLElement).getByText('parked for you — no question recorded')).toBeTruthy();
  expect(within(band('stalled')).queryByText(/helm returns the raw script path/)).toBeNull();
});

it('counts owed, live, and closed separately in the header', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/2 owed · 5 anchors · 1 closed/)).toBeTruthy());
});

// The layout-stability rule: a row the operator was looking at does not leave
// because it was answered. It sinks into the recently-closed band and ages out
// of it on the window clock, with no manual clear.
it('keeps a closed anchor in the recently-closed band', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/takeaway cap conversation/)).toBeTruthy());

  const done = band('recently closed');
  const row = within(done).getByText(/takeaway cap conversation/).closest('tr');
  expect(row).not.toBeNull();
  expect(within(row as HTMLElement).getByText('closed 1d ago')).toBeTruthy();
  expect(within(done).getByText(/ageing out of this band/)).toBeTruthy();
});

// The band's copy is the operator's only statement of what it promises, and the
// promise is narrower than "nothing leaves on its own": the gather reaches back
// GC_HELM_DONE_WINDOW, so a row does age out on that clock.
it('states the window bound rather than promising an unbounded band', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/takeaway cap conversation/)).toBeTruthy());

  const done = band('recently closed');
  expect(within(done).getByText(/GC_HELM_DONE_WINDOW/)).toBeTruthy();
  expect(done.textContent).not.toMatch(/leaves it on its own/);
});

// A closed parked subject is `parked` by kind, so only the section it carries
// keeps it out of a live band that tells the operator these threads resume.
it('keeps a closed parked subject out of every live band', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/takeaway cap conversation/)).toBeTruthy());

  expect(within(band('cleanup')).queryByText(/takeaway cap conversation/)).toBeNull();
  expect(within(band('stalled')).queryByText(/takeaway cap conversation/)).toBeNull();
  expect(within(band('gate')).queryByText(/takeaway cap conversation/)).toBeNull();
});

// The defect this split exists to prevent (tk-2plde): a subject that routed work
// out of a sitting kept saying "nothing further needed here" after that work
// merged. Once the blocker closes it owes a disposition, so it belongs in the
// gate band — a parked row the operator has to open to discover is the bug.
it('bands a parked row whose blocker landed as a gate, not cleanup', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/fix\+guard ruled/)).toBeTruthy());

  expect(within(band('gate')).getByText(/fix\+guard ruled/)).toBeTruthy();
  expect(within(band('cleanup')).queryByText(/fix\+guard ruled/)).toBeNull();

  const row = within(band('gate')).getByText(/fix\+guard ruled/).closest('tr');
  expect(within(row as HTMLElement).getByText(/blocker landed — dispose or resume/)).toBeTruthy();
});

// The defect tk-a9k0l is about. A parked subject that decomposed keeps its
// takeaway, so it stays kind `parked`, and its open child is not a tile of its
// own. Stranded, it belongs in the stalled band, carrying the roll-up.
it('bands a parked row with open children as stalled, not cleanup', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/composition-seam doc/)).toBeTruthy());

  expect(within(band('stalled')).getByText(/composition-seam doc/)).toBeTruthy();
  expect(within(band('cleanup')).queryByText(/composition-seam doc/)).toBeNull();

  const row = within(band('stalled')).getByText(/composition-seam doc/).closest('tr');
  expect(within(row as HTMLElement).getByText('1/2')).toBeTruthy();
  expect(within(row as HTMLElement).getByText(/1 open · 0 in flight \(stranded\)/)).toBeTruthy();
});

it('drills into a cleanup row like any other tile', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/helm returns the raw script path/)).toBeTruthy());

  fireEvent.click(within(band('cleanup')).getByRole('button', { name: 'tk-yps55' }));
  expect(screen.getByRole('complementary', { name: /detail for tk-yps55/i })).toBeTruthy();
});

// A board with nothing in a band must not grow an empty section for it.
it('shows no cleanup band when nothing is in it', async () => {
  const stalledOnly: Board = { ...BOARD, total: 1, tiles: [BOARD.tiles![1]], sittings: null };
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => new Response(JSON.stringify(stalledOnly), { status: 200 })),
  );

  render(<App />);
  await waitFor(() => expect(screen.getByText('Attention Canvas')).toBeTruthy());
  expect(queryBand('cleanup')).toBeNull();
  expect(screen.getByText(/1 anchors · generated/)).toBeTruthy();
});

// A recurring template — many rows with one needs sentence — folds to a single
// line that names the count and lists the members, instead of N peer rows.
it('collapses a cluster to one line that names its members', async () => {
  const clustered: Tile[] = [0, 1, 2, 3].map((i) =>
    tile({
      id: `tk-fr${i}`,
      kind: 'human',
      title: `first reaction ${i}`,
      severity: 'ELEVATED',
      owed: true,
      section: 'gate',
      needs: 'first reaction ready: accept or redirect',
      cluster_key: 'first reaction ready: accept or redirect',
    }),
  );
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => new Response(JSON.stringify({ ...BOARD, total: 4, tiles: clustered, sittings: null }), { status: 200 })),
  );

  render(<App />);
  await waitFor(() => expect(screen.getByText('4×')).toBeTruthy());

  const gate = band('gate');
  // The shared needs prints once for the whole cluster.
  expect(within(gate).getAllByText('first reaction ready: accept or redirect')).toHaveLength(1);
  // Every member is still one drill click away.
  for (const i of [0, 1, 2, 3]) {
    expect(within(gate).getByRole('button', { name: `tk-fr${i}` })).toBeTruthy();
  }
});

// The record is not an attention list: a sitting must not appear as a row in any
// band, where it would compete with work that needs doing.
it('keeps sittings out of the bands', async () => {
  render(<App />);
  await waitFor(() => expect(band('converse sittings')).toBeTruthy());

  expect(within(band('gate')).queryByText('tk-vst01')).toBeNull();
  expect(within(band('stalled')).queryByText(/what the canvas owes the operator/)).toBeNull();
});

it('shows running sittings and recently closed ones with their outcome', async () => {
  render(<App />);
  await waitFor(() => expect(band('converse sittings')).toBeTruthy());

  const section = band('converse sittings');
  expect(within(section).getByText(/1 running · 1 closed recently/)).toBeTruthy();

  const live = within(section).getByText('tk-vst01').closest('tr') as HTMLElement;
  expect(within(live).getByText('running')).toBeTruthy();
  expect(within(live).getByText('40m')).toBeTruthy();
  expect(within(live).getByText('—')).toBeTruthy();

  const done = within(section).getByText('tk-vst02').closest('tr') as HTMLElement;
  expect(within(done).getByText('closed')).toBeTruthy();
  expect(within(done).getByText('diagnosed')).toBeTruthy();
  expect(within(done).getByText(/the path was the launcher/)).toBeTruthy();
});

it('shows the outcome on a running sitting a dismissal stamped but could not close', async () => {
  const stuck: Board = {
    ...BOARD,
    sittings: [
      {
        id: 'tk-vst09',
        rig: 'gc-toolkit',
        subject: 'tk-epic',
        title: 'visit: tk-epic — the operator ended it from the board',
        status: 'in_progress',
        outcome: 'dismissed',
        session: 'gc-toolkit__converse-9',
        opened_at: '2026-08-21T18:34:00Z',
        takeaway: '',
      },
    ],
  };
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => new Response(JSON.stringify(stuck), { status: 200 })),
  );

  render(<App />);
  await waitFor(() => expect(band('converse sittings')).toBeTruthy());

  const row = within(band('converse sittings')).getByText('tk-vst09').closest('tr') as HTMLElement;
  expect(within(row).getByText('running')).toBeTruthy();
  expect(within(row).getByText('dismissed')).toBeTruthy();
});

it('drills into a sitting by its subject', async () => {
  render(<App />);
  await waitFor(() => expect(band('converse sittings')).toBeTruthy());

  fireEvent.click(within(band('converse sittings')).getByRole('button', { name: 'tk-epic' }));
  expect(screen.getByRole('complementary', { name: /detail for tk-epic/i })).toBeTruthy();
});

it('shows no sittings section when there are none', async () => {
  const noSittings: Board = { ...BOARD, sittings: null };
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => new Response(JSON.stringify(noSittings), { status: 200 })),
  );

  render(<App />);
  await waitFor(() => expect(screen.getByText('Attention Canvas')).toBeTruthy());
  expect(queryBand('converse sittings')).toBeNull();
});

it('ages a sitting against the board it came from, not the clock', async () => {
  const later: Board = { ...BOARD, generated_at: '2026-08-21T21:14:00Z' };
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => new Response(JSON.stringify(later), { status: 200 })),
  );

  render(<App />);
  await waitFor(() => expect(band('converse sittings')).toBeTruthy());

  const live = within(band('converse sittings')).getByText('tk-vst01').closest('tr') as HTMLElement;
  expect(within(live).getByText('2h')).toBeTruthy();
});

// "No anchors need attention" is a claim about the whole board. On an owed-only
// board the unqualified sentence contradicts the queue it sits under.
it('does not tell an owed-only board that nothing needs attention', async () => {
  const owedOnly: Board = { ...BOARD, total: 1, tiles: [BOARD.tiles![0]] };
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => new Response(JSON.stringify(owedOnly), { status: 200 })),
  );

  render(<App />);
  await waitFor(() => expect(screen.getByText(/anchorless open PR/)).toBeTruthy());
  expect(screen.getByText('No other anchors need attention.')).toBeTruthy();
  expect(screen.queryByText('No anchors need attention.')).toBeNull();
});

it('tells a board with no rows at all that nothing needs attention', async () => {
  const nothing: Board = { ...BOARD, total: 0, tiles: [], sittings: null };
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => new Response(JSON.stringify(nothing), { status: 200 })),
  );

  render(<App />);
  await waitFor(() => expect(screen.getByText(/Nothing is owed by you/)).toBeTruthy());
  expect(screen.getByText('No anchors need attention.')).toBeTruthy();
});

// --- the PR round-trip (specs/tk-q0ml23) --------------------------------------

/** Serve a board made of exactly these tiles. */
function serve(tiles: Tile[]) {
  const board: Board = { ...BOARD, total: tiles.length, tiles, sittings: [] };
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => new Response(JSON.stringify(board), { status: 200 })),
  );
}

// A merge anchor bands review, and the row says WHY nothing is moving: "routed
// to a person" alone reads identically for an anchor awaiting a ruling and for
// one the review cap parked, where the only release is a ruling nobody gave.
it('names the wedge and links the pull request', async () => {
  serve([
    prTile({
      id: 'tk-veto',
      title: 'a pull request a human rejected',
      pr_machine: 'wedged-veto',
      pr_number: 513,
      pr_url: 'https://github.com/zook/gc-toolkit/pull/513',
      needs: 'wedged: a standing CHANGES_REQUESTED with the rework rounds spent',
    }),
  ]);
  render(<App />);
  await waitFor(() => expect(screen.getByText(/a pull request a human rejected/)).toBeTruthy());

  const row = within(band('review')).getByText(/a pull request a human rejected/).closest('tr');
  expect(row).not.toBeNull();
  expect(within(row as HTMLElement).getByText(/wedged: a standing CHANGES_REQUESTED/)).toBeTruthy();

  const link = within(row as HTMLElement).getByRole('link', { name: 'PR #513' });
  expect(link.getAttribute('href')).toBe('https://github.com/zook/gc-toolkit/pull/513');
});

// The row is a MERGE ANCHOR's, not a pull request's. Most wedged anchors have no
// pull request at all, so a surface that could only identify a row by its number
// would have nothing to show for the majority of them.
it('identifies a pre-open row without inventing a link', async () => {
  serve([prTile({ id: 'tk-pre', title: 'wedged before the PR opened' })]);
  render(<App />);
  await waitFor(() => expect(screen.getByText(/wedged before the PR opened/)).toBeTruthy());

  const row = within(band('review')).getByText(/wedged before the PR opened/).closest('tr');
  expect(within(row as HTMLElement).queryByRole('link')).toBeNull();
  expect(within(row as HTMLElement).getByText('polecat/tk-pre')).toBeTruthy();
});

// An anchor at a human state carries merge_result and can carry no branch and no
// number, and a cell that named an absence as an identity is the same failure
// inverted.
it('says so on a row that records neither number nor branch', async () => {
  serve([prTile({ id: 'tk-bare', title: 'a merge anchor with no branch recorded', pr_branch: '' })]);
  render(<App />);
  await waitFor(() => expect(screen.getByText(/no branch recorded/)).toBeTruthy());

  const row = within(band('review')).getByText(/no branch recorded/).closest('tr');
  expect(within(row as HTMLElement).getByText('not open yet')).toBeTruthy();
});

// The queue is ordered by how long a row has been owed, and pr_owed_since is the
// only stamp on a merge anchor that dates the TURN.
it('dates an owed PR row by its turn, not by the last pass that touched it', async () => {
  serve([
    prTile({
      id: 'tk-old',
      title: 'wedged for three days',
      pr_owed_since: '2026-08-08T11:02:00Z',
      updated_at: '2026-08-11T14:55:00Z',
    }),
  ]);
  render(<App />);
  await waitFor(() => expect(screen.getByText(/wedged for three days/)).toBeTruthy());

  const row = within(band('review')).getByText(/wedged for three days/).closest('tr');
  expect(within(row as HTMLElement).getByText('2026-08-08')).toBeTruthy();
  expect(within(row as HTMLElement).queryByText('2026-08-11')).toBeNull();
});

// The empty-state contract, extended. A board that says "nothing is owed" while
// a pull request's position is unread has told the operator to stop looking on
// the strength of a question it never asked.
it('withholds the all-clear while a PR position is unread', async () => {
  serve([
    prTile({
      id: 'tk-silent',
      title: 'a pull request the cadence has not judged',
      owed: false,
      section: 'review',
      pr_machine: 'unknown',
      pr_owed_since: undefined,
      needs: 'position unknown — the merge cadence has recorded none',
    }),
  ]);
  render(<App />);
  await waitFor(() => expect(screen.getByText(/NOT an all-clear/)).toBeTruthy());

  const sub = within(owedCover()).getByRole('status');
  expect(sub.textContent).toMatch(/1 of 1 have no position recorded/);
  expect(sub.textContent).toMatch(/acknowledgement watermarks are not built yet/);
  expect(sub.textContent).not.toMatch(/^Nothing is owed by you\./);
});

// The DONE band is not coverage debt. Its rows carry the same axes as live ones
// with the same unknowns, so counting them would keep the queue's own emptiness
// from ever reading as an all-clear.
it('does not count closed pull requests as unread positions', async () => {
  const shut = prTile({
    id: 'tk-shut',
    title: 'a pull request that landed',
    owed: false,
    severity: 'DONE',
    section: 'done',
    closed_at: '2026-08-20T19:14:00Z',
    pr_machine: 'unknown',
    pr_owed_since: undefined,
    needs: 'closed — ages out',
  });
  serve([shut]);
  const view = render(<App />);
  await waitFor(() => expect(screen.getByText(/Nothing is owed by you/)).toBeTruthy());
  expect(within(owedCover()).getByRole('status').textContent).not.toMatch(/all-clear/);
  view.unmount();

  serve([
    shut,
    prTile({
      id: 'tk-silent',
      title: 'a pull request the cadence has not judged',
      owed: false,
      section: 'review',
      pr_machine: 'unknown',
      pr_owed_since: undefined,
      needs: 'position unknown — the merge cadence has recorded none',
    }),
  ]);
  render(<App />);
  await waitFor(() => expect(screen.getByText(/NOT an all-clear/)).toBeTruthy());
  expect(within(owedCover()).getByRole('status').textContent).toMatch(/1 of 1 have no position recorded/);
});

it('gives the all-clear when every PR position was readable', async () => {
  serve([
    prTile({
      id: 'tk-green',
      title: 'a pull request waiting on the merge pass',
      owed: false,
      section: 'review',
      pr_machine: 'settled',
      pr_conversation: 'quiet',
      pr_approval: 'not_required',
      pr_owed_since: undefined,
      needs: 'green — waiting on the merge pass',
    }),
  ]);
  render(<App />);
  await waitFor(() => expect(screen.getByText(/Nothing is owed by you/)).toBeTruthy());

  const sub = within(owedCover()).getByRole('status');
  expect(sub.textContent).toMatch(/1 pull requests read, all with a position/);
});

// --- pack builds ---------------------------------------------------------

function build(over: Partial<PackBuild> & Pick<PackBuild, 'component'>): PackBuild {
  return {
    source_rev: 'aaaaaaaaaaaa1111',
    binary_rev: 'aaaaaaaaaaaa1111',
    last_build_rc: 0,
    restart_pending: false,
    severity: 'NORMAL',
    detail: 'current at aaaaaaaaaaaa',
    ...over,
  };
}

function serveBoard(board: Board) {
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => new Response(JSON.stringify(board), { status: 200 })),
  );
}

function packSection(): HTMLElement {
  return screen.getByRole('region', { name: /pack builds/i });
}

it('lists every compiled component, including the healthy ones', async () => {
  serveBoard({
    ...BOARD,
    pack_health: [
      build({ component: 'gctk', severity: 'HIGH', last_build_rc: 1, detail: 'last build FAILED (rc 1); still serving bbbbbbbbbbbb' }),
      build({ component: 'helm' }),
    ],
  });

  render(<App />);
  await waitFor(() => expect(packSection()).toBeTruthy());

  const section = packSection();
  expect(within(section).getByText('gctk')).toBeTruthy();
  expect(within(section).getByText(/last build FAILED/)).toBeTruthy();
  expect(within(section).getByText('helm')).toBeTruthy();
  expect(within(section).getByText(/current at aaaaaaaaaaaa/)).toBeTruthy();
});

it('shows no pack-builds section when the city recorded no builds', async () => {
  serveBoard({ ...BOARD, pack_health: undefined });

  render(<App />);
  await waitFor(() => expect(screen.getByText('Attention Canvas')).toBeTruthy());
  expect(screen.queryByRole('region', { name: /pack builds/i })).toBeNull();
});

it('renders the severity the service assigned, not one it re-derives', async () => {
  serveBoard({
    ...BOARD,
    pack_health: [
      build({ component: 'helm', severity: 'ELEVATED', binary_rev: 'oldoldoldold', detail: 'serving oldoldoldold, sources are at aaaaaaaaaaaa' }),
    ],
  });

  render(<App />);
  await waitFor(() => expect(packSection()).toBeTruthy());
  expect(within(packSection()).getByText('ELEVATED')).toBeTruthy();
});
