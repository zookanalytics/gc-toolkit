import { describe, expect, it } from 'vitest';

import { TtydSession, type SessionState } from './session';
import { ClientCommand, MIN_SIZE, TTYD_SUBPROTOCOL } from './protocol';

const decoder = new TextDecoder();

/** A WebSocket stand-in that records everything written to it. */
class FakeSocket {
  binaryType = 'blob';
  readyState = 0;
  readonly sent: Uint8Array[] = [];
  readonly closeCodes: (number | undefined)[] = [];
  private readonly listeners = new Map<string, Set<(event: unknown) => void>>();

  constructor(
    readonly url: string,
    readonly protocols: string,
  ) {}

  send(data: Uint8Array): void {
    this.sent.push(new Uint8Array(data));
  }

  close(code?: number): void {
    this.closeCodes.push(code);
    this.readyState = 3;
  }

  addEventListener(type: string, listener: (event: unknown) => void): void {
    let set = this.listeners.get(type);
    if (!set) {
      set = new Set();
      this.listeners.set(type, set);
    }
    set.add(listener);
  }

  removeEventListener(type: string, listener: (event: unknown) => void): void {
    this.listeners.get(type)?.delete(listener);
  }

  /** Count of live listeners, to prove teardown unsubscribes. */
  listenerCount(): number {
    let total = 0;
    for (const set of this.listeners.values()) total += set.size;
    return total;
  }

  emit(type: string, event: unknown): void {
    for (const listener of [...(this.listeners.get(type) ?? [])]) listener(event);
  }

  /** Drives the open handshake the way a real socket would. */
  connect(): void {
    this.readyState = 1;
    this.emit('open', {});
  }
}

interface Harness {
  session: TtydSession;
  sockets: FakeSocket[];
  states: { state: SessionState; detail?: string }[];
  output: string[];
  titles: string[];
}

function harness(size = { columns: 100, rows: 30 }): Harness {
  const sockets: FakeSocket[] = [];
  const states: { state: SessionState; detail?: string }[] = [];
  const output: string[] = [];
  const titles: string[] = [];
  const session = new TtydSession(
    'wss://example.test/terminal/ws',
    'tok',
    size,
    {
      onOutput: (data) => output.push(data),
      onTitle: (title) => titles.push(title),
      onStateChange: (state, detail) => states.push({ state, detail }),
    },
    (url, protocols) => {
      const socket = new FakeSocket(url, protocols);
      sockets.push(socket);
      return socket as unknown as WebSocket;
    },
  );
  return { session, sockets, states, output, titles };
}

/** Server->client frame bytes, as ttyd would send them. */
function serverFrame(command: string, payload: string): ArrayBuffer {
  const body = new TextEncoder().encode(payload);
  const frame = new Uint8Array(body.length + 1);
  frame[0] = command.charCodeAt(0);
  frame.set(body, 1);
  return frame.buffer;
}

const commandOf = (frame: Uint8Array) => String.fromCharCode(frame[0]);
const bodyOf = (frame: Uint8Array) => decoder.decode(frame.subarray(1));
const isInput = (frame: Uint8Array) => commandOf(frame) === ClientCommand.INPUT;

describe('TtydSession handshake', () => {
  it('opens with ttyd subprotocol and binary frames', () => {
    const h = harness();
    h.session.attach();
    expect(h.sockets).toHaveLength(1);
    expect(h.sockets[0].url).toBe('wss://example.test/terminal/ws');
    expect(h.sockets[0].protocols).toBe(TTYD_SUBPROTOCOL);
    expect(h.sockets[0].binaryType).toBe('arraybuffer');
  });

  it('sends the auth/size frame first, then reports attached', () => {
    const h = harness({ columns: 100, rows: 30 });
    h.session.attach();
    h.sockets[0].connect();

    expect(h.sockets[0].sent).toHaveLength(1);
    expect(JSON.parse(decoder.decode(h.sockets[0].sent[0]))).toEqual({
      AuthToken: 'tok',
      columns: 100,
      rows: 30,
    });
    expect(h.session.currentState).toBe('attached');
  });

  it('never reports a size below the floor, so a small tile cannot reflow a shared session', () => {
    const h = harness({ columns: 20, rows: 5 });
    h.session.attach();
    h.sockets[0].connect();

    expect(JSON.parse(decoder.decode(h.sockets[0].sent[0]))).toEqual({
      AuthToken: 'tok',
      columns: MIN_SIZE.columns,
      rows: MIN_SIZE.rows,
    });
  });
});

