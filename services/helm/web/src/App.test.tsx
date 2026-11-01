import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { App, resolveDrillTarget } from './App';
import type { Board, PackBuild, Sitting, Tile } from './contract';

// The board arrives as one ranked list; every row carries its dependency FAMILY
// in `tile.group_root`, its immediate parent in that family in `tile.group_parent`,
// and the band it wants within the family in `tile.section`. The app groups by
// reading those fields — it never re-derives the split — so these fixtures set
// them the way the derive layer would, and the tests address a family by its
// root's heading. group_root defaults to the tile's own id (its own family root)
// and group_parent to empty (no parent); a member sets group_root to its root's
// id, and a nested member also sets group_parent to its immediate parent.
function tile(over: Partial<Tile> & Pick<Tile, 'id' | 'kind' | 'title' | 'severity'>): Tile {
  return {
    group_root: over.id,
    group_parent: '',
    rig: 'gc-toolkit',
    owed: false,
    weight: 0,
    held: false,
    sitting_state: '',
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
    pr_branch_url: '',
    pr_phase: '',
    phase: '',
    pr_machine: '',
    pr_conversation: '',
    pr_approval: '',
    section: 'active',
    acceptable: false,
    accept_formula: '',
    recommendation: null,
    accept_withheld: null,
    gates_in_session: null,
    sitting_start_failure: '',
    pr_held: null,
    work_held: false,
    ...over,
  };
}

/**
 * A merge anchor row, as the board derives one: it bands `review` whatever the
 * cadence recorded. The default is an owed row routed to a person, held by a
 * block no automated actor clears, with no pull request open.
 */
function prTile(over: Partial<Tile> & Pick<Tile, 'id'>): Tile {
  return tile({
    kind: 'human',
    title: 'a merge anchor',
    severity: 'ELEVATED',
    owed: true,
    section: 'review',
    pr_branch: `polecat/${over.id}`,
    pr_machine: 'blocked',
    pr_conversation: 'unknown',
    pr_approval: 'unknown',
    pr_owed_since: '2026-08-08T11:02:00Z',
    needs: 'blocked — a person must clear it before the merge can proceed',
    ...over,
  });
}

// The two halves of the conversation record: one sitting in session, one closed
// with the close reason and the takeaway it left.
const SITTINGS: Sitting[] = [
  {
    id: 'tk-vst01',
    rig: 'gc-toolkit',
    subject: 'tk-epic',
    title: 'what the canvas owes the operator',
    outcome_reason: '',
    session: 'gc-toolkit__converse-1',
    opened_at: '2026-08-21T18:34:00Z',
    takeaway: '',
    subject_title: 'the attention-canvas epic topic',
    state: 'in_session',
    headline: 'the attention-canvas epic topic',
  },
  {
    id: 'tk-vst02',
    rig: 'gc-toolkit',
    subject: 'tk-yps55',
    title: 'the raw script path',
    outcome_reason: '',
    session: 'gc-toolkit__converse-2',
    opened_at: '2026-08-21T17:20:00Z',
    closed_at: '2026-08-21T17:54:00Z',
    takeaway: 'the path was the launcher’s, not the board’s',
    subject_title: 'the raw-path launcher finding',
    state: 'closed',
    headline: 'the path was the launcher’s, not the board’s',
  },
];

// The fixture exercises Model C: one real FAMILY (the tk-epic epic and two
// members that hang off it — a merge anchor under review and an operator-owned
// gate bead) plus standalone families, each a single anchor that is its own
// root. Members carry group_root; roots leave it their own id.
const BOARD: Board = {
  generated_at: '2026-08-21T19:14:00Z',
  total: 7,
  sittings: SITTINGS,
  tiles: [
    // A bead a person owes with no question recorded → the gate band, as a
    // member of the tk-epic family it hangs off.
    tile({
      id: 'tk-jgq6s',
      kind: 'human',
      title: 'Disposition: 1 anchorless open PR remains (#88)',
      severity: 'ELEVATED',
      owed: true,
      section: 'gate',
      group_root: 'tk-epic',
      takeaway_at: '2026-07-04T09:00:00Z',
      frontier: 'routed to the operator — no agent will take it',
      needs: 'routed to you — no question recorded',
      rank_score: 2_003_011,
    }),
    // The family root: a stranded epic. Not owed, so it does not itself lead the
    // queue, but its owed members do.
    tile({
      id: 'tk-epic',
      kind: 'epic',
      title: 'Attention Canvas',
      severity: 'HIGH',
      m_total: 2,
      open: 2,
      stranded: true,
      section: 'stalled',
      group_root: 'tk-epic',
      frontier: '2 open · 0 in-progress (stranded)',
      needs: 'decomposed, idle — assign or discuss',
      rank_score: 3_005_003,
    }),
    // A merge anchor under review → the review band, another member of tk-epic.
    tile({
      id: 'tk-pr88',
      kind: 'merge',
      title: 'the canvas PR waiting on your review',
      severity: 'ELEVATED',
      owed: true,
      section: 'review',
      group_root: 'tk-epic',
      pr_number: 88,
      pr_url: 'https://github.com/zook/gc-toolkit/pull/88',
      pr_branch: 'polecat/tk-pr88',
      pr_machine: 'settled',
      pr_conversation: 'unknown',
      pr_approval: 'required',
      pr_owed_since: '2026-08-19T09:00:00Z',
      frontier: 'PR #88 · owed 2d',
      needs: 'green, waiting on your review',
      rank_score: 2_002_500,
    }),
    // Parked by kind, but the work it was waiting on has closed — it owes a
    // disposition now, so the derive layer marks it owed and bands it gate. Its
    // own family.
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
      frontier: 'blocker landed',
      needs: 'blocker landed — dispose or resume',
      rank_score: 2_002_001,
    }),
    // A quiet parked conversation → the cleanup band, its own family.
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
    // live family even though it is `parked` by kind.
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
  // Collapse state persists to localStorage, which a jsdom shares across the
  // tests in this file; clear it so one test's fold does not leak into the next.
  localStorage.clear();
});

// A fixed region by its accessible name — the owed cover-sheet, the sittings
// record, the pack strip, or the anchors table; never by position.
const region = (name: string): HTMLElement => screen.getByRole('region', { name });
const queryRegion = (name: string): HTMLElement | null => screen.queryByRole('region', { name });
const owedCover = (): HTMLElement => screen.getByRole('region', { name: 'owed by you' });
const anchors = (): HTMLElement => screen.getByRole('region', { name: 'anchors' });

// The board is ONE table, so a row is addressed by unique text it carries (its
// title, id, or needs sentence), found within the anchors region.
function rowFor(text: RegExp | string): HTMLElement | null {
  const cell = within(anchors()).queryByText(text);
  return cell ? (cell.closest('tr') as HTMLElement) : null;
}

// True when row `a` renders before row `b` — the table's order, read positionally.
function precedes(a: HTMLElement, b: HTMLElement): boolean {
  return Boolean(a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING);
}

// A bead a person owes reaches the board (before tk-2v08m a gather keyed on
// issue type could not see `gc.routed_to=human` on a task), and it surfaces as a
// GATE member of the family it hangs off — one of the two bands a ● marks as the
// operator's move — not as a family of its own.
it('surfaces the operator-owned bead as a gate row indented under its family', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/anchorless open PR/)).toBeTruthy());

  const row = rowFor(/anchorless open PR/);
  expect(row).not.toBeNull();
  expect(within(row as HTMLElement).getByText('gate')).toBeTruthy();
  expect(within(row as HTMLElement).getByText('routed to you — no question recorded')).toBeTruthy();
  expect(within(row as HTMLElement).getByText('2026-07-04')).toBeTruthy();
  // A ● marks the person's move on this row.
  expect((row as HTMLElement).textContent).toContain('●');
  // It is a MEMBER row indented under tk-epic, not a group or loose row of its own.
  expect((row as HTMLElement).className).toContain('row-member');
});

