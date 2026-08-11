import { act, cleanup, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { DrillPanel } from './DrillPanel';
import { DrillProvider } from './context';
import type { SupervisorOrigin } from './origin';

// The board is opened over tailscale in normal use, so the fixture origin is a
// tailscale-style host rather than loopback: every URL asserted below is one
// the browser must be able to reach from a device that is not the city host.
const ORIGIN: SupervisorOrigin = {
  baseUrl: 'https://gc-host.tail1234.ts.net',
  city: 'loomington',
};
const BEAD_ID = 'tk-eemvf.3';

const BEAD = {
  id: BEAD_ID,
  title: 'helm web (U8): drill-in plane',
  status: 'in_progress',
  issue_type: 'task',
  priority: 1,
  created_at: '2026-08-11T06:52:14Z',
  updated_at: '2026-08-11T15:00:00Z',
  assignee: 'gc-toolkit__polecat-lx-8y6j',
  labels: ['helm'],
  description: 'Execute from the plan.',
};

const SESSION = {
  id: 'lx-8y6j',
  title: 'gc-toolkit/gc-toolkit.nux',
  alias: 'gc-toolkit/gc-toolkit.nux',
  state: 'active',
  provider: 'claude',
  session_name: 'gc-toolkit__polecat-lx-8y6j',
  template: 'gc-toolkit/gc-toolkit.polecat',
  created_at: '2026-08-11T15:06:00Z',
  running: true,
  attached: false,
  active_bead: BEAD_ID,
};

function event(overrides: Record<string, unknown> = {}) {
  return {
    seq: 100,
    type: 'bead.updated',
    ts: '2026-08-11T15:10:00Z',
    actor: 'polecat',
    subject: BEAD_ID,
    payload: {},
    ...overrides,
  };
}

/** URLs the stubbed fetch was asked for, in order. */
let requested: string[] = [];
let sessionPeek: string | undefined;
let historyEvents: unknown[] = [];
/**
 * Sessions the /sessions read reports. `null` makes the read fail outright —
 * the other way a caller can end up holding no sessions.
 */
let sessionItems: unknown[] | null = null;
/** Envelope fields merged into /sessions — `partial`, `partial_errors`, `total`. */
let sessionsEnvelope: Record<string, unknown> = {};
/** The same, for /events. */
let eventsEnvelope: Record<string, unknown> = {};

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
  if (pathname === `/v0/city/loomington/bead/${BEAD_ID}`) return jsonResponse(BEAD);
  if (pathname === '/v0/city/loomington/sessions') {
    if (sessionItems === null) {
      return new Response(JSON.stringify({ title: 'sessions unavailable' }), {
        status: 503,
        headers: { 'Content-Type': 'application/json' },
      });
    }
    return jsonResponse({ items: sessionItems, total: sessionItems.length, ...sessionsEnvelope });
  }
  if (pathname === `/v0/city/loomington/session/${SESSION.id}`) {
    return jsonResponse({ ...SESSION, last_output: sessionPeek });
  }
  if (pathname === '/v0/city/loomington/events') {
    return jsonResponse({ items: historyEvents, total: historyEvents.length, ...eventsEnvelope });
  }
  return new Response(JSON.stringify({ title: 'not found' }), {
    status: 404,
    headers: { 'Content-Type': 'application/json' },
  });
}

// One shared fake stream, so a test can push a frame after the panel mounts.
class FakeEventSource {
  static latest: FakeEventSource | null = null;
  onopen: ((event: Event) => void) | null = null;
  onmessage: ((event: MessageEvent<string>) => void) | null = null;
  onerror: ((event: Event) => void) | null = null;
  readonly listeners: EventListener[] = [];

  constructor(readonly url: string) {
    FakeEventSource.latest = this;
  }
  addEventListener(type: string, listener: EventListener) {
    if (type === 'event') this.listeners.push(listener);
  }
  close() {}
  emit(payload: unknown) {
    const data = JSON.stringify(payload);
    for (const listener of this.listeners) {
      listener(new MessageEvent('event', { data }) as Event);
    }
  }
}

