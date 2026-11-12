import { act, cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { StrictMode } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import golden from '../../../internal/rigboard/testdata/gc-toolkit.board.json';
import { Page } from './Board';
import type { Document } from './document.gen';

// The page runs here on the document the rig read builds from the committed
// gc-toolkit fixture (internal/rigboard/testdata/gc-toolkit.board.json), so a
// change to the read that the page does not follow fails here. Matchers are
// plain vitest and interaction is fireEvent: the package carries neither
// jest-dom nor user-event.

const board = golden as unknown as Document;
const READ_AT = '2026-11-11T16:40:00Z';

interface Call {
  url: string;
  method: string;
  body?: string;
  headers: Record<string, string>;
}

let calls: Call[];
/** The answers the rig read gives, in turn; the last one repeats. */
let rigReads: (() => Response)[];
let engageReply: () => Response;
let openReply: () => Response;
let beadReply: (id: string) => Response;
/** Each scrollIntoView call, in turn. jsdom lays nothing out and has no
 *  scrollIntoView of its own, so the page's calls land here. */
let scrolls: { el: Element; arg: unknown }[];

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

function headersOf(init?: RequestInit, req?: Request): Record<string, string> {
  const out: Record<string, string> = {};
  new Headers(init?.headers ?? req?.headers).forEach((v, k) => {
    out[k] = v;
  });
  return out;
}

beforeEach(() => {
  calls = [];
  scrolls = [];
  Object.defineProperty(Element.prototype, 'scrollIntoView', {
    configurable: true,
    writable: true,
    value(this: Element, arg?: unknown) {
      scrolls.push({ el: this, arg });
    },
  });
  rigReads = [() => json({ read_at: READ_AT, board })];
  engageReply = () =>
    json({
      bead: 'tk-q4dd6mk',
      verb: 'engage',
      message: '✓ discuss on new conversation tk-c0nv1 for tk-q4dd6mk\n  attach: gc session attach tk-s1tt1ng',
    });
  openReply = () =>
    json({
      bead: 'tk-q4dd6mk',
      outcome: 'filed',
      conversation: 'tk-c0nv2',
      message: "conversation tk-c0nv2 filed on tk-q4dd6mk — waiting in the operator's queue; no session spawned.",
    });
  beadReply = (id) => json({ id, title: board.rows[id]?.title ?? id, description: '## The ask\n\nRule on it **now**.' });
  vi.stubGlobal('fetch', async (input: RequestInfo | URL, init?: RequestInit) => {
    const req = input instanceof Request ? input : undefined;
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
    const method = (init?.method ?? req?.method ?? 'GET').toUpperCase();
    calls.push({ url, method, body: typeof init?.body === 'string' ? init.body : undefined, headers: headersOf(init, req) });
    if (url === 'helm/rigs') return json({ read_at: READ_AT, rigs: ['gc-toolkit', 'example-rig'] });
    if (url === 'helm/rigs/gc-toolkit') {
      const next = rigReads.length > 1 ? rigReads.shift() : rigReads[0];
      return next!();
    }
    if (url === 'helm/engage') return engageReply();
    if (url === 'helm/open') return openReply();
    const bead = /\/v0\/city\/test-city\/bead\/([^/?]+)$/.exec(url);
    if (bead !== null) return beadReply(decodeURIComponent(bead[1]));
    return json({ error: `no route for ${url}` }, 404);
  });
  window.history.replaceState({}, '', '/?rig=gc-toolkit');
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  Reflect.deleteProperty(Element.prototype, 'scrollIntoView');
});

function text(el: Element | null): string {
  return el?.textContent ?? '';
}

/** Every row drawn for a bead: each line whose own id reads id. */
function rowsOf(id: string): HTMLElement[] {
  return [...document.querySelectorAll('.line .bead-slot .bead-id')]
    .filter((b) => text(b) === id)
    .map((b) => b.closest('.line'))
    .filter((l): l is HTMLElement => l instanceof HTMLElement);
}

/** The row drawn for a bead, the first where the page draws it twice. */
function rowOf(id: string): HTMLElement {
  const line = rowsOf(id)[0];
  if (line === undefined) throw new Error(`no row for ${id}`);
  return line;
}

/** The rows drawn, by their own ids, in page order. */
function rowIds(): string[] {
  return [...document.querySelectorAll('.line .bead-slot .bead-id')].map((b) => text(b));
}

function headings(): string[] {
  return [...document.querySelectorAll('.line--section .title, .line--heading .title')].map((t) => text(t));
}

async function loaded() {
  await screen.findByText(/^Read at /);
}

function tab(name: RegExp) {
  fireEvent.click(screen.getByRole('button', { name }));
}

describe('the address', () => {
  it('lists the city’s rigs as links when it names no rig', async () => {
    window.history.replaceState({}, '', '/');
    render(<Page />);
    const link = await screen.findByRole('link', { name: 'gc-toolkit' });
    expect(link.getAttribute('href')).toBe('?rig=gc-toolkit');
    expect(screen.getByRole('link', { name: 'example-rig' }).getAttribute('href')).toBe('?rig=example-rig');
    expect(calls.map((c) => c.url)).toEqual(['helm/rigs']);
  });

  // StrictMode mounts the list, leaves it and mounts it again, as a dev build
  // does, and the read the first mount dropped is no failure of the service.
  it('says nothing of a rig list read it dropped on leaving', async () => {
    window.history.replaceState({}, '', '/');
    vi.stubGlobal(
      'fetch',
      (_input: RequestInfo | URL, init?: RequestInit) =>
        new Promise<Response>((_resolve, reject) => {
          init?.signal?.addEventListener('abort', () => reject(new DOMException('The read was dropped.', 'AbortError')));
        }),
    );
    render(
      <StrictMode>
        <Page />
      </StrictMode>,
    );
    await screen.findByText("Reading the city's rigs…");
    await act(async () => {
      await new Promise((resolve) => setTimeout(resolve, 0));
    });
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('reads the rig the address names, and only that rig', async () => {
    render(<Page />);
    await loaded();
    expect(calls.map((c) => c.url)).toEqual(['helm/rigs/gc-toolkit']);
    expect(document.title).toBe('helm · gc-toolkit');
  });
});

describe('a read that fails', () => {
  it('draws no list when no read has given a document', async () => {
    rigReads = [() => json({ error: 'the gc-toolkit board could not be read: the store did not answer' }, 502)];
    render(<Page />);
    const alert = await screen.findByRole('alert');
    expect(text(alert)).toContain('the store did not answer');
    expect(document.querySelectorAll('.line')).toHaveLength(0);
    tab(/Needs you/);
    expect(document.querySelector('.lead')).toBeNull();
  });

  it('keeps the last good document on screen with its read time and the failure beside it', async () => {
    rigReads = [
      () => json({ read_at: READ_AT, board }),
      () => json({ error: 'the gc-toolkit board could not be read: the store did not answer' }, 502),
    ];
    render(<Page />);
    await loaded();
    tab(/Needs you/);
    // A successful engage reads the document again, and that read fails.
    fireEvent.click(within(rowOf('tk-q4dd6mk')).getByRole('button', { name: 'Start the conversation' }));
    const alert = await screen.findByText(/The latest read failed at/);
    expect(text(alert)).toContain('the store did not answer');
    expect(text(alert)).toContain('This is the board read at');
    expect(rowIds()).toContain('tk-q4dd6mk');
    expect(text(document.querySelector('.lead-count'))).toBe(String(board.needs_you.count));
  });
});

/** The entry of one epic on the Epics page. */
function epicEntry(id: string) {
  return board.epics.find((e) => e.id === id)!;
}

/** The ids a Needs you view draws, each need followed by the beads it holds. */
function needIds(needs: { id: string; holds: string[] }[]): string[] {
  return needs.flatMap((n) => [n.id, ...n.holds]);
}

/** The rows drawn between an epic's row and the next epic's. */
function underEpic(id: string): string[] {
  const shown = rowIds();
  const at = shown.indexOf(id);
  const epics = new Set(board.epics.map((e) => e.id));
  const end = shown.findIndex((x, i) => i > at && epics.has(x));
  return shown.slice(at + 1, end < 0 ? undefined : end);
}

/** How a row reads as an object: its tag, and the background it is drawn on. */
function lookOf(id: string): { tag: string; background: string } {
  const line = rowOf(id);
  return { tag: text(line.querySelector('.tag')), background: line.style.background };
}

const SIMPLIFY = /Simplify gc-toolkit onto Gas City/;

describe('the Epics page', () => {
  it('lists every open epic in the document’s order, folded, each leading with what needs you', async () => {
    render(<Page />);
    await loaded();
    expect(rowIds()).toEqual(board.epics.map((e) => e.id));
    const titles = [...document.querySelectorAll('.line--epic .title')].map((t) => text(t));
    // An epic reads its handle where it records one, and its title otherwise.
    expect(titles).toEqual([
      board.rows['tk-1tfzr71'].title,
      'Epic Checkpoints & Features',
      board.rows['tk-ssm8qns'].title,
      'Board UI design',
    ]);
    const counts = (id: string) => [...rowOf(id).querySelectorAll('.bit--count')].map((b) => text(b));
    expect(counts('tk-1tfzr71')).toEqual(['2 need you', '21 in the queue', '2 not scheduled', '51 closed']);
    expect(counts('tk-wmwcdlc')).toEqual(['1 needs you', '2 in the queue', '0 not scheduled', '13 closed']);
    expect(text(rowOf('tk-wmwcdlc').querySelector('.line-2'))).toBe(board.rows['tk-wmwcdlc'].line2);
  });

  it('opens an epic onto its Needs you, each need with the beads it holds in queue order, and its Work queue', async () => {
    render(<Page />);
    await loaded();
    fireEvent.click(within(rowOf('tk-1tfzr71')).getByRole('button', { name: SIMPLIFY }));
    expect(headings()).toEqual(['Needs you2', 'Work queue23', 'Not scheduled2', 'Closed51']);
    const entry = epicEntry('tk-1tfzr71');
    // Not scheduled and Closed fold until opened.
    expect(underEpic('tk-1tfzr71')).toEqual([...needIds(entry.needs), ...entry.queue.queue]);
    expect(entry.needs.map((n) => n.id)).toEqual(['tk-q4dd6mk', 'tk-ucjq40f']);
    expect(entry.queue.queue[0]).toBe('tk-1tfzr71.66');
  });

  it('draws a Delivery with its own views, and the rest of the epic apart', async () => {
    render(<Page />);
    await loaded();
    fireEvent.click(within(rowOf('tk-wmwcdlc')).getByRole('button', { name: /Epic Checkpoints/ }));
    const delivery = rowOf('tk-wmwcdlc.3');
    expect(text(delivery.querySelector('.line-2'))).toMatch(/^Aim:/);
    // Its work has all closed, so it folds, and its ruling is a need of the epic.
    expect(screen.getByText('The rest of the epic')).toBeTruthy();
    const entry = epicEntry('tk-wmwcdlc');
    const shown = rowIds();
    for (const id of [...needIds(entry.needs), ...entry.queue.queue]) expect(shown).toContain(id);
    for (const id of entry.deliveries[0].closed) expect(shown).not.toContain(id);
    fireEvent.click(within(delivery).getByRole('button', { name: /Delivery: the Delivery layer/ }));
    expect(headings()).toContain('Closed7');
  });

  it('opens just one part when its count is clicked', async () => {
    render(<Page />);
    await loaded();
    fireEvent.click(within(rowOf('tk-1tfzr71')).getByRole('button', { name: '51 closed' }));
    const entry = epicEntry('tk-1tfzr71');
    expect(underEpic('tk-1tfzr71')).toEqual(entry.closed);
    fireEvent.click(within(rowOf('tk-1tfzr71')).getByRole('button', { name: '2 not scheduled' }));
    expect(underEpic('tk-1tfzr71')).toEqual([...entry.queue.queue, ...entry.queue.not_scheduled]);
  });
});

describe('the Needs you page', () => {
  it('leads with the document’s count and lists every need with the beads it holds beneath it', async () => {
    render(<Page />);
    await loaded();
    tab(/Needs you/);
    expect(text(document.querySelector('.pill'))).toBe(String(board.needs_you.count));
    expect(text(document.querySelector('.lead-count'))).toBe(String(board.needs_you.count));
    expect(text(document.querySelector('.lead-text'))).toBe('things in an epic are waiting on you.');
    expect(headings()).toEqual([]);
    expect(rowIds()).toEqual(needIds(board.needs_you.needs));
  });

  it('draws a need the same way on every page', async () => {
    render(<Page />);
    await loaded();
    tab(/Needs you/);
    const need = lookOf('tk-yhquh93.10');
    expect(need.tag).toBe('Pull request');
    expect(need.background).not.toBe(lookOf('tk-1tfzr71.39').background);
    tab(/Work queue/);
    expect(lookOf('tk-yhquh93.10')).toEqual(need);
    tab(/Epics/);
    fireEvent.click(within(rowOf('tk-yhquh93')).getByRole('button', { name: /Board UI design/ }));
    const lines = rowsOf('tk-yhquh93.10');
    expect(lines.length).toBeGreaterThan(1);
    for (const line of lines) {
      expect({ tag: text(line.querySelector('.tag')), background: line.style.background }).toEqual(need);
    }
  });

  it('starts the conversation on a question no conversation answers', async () => {
    render(<Page />);
    await loaded();
    tab(/Needs you/);
    fireEvent.click(within(rowOf('tk-q4dd6mk')).getByRole('button', { name: 'Start the conversation' }));
    const panel = await screen.findByRole('complementary', { name: 'Conversation' });
    await within(panel).findByText(/discuss on new conversation tk-c0nv1/);
    expect(text(within(panel).getByText('gc session attach tk-s1tt1ng'))).toBe('gc session attach tk-s1tt1ng');
    expect(within(panel).getByRole('button', { name: 'Copy' })).toBeTruthy();
    const engage = calls.find((c) => c.url === 'helm/engage')!;
    expect(engage.method).toBe('POST');
    expect(JSON.parse(engage.body!)).toEqual({ bead: 'tk-q4dd6mk' });
    expect(engage.headers['x-gc-request']).toBe('true');
  });

  it('rejoins the conversation that answers a question, and a conversation of its own', async () => {
    // The cut holds no question a conversation answers, so this document gives
    // one question the conversation the read would name.
    const answered: Document = structuredClone(board);
    answered.rows['tk-toahupq'].conversation = 'tk-c4nv0';
    answered.rows['tk-toahupq'].signal = 'Conversation waits for you';
    rigReads = [() => json({ read_at: READ_AT, board: answered })];
    render(<Page />);
    await loaded();
    tab(/Needs you/);
    fireEvent.click(within(rowOf('tk-toahupq')).getByRole('button', { name: 'Rejoin the conversation' }));
    await screen.findByRole('complementary', { name: 'Conversation' });
    fireEvent.click(within(rowOf('tk-2pvj50q')).getByRole('button', { name: 'Rejoin the conversation' }));
    await waitFor(() => expect(calls.filter((c) => c.url === 'helm/engage')).toHaveLength(2));
    const bodies = calls.filter((c) => c.url === 'helm/engage').map((c) => JSON.parse(c.body!).bead);
    expect(bodies).toEqual(['tk-c4nv0', 'tk-2pvj50q']);
  });

  it('shows why an engage failed, in the tool’s words', async () => {
    engageReply = () => json({ error: 'the gate holds two beads: name one with --from', reason: 'verb_failed' }, 422);
    render(<Page />);
    await loaded();
    tab(/Needs you/);
    fireEvent.click(within(rowOf('tk-q4dd6mk')).getByRole('button', { name: 'Start the conversation' }));
    const panel = await screen.findByRole('complementary', { name: 'Conversation' });
    const alert = await within(panel).findByRole('alert');
    expect(text(alert)).toContain('the gate holds two beads');
  });

  // Where the page places the panel below the board, opening it must bring it
  // into view. jsdom lays nothing out, so this holds the calls: one
  // scrollIntoView each time the panel opens or turns to another bead or kind,
  // none for the answer an engage writes into it afterwards, and focus inside
  // it each time.
  it('brings the side panel into view once each time it opens or turns, and moves focus into it', async () => {
    render(<Page />);
    await loaded();
    tab(/Needs you/);
    const start = () => within(rowOf('tk-q4dd6mk')).getByRole('button', { name: 'Start the conversation' });
    start().focus();
    fireEvent.click(start());
    const panel = await screen.findByRole('complementary', { name: 'Conversation' });
    await within(panel).findByText(/discuss on new conversation tk-c0nv1/);
    expect(scrolls).toHaveLength(1);
    expect(scrolls[0].el).toBe(panel);
    expect(scrolls[0].arg).toEqual({ block: 'nearest' });
    expect(document.activeElement).toBe(panel);

    fireEvent.click(within(rowOf('tk-toahupq')).getByRole('button', { name: 'Details' }));
    const discuss = screen.getByRole('button', { name: 'Discuss' });
    discuss.focus();
    fireEvent.click(discuss);
    const form = screen.getByRole('complementary', { name: 'Discuss' });
    expect(scrolls).toHaveLength(2);
    expect(scrolls[1].el).toBe(form);
    expect(document.activeElement).toBe(form);

    fireEvent.click(within(form).getByRole('button', { name: 'Close' }));
    expect(screen.queryByRole('complementary')).toBeNull();
    start().focus();
    fireEvent.click(start());
    const again = await screen.findByRole('complementary', { name: 'Conversation' });
    await waitFor(() => expect(calls.filter((c) => c.url === 'helm/engage')).toHaveLength(2));
    await within(again).findByText(/discuss on new conversation tk-c0nv1/);
    expect(scrolls).toHaveLength(3);
    expect(document.activeElement).toBe(again);
  });
});

describe('the Work queue', () => {
  it('lists the queue in its order, then the work nobody scheduled, folded', async () => {
    render(<Page />);
    await loaded();
    tab(/Work queue/);
    const q = board.work_queue;
    expect(rowIds()).toEqual(q.queue);
    expect(headings()).toEqual([`Not scheduled${q.not_scheduled.length}`]);
    fireEvent.click(screen.getByRole('button', { name: /^Not scheduled/ }));
    expect(rowIds()).toEqual([...q.queue, ...q.not_scheduled]);
  });

  it('names the bead a row waits on, and nests nothing beneath a row', async () => {
    render(<Page />);
    await loaded();
    tab(/Work queue/);
    expect(text(rowOf('tk-1tfzr71.67').querySelector('.signal'))).toContain('Waits on tk-1tfzr71.66');
    expect(document.querySelectorAll('.line--item .line-main[aria-expanded]')).toHaveLength(0);
  });
});

describe('the Unprioritized page', () => {
  it('groups the beads that carry hold:mayor by priority, in the document’s order', async () => {
    render(<Page />);
    await loaded();
    tab(/Unprioritized/);
    expect(headings()).toEqual(board.unprioritized.map((p) => `P${p.priority}${p.ids.length}`));
    expect(rowIds()).toEqual(board.unprioritized.flatMap((p) => p.ids));
  });
});

describe('search', () => {
  it('lists the rows whose id or title holds it, and goes back to the board', async () => {
    render(<Page />);
    await loaded();
    fireEvent.change(screen.getByRole('searchbox', { name: 'Search this rig' }), { target: { value: 'tk-ra77u1s' } });
    expect(rowIds()).toEqual(['tk-ra77u1s']);
    fireEvent.click(screen.getByRole('button', { name: 'Back to the board' }));
    expect(rowIds()).toEqual(board.epics.map((e) => e.id));
  });

  it('fills with an id a row refers to when its show link is clicked', async () => {
    render(<Page />);
    await loaded();
    tab(/Work queue/);
    const withRef = board.work_queue.queue.map((id) => board.rows[id]).find((r) => (r.line3 ?? []).length > 0)!;
    const ref = withRef.line3![0].id;
    fireEvent.click(within(rowOf(withRef.id)).getAllByRole('button', { name: 'show' })[0]);
    expect((screen.getByRole('searchbox', { name: 'Search this rig' }) as HTMLInputElement).value).toBe(ref);
    expect(rowIds()).toContain(ref);
  });

  it('copies a bead id on a click', async () => {
    const writeText = vi.fn().mockResolvedValue(undefined);
    vi.stubGlobal('navigator', { ...navigator, clipboard: { writeText } });
    render(<Page />);
    await loaded();
    fireEvent.click(screen.getByRole('button', { name: 'tk-wmwcdlc' }));
    expect(writeText).toHaveBeenCalledWith('tk-wmwcdlc');
    expect(screen.getByRole('button', { name: 'copied' })).toBeTruthy();
  });
});

describe('Details', () => {
  it('reads the bead’s whole description from the supervisor and formats it', async () => {
    render(<Page />);
    await loaded();
    tab(/Needs you/);
    fireEvent.click(within(rowOf('tk-q4dd6mk')).getByRole('button', { name: 'Details' }));
    expect(await screen.findByRole('heading', { name: 'The ask' })).toBeTruthy();
    expect(calls.map((c) => c.url)).toContain('http://localhost:3000/v0/city/test-city/bead/tk-q4dd6mk');
    const block = document.querySelector('.details-block')!;
    expect(text(block)).toContain('Status');
    expect(text(block)).toContain('Holds');
  });

  it('shows raw HTML in a description as text, and drops a script link', async () => {
    beadReply = (id) =>
      json({ id, title: id, description: 'Plain <b onclick="x()">bold</b> and [a link](javascript:alert(1)).' });
    render(<Page />);
    await loaded();
    fireEvent.click(within(rowOf('tk-wmwcdlc')).getByRole('button', { name: 'Details' }));
    const description = await waitFor(() => {
      const d = document.querySelector('.description');
      if (d === null) throw new Error('no description yet');
      return d;
    });
    expect(description.querySelector('b')).toBeNull();
    expect(text(description)).toContain('<b onclick="x()">bold</b>');
    expect(description.querySelector('a')?.getAttribute('href') ?? '').not.toContain('javascript');
  });

  it('shows an epic’s contract and its title', async () => {
    render(<Page />);
    await loaded();
    fireEvent.click(within(rowOf('tk-wmwcdlc')).getByRole('button', { name: 'Details' }));
    const block = document.querySelector('.details-block')!;
    expect(text(block)).toContain(board.rows['tk-wmwcdlc'].title);
    for (const k of ['Hypothesis', 'Boundaries', 'Closure condition', 'Leading indicators', 'Last ruling']) {
      expect(text(block)).toContain(k);
    }
  });

  it('says so when the description cannot be read', async () => {
    beadReply = () => json({ title: 'Not Found', status: 404, detail: 'bead not found' }, 404);
    render(<Page />);
    await loaded();
    fireEvent.click(within(rowOf('tk-wmwcdlc')).getByRole('button', { name: 'Details' }));
    const alert = await screen.findByRole('alert');
    expect(text(alert)).toContain('bead not found');
  });

  it('opens Discuss’s form in the side panel, and reads the board again once it files', async () => {
    render(<Page />);
    await loaded();
    tab(/Needs you/);
    fireEvent.click(within(rowOf('tk-q4dd6mk')).getByRole('button', { name: 'Details' }));
    fireEvent.click(screen.getByRole('button', { name: 'Discuss' }));
    const panel = screen.getByRole('complementary', { name: 'Discuss' });
    fireEvent.click(within(panel).getByRole('button', { name: /file a conversation/i }));
    await within(panel).findByText('A conversation waits in your queue.');
    const open = calls.find((c) => c.url === 'helm/open')!;
    expect(JSON.parse(open.body!)).toEqual({ bead: 'tk-q4dd6mk' });
    await waitFor(() => expect(calls.filter((c) => c.url === 'helm/rigs/gc-toolkit')).toHaveLength(2));
  });
});
