// Package web embeds the Helm SPA and serves it under the service mount.
//
// The app source (Vite + React + TypeScript) and its build output live in this
// same directory: `npm run build` here produces dist/, which the `all:` embed
// below compiles into helm-svc. dist/ is COMMITTED on purpose — the launcher
// (assets/scripts/gc-helm-svc.sh) rebuilds the Go binary on demand but never
// runs npm, so a Node-less build must still yield a working board. Rebuild and
// commit dist/ whenever the app source changes; see README.md.
//
// The `all:` prefix captures dotfiles and nested asset directories under dist/.
package web

import "embed"

//go:embed all:dist
var distFS embed.FS
