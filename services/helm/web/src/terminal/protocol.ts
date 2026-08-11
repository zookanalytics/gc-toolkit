// The ttyd wire protocol, as spoken by the ttyd this service attaches to.
//
// We do not run our own PTY. ttyd is already deployed in the city, wrapping
// `gc session attach` (see endpoint.ts for the deployment shape), and this
// module is the client half of its WebSocket protocol so an xterm.js terminal
// can be driven from inside the board.
//
// The constants below were read out of the running server's own bundled client
// (ttyd 1.7.7), not from documentation — ttyd's protocol is not versioned or
// specified anywhere else, so the shipped client is the only authority:
//
//   GET <base>/token            -> {"token": "<token>"}
//   WS  <base>/ws               subprotocol "tty"
//   first frame (client->server, binary):
//       JSON {"AuthToken": <token>, "columns": <cols>, "rows": <rows>}
//   every later frame: a one-byte command followed by its payload.
//
// Everything here is DOM-free and side-effect-free on purpose: it is the part
// of the terminal worth testing, and it stays testable without a browser.

/** Command bytes the client sends. First byte of a client->server frame. */
export const ClientCommand = {
  INPUT: '0',
  RESIZE_TERMINAL: '1',
  PAUSE: '2',
  RESUME: '3',
} as const;

/** Command bytes the server sends. First byte of a server->client frame. */
export const ServerCommand = {
  OUTPUT: '0',
  SET_WINDOW_TITLE: '1',
  SET_PREFERENCES: '2',
} as const;

/** The WebSocket subprotocol ttyd requires; it rejects a handshake without it. */
export const TTYD_SUBPROTOCOL = 'tty';

const encoder = new TextEncoder();
const decoder = new TextDecoder();

/** Terminal dimensions, in character cells. */
export interface TerminalSize {
  columns: number;
  rows: number;
}

/**
 * The lower bound this client will ever report to ttyd.
 *
 * ttyd sizes the PTY from whatever the client reports, and the PTY here is a
 * *shared, live* tmux session that a human may also be attached to. tmux sizes
 * a window to fit its clients, so a tile reporting its own small pixel size
 * would reflow the operator's real terminal to match. Clamping at the
 * conventional 80x24 floor means an embedded terminal can be smaller than its
 * content (it scrolls) but can never shrink somebody else's session below a
 * standard terminal.
 */
export const MIN_SIZE: TerminalSize = { columns: 80, rows: 24 };

/** Clamps a proposed size to {@link MIN_SIZE} and to whole cells. */
export function clampSize(size: TerminalSize): TerminalSize {
  const clamp = (value: number, min: number) =>
    Number.isFinite(value) ? Math.max(Math.floor(value), min) : min;
  return {
    columns: clamp(size.columns, MIN_SIZE.columns),
    rows: clamp(size.rows, MIN_SIZE.rows),
  };
}

/**
 * Builds the opening frame. ttyd expects this before anything else on the
 * socket and closes the connection if it does not arrive.
 */
export function encodeHandshake(token: string, size: TerminalSize): Uint8Array {
  const { columns, rows } = clampSize(size);
  return encoder.encode(JSON.stringify({ AuthToken: token, columns, rows }));
}

/**
 * Builds an INPUT frame: the command byte followed by the raw UTF-8 bytes of
 * the keystrokes. Built as bytes rather than a string so multi-byte input
 * (a pasted character outside ASCII) is not corrupted by re-encoding.
 */
export function encodeInput(data: string): Uint8Array {
  return prefix(ClientCommand.INPUT, encoder.encode(data));
}

/** Builds a RESIZE_TERMINAL frame. The size is clamped; see {@link MIN_SIZE}. */
export function encodeResize(size: TerminalSize): Uint8Array {
  const { columns, rows } = clampSize(size);
  return prefix(ClientCommand.RESIZE_TERMINAL, encoder.encode(JSON.stringify({ columns, rows })));
}

function prefix(command: string, payload: Uint8Array): Uint8Array {
  const frame = new Uint8Array(payload.length + 1);
  frame[0] = command.charCodeAt(0);
  frame.set(payload, 1);
  return frame;
}

/** A decoded server->client frame. */
export type ServerMessage =
  | { type: 'output'; data: string }
  | { type: 'title'; title: string }
  | { type: 'preferences'; preferences: unknown }
  | { type: 'unknown'; command: string };

/**
 * Decodes one server->client frame.
 *
 * Unknown commands decode to `{type:'unknown'}` rather than throwing: a future
 * ttyd may add commands, and an embedded terminal that tore itself down on the
 * first unrecognised byte would be more fragile than one that ignores it.
 */
export function decodeServerMessage(raw: ArrayBuffer | Uint8Array): ServerMessage | null {
  const bytes = raw instanceof Uint8Array ? raw : new Uint8Array(raw);
  if (bytes.length === 0) return null;
  const command = String.fromCharCode(bytes[0]);
  const payload = bytes.subarray(1);
  switch (command) {
    case ServerCommand.OUTPUT:
      return { type: 'output', data: decoder.decode(payload) };
    case ServerCommand.SET_WINDOW_TITLE:
      return { type: 'title', title: decoder.decode(payload) };
    case ServerCommand.SET_PREFERENCES: {
      const text = decoder.decode(payload);
      try {
        return { type: 'preferences', preferences: JSON.parse(text) as unknown };
      } catch {
        // A malformed preferences blob is cosmetic — it carries theme and font
        // hints. Report it as unknown rather than failing the session over it.
        return { type: 'unknown', command };
      }
    }
    default:
      return { type: 'unknown', command };
  }
}
