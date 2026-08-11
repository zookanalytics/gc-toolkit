#!/usr/bin/env node
// Regenerate the drill plane's supervisor types from the supervisor's own
// OpenAPI spec.
//
// WHY THIS EXISTS. The supervisor API is fully described by an OpenAPI 3.1
// document, so the drill plane should not hand-write request/response types —
// it gets them for free. But the spec lives in a DIFFERENT repository (the
// gascity rig, internal/api/openapi.json, generated there by cmd/genspec from
// the Huma handlers) and describes ~200 operations; running openapi-typescript
// over the whole thing emits ~23k lines / ~865KB of .d.ts. Committing that into
// gc-toolkit for the eight operations this plane calls is not a trade worth
// making, and there is no build-time path to the other repo's file anyway.
//
// So: prune first, then generate. This script reads the full spec (from a live
// supervisor by default — it serves /openapi.json), keeps exactly the
// operations OPERATIONS lists plus the transitive closure of everything they
// $ref, and runs openapi-typescript over that subset to produce the ONE
// committed artifact:
//
//   src/drill/gen/supervisor.d.ts
//
// It is committed because the Go binary embeds a prebuilt bundle and the
// launcher never runs npm (see services/helm/web/.gitignore); a build must
// never need a live supervisor. The pruned spec itself is an intermediate and
// is deliberately NOT committed — nothing reads it, the OPERATIONS list below
// documents the dependency surface far better than 8k lines of JSON would, and
// `--spec <file>` still regenerates offline from any copy of the upstream spec.
//
// The OPERATIONS list is therefore the drill plane's declared dependency
// surface on the supervisor: adding an endpoint means adding it here and
// re-running this script. Calling an endpoint that is NOT here does not fail
// subtly at runtime — openapi-fetch is typed by `paths`, so `tsc` rejects it.
//
// Usage:
//   npm run gen:supervisor-types                       # live supervisor
//   npm run gen:supervisor-types -- --spec ./spec.json # a file (offline)
//   npm run gen:supervisor-types -- --check            # verify, write nothing
//
// --check regenerates into a temp file and exits non-zero if it differs from
// the committed .d.ts, which is how CI (or a curious reviewer) detects that the
// upstream supervisor spec has drifted away from the vendored types.

import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const WEB_ROOT = resolve(HERE, '..');
const GEN_DIR = resolve(WEB_ROOT, 'src/drill/gen');
const TYPES_OUT = resolve(GEN_DIR, 'supervisor.d.ts');

const DEFAULT_SPEC = 'http://127.0.0.1:8372/openapi.json';

// The drill plane's dependency surface. Each entry is one operation it calls.
// Keep the comments — they are why the endpoint is here, which is the thing a
// future reader needs when the supervisor spec changes under them.
const OPERATIONS = [
  // Bead detail: the primary drill target. A tile's id IS a bead id.
  ['/v0/city/{cityName}/bead/{id}', ['get']],
  // Bead lists. The board's own tiles come from helm-svc, not here; this is for
  // the drill plane's own queries (e.g. label=gc:wait — who is waiting on a
  // human right now).
  ['/v0/city/{cityName}/beads', ['get']],
  // Session liveness: the only source of running/attached, and what maps an
  // anchor to the agent working it (active_bead).
  ['/v0/city/{cityName}/sessions', ['get']],
  // Session detail, incl. ?peek=true — the "read the latest output" snapshot
  // that a resting tile shows before U9 attaches a live terminal.
  ['/v0/city/{cityName}/session/{id}', ['get']],
  // What is blocking on the operator right now.
  ['/v0/city/{cityName}/pending', ['get']],
  // Mail counts — cheap "is anything addressed to me" signal.
  ['/v0/city/{cityName}/mail/count', ['get']],
  // Recent activity, filtered per drill target. Also the source of the WireEvent
  // schema that types the SSE payloads.
  ['/v0/city/{cityName}/events', ['get']],
  // The SSE stream itself. Consumed via EventSource (not openapi-fetch, which
  // has no streaming surface), but declared here so the dependency is visible
  // and the pruned spec documents the whole plane.
  ['/v0/city/{cityName}/events/stream', ['get']],
];

function parseArgs(argv) {
  const args = { spec: DEFAULT_SPEC, check: false };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--check') {
      args.check = true;
    } else if (arg === '--spec') {
      const value = argv[++i];
      if (value === undefined) throw new Error('--spec requires a value (a URL or a file path)');
      args.spec = value;
    } else if (arg.startsWith('--spec=')) {
      args.spec = arg.slice('--spec='.length);
    } else {
      throw new Error(`unknown argument: ${arg}`);
    }
  }
  return args;
}

async function loadSpec(source) {
  if (/^https?:\/\//.test(source)) {
    const res = await fetch(source, { signal: AbortSignal.timeout(30_000) });
    if (!res.ok) throw new Error(`GET ${source}: HTTP ${res.status}`);
    return await res.json();
  }
  return JSON.parse(readFileSync(resolve(process.cwd(), source), 'utf8'));
}