// A held row carries a VISIBLE, self-evident chip, not a bare glyph in a native
// title: it names the state in a word — waiting for the operator vs in session,
// a live sitting on it now — is a real button announced as interactive, and
// reveals the sittings (headline, state, session) in a details card reached by
// hover or focus rather than a native `title`. The wire's sitting_state and each
// sitting's state decide what the chip and the card say.
it('marks a held row with a visible waiting/in-session chip and reveals the sittings', async () => {
  const board: Board = {
    generated_at: '2026-08-26T08:00:00Z',
    total: 5,
    sittings: [
      {
        id: 'tk-vsit-engaged',
        rig: 'gc-toolkit',
        subject: 'tk-engaged',
        title: 'the engaged row',
        outcome_reason: '',
        session: 'gc-toolkit__converse-9',
        opened_at: '2026-08-26T07:00:00Z',
        takeaway: '',
        subject_title: 'what the engaged row is about',
        state: 'in_session',
        headline: 'what the engaged row is about',
      },
      {
        id: 'tk-vsit-parked',
        rig: 'gc-toolkit',
        subject: 'tk-parked',
        title: 'the parked row',
        outcome_reason: '',
        session: 'gc-toolkit__converse-8',
        opened_at: '2026-08-26T07:05:00Z',
        takeaway: '',
        subject_title: 'what the parked row is about',
        state: 'waiting',
        headline: 'what the parked row is about',
      },
    ],
    tiles: [
      tile({
        id: 'tk-fam',
        kind: 'epic',
        title: 'family root',
        severity: 'HIGH',
        section: 'stalled',
        m_total: 3,
        open: 3,
        group_root: 'tk-fam',
        frontier: '3 open',
        rank_score: 3_000_000,
      }),
      tile({
        id: 'tk-engaged',
        kind: 'task',
        title: 'engaged row',
        severity: 'NORMAL',
        section: 'active',
        held: true,
        sitting_state: 'in_session',
        group_root: 'tk-fam',
        frontier: 'in flight',
        rank_score: 2_500_000,
      }),
      tile({
        id: 'tk-parked',
        kind: 'task',
        title: 'parked row',
        severity: 'NORMAL',
        section: 'active',
        held: true,
        sitting_state: 'waiting',
        group_root: 'tk-fam',
        frontier: 'in flight',
        rank_score: 2_450_000,
      }),
      tile({
        id: 'tk-both',
        kind: 'review',
        title: 'held and gated',
        severity: 'ELEVATED',
        section: 'gate',
        held: true,
        work_held: true,
        sitting_state: 'in_session',
        group_root: 'tk-fam',
        frontier: 'PR #7',
        rank_score: 2_400_000,
      }),
      tile({
        id: 'tk-wants',
        kind: 'review',
        title: 'wants a person',
        severity: 'ELEVATED',
        section: 'review',
        group_root: 'tk-fam',
        frontier: 'PR #8',
        rank_score: 2_300_000,
      }),
    ],
  };
  vi.stubGlobal(
    'fetch',
    vi.fn(async (input: RequestInfo | URL) => {
      const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
      if (new URL(url, 'http://localhost/').pathname.endsWith('/helm')) {
        return new Response(JSON.stringify(board), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      }
      return new Response('{}', { status: 404, headers: { 'Content-Type': 'application/json' } });
    }),
  );

  render(<App />);
  await waitFor(() => expect(screen.getByText('engaged row')).toBeTruthy());

  // In session: a visible chip, a real button announced as interactive, naming the
  // live state in a word — and NO native title tooltip.
  const engaged = rowFor('engaged row') as HTMLElement;
  const engagedChip = within(engaged).getByRole('button', { name: /in session/i });
  expect(engagedChip.textContent).toContain('in session');
  expect(engagedChip.getAttribute('title')).toBeNull();
  // The details live in a real card, wired to the chip for assistive tech, naming
  // the sitting's headline, its state, and the session to attach to.
  expect(engagedChip.getAttribute('aria-describedby')).toBe('sitting-card-tk-engaged');
  const engagedCard = document.getElementById('sitting-card-tk-engaged') as HTMLElement;
  expect(engagedCard.textContent).toMatch(/being worked right now/i);
  expect(engagedCard.textContent).toContain('what the engaged row is about · in session · gc-toolkit__converse-9');

  // Waiting: a different word and heading, told apart from in session at a glance.
  const parked = rowFor('parked row') as HTMLElement;
  const parkedChip = within(parked).getByRole('button', { name: /waiting/i });
  expect(parkedChip.textContent).toContain('waiting');
  const parkedCard = document.getElementById('sitting-card-tk-parked') as HTMLElement;
  expect(parkedCard.textContent).toMatch(/waiting for you/i);
  expect(parkedCard.textContent).toContain('what the parked row is about · waiting');
  // A waiting sitting's last session is over, so the card offers none to attach to.
  expect(parkedCard.textContent).not.toContain('gc-toolkit__converse-8');

  // Held AND wants-person: the ● and the sitting chip both render, not one merged glyph.
  const both = rowFor('held and gated') as HTMLElement;
  expect(both.textContent).toContain('●');
  expect(within(both).getByRole('button', { name: /in session/i })).toBeTruthy();

  // What the row has rides the chip, read off work_held: a human gate holds the
  // work until the operator answers, and a conversation holds nothing. The card
  // says which in words, and a conversation-only chip wears its own outline.
  expect(engagedChip.textContent).toContain('conversation · in session');
  expect(engagedChip.getAttribute('aria-label')).toContain('the work is not held');
  expect(engagedCard.textContent).toContain('a conversation is on this bead and holds nothing: the work is not held');
  expect(engaged.querySelector('.sitting-marker--conversation')).not.toBeNull();
  expect(parkedChip.textContent).toContain('conversation · waiting');
  expect(parkedCard.textContent).toContain('the work is not held');
  const bothChip = within(both).getByRole('button', { name: /in session/i });
  expect(bothChip.textContent).toContain('gate · in session');
  expect(bothChip.getAttribute('aria-label')).toContain('a human gate holds the work until you answer');
  const bothCard = document.getElementById('sitting-card-tk-both') as HTMLElement;
  expect(bothCard.textContent).toContain('a human gate holds the work until you answer');
  expect(bothCard.textContent).not.toContain('not held');
  expect(both.querySelector('.sitting-marker--conversation')).toBeNull();

  // A plain person's move, unheld: the ● leads and there is no sitting chip.
  const wants = rowFor('wants a person') as HTMLElement;
  expect(wants.textContent).toContain('●');
  expect(within(wants).queryByRole('button', { name: /in session|waiting/i })).toBeNull();
});

// The key states what the row markers and tints mean, so the board's glyphs and
// colours are legible without hunting. It rides with the anchors table, naming
// both states the sitting marker distinguishes.
it('shows a key for the row markers and the state tints', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText('Attention Canvas')).toBeTruthy());

  const key = anchors().querySelector('.legend') as HTMLElement;
  expect(key).not.toBeNull();
  expect(key.textContent).toContain('needs you');
  expect(key.textContent).toContain('waiting for you');
  expect(key.textContent).toContain('a sitting in session');
  expect(key.textContent).toContain('a human gate or a conversation is on it');
  expect(key.textContent).toContain('gate = a human gate holds the work until you answer');
  expect(key.textContent).toContain('conversation = a conversation holds nothing, so the work is not held');
  expect(key.textContent).not.toContain('conversation holds it');
  expect(key.textContent).not.toContain('visit');
});

// Within a family the members read in SECTION_ORDER — the most-pressing move
// first — so review leads gate. Dependency structure is the top-level axis (the
// epic leads its members); the band orders WITHIN a family.
it('orders members within a family by the move they want', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText('Attention Canvas')).toBeTruthy());

  const epic = rowFor('Attention Canvas') as HTMLElement;
  const review = rowFor(/the canvas PR waiting on your review/) as HTMLElement;
  const gate = rowFor(/anchorless open PR/) as HTMLElement;
  expect(epic.className).toContain('row-group');
  expect(within(review).getByText('review')).toBeTruthy();
  expect(within(gate).getByText('gate')).toBeTruthy();
  // The epic leads, then its members in SECTION_ORDER: review before gate.
  expect(precedes(epic, review)).toBe(true);
  expect(precedes(review, gate)).toBe(true);
});

