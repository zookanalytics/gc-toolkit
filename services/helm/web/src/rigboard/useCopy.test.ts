import { act, cleanup, renderHook } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { COPIED_MS, useCopy } from './useCopy';

// The copy the board's bead ids and the side panel's command share. The
// clipboard here is a stub whose writes answer when a case says so, and the
// clock is vitest's, so each case reads what the page would show at each
// moment: before the browser answers, after, and once the moment has passed.

/** A write the stub clipboard took, waiting for the case to answer it. */
interface Write {
  text: string;
  take(): void;
  refuse(): void;
}

let writes: Write[];

beforeEach(() => {
  vi.useFakeTimers();
  writes = [];
  vi.stubGlobal('navigator', {
    ...navigator,
    clipboard: {
      writeText: (text: string) =>
        new Promise<void>((resolve, reject) => {
          writes.push({
            text,
            take: () => resolve(),
            refuse: () => reject(new DOMException('Write permission denied.', 'NotAllowedError')),
          });
        }),
    },
  });
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

/** Moves the clock on by ms, letting every answer due by then reach the hook. */
async function wait(ms: number) {
  await act(async () => {
    await vi.advanceTimersByTimeAsync(ms);
  });
}

function mount() {
  const hook = renderHook(() => useCopy());
  return {
    ...hook,
    copied: () => hook.result.current[0],
    copy: (text: string) => act(() => hook.result.current[1](text)),
  };
}

describe('useCopy', () => {
  it('shows a copy only once the clipboard has taken it, for COPIED_MS', async () => {
    const h = mount();
    h.copy('tk-wmwcdlc');
    expect(writes.map((w) => w.text)).toEqual(['tk-wmwcdlc']);
    await wait(0);
    expect(h.copied()).toBeNull();
    writes[0].take();
    await wait(0);
    expect(h.copied()).toBe('tk-wmwcdlc');
    await wait(COPIED_MS - 1);
    expect(h.copied()).toBe('tk-wmwcdlc');
    await wait(1);
    expect(h.copied()).toBeNull();
  });

  it('shows nothing when the browser refuses the write', async () => {
    const h = mount();
    h.copy('tk-wmwcdlc');
    writes[0].refuse();
    await wait(0);
    expect(h.copied()).toBeNull();
    expect(vi.getTimerCount()).toBe(0);
  });

  it('shows nothing on a page with no clipboard', async () => {
    vi.stubGlobal('navigator', { ...navigator, clipboard: undefined });
    const h = mount();
    h.copy('tk-wmwcdlc');
    await wait(0);
    expect(h.copied()).toBeNull();
    expect(vi.getTimerCount()).toBe(0);
  });

  it('clears an earlier success at a later copy, and gives the later one its whole moment', async () => {
    const h = mount();
    h.copy('tk-first');
    writes[0].take();
    await wait(0);
    expect(h.copied()).toBe('tk-first');
    await wait(COPIED_MS - 200);
    h.copy('tk-second');
    // The earlier success goes at the click, before the browser answers.
    expect(h.copied()).toBeNull();
    writes[1].take();
    await wait(0);
    expect(h.copied()).toBe('tk-second');
    expect(vi.getTimerCount()).toBe(1);
    // Past the moment the earlier copy's timer would have ended it.
    await wait(200);
    expect(h.copied()).toBe('tk-second');
    await wait(COPIED_MS - 200);
    expect(h.copied()).toBeNull();
  });

  it('shows nothing for a write that answers after a later copy started', async () => {
    const h = mount();
    h.copy('tk-first');
    h.copy('tk-second');
    writes[0].take();
    await wait(0);
    expect(h.copied()).toBeNull();
    writes[1].take();
    await wait(0);
    expect(h.copied()).toBe('tk-second');
  });

  it('a later refusal leaves no earlier success showing', async () => {
    const h = mount();
    h.copy('tk-first');
    writes[0].take();
    await wait(0);
    h.copy('tk-second');
    writes[1].refuse();
    await wait(0);
    expect(h.copied()).toBeNull();
    expect(vi.getTimerCount()).toBe(0);
  });

  it('leaves no timer behind when it unmounts, and starts none for a write still in flight', async () => {
    const h = mount();
    h.copy('tk-first');
    writes[0].take();
    await wait(0);
    expect(vi.getTimerCount()).toBe(1);
    h.unmount();
    expect(vi.getTimerCount()).toBe(0);

    const late = mount();
    late.copy('tk-second');
    late.unmount();
    writes[1].take();
    await wait(0);
    expect(vi.getTimerCount()).toBe(0);
  });
});