function renderPanel() {
  return render(
    <DrillProvider origin={ORIGIN}>
      <DrillPanel beadId={BEAD_ID} onClose={() => {}} />
    </DrillProvider>,
  );
}

beforeEach(() => {
  requested = [];
  sessionPeek = undefined;
  historyEvents = [];
  sessionItems = [SESSION];
  sessionsEnvelope = {};
  eventsEnvelope = {};
  FakeEventSource.latest = null;
  vi.stubGlobal(
    'fetch',
    vi.fn((input: Request | string | URL) => Promise.resolve(routeFetch(input))),
  );
  vi.stubGlobal('EventSource', FakeEventSource);
});

afterEach(() => {
  // Explicit because these tests do not run with vitest globals, so
  // @testing-library's auto-cleanup hook is never registered and mounted trees
  // would otherwise pile up across cases.
  cleanup();
  vi.unstubAllGlobals();
});

describe('DrillPanel', () => {
  it('opens a tile and shows its live detail', async () => {
    sessionPeek = 'running go test ./...';
    renderPanel();

    expect(await screen.findByText('helm web (U8): drill-in plane')).toBeTruthy();
    // The bead's own state, and the session working it, with its peeked output —
    // the "dive in and read the latest" the tile is opened for.
    await waitFor(() => expect(screen.getByText(/gc-toolkit__polecat-lx-8y6j/)).toBeTruthy());
    await waitFor(() => expect(screen.getByText(/running go test/)).toBeTruthy());
  });

  // The reachability requirement made concrete: every request goes to the
  // origin the document came from. A loopback URL here would 404 for an
  // operator reading the board over tailscale, and would be blocked by the
  // app's own connect-src 'self' policy before it left the page.
  it('addresses the supervisor on the document origin', async () => {
    renderPanel();
    await screen.findByText('helm web (U8): drill-in plane');

    expect(requested.length).toBeGreaterThan(0);
    for (const url of requested) {
      expect(url.startsWith('https://gc-host.tail1234.ts.net/v0/city/loomington/')).toBe(true);
    }
    expect(requested).toContain(
      `https://gc-host.tail1234.ts.net/v0/city/loomington/bead/${BEAD_ID}`,
    );
    await waitFor(() => expect(FakeEventSource.latest).not.toBeNull());
    expect(FakeEventSource.latest?.url).toBe(
      'https://gc-host.tail1234.ts.net/v0/city/loomington/events/stream',
    );
  });

  it('seeds activity from recent history, keeping only this anchor', async () => {
    historyEvents = [
      event({ seq: 90, type: 'bead.updated', subject: BEAD_ID }),
      event({ seq: 89, type: 'order.completed', subject: 'dolt-health' }),
    ];
    renderPanel();

    await waitFor(() => expect(screen.getByText('bead.updated')).toBeTruthy());
    expect(screen.queryByText('order.completed')).toBeNull();
  });

  // The live half: a frame off the stream lands in the panel with no refetch.
  it('applies an SSE event to live state', async () => {
    renderPanel();
    await screen.findByText('helm web (U8): drill-in plane');
    await waitFor(() => expect(FakeEventSource.latest).not.toBeNull());

    expect(screen.queryByText('session.woke')).toBeNull();
    FakeEventSource.latest?.emit(event({ seq: 101, type: 'session.woke', subject: BEAD_ID }));
    expect(await screen.findByText('session.woke')).toBeTruthy();
  });

  it('ignores stream events about other anchors', async () => {
    renderPanel();
    await waitFor(() => expect(FakeEventSource.latest).not.toBeNull());

    FakeEventSource.latest?.emit(event({ seq: 102, type: 'mail.sent', subject: 'someone-else' }));
    await waitFor(() => expect(screen.getByText(/Nothing for this anchor/)).toBeTruthy());
  });

  it('does not repeat an event redelivered after a reconnect', async () => {
    renderPanel();
    await waitFor(() => expect(FakeEventSource.latest).not.toBeNull());

    const redelivered = event({ seq: 103, type: 'bead.closed', subject: BEAD_ID });
    FakeEventSource.latest?.emit(redelivered);
    FakeEventSource.latest?.emit(redelivered);
    expect(await screen.findAllByText('bead.closed')).toHaveLength(1);
  });

  it('says so plainly when no session is working the anchor', async () => {
    // The fixture session claims BEAD_ID, so drill a bead nothing is working:
    // an anchor with no agent on it is a normal state, not an error.
    render(
      <DrillProvider origin={ORIGIN}>
        <DrillPanel beadId="tk-unworked" onClose={() => {}} />
      </DrillProvider>,
    );
    expect(await screen.findByText(/No agent is working/)).toBeTruthy();
  });

  // Partial data is first-class on this surface, and the failure mode it
  // prevents is specific: an unanswered session store rendering as the sentence
  // an operator reads to mean "nothing is happening here, look elsewhere".
  it('does not claim the anchor is unworked when the session list came back partial', async () => {
    sessionItems = []; // the stores that did answer had nothing
    sessionsEnvelope = { partial: true, partial_errors: ['rig gascity: context canceled'] };
    renderPanel();

    expect(await screen.findByText(/Could not tell whether an agent is working/)).toBeTruthy();
    expect(screen.queryByText(/No agent is working/)).toBeNull();
    // The reason the supervisor gave travels with it — "incomplete" without a
    // cause leaves the operator no idea whether to wait or go look.
    expect(screen.getByText(/context canceled/)).toBeTruthy();
  });

  // Same statement, other route to it: a read that never landed is the
  // maximally incomplete one, not an authoritative empty list.
  it('does not claim the anchor is unworked when the session read fails outright', async () => {
    sessionItems = null;
    renderPanel();

    expect(await screen.findByText(/Could not tell whether an agent is working/)).toBeTruthy();
    expect(screen.queryByText(/No agent is working/)).toBeNull();
  });

  it('still names the session working the anchor when the list is otherwise partial', async () => {
    // A match settles the question whatever else went missing, so this must not
    // over-correct into refusing to answer when it actually knows.
    sessionsEnvelope = { partial: true, partial_errors: ['rig signal-loom: context canceled'] };
    renderPanel();

    await waitFor(() => expect(screen.getByText(/gc-toolkit\/gc-toolkit\.nux/)).toBeTruthy());
    expect(screen.queryByText(/Could not tell whether an agent is working/)).toBeNull();
  });

  it('says the recent log was incomplete rather than showing a bare empty history', async () => {
    eventsEnvelope = { partial: true, partial_errors: ['rig shutupandlisten: context canceled'] };
    renderPanel();

    expect(await screen.findByText(/came back partial/)).toBeTruthy();
    expect(screen.getByText(/part of the city log that answered/)).toBeTruthy();
    expect(screen.queryByText(/Nothing for this anchor/)).toBeNull();
  });

  it('shows no partial notice when every store answered', async () => {
    renderPanel();
    await screen.findByText('helm web (U8): drill-in plane');

    await waitFor(() => expect(screen.getByText(/Nothing for this anchor/)).toBeTruthy());
    expect(screen.queryByText(/came back partial/)).toBeNull();
  });

  // The other half of the reconnect story. `after_seq` closes the gap whenever
  // the stream has delivered something to resume from (see events.test.ts); a
  // drop before the first event has no cursor, so the replacement starts at the
  // city head and whatever happened in between is unrecoverable. This panel
  // refetches only in response to a delivered event, so without this it would
  // sit on stale state under a "live" indicator, indefinitely.
  it('refetches after a reconnect it could not resume', async () => {
    renderPanel();
    // Settle the whole opening read before counting: this text renders only
    // once the bead, session and history have all resolved.
    await screen.findByText(/Nothing for this anchor/);
    await waitFor(() => expect(FakeEventSource.latest).not.toBeNull());
    const before = requested.length;

    // Fake timers only across the reconnect, so the assertions above and below
    // keep the real ones @testing-library's waitFor needs to make progress.
    vi.useFakeTimers();
    try {
      const dropped = FakeEventSource.latest;
      act(() => dropped?.onopen?.(new Event('open')));
      act(() => dropped?.onerror?.(new Event('error')));
      // Backoff elapses and a replacement connects — carrying no cursor,
      // because nothing was ever delivered on the connection that died.
      await act(async () => {
        await vi.advanceTimersByTimeAsync(1_000);
      });
      expect(FakeEventSource.latest).not.toBe(dropped);
      expect(FakeEventSource.latest?.url).not.toContain('after_seq');
      act(() => FakeEventSource.latest?.onopen?.(new Event('open')));
      await act(async () => {
        await vi.advanceTimersByTimeAsync(2_000);
      });
    } finally {
      vi.useRealTimers();
    }

    await waitFor(() => expect(requested.length).toBeGreaterThan(before));
  });

  // The gap the old "only after open" guard missed: the very first connection
  // dies while still connecting — before onopen, before any event. Its
  // replacement also carries no cursor, so the same unrecoverable gap opens; the
  // panel must refetch when the stream finally comes up, not trust it was empty.
  it('refetches when the first connection drops before it ever opened', async () => {
    renderPanel();
    await screen.findByText(/Nothing for this anchor/);
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
      // Replacement carries no cursor, because nothing was ever delivered.
      expect(FakeEventSource.latest).not.toBe(dropped);
      expect(FakeEventSource.latest?.url).not.toContain('after_seq');
      act(() => FakeEventSource.latest?.onopen?.(new Event('open')));
      await act(async () => {
        await vi.advanceTimersByTimeAsync(2_000);
      });
    } finally {
      vi.useRealTimers();
    }

    await waitFor(() => expect(requested.length).toBeGreaterThan(before));
  });

  // Switching tiles must not bleed one anchor's detail into another's panel.
  // Opening tile B drops A's title/facts/session/activity in the same render, so
  // B never shows them under its header while B loads — and if B's own bead read
  // fails, the alert stands over an empty panel, not over A's stale detail.
  it('drops the previous anchor detail when another tile is opened', async () => {
    historyEvents = [event({ seq: 90, type: 'bead.updated', subject: BEAD_ID })];
    const { rerender } = renderPanel();
    await screen.findByText('helm web (U8): drill-in plane');
    await waitFor(() => expect(screen.getByText(/gc-toolkit__polecat-lx-8y6j/)).toBeTruthy());
    await waitFor(() => expect(screen.getByText('bead.updated')).toBeTruthy());

    // Open a second tile whose bead read fails (404). Synchronously — while B is
    // still loading — the first anchor's detail is already gone.
    rerender(
      <DrillProvider origin={ORIGIN}>
        <DrillPanel beadId="tk-missing" onClose={() => {}} />
      </DrillProvider>,
    );
    expect(screen.queryByText('helm web (U8): drill-in plane')).toBeNull();
    expect(screen.queryByText(/gc-toolkit__polecat-lx-8y6j/)).toBeNull();
    expect(screen.queryByText('bead.updated')).toBeNull();

    // And once B's read has failed, the alert stands over an empty panel — the
    // stale detail never reappears under it.
    expect(await screen.findByRole('alert')).toBeTruthy();
    expect(screen.queryByText('helm web (U8): drill-in plane')).toBeNull();
    expect(screen.queryByText('bead.updated')).toBeNull();
  });

  it('reports a failed bead read instead of rendering an empty panel', async () => {
    render(
      <DrillProvider origin={ORIGIN}>
        <DrillPanel beadId="tk-missing" onClose={() => {}} />
      </DrillProvider>,
    );
    expect(await screen.findByRole('alert')).toBeTruthy();
  });

  it('renders nothing when no tile is open', () => {
    const { container } = render(
      <DrillProvider origin={ORIGIN}>
        <DrillPanel beadId={null} onClose={() => {}} />
      </DrillProvider>,
    );
    expect(container.querySelector('.drill')).toBeNull();
  });
});
