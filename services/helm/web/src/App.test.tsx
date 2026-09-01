import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { App } from './App';
import type { Board, Sitting, Tile } from './contract';

// A board carrying all six shapes the sections have to tell apart: an ordinary
// ranked anchor, an operator-owned bead that is the DEFAULT answer, a parked
// conversation that is neither, a parked conversation whose routed work has
// landed — which stopped being "wants nothing" and has to leave the quiet
// section (tk-2plde) — a parked conversation whose routed work is still OPEN,
// which never was "wants nothing" (tk-a9k0l), and a parked conversation whose
// own bead has closed, which belongs to none of them.
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
    ...over,
  };
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
    tile({
      id: 'tk-jgq6s',
      kind: 'human',
      title: 'Disposition: 1 anchorless open PR remains (#88)',
      severity: 'ELEVATED',
      owed: true,
      takeaway_at: '2026-07-04T09:00:00Z',
      frontier: 'routed to the operator — no agent will take it',
      needs: 'routed to you — no question recorded',
      rank_score: 2_003_011,
    }),
    tile({
      id: 'tk-epic',
      kind: 'epic',
      title: 'Attention Canvas',
      severity: 'HIGH',
      m_total: 2,
      open: 2,
      frontier: '2 open · 0 in-progress (stranded)',
      needs: 'decomposed, idle — assign or visit',
      rank_score: 3_005_003,
    }),
    tile({
      id: 'tk-yps55',
      kind: 'parked',
      title: "gc-toolkit's helm returns the raw script path",
      severity: 'LOW',
      frontier: 'conversation parked — no takeaway recorded',
      needs: 'parked for you — no question recorded',
      rank_score: 2_001,
    }),
    // Parked by kind, but the work it was waiting on has closed. The service
    // bands it ELEVATED; the app must not file it under "wants nothing".
    tile({
      id: 'tk-dispo',
      kind: 'parked',
      title: 'routed — fix+guard ruled, nothing further needed here',
      severity: 'ELEVATED',
      waiting_on: ['tk-hgmob'],
      waiting_on_open: [],
      disposition_due: true,
      frontier: 'parked · blocker landed',
      needs: 'blocker landed — dispose or resume',
      rank_score: 2_002_001,
    }),
    // Parked by kind, and the work the sitting routed is its own OPEN child.
    // No waiting edge can exist on this shape — beads refuses a parent→
    // descendant `blocks` edge — so disposition_due is false and the roll-up
    // is the only thing that can say the subject is not quiet (tk-a9k0l).
    tile({
      id: 'tk-z9nln',
      kind: 'parked',
      title: 'audit the gc-toolkit workflow and write the composition-seam doc',
      severity: 'HIGH',
      n_closed: 1,
      m_total: 2,
      open: 1,
      stranded: true,
      open_heads: ['tk-wvrga'],
      frontier: '1 open · 0 in flight (stranded)',
      needs: 'kept open as the seat for the strategic conversation',
      rank_score: 3_005_000,
    }),
    // A parked subject whose own bead has CLOSED. It is `parked` by kind and
    // quiet by every other test, so without the DONE filter it would read as a
    // live conversation to pick back up — in the section whose whole promise is
    // that its rows are resumable.
    tile({
      id: 'tk-9tbbk',
      kind: 'parked',
      title: 'the takeaway cap conversation',
      severity: 'DONE',
      closed_at: '2026-08-20T19:14:00Z',
      frontier: 'closed 1d ago',
      needs: 'closed — dismiss to clear',
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

// Address the tables through their sections, not by position: the queue leads
// the page, so an index would silently re-point at it.
function owedSection(): HTMLElement {
  return screen.getByRole('region', { name: /owed by you/i });
}

function parkedSection(): HTMLElement {
  return screen.getByRole('region', { name: /parked conversations/i });
}

function sittingsSection(): HTMLElement {
  return screen.getByRole('region', { name: /converse sittings/i });
}

function doneSection(): HTMLElement {
  return screen.getByRole('region', { name: /recently closed/i });
}

/** The city overview — the one table outside every section. */
function attentionTable(): HTMLElement {
  const tables = screen.getAllByRole('table');
  const sectioned = [
    owedSection(),
    screen.queryByRole('region', { name: /parked conversations/i }),
    screen.queryByRole('region', { name: /recently closed/i }),
    screen.queryByRole('region', { name: /converse sittings/i }),
  ];
  const found = tables.find((t) => !sectioned.some((s) => s?.contains(t)));
  if (!found) throw new Error('no overview table on the page');
  return found;
}

// Two bugs in one assertion. A bead the operator owns has to reach the board at
// all — before tk-2v08m the gather was keyed on issue type, so
// `gc.routed_to=human` on an ordinary task was invisible however plainly it was
// marked. And it has to be the board's DEFAULT answer rather than one row in a
// ranked list, because rank sorts a one-bead demand under every container.
it('answers with the operator-owned bead, not with the ranked overview', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/anchorless open PR/)).toBeTruthy());

  const row = within(owedSection()).getByText(/anchorless open PR/).closest('tr');
  expect(row).not.toBeNull();
  expect(within(row as HTMLElement).getByText('routed to you — no question recorded')).toBeTruthy();
  expect(within(row as HTMLElement).getByText('2026-07-04')).toBeTruthy();

  // It is in the queue INSTEAD of the overview, not as well as.
  expect(within(attentionTable()).queryByText(/anchorless open PR/)).toBeNull();
  // …and the HIGH row it outranks nowhere still leads that overview.
  expect(within(attentionTable()).getByText('Attention Canvas')).toBeTruthy();
});

