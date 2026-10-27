import { describe, expect, it } from 'vitest';
import { cityUrl, parseMountPath, resolveSupervisorOrigin } from './origin';

// The whole drill plane hangs off this parse: get the city wrong and every
// request addresses the wrong city; get the origin wrong and the CSP
// (connect-src 'self') refuses the request outright.
describe('parseMountPath', () => {
  it('reads the city out of the service mount', () => {
    expect(parseMountPath('/v0/city/mycity/svc/helm/')).toEqual({
      pathPrefix: '',
      city: 'mycity',
    });
  });

  it('accepts the mount without its trailing slash', () => {
    // index.html's normalizer redirects to the trailing-slash form, but the
    // first paint happens before that lands.
    expect(parseMountPath('/v0/city/mycity/svc/helm')).toEqual({
      pathPrefix: '',
      city: 'mycity',
    });
  });

  it('keeps a path prefix when the supervisor is mounted under one', () => {
    expect(parseMountPath('/gc/v0/city/mycity/svc/helm/')).toEqual({
      pathPrefix: '/gc',
      city: 'mycity',
    });
  });

  it('reads deeper paths under the mount', () => {
    expect(parseMountPath('/v0/city/mycity/svc/helm/assets/index-abc.js')?.city).toBe(
      'mycity',
    );
  });

  it('decodes a percent-encoded city segment', () => {
    expect(parseMountPath('/v0/city/my%20city/svc/helm/')?.city).toBe('my city');
  });

  it('returns null off a service mount', () => {
    expect(parseMountPath('/')).toBeNull();
    expect(parseMountPath('/v0/city/mycity/beads')).toBeNull();
    expect(parseMountPath('/svc/helm/')).toBeNull();
  });

  it('returns null rather than guessing when the city segment is empty', () => {
    expect(parseMountPath('/v0/city//svc/helm/')).toBeNull();
  });
});

describe('resolveSupervisorOrigin', () => {
  // The reachability requirement, as a test: whatever origin the operator
  // loaded the board from is the origin the drill plane talks to. A hardcoded
  // 127.0.0.1 would be the operator's own laptop when the board is opened over
  // tailscale, and would be refused by connect-src 'self' besides.
  it('addresses the same origin the document was served from', () => {
    const origin = resolveSupervisorOrigin({
      origin: 'https://gc-host.tail1234.ts.net',
      pathname: '/v0/city/mycity/svc/helm/',
    });
    expect(origin).toEqual({ baseUrl: 'https://gc-host.tail1234.ts.net', city: 'mycity' });
  });

  it('carries a path prefix into the base url', () => {
    expect(
      resolveSupervisorOrigin({
        origin: 'https://gc-host.tail1234.ts.net',
        pathname: '/gc/v0/city/mycity/svc/helm/',
      })?.baseUrl,
    ).toBe('https://gc-host.tail1234.ts.net/gc');
  });

  it('resolves loopback the same way, with no special case', () => {
    expect(
      resolveSupervisorOrigin({
        origin: 'http://127.0.0.1:8372',
        pathname: '/v0/city/mycity/svc/helm/',
      }),
    ).toEqual({ baseUrl: 'http://127.0.0.1:8372', city: 'mycity' });
  });
});

describe('cityUrl', () => {
  it('builds a city-scoped supervisor url', () => {
    const origin = { baseUrl: 'https://gc-host.tail1234.ts.net', city: 'mycity' };
    expect(cityUrl(origin, '/events/stream')).toBe(
      'https://gc-host.tail1234.ts.net/v0/city/mycity/events/stream',
    );
  });

  it('escapes a city name that needs it', () => {
    expect(cityUrl({ baseUrl: '', city: 'my city' }, '/pending')).toBe(
      '/v0/city/my%20city/pending',
    );
  });
});