// A family nests as a tree: a member that is itself a parent (a sub-epic) renders
// as a sub-group above its own children, each row indented by its depth, rather
// than as a flat sibling beside them. The wire's group_parent draws the edges;
// group_root still names the top of the tree for every row.
it('nests a family as a tree, indenting each row by its depth', async () => {
  const board: Board = {
    generated_at: '2026-09-30T08:00:00Z',
    total: 3,
    sittings: [],
    tiles: [
      tile({
        id: 'tk-top',
        kind: 'epic',
        title: 'top epic',
        severity: 'HIGH',
        section: 'stalled',
        m_total: 1,
        open: 1,
        group_root: 'tk-top',
        rank_score: 3_000_000,
      }),
      tile({
        id: 'tk-sub',
        kind: 'epic',
        title: 'sub epic',
        severity: 'ELEVATED',
        section: 'active',
        m_total: 1,
        open: 1,
        group_root: 'tk-top',
        group_parent: 'tk-top',
        rank_score: 2_500_000,
      }),
      tile({
        id: 'tk-leaf',
        kind: 'task',
        title: 'leaf task',
        severity: 'NORMAL',
        section: 'active',
        group_root: 'tk-top',
        group_parent: 'tk-sub',
        rank_score: 2_000_000,
      }),
    ],
  };
  vi.stubGlobal(
    'fetch',
    vi.fn(async (input: RequestInfo | URL) => {
      const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
      if (new URL(url, 'http://localhost/').pathname.endsWith('/helm')) {
        return new Response(JSON.stringify(board), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      }
      return new Response('{}', { status: 404, headers: { 'Content-Type': 'application/json' } });
    }),
  );

  render(<App />);
  await waitFor(() => expect(screen.getByText('top epic')).toBeTruthy());

  const top = rowFor('top epic') as HTMLElement;
  const sub = rowFor('sub epic') as HTMLElement;
  const leaf = rowFor('leaf task') as HTMLElement;

  // Tree pre-order: the top epic, then its sub-epic, then the sub-epic's leaf —
  // the leaf sits under its own parent, not flat beside it.
  expect(precedes(top, sub)).toBe(true);
  expect(precedes(sub, leaf)).toBe(true);

  // The top root leads its family as a group row; the sub-epic and leaf nest as
  // members.
  expect(top.className).toContain('row-group');
  expect(sub.className).toContain('row-member');
  expect(leaf.className).toContain('row-member');

  // Depth rides the title cell as --depth: the root at 0, the sub-epic one step
  // in, the leaf one step deeper.
  const depthOf = (row: HTMLElement): string =>
    (row.querySelector('.title-cell') as HTMLElement).style.getPropertyValue('--depth');
  expect(depthOf(top)).toBe('0');
  expect(depthOf(sub)).toBe('1');
  expect(depthOf(leaf)).toBe('2');

  // A member that heads a sub-group reads as a header (family-title); a leaf does
  // not.
  expect(sub.querySelector('.family-title')?.textContent).toBe('sub epic');
  expect(leaf.querySelector('.family-title')).toBeNull();
});

// The board renders as ONE table, not a mini-table per family.
it('renders the whole board as one table', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText('Attention Canvas')).toBeTruthy());
  expect(within(anchors()).getAllByRole('table')).toHaveLength(1);
});

// A parent is a navigable header: its disclosure control folds the subtree
// below it and unfolds it again. Default is expanded — nothing is hidden until
// the operator folds it — so the members start visible.
it('folds and unfolds a parent subtree from its disclosure control', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText('Attention Canvas')).toBeTruthy());

  // Expanded by default: the epic's two members are on the board.
  expect(rowFor(/the canvas PR waiting on your review/)).not.toBeNull();
  expect(rowFor(/anchorless open PR/)).not.toBeNull();

  const epic = rowFor('Attention Canvas') as HTMLElement;
  fireEvent.click(within(epic).getByRole('button', { name: /collapse Attention Canvas/i }));

  // Folded: the members leave the DOM, the epic header stays.
  expect(rowFor('Attention Canvas')).not.toBeNull();
  expect(rowFor(/the canvas PR waiting on your review/)).toBeNull();
  expect(rowFor(/anchorless open PR/)).toBeNull();

  // The control now offers to expand, and does.
  fireEvent.click(
    within(rowFor('Attention Canvas') as HTMLElement).getByRole('button', {
      name: /expand Attention Canvas/i,
    }),
  );
  expect(rowFor(/the canvas PR waiting on your review/)).not.toBeNull();
  expect(rowFor(/anchorless open PR/)).not.toBeNull();
});

// What a fold leaves legible: the needs-you count shows whether folded or not —
// the one signal a collapse must not swallow — and the band breakdown of the
// hidden subtree shows only once it is folded, because an expanded parent has
// its rows below to carry it.
it('summarizes the subtree on the parent header, needs-you count always and the band spread when folded', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText('Attention Canvas')).toBeTruthy());

  // Expanded: the needs-you count is present (both members are owed); the band
  // breakdown is not, because the member rows are visible.
  let epic = rowFor('Attention Canvas') as HTMLElement;
  expect(epic.textContent).toContain('2 need you');
  expect(epic.textContent).not.toContain('1 review');

  fireEvent.click(within(epic).getByRole('button', { name: /collapse Attention Canvas/i }));

  // Folded: the needs-you count stays, and the band spread appears — one review
  // member, one gate member — so the family's shape reads without its rows.
  epic = rowFor('Attention Canvas') as HTMLElement;
  expect(epic.textContent).toContain('2 need you');
  expect(epic.textContent).toContain('1 review');
  expect(epic.textContent).toContain('1 gate');
});

// Folding hides rows; it never reorders them. The epic still leads the family
// below it after a fold, so the owed-first family order (#878/#911) is untouched.
it('does not reorder the board when a parent is folded', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText('Attention Canvas')).toBeTruthy());

  const epic = rowFor('Attention Canvas') as HTMLElement;
  const nextFamily = rowFor(/fix\+guard ruled/) as HTMLElement;
  expect(precedes(epic, nextFamily)).toBe(true);

  fireEvent.click(within(epic).getByRole('button', { name: /collapse Attention Canvas/i }));

  // The epic header still precedes the next family; nothing floated.
  expect(precedes(rowFor('Attention Canvas') as HTMLElement, rowFor(/fix\+guard ruled/) as HTMLElement)).toBe(
    true,
  );
});

// A fold is a durable view choice: it survives a remount, because it is kept in
// localStorage, not just React state. The board reinstates the operator's view
// the way it reinstates their context — by place.
it('persists a fold across a remount', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText('Attention Canvas')).toBeTruthy());
  fireEvent.click(
    within(rowFor('Attention Canvas') as HTMLElement).getByRole('button', {
      name: /collapse Attention Canvas/i,
    }),
  );
  expect(rowFor(/the canvas PR waiting on your review/)).toBeNull();

  // A fresh mount reads the persisted fold and starts collapsed.
  cleanup();
  render(<App />);
  await waitFor(() => expect(screen.getByText('Attention Canvas')).toBeTruthy());
  expect(rowFor(/the canvas PR waiting on your review/)).toBeNull();
  expect(
    within(rowFor('Attention Canvas') as HTMLElement).getByRole('button', {
      name: /expand Attention Canvas/i,
    }),
  ).toBeTruthy();
});