// The never-blank contract. "Nothing is owed by you" is this page's most
// consequential sentence and the default output of every failure path, so the
// section states its coverage or states the error — it is never empty.
it('states its coverage when nothing is owed', async () => {
  const nothingOwed: Board = { ...BOARD, total: 1, tiles: [BOARD.tiles![1]] };
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => new Response(JSON.stringify(nothingOwed), { status: 200 })),
  );

  render(<App />);
  await waitFor(() => expect(screen.getByText('Attention Canvas')).toBeTruthy());
  expect(within(owedSection()).getByText(/Every store answered/)).toBeTruthy();
});

it('refuses to call a partial gather an all-clear', async () => {
  const partial: Board = { ...BOARD, total: 1, tiles: [BOARD.tiles![1]], partial: true };
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => new Response(JSON.stringify(partial), { status: 200 })),
  );

  render(<App />);
  await waitFor(() => expect(screen.getByText('Attention Canvas')).toBeTruthy());
  expect(within(owedSection()).getByText(/not an all-clear/)).toBeTruthy();
  expect(within(owedSection()).queryByText(/Every store answered/)).toBeNull();
});

// The other half of the bead: a parked conversation must be FINDABLE without
// competing for rank with stranded epics, so it gets a section rather than a
// row among them.
it('lists a parked conversation in its own section, not in the ranked table', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/helm returns the raw script path/)).toBeTruthy());

  const parked = within(parkedSection()).getByText(/helm returns the raw script path/);
  expect(within(attentionTable()).queryByText(/helm returns the raw script path/)).toBeNull();

  // The row carries its own ask. This fixture is the shape a sitting left
  // without recording one, and the section says so rather than filing it as an
  // ordinary quiet row.
  const row = parked.closest('tr');
  expect(row).not.toBeNull();
  expect(within(row as HTMLElement).getByText('parked for you — no question recorded')).toBeTruthy();
});

it('counts each section separately in the header', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/1 owed · 3 anchors · 1 parked · 1 closed/)).toBeTruthy());
});

// The layout-stability rule for the board: a row the operator was looking at
// does not leave because it was answered. It sinks into its own section and
// waits there for an explicit dismiss.
it('keeps a closed anchor on the board, in the recently-closed section', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/takeaway cap conversation/)).toBeTruthy());

  const row = within(doneSection()).getByText(/takeaway cap conversation/).closest('tr');
  expect(row).not.toBeNull();
  expect(within(row as HTMLElement).getByText('closed 1d ago')).toBeTruthy();
  expect(within(doneSection()).getByText(/gc-helm dismiss/)).toBeTruthy();
});

