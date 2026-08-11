import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { CityEvent } from './client';
import {
  createEventHub,
  eventConcernsBead,
  eventConcernsSession,
  subscribeCityEvents,
  type StreamState,
} from './events';

const ORIGIN = { baseUrl: 'https://gc-host.tail1234.ts.net', city: 'loomington' };

// A controllable stand-in for the browser's EventSource. Frames are pushed by
// the test rather than by a server, so the assertions are about how this module
// reacts to the wire protocol, not about network timing.
class FakeEventSource {
  static instances: FakeEventSource[] = [];

  onopen: ((event: Event) => void) | null = null;
  onmessage: ((event: MessageEvent<string>) => void) | null = null;
  onerror: ((event: Event) => void) | null = null;
  closed = false;
  readonly listeners = new Map<string, EventListener[]>();

  constructor(readonly url: string) {
    FakeEventSource.instances.push(this);
  }

  addEventListener(type: string, listener: EventListener) {
    const existing = this.listeners.get(type) ?? [];
    existing.push(listener);
    this.listeners.set(type, existing);
  }

  close() {
    this.closed = true;
  }

  /** Deliver a frame the way the supervisor sends it: `event: event`. */
  emitNamed(data: string) {
    for (const listener of this.listeners.get('event') ?? []) {
      listener(new MessageEvent('event', { data }) as Event);
    }
  }

  /** Deliver an unnamed frame, which reaches .onmessage instead. */
  emitUnnamed(data: string) {
    this.onmessage?.(new MessageEvent('message', { data }));
  }

  fail() {
    this.onerror?.(new Event('error'));
  }
}

function frame(overrides: Partial<CityEvent> = {}): string {
  return JSON.stringify({
    seq: 1,
    type: 'bead.updated',
    ts: '2026-08-11T15:00:00Z',
    actor: 'polecat',
    subject: 'tk-eemvf.3',
    payload: {},
    ...overrides,
  });
}

beforeEach(() => {
  FakeEventSource.instances = [];
  vi.useFakeTimers();
});

afterEach(() => {
  vi.useRealTimers();
});

