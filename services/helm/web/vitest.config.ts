import { defineConfig } from 'vitest/config';

// Kept separate from vite.config.ts so the app build never carries test config,
// and so `vitest` does not inherit the dev proxy (which would reach a live
// supervisor — these tests stub fetch and EventSource instead, and must pass
// with no city running).
export default defineConfig({
  test: {
    environment: 'jsdom',
    include: ['src/**/*.test.ts', 'src/**/*.test.tsx'],
    restoreMocks: true,
  },
  // Vitest loads each test file through Vite's transform, which enforces
  // server.fs.deny. Vite's default deny list includes '**/.git/**', so a
  // worktree whose path contains a .git segment — the refinery stages its
  // merge-prep tree at <git-common-dir>/gc-refinery-prep, inside .git — makes
  // every source file match the deny glob and fail to load. fs.strict guards a
  // served dev server; vitest serves nothing, so disabling it lets the suite
  // run from any path.
  server: { fs: { strict: false } },
  define: {
    // vite.config.ts injects this from HELM_DEV_MOUNT; tests never take the dev
    // branch that reads it (they pass an explicit origin), but the identifier
    // must still resolve at module scope.
    __HELM_DEV_CITY__: JSON.stringify('test-city'),
  },
});
