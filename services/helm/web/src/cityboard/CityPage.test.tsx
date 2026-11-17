import { act, cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import golden from '../../../internal/cityboard/testdata/city.json';
import { Page } from '../rigboard/Board';
import type { Check, Doctor, Response as CityResponse } from './document.gen';

// The page runs here on the document the city's read builds from a live
// city's newest doctor run (internal/cityboard/testdata/city.json), so a
// change to the read that the page does not follow fails here.

const live = golden as unknown as CityResponse;

let calls: string[];
/** The answers the city's read gives, in turn; the last one repeats. */
let cityReads: (() => Response)[];

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

/** The live document with its doctor changed as the test says. */
function withDoctor(change: Partial<Doctor>): CityResponse {
  return { ...live, city: { ...live.city, doctor: { ...live.city.doctor, ...change } } };
}

beforeEach(() => {
  calls = [];
  cityReads = [() => json(live)];
  vi.stubGlobal('fetch', async (input: RequestInfo | URL) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
    calls.push(url);
    if (url === 'helm/city') {
      const next = cityReads.length > 1 ? cityReads.shift() : cityReads[0];
      return next!();
    }
    if (url === 'helm/rigs') return json({ read_at: live.read_at, rigs: ['gc-toolkit'] });
    return json({ error: `no route for ${url}` }, 404);
  });
  window.history.replaceState({}, '', '/?city');
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

function text(el: Element | null): string {
  return el?.textContent ?? '';
}

async function loaded() {
  await screen.findByText(/^Read at /);
}

/** The title of each section heading, with its count, in page order. */
function sections(): string[] {
  return [...document.querySelectorAll('.line--section .title')].map((t) => text(t));
}

/** The checks drawn under the section whose title begins with label, in page
 *  order: each item row after that heading, up to the next. */
function rowsUnder(label: string): HTMLElement[] {
  const out: HTMLElement[] = [];
  let inside = false;
  for (const line of document.querySelectorAll<HTMLElement>('.line')) {
    if (line.classList.contains('line--section')) {
      inside = text(line.querySelector('.title')).startsWith(label);
      continue;
    }
    if (inside) out.push(line);
  }
  return out;
}

function titleOf(row: HTMLElement): string {
  return text(row.querySelector('.title'));
}

function leadOf(): string {
  return text(document.querySelector('.lead'));
}

describe('the city page', () => {
  it('reads the city’s document alone at ?city, and leads with how many checks fail', async () => {
    render(<Page />);
    await loaded();
    expect(calls).toEqual(['helm/city']);
    expect(document.title).toBe('helm · city');
    expect(leadOf()).toBe('15checks are failing.');
    expect(sections()).toEqual(['Failing15', 'Accepted1', 'Monitor orders7']);
  });

  it('lists the failing checks in the document’s order, each with since when and how many runs', async () => {
    render(<Page />);
    await loaded();
    const rows = rowsUnder('Failing');
    expect(rows.map(titleOf)).toEqual(live.city.doctor.failing.map((c) => c.name));
    const first = rows[0];
    expect(text(first.querySelector('.tag'))).toBe('error');
    const since = new Date(live.city.doctor.failing[0].first_failed ?? '').toLocaleString();
    expect(text(first.querySelector('.signal'))).toBe(`failing since ${since}2 runs in a row`);
    expect(text(first.querySelector('.line-2'))).toBe(live.city.doctor.failing[0].message);
    expect(text(first.querySelector('.line-3'))).toBe('blocking');
  });

  it('says when doctor last ran, and marks a run over two hours old late', async () => {
    render(<Page />);
    await loaded();
    const started = new Date(live.city.doctor.started ?? '').toLocaleString();
    const note = screen.getByText(new RegExp(`^Doctor last ran at ${started.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`));
    expect(text(note)).toContain('Late: doctor runs every hour, and this run started over two hours ago.');
  });

  it('marks no run late inside two hours', async () => {
    cityReads = [() => json(withDoctor({ late: false }))];
    render(<Page />);
    await loaded();
    expect(screen.queryByText(/Late:/)).toBeNull();
  });

  it('folds the accepted checks under their count, each with why and the ruling once opened', async () => {
    render(<Page />);
    await loaded();
    expect(rowsUnder('Accepted')).toHaveLength(0);
    fireEvent.click(screen.getByRole('button', { name: /^Accepted/ }));
    const rows = rowsUnder('Accepted');
    expect(rows.map(titleOf)).toEqual(['hold-label-routed-to']);
    expect(text(rows[0].querySelector('.line-3'))).toContain(`Accepted: ${live.city.doctor.accepted[0].accepted?.reason}`);
    expect(text(rows[0].querySelector('.line-3'))).toContain(`Ruling: ${live.city.doctor.accepted[0].accepted?.ruling}`);
  });

  it('lists each monitor order with its last good run, and one with none known', async () => {
    render(<Page />);
    await loaded();
    const rows = rowsUnder('Monitor orders');
    expect(rows.map(titleOf)).toEqual(live.city.doctor.monitors.map((m) => m.order));
    expect(text(rows[0].querySelector('.signal'))).toBe('no good run known');
    const good = new Date(live.city.doctor.monitors[1].last_good ?? '').toLocaleString();
    expect(text(rows[1].querySelector('.signal'))).toBe(`last good run ${good}`);
  });

  it('says when the run could not read the monitor orders’ runs', async () => {
    cityReads = [() => json(withDoctor({ monitors_unread: 'gc events did not read' }))];
    render(<Page />);
    await loaded();
    expect(screen.getByText(/could not read the monitor orders’ runs|could not read the monitor orders' runs/).textContent).toContain(
      'gc events did not read',
    );
  });
});

describe('a check the run did not measure', () => {
  const shown: Check = { name: 'worktree-disk-size', first_failed: '2026-11-16T20:00:00Z', streak: 3, unmeasured: 'timed_out' };
  const accepted: Check = {
    name: 'rig:rig-a:beads',
    first_failed: '2026-11-16T20:00:00Z',
    streak: 4,
    unmeasured: 'not checked: store not running (rig:rig-a)',
    accepted: { reason: 'a Gas City bug', ruling: 'the design’s approval' },
  };
  const fine: Check = { name: 'controller', unmeasured: 'timed_out' };

  it('stays failing and counted when it showed failing, and says why the run did not measure it', async () => {
    cityReads = [() => json(withDoctor({ count: 1, failing: [shown], not_measured: [accepted, fine] }))];
    render(<Page />);
    await loaded();
    expect(leadOf()).toBe('1check is failing.');
    const [row] = rowsUnder('Failing');
    expect(titleOf(row)).toBe('worktree-disk-size');
    expect(text(row.querySelector('.tag'))).toBe('not measured');
    expect(text(row.querySelector('.signal'))).toContain('3 runs in a row');
    expect(text(row.querySelector('.line-2'))).toBe('Not measured: doctor abandoned the check at its per-check timeout.');
  });

  it('is listed as not measured otherwise, with the failure it carries and its acceptance', async () => {
    cityReads = [() => json(withDoctor({ count: 1, failing: [shown], not_measured: [accepted, fine] }))];
    render(<Page />);
    await loaded();
    const rows = rowsUnder('Not measured');
    expect(rows.map(titleOf)).toEqual(['rig:rig-a:beads', 'controller']);
    expect(text(rows[0].querySelector('.line-2'))).toBe('Not measured: not checked: store not running (rig:rig-a)');
    expect(text(rows[0].querySelector('.line-3'))).toContain('Accepted: a Gas City bug');
    expect(text(rows[1].querySelector('.signal'))).toBe('');
  });
});

describe('a lead that reaches zero, or has nothing to count', () => {
  it('leads with zero when no check is failing', async () => {
    cityReads = [() => json(withDoctor({ count: 0, failing: [] }))];
    render(<Page />);
    await loaded();
    expect(leadOf()).toBe('0No check is failing.');
    expect(sections()).toEqual(['Accepted1', 'Monitor orders7']);
  });

  it('shows no count when the log holds no doctor run', async () => {
    cityReads = [
      () =>
        json({
          read_at: live.read_at,
          city: { doctor: { ran: false, late: false, completed: false, count: 0, failing: [], not_measured: [], accepted: [], monitors: [] } },
        }),
    ];
    render(<Page />);
    await loaded();
    expect(document.querySelector('.lead')).toBeNull();
    expect(screen.getByText(/Doctor has recorded no run/)).toBeTruthy();
    expect(document.querySelectorAll('.line')).toHaveLength(0);
  });

  it('says a run did not complete, and what the lists are, or that no run has measured them', async () => {
    const measured = '2026-11-16T21:00:00Z';
    cityReads = [() => json(withDoctor({ completed: false, why: 'gc doctor did not finish within 20m0s', measured }))];
    render(<Page />);
    await loaded();
    expect(screen.getByText(/^Doctor last ran at /).textContent).toContain(
      `That run did not complete: gc doctor did not finish within 20m0s. The checks below are what the run at ${new Date(measured).toLocaleString()} measured.`,
    );
    cleanup();
    cityReads = [() => json(withDoctor({ completed: false, why: 'gc doctor exited 2', measured: undefined, count: 0, failing: [], accepted: [] }))];
    render(<Page />);
    await loaded();
    expect(document.querySelector('.lead')).toBeNull();
    expect(screen.getByText(/No doctor run has measured the checks yet/)).toBeTruthy();
  });
});

describe('a read that fails', () => {
  it('draws no page when no read has given a document', async () => {
    cityReads = [() => json({ error: 'the city page could not be read: the supervisor did not answer' }, 502)];
    render(<Page />);
    const alert = await screen.findByRole('alert');
    expect(text(alert)).toContain('the supervisor did not answer');
    expect(document.querySelector('.lead')).toBeNull();
    expect(document.querySelectorAll('.line')).toHaveLength(0);
  });

  it('keeps the last good document on screen with the failure beside it', async () => {
    cityReads = [() => json(live), () => json({ error: 'the city page could not be read: the supervisor did not answer' }, 502)];
    render(<Page />);
    await loaded();
    await act(async () => {
      document.dispatchEvent(new Event('visibilitychange'));
      await new Promise((resolve) => setTimeout(resolve, 0));
    });
    const alert = await screen.findByRole('alert');
    expect(text(alert)).toContain('the supervisor did not answer');
    expect(leadOf()).toBe('15checks are failing.');
  });
});

describe('the city page beside the rig pages', () => {
  it('is a link from the rig list', async () => {
    window.history.replaceState({}, '', '/');
    render(<Page />);
    await screen.findByRole('link', { name: 'gc-toolkit' });
    expect(screen.getByRole('link', { name: 'City' }).getAttribute('href')).toBe('?city');
  });

  it('links back to the rig list', async () => {
    render(<Page />);
    await loaded();
    expect(screen.getByRole('link', { name: 'Rigs' }).getAttribute('href')).toBe('./');
  });
});
