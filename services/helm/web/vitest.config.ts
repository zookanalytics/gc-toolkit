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
  define: {
    // vite.config.ts injects this from HELM_DEV_MOUNT; tests never take the dev
    // branch that reads it (they pass an explicit origin), but the identifier
    // must still resolve at module scope.
    __HELM_DEV_CITY__: JSON.stringify('test-city'),
  },
});
