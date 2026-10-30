// demo-screenshot.mjs — the renderer behind demo-screenshot.sh's markdown
// kind: draw an HTML fragment from GitHub's markdown API inside a comment box
// carrying GitHub's comment styles, as one HTML page, which the SprintShow
// engine's screenshot command then serves and captures.
//
// The page carries no script. Its surface is the element with id="surface",
// which the capture crops to, and the page paints no background around it, so
// a capture that leaves out the default white background keeps the surface's
// rounded corners transparent. A fragment holding a block that github.com's
// page script finishes, such as a mermaid diagram or math, is refused, because
// this page has no script.
//
// Usage (demo-screenshot.sh is the interface; this is its contract):
//   node demo-screenshot.mjs --output <page.html> --html <file>
//       [--title <text>] [--expand]
//
// Exit: 0 the page is written, 2 bad arguments, 1 anything that stopped the
// write, a refused fragment included.

import { readFileSync, realpathSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const PROG = 'demo-screenshot.mjs';

class UsageError extends Error {}

const VALUE_FLAGS = new Set(['output', 'html', 'title']);
const BOOLEAN_FLAGS = new Set(['expand']);

export function parseArgs(argv) {
  const opts = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) throw new UsageError(`unexpected argument '${a}'`);
    const name = a.slice(2);
    if (BOOLEAN_FLAGS.has(name)) {
      opts[name] = true;
    } else if (VALUE_FLAGS.has(name)) {
      if (i + 1 >= argv.length) throw new UsageError(`--${name} needs a value`);
      opts[name] = argv[++i];
    } else {
      throw new UsageError(`unknown flag --${name}`);
    }
  }
  if (!opts.output) throw new UsageError('--output is required');
  if (!opts.html) throw new UsageError('--html is required');
  return opts;
}