describe('subscribeCityEvents', () => {
  it('connects to the city stream on the document origin', () => {
    const stop = subscribeCityEvents(ORIGIN, {
      onEvent: () => {},
      eventSourceCtor: FakeEventSource as unknown as typeof EventSource,
    });
    expect(FakeEventSource.instances[0].url).toBe(
      'https://gc-host.tail1234.ts.net/v0/city/loomington/events/stream',
    );
    stop();
  });

  // The supervisor names its frames `event`, and a named frame never reaches
  // .onmessage. A handler bound only to .onmessage receives nothing at all —
  // silently, forever — so this is the single most load-bearing assertion here.
  it('receives frames named "event"', () => {
    const seen: CityEvent[] = [];
    const stop = subscribeCityEvents(ORIGIN, {
      onEvent: (event) => seen.push(event),
      eventSourceCtor: FakeEventSource as unknown as typeof EventSource,
    });
    FakeEventSource.instances[0].emitNamed(frame({ seq: 7 }));
    expect(seen.map((event) => event.seq)).toEqual([7]);
    stop();
  });

  it('also receives unnamed frames', () => {
    const seen: CityEvent[] = [];
    const stop = subscribeCityEvents(ORIGIN, {
      onEvent: (event) => seen.push(event),
      eventSourceCtor: FakeEventSource as unknown as typeof EventSource,
    });
    FakeEventSource.instances[0].emitUnnamed(frame({ seq: 8 }));
    expect(seen.map((event) => event.seq)).toEqual([8]);
    stop();
  });

  it('degrades instead of throwing on an unreadable frame', () => {
    const states: StreamState[] = [];
    const seen: CityEvent[] = [];
    const stop = subscribeCityEvents(ORIGIN, {
      onEvent: (event) => seen.push(event),
      onState: (state) => states.push(state),
      eventSourceCtor: FakeEventSource as unknown as typeof EventSource,
    });
    const source = FakeEventSource.instances[0];
    expect(() => source.emitNamed('{not json')).not.toThrow();
    expect(() => source.emitNamed(JSON.stringify({ seq: 1 }))).not.toThrow(); // no `type`
    expect(seen).toEqual([]);
    expect(states).toContain('degraded');

    // ...and a good frame afterwards still lands.
    source.emitNamed(frame({ seq: 9 }));
    expect(seen.map((event) => event.seq)).toEqual([9]);
    stop();
  });

  it('reconnects with capped exponential backoff', () => {
    const stop = subscribeCityEvents(ORIGIN, {
      onEvent: () => {},
      retryBaseMs: 1_000,
      retryMaxMs: 4_000,
      eventSourceCtor: FakeEventSource as unknown as typeof EventSource,
    });

    FakeEventSource.instances[0].fail();
    expect(FakeEventSource.instances).toHaveLength(1);
    vi.advanceTimersByTime(1_000);
    expect(FakeEventSource.instances).toHaveLength(2);

    FakeEventSource.instances[1].fail();
    vi.advanceTimersByTime(1_999);
    expect(FakeEventSource.instances).toHaveLength(2); // not yet — the window doubled
    vi.advanceTimersByTime(1);
    expect(FakeEventSource.instances).toHaveLength(3);

    // Cap holds: 1s, 2s, 4s, then 4s forever rather than growing unbounded.
    FakeEventSource.instances[2].fail();
    vi.advanceTimersByTime(4_000);
    expect(FakeEventSource.instances).toHaveLength(4);
    FakeEventSource.instances[3].fail();
    vi.advanceTimersByTime(4_000);
    expect(FakeEventSource.instances).toHaveLength(5);
    stop();
  });

  // The gap bug this pins: a replacement EventSource is a NEW object, and the
  // browser resends Last-Event-ID only on its own reconnect of the SAME one. A
  // replacement built from the bare stream URL therefore starts at the current
  // city head by the supervisor's documented default, and every event emitted
  // while nothing was connected is dropped — silently, while the indicator
  // returns to "live". The cursor has to be ours, and explicit.
  it('resumes the replacement stream from the last delivered event', () => {
    const seen: CityEvent[] = [];
    const stop = subscribeCityEvents(ORIGIN, {
      onEvent: (event) => seen.push(event),
      retryBaseMs: 1_000,
      eventSourceCtor: FakeEventSource as unknown as typeof EventSource,
    });

    // The first connection carries no cursor: the board opens on the live
    // present, not on a replay of the city's backlog.
    expect(FakeEventSource.instances[0].url).toBe(
      'https://gc-host.tail1234.ts.net/v0/city/loomington/events/stream',
    );

    FakeEventSource.instances[0].emitNamed(frame({ seq: 41 }));
    FakeEventSource.instances[0].fail();
    vi.advanceTimersByTime(1_000);

    expect(FakeEventSource.instances[1].url).toBe(
      'https://gc-host.tail1234.ts.net/v0/city/loomington/events/stream?after_seq=41',
    );

    // ...and what the supervisor replays from that cursor — the event emitted
    // while nothing was connected — reaches the consumer rather than vanishing.
    FakeEventSource.instances[1].emitNamed(frame({ seq: 42 }));
    expect(seen.map((event) => event.seq)).toEqual([41, 42]);
    stop();
  });

  it('carries the cursor forward across repeated drops', () => {
    const stop = subscribeCityEvents(ORIGIN, {
      onEvent: () => {},
      retryBaseMs: 1_000,
      retryMaxMs: 1_000,
      eventSourceCtor: FakeEventSource as unknown as typeof EventSource,
    });

    FakeEventSource.instances[0].emitNamed(frame({ seq: 5 }));
    FakeEventSource.instances[0].fail();
    vi.advanceTimersByTime(1_000);
    expect(FakeEventSource.instances[1].url).toContain('after_seq=5');

    // A drop that delivered nothing new must not lose the cursor it already had.
    FakeEventSource.instances[1].fail();
    vi.advanceTimersByTime(1_000);
    expect(FakeEventSource.instances[2].url).toContain('after_seq=5');

    FakeEventSource.instances[2].emitNamed(frame({ seq: 9 }));
    FakeEventSource.instances[2].fail();
    vi.advanceTimersByTime(1_000);
    expect(FakeEventSource.instances[3].url).toContain('after_seq=9');
    stop();
  });

  // A supervisor restart can replay frames already delivered. Resuming from the
  // most recent one would walk the cursor backwards and ask for that same
  // replay again on every reconnect after it; the highest seq never does.
  it('does not walk the cursor backwards when the stream replays', () => {
    const stop = subscribeCityEvents(ORIGIN, {
      onEvent: () => {},
      retryBaseMs: 1_000,
      eventSourceCtor: FakeEventSource as unknown as typeof EventSource,
    });

    FakeEventSource.instances[0].emitNamed(frame({ seq: 41 }));
    FakeEventSource.instances[0].emitNamed(frame({ seq: 30 })); // replayed
    FakeEventSource.instances[0].fail();
    vi.advanceTimersByTime(1_000);

    expect(FakeEventSource.instances[1].url).toContain('after_seq=41');
    stop();
  });

  // Nothing delivered means no cursor exists, and the head is the only honest
  // place to restart from. Consumers cover this gap by refetching on the way
  // back to open — see useDrill / useCitySignals.
  it('reconnects without a cursor when it never delivered an event', () => {
    const stop = subscribeCityEvents(ORIGIN, {
      onEvent: () => {},
      retryBaseMs: 1_000,
      eventSourceCtor: FakeEventSource as unknown as typeof EventSource,
    });

    FakeEventSource.instances[0].fail();
    vi.advanceTimersByTime(1_000);
    expect(FakeEventSource.instances[1].url).toBe(
      'https://gc-host.tail1234.ts.net/v0/city/loomington/events/stream',
    );
    stop();
  });

  it('resets the backoff once a connection opens', () => {
    const stop = subscribeCityEvents(ORIGIN, {
      onEvent: () => {},
      retryBaseMs: 1_000,
      retryMaxMs: 30_000,
      eventSourceCtor: FakeEventSource as unknown as typeof EventSource,
    });
    FakeEventSource.instances[0].fail();
    vi.advanceTimersByTime(1_000);
    const second = FakeEventSource.instances[1];
    second.onopen?.(new Event('open'));
    second.fail();
    // Back to the base delay, not the doubled one.
    vi.advanceTimersByTime(1_000);
    expect(FakeEventSource.instances).toHaveLength(3);
    stop();
  });

  it('stops delivering and reconnecting after unsubscribe', () => {
    const seen: CityEvent[] = [];
    const stop = subscribeCityEvents(ORIGIN, {
      onEvent: (event) => seen.push(event),
      retryBaseMs: 1_000,
      eventSourceCtor: FakeEventSource as unknown as typeof EventSource,
    });
    const source = FakeEventSource.instances[0];
    stop();
    expect(source.closed).toBe(true);
    source.emitNamed(frame({ seq: 11 }));
    expect(seen).toEqual([]);

    source.fail();
    vi.advanceTimersByTime(60_000);
    expect(FakeEventSource.instances).toHaveLength(1);
    stop(); // idempotent
  });

  it('does not fail when the host has no EventSource', () => {
    const states: StreamState[] = [];
    const stop = subscribeCityEvents(ORIGIN, {
      onEvent: () => {},
      onState: (state) => states.push(state),
      eventSourceCtor: undefined,
    });
    expect(states).toEqual(['closed']);
    expect(() => stop()).not.toThrow();
  });
});