// The escape hatch: expand-all appears only once something is folded, and
// unfolds every parent so a row folded away is never lost.
it('offers expand-all only while something is folded, and unfolds everything', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText('Attention Canvas')).toBeTruthy());

  // Nothing folded: no escape hatch.
  expect(within(anchors()).queryByRole('button', { name: /expand all/i })).toBeNull();

  fireEvent.click(
    within(rowFor('Attention Canvas') as HTMLElement).getByRole('button', {
      name: /collapse Attention Canvas/i,
    }),
  );
  const expandAll = within(anchors()).getByRole('button', { name: /expand all/i });
  fireEvent.click(expandAll);

  expect(rowFor(/the canvas PR waiting on your review/)).not.toBeNull();
  expect(within(anchors()).queryByRole('button', { name: /expand all/i })).toBeNull();
});

// A leaf cannot fold: a single-item family (a loose row) carries no disclosure
// control, so the affordance appears only where there is a subtree to fold.
it('gives a loose row no disclosure control', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText('Attention Canvas')).toBeTruthy());

  const loose = rowFor(/fix\+guard ruled/) as HTMLElement;
  expect(loose.className).toContain('row-loose');
  expect(within(loose).queryByRole('button', { name: /collapse|expand/i })).toBeNull();
});

// Degrade: a family whose members carry no group_parent renders as a flat
// one-level list under its root (the #911 safe degrade), and that root still
// folds — the disclosure works whether the family is a deep tree or a flat list.
it('folds a flat (unstamped group_parent) family from its root', async () => {
  const board: Board = {
    generated_at: '2026-09-30T08:00:00Z',
    total: 3,
    sittings: [],
    tiles: [
      tile({
        id: 'tk-flat',
        kind: 'epic',
        title: 'flat root',
        severity: 'HIGH',
        section: 'stalled',
        m_total: 2,
        open: 2,
        group_root: 'tk-flat',
      }),
      tile({
        id: 'tk-m1',
        kind: 'task',
        title: 'flat member one',
        severity: 'NORMAL',
        section: 'active',
        group_root: 'tk-flat',
      }),
      tile({
        id: 'tk-m2',
        kind: 'task',
        title: 'flat member two',
        severity: 'NORMAL',
        section: 'active',
        group_root: 'tk-flat',
      }),
    ],
  };
  vi.stubGlobal(
    'fetch',
    vi.fn(async (input: RequestInfo | URL) => {
      const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
      if (new URL(url, 'http://localhost/').pathname.endsWith('/helm')) {
        return new Response(JSON.stringify(board), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      }
      return new Response('{}', { status: 404, headers: { 'Content-Type': 'application/json' } });
    }),
  );

  render(<App />);
  await waitFor(() => expect(screen.getByText('flat root')).toBeTruthy());
  // Both members hang directly off the root (depth 1) — the flat degrade.
  const depthOf = (row: HTMLElement): string =>
    (row.querySelector('.title-cell') as HTMLElement).style.getPropertyValue('--depth');
  expect(depthOf(rowFor('flat member one') as HTMLElement)).toBe('1');

  fireEvent.click(
    within(rowFor('flat root') as HTMLElement).getByRole('button', { name: /collapse flat root/i }),
  );
  expect(rowFor('flat member one')).toBeNull();
  expect(rowFor('flat member two')).toBeNull();
});

// The needs-you highlight rides the row in place; the board keeps wire order and
// does not float the operator's rows to the top. The stranded epic leads because
// it leads the wire, even though its own next move is not the operator's.
it('highlights needs-you rows in place without reordering the board', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText('Attention Canvas')).toBeTruthy());

  const epic = rowFor('Attention Canvas') as HTMLElement;
  const review = rowFor(/the canvas PR waiting on your review/) as HTMLElement;
  expect(epic.className).not.toContain('row-wants-person');
  expect(review.className).toContain('row-wants-person');
  // The needs-you review row sits BELOW the non-needs-you epic — no float-to-top.
  expect(precedes(epic, review)).toBe(true);
});

// A held row — a human gate holds the bead or a conversation is on it — carries the row
// tint too, the second of the two signals the highlight speaks.
it('highlights a held row in place', async () => {
  serve([
    tile({
      id: 'tk-held',
      kind: 'human',
      title: 'an anchor a sitting talks over',
      severity: 'NORMAL',
      section: 'active',
      held: true,
      needs: 'a sitting has this open',
    }),
  ]);
  render(<App />);
  await waitFor(() => expect(screen.getByText(/a sitting talks over/)).toBeTruthy());

  const row = rowFor(/a sitting talks over/) as HTMLElement;
  expect(row.className).toContain('row-held');
});

// A recommendation Accept is withheld on says why where the button would be —
// the other gates to answer first — and a row whose gate a live sitting is
// answering names that gate beside its needs, as the CLI board's NEEDS cell
// does.
it('names the gates that withhold Accept and the gates in session', async () => {
  serve([
    tile({
      id: 'tk-rec',
      kind: 'parked',
      title: 'a recommendation behind another gate',
      severity: 'NORMAL',
      section: 'gate',
      owed: true,
      held: true,
      sitting_state: 'in_session',
      needs: '2× — Accept? · Rule on the finding',
      accept_withheld: 'Rule on the finding',
      gates_in_session: 'Rule on the finding',
    }),
  ]);
  render(<App />);
  await waitFor(() => expect(screen.getByText(/a recommendation behind another gate/)).toBeTruthy());

  const row = rowFor(/a recommendation behind another gate/) as HTMLElement;
  expect(row.textContent).toContain('in session: Rule on the finding');
  expect(row.textContent).toContain('accept waits on: Rule on the finding');
  expect(within(row).queryByRole('button', { name: /accept/i })).toBeNull();
});

// The Accept affordance is the board's one row-level actuation: it renders only
// where the wire says the row is `acceptable`, names the formula it would
// dispatch, and — proven in ActuateButton.test.tsx — POSTs helm/accept. A
// discuss-only row (acceptable false) carries no button, the same split the CLI
// board's "accept ▸" marker makes.
it('renders Accept on an acceptable member row and not on a discuss-only one', async () => {
  serve([
    tile({ id: 'tk-root', kind: 'epic', title: 'the family root', severity: 'NORMAL', section: 'active' }),
    tile({
      id: 'tk-rec',
      kind: 'gate',
      title: 'a recommendation to accept',
      severity: 'ELEVATED',
      section: 'gate',
      group_root: 'tk-root',
      acceptable: true,
      accept_formula: 'mol-dispose-pr',
      needs: 'ruling recorded — accept to actuate',
    }),
    tile({
      id: 'tk-plain',
      kind: 'gate',
      title: 'a discuss-only gate',
      severity: 'ELEVATED',
      section: 'gate',
      group_root: 'tk-root',
      needs: "let's talk it through",
    }),
  ]);
  render(<App />);
  await waitFor(() => expect(screen.getByText(/a recommendation to accept/)).toBeTruthy());

  const rec = rowFor(/a recommendation to accept/);
  expect(within(rec as HTMLElement).getByRole('button', { name: /accept ▸ mol-dispose-pr/i })).toBeTruthy();

  const plain = rowFor(/a discuss-only gate/);
  expect(within(plain as HTMLElement).queryByRole('button', { name: /accept/i })).toBeNull();
});

// The first-reaction card rides the acceptable row: its Proposal and
// Decision-needed are one disclosure away from the Accept button, so the
// decision point shows WHY, not only the one-line needs. A row the wire gives no
// recommendation carries no disclosure.
it('folds the first-reaction recommendation under an acceptable row', async () => {
  serve([
    tile({ id: 'tk-root', kind: 'epic', title: 'the family root', severity: 'NORMAL', section: 'active' }),
    tile({
      id: 'tk-rec',
      kind: 'gate',
      title: 'a recommendation to accept',
      severity: 'ELEVATED',
      section: 'gate',
      group_root: 'tk-root',
      acceptable: true,
      accept_formula: 'mol-polecat-work',
      needs: 'recommend: fix the thing',
      recommendation: '## Proposal\nFix the thing.\n\n## Decision needed\nAccept or redirect the scope.',
    }),
    tile({
      id: 'tk-plain',
      kind: 'gate',
      title: 'a discuss-only gate',
      severity: 'ELEVATED',
      section: 'gate',
      group_root: 'tk-root',
      acceptable: true,
      accept_formula: 'mol-polecat-work',
      needs: "let's talk it through",
    }),
  ]);
  render(<App />);
  await waitFor(() => expect(screen.getByText(/a recommendation to accept/)).toBeTruthy());

  const rec = rowFor(/a recommendation to accept/) as HTMLElement;
  // The disclosure is labelled and holds the card body, so one open at the
  // decision point reveals the Proposal and the Decision needed.
  expect(within(rec).getByText('recommendation')).toBeTruthy();
  expect(within(rec).getByText(/Decision needed/)).toBeTruthy();
  expect(within(rec).getByText(/Accept or redirect the scope/)).toBeTruthy();

  // An acceptable row the wire gave no recommendation shows the Accept button
  // but no card disclosure — the field's presence is the only gate.
  const plain = rowFor(/a discuss-only gate/) as HTMLElement;
  expect(within(plain).queryByText('recommendation')).toBeNull();
});