// Collect every "#/components/<section>/<name>" ref reachable from `node`,
// following refs through the components they land in. Local refs only: the
// supervisor spec is self-contained, and a remote ref would silently produce a
// subset that does not stand alone.
function collectRefs(node, spec, seen) {
  if (node === null || typeof node !== 'object') return;
  if (Array.isArray(node)) {
    for (const item of node) collectRefs(item, spec, seen);
    return;
  }
  for (const [key, value] of Object.entries(node)) {
    if (key === '$ref' && typeof value === 'string') {
      if (!value.startsWith('#/components/')) {
        throw new Error(`unsupported non-local $ref: ${value}`);
      }
      const parts = value.slice('#/components/'.length).split('/');
      if (parts.length !== 2) throw new Error(`unsupported $ref shape: ${value}`);
      const [section, name] = parts;
      const key2 = `${section}/${name}`;
      if (seen.has(key2)) continue;
      const target = spec.components?.[section]?.[name];
      if (target === undefined) throw new Error(`dangling $ref: ${value}`);
      seen.add(key2);
      collectRefs(target, spec, seen);
      continue;
    }
    collectRefs(value, spec, seen);
  }
}

function prune(spec) {
  const paths = {};
  for (const [path, methods] of OPERATIONS) {
    const source = spec.paths?.[path];
    if (source === undefined) {
      throw new Error(`spec has no path ${path} — the supervisor API changed shape`);
    }
    const kept = {};
    // Path-level parameters apply to every operation under the path.
    if (source.parameters !== undefined) kept.parameters = source.parameters;
    for (const method of methods) {
      if (source[method] === undefined) {
        throw new Error(`spec has no ${method.toUpperCase()} ${path}`);
      }
      kept[method] = source[method];
    }
    paths[path] = kept;
  }

  const seen = new Set();
  collectRefs(paths, spec, seen);

  const components = {};
  for (const ref of [...seen].sort()) {
    const [section, name] = ref.split('/');
    components[section] ??= {};
    components[section][name] = spec.components[section][name];
  }
  // Sort each section so the committed artifact has a stable diff regardless of
  // the order refs happened to be discovered in.
  for (const section of Object.keys(components)) {
    components[section] = Object.fromEntries(
      Object.entries(components[section]).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)),
    );
  }

  return {
    openapi: spec.openapi,
    info: {
      ...spec.info,
      // Stamp the subset so nobody mistakes the vendored file for the whole API.
      title: `${spec.info?.title ?? 'Gas City Supervisor API'} (helm drill-in subset)`,
      description:
        'PRUNED SUBSET — generated by services/helm/web/scripts/gen-supervisor-types.mjs. ' +
        'Contains only the operations the helm drill-in plane calls. Do not edit by hand; ' +
        'do not treat as the supervisor API contract (the authority is the gascity rig).',
    },
    paths,
    components,
  };
}

// Render the pruned spec to .d.ts at `destination`. openapi-typescript reads a
// file, so the intermediate is written to a scratch dir that is always removed.
function generateTypes(pruned, destination) {
  const scratch = mkdtempSync(join(tmpdir(), 'helm-supervisor-spec-'));
  try {
    const specPath = join(scratch, 'supervisor-openapi.json');
    writeFileSync(specPath, JSON.stringify(pruned, null, 2) + '\n');
    execFileSync(
      'npx',
      [
        '--no-install',
        'openapi-typescript',
        specPath,
        '-o',
        destination,
        '--empty-objects-unknown',
      ],
      { stdio: 'inherit', cwd: WEB_ROOT },
    );
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const spec = await loadSpec(args.spec);
  const pruned = prune(spec);

  if (args.check) {
    let committed;
    try {
      committed = readFileSync(TYPES_OUT, 'utf8');
    } catch {
      console.error(`missing ${TYPES_OUT} — run: npm run gen:supervisor-types`);
      process.exit(1);
    }
    const scratch = mkdtempSync(join(tmpdir(), 'helm-supervisor-types-'));
    try {
      const candidate = join(scratch, 'supervisor.d.ts');
      generateTypes(pruned, candidate);
      if (readFileSync(candidate, 'utf8') !== committed) {
        console.error(
          `${TYPES_OUT} is stale: the upstream spec no longer generates the committed bytes.\n` +
            'Re-run `npm run gen:supervisor-types` and review the diff.',
        );
        process.exit(1);
      }
    } finally {
      rmSync(scratch, { recursive: true, force: true });
    }
    console.log(`ok: ${TYPES_OUT} matches ${args.spec}`);
    return;
  }

  mkdirSync(GEN_DIR, { recursive: true });
  generateTypes(pruned, TYPES_OUT);
  console.log(`wrote ${TYPES_OUT}`);
}

await main();
