import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ClosedPanel } from './ClosedPanel';

// What this file guards is the operator's READING of the panel: that a quiet
// window and a failed read never look the same, that the window picker actually
// changes the question asked, that a repeated subject renders as the several
// decisions it is, and that this surface stays pull-only.
//
// Matchers are plain vitest and interaction is fireEvent, matching the rest of
// this package — it carries neither jest-dom nor user-event.

let calls: string[] = [];
let reply: () => Response | Promise<Response>;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function view(rows: unknown[], extra: Record<string, unknown> = {}) {
  return {
    generated_at: '2026-08-24T06:00:00Z',
    since: '24h',
    cutoff: '2026-08-23T06:00:00Z',
    total: rows.length,
    rows,
    ...extra,
  };
}

function row(over: Record<string, unknown> = {}) {
  return {
    rig: 'gc-toolkit',
    visit: 'tk-v1',
    closed_at: '2026-08-24T04:32:19Z',
    outcome: 'routed',
    subject: 'tk-s',
    subject_title: 'a subject',
    takeaway: 'routed — the work is out',
    ...over,
  };
}

/** Open the panel, which is collapsed on mount. */
function openPanel() {
  fireEvent.click(screen.getByText(/what was decided/));
}

beforeEach(() => {
  calls = [];
  reply = () => json(view([row()]));
  vi.stubGlobal('fetch', (input: RequestInfo | URL) => {
    calls.push(String(input));
    return Promise.resolve(reply());
  });
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe('ClosedPanel', () => {
  it('asks for nothing until the operator opens it', async () => {
    render(<ClosedPanel />);
    // PULL, NOT PUSH is a ruling, not a default: the operator refused a
    // cadence, so a panel that read the window on mount — or on a timer —
    // would be the digest they declined.
    await new Promise((r) => setTimeout(r, 20));
    expect(calls).toEqual([]);
  });

  it('reads the default 24h window when opened', async () => {
    render(<ClosedPanel />);
    openPanel();
    await waitFor(() => expect(calls.length).toBe(1));
    expect(calls[0]).toBe('helm/closed?since=24h');
    // Document-relative: the app is served under a runtime-city-named prefix,
    // so a leading slash would address the supervisor root.
    expect(calls[0].startsWith('/')).toBe(false);
  });

  it('renders a row per visit, with the subject id AND its title', async () => {
    reply = () =>
      json(
        view([
          row({ visit: 'tk-v1', takeaway: 'first sitting' }),
          row({ visit: 'tk-v2', takeaway: 'second sitting' }),
        ]),
      );
    render(<ClosedPanel />);
    openPanel();
    await waitFor(() => expect(screen.getByText('first sitting')).toBeTruthy());

    // The same subject twice is two decisions, not a duplicate to collapse:
    // the earlier sitting is exactly the one no other surface still shows.
    expect(screen.getByText('second sitting')).toBeTruthy();
    expect(screen.getAllByText('tk-s').length).toBe(2);
    // An id alone is not readable and a title alone is not resolvable.
    expect(screen.getAllByText('a subject').length).toBe(2);
  });

  it('changing the window changes the question, and drops the old answer first', async () => {
    render(<ClosedPanel />);
    openPanel();
    await waitFor(() => expect(calls.length).toBe(1));

    reply = () => json(view([row({ visit: 'tk-v9', takeaway: 'a week ago' })], { since: '7d' }));
    fireEvent.click(screen.getByText('7d'));
    await waitFor(() => expect(screen.getByText('a week ago')).toBeTruthy());

    expect(calls[1]).toBe('helm/closed?since=7d');
    // Leaving the previous rows up under a changed picker would label 7 days
    // of decisions as 24h — the same wrong-window failure the parser refuses.
    expect(screen.queryByText('routed — the work is out')).toBeNull();
  });

  it('says a quiet window is quiet, in words', async () => {
    reply = () => json(view([]));
    render(<ClosedPanel />);
    openPanel();
    await waitFor(() => expect(screen.getByText(/No visit reached a disposition/)).toBeTruthy());
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('a failed read is an ERROR, never an empty window', async () => {
    // The distinction the whole surface exists to protect: "nothing was
    // decided" and "we could not look" are opposite answers.
    reply = () => json({ error: 'closed dispositions unavailable: dolt wedged' }, 502);
    render(<ClosedPanel />);
    openPanel();

    const alert = await screen.findByRole('alert');
    expect(alert.textContent).toContain('dolt wedged');
    expect(screen.queryByText(/No visit reached a disposition/)).toBeNull();
  });

  it('surfaces the 501 reason rather than pretending the route is missing', async () => {
    reply = () => json({ error: 'closed dispositions are unavailable under this source backend' }, 501);
    render(<ClosedPanel />);
    openPanel();
    const alert = await screen.findByRole('alert');
    expect(alert.textContent).toContain('source backend');
  });

  it('renders an incomplete row rather than dropping it', async () => {
    // A closed visit is terminal whether or not sign-off stamped it, and
    // dropping the row would hide the disposition whose record is incomplete.
    reply = () => json(view([row({ subject: '', subject_title: '', outcome: '', takeaway: '' })]));
    render(<ClosedPanel />);
    openPanel();
    await waitFor(() => expect(screen.getByText('(unlinked)')).toBeTruthy());
    expect(screen.getAllByText('—').length).toBeGreaterThan(0);
  });

  it('says what it is not showing when the list is capped', async () => {
    reply = () => json(view([row()], { total: 40 }));
    render(<ClosedPanel />);
    openPanel();
    await waitFor(() => expect(screen.getByText(/Showing the newest 1 of 40/)).toBeTruthy());
  });

  it('tolerates a null rows array without claiming a failure', async () => {
    reply = () => json({ ...view([]), rows: null });
    render(<ClosedPanel />);
    openPanel();
    await waitFor(() => expect(screen.getByText(/No visit reached a disposition/)).toBeTruthy());
    expect(screen.queryByRole('alert')).toBeNull();
  });
});