// A single-item family that is itself a recommendation renders as a plain loose
// row, with Accept in its needs cell — the same column a member row carries it.
it('renders Accept on an acceptable root that stands as a loose row', async () => {
  serve([
    tile({
      id: 'tk-recroot',
      kind: 'decision',
      title: 'a root that is itself a recommendation',
      severity: 'ELEVATED',
      section: 'gate',
      acceptable: true,
      accept_formula: 'mol-supersede',
      needs: 'ruling recorded — accept to actuate',
    }),
  ]);
  render(<App />);
  await waitFor(() => expect(screen.getByText(/a root that is itself a recommendation/)).toBeTruthy());

  const row = rowFor(/a root that is itself a recommendation/) as HTMLElement;
  expect(row.className).toContain('row-loose');
  expect(within(row).getByRole('button', { name: /accept ▸ mol-supersede/i })).toBeTruthy();
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
// stranded epics: it gets the cleanup band, carries its ask, and — as a family
// of one — stands as a plain loose row rather than being swept under the epic.
it('lists a quiet parked conversation as a cleanup loose row', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/helm returns the raw script path/)).toBeTruthy());

  const row = rowFor(/helm returns the raw script path/) as HTMLElement;
  expect(row.className).toContain('row-loose');
  expect(within(row).getByText(/cleanup/)).toBeTruthy();
  expect(within(row).getByText(/parked for you — no question recorded/)).toBeTruthy();
});

it('counts owed, live, and closed separately in the header', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/3 owed · 6 anchors · 1 closed/)).toBeTruthy());
});

// The layout-stability rule: a row the operator was looking at does not leave
// because it was answered. It stays a dimmed done row and ages out on the window
// clock, with no manual clear; the table states that bound once, below it.
it('keeps a closed anchor on the board as a dimmed done row that names the window', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/takeaway cap conversation/)).toBeTruthy());

  const row = rowFor(/takeaway cap conversation/) as HTMLElement;
  expect(within(row).getByText(/closed 1d ago/)).toBeTruthy();
  expect(within(row).getByText('done')).toBeTruthy();
  expect(row.className).toContain('row-done');
  // The window bound is stated once under the table, for every DONE row — the
  // operator's only statement of what the band promises.
  expect(within(anchors()).getByText(/GC_HELM_DONE_WINDOW/)).toBeTruthy();
});

// The defect this split exists to prevent (tk-2plde): a subject that routed work
// out of a sitting kept saying "nothing further needed here" after that work
// merged. Once the blocker closes it owes a disposition, so it bands gate — a
// parked row the operator has to open to discover is the bug.
it('bands a parked row whose blocker landed as a gate, not cleanup', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/fix\+guard ruled/)).toBeTruthy());

  const row = rowFor(/fix\+guard ruled/) as HTMLElement;
  expect(within(row).getByText('gate')).toBeTruthy();
  expect(row.textContent).not.toMatch(/cleanup/);
  expect(within(row).getByText(/blocker landed — dispose or resume/)).toBeTruthy();
});

// The defect tk-a9k0l is about. A parked subject that decomposed keeps its
// takeaway, so it stays kind `parked`, and its open child is not a tile of its
// own. Stranded, it bands stalled, carrying the roll-up.
it('bands a parked row with open children as stalled, not cleanup', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/composition-seam doc/)).toBeTruthy());

  const row = rowFor(/composition-seam doc/) as HTMLElement;
  expect(within(row).getByText('stalled')).toBeTruthy();
  expect(row.textContent).not.toMatch(/cleanup/);
  expect(row.textContent).toMatch(/1\/2/);
  expect(within(row).getByText(/1 open · 0 in flight \(stranded\)/)).toBeTruthy();
});

it('drills into a row by its id like any other tile', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText(/helm returns the raw script path/)).toBeTruthy());

  const row = rowFor(/helm returns the raw script path/) as HTMLElement;
  fireEvent.click(within(row).getByRole('button', { name: 'tk-yps55' }));
  expect(screen.getByRole('complementary', { name: /detail for tk-yps55/i })).toBeTruthy();
});

it('resolveDrillTarget reads ?drill= and ignores everything else', () => {
  expect(resolveDrillTarget('')).toBeNull();
  expect(resolveDrillTarget('?other=1')).toBeNull();
  expect(resolveDrillTarget('?drill=')).toBeNull();
  expect(resolveDrillTarget('?drill=%20%20')).toBeNull();
  expect(resolveDrillTarget('?drill=tk-abc12')).toBe('tk-abc12');
  expect(resolveDrillTarget('?drill=tk-abc12.3')).toBe('tk-abc12.3');
});

// A `?drill=<bead>` deep link opens the board straight on that row's drill
// panel — the target end of a link from a pull request back to a board move.
it('opens the drill panel for a ?drill= deep link on load', async () => {
  window.history.replaceState({}, '', '?drill=tk-yps55');
  try {
    render(<App />);
    await waitFor(() =>
      expect(screen.getByRole('complementary', { name: /detail for tk-yps55/i })).toBeTruthy(),
    );
  } finally {
    window.history.replaceState({}, '', '/');
  }
});

// A board renders exactly the rows it holds — never one for a tile that is not
// on the wire.
it('renders only the rows present', async () => {
  const stalledOnly: Board = { ...BOARD, total: 1, tiles: [BOARD.tiles![1]], sittings: null };
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => new Response(JSON.stringify(stalledOnly), { status: 200 })),
  );

  render(<App />);
  await waitFor(() => expect(screen.getByText('Attention Canvas')).toBeTruthy());
  expect(rowFor('Attention Canvas')).not.toBeNull();
  expect(rowFor(/helm returns the raw script path/)).toBeNull();
  expect(screen.getByText(/1 anchors · generated/)).toBeTruthy();
});

// The record is not an attention list: a sitting must not appear as a row in the
// anchors table, where it would compete with work that needs doing.
it('keeps sittings out of the anchors table', async () => {
  render(<App />);
  await waitFor(() => expect(region('converse sittings')).toBeTruthy());

  expect(rowFor('tk-vst01')).toBeNull();
  expect(within(anchors()).queryByText(/what the canvas owes the operator/)).toBeNull();
});

it('shows where each sitting stands and what the recently closed ones concluded', async () => {
  render(<App />);
  await waitFor(() => expect(region('converse sittings')).toBeTruthy());

  const section = region('converse sittings');
  expect(within(section).getByText(/1 in session · 0 waiting · 1 closed recently/)).toBeTruthy();
  expect(within(section).queryByText('outcome')).toBeNull();

  const live = within(section).getByText('tk-vst01').closest('tr') as HTMLElement;
  expect(within(live).getByText('in session')).toBeTruthy();
  expect(within(live).getByText('40m')).toBeTruthy();
  // No takeaway: the headline is the subject's title (the topic), not the
  // conversation's own title. The topic also labels the subject cell.
  expect(within(live).getAllByText(/the attention-canvas epic topic/).length).toBeGreaterThan(0);
  expect(within(live).queryByText(/what the canvas owes the operator/)).toBeNull();

  const done = within(section).getByText('tk-vst02').closest('tr') as HTMLElement;
  expect(within(done).getByText('closed')).toBeTruthy();
  // A takeaway wins the headline; the subject title labels the subject cell.
  expect(within(done).getByText(/the path was the launcher/)).toBeTruthy();
  expect(within(done).getByText('the raw-path launcher finding')).toBeTruthy();
});