export function escapeHtml(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

const SANS = '-apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji"';
const MONO = 'ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace';

// ── A rendered comment ────────────────────────────────────────────────────

// GitHub's comment styles (Primer, light theme) for the markup its markdown
// renderer emits, the utility classes it writes on that markup included, such
// as a colour swatch's.
const MARKDOWN_CSS = `
.markdown-body { font-family: ${SANS}; font-size: 14px; line-height: 1.5; color: #1f2328; word-wrap: break-word; }
.markdown-body * { box-sizing: border-box; }
.markdown-body > *:first-child { margin-top: 0 !important; }
.markdown-body > *:last-child { margin-bottom: 0 !important; }
.markdown-body p, .markdown-body blockquote, .markdown-body ul, .markdown-body ol, .markdown-body dl,
.markdown-body table, .markdown-body pre, .markdown-body details { margin-top: 0; margin-bottom: 16px; }
.markdown-body a { color: #0969da; text-decoration: underline; text-underline-offset: .2rem; }
.markdown-body a.user-mention, .markdown-body a.team-mention { font-weight: 600; color: #1f2328; text-decoration: none; }
.markdown-body strong, .markdown-body b { font-weight: 600; }
.markdown-body sub, .markdown-body sup { position: relative; font-size: 75%; line-height: 0; vertical-align: baseline; }
.markdown-body sub { bottom: -.25em; }
.markdown-body sup { top: -.5em; }
.markdown-body h1, .markdown-body h2, .markdown-body h3, .markdown-body h4, .markdown-body h5, .markdown-body h6 { margin-top: 24px; margin-bottom: 16px; font-weight: 600; line-height: 1.25; }
.markdown-body h1 { font-size: 2em; padding-bottom: .3em; border-bottom: 1px solid #d1d9e0b3; }
.markdown-body h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid #d1d9e0b3; }
.markdown-body h3 { font-size: 1.25em; }
.markdown-body h4 { font-size: 1em; }
.markdown-body h5 { font-size: .875em; }
.markdown-body h6 { font-size: .85em; color: #59636e; }
.markdown-body .anchor { display: none; }
.markdown-body ul, .markdown-body ol { padding-left: 2em; }
.markdown-body ul ul, .markdown-body ul ol, .markdown-body ol ol, .markdown-body ol ul { margin-top: 0; margin-bottom: 0; }
.markdown-body li + li { margin-top: .25em; }
.markdown-body li > p { margin-top: 16px; }
.markdown-body .contains-task-list { padding-left: 2em; }
.markdown-body .task-list-item { list-style-type: none; }
.markdown-body .task-list-item-checkbox { margin: 0 .2em .25em -1.4em; vertical-align: middle; }
.markdown-body code, .markdown-body tt { padding: .2em .4em; margin: 0; font-size: 85%; white-space: break-spaces; background-color: #818b981f; border-radius: 6px; font-family: ${MONO}; }
.markdown-body pre { padding: 16px; overflow: auto; font-size: 85%; line-height: 1.45; color: #1f2328; background-color: #f6f8fa; border-radius: 6px; font-family: ${MONO}; word-wrap: normal; }
.markdown-body pre code, .markdown-body pre tt { display: inline; padding: 0; margin: 0; overflow: visible; line-height: inherit; word-wrap: normal; background-color: transparent; border: 0; font-size: 100%; white-space: pre; }
.markdown-body .highlight { margin-bottom: 16px; }
.markdown-body .highlight pre { margin-bottom: 0; word-break: normal; }
.markdown-body blockquote { margin-left: 0; margin-right: 0; padding: 0 1em; color: #59636e; border-left: .25em solid #d1d9e0; }
.markdown-body hr { height: 1px; margin: 24px 0; background-color: #d1d9e0; border: 0; padding: 0; }
.markdown-body table { display: block; width: max-content; max-width: 100%; overflow: auto; border-spacing: 0; border-collapse: collapse; font-variant: tabular-nums; }
.markdown-body table th { font-weight: 600; }
.markdown-body table th, .markdown-body table td { padding: 6px 13px; border: 1px solid #d1d9e0; }
.markdown-body table tr { background-color: #ffffff; border-top: 1px solid #d1d9e0b3; }
.markdown-body table tr:nth-child(2n) { background-color: #f6f8fa; }
.markdown-body img { max-width: 100%; box-sizing: content-box; background-color: #ffffff; }
.markdown-body details summary { cursor: pointer; }
.markdown-body kbd { display: inline-block; padding: 4px; font: 11px ${MONO}; line-height: 10px; color: #1f2328; vertical-align: middle; background-color: #f6f8fa; border: 1px solid #d1d9e0b3; border-radius: 6px; box-shadow: inset 0 -1px 0 #d1d9e0b3; }
.markdown-body [data-footnote-ref]::before { content: "["; }
.markdown-body [data-footnote-ref]::after { content: "]"; }
.markdown-body .footnotes { font-size: 12px; color: #59636e; border-top: 1px solid #d1d9e0; }
.markdown-body .footnotes ol { padding-left: 16px; }
.markdown-body .footnotes ol ul { display: inline-block; padding-left: 16px; margin-top: 16px; }
.markdown-body .footnotes li { position: relative; }
.markdown-body .markdown-alert { padding: .5rem 1rem; margin-bottom: 16px; color: inherit; border-left: .25em solid #d1d9e0; }
.markdown-body .markdown-alert > :first-child { margin-top: 0; }
.markdown-body .markdown-alert > :last-child { margin-bottom: 0; }
.markdown-body .markdown-alert .markdown-alert-title { display: flex; align-items: center; font-weight: 500; line-height: 1; }
.markdown-body .markdown-alert.markdown-alert-note { border-left-color: #0969da; }
.markdown-body .markdown-alert.markdown-alert-note .markdown-alert-title { color: #0969da; }
.markdown-body .markdown-alert.markdown-alert-tip { border-left-color: #1a7f37; }
.markdown-body .markdown-alert.markdown-alert-tip .markdown-alert-title { color: #1a7f37; }
.markdown-body .markdown-alert.markdown-alert-important { border-left-color: #8250df; }
.markdown-body .markdown-alert.markdown-alert-important .markdown-alert-title { color: #8250df; }
.markdown-body .markdown-alert.markdown-alert-warning { border-left-color: #9a6700; }
.markdown-body .markdown-alert.markdown-alert-warning .markdown-alert-title { color: #9a6700; }
.markdown-body .markdown-alert.markdown-alert-caution { border-left-color: #cf222e; }
.markdown-body .markdown-alert.markdown-alert-caution .markdown-alert-title { color: #cf222e; }
.markdown-body .octicon { display: inline-block; overflow: visible; vertical-align: text-bottom; fill: currentColor; }
.markdown-body .mr-2 { margin-right: 8px; }
.markdown-body .ml-1 { margin-left: 4px; }
.markdown-body .d-inline-block { display: inline-block; }
.markdown-body .border { border: 1px solid #d1d9e0; }
.markdown-body .color-border-subtle { border-color: #d1d9e0b3; }
.markdown-body .circle { border-radius: 9999px; }
.markdown-body .sr-only { position: absolute; width: 1px; height: 1px; padding: 0; overflow: hidden; clip-path: rect(0 0 0 0); overflow-wrap: normal; border: 0; }
.markdown-body g-emoji { display: inline-block; min-width: 1ch; font-family: "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol"; font-size: 1em; font-style: normal; font-weight: 400; line-height: 1; vertical-align: -.075em; }
.markdown-body .pl-c { color: #59636e; }
.markdown-body .pl-c1, .markdown-body .pl-s .pl-v { color: #0550ae; }
.markdown-body .pl-e, .markdown-body .pl-en { color: #6639ba; }
.markdown-body .pl-smi, .markdown-body .pl-s .pl-s1 { color: #1f2328; }
.markdown-body .pl-ent { color: #0550ae; }
.markdown-body .pl-k { color: #cf222e; }
.markdown-body .pl-s, .markdown-body .pl-pds, .markdown-body .pl-s .pl-pse .pl-s1, .markdown-body .pl-sr { color: #0a3069; }
.markdown-body .pl-v, .markdown-body .pl-smw { color: #953800; }
.markdown-body .pl-bu { color: #82071e; }
.markdown-body .pl-mi { font-style: italic; color: #1f2328; }
.markdown-body .pl-mb { font-weight: bold; color: #1f2328; }
.markdown-body .pl-md { color: #82071e; background-color: #ffebe9; }
.markdown-body .pl-mi1 { color: #116329; background-color: #dafbe1; }
`;

// GitHub's markdown API leaves some blocks of a comment for github.com's page
// script to finish. A mermaid, geojson, topojson or stl fence comes back as a
// section marked js-render-needs-enrichment, holding the fence's source and a
// loading spinner, and naming its renderer at viewscreen.githubusercontent.com,
// whose content security policy lets only github.com frame it. Math comes back
// as its TeX inside a <math-renderer>. A page with no script would draw that
// markup in place of what GitHub shows. Every enrichment type carries the same
// marker, and a custom element is drawn only when its own markup is what GitHub
// shows, so a block of a kind GitHub adds later is refused as well.
const DRAWN_FROM_MARKUP = new Set([
  'markdown-accessiblity-table', // GitHub's spelling; it wraps a <table>
  'themed-picture', // it wraps a <picture>
  // It wraps an emoji. Its script changes the text only for a tag carrying a
  // fallback-src or a tone, and GitHub's markdown API writes neither.
  'g-emoji',
]);

// A start tag: GitHub's renderer escapes every < in text and in attribute
// values, so each raw < that opens a name is a tag. The attributes run to the
// first >, which is enough to find the marker and the type GitHub writes there.
const START_TAG = /<([a-zA-Z][a-zA-Z0-9-]*)([^>]*)>/g;
const ENRICHMENT = /(?:^|[\s"'=])js-render-needs-enrichment(?=[\s"'>/]|$)/;
const DATA_TYPE = /\sdata-type\s*=\s*"([^"]*)"/i;

/**
 * The blocks of a fragment from GitHub's markdown API that github.com's page
 * script finishes, in document order: an enrichment section by its type
 * (`mermaid`), math as `math`, and any other custom element by its tag.
 */
export function unfinishedBlocks(fragment) {
  const blocks = [];
  for (const [, tag, attrs] of fragment.matchAll(START_TAG)) {
    const name = tag.toLowerCase();
    if (ENRICHMENT.test(attrs)) blocks.push(attrs.match(DATA_TYPE)?.[1] || 'enrichment');
    else if (name === 'math-renderer') blocks.push('math');
    else if (name.includes('-') && !DRAWN_FROM_MARKUP.has(name)) blocks.push(`<${name}>`);
  }
  return blocks;
}

export function commentDocument({ fragment, title, expand = false }) {
  // A block inside a collapsed <details> is refused as well, because the
  // same comment captured with --expand would show it.
  const unfinished = unfinishedBlocks(fragment);
  if (unfinished.length) {
    const counts = new Map();
    for (const b of unfinished) counts.set(b, (counts.get(b) ?? 0) + 1);
    const named = [...counts].map(([b, n]) => `${b} (${n})`).join(', ');
    throw new Error(`github.com finishes part of this comment with its page script, which this page does not carry: ${named}. A capture would show that part unfinished, so no page is written.`);
  }
  // The page has no script, and the capture clicks nothing, so --expand opens
  // each <details> in the markup itself.
  const body = expand ? fragment.replace(/<details(?![\w-])/gi, '<details open') : fragment;
  const header = title ? `<div class="comment-header">${escapeHtml(title)}</div>` : '';
  return `<!doctype html>
<html><head><meta charset="utf-8"><style>
html, body { margin: 0; background: transparent; }
.comment { width: 800px; background: #ffffff; border: 1px solid #d1d9e0; border-radius: 6px; overflow: hidden; }
.comment-header { padding: 8px 16px; background: #f6f8fa; border-bottom: 1px solid #d1d9e0; color: #59636e; font: 14px/1.5 ${SANS}; }
.comment > .markdown-body { padding: 16px; }
${MARKDOWN_CSS}
</style></head><body><div class="comment" id="surface">${header}<div class="markdown-body">${body}</div></div></body></html>`;
}

// ── The page ──────────────────────────────────────────────────────────────

/** The page a parsed call draws. */
export function renderPage(opts) {
  return commentDocument({ fragment: readFileSync(opts.html, 'utf8'), title: opts.title, expand: Boolean(opts.expand) });
}

function main(argv) {
  let opts;
  try {
    opts = parseArgs(argv);
  } catch (e) {
    if (e instanceof UsageError) {
      console.error(`${PROG}: ${e.message}`);
      return 2;
    }
    throw e;
  }
  writeFileSync(path.resolve(opts.output), renderPage(opts));
  return 0;
}

// Node runs a script from its real path, so import.meta.url names this file
// with every symlink resolved, while process.argv[1] keeps the path it was run
// by, such as macOS's /var for /private/var. --preserve-symlinks-main keeps the
// symlink in import.meta.url instead, so both sides are resolved. A path that
// does not resolve, such as an argument after node -e, is not this file.
function runAsScript() {
  if (!process.argv[1]) return false;
  try {
    return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (runAsScript()) {
  try {
    process.exitCode = main(process.argv.slice(2));
  } catch (e) {
    console.error(`${PROG}: ${e?.message?.split('\n')[0] ?? e}`);
    process.exitCode = 1;
  }
}