describe('createEventHub', () => {
  it('opens one connection for many subscribers and closes it with the last', () => {
    const hub = createEventHub(ORIGIN, {
      eventSourceCtor: FakeEventSource as unknown as typeof EventSource,
    });
    const a: number[] = [];
    const b: number[] = [];

    const stopA = hub.subscribe((event) => a.push(event.seq));
    const stopB = hub.subscribe((event) => b.push(event.seq));
    expect(FakeEventSource.instances).toHaveLength(1);

    FakeEventSource.instances[0].emitNamed(frame({ seq: 3 }));
    expect(a).toEqual([3]);
    expect(b).toEqual([3]);

    stopA();
    expect(FakeEventSource.instances[0].closed).toBe(false); // b still listening
    FakeEventSource.instances[0].emitNamed(frame({ seq: 4 }));
    expect(a).toEqual([3]);
    expect(b).toEqual([3, 4]);

    stopB();
    expect(FakeEventSource.instances[0].closed).toBe(true);
  });

  it('reopens after every subscriber has left and one returns', () => {
    const hub = createEventHub(ORIGIN, {
      eventSourceCtor: FakeEventSource as unknown as typeof EventSource,
    });
    hub.subscribe(() => {})();
    expect(FakeEventSource.instances).toHaveLength(1);
    const stop = hub.subscribe(() => {});
    expect(FakeEventSource.instances).toHaveLength(2);
    stop();
  });

  it('hands a new subscriber the current state immediately', () => {
    const hub = createEventHub(ORIGIN, {
      eventSourceCtor: FakeEventSource as unknown as typeof EventSource,
    });
    const first = hub.subscribe(() => {});
    FakeEventSource.instances[0].onopen?.(new Event('open'));

    const states: StreamState[] = [];
    const second = hub.subscribe(
      () => {},
      (state) => states.push(state),
    );
    expect(states[0]).toBe('open');
    first();
    second();
  });

  it('survives a subscriber unsubscribing while an event is dispatching', () => {
    const hub = createEventHub(ORIGIN, {
      eventSourceCtor: FakeEventSource as unknown as typeof EventSource,
    });
    const seen: number[] = [];
    const stopA = hub.subscribe(() => stopA());
    hub.subscribe((event) => seen.push(event.seq));
    expect(() => FakeEventSource.instances[0].emitNamed(frame({ seq: 5 }))).not.toThrow();
    expect(seen).toEqual([5]);
  });
});