it('shows a closed conversation’s close reason as its headline when it left no takeaway', async () => {
  const dismissed: Board = {
    ...BOARD,
    sittings: [
      {
        id: 'tk-vst10',
        rig: 'gc-toolkit',
        subject: 'tk-epic',
        title: 'operator pick from the board',
        outcome_reason: 'dismissed by the operator: superseded by the new plan',
        session: 'gc-toolkit__converse-10',
        opened_at: '2026-08-21T18:34:00Z',
        closed_at: '2026-08-21T18:40:00Z',
        takeaway: '',
        subject_title: 'the attention-canvas epic topic',
        state: 'closed',
        headline: 'dismissed by the operator: superseded by the new plan',
      },
    ],
  };
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => new Response(JSON.stringify(dismissed), { status: 200 })),
  );

  render(<App />);
  await waitFor(() => expect(region('converse sittings')).toBeTruthy());

  const row = within(region('converse sittings')).getByText('tk-vst10').closest('tr') as HTMLElement;
  // No takeaway: the headline is the close reason (why it closed), so the
  // dismissal reads as a decision rather than falling back to the topic.
  expect(within(row).getByText('dismissed by the operator: superseded by the new plan')).toBeTruthy();
  expect(within(row).queryByText(/operator pick from the board/)).toBeNull();
});

// One sitting in each state, all on one bead, as the wire carries them. The
// takeaway and the close reason differ from the headline, so a test that reads
// the headline proves it was printed rather than re-derived.
function sittingIn(state: string, id: string, headline: string): Sitting {
  return {
    id,
    rig: 'gc-toolkit',
    subject: 'tk-subj',
    title: `the conversation ${id}`,
    outcome_reason: 'not the headline',
    session: `gc-toolkit__converse-${id}`,
    opened_at: '2026-08-21T18:34:00Z',
    closed_at: state === 'closed' ? '2026-08-21T18:40:00Z' : undefined,
    takeaway: 'not the headline either',
    subject_title: 'the subject',
    state,
    headline,
  };
}

const EVERY_STATE: Sitting[] = [
  sittingIn('in_session', 'tk-s1', 'headline of the live one'),
  sittingIn('waiting', 'tk-s2', 'headline of the waiting one'),
  sittingIn('start-failed', 'tk-s3', 'headline of the failed one'),
  sittingIn('closed', 'tk-s4', 'headline of the closed one'),
];

// The operator's question of this table is whether a sitting is waiting or has
// an active session, so each row prints the wire's state in a word and the count
// line splits the open ones the same way.
it('prints the state and headline the wire carries in the sittings table', async () => {
  serveBoard({ ...BOARD, sittings: EVERY_STATE });
  render(<App />);
  await waitFor(() => expect(region('converse sittings')).toBeTruthy());

  const section = region('converse sittings');
  expect(within(section).getByText(/1 in session · 1 waiting · 1 start failed · 1 closed recently/)).toBeTruthy();
  expect(section.textContent).not.toContain('running');

  // An open sitting's age runs from its start, and a closed one's from its end.
  const cases: [string, string, string, string][] = [
    ['tk-s1', 'in session', '40m', 'headline of the live one'],
    ['tk-s2', 'waiting', '40m', 'headline of the waiting one'],
    ['tk-s3', 'start failed', '40m', 'headline of the failed one'],
    ['tk-s4', 'closed', '34m', 'headline of the closed one'],
  ];
  for (const [id, word, age, headline] of cases) {
    const row = within(section).getByText(id).closest('tr') as HTMLTableRowElement;
    expect(row.cells[0].textContent).toBe(word);
    expect(row.cells[4].textContent).toBe(age);
    expect(within(row).getByText(headline)).toBeTruthy();
    expect(within(row).queryByText(/not the headline/)).toBeNull();
  }
  // Only the sitting a live session holds is the row to join.
  const emphasised = Array.from(section.querySelectorAll('tr.sitting-in-session'));
  expect(emphasised.map((r) => (r as HTMLTableRowElement).cells[1].textContent)).toEqual(['tk-s1']);
});

// The hover card prints the same word and headline for each sitting as the
// table does, whatever the row's own roll-up reads, and offers a session only
// for the sitting in session, the one that can be attached to.
it('prints each sitting’s state and headline in the hover card', async () => {
  serveBoard({
    ...BOARD,
    sittings: EVERY_STATE,
    tiles: [
      tile({
        id: 'tk-subj',
        kind: 'task',
        title: 'the row with every sitting',
        severity: 'ELEVATED',
        section: 'gate',
        owed: true,
        held: true,
        sitting_state: 'start-failed',
        sitting_start_failure: 'setup timeout',
      }),
    ],
  });
  render(<App />);
  await waitFor(() => expect(screen.getByText('the row with every sitting')).toBeTruthy());

  const card = document.getElementById('sitting-card-tk-subj') as HTMLElement;
  const entries = Array.from(card.querySelectorAll('.sitting-card__sitting')).map((e) => e.textContent);
  expect(entries).toEqual([
    'headline of the live one · in session · gc-toolkit__converse-tk-s1',
    'headline of the waiting one · waiting',
    'headline of the failed one · start failed',
    'headline of the closed one · closed',
  ]);
});

// A failed start is the state nothing else on the row would say, so the chip
// says it in words, with the reason in its card and its label, on a subject's
// held row and on a conversation's own row, whose subject has no live row.
it('reads a failed start on the chip of a held row and of a conversation’s own row', async () => {
  serveBoard({
    ...BOARD,
    sittings: [{ ...sittingIn('start-failed', 'tk-own', 'the ask nobody started on'), subject: 'tk-gone' }],
    tiles: [
      tile({
        id: 'tk-held',
        kind: 'task',
        title: 'a held row',
        severity: 'ELEVATED',
        section: 'gate',
        owed: true,
        held: true,
        work_held: true,
        sitting_state: 'start-failed',
        sitting_start_failure: 'setup timeout',
        needs: 'start failed (setup timeout): rule on it',
      }),
      tile({
        id: 'tk-own',
        kind: 'conversation',
        title: 'conversation: tk-gone',
        severity: 'ELEVATED',
        section: 'gate',
        owed: true,
        held: true,
        sitting_state: 'start-failed',
        sitting_start_failure: 'provider error: model_not_found',
        needs: 'start failed (provider error: model_not_found): the ask',
      }),
    ],
  });
  render(<App />);
  await waitFor(() => expect(screen.getByText('a held row')).toBeTruthy());

  const heldChip = within(rowFor('a held row') as HTMLElement).getByRole('button', { name: /start failed/i });
  expect(heldChip.textContent).toContain('✗');
  expect(heldChip.textContent).toContain('gate · start failed');
  expect(heldChip.getAttribute('aria-label')).toContain('setup timeout');
  expect(heldChip.parentElement?.className).toContain('sitting-marker--start-failed');
  expect(document.getElementById('sitting-card-tk-held')?.textContent).toContain('Start failed — setup timeout');

  const ownChip = within(rowFor('conversation: tk-gone') as HTMLElement).getByRole('button', { name: /start failed/i });
  expect(ownChip.textContent).toContain('conversation · start failed');
  const ownCard = document.getElementById('sitting-card-tk-own') as HTMLElement;
  expect(ownCard.textContent).toContain('Start failed — provider error: model_not_found');
  // The row is the sitting's own, so its card names that sitting too.
  expect(ownCard.textContent).toContain('the ask nobody started on · start failed');
});

