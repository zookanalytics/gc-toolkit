import { act, cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import golden from '../../../internal/cityboard/testdata/city.json';
import firstRun from '../../../internal/cityboard/testdata/first-run.json';
import { Page } from '../rigboard/Board';
import { when } from './CityPage';
import type { Check, Document, Doctor, Mail, Response as CityResponse } from './document.gen';

// The page runs here on the document the city's read builds from a live
// city's newest doctor run (internal/cityboard/testdata/city.json), so a
// change to the read that the page does not follow fails here.

const live: CityResponse = { read_at: '2026-11-17T00:42:00Z', city: golden as unknown as Document };

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

/** The live document with the mailbox's count the test gives. */
function withMail(mail: Mail): CityResponse {
  return { ...live, city: { ...live.city, mail } };
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
    expect(leadOf()).toBe('15checks have failed two runs in a row, not counting 1 accepted.');
    expect(sections()).toEqual(['Failing15', 'Accepted1', 'Monitor orders7']);
  });

  it('lists the failing checks in the document’s order, each with since when and how many runs', async () => {
    render(<Page />);
    await loaded();
    const rows = rowsUnder('Failing');
    expect(rows.map(titleOf)).toEqual(live.city.doctor.failing.map((c) => c.name));
    const first = rows[0];
    expect(text(first.querySelector('.tag'))).toBe('error');
    const since = when(live.city.doctor.failing[0].first_failed ?? '');
    expect(text(first.querySelector('.signal'))).toBe(`failing since ${since}2 runs in a row`);
    expect(text(first.querySelector('.line-2'))).toBe(live.city.doctor.failing[0].message);
    expect(text(first.querySelector('.line-3'))).toBe('blocking');
  });

  it('says when doctor last ran, and marks a run over two hours old late', async () => {
    render(<Page />);
    await loaded();
    const started = when(live.city.doctor.started ?? '');
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
    const good = when(live.city.doctor.monitors[1].last_good ?? '');
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
    expect(leadOf()).toBe('1check has failed two runs in a row, not counting 1 accepted and 2 not measured.');
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
  it('leads with zero when no check has failed two runs in a row', async () => {
    cityReads = [() => json(withDoctor({ count: 0, failing: [] }))];
    render(<Page />);
    await loaded();
    expect(leadOf()).toBe('0No check has failed two runs in a row, not counting 1 accepted.');
    expect(sections()).toEqual(['Accepted1', 'Monitor orders7']);
  });

  it('says what its zero counts when the run’s only failure is its first', async () => {
    // internal/cityboard/testdata/first-run.json: the document the city's read
    // builds from a run whose one failing check failed for the first time.
    cityReads = [() => json({ read_at: live.read_at, city: firstRun as unknown as Document })];
    render(<Page />);
    await loaded();
    expect(leadOf()).toBe('0No check has failed two runs in a row.');
    expect(sections()).toEqual(['Monitor orders0']);
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
      `That run did not complete: gc doctor did not finish within 20m0s. The checks below are what the run at ${when(measured)} measured.`,
    );
    cleanup();
    cityReads = [() => json(withDoctor({ completed: false, why: 'gc doctor exited 2', measured: undefined, count: 0, failing: [], accepted: [] }))];
    render(<Page />);
    await loaded();
    expect(document.querySelector('.lead')).toBeNull();
    expect(screen.getByText(/No doctor run has measured the checks yet/)).toBeTruthy();
  });
});

describe('the mailbox count', () => {
  /** The text of each lead, in page order. */
  function leads(): string[] {
    return [...document.querySelectorAll('.lead')].map((l) => text(l));
  }

  it('shows how many messages wait beside the failing checks, with how to open the postmaster', async () => {
    cityReads = [() => json(withMail({ counted: true, waiting: 130 }))];
    render(<Page />);
    await loaded();
    expect(leads()).toEqual([
      '15checks have failed two runs in a row, not counting 1 accepted.',
      '130messages wait in your mailbox, read or not. Open the postmaster to work through them: gc-helm postmaster.',
    ]);
  });

  it('says it of one message, and names no postmaster when none waits', async () => {
    cityReads = [() => json(withMail({ counted: true, waiting: 1 }))];
    render(<Page />);
    await loaded();
    expect(leads()[1]).toBe('1message waits in your mailbox, read or not. Open the postmaster to work through it: gc-helm postmaster.');
    cleanup();
    cityReads = [() => json(withMail({ counted: true, waiting: 0 }))];
    render(<Page />);
    await loaded();
    expect(leads()[1]).toBe('0messages wait in your mailbox, read or not.');
  });

  it('says what a count may miss when a store did not answer', async () => {
    cityReads = [() => json(withMail({ counted: true, waiting: 4, short: 'mail provider docs: store_slow: read timed out' }))];
    render(<Page />);
    await loaded();
    expect(leads()[1]).toBe(
      '4messages wait in your mailbox, read or not. Open the postmaster to work through them: gc-helm postmaster. The count may miss some: mail provider docs: store_slow: read timed out.',
    );
  });

  it('shows why in place of a number when the count did not read, and nothing for a document with no count', async () => {
    cityReads = [() => json(withMail({ counted: false, waiting: 0, why: "the supervisor's mail count answered HTTP 503" }))];
    render(<Page />);
    await loaded();
    expect(screen.getByText("Your mailbox could not be counted: the supervisor's mail count answered HTTP 503.")).toBeTruthy();
    expect(leads()).toHaveLength(1);
    cleanup();
    cityReads = [() => json(live)];
    render(<Page />);
    await loaded();
    expect(leads()).toHaveLength(1);
    expect(screen.queryByText(/mailbox/)).toBeNull();
  });

  it('shows the count when doctor has recorded no run', async () => {
    cityReads = [
      () =>
        json({
          read_at: live.read_at,
          city: {
            doctor: { ran: false, late: false, completed: false, count: 0, failing: [], not_measured: [], accepted: [], monitors: [] },
            mail: { counted: true, waiting: 2 },
          },
        }),
    ];
    render(<Page />);
    await loaded();
    expect(screen.getByText(/Doctor has recorded no run/)).toBeTruthy();
    expect(leads()).toEqual(['2messages wait in your mailbox, read or not. Open the postmaster to work through them: gc-helm postmaster.']);
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
    expect(leadOf()).toBe('15checks have failed two runs in a row, not counting 1 accepted.');
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
