// demo-screenshot.mjs — the renderer behind demo-screenshot.sh's terminal and
// markdown kinds: draw a surface that has no app of its own as one HTML page,
// which the SprintShow engine's screenshot command then serves and captures.
//
// The page carries no script. Its surface is the element with id="surface",
// which the capture crops to, and the page paints no background around it, so
// a capture that leaves out the default white background keeps the surface's
// rounded corners transparent.
//
// Kinds, one per surface with no app to drive:
//   terminal  render a command's captured output as a terminal window shows
//             it: ANSI SGR colour and weight kept, every other escape dropped,
//             a carriage return's redraw kept over what it overwrote.
//   markdown  render an HTML fragment from GitHub's markdown API inside a
//             comment box carrying GitHub's comment styles. A fragment holding
//             a block that github.com's page script finishes, such as a mermaid
//             diagram or math, is refused, because this page has no script.
//
// Usage (demo-screenshot.sh is the interface; this is its contract):
//   node demo-screenshot.mjs terminal --output <page.html> --text <file>
//       [--prompt <command>] [--title <text>] [--columns <n>] [--max-lines <n>]
//   node demo-screenshot.mjs markdown --output <page.html> --html <file>
//       [--title <text>] [--expand]
//
// Exit: 0 the page is written, 2 bad arguments, 1 anything that stopped the
// write, a refused fragment included.

import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const PROG = 'demo-screenshot.mjs';

class UsageError extends Error {}

const VALUE_FLAGS = new Set(['output', 'text', 'prompt', 'title', 'columns', 'max-lines', 'html']);
const BOOLEAN_FLAGS = new Set(['expand']);
const KIND_FLAGS = {
  terminal: ['output', 'text', 'prompt', 'title', 'columns', 'max-lines'],
  markdown: ['output', 'html', 'title', 'expand'],
};

export function parseArgs(argv) {
  const [kind, ...rest] = argv;
  if (!kind || !Object.hasOwn(KIND_FLAGS, kind)) throw new UsageError(`a kind is required: terminal or markdown (got '${kind ?? ''}')`);
  const opts = { kind };
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i];
    if (!a.startsWith('--')) throw new UsageError(`unexpected argument '${a}'`);
    const name = a.slice(2);
    if (!KIND_FLAGS[kind].includes(name)) throw new UsageError(`${kind} takes no --${name}`);
    if (BOOLEAN_FLAGS.has(name)) {
      opts[name] = true;
    } else if (VALUE_FLAGS.has(name)) {
      if (i + 1 >= rest.length) throw new UsageError(`--${name} needs a value`);
      opts[name] = rest[++i];
    }
  }
  if (!opts.output) throw new UsageError('--output is required');
  const need = { terminal: 'text', markdown: 'html' }[kind];
  if (!opts[need]) throw new UsageError(`${kind} needs --${need}`);
  for (const n of ['columns', 'max-lines']) {
    if (opts[n] !== undefined && !/^[1-9][0-9]*$/.test(opts[n])) throw new UsageError(`--${n} must be a positive integer (got '${opts[n]}')`);
  }
  return opts;
}

// ── Terminal output ───────────────────────────────────────────────────────

const PALETTE = [
  '#000000', '#cd3131', '#0dbc79', '#e5e510', '#2472c8', '#bc3fbc', '#11a8cd', '#e5e5e5',
  '#666666', '#f14c4c', '#23d18b', '#f5f543', '#3b8eea', '#d670d6', '#29b8db', '#ffffff',
];
const TERM_FG = '#cccccc';
const TERM_BG = '#1e1e1e';
const TAB = 8;

function color256(n) {
  if (n < 16) return PALETTE[n];
  if (n < 232) {
    const levels = [0, 95, 135, 175, 215, 255];
    const i = n - 16;
    return rgb(levels[Math.floor(i / 36)], levels[Math.floor(i / 6) % 6], levels[i % 6]);
  }
  const g = 8 + (n - 232) * 10;
  return rgb(g, g, g);
}

function rgb(r, g, b) {
  return '#' + [r, g, b].map((v) => Math.max(0, Math.min(255, v)).toString(16).padStart(2, '0')).join('');
}