it('drills into a sitting by its subject', async () => {
  render(<App />);
  await waitFor(() => expect(region('converse sittings')).toBeTruthy());

  // The subject cell is labelled by its topic (the subject's title) but still
  // drills by the subject id — the id rides along as the button's hover title.
  fireEvent.click(
    within(region('converse sittings')).getByRole('button', { name: 'the attention-canvas epic topic' }),
  );
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
  expect(queryRegion('converse sittings')).toBeNull();
});

it('ages a sitting against the board it came from, not the clock', async () => {
  const later: Board = { ...BOARD, generated_at: '2026-08-21T21:14:00Z' };
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => new Response(JSON.stringify(later), { status: 200 })),
  );

  render(<App />);
  await waitFor(() => expect(region('converse sittings')).toBeTruthy());

  const live = within(region('converse sittings')).getByText('tk-vst01').closest('tr') as HTMLElement;
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

// Serve one family: a bare root and the given merge-anchor member beneath it, so
// the PR row renders as a member row indented under it, with its link, needs and
// owed-since.
function servePRUnder(rootId: string, pr: Tile) {
  serve([
    tile({ id: rootId, kind: 'epic', title: 'the family root', severity: 'NORMAL', section: 'active' }),
    { ...pr, group_root: rootId },
  ]);
}

// A merge anchor bands review, and the row says WHY nothing is moving: "routed
// to a person" alone reads identically for an anchor awaiting a ruling and for
// one a conflict blocks, where the release is bringing the branch current.
it('names the block and links the pull request', async () => {
  servePRUnder('tk-root', prTile({
    id: 'tk-blk',
    title: 'a pull request a conflict blocks',
    pr_machine: 'blocked',
    pr_number: 513,
    pr_url: 'https://github.com/zook/gc-toolkit/pull/513',
    needs: "blocked: the branch conflicts with 'main' and no merge-in rework is in flight",
  }));
  render(<App />);
  await waitFor(() => expect(screen.getByText(/a pull request a conflict blocks/)).toBeTruthy());

  const row = rowFor(/a pull request a conflict blocks/);
  expect(row).not.toBeNull();
  expect(within(row as HTMLElement).getByText(/blocked: the branch conflicts/)).toBeTruthy();

  const link = within(row as HTMLElement).getByRole('link', { name: 'PR #513' });
  expect(link.getAttribute('href')).toBe('https://github.com/zook/gc-toolkit/pull/513');
});

// The row is a MERGE ANCHOR's, not a pull request's. An anchor at pre_open_gate
// has no pull request at all, so a surface that could only identify a row by its
// number would have nothing to show for it.
it('identifies a pre-open row without inventing a link', async () => {
  servePRUnder('tk-root', prTile({ id: 'tk-pre', title: 'held before the PR opened' }));
  render(<App />);
  await waitFor(() => expect(screen.getByText(/held before the PR opened/)).toBeTruthy());

  const row = rowFor(/held before the PR opened/);
  expect(within(row as HTMLElement).queryByRole('link')).toBeNull();
  expect(within(row as HTMLElement).getByText('polecat/tk-pre')).toBeTruthy();
});

// The pre-PR branch is browsable: when the board resolved the rig's repository,
// the branch string links to its GitHub tree view rather than reading as bare
// text.
it('links a pre-open branch to GitHub when the repo is known', async () => {
  servePRUnder('tk-root', prTile({
    id: 'tk-link',
    title: 'a pre-open branch with a known repo',
    pr_branch: 'polecat/tk-link',
    pr_branch_url: 'https://github.com/zook/gc-toolkit/tree/polecat/tk-link',
  }));
  render(<App />);
  await waitFor(() => expect(screen.getByText(/a pre-open branch with a known repo/)).toBeTruthy());

  const row = rowFor(/a pre-open branch with a known repo/);
  const link = within(row as HTMLElement).getByRole('link', { name: 'polecat/tk-link' });
  expect(link.getAttribute('href')).toBe('https://github.com/zook/gc-toolkit/tree/polecat/tk-link');
});

// The phase chip names who must act next in the same words the GitHub status:
// label carries, so the board and the label do not read as two vocabularies.
it('shows the PR phase beside the row', async () => {
  servePRUnder('tk-root', prTile({
    id: 'tk-ph',
    title: 'a row that needs a review',
    pr_phase: 'needs-review',
  }));
  render(<App />);
  await waitFor(() => expect(screen.getByText(/a row that needs a review/)).toBeTruthy());

  const row = rowFor(/a row that needs a review/);
  expect(within(row as HTMLElement).getByText('needs-review')).toBeTruthy();
});