describe('event matching', () => {
  it('matches a bead by envelope subject', () => {
    expect(eventConcernsBead(JSON.parse(frame()) as CityEvent, 'tk-eemvf.3')).toBe(true);
    expect(eventConcernsBead(JSON.parse(frame()) as CityEvent, 'tk-other')).toBe(false);
  });

  it('matches a bead named only in the payload', () => {
    const event = JSON.parse(
      frame({ subject: 'lx-8y6j', payload: { bead_id: 'tk-eemvf.3' } as never }),
    ) as CityEvent;
    expect(eventConcernsBead(event, 'tk-eemvf.3')).toBe(true);
  });

  it('matches a session event that lists the bead among its work', () => {
    const event = JSON.parse(
      frame({
        type: 'session.stranded' as never,
        subject: 'lx-8y6j',
        payload: { session_id: 'lx-8y6j', work_bead_ids: ['tk-eemvf.3'] } as never,
      }),
    ) as CityEvent;
    expect(eventConcernsBead(event, 'tk-eemvf.3')).toBe(true);
  });

  it('matches a session by id, subject, or payload', () => {
    const bySession = JSON.parse(frame({ session_id: 'lx-8y6j' })) as CityEvent;
    expect(eventConcernsSession(bySession, 'lx-8y6j')).toBe(true);

    const bySubject = JSON.parse(frame({ subject: 'lx-8y6j' })) as CityEvent;
    expect(eventConcernsSession(bySubject, 'lx-8y6j')).toBe(true);

    const byPayload = JSON.parse(
      frame({ subject: 'other', payload: { session_id: 'lx-8y6j' } as never }),
    ) as CityEvent;
    expect(eventConcernsSession(byPayload, 'lx-8y6j')).toBe(true);

    expect(eventConcernsSession(JSON.parse(frame()) as CityEvent, 'lx-8y6j')).toBe(false);
  });
});
