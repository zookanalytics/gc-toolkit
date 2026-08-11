// The resting half of a terminal tile.
//
// A tile is a live terminal only while it has focus; at rest it shows a peek —
// a still of what the terminal last looked like. Taking that still at detach
// time is what lets the socket close: the tile keeps something to show without
// keeping a session attached to show it.
//
// The terminal is described structurally rather than imported from xterm, so
// this is testable without a DOM and does not pin the tile to one terminal
// implementation.

/** The part of an xterm buffer line this module reads. */
export interface BufferLineLike {
  translateToString(trimRight?: boolean): string;
}

/** The part of an xterm buffer this module reads. */
export interface BufferLike {
  readonly baseY: number;
  getLine(y: number): BufferLineLike | undefined;
}

/** The part of an xterm terminal this module reads. */
export interface TerminalLike {
  readonly rows: number;
  readonly buffer: { readonly active: BufferLike };
}

/** How many lines of peek a resting tile keeps, at most. */
export const MAX_SNAPSHOT_LINES = 200;

/**
 * Captures the visible screen as plain text.
 *
 * Reads the viewport — `baseY` is the top of what is on screen — rather than
 * the whole scrollback, so the peek shows what the operator would have seen at
 * the moment of detaching. Trailing blank lines are dropped so a mostly-empty
 * screen rests as a few lines instead of a screenful of padding.
 */
export function captureSnapshot(terminal: TerminalLike, maxLines = MAX_SNAPSHOT_LINES): string {
  const buffer = terminal.buffer.active;
  const rows = Math.min(Math.max(terminal.rows, 0), maxLines);
  const start = buffer.baseY + Math.max(terminal.rows - rows, 0);

  const lines: string[] = [];
  for (let i = 0; i < rows; i += 1) {
    const line = buffer.getLine(start + i);
    lines.push(line ? line.translateToString(true) : '');
  }
  while (lines.length > 0 && lines[lines.length - 1].trim() === '') {
    lines.pop();
  }
  return lines.join('\n');
}