// The section's copy is the operator's only statement of what the band
// promises, and the promise the band actually keeps is narrower than "nothing
// leaves on its own": the gather reaches back GC_HELM_DONE_WINDOW, so a row
// does age out of the band on that clock. Copy that says otherwise teaches the
// operator to stop looking for a row that is gone.
it('states the window bound rather than promising an unbounded band', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/takeaway cap conversation/)).toBeTruthy());

  const done = doneSection();
  expect(within(done).getByText(/GC_HELM_DONE_WINDOW/)).toBeTruthy();
  expect(done.textContent).not.toMatch(/leaves it on its own/);
});

// It is `parked` by kind, so the DONE filter is what keeps it out of a section
// that tells the operator these threads can be picked back up.
it('keeps a closed parked subject out of the parked and ranked tables', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/takeaway cap conversation/)).toBeTruthy());

  expect(within(parkedSection()).queryByText(/takeaway cap conversation/)).toBeNull();
  expect(within(attentionTable()).queryByText(/takeaway cap conversation/)).toBeNull();
});

// The defect this split exists to prevent (tk-2plde): a subject that routed
// work out of a sitting kept saying "nothing further needed here" after that
// work merged, and the quiet section is where it went on saying it. Once the
// blocker closes the row owes a disposition, so it must be in the ranked table
// — a parked row the operator has to open to discover is the whole bug.
it('promotes a parked row whose blocker landed into the ranked table', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/fix\+guard ruled/)).toBeTruthy());

  expect(within(attentionTable()).getByText(/fix\+guard ruled/)).toBeTruthy();
  expect(within(parkedSection()).queryByText(/fix\+guard ruled/)).toBeNull();

  const row = within(attentionTable()).getByText(/fix\+guard ruled/).closest('tr');
  expect(row).not.toBeNull();
  // The stale takeaway must not be the row's answer — the deterministic
  // disposition phrase outranks it.
  expect(within(row as HTMLElement).getByText(/blocker landed — dispose or resume/)).toBeTruthy();
});

// The defect tk-a9k0l is about. A parked subject that decomposed keeps its
// takeaway, so it stays kind `parked`, and its open child is not a tile of its
// own — a plain bead reaches the board only through its parent's roll-up. Filed
// under "wants nothing", the row hides the only surface that work has.
it('promotes a parked row with open children into the ranked table', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/composition-seam doc/)).toBeTruthy());

  expect(within(attentionTable()).getByText(/composition-seam doc/)).toBeTruthy();
  expect(within(parkedSection()).queryByText(/composition-seam doc/)).toBeNull();

  // …carrying the roll-up that promoted it, so the open child is countable
  // from the row rather than only from --json.
  const row = within(attentionTable()).getByText(/composition-seam doc/).closest('tr');
  expect(row).not.toBeNull();
  expect(within(row as HTMLElement).getByText('1/2')).toBeTruthy();
  expect(within(row as HTMLElement).getByText(/1 open · 0 in flight \(stranded\)/)).toBeTruthy();
});

it('drills into a parked row like any other tile', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/helm returns the raw script path/)).toBeTruthy());

  fireEvent.click(within(parkedSection()).getByRole('button', { name: 'tk-yps55' }));
  expect(screen.getByRole('complementary', { name: /detail for tk-yps55/i })).toBeTruthy();
});

// A board with nothing parked must not grow an empty section or a "· 0 parked"
// suffix that reads as a category the operator has to check.
it('shows no parked section when nothing is parked', async () => {
  const attentionOnly: Board = { ...BOARD, total: 1, tiles: [BOARD.tiles![1]], sittings: null };
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => new Response(JSON.stringify(attentionOnly), { status: 200 })),
  );

  render(<App />);
  await waitFor(() => expect(screen.getByText('Attention Canvas')).toBeTruthy());
  expect(screen.queryByRole('region', { name: /parked conversations/i })).toBeNull();
  expect(screen.getByText(/1 anchors · generated/)).toBeTruthy();
});

