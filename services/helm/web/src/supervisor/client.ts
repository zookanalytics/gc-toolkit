// The page's typed supervisor client: the one read the page makes of the
// supervisor itself, a bead's whole text for its row's Details.
//
// Every request and response type here comes from gen/supervisor.d.ts, which is
// generated from the supervisor's own OpenAPI document (see
// scripts/gen-supervisor-types.mjs). Nothing in this file describes a wire
// shape by hand. A path the page calls that is missing from the generated types
// fails to compile, which keeps the pruned type surface honest with the code.
//
// openapi-fetch is a small wrapper over fetch that types `path` params and the
// response against `paths`.

import createClient from 'openapi-fetch';
import type { components, paths } from './gen/supervisor';
import type { SupervisorOrigin } from './origin';

export type Bead = components['schemas']['Bead'];
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
 * Read one bead through the supervisor's GET /v0/city/{cityName}/bead/{id},
 * which answers a bead of any rig in the city.
 *
 * `origin.baseUrl` is the document's own origin, never a fixed host:
 * origin.ts explains why that is the only thing that works here.
 */
export async function readBead(origin: SupervisorOrigin, id: string, signal?: AbortSignal): Promise<Bead> {
  const client = createClient<paths>({ baseUrl: origin.baseUrl });
  const { data, error, response } = await client.GET('/v0/city/{cityName}/bead/{id}', {
    params: { path: { cityName: origin.city, id } },
    signal,
  });
  if (data === undefined) throw describe(response.status, error, `bead ${id} unavailable`);
  return data;
}
