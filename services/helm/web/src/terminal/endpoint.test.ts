import { describe, expect, it } from 'vitest';

import {
  DEFAULT_TERMINAL_BASE,
  probeTerminal,
  resolveTerminalBase,
  socketURL,
  tokenURL,
} from './endpoint';

function response(body: string, contentType: string, status = 200): Response {
  return new Response(body, { status, headers: { 'content-type': contentType } });
}

describe('resolveTerminalBase', () => {
  it('defaults to where the city publishes ttyd', () => {
    expect(resolveTerminalBase('')).toBe(DEFAULT_TERMINAL_BASE);
    expect(resolveTerminalBase('?other=1')).toBe(DEFAULT_TERMINAL_BASE);
  });

  it('accepts a same-origin path override', () => {
    expect(resolveTerminalBase('?terminal=/tty')).toBe('/tty');
    expect(resolveTerminalBase('?terminal=/tty/')).toBe('/tty');
  });

  it('refuses anything that could aim the terminal off-origin', () => {
    // A full URL, a protocol-relative host, and a bare relative path are all
    // rejected: the CSP would block the first two anyway, and silently
    // honouring them would make this knob a way to point an operator's
    // terminal session at somebody else's host.
    expect(resolveTerminalBase('?terminal=https://evil.test/terminal')).toBe(DEFAULT_TERMINAL_BASE);
    expect(resolveTerminalBase('?terminal=//evil.test/terminal')).toBe(DEFAULT_TERMINAL_BASE);
    expect(resolveTerminalBase('?terminal=terminal')).toBe(DEFAULT_TERMINAL_BASE);
  });
});

describe('endpoint URLs', () => {
  it('builds the token URL under the base', () => {
    expect(tokenURL('/terminal')).toBe('/terminal/token');
    expect(tokenURL('/terminal/')).toBe('/terminal/token');
  });

  it('uses wss from a secure document and ws otherwise', () => {
    expect(socketURL('/terminal', { protocol: 'https:', host: 'box.ts.net' })).toBe(
      'wss://box.ts.net/terminal/ws',
    );
    expect(socketURL('/terminal', { protocol: 'http:', host: '127.0.0.1:5175' })).toBe(
      'ws://127.0.0.1:5175/terminal/ws',
    );
  });
});

describe('probeTerminal', () => {
  it('accepts real ttyd, including its usual empty token', async () => {
    // Byte-for-byte what the deployed ttyd 1.7.7 answers.
    const probe = await probeTerminal('/terminal', async () =>
      response('{"token": ""}', 'application/json;charset=utf-8'),
    );
    expect(probe).toEqual({ reachable: true, token: '' });
  });

  it('returns a configured token when ttyd has credentials', async () => {
    const probe = await probeTerminal('/terminal', async () =>
      response('{"token": "abc123"}', 'application/json'),
    );
    expect(probe).toEqual({ reachable: true, token: 'abc123' });
  });

  // The finding that motivated a content-type check instead of a status check.
  // The supervisor answers every unmatched path with a 200 and an HTML shell,
  // so on an origin that does not route ttyd, `GET /terminal/token` looks
  // perfectly healthy to a status-only probe and the terminal fails later, at
  // the socket, with nothing to explain it.
  it('rejects an SPA catch-all that 200s every path', async () => {
    const probe = await probeTerminal('/terminal', async () =>
      response('<!doctype html><html lang="en">', 'text/html; charset=utf-8'),
    );
    expect(probe.reachable).toBe(false);
    if (!probe.reachable) {
      expect(probe.reason).toContain('not ttyd on this origin');
      expect(probe.reason).toContain('text/html');
    }
  });

  it('reports a non-200', async () => {
    const probe = await probeTerminal('/terminal', async () =>
      response('nope', 'text/plain', 502),
    );
    expect(probe).toEqual({ reachable: false, reason: 'terminal endpoint returned HTTP 502' });
  });

  it('reports a transport failure', async () => {
    const probe = await probeTerminal('/terminal', async () => {
      throw new Error('connection refused');
    });
    expect(probe.reachable).toBe(false);
    if (!probe.reachable) expect(probe.reason).toContain('connection refused');
  });

  it('rejects JSON without a usable token', async () => {
    const missing = await probeTerminal('/terminal', async () => response('{}', 'application/json'));
    expect(missing).toEqual({
      reachable: false,
      reason: 'terminal token response had no token field',
    });

    const wrongType = await probeTerminal('/terminal', async () =>
      response('{"token": 7}', 'application/json'),
    );
    expect(wrongType).toEqual({ reachable: false, reason: 'terminal token was not a string' });
  });

  it('requests the token from under the base path', async () => {
    const seen: string[] = [];
    await probeTerminal('/terminal', async (input) => {
      seen.push(String(input));
      return response('{"token": ""}', 'application/json');
    });
    expect(seen).toEqual(['/terminal/token']);
  });
});