// The operator's ask in one assertion: both halves of the conversation record
// on the board, each closed sitting carrying the justification it closed on.
it('shows running sittings and recently closed ones with their outcome', async () => {
  render(<App />);
  await waitFor(() => expect(sittingsSection()).toBeTruthy());

  const section = sittingsSection();
  expect(within(section).getByText(/1 running · 1 closed recently/)).toBeTruthy();

  const live = within(section).getByText('tk-vst01').closest('tr') as HTMLElement;
  expect(within(live).getByText('running')).toBeTruthy();
  expect(within(live).getByText('40m')).toBeTruthy();
  // A sitting that has not ended has no outcome to show.
  expect(within(live).getByText('—')).toBeTruthy();

  const done = within(section).getByText('tk-vst02').closest('tr') as HTMLElement;
  expect(within(done).getByText('closed')).toBeTruthy();
  expect(within(done).getByText('diagnosed')).toBeTruthy();
  expect(within(done).getByText(/the path was the launcher/)).toBeTruthy();
});

// The record is not an attention list: a sitting must not appear as a row in
// the ranked table, where it would compete with work that needs doing.
it('keeps sittings out of the ranked table', async () => {
  render(<App />);
  await waitFor(() => expect(sittingsSection()).toBeTruthy());

  expect(within(attentionTable()).queryByText('tk-vst01')).toBeNull();
  expect(within(attentionTable()).queryByText(/what the canvas owes the operator/)).toBeNull();
});

// A sitting's subject is an anchor, so the drill gesture is the one the rest of
// the board already uses.
it('drills into a sitting by its subject', async () => {
  render(<App />);
  await waitFor(() => expect(sittingsSection()).toBeTruthy());

  fireEvent.click(within(sittingsSection()).getByRole('button', { name: 'tk-epic' }));
  expect(screen.getByRole('complementary', { name: /detail for tk-epic/i })).toBeTruthy();
});

// A quiet city grows no empty section, exactly as it grows no empty parked one.
it('shows no sittings section when there are none', async () => {
  const noSittings: Board = { ...BOARD, sittings: null };
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => new Response(JSON.stringify(noSittings), { status: 200 })),
  );

  render(<App />);
  await waitFor(() => expect(screen.getByText('Attention Canvas')).toBeTruthy());
  expect(screen.queryByRole('region', { name: /converse sittings/i })).toBeNull();
});

// Ages are measured from the board's own generated_at rather than the wall
// clock: a tab left open overnight must not age every sitting past what the
// gather actually saw.
it('ages a sitting against the board it came from, not the clock', async () => {
  const later: Board = { ...BOARD, generated_at: '2026-08-21T21:14:00Z' };
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => new Response(JSON.stringify(later), { status: 200 })),
  );

  render(<App />);
  await waitFor(() => expect(sittingsSection()).toBeTruthy());

  const live = within(sittingsSection()).getByText('tk-vst01').closest('tr') as HTMLElement;
  expect(within(live).getByText('2h')).toBeTruthy();
});

// "No anchors need attention" is a claim about the WHOLE board, and the section
// directly above it has just listed anchors that need one. On an owed-only board
// the unqualified sentence contradicts the queue it sits under; the same board
// with nothing on it at all is the only one it is true of.
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

// attentionTable() addresses the overview by exclusion, so every other table on
// the page has to be excluded by name. A board whose only row is owed renders
// no overview table at all while the sittings section still renders one — the
// arm where a missed exclusion hands a test the wrong table instead of failing.
it('does not mistake the sittings table for the overview', async () => {
  const owedOnly: Board = { ...BOARD, total: 1, tiles: [BOARD.tiles![0]] };
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => new Response(JSON.stringify(owedOnly), { status: 200 })),
  );

  render(<App />);
  await waitFor(() => expect(sittingsSection()).toBeTruthy());
  expect(within(sittingsSection()).getByRole('table')).toBeTruthy();
  expect(() => attentionTable()).toThrow(/no overview table/);
});
