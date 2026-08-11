// Injected by vite.config.ts `define`, from the same HELM_DEV_MOUNT that
// configures the dev proxy. Only ever read behind `import.meta.env.DEV`, so it
// is constant-folded away in production builds — see origin.ts.
declare const __HELM_DEV_CITY__: string;
