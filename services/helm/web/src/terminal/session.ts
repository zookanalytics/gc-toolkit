// The attach/detach lifecycle of one embedded terminal.
//
// DOM-free and injectable (the socket arrives through a factory), because the
// behaviour that matters here — what does and does not go over the wire when a
// tile closes — is exactly the behaviour worth testing without a browser.

import {
  TTYD_SUBPROTOCOL,
  decodeServerMessage,
  encodeHandshake,
  encodeInput,
  encodeResize,
  type TerminalSize,
} from './protocol';

/** Lifecycle of a session, surfaced so the tile can render honestly. */
export type SessionState = 'idle' | 'connecting' | 'attached' | 'detached' | 'failed';

/** Callbacks a host (the React tile) supplies. All are optional. */
export interface SessionHandlers {
  onOutput?(data: string): void;
  onTitle?(title: string): void;
  onStateChange?(state: SessionState, detail?: string): void;
}

/** Builds the socket. Injected so tests can drive the protocol without a browser. */
export type SocketFactory = (url: string, protocols: string) => WebSocket;

const NORMAL_CLOSURE = 1000;
/** WebSocket.OPEN, as a literal — this module never touches a browser global. */
const SOCKET_OPEN = 1;

/**
 * One terminal attached to ttyd.
 *
 * ### Close means detach, not kill
 *
 * This is the destructive failure mode for an embedded terminal, so it is
 * worth being precise about why closing a tile is safe.
 *
 * ttyd spawns one `gc session attach <session>` process per connected client,
 * and that process is a *tmux client* of a session that is already running and
 * that outlives every client. When this socket closes, ttyd hangs up that one
 * client process; tmux detaches it and the session — and the agent working
 * inside it — carries on. Nothing about closing a socket reaches the session.
 *
 * What WOULD kill it is writing to the PTY on the way out: an `exit`, a
 * Ctrl-D, a Ctrl-C, a `tmux kill-session`. Those are indistinguishable from
 * the operator typing them, and they would end a live agent's session for the
 * sake of a UI teardown.
 *
 * The invariant that keeps the two apart is therefore narrow and absolute:
 *
 *     TEARDOWN NEVER WRITES TO THE SOCKET.
 *
 * {@link detach} closes and nothing else, and {@link send} refuses to write
 * once detaching has begun, so a keystroke racing the teardown cannot slip
 * through either. `session.test.ts` asserts both.
 *
 * ### No automatic reconnect
 *
 * A dropped socket settles into `detached` and waits for the operator. An
 * embedded tile that reconnects on its own would re-run `gc session attach`
 * unattended — which resumes a suspended session — so reattaching stays an
 * explicit act.
 */
export class TtydSession {
  private socket: WebSocket | null = null;
  private state: SessionState = 'idle';
  private size: TerminalSize;
  private closing = false;

  constructor(
    private readonly url: string,
    private readonly token: string,
    initialSize: TerminalSize,
    private readonly handlers: SessionHandlers = {},
    private readonly createSocket: SocketFactory = (url, protocols) => new WebSocket(url, protocols),
  ) {
    this.size = initialSize;
  }

  /** Current lifecycle state. */
  get currentState(): SessionState {
    return this.state;
  }

  /** Opens the socket and performs ttyd's handshake. Idempotent while live. */
  attach(): void {
    if (this.state === 'connecting' || this.state === 'attached') return;
    this.closing = false;
    this.setState('connecting');

    let socket: WebSocket;
    try {
      socket = this.createSocket(this.url, TTYD_SUBPROTOCOL);
    } catch (err) {
      this.setState('failed', err instanceof Error ? err.message : String(err));
      return;
    }
    socket.binaryType = 'arraybuffer';
    this.socket = socket;

    socket.addEventListener('open', this.handleOpen);
    socket.addEventListener('message', this.handleMessage);
    socket.addEventListener('close', this.handleClose);
    socket.addEventListener('error', this.handleError);
  }

  /**
   * Detaches: closes the socket cleanly and writes nothing.
   *
   * See the class comment — this is the whole safety property. Any write added
   * here would reach a live agent's terminal.
   */
  detach(): void {
    const socket = this.socket;
    this.closing = true;
    if (!socket) {
      if (this.state !== 'idle') this.setState('detached');
      return;
    }
    this.releaseSocket(socket);
    try {
      socket.close(NORMAL_CLOSURE);
    } catch {
      // Closing an already-closed socket is not an error worth surfacing.
    }
    this.socket = null;
    this.setState('detached');
  }

  /** Sends keystrokes. Refused unless the session is live and not tearing down. */
  send(data: string): void {
    if (this.closing || this.state !== 'attached') return;
    const socket = this.socket;
    if (!socket || socket.readyState !== SOCKET_OPEN) return;
    socket.send(encodeInput(data));
  }

  /**
   * Reports a new terminal size, clamped by {@link protocol.MIN_SIZE} so a
   * small tile cannot reflow a session the operator is also attached to.
   */
  resize(size: TerminalSize): void {
    this.size = size;
    if (this.closing || this.state !== 'attached') return;
    const socket = this.socket;
    if (!socket || socket.readyState !== SOCKET_OPEN) return;
    socket.send(encodeResize(size));
  }

  private readonly handleOpen = (): void => {
    const socket = this.socket;
    if (!socket || this.closing) return;
    socket.send(encodeHandshake(this.token, this.size));
    this.setState('attached');
  };

  private readonly handleMessage = (event: MessageEvent): void => {
    if (this.closing) return;
    const data = event.data;
    if (!(data instanceof ArrayBuffer)) return;
    const message = decodeServerMessage(data);
    if (!message) return;
    switch (message.type) {
      case 'output':
        this.handlers.onOutput?.(message.data);
        break;
      case 'title':
        this.handlers.onTitle?.(message.title);
        break;
      default:
        // 'preferences' carries ttyd's own font/theme defaults, which the tile
        // deliberately does not adopt — it inherits the board's styling.
        break;
    }
  };

  private readonly handleClose = (event: CloseEvent): void => {
    if (this.socket) this.releaseSocket(this.socket);
    this.socket = null;
    if (this.closing) return;
    // The far side went away on its own — ttyd stopped, or the session's
    // attach process exited. Nothing was killed by us; report and rest.
    this.setState('detached', event.reason || `socket closed (code ${event.code})`);
  };

  private readonly handleError = (): void => {
    if (this.closing) return;
    this.setState('failed', 'terminal socket error');
  };

  private releaseSocket(socket: WebSocket): void {
    socket.removeEventListener('open', this.handleOpen);
    socket.removeEventListener('message', this.handleMessage);
    socket.removeEventListener('close', this.handleClose);
    socket.removeEventListener('error', this.handleError);
  }

  private setState(state: SessionState, detail?: string): void {
    if (this.state === state && detail === undefined) return;
    this.state = state;
    this.handlers.onStateChange?.(state, detail);
  }
}
