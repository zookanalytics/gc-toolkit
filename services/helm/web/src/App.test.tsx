import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { App } from './App';
import type { Board, Tile } from './contract';

// A board carrying all five shapes the split has to tell apart: an ordinary
// ranked anchor, an operator-owned bead that IS attention, a parked
// conversation that is not, a parked conversation whose routed work has
// landed — which stopped being "wants nothing" and has to leave the quiet
// section (tk-2plde) — and a parked conversation whose routed work is still
// OPEN, which never was "wants nothing" (tk-a9k0l).
function tile(over: Partial<Tile> & Pick<Tile, 'id' | 'kind' | 'title' | 'severity'>): Tile {
  return {
    rig: 'gc-toolkit',
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

const BOARD: Board = {
  generated_at: '2026-08-21T19:14:00Z',
  total: 5,
  tiles: [
    // The takeaway is what keeps an idle epic in the HIGH band since
    // tk-9tbbk.3: without one the server derives `awaiting dispatch` and stands
    // the row down to LOW, so a HIGH tile with a mechanical NEEDS phrase is a
    // board this app can no longer be sent.
    tile({
      id: 'tk-epic',
      kind: 'epic',
      title: 'Attention Canvas',
      severity: 'HIGH',
      m_total: 2,
      open: 2,
      stranded: true,
      takeaway: 'the ink-model decision is the operator\u2019s and blocks both tracks',
      frontier: '2 open · 0 in flight (stranded)',
      needs: 'the ink-model decision is the operator\u2019s and blocks both tracks',
      rank_score: 3_005_003,
    }),
    tile({
      id: 'tk-jgq6s',
      kind: 'human',
      title: 'Disposition: 1 anchorless open PR remains (#88)',
      severity: 'ELEVATED',
      frontier: 'routed to the operator — no agent will take it',
      needs: 'operator action',
      rank_score: 2_003_011,
    }),
    tile({
      id: 'tk-yps55',
      kind: 'parked',
      title: "gc-toolkit's helm returns the raw script path",
      severity: 'LOW',
      frontier: 'conversation parked — takeaway recorded',
      needs: 'resume: prefix+a, then the bead id',
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

/** The main ranked table is the first one on the page; the parked one follows. */
function attentionTable(): HTMLElement {
  return screen.getAllByRole('table')[0];
}

function parkedSection(): HTMLElement {
  return screen.getByRole('region', { name: /parked conversations/i });
}

// The bug in one assertion: a bead the operator owns reaches the board at all.
// Before tk-2v08m the gather was keyed on issue type, so `gc.routed_to=human`
// on an ordinary task made it invisible however plainly it was marked.
it('ranks an operator-owned bead with the rest of the attention', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/anchorless open PR/)).toBeTruthy());

  const row = within(attentionTable()).getByText(/anchorless open PR/).closest('tr');
  expect(row).not.toBeNull();
  expect(within(row as HTMLElement).getByText('ELEVATED')).toBeTruthy();
  expect(within(row as HTMLElement).getByText('operator action')).toBeTruthy();
});

// The other half of the bead: a parked conversation must be FINDABLE without
// competing for rank with stranded epics, so it gets a section rather than a
// row among them.
it('lists a parked conversation in its own section, not in the ranked table', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/helm returns the raw script path/)).toBeTruthy());

  const parked = within(parkedSection()).getByText(/helm returns the raw script path/);
  expect(within(attentionTable()).queryByText(/helm returns the raw script path/)).toBeNull();

  // The resume gesture rides on the row itself — the thread was always
  // resumable, only never findable.
  const row = parked.closest('tr');
  expect(row).not.toBeNull();
  expect(within(row as HTMLElement).getByText(/prefix\+a/)).toBeTruthy();
});

it('counts the two sections separately in the header', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/4 anchors · 1 parked/)).toBeTruthy());
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
  const attentionOnly: Board = { ...BOARD, total: 1, tiles: [BOARD.tiles![0]] };
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => new Response(JSON.stringify(attentionOnly), { status: 200 })),
  );

  render(<App />);
  await waitFor(() => expect(screen.getByText('Attention Canvas')).toBeTruthy());
  expect(screen.queryByRole('region', { name: /parked conversations/i })).toBeNull();
  expect(screen.getByText(/1 anchors · generated/)).toBeTruthy();
});
