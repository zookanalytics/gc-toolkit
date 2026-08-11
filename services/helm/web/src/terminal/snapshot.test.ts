import { describe, expect, it } from 'vitest';

import { captureSnapshot, type TerminalLike } from './snapshot';

/** A buffer shaped like xterm's: scrollback below baseY, viewport from it. */
function terminal(lines: string[], rows: number, baseY = 0): TerminalLike {
  return {
    rows,
    buffer: {
      active: {
        baseY,
        getLine: (y: number) =>
          y >= 0 && y < lines.length ? { translateToString: () => lines[y] } : undefined,
      },
    },
  };
}

describe('captureSnapshot', () => {
  it('reads the viewport, not the scrollback above it', () => {
    const lines = ['scrolled off', 'also gone', 'visible one', 'visible two'];
    expect(captureSnapshot(terminal(lines, 2, 2))).toBe('visible one\nvisible two');
  });

  it('drops trailing blank lines so an idle screen rests small', () => {
    const lines = ['a prompt $', '', '   ', ''];
    expect(captureSnapshot(terminal(lines, 4))).toBe('a prompt $');
  });

  it('keeps blank lines that sit between content', () => {
    const lines = ['top', '', 'bottom', ''];
    expect(captureSnapshot(terminal(lines, 4))).toBe('top\n\nbottom');
  });

  it('is empty for a blank screen', () => {
    expect(captureSnapshot(terminal(['', '', ''], 3))).toBe('');
  });

  it('renders missing lines as blanks rather than throwing', () => {
    expect(captureSnapshot(terminal(['only'], 3))).toBe('only');
  });

  it('caps how much peek a tile keeps', () => {
    const lines = Array.from({ length: 500 }, (_, i) => `line ${i}`);
    const snapshot = captureSnapshot(terminal(lines, 500), 10);
    expect(snapshot.split('\n')).toHaveLength(10);
    // The cap keeps the BOTTOM of the screen — the newest output.
    expect(snapshot.split('\n')[9]).toBe('line 499');
  });
});