// An approved PR the city is landing reads merging, in its own color, so it no
// longer shares the working chip with a PR the city is still changing. The chip
// builds its class from any phase it is given, so the color is pinned on the
// stylesheet, read from disk because the suite loads no CSS: without a rule of
// its own, a merging chip renders in the chip's plain text color.
it('shows merging on the chip of a PR the city is landing', async () => {
  servePRUnder('tk-root', prTile({
    id: 'tk-mg',
    title: 'an approved row being landed',
    pr_phase: 'merging',
  }));
  render(<App />);
  await waitFor(() => expect(screen.getByText(/an approved row being landed/)).toBeTruthy());

  const row = rowFor(/an approved row being landed/);
  const chip = within(row as HTMLElement).getByText('merging');
  expect(chip.className).toBe('pr-phase pr-phase--merging');
  const styles = readFileSync(join(import.meta.dirname, 'styles.css'), 'utf8');
  expect(styles).toMatch(/\.pr-phase--merging\s*\{[^}]*\bcolor:\s*#[0-9a-fA-F]{3,8}\s*;/);
});

// A resolved PR names its terminal state on the same chip, so a done row says how
// its PR ended — merged or closed — rather than freezing on its last live phase.
it('shows a resolved PR state on the chip', async () => {
  servePRUnder('tk-root', prTile({
    id: 'tk-merged',
    title: 'a row whose PR has merged',
    pr_phase: 'merged',
  }));
  render(<App />);
  await waitFor(() => expect(screen.getByText(/a row whose PR has merged/)).toBeTruthy());

  const row = rowFor(/a row whose PR has merged/);
  const chip = within(row as HTMLElement).getByText('merged');
  expect(chip.className).toContain('pr-phase--merged');
});

// What holds a PR rides its row as one chip per held: label, read off the wire
// in its order, each with hover text saying what it asks of the operator, in a
// colour of its own pinned on the stylesheet. A PR nothing holds carries none.
it('shows what holds a PR beside its phase, one chip per held value', async () => {
  serve([
    tile({ id: 'tk-root', kind: 'epic', title: 'the family root', severity: 'NORMAL', section: 'active' }),
    {
      ...prTile({ id: 'tk-held', title: 'a pull request a gate and a blocker hold', pr_phase: 'needs-attention', pr_held: ['gate', 'blocked'] }),
      group_root: 'tk-root',
    },
    {
      ...prTile({ id: 'tk-free', title: 'a pull request nothing holds', pr_phase: 'merging', pr_held: null }),
      group_root: 'tk-root',
    },
  ]);
  render(<App />);
  await waitFor(() => expect(screen.getByText('a pull request a gate and a blocker hold')).toBeTruthy());

  const held = rowFor('a pull request a gate and a blocker hold') as HTMLElement;
  const chips = Array.from(held.querySelectorAll('.pr-held')).map((c) => c.textContent);
  expect(chips).toEqual(['held: gate', 'held: blocked']);
  expect(within(held).getByText('held: gate').getAttribute('title')).toMatch(/^held: gate: \S/);
  expect(within(held).getByText('held: blocked').className).toBe('pr-held pr-held--blocked');

  const free = rowFor('a pull request nothing holds') as HTMLElement;
  expect(free.querySelectorAll('.pr-held')).toHaveLength(0);

  const styles = readFileSync(join(import.meta.dirname, 'styles.css'), 'utf8');
  expect(styles).toMatch(/\.pr-held\s*\{[^}]*\bcolor:\s*#[0-9a-fA-F]{3,8}\s*;/);
  const key = anchors().querySelector('.legend') as HTMLElement;
  expect(key.textContent).toContain('what holds a PR: gate = an open human gate on the PR');
});

// The conversation axis is how the board shows which pull requests carry the
// operator's comments, so each live PR row names where its conversation stands
// in the wire's own word, and an unread one says unknown rather than quiet.
it('shows where each PR conversation stands on its row', async () => {
  const values = ['quiet', 'outstanding', 'answered', 'asking', 'unknown'];
  serve([
    tile({ id: 'tk-root', kind: 'epic', title: 'the family root', severity: 'NORMAL', section: 'active' }),
    ...values.map((v) => ({
      ...prTile({ id: `tk-${v}`, title: `a pull request reading ${v}`, pr_conversation: v }),
      group_root: 'tk-root',
    })),
  ]);
  render(<App />);
  await waitFor(() => expect(screen.getByText('a pull request reading quiet')).toBeTruthy());

  for (const v of values) {
    const row = rowFor(`a pull request reading ${v}`);
    expect(row).not.toBeNull();
    const chip = within(row as HTMLElement).getByText(v);
    expect(chip.className).toContain(`pr-conversation--${v}`);
    expect(chip.getAttribute('title')).toMatch(new RegExp(`^conversation ${v}: \\S`));
  }
});

// A finished pull request's conversation is nobody's move, and a row that is not
// a merge anchor has no pull request to speak on, so neither carries the chip.
it('shows no conversation on a closed PR row or a row that is not a PR', async () => {
  serve([
    tile({ id: 'tk-root', kind: 'epic', title: 'the family root', severity: 'NORMAL', section: 'active' }),
    {
      ...prTile({
        id: 'tk-landed',
        title: 'a pull request that landed',
        owed: false,
        severity: 'DONE',
        section: 'done',
        closed_at: '2026-08-20T19:14:00Z',
        pr_conversation: 'answered',
        pr_owed_since: undefined,
        needs: 'closed — ages out',
      }),
      group_root: 'tk-root',
    },
  ]);
  render(<App />);
  await waitFor(() => expect(screen.getByText('a pull request that landed')).toBeTruthy());

  expect(rowFor('a pull request that landed')?.querySelector('.pr-conversation')).toBeNull();
  expect(rowFor('the family root')?.querySelector('.pr-conversation')).toBeNull();
});

// An anchor at a human state carries merge_result and can carry no branch and no
// number, and a cell that named an absence as an identity is the same failure
// inverted.
it('says so on a row that records neither number nor branch', async () => {
  servePRUnder('tk-root', prTile({ id: 'tk-bare', title: 'a merge anchor with no branch recorded', pr_branch: '' }));
  render(<App />);
  await waitFor(() => expect(screen.getByText(/no branch recorded/)).toBeTruthy());

  const row = rowFor(/no branch recorded/);
  expect(within(row as HTMLElement).getByText('not open yet')).toBeTruthy();
});

// The queue is ordered by how long a row has been owed, and pr_owed_since is the
// only stamp on a merge anchor that dates the TURN.
it('dates an owed PR row by its turn, not by the last pass that touched it', async () => {
  servePRUnder('tk-root', prTile({
    id: 'tk-old',
    title: 'owed for three days',
    pr_owed_since: '2026-08-08T11:02:00Z',
    updated_at: '2026-08-11T14:55:00Z',
  }));
  render(<App />);
  await waitFor(() => expect(screen.getByText(/owed for three days/)).toBeTruthy());

  const row = rowFor(/owed for three days/);
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
  expect(sub.textContent).toMatch(/where the conversation stands \(the merge cadence has not recorded it\)/);
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
      pr_approval: 'met',
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

// --- the rig filter -----------------------------------------------------------

// A cross-rig board with rows in two rigs and a third rig that did not answer,
// so the filter has something to choose between and the partial-gather signal
// is live to check the filter against.
const MULTI_RIG: Board = {
  generated_at: '2026-09-01T12:00:00Z',
  total: 2,
  partial: true,
  partial_errors: ['rig rig-b: context canceled'],
  tiles: [
    tile({ id: 'tk-gct', kind: 'epic', title: 'the gc-toolkit family', severity: 'NORMAL', section: 'active', rig: 'gc-toolkit' }),
    tile({ id: 'tk-gcy', kind: 'epic', title: 'the gascity family', severity: 'NORMAL', section: 'active', rig: 'gascity' }),
  ],
  sittings: [
    {
      id: 'tk-vs-gct', rig: 'gc-toolkit', subject: 'tk-gct', title: 'about tk-gct',
      outcome_reason: 'settled', session: 'gc-toolkit__converse-1',
      opened_at: '2026-09-01T10:00:00Z', closed_at: '2026-09-01T11:00:00Z',
      takeaway: '', subject_title: 'the gc-toolkit topic',
      state: 'closed', headline: 'settled',
    },
    {
      id: 'tk-vs-gcy', rig: 'gascity', subject: 'tk-gcy', title: 'about tk-gcy',
      outcome_reason: 'settled', session: 'gascity__converse-1',
      opened_at: '2026-09-01T10:00:00Z', closed_at: '2026-09-01T11:00:00Z',
      takeaway: '', subject_title: 'the gascity topic',
      state: 'closed', headline: 'settled',
    },
  ],
};

const rigCombo = (): HTMLSelectElement =>
  screen.getByRole('combobox', { name: 'filter by rig' }) as HTMLSelectElement;
const sittingsRegion = (): HTMLElement => screen.getByRole('region', { name: 'converse sittings' });

it('offers a rig filter listing each rig, defaulting to all rigs', async () => {
  serveBoard(MULTI_RIG);
  render(<App />);
  await waitFor(() => expect(screen.getByText('the gascity family')).toBeTruthy());

  const combo = rigCombo();
  expect(combo.value).toBe('');
  const options = within(combo)
    .getAllByRole('option')
    .map((o) => o.textContent);
  expect(options).toEqual(['all rigs', 'gascity', 'gc-toolkit']);
});

it('narrows the rows and the header count to the selected rig', async () => {
  serveBoard(MULTI_RIG);
  render(<App />);
  await waitFor(() => expect(screen.getByText('the gascity family')).toBeTruthy());
  expect(screen.getByText(/2 anchors · generated/)).toBeTruthy();

  fireEvent.change(rigCombo(), { target: { value: 'gascity' } });

  expect(rowFor('the gascity family')).not.toBeNull();
  expect(rowFor('the gc-toolkit family')).toBeNull();
  expect(screen.getByText(/1 anchors · generated/)).toBeTruthy();
});

it('narrows the sittings record to the selected rig', async () => {
  serveBoard(MULTI_RIG);
  render(<App />);
  await waitFor(() => expect(screen.getByText('the gascity family')).toBeTruthy());
  expect(within(sittingsRegion()).getByText('tk-vs-gct')).toBeTruthy();

  fireEvent.change(rigCombo(), { target: { value: 'gascity' } });

  expect(within(sittingsRegion()).getByText('tk-vs-gcy')).toBeTruthy();
  expect(within(sittingsRegion()).queryByText('tk-vs-gct')).toBeNull();
});

// The cross-rig completeness signal is a fact about the whole city, so selecting
// one rig must not switch it off — a filtered view that hid it would read as an
// all-clear the gather never earned.
it('keeps the partial-gather warning when a rig is selected', async () => {
  serveBoard(MULTI_RIG);
  render(<App />);
  await waitFor(() => expect(screen.getByText('the gascity family')).toBeTruthy());
  expect(screen.getByText(/Partial board/)).toBeTruthy();

  fireEvent.change(rigCombo(), { target: { value: 'gascity' } });

  expect(screen.getByText(/Partial board/)).toBeTruthy();
});

it('omits the rig filter when the board holds a single rig', async () => {
  render(<App />);
  await waitFor(() => expect(screen.getByText('Attention Canvas')).toBeTruthy());
  expect(screen.queryByRole('combobox', { name: 'filter by rig' })).toBeNull();
});
