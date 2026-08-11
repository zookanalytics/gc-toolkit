import { act, cleanup, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { CitySignals } from './CitySignals';
import { DrillProvider } from './context';
import type { SupervisorOrigin } from './origin';

// Same tailscale-style fixture origin as the panel tests: everything this strip
// asks for must be reachable from a device that is not the city host.
const ORIGIN: SupervisorOrigin = {
  baseUrl: 'https://gc-host.tail1234.ts.net',
  city: 'loomington',
};

/** Envelope the /pending read answers with. */
let pendingBody: Record<string, unknown>;
/** Envelope the /mail/count read answers with. */
let mailBody: Record<string, unknown>;
/** Envelope the /beads?label=gc:wait read answers with. */
let waitingBody: Record<string, unknown>;
/** URLs the stubbed fetch was asked for, in order. */
let requested: string[] = [];

function jsonResponse(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

function routeFetch(input: Request | string | URL): Response {
  const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
  requested.push(url);
  const { pathname } = new URL(url);
  if (pathname === '/v0/city/loomington/pending') return jsonResponse(pendingBody);
  if (pathname === '/v0/city/loomington/mail/count') return jsonResponse(mailBody);
  if (pathname === '/v0/city/loomington/beads') return jsonResponse(waitingBody);
  return new Response(JSON.stringify({ title: 'not found' }), {
    status: 404,
    headers: { 'Content-Type': 'application/json' },
  });
}

// The strip subscribes to the shared hub, so a stream has to exist. Most tests
// drive no frames; the reconnect test drives connection state through `latest`.
class FakeEventSource {
  static latest: FakeEventSource | null = null;
  onopen: ((event: Event) => void) | null = null;
  onmessage: ((event: MessageEvent<string>) => void) | null = null;
  onerror: ((event: Event) => void) | null = null;
  constructor(readonly url: string) {
    FakeEventSource.latest = this;
  }
  addEventListener() {}
  close() {}
}

function renderStrip() {
  return render(
    <DrillProvider origin={ORIGIN}>
      <CitySignals />
    </DrillProvider>,
  );
}

/**
 * The strip's rendered sentence once the reads land — numbers and labels
 * together. Asserted as one string because the three counts are frequently the
 * same number, and each is only meaningful next to the thing it counts.
 */
async function stripText(): Promise<string> {
  const line = await screen.findByText(/waiting on you/);
  return line.textContent ?? '';
}

beforeEach(() => {
  pendingBody = { items: [], total: 0 };
  mailBody = { unread: 0, total: 0 };
  waitingBody = { items: [], total: 0 };
  requested = [];
  FakeEventSource.latest = null;
  vi.stubGlobal(
    'fetch',
    vi.fn((input: Request | string | URL) => Promise.resolve(routeFetch(input))),
  );
  vi.stubGlobal('EventSource', FakeEventSource);
});

afterEach(() => {
  // Explicit: these tests do not run with vitest globals, so @testing-library's
  // auto-cleanup hook is never registered.
  cleanup();
  vi.unstubAllGlobals();
});

describe('CitySignals', () => {
  it('states plain counts when every store answered', async () => {
    pendingBody = { items: [{ session_id: 'lx-8y6j' }], total: 1 };
    mailBody = { unread: 2, total: 9 };
    waitingBody = { items: [{ id: 'tk-parked' }], total: 1 };
    renderStrip();

    const text = await stripText();
    expect(text).toContain('1 waiting on you');
    expect(text).toContain('2 unread mail');
    expect(text).toContain('1 parked on an answer');
    // A quiet city looks quiet, not broken: no notice when nothing is missing.
    expect(screen.queryByText(/came back partial/)).toBeNull();
    expect(text).not.toContain('at least');
  });

  // The defect this pins: an exact "0 waiting on you" is the sentence an
  // operator reads to mean nobody needs them. A store that did not answer
  // cannot support that claim, and used to render it anyway — only mail's
  // `partial` flag was ever honoured.
  it('does not state an exact count when the pending read came back partial', async () => {
    pendingBody = {
      items: [],
      total: 0,
      partial: true,
      partial_errors: ['rig gascity: context canceled'],
    };
    renderStrip();

    expect(await stripText()).toContain('at least 0 waiting on you');
    expect(screen.getByText(/came back partial/)).toBeTruthy();
    expect(screen.getByText(/context canceled/)).toBeTruthy();
  });

  it('does not state an exact count when the gc:wait read came back partial', async () => {
    waitingBody = {
      items: [],
      total: 0,
      partial: true,
      partial_errors: ['rig signal-loom: context canceled'],
    };
    renderStrip();

    expect(await stripText()).toContain('at least 0 parked on an answer');
    expect(screen.getByText(/came back partial/)).toBeTruthy();
  });

  it('still honours a partial mail count', async () => {
    mailBody = { unread: 4, total: 40, partial: true, partial_errors: ['rig gascity: timeout'] };
    renderStrip();

    expect(await stripText()).toContain('at least 4 unread mail');
    expect(screen.getByText(/came back partial/)).toBeTruthy();
  });

  // The supervisor counts the whole match set and returns a page of it. Counting
  // the page instead understates the total the moment a response is truncated.
  it('counts what the supervisor counted, not the page it returned', async () => {
    pendingBody = { items: [{ session_id: 'lx-1' }, { session_id: 'lx-2' }], total: 7 };
    renderStrip();

    expect(await stripText()).toContain('7 waiting on you');
  });

  // The reconnect gap, on the signals strip: these counts move only on an event,
  // so a first connection that dies while still connecting — no cursor, so the
  // replacement restarts at the city head — would freeze the counts under a
  // "live" stream. The strip must refetch when the stream finally comes up.
  it('refetches when the first connection drops before it ever opened', async () => {
    renderStrip();
    await stripText();
    await waitFor(() => expect(FakeEventSource.latest).not.toBeNull());
    const before = requested.length;

    vi.useFakeTimers();
    try {
      const dropped = FakeEventSource.latest;
      // No onopen first: the connection fails while still in 'connecting'.
      act(() => dropped?.onerror?.(new Event('error')));
      await act(async () => {
        await vi.advanceTimersByTimeAsync(1_000);
      });
      expect(FakeEventSource.latest).not.toBe(dropped);
      expect(FakeEventSource.latest?.url).not.toContain('after_seq');
      act(() => FakeEventSource.latest?.onopen?.(new Event('open')));
      await act(async () => {
        await vi.advanceTimersByTimeAsync(3_000);
      });
    } finally {
      vi.useRealTimers();
    }

    await waitFor(() => expect(requested.length).toBeGreaterThan(before));
  });
});
