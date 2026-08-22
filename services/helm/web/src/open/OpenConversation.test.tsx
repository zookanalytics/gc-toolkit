import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { OpenConversation } from './OpenConversation';

// What this file guards is the operator's READING of the action: that a click
// files the visit, that "filed" and "already open" do not read the same, that a
// failure says WHICH failure, and that nothing here claims to have attached the
// operator to anything.
//
// Matchers are plain vitest and interaction is fireEvent, matching App.test.tsx
// — this package carries neither jest-dom nor user-event, and the board's
// bundle is committed, so a test-only dependency is not free here.

const BEAD_ID = 'tk-eemvf.3';

/** Every request the component made, in order. */
let calls: { url: string; init: RequestInit | undefined }[] = [];
/** What the stubbed endpoint answers next. */
let reply: () => Response | Promise<Response>;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function text(el: HTMLElement): string {
  return el.textContent ?? '';
}

beforeEach(() => {
  calls = [];
  reply = () =>
    json({
      bead: BEAD_ID,
      outcome: 'filed',
      visit: 'tk-v1s1t',
      message: `visit tk-v1s1t filed on ${BEAD_ID} (pool gc-toolkit/gc-toolkit.converse) — a converse session will spawn (cold) or vacuum it (warm).`,
    });
  vi.stubGlobal('fetch', (input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
    calls.push({ url, init });
    return Promise.resolve(reply());
  });
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

function clickOpen() {
  fireEvent.click(screen.getByRole('button', { name: /start a conversation/i }));
}

describe('OpenConversation', () => {
  it('POSTs the bead to the board service, document-relative', async () => {
    render(<OpenConversation beadId={BEAD_ID} />);
    clickOpen();

    await waitFor(() => expect(calls).toHaveLength(1));
    const [call] = calls;
    // Document-relative: the app is served under /v0/city/<city>/svc/helm/, so
    // an absolute '/helm/open' would address the supervisor root and 404.
    expect(call.url).toBe('helm/open');
    expect(call.init?.method).toBe('POST');
    expect(JSON.parse(String(call.init?.body))).toEqual({ bead: BEAD_ID });
  });

  it('reports a filed visit without claiming to have attached the operator', async () => {
    render(<OpenConversation beadId={BEAD_ID} />);
    clickOpen();

    const status = await screen.findByRole('status');
    expect(text(status)).toContain('A conversation is being opened.');
    // The tool's own sentence survives to the browser.
    expect(text(status)).toContain('visit tk-v1s1t filed on');
    // …and the one thing the tool does not say.
    expect(text(status)).toMatch(/does not attach you/i);
  });

  it('says something DIFFERENT when a visit was already open', async () => {
    reply = () =>
      json({
        bead: BEAD_ID,
        outcome: 'existing',
        visit: 'tk-old99',
        message: `visit tk-old99 is already open for ${BEAD_ID} — a converse session holds it (or will spawn/vacuum it).`,
      });
    render(<OpenConversation beadId={BEAD_ID} />);
    clickOpen();

    const status = await screen.findByRole('status');
    expect(text(status)).toContain('A conversation is already open on this bead.');
    expect(text(status)).toContain('tk-old99');
    // Told "being opened" here, an operator would believe a second conversation
    // now exists. It does not — the tool deliberately filed nothing.
    expect(text(status)).not.toContain('A conversation is being opened.');
  });

  // THE OPERATOR'S ACTUAL COMPLAINT: different operator moves must not render
  // identically. Each reason gets its own next step alongside the service's
  // own sentence.
  it('renders a distinct, actionable message per failure reason', async () => {
    const cases = [
      {
        reason: 'environment',
        error: 'could not enumerate rigs',
        status: 503,
        want: /data plane|gc doctor/i,
      },
      {
        reason: 'verb_failed',
        error:
          "bead not found: 'zz-nope1' — its id prefix 'zz' matches no rig in 'gc rig list'. No visit filed.",
        status: 422,
        want: /matches no rig/i,
      },
      {
        reason: 'timeout',
        error: 'the visit tool did not finish in time',
        status: 504,
        want: /nothing was filed/i,
      },
      {
        reason: 'unavailable',
        error: 'this board cannot file visits',
        status: 503,
        want: /without the visit tool|unreachable/i,
      },
    ];

    const rendered: string[] = [];
    for (const tc of cases) {
      reply = () => json({ error: tc.error, reason: tc.reason }, tc.status);
      const { unmount } = render(<OpenConversation beadId={BEAD_ID} />);
      clickOpen();
      const alert = await screen.findByRole('alert');
      expect(text(alert)).toMatch(tc.want);
      // The service's own sentence is always shown, verbatim.
      expect(text(alert)).toContain(tc.error);
      rendered.push(text(alert));
      unmount();
    }
    // No two failures read the same — the whole point of the mapping.
    expect(new Set(rendered).size).toBe(cases.length);
  });

  it('distinguishes a request that never reached the service', async () => {
    vi.stubGlobal('fetch', () => Promise.reject(new TypeError('Failed to fetch')));
    render(<OpenConversation beadId={BEAD_ID} />);
    clickOpen();

    const alert = await screen.findByRole('alert');
    expect(text(alert)).toMatch(/could not reach the board service/i);
    expect(text(alert)).toMatch(/no visit was filed/i);
  });

  it('falls back to the status code when the body carries no message', async () => {
    reply = () => new Response('<html>502</html>', { status: 502 });
    render(<OpenConversation beadId={BEAD_ID} />);
    clickOpen();

    const alert = await screen.findByRole('alert');
    expect(text(alert)).toContain('502');
  });

  // The drill panel stays mounted as the operator moves between tiles, so this
  // component is handed a new beadId rather than being remounted. A result left
  // over from the previous bead would then sit under the NEW bead's title,
  // telling the operator a conversation was opened on a row where it was not.
  it('drops a result when the panel is pointed at a different bead', async () => {
    const { rerender } = render(<OpenConversation beadId={BEAD_ID} />);
    clickOpen();
    const status = await screen.findByRole('status');
    expect(text(status)).toContain('visit tk-v1s1t filed on');

    rerender(<OpenConversation beadId="tk-other9" />);
    expect(screen.queryByRole('status')).toBeNull();
    // …and the action is offered afresh for the new bead.
    expect(screen.getByRole('button', { name: /start a conversation/i })).toBeTruthy();
  });

  it('drops a failure when the panel is pointed at a different bead', async () => {
    reply = () => json({ error: 'could not enumerate rigs', reason: 'environment' }, 503);
    const { rerender } = render(<OpenConversation beadId={BEAD_ID} />);
    clickOpen();
    await screen.findByRole('alert');

    rerender(<OpenConversation beadId="tk-other9" />);
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('ignores a response that lands after the panel moved to another bead', async () => {
    let release: (r: Response) => void = () => {};
    reply = () =>
      new Promise<Response>((resolve) => {
        release = resolve;
      });

    const { rerender } = render(<OpenConversation beadId={BEAD_ID} />);
    clickOpen();
    await screen.findByRole('button', { name: /opening…/i });

    rerender(<OpenConversation beadId="tk-other9" />);
    release(
      json({ bead: BEAD_ID, outcome: 'filed', visit: 'tk-v1s1t', message: 'visit tk-v1s1t filed on x' }),
    );
    // Give the settled promise a turn to run.
    await waitFor(() =>
      expect(screen.getByRole('button', { name: /start a conversation/i })).toBeTruthy(),
    );
    expect(screen.queryByRole('status')).toBeNull();
  });

  it('disables the button while a request is in flight and makes only one', async () => {
    let release: (r: Response) => void = () => {};
    reply = () =>
      new Promise<Response>((resolve) => {
        release = resolve;
      });

    render(<OpenConversation beadId={BEAD_ID} />);
    clickOpen();

    const button = await screen.findByRole('button', { name: /opening…/i });
    expect((button as HTMLButtonElement).disabled).toBe(true);

    // A second click while in flight must not queue a second visit.
    fireEvent.click(button);
    expect(calls).toHaveLength(1);

    release(
      json({ bead: BEAD_ID, outcome: 'filed', visit: 'tk-v', message: 'visit tk-v filed on x' }),
    );
    await screen.findByRole('status');
    expect(calls).toHaveLength(1);
  });
});
