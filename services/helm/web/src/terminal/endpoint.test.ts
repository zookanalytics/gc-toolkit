import { describe, expect, it } from 'vitest';

import {
  DEFAULT_TERMINAL_BASE,
  probeTerminal,
  resolveTerminalBase,
  resolveTerminalSession,
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

  const secure = { protocol: 'https:', host: 'box.ts.net' };

  // The behaviour this whole change exists to produce: the socket, not the
  // systemd unit, names the session.
  it('carries the chosen session as ttyd expects it', () => {
    expect(socketURL('/terminal', secure, 'gc-toolkit.mayor')).toBe(
      'wss://box.ts.net/terminal/ws?arg=gc-toolkit.mayor',
    );
  });

  // Naming no session must produce the request the board made before the
  // target was selectable — no parameter at all, not an empty one. ttyd turns
  // a bare `?arg=` into one empty argument rather than none (verified against
  // 1.7.7), so the two are genuinely different on the far side.
  it('omits the parameter entirely when no session is named', () => {
    expect(socketURL('/terminal', secure)).toBe('wss://box.ts.net/terminal/ws');
    expect(socketURL('/terminal', secure, undefined)).toBe('wss://box.ts.net/terminal/ws');
    expect(socketURL('/terminal', secure, '')).toBe('wss://box.ts.net/terminal/ws');
  });

  // A rig-scoped session name contains a '/'. It has to survive, because these
  // are the sessions an operator actually dives into.
  it('encodes a rig-scoped session name', () => {
    expect(socketURL('/terminal', secure, 'gc-toolkit/gc-toolkit.witness')).toBe(
      'wss://box.ts.net/terminal/ws?arg=gc-toolkit%2Fgc-toolkit.witness',
    );
  });

  // THE INJECTION THAT ENCODING PREVENTS. ttyd appends *every* `arg` in the
  // query string to the child's argv, so a name carrying its own `&arg=` would
  // append a second argument — the shape of an attempt to slip a flag past the
  // guard. Encoding makes it one argument, whatever it contains.
  it('cannot be made to smuggle a second argument', () => {
    const url = socketURL('/terminal', secure, 'gc-toolkit.mayor&arg=--evil');
    expect(url).toBe('wss://box.ts.net/terminal/ws?arg=gc-toolkit.mayor%26arg%3D--evil');
    // One `arg`, and it is the whole hostile string rather than two values.
    const args = new URL(url.replace(/^wss:/, 'https:')).searchParams.getAll('arg');
    expect(args).toEqual(['gc-toolkit.mayor&arg=--evil']);
  });

  it('percent-encodes the rest of the hostile alphabet', () => {
    const args = (name: string) =>
      new URL(socketURL('/terminal', secure, name).replace(/^wss:/, 'https:')).searchParams.getAll(
        'arg',
      );
    // Each of these was verified to reach argv intact through ttyd, so each
    // must arrive as exactly one argument for the guard to refuse.
    expect(args('a b')).toEqual(['a b']);
    expect(args('$(id)')).toEqual(['$(id)']);
    expect(args('../etc/passwd')).toEqual(['../etc/passwd']);
    expect(args('-v')).toEqual(['-v']);
    expect(args('a#b?c')).toEqual(['a#b?c']);
  });
});

describe('resolveTerminalSession', () => {
  it('names no session by default', () => {
    expect(resolveTerminalSession('')).toBeUndefined();
    expect(resolveTerminalSession('?terminal=/tty')).toBeUndefined();
  });

  it('reads the session override', () => {
    expect(resolveTerminalSession('?session=gc-toolkit.mayor')).toBe('gc-toolkit.mayor');
    expect(resolveTerminalSession('?terminal=/tty&session=lx-k7r38')).toBe('lx-k7r38');
    // URLSearchParams decodes, so a rig-scoped name arrives whole.
    expect(resolveTerminalSession('?session=gc-toolkit%2Fgc-toolkit.witness')).toBe(
      'gc-toolkit/gc-toolkit.witness',
    );
  });

  // Blank is not a session name; it is the absence of one, and it must land on
  // the default rather than travelling as an empty argument.
  it('treats a blank override as naming nothing', () => {
    expect(resolveTerminalSession('?session=')).toBeUndefined();
    expect(resolveTerminalSession('?session=%20%20')).toBeUndefined();
  });

  // This function deliberately does not validate: the guard script does, against
  // the live session list, before `gc` sees anything. Asserting the pass-through
  // pins that the browser is not quietly acting as a second, weaker gate.
  it('passes a hostile name through for the guard to refuse', () => {
    expect(resolveTerminalSession('?session=--writable')).toBe('--writable');
    expect(resolveTerminalSession('?session=..%2F..%2Fetc')).toBe('../../etc');
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
