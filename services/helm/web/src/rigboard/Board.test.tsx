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
      bead: 'tk-78qg2my',
      verb: 'engage',
      message: '✓ discuss on new conversation tk-c0nv1 for tk-78qg2my\n  attach: gc session attach tk-s1tt1ng',
    });
  openReply = () =>
    json({
      bead: 'tk-78qg2my',
      outcome: 'filed',
      conversation: 'tk-c0nv2',
      message: "conversation tk-c0nv2 filed on tk-78qg2my — waiting in the operator's queue; no session spawned.",
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

/** What a control reads: its text, less a reading it holds unseen. */
function reading(el: Element | null): string {
  if (el === null) return '';
  return [...el.childNodes]
    .filter((n) => !(n instanceof Element && n.getAttribute('aria-hidden') === 'true'))
    .map((n) => n.textContent ?? '')
    .join('');
}

/** The row whose bead id reads id, the first where the page draws it twice. */
function rowOf(id: string): HTMLElement {
  const button = screen.getAllByRole('button', { name: id })[0];
  const line = button.closest('.line');
  if (!(line instanceof HTMLElement)) throw new Error(`no row for ${id}`);
  return line;
}

function rowIds(): string[] {
  return [...document.querySelectorAll('.line .bead-id')].map((b) => reading(b));
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
    fireEvent.click(within(rowOf('tk-78qg2my')).getByRole('button', { name: 'Start the conversation' }));
    const alert = await screen.findByText(/The latest read failed at/);
    expect(text(alert)).toContain('the store did not answer');
    expect(text(alert)).toContain('This is the board read at');
    expect(rowIds()).toContain('tk-78qg2my');
    expect(text(document.querySelector('.lead-count'))).toBe('6');
  });
});

describe('the Epics page', () => {
  it('lists every open epic in the document’s order, folded, with its counts', async () => {
    render(<Page />);
    await loaded();
    expect(rowIds()).toEqual(board.epics.map((e) => e.id));
    const titles = [...document.querySelectorAll('.line--epic .title')].map((t) => text(t));
    // An epic reads its handle where it records one, and its title otherwise.
    expect(titles).toEqual([
      'Epic Checkpoints & Features',
      board.rows['tk-ssm8qns'].title,
      'Board UI design',
    ]);
    const counts = [...rowOf('tk-wmwcdlc').querySelectorAll('.bit--count')].map((b) => text(b));
    expect(counts).toEqual(['3 on you', '0 queued', '1 not moving', '11 closed']);
    expect(text(rowOf('tk-wmwcdlc').querySelector('.line-2'))).toBe(board.rows['tk-wmwcdlc'].line2);
  });

  it('opens an epic onto its Deliveries and its groups, Not moving and Closed folded', async () => {
    render(<Page />);
    await loaded();
    fireEvent.click(within(rowOf('tk-ssm8qns')).getByRole('button', { name: /gctk/ }));
    expect(headings()).toEqual(['Waiting on you1', 'Queued3', 'Not moving7', 'Closed16']);
    const entry = board.epics.find((e) => e.id === 'tk-ssm8qns')!;
    const shown = rowIds();
    for (const l of entry.groups) {
      for (const id of l.ids) {
        if (l.group === 'Waiting on you' || l.group === 'Queued') expect(shown).toContain(id);
        else expect(shown).not.toContain(id);
      }
    }
  });

  it('draws a Delivery with its own work, and the rest of the epic apart', async () => {
    render(<Page />);
    await loaded();
    fireEvent.click(within(rowOf('tk-wmwcdlc')).getByRole('button', { name: /Epic Checkpoints/ }));
    const delivery = rowOf('tk-wmwcdlc.3');
    expect(text(delivery.querySelector('.tag'))).toBe('Delivery');
    expect(text(delivery.querySelector('.line-2'))).toMatch(/^Aim:/);
    expect(headings()).toContain('Waiting on you1');
    expect(screen.getByText('The rest of the epic')).toBeTruthy();
    expect(rowIds()).toContain('tk-wmwcdlc.3.5');
  });

  it('opens just one group when its count is clicked', async () => {
    render(<Page />);
    await loaded();
    fireEvent.click(within(rowOf('tk-ssm8qns')).getByRole('button', { name: '16 closed' }));
    const entry = board.epics.find((e) => e.id === 'tk-ssm8qns')!;
    const shown = rowIds();
    for (const l of entry.groups) {
      for (const id of l.ids) {
        if (l.group === 'Closed') expect(shown).toContain(id);
        else expect(shown).not.toContain(id);
      }
    }
  });
});

