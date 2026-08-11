// The drill plane's typed supervisor client.
//
// Every request/response type here comes from gen/supervisor.d.ts, which is
// generated from the supervisor's own OpenAPI document (see
// scripts/gen-supervisor-types.mjs). Nothing in this file describes a wire
// shape by hand — that is the point. The board contract needs a hand-written
// mirror because the /svc/ surface is absent from the spec (U7); this plane
// does not, and inventing one here would create a second contract to drift.
//
// openapi-fetch is a ~2KB wrapper over fetch that types `path`/`query` params
// and the response against `paths`. A path this app calls that is missing from
// the generated types fails to compile, which is what keeps the pruned type
// surface honest with the code.

import createClient from 'openapi-fetch';
import type { components, paths } from './gen/supervisor';
import type { SupervisorOrigin } from './origin';

export type Bead = components['schemas']['Bead'];
export type Session = components['schemas']['SessionResponse'];
export type PendingEntry = components['schemas']['CityPendingEntry'];
export type MailCount = components['schemas']['MailCountOutputBody'];
/**
 * One city event. The supervisor spec models this as a discriminated union over
 * `type`, so narrowing on `event.type` narrows `event.payload` with it — the
 * generated types carry every payload shape the city can emit.
 */
export type CityEvent = components['schemas']['TypedEventStreamEnvelope'];
type ErrorModel = components['schemas']['ErrorModel'];

/** A non-2xx answer from the supervisor, carrying its RFC7807 detail. */
export class SupervisorError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = 'SupervisorError';
  }
}

function describe(status: number, error: unknown, fallback: string): SupervisorError {
  const model = error as ErrorModel | undefined;
  const detail = model?.detail ?? model?.title;
  return new SupervisorError(status, detail !== undefined && detail !== '' ? detail : fallback);
}

/**
 * A list read, together with what the supervisor said about its completeness.
 *
 * The board aggregates across every rig in the city and legitimately answers
 * with part of the truth: HTTP 200, `partial: true`, and one `partial_errors`
 * entry per store that did not report. Unwrapping straight to `items` throws
 * that away and makes an incomplete answer indistinguishable from an empty
 * one — which is how a panel comes to tell the operator "no agent is working
 * this anchor" when the session store simply did not answer. Partial data is
 * first-class on this surface, so every list read carries its envelope and
 * callers can tell *none* from *not known*.
 */
export interface ListResult<T> {
  items: T[];
  /** True when the answer is known to be incomplete. */
  partial: boolean;
  /** Per-store reasons the answer is incomplete; empty when it is not. */
  partialErrors: string[];
  /**
   * How many items match the query, as counted by the supervisor. A count
   * rendered from `items.length` is wrong whenever the response was truncated;
   * this is the number to display.
   */
  total?: number;
  /** Set when the response was truncated — pass back to fetch the next page. */
  nextCursor?: string;
}

/** The generated list envelopes, structurally: every one of them has this shape. */
interface ListEnvelope<T> {
  items?: T[] | null;
  partial?: boolean;
  partial_errors?: string[] | null;
  total?: number;
  next_cursor?: string;
}

function listResult<T>(body: ListEnvelope<T>): ListResult<T> {
  return {
    items: body.items ?? [],
    partial: body.partial === true,
    partialErrors: body.partial_errors ?? [],
    total: body.total,
    nextCursor: body.next_cursor,
  };
}

/**
 * A list read that did not happen at all, expressed in the same shape.
 *
 * Callers that degrade rather than fail outright — a broken session lookup must
 * not hide the bead the operator opened — still must not degrade into a
 * confident empty list. A read that never landed is the maximally incomplete
 * one, so it is exactly `partial` with the failure as its reason.
 */
export function unreadList<T>(reason: unknown): ListResult<T> {
  return {
    items: [],
    partial: true,
    partialErrors: [reason instanceof Error ? reason.message : String(reason)],
  };
}

export interface DrillReads {
  bead(id: string, signal?: AbortSignal): Promise<Bead>;
  session(id: string, signal?: AbortSignal): Promise<Session>;
  sessions(signal?: AbortSignal): Promise<ListResult<Session>>;
  pending(signal?: AbortSignal): Promise<ListResult<PendingEntry>>;
  mailCount(signal?: AbortSignal): Promise<MailCount>;
  waitingBeads(signal?: AbortSignal): Promise<ListResult<Bead>>;
  /** Most recent events first, newest `limit` entries. */
  recentEvents(limit: number, signal?: AbortSignal): Promise<ListResult<CityEvent>>;
}

/**
 * Build the read surface for one city.
 *
 * `baseUrl` is a path prefix, normally '', NOT an absolute origin: requests
 * resolve against the document so they inherit its origin — the tailscale host
 * in normal use. origin.ts explains why that is the only thing that works here.
 */
export function createDrillReads(origin: SupervisorOrigin): DrillReads {
  const client = createClient<paths>({ baseUrl: origin.baseUrl });
  const cityName = origin.city;

  return {
    async bead(id, signal) {
      const { data, error, response } = await client.GET('/v0/city/{cityName}/bead/{id}', {
        params: { path: { cityName, id } },
        signal,
      });
      if (data === undefined) throw describe(response.status, error, `bead ${id} unavailable`);
      return data;
    },

    async session(id, signal) {
      const { data, error, response } = await client.GET('/v0/city/{cityName}/session/{id}', {
        // peek returns the tail of the session's own output — the "read the
        // latest" half of the drill, without attaching a terminal (that is U9).
        params: { path: { cityName, id }, query: { peek: true, peek_lines: 40 } },
        signal,
      });
      if (data === undefined) throw describe(response.status, error, `session ${id} unavailable`);
      return data;
    },

    async sessions(signal) {
      const { data, error, response } = await client.GET('/v0/city/{cityName}/sessions', {
        params: { path: { cityName } },
        signal,
      });
      if (data === undefined) throw describe(response.status, error, 'sessions unavailable');
      return listResult(data);
    },

    async pending(signal) {
      const { data, error, response } = await client.GET('/v0/city/{cityName}/pending', {
        params: { path: { cityName } },
        signal,
      });
      if (data === undefined) throw describe(response.status, error, 'pending unavailable');
      return listResult(data);
    },

    async mailCount(signal) {
      const { data, error, response } = await client.GET('/v0/city/{cityName}/mail/count', {
        params: { path: { cityName } },
        signal,
      });
      if (data === undefined) throw describe(response.status, error, 'mail count unavailable');
      return data;
    },

    async waitingBeads(signal) {
      const { data, error, response } = await client.GET('/v0/city/{cityName}/beads', {
        params: { path: { cityName }, query: { label: 'gc:wait' } },
        signal,
      });
      if (data === undefined) throw describe(response.status, error, 'waiting beads unavailable');
      return listResult(data);
    },

    async recentEvents(limit, signal) {
      const { data, error, response } = await client.GET('/v0/city/{cityName}/events', {
        params: { path: { cityName }, query: { limit } },
        signal,
      });
      if (data === undefined) throw describe(response.status, error, 'events unavailable');
      return listResult(data);
    },
  };
}