export function escapeHtml(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function freshStyle() {
  return { fg: null, bg: null, bold: false, dim: false, italic: false, underline: false, strike: false, inverse: false };
}

/** A colour given as sub-parameters: `5:n`, `2:r:g:b`, or `2:<colour space>:r:g:b`. */
function subColor(sub) {
  if (sub[0] === 5 && sub.length >= 2) return color256(sub[1] & 255);
  if (sub[0] === 2 && sub.length >= 5) return rgb(sub[2], sub[3], sub[4]);
  if (sub[0] === 2 && sub.length === 4) return rgb(sub[1], sub[2], sub[3]);
  return null;
}

/**
 * Apply one SGR parameter list (`1;31`, `38;5;208`, `38:2::255:135:0`, `` for
 * reset) to a style. A `;` separates parameters and a `:` separates one
 * parameter's sub-parameters, so `4:3`, a curly underline, is one parameter. A
 * private marker (`<=>?`) makes the sequence another one, such as xterm's
 * `CSI > 4 ; 2 m`, which sets nothing that is drawn.
 */
function applySgr(style, params) {
  if (!/^[0-9;:]*$/.test(params)) return;
  const p = (params === '' ? '0' : params).split(';').map((g) => g.split(':').map((x) => (x === '' ? 0 : Number(x))));
  for (let i = 0; i < p.length; i++) {
    const [c, ...sub] = p[i];
    if (c === 0) Object.assign(style, freshStyle());
    else if (c === 1) style.bold = true;
    else if (c === 2) style.dim = true;
    else if (c === 3) style.italic = true;
    else if (c === 4) style.underline = sub[0] !== 0;
    else if (c === 7) style.inverse = true;
    else if (c === 9) style.strike = true;
    else if (c === 22) { style.bold = false; style.dim = false; }
    else if (c === 23) style.italic = false;
    else if (c === 24) style.underline = false;
    else if (c === 27) style.inverse = false;
    else if (c === 29) style.strike = false;
    else if (c >= 30 && c <= 37) style.fg = PALETTE[c - 30];
    else if (c >= 90 && c <= 97) style.fg = PALETTE[c - 90 + 8];
    else if (c >= 40 && c <= 47) style.bg = PALETTE[c - 40];
    else if (c >= 100 && c <= 107) style.bg = PALETTE[c - 100 + 8];
    else if (c === 39) style.fg = null;
    else if (c === 49) style.bg = null;
    else if (c === 38 || c === 48 || c === 58) {
      // The colour is in this parameter's sub-parameters or in the parameters
      // that follow it. 58 colours the underline, which is drawn in the text's
      // colour, so its colour is only skipped.
      let col = null;
      if (sub.length) col = subColor(sub);
      else if (p[i + 1]?.[0] === 5 && i + 2 < p.length) { col = color256(p[i + 2][0] & 255); i += 2; }
      else if (p[i + 1]?.[0] === 2 && i + 4 < p.length) { col = rgb(p[i + 2][0], p[i + 3][0], p[i + 4][0]); i += 4; }
      else break;
      if (col && c === 38) style.fg = col;
      else if (col && c === 48) style.bg = col;
    }
  }
}

function styleCss(s) {
  let fg = s.fg; let bg = s.bg;
  if (s.inverse) { fg = s.bg ?? TERM_BG; bg = s.fg ?? TERM_FG; }
  const css = [];
  if (fg) css.push(`color:${fg}`);
  if (bg) css.push(`background:${bg}`);
  if (s.bold) css.push('font-weight:bold');
  if (s.dim) css.push('opacity:.65');
  if (s.italic) css.push('font-style:italic');
  const deco = [s.underline && 'underline', s.strike && 'line-through'].filter(Boolean);
  if (deco.length) css.push(`text-decoration:${deco.join(' ')}`);
  return css.join(';');
}

// An escape sequence: CSI (ESC [ … final), OSC (ESC ] … BEL or ST), or any
// other ESC, its intermediate bytes and its final byte, such as ESC ( B. Only a
// CSI ending in `m` with no private marker (SGR) changes what is drawn.
const ESCAPE = /\x1b\[([0-9;:?<=>]*)[ -\/]*([@-~])|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)?|\x1b[ -\/]*[0-~]?/g;

/**
 * Turn captured output into HTML a terminal window would show, and report its
 * widest line in columns and how many lines it has.
 */
export function ansiToHtml(text, maxLines = Infinity) {
  const style = freshStyle();
  const lines = text.replace(/\r\n/g, '\n').replace(/\n$/, '').split('\n');
  const shown = lines.length > maxLines ? lines.slice(0, maxLines) : lines;
  let widest = 0;
  const out = shown.map((line) => {
    // A carriage return draws over the line from its start; keep what the last
    // redraw shows, with the styles every earlier segment set. A return that
    // ends the line redraws nothing, so the line stands.
    const segs = line.replace(/\r+$/, '').split('\r');
    for (const dropped of segs.slice(0, -1)) {
      for (const m of dropped.matchAll(ESCAPE)) if (m[2] === 'm') applySgr(style, m[1]);
    }
    const last = segs[segs.length - 1];
    let html = '';
    let cols = 0;
    let at = 0;
    const emit = (chunk) => {
      // Every control byte but a tab draws nothing.
      const t = chunk.replace(/[\x00-\x08\x0b-\x1f\x7f]/g, '');
      if (!t) return;
      for (const ch of t) cols = ch === '\t' ? cols + TAB - (cols % TAB) : cols + 1;
      const css = styleCss(style);
      html += css ? `<span style="${css}">${escapeHtml(t)}</span>` : escapeHtml(t);
    };
    for (const m of last.matchAll(ESCAPE)) {
      emit(last.slice(at, m.index));
      if (m[2] === 'm') applySgr(style, m[1]);
      at = m.index + m[0].length;
    }
    emit(last.slice(at));
    widest = Math.max(widest, cols);
    return html;
  });
  return { html: out.join('\n'), widest, hidden: lines.length - shown.length };
}

const SANS = '-apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji"';
const MONO = 'ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace';

export function terminalDocument({ text, prompt, title, columns = 120, maxLines = 200 }) {
  const body = ansiToHtml(text, maxLines);
  const promptLine = prompt ? `<span class="prompt">$</span> ${escapeHtml(prompt)}\n` : '';
  const more = body.hidden > 0 ? `\n<span class="more">[${body.hidden} more line(s) not shown]</span>` : '';
  const width = Math.max(40, Math.min(columns, Math.max(body.widest, prompt ? [...prompt].length + 2 : 0)));
  return `<!doctype html>
<html><head><meta charset="utf-8"><style>
html, body { margin: 0; background: transparent; }
.terminal { display: inline-block; background: ${TERM_BG}; border-radius: 8px; overflow: hidden; border: 1px solid #3c3c3c; }
.bar { position: relative; height: 28px; background: #323233; }
.dots { position: absolute; left: 12px; top: 8px; display: flex; gap: 8px; }
.dots span { width: 12px; height: 12px; border-radius: 50%; }
.title { margin: 0 72px; line-height: 28px; text-align: center; color: #cccccc; font: 12px/28px ${SANS}; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
pre { margin: 0; padding: 12px 16px 14px; width: ${width}ch; color: ${TERM_FG}; font: 13px/1.4 ${MONO}; white-space: pre-wrap; overflow-wrap: anywhere; tab-size: ${TAB}; }
.prompt { color: #23d18b; }
.more { color: #8b8b8b; font-style: italic; }
</style></head><body><div class="terminal" id="surface"><div class="bar"><div class="dots"><span style="background:#ff5f57"></span><span style="background:#febc2e"></span><span style="background:#28c840"></span></div><div class="title">${escapeHtml(title ?? '')}</div></div><pre>${promptLine}${body.html}${more}</pre></div></body></html>`;
}

// ── A rendered comment ────────────────────────────────────────────────────

// GitHub's comment styles (Primer, light theme) for the elements its markdown
// renderer emits.
const MARKDOWN_CSS = `
.markdown-body { font-family: ${SANS}; font-size: 14px; line-height: 1.5; color: #1f2328; word-wrap: break-word; }
.markdown-body > *:first-child { margin-top: 0 !important; }
.markdown-body > *:last-child { margin-bottom: 0 !important; }
.markdown-body p, .markdown-body blockquote, .markdown-body ul, .markdown-body ol, .markdown-body dl,
.markdown-body table, .markdown-body pre, .markdown-body details { margin-top: 0; margin-bottom: 16px; }
.markdown-body a { color: #0969da; text-decoration: underline; text-underline-offset: .2rem; }
.markdown-body a.user-mention, .markdown-body a.team-mention { font-weight: 600; color: #1f2328; text-decoration: none; }
.markdown-body strong, .markdown-body b { font-weight: 600; }
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
.markdown-body hr { box-sizing: content-box; height: .25em; padding: 0; margin: 24px 0; overflow: hidden; background-color: #d1d9e0; border: 0; }
.markdown-body table { display: block; width: max-content; max-width: 100%; overflow: auto; border-spacing: 0; border-collapse: collapse; font-variant: tabular-nums; }
.markdown-body table th { font-weight: 600; }
.markdown-body table th, .markdown-body table td { padding: 6px 13px; border: 1px solid #d1d9e0; }
.markdown-body table tr { background-color: #ffffff; border-top: 1px solid #d1d9e0b3; }
.markdown-body table tr:nth-child(2n) { background-color: #f6f8fa; }
.markdown-body img { max-width: 100%; box-sizing: content-box; background-color: #ffffff; }
.markdown-body details summary { cursor: pointer; }
.markdown-body kbd { display: inline-block; padding: 4px; font: 11px ${MONO}; line-height: 10px; color: #1f2328; vertical-align: middle; background-color: #f6f8fa; border: 1px solid #d1d9e0b3; border-radius: 6px; box-shadow: inset 0 -1px 0 #d1d9e0b3; }
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
  if (opts.kind === 'terminal') {
    return terminalDocument({
      text: readFileSync(opts.text, 'utf8'),
      prompt: opts.prompt,
      title: opts.title,
      columns: opts.columns ? Number(opts.columns) : undefined,
      maxLines: opts['max-lines'] ? Number(opts['max-lines']) : undefined,
    });
  }
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

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    process.exitCode = main(process.argv.slice(2));
  } catch (e) {
    console.error(`${PROG}: ${e?.message?.split('\n')[0] ?? e}`);
    process.exitCode = 1;
  }
}
