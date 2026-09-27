import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ActuateButton } from './ActuateButton';

// What this file guards is the operator's READING of the three parity actions:
// that a click runs the verb its route names, that the tool's sentence reaches the
// browser, that engage never claims to have attached anyone, that a failure says
// WHICH failure, and that a result never lingers under the wrong bead.
//
// Matchers are plain vitest and interaction is fireEvent, matching
// OpenConversation.test.tsx — this package carries neither jest-dom nor
// user-event.

const BEAD_ID = 'tk-eemvf.3';

let calls: { url: string; init: RequestInit | undefined }[] = [];
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
  reply = () => json({ bead: BEAD_ID, verb: 'accept', message: 'accept: dispatched mol-x at ' + BEAD_ID });
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

describe('ActuateButton', () => {
  it('POSTs the bead to the verb-named route, document-relative', async () => {
    for (const verb of ['accept', 'engage', 'dismiss'] as const) {
      calls = [];
      reply = () => json({ bead: BEAD_ID, verb, message: `${verb}: ok` });
      const { unmount } = render(<ActuateButton verb={verb} beadId={BEAD_ID} formula="mol-x" />);
      fireEvent.click(screen.getByRole('button'));
      await waitFor(() => expect(calls).toHaveLength(1));
      const [call] = calls;
      // Document-relative: an absolute '/helm/<verb>' would address the supervisor
      // root and 404.
      expect(call.url).toBe(`helm/${verb}`);
      expect(call.init?.method).toBe('POST');
      expect(JSON.parse(String(call.init?.body))).toEqual({ bead: BEAD_ID });
      unmount();
    }
  });

  it('accept names its formula, reports the tool sentence, and refreshes the board', async () => {
    const onDone = vi.fn();
    reply = () => json({ bead: BEAD_ID, verb: 'accept', message: 'accept: dispatched mol-dispose-pr at ' + BEAD_ID });
    render(<ActuateButton verb="accept" beadId={BEAD_ID} formula="mol-dispose-pr" onDone={onDone} />);
    // The resting label names the formula, mirroring the CLI board's "accept ▸".
    expect(screen.getByRole('button', { name: /accept ▸ mol-dispose-pr/i })).toBeTruthy();

    fireEvent.click(screen.getByRole('button'));
    const status = await screen.findByRole('status');
    expect(text(status)).toContain('dispatched mol-dispose-pr');
    // A successful board write refreshes the row.
    expect(onDone).toHaveBeenCalledTimes(1);
  });

  it('engage reports the sitting without claiming to have attached the operator', async () => {
    reply = () =>
      json({ bead: BEAD_ID, verb: 'engage', message: '✓ converse-opus on new visit tk-v1 for ' + BEAD_ID + '\n  attach: gc session attach gc-42' });
    render(<ActuateButton verb="engage" beadId={BEAD_ID} />);
    fireEvent.click(screen.getByRole('button', { name: /discuss/i }));

    const status = await screen.findByRole('status');
    // The tool's own sentence, including the attach line, survives.
    expect(text(status)).toContain('gc session attach gc-42');
    // …and the one thing the tool does not say.
    expect(text(status)).toMatch(/does not attach you/i);
  });

  it('dismiss reports the closed visit', async () => {
    reply = () => json({ bead: BEAD_ID, verb: 'dismiss', message: 'dismiss: closed visit tk-v1 — the sitting on ' + BEAD_ID + ' ends' });
    render(<ActuateButton verb="dismiss" beadId={BEAD_ID} />);
    fireEvent.click(screen.getByRole('button', { name: /dismiss/i }));

    const status = await screen.findByRole('status');
    expect(text(status)).toContain('closed visit tk-v1');
  });

  it('falls back to a verb sentence when the tool message is empty', async () => {
    reply = () => json({ bead: BEAD_ID, verb: 'dismiss', message: '' });
    render(<ActuateButton verb="dismiss" beadId={BEAD_ID} />);
    fireEvent.click(screen.getByRole('button', { name: /dismiss/i }));
    const status = await screen.findByRole('status');
    expect(text(status)).toMatch(/visit was closed/i);
  });

  // Different operator moves must not render identically: each reason gets its own
  // next step alongside the service's own sentence.
  it('renders a distinct, actionable message per failure reason', async () => {
    const cases = [
      { reason: 'environment', error: 'could not enumerate rigs', status: 503, want: /data plane|gc doctor/i },
      {
        reason: 'verb_failed',
        // accept's discuss-only refusal — the script's sentence is the whole story,
        // so no extra hint is added, only shown verbatim.
        error: 'tk-abc12 carries no gc.recommended_formula — it is discuss-only. Engage it to decide.',
        status: 422,
        want: /discuss-only/i,
      },
      {
        reason: 'timeout',
        error: 'the write tool did not finish in time',
        status: 504,
        want: /may still have gone through|check the bead/i,
      },
      { reason: 'unavailable', error: 'this board cannot actuate', status: 503, want: /without the write tool|unreachable/i },
    ];

    const rendered: string[] = [];
    for (const tc of cases) {
      reply = () => json({ error: tc.error, reason: tc.reason }, tc.status);
      const { unmount } = render(<ActuateButton verb="accept" beadId={BEAD_ID} formula="mol-x" />);
      fireEvent.click(screen.getByRole('button'));
      const alert = await screen.findByRole('alert');
      expect(text(alert)).toMatch(tc.want);
      // The service's own sentence is always shown, verbatim.
      expect(text(alert)).toContain(tc.error);
      rendered.push(text(alert));
      unmount();
    }
    expect(new Set(rendered).size).toBe(cases.length);
  });

  it('does not refresh the board on a failure', async () => {
    const onDone = vi.fn();
    reply = () => json({ error: 'discuss-only', reason: 'verb_failed' }, 422);
    render(<ActuateButton verb="accept" beadId={BEAD_ID} formula="mol-x" onDone={onDone} />);
    fireEvent.click(screen.getByRole('button'));
    await screen.findByRole('alert');
    expect(onDone).not.toHaveBeenCalled();
  });

  it('distinguishes a request that never reached the service, in the verb’s terms', async () => {
    vi.stubGlobal('fetch', () => Promise.reject(new TypeError('Failed to fetch')));
    render(<ActuateButton verb="accept" beadId={BEAD_ID} formula="mol-x" />);
    fireEvent.click(screen.getByRole('button'));
    const alert = await screen.findByRole('alert');
    expect(text(alert)).toMatch(/could not reach the board service/i);
    // A transport failure does not prove the request never arrived.
    expect(text(alert)).toMatch(/may still have been dispatched/i);
  });

  it('falls back to the status code when the body carries no message', async () => {
    reply = () => new Response('<html>502</html>', { status: 502 });
    render(<ActuateButton verb="engage" beadId={BEAD_ID} />);
    fireEvent.click(screen.getByRole('button', { name: /discuss/i }));
    const alert = await screen.findByRole('alert');
    expect(text(alert)).toContain('502');
  });

  // The drill panel stays mounted as the operator moves between tiles, so this
  // button is handed a new beadId rather than being remounted. A result left over
  // from the previous bead would sit under the NEW bead.
  it('drops a result when pointed at a different bead', async () => {
    reply = () => json({ bead: BEAD_ID, verb: 'dismiss', message: 'dismiss: closed visit tk-v1' });
    const { rerender } = render(<ActuateButton verb="dismiss" beadId={BEAD_ID} />);
    fireEvent.click(screen.getByRole('button', { name: /dismiss/i }));
    await screen.findByRole('status');

    rerender(<ActuateButton verb="dismiss" beadId="tk-other9" />);
    expect(screen.queryByRole('status')).toBeNull();
    expect(screen.getByRole('button', { name: /dismiss/i })).toBeTruthy();
  });

  it('ignores a response that lands after the bead changed', async () => {
    let release: (r: Response) => void = () => {};
    reply = () => new Promise<Response>((resolve) => { release = resolve; });

    const { rerender } = render(<ActuateButton verb="dismiss" beadId={BEAD_ID} />);
    fireEvent.click(screen.getByRole('button', { name: /^dismiss$/i }));
    await screen.findByRole('button', { name: /dismissing…/i });

    rerender(<ActuateButton verb="dismiss" beadId="tk-other9" />);
    release(json({ bead: BEAD_ID, verb: 'dismiss', message: 'dismiss: closed visit tk-v1' }));
    await waitFor(() => expect(screen.getByRole('button', { name: /^dismiss$/i })).toBeTruthy());
    expect(screen.queryByRole('status')).toBeNull();
  });

  it('disables the button while a request is in flight and makes only one', async () => {
    let release: (r: Response) => void = () => {};
    reply = () => new Promise<Response>((resolve) => { release = resolve; });

    render(<ActuateButton verb="accept" beadId={BEAD_ID} formula="mol-x" />);
    fireEvent.click(screen.getByRole('button'));

    const button = await screen.findByRole('button', { name: /accepting…/i });
    expect((button as HTMLButtonElement).disabled).toBe(true);

    fireEvent.click(button);
    expect(calls).toHaveLength(1);

    release(json({ bead: BEAD_ID, verb: 'accept', message: 'accept: dispatched mol-x at x' }));
    await screen.findByRole('status');
    expect(calls).toHaveLength(1);
  });
});