describe('TtydSession traffic', () => {
  it('frames keystrokes as INPUT', () => {
    const h = harness();
    h.session.attach();
    h.sockets[0].connect();
    h.session.send('ls\r');

    const frame = h.sockets[0].sent[1];
    expect(commandOf(frame)).toBe(ClientCommand.INPUT);
    expect(bodyOf(frame)).toBe('ls\r');
  });

  it('frames resizes as RESIZE_TERMINAL', () => {
    const h = harness();
    h.session.attach();
    h.sockets[0].connect();
    h.session.resize({ columns: 120, rows: 40 });

    const frame = h.sockets[0].sent[1];
    expect(commandOf(frame)).toBe(ClientCommand.RESIZE_TERMINAL);
    expect(JSON.parse(bodyOf(frame))).toEqual({ columns: 120, rows: 40 });
  });

  it('routes server output and titles to the host', () => {
    const h = harness();
    h.session.attach();
    h.sockets[0].connect();
    h.sockets[0].emit('message', { data: serverFrame('0', 'hello\r\n') });
    h.sockets[0].emit('message', { data: serverFrame('1', 'mayor') });

    expect(h.output).toEqual(['hello\r\n']);
    expect(h.titles).toEqual(['mayor']);
  });

  it('writes nothing before the socket is open', () => {
    const h = harness();
    h.session.attach();
    h.session.send('rm -rf /\r');
    h.session.resize({ columns: 90, rows: 30 });
    expect(h.sockets[0].sent).toEqual([]);
  });
});

// The reason this file exists. Closing a tile must detach the viewer, never
// end the session on the other side — the session belongs to a working agent.
describe('close means detach, not kill', () => {
  it('detach writes NOTHING to the socket and closes cleanly', () => {
    const h = harness();
    h.session.attach();
    h.sockets[0].connect();
    h.session.send('echo hi\r');

    const beforeDetach = h.sockets[0].sent.length;
    h.session.detach();

    // The only acceptable teardown traffic is none at all: no exit, no ^C,
    // no ^D, no kill-session — anything written here reaches a live PTY.
    expect(h.sockets[0].sent).toHaveLength(beforeDetach);
    expect(h.sockets[0].closeCodes).toEqual([1000]);
    expect(h.session.currentState).toBe('detached');
  });

  it('sends no INPUT frame across a full attach/use/detach cycle beyond typed keys', () => {
    const h = harness();
    h.session.attach();
    h.sockets[0].connect();
    h.session.resize({ columns: 90, rows: 30 });
    h.session.detach();

    const typed = h.sockets[0].sent.filter(isInput);
    expect(typed).toEqual([]);
  });

  it('refuses a keystroke that races the teardown', () => {
    const h = harness();
    h.session.attach();
    h.sockets[0].connect();
    h.session.detach();

    const after = h.sockets[0].sent.length;
    h.session.send('exit\r');
    h.session.resize({ columns: 200, rows: 60 });
    expect(h.sockets[0].sent).toHaveLength(after);
  });

  it('unsubscribes on detach so a late close cannot resurrect the session', () => {
    const h = harness();
    h.session.attach();
    h.sockets[0].connect();
    h.session.detach();
    expect(h.sockets[0].listenerCount()).toBe(0);

    h.sockets[0].emit('close', { code: 1006, reason: 'gone' });
    expect(h.sockets).toHaveLength(1);
    expect(h.session.currentState).toBe('detached');
  });

  it('detaching twice is harmless', () => {
    const h = harness();
    h.session.attach();
    h.sockets[0].connect();
    h.session.detach();
    h.session.detach();
    expect(h.sockets[0].closeCodes).toEqual([1000]);
  });
});

describe('TtydSession disconnection', () => {
  it('rests, rather than reconnecting, when the far side closes', () => {
    const h = harness();
    h.session.attach();
    h.sockets[0].connect();
    h.sockets[0].emit('close', { code: 1006, reason: '' });

    expect(h.session.currentState).toBe('detached');
    // Reattaching must stay an explicit act: it re-runs `gc session attach`.
    expect(h.sockets).toHaveLength(1);
  });

  it('reports a socket error as failed', () => {
    const h = harness();
    h.session.attach();
    h.sockets[0].emit('error', {});
    expect(h.session.currentState).toBe('failed');
  });

  it('can reattach after detaching', () => {
    const h = harness();
    h.session.attach();
    h.sockets[0].connect();
    h.session.detach();
    h.session.attach();
    h.sockets[1].connect();

    expect(h.sockets).toHaveLength(2);
    expect(h.session.currentState).toBe('attached');
  });
});