describe('the Needs you page', () => {
  it('leads with the document’s count and lists its sections', async () => {
    render(<Page />);
    await loaded();
    tab(/Needs you/);
    expect(text(document.querySelector('.pill'))).toBe('6');
    expect(text(document.querySelector('.lead-count'))).toBe(String(board.needs_you.count));
    expect(text(document.querySelector('.lead-text'))).toBe('things in an epic are waiting on you.');
    expect(headings()).toEqual([
      'In conversation2',
      'No conversation yet5',
      'P2 · Epic Checkpoints & Features3',
      `P2 · ${board.rows['tk-ssm8qns'].title}1`,
      'No epic1',
    ]);
    const askRows = [
      ...board.needs_you.in_conversation,
      ...board.needs_you.no_conversation_yet.flatMap((e) => e.asks),
      ...board.needs_you.no_epic,
    ];
    const shown = rowIds();
    for (const id of askRows) expect(shown).toContain(id);
    // An ask is drawn under its section as an ask, and may also be drawn as
    // work an earlier ask holds.
    const tagsOf = (id: string) =>
      screen.getAllByRole('button', { name: id }).map((b) => text(b.closest('.line')?.querySelector('.tag') ?? null));
    expect(tagsOf('tk-78qg2my')).toContain('Question');
    expect(tagsOf('tk-1tfzr71.66')).toContain('Pull request');
  });

  it('nests the work an ask holds beneath it', async () => {
    render(<Page />);
    await loaded();
    tab(/Needs you/);
    const shown = rowIds();
    for (const id of board.rows['tk-78qg2my'].holds) expect(shown).toContain(id);
  });

  it('starts the conversation on a question no conversation answers', async () => {
    render(<Page />);
    await loaded();
    tab(/Needs you/);
    fireEvent.click(within(rowOf('tk-78qg2my')).getByRole('button', { name: 'Start the conversation' }));
    const panel = await screen.findByRole('complementary', { name: 'Conversation' });
    await within(panel).findByText(/discuss on new conversation tk-c0nv1/);
    expect(text(within(panel).getByText('gc session attach tk-s1tt1ng'))).toBe('gc session attach tk-s1tt1ng');
    expect(within(panel).getByRole('button', { name: 'Copy' })).toBeTruthy();
    const engage = calls.find((c) => c.url === 'helm/engage')!;
    expect(engage.method).toBe('POST');
    expect(JSON.parse(engage.body!)).toEqual({ bead: 'tk-78qg2my' });
    expect(engage.headers['x-gc-request']).toBe('true');
  });

  it('rejoins the conversation that answers a question, and a conversation of its own', async () => {
    render(<Page />);
    await loaded();
    tab(/Needs you/);
    fireEvent.click(within(rowOf('tk-v94mnsx')).getByRole('button', { name: 'Rejoin the conversation' }));
    await screen.findByRole('complementary', { name: 'Conversation' });
    fireEvent.click(within(rowOf('tk-tj17s9i')).getByRole('button', { name: 'Rejoin the conversation' }));
    await waitFor(() => expect(calls.filter((c) => c.url === 'helm/engage')).toHaveLength(2));
    const bodies = calls.filter((c) => c.url === 'helm/engage').map((c) => JSON.parse(c.body!).bead);
    expect(bodies).toEqual([board.rows['tk-v94mnsx'].conversation, 'tk-tj17s9i']);
  });

  it('shows why an engage failed, in the tool’s words', async () => {
    engageReply = () =>
      json(
        {
          error:
            'gc-helm: engage: nothing waits on gate tk-78qg2my (it was about tk-0ldb3ad, now closed), so there is no bead for a conversation to be about.',
          reason: 'verb_failed',
        },
        422,
      );
    render(<Page />);
    await loaded();
    tab(/Needs you/);
    fireEvent.click(within(rowOf('tk-78qg2my')).getByRole('button', { name: 'Start the conversation' }));
    const panel = await screen.findByRole('complementary', { name: 'Conversation' });
    const alert = await within(panel).findByRole('alert');
    expect(text(alert)).toContain('nothing waits on gate tk-78qg2my');
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
    const start = () => within(rowOf('tk-78qg2my')).getByRole('button', { name: 'Start the conversation' });
    start().focus();
    fireEvent.click(start());
    const panel = await screen.findByRole('complementary', { name: 'Conversation' });
    await within(panel).findByText(/discuss on new conversation tk-c0nv1/);
    expect(scrolls).toHaveLength(1);
    expect(scrolls[0].el).toBe(panel);
    expect(scrolls[0].arg).toEqual({ block: 'nearest' });
    expect(document.activeElement).toBe(panel);

    fireEvent.click(within(rowOf('tk-v94mnsx')).getByRole('button', { name: 'Details' }));
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
  it('lists the document’s sections in its order', async () => {
    render(<Page />);
    await loaded();
    tab(/Work queue/);
    const names = headings().map((h) => h.replace(/\d+$/, ''));
    const want: string[] = [];
    for (const s of board.work_queue) {
      want.push(s.name);
      for (const p of s.parts ?? []) want.push(p.name);
    }
    expect(names).toEqual(want);
  });

  it('draws a gate that holds work once, with the work it holds beneath it', async () => {
    render(<Page />);
    await loaded();
    tab(/Work queue/);
    const shown = rowIds();
    expect(shown.filter((id) => id === 'tk-u5t8h6x')).toHaveLength(1);
    const at = shown.indexOf('tk-u5t8h6x');
    expect(shown.slice(at + 1, at + 4)).toEqual(['tk-pchr4j2', 'tk-dje125x', 'tk-vt57970']);
    expect(text(rowOf('tk-u5t8h6x').querySelector('.tag'))).toBe('Gate');
  });
});

describe('the Unprioritized page', () => {
  it('groups the beads that carry hold:mayor by priority, in the document’s order', async () => {
    render(<Page />);
    await loaded();
    tab(/Unprioritized/);
    expect(headings()).toEqual(['P24', 'P31']);
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
    const withRef = Object.values(board.rows).find(
      (r) => (r.line3 ?? []).length > 0 && board.work_queue.some((s) => (s.parts ?? []).some((p) => p.rows.some((e) => e.id === r.id))),
    )!;
    const ref = withRef.line3![0].id;
    fireEvent.click(within(rowOf(withRef.id)).getAllByRole('button', { name: 'show' })[0]);
    expect((screen.getByRole('searchbox', { name: 'Search this rig' }) as HTMLInputElement).value).toBe(ref);
    expect(rowIds()).toContain(ref);
  });
});

// A bead id and the side panel's attach command copy through one hook
// (useCopy.test.ts holds its timers); these hold what each control reads when
// the browser takes the write, refuses it, or has no clipboard at all.
describe('copying', () => {
  /** A clipboard whose writes answer as answer says. */
  function clipboard(answer: () => Promise<void>) {
    const writeText = vi.fn((_text: string) => answer());
    vi.stubGlobal('navigator', { ...navigator, clipboard: { writeText } });
    return writeText;
  }

  function refused(): Promise<void> {
    return Promise.reject(new DOMException('Write permission denied.', 'NotAllowedError'));
  }

  /** Lets every answer already due reach the page. */
  async function settle() {
    await act(async () => {
      await new Promise((resolve) => setTimeout(resolve, 0));
    });
  }

  async function attachPanel(): Promise<HTMLElement> {
    tab(/Needs you/);
    fireEvent.click(within(rowOf('tk-78qg2my')).getByRole('button', { name: 'Start the conversation' }));
    const panel = await screen.findByRole('complementary', { name: 'Conversation' });
    await within(panel).findByText('gc session attach tk-s1tt1ng');
    return panel;
  }

  it('says a bead id was copied only once the clipboard has taken it', async () => {
    let take = () => {};
    const writeText = clipboard(
      () =>
        new Promise<void>((resolve) => {
          take = resolve;
        }),
    );
    render(<Page />);
    await loaded();
    fireEvent.click(screen.getByRole('button', { name: 'tk-wmwcdlc' }));
    expect(writeText).toHaveBeenCalledWith('tk-wmwcdlc');
    await settle();
    expect(screen.queryByRole('button', { name: 'copied' })).toBeNull();
    take();
    expect(await screen.findByRole('button', { name: 'copied' })).toBeTruthy();
  });

  it('says a bead id was copied only where it was clicked, though the page draws it in more than one place', async () => {
    const writeText = clipboard(() => Promise.resolve());
    render(<Page />);
    await loaded();
    tab(/Needs you/);
    // Needs you draws a bead once for each row that names it.
    const readings = screen.getAllByTitle('Copy the bead ID').map((b) => reading(b));
    const id = readings.find((r, i) => readings.indexOf(r) !== i);
    if (id === undefined) throw new Error('Needs you draws no bead id twice');
    const drawn = screen.getAllByRole('button', { name: id });
    const clicked = drawn[drawn.length - 1];
    fireEvent.click(clicked);
    expect(writeText).toHaveBeenCalledWith(id);
    expect(await screen.findAllByRole('button', { name: 'copied' })).toEqual([clicked]);
    expect(screen.getAllByRole('button', { name: id })).toEqual(drawn.filter((b) => b !== clicked));
    // The clicked id stays laid out under its word, unseen, so the control
    // keeps the id's size and nothing beside it moves.
    expect(text(clicked.querySelector('[aria-hidden="true"]'))).toBe(id);
  });

  it('says copied in one place on the board at a time: a later bead id takes the word from an earlier one', async () => {
    clipboard(() => Promise.resolve());
    render(<Page />);
    await loaded();
    tab(/Needs you/);
    // Two ids the page draws once each, so only the one slot is in question.
    const controls = screen.getAllByTitle('Copy the bead ID');
    const [first, second] = controls.filter((b) => controls.filter((c) => reading(c) === reading(b)).length === 1);
    fireEvent.click(first);
    expect(await screen.findAllByRole('button', { name: 'copied' })).toEqual([first]);
    fireEvent.click(second);
    expect(await screen.findAllByRole('button', { name: 'copied' })).toEqual([second]);
  });

  it('keeps a bead id on screen, and claims no copy, when the browser refuses the write', async () => {
    const writeText = clipboard(refused);
    render(<Page />);
    await loaded();
    fireEvent.click(screen.getByRole('button', { name: 'tk-wmwcdlc' }));
    await settle();
    expect(writeText).toHaveBeenCalledWith('tk-wmwcdlc');
    expect(screen.queryByRole('button', { name: 'copied' })).toBeNull();
    expect(screen.getByRole('button', { name: 'tk-wmwcdlc' })).toBeTruthy();
  });

  it('keeps a bead id on screen, and claims no copy, on a page with no clipboard', async () => {
    vi.stubGlobal('navigator', { ...navigator, clipboard: undefined });
    render(<Page />);
    await loaded();
    fireEvent.click(screen.getByRole('button', { name: 'tk-wmwcdlc' }));
    await settle();
    expect(screen.queryByRole('button', { name: 'copied' })).toBeNull();
    expect(screen.getByRole('button', { name: 'tk-wmwcdlc' })).toBeTruthy();
  });

  it('says the attach command was copied once the clipboard has taken it', async () => {
    const writeText = clipboard(() => Promise.resolve());
    render(<Page />);
    await loaded();
    const panel = await attachPanel();
    fireEvent.click(within(panel).getByRole('button', { name: 'Copy' }));
    expect(writeText).toHaveBeenCalledWith('gc session attach tk-s1tt1ng');
    const copied = await within(panel).findByRole('button', { name: 'Copied' });
    // Copy stays laid out under Copied, unseen, so the control keeps one size.
    expect(text(copied.querySelector('[aria-hidden="true"]'))).toBe('Copy');
  });

  it('leaves the attach command to select by hand, and claims no copy, when the browser refuses the write', async () => {
    const writeText = clipboard(refused);
    render(<Page />);
    await loaded();
    const panel = await attachPanel();
    fireEvent.click(within(panel).getByRole('button', { name: 'Copy' }));
    await settle();
    expect(writeText).toHaveBeenCalledWith('gc session attach tk-s1tt1ng');
    expect(within(panel).queryByRole('button', { name: 'Copied' })).toBeNull();
    expect(within(panel).getByRole('button', { name: 'Copy' })).toBeTruthy();
    expect(text(panel.querySelector('.command code'))).toBe('gc session attach tk-s1tt1ng');
  });
});

// The row and its Details draw a pull request in markup of their own, and
// read its state and what holds it in the same words.
describe('a pull request', () => {
  /** The row whose own bead id reads id, as search lists it. */
  function found(id: string): HTMLElement {
    fireEvent.change(screen.getByRole('searchbox', { name: 'Search this rig' }), { target: { value: id } });
    const line = [...document.querySelectorAll('.line')].find((l) => reading(l.querySelector('.bead-slot .bead-id')) === id);
    if (!(line instanceof HTMLElement)) throw new Error(`no row for ${id}`);
    return line;
  }

  /** What the row's pull request bit reads, and what Details' Pull request
   *  field reads once Details is open. */
  function readings(id: string): { row: string; details: string } {
    const line = found(id);
    const row = text(line.querySelector('.bit--mono'));
    fireEvent.click(within(line).getByRole('button', { name: 'Details' }));
    const block = line.nextElementSibling;
    if (block === null || !block.classList.contains('details-block')) throw new Error(`no Details for ${id}`);
    const field = [...block.querySelectorAll('.field')].find((f) => text(f.querySelector('.field-key')) === 'Pull request');
    return { row, details: text(field?.querySelector('.field-value') ?? null) };
  }

  it('reads its state and every reason it is held the same on its row and in Details', async () => {
    const doc = structuredClone(board);
    const held = doc.rows['tk-1tfzr71.66'];
    held.pull_request = { ...held.pull_request!, held: ['gate', 'review'] };
    rigReads = [() => json({ read_at: READ_AT, board: doc })];
    render(<Page />);
    await loaded();
    expect(readings('tk-1tfzr71.66')).toEqual({
      row: '#1459 · needs-attention · held: gate, review',
      details: '#1459 needs-attention · held: gate, review',
    });
  });

  it('reads a state with nothing held, and a number alone, the same way in both', async () => {
    render(<Page />);
    await loaded();
    expect(readings('tk-c9dcsbn')).toEqual({ row: '#1464 · working', details: '#1464 working' });
    expect(readings('tk-1hazlo2')).toEqual({ row: '#1256', details: '#1256' });
  });
});

describe('Details', () => {
  it('reads the bead’s whole description from the supervisor and formats it', async () => {
    render(<Page />);
    await loaded();
    tab(/Needs you/);
    fireEvent.click(within(rowOf('tk-78qg2my')).getByRole('button', { name: 'Details' }));
    expect(await screen.findByRole('heading', { name: 'The ask' })).toBeTruthy();
    expect(calls.map((c) => c.url)).toContain('http://localhost:3000/v0/city/test-city/bead/tk-78qg2my');
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
    fireEvent.click(within(rowOf('tk-78qg2my')).getByRole('button', { name: 'Details' }));
    fireEvent.click(screen.getByRole('button', { name: 'Discuss' }));
    const panel = screen.getByRole('complementary', { name: 'Discuss' });
    fireEvent.click(within(panel).getByRole('button', { name: /file a conversation/i }));
    await within(panel).findByText('A conversation waits in your queue.');
    const open = calls.find((c) => c.url === 'helm/open')!;
    expect(JSON.parse(open.body!)).toEqual({ bead: 'tk-78qg2my' });
    await waitFor(() => expect(calls.filter((c) => c.url === 'helm/rigs/gc-toolkit')).toHaveLength(2));
  });
});
