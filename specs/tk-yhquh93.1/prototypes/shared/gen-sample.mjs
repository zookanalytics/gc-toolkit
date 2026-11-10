#!/usr/bin/env node
// gen-sample.mjs writes the sample board the design prototypes read.
//
// The board is invented, so no rig's work reaches this public repository, and
// its proportions follow the live board as it stood on 2026-11-10 at 06:00Z:
// about as many rows closed in the last week as open, a third of the open rows
// owed to the operator (most of them green pull requests and decisions), half
// of the open rows parked work that sits in no epic, and almost every open row
// in a family of its own. Every field is a field of today's board contract
// (services/helm/web/src/contract.ts), so the same board renders today's page
// through helm-fixture and the prototypes side by side.
//
// Usage:
//   node gen-sample.mjs                      write sample-board.js beside this file
//   node gen-sample.mjs --json [--now <t>]   print the board envelope, for helm-fixture
//                                            --board, with every time shifted so the
//                                            board was read at <t> (RFC 3339)
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const nowArg = process.argv.indexOf('--now');
const NOW = Date.parse(nowArg > 0 ? process.argv[nowArg + 1] : '2026-11-10T06:00:00Z');
let seed = 20261110;
function rnd() {
  seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const int = (lo, hi) => lo + Math.floor(rnd() * (hi - lo + 1));
const iso = (hoursAgo) => new Date(NOW - hoursAgo * 3600e3).toISOString().replace(/\.\d+Z$/, 'Z');
const ago = (h) => (h < 24 ? `${h}h` : `${Math.round(h / 24)}d`);

const PREFIX = { 'gc-toolkit': 'tk', gascity: 'gc', 'rig-a': 'ra', 'rig-b': 'rb', 'rig-c': 'rc' };
const used = new Set();
function newId(rig) {
  const abc = 'abcdefghijklmnopqrstuvwxyz0123456789';
  for (;;) {
    let s = '';
    for (let i = 0; i < 6; i++) s += abc[int(0, 35)];
    const id = `${PREFIX[rig]}-${s}`;
    if (!used.has(id)) {
      used.add(id);
      return id;
    }
  }
}
const prSeq = { 'gc-toolkit': 1398, gascity: 2210, 'rig-a': 341, 'rig-b': 188, 'rig-c': 77 };
const nextPR = (rig) => (prSeq[rig] += int(1, 3));
const ORG = 'https://github.com/example-org';
const PARK_GATE = 'tk-pk0001';

// tile returns a row with every contract field, in the contract's order.
function tile(o) {
  const t = {
    id: '', rig: '', kind: '', title: '', severity: 'NORMAL', owed: false, weight: 1, held: false,
    sitting_state: '', n_closed: 0, m_total: 0, open: 0, in_progress: 0, assigned: 0,
    in_progress_live: 0, in_progress_dead: 0, dead_owner: false, in_flight: 0, in_flight_heads: [],
    owned: null, stranded: false, empty: false, complete: false, stale_days: 0, priority: 2,
    cross_rig_refs: [], open_heads: [], dead_owner_heads: [], parked_heads: [], waiting_on: [],
    waiting_on_open: [], disposition_due: false, takeaway: null, takeaway_at: null, takeaway_by: null,
    updated_at: undefined, closed_at: undefined, frontier: '', needs: '', rank_score: 0,
    pr_number: 0, pr_url: '', pr_branch: '', pr_machine: '', pr_conversation: '', pr_approval: '',
    pr_owed_since: undefined, section: 'active', cluster_key: undefined, group_root: '',
    group_parent: '', acceptable: false, accept_formula: '', pr_branch_url: '', pr_phase: '',
    phase: 'working', recommendation: null, accept_withheld: null, gates_in_session: null,
    sitting_start_failure: '', pr_held: null, work_held: false,
  };
  Object.assign(t, o);
  if (!t.group_root) t.group_root = t.id;
  return t;
}

function prFields(rig, id) {
  const n = nextPR(rig);
  return {
    pr_number: n,
    pr_url: `${ORG}/${rig}/pull/${n}`,
    pr_branch: `polecat/${id}`,
    pr_branch_url: `${ORG}/${rig}/tree/polecat/${id}`,
  };
}

const sittings = [];
function sitting(row, state, headline, hoursOpen) {
  const s = {
    id: newId(row.rig),
    rig: row.rig,
    subject: row.id,
    title: headline,
    outcome_reason: state === 'closed' ? headline : '',
    session: state === 'in_session' ? `converse-${row.id.slice(3, 7)}` : '',
    opened_at: iso(hoursOpen),
    takeaway: state === 'closed' ? headline : '',
    subject_title: row.title,
    state,
    headline,
  };
  if (state === 'closed') s.closed_at = iso(Math.max(1, hoursOpen - 2));
  else delete s.closed_at;
  sittings.push(s);
}

// Each row kind below is one shape the live board serves, with the sentences
// its derivation writes.
const make = {
  review(rig, title, p, h = int(3, 260)) {
    const id = newId(rig);
    const pr = prFields(rig, id);
    return tile({
      id, rig, kind: 'merge', title, priority: p, severity: 'ELEVATED', owed: true, section: 'review',
      phase: 'needs-review', pr_phase: 'needs-review', ...pr, pr_machine: 'settled',
      pr_conversation: 'quiet', pr_approval: 'required', pr_owed_since: iso(h), updated_at: iso(1),
      needs: 'green, waiting on your review', frontier: `needs-review · PR #${pr.pr_number} · owed ${ago(h)}`,
    });
  },
  answered(rig, title, p, h = int(5, 90)) {
    const row = make.review(rig, title, p, h);
    row.pr_conversation = 'answered';
    row.needs = 'your comments are answered on the branch — re-review';
    return row;
  },
  prAsk(rig, title, p, ask, h = int(10, 200)) {
    const row = make.review(rig, title, p, h);
    Object.assign(row, {
      phase: 'needs-attention', pr_phase: 'needs-attention', pr_held: ['gate'], held: true,
      work_held: true, sitting_state: 'waiting', needs: `asking: ${ask}`, severity: 'HIGH',
      frontier: `needs-attention · PR #${row.pr_number} · held: gate`,
    });
    return row;
  },
  decision(rig, title, p, h = int(20, 400)) {
    return tile({
      id: newId(rig), rig, kind: 'decision', title, priority: p, severity: 'ELEVATED', owed: true,
      section: 'gate', held: true, work_held: true, sitting_state: 'waiting', phase: 'needs-review',
      needs: 'operator decision', frontier: 'needs-review · human-gated decision',
      pr_owed_since: iso(h), updated_at: iso(int(1, 30)),
    });
  },
  ask(rig, title, p, ask, opts = {}) {
    const h = opts.h ?? int(6, 330);
    const row = tile({
      id: newId(rig), rig, kind: 'gate', title, priority: p, severity: 'ELEVATED', owed: true,
      section: 'gate', held: true, work_held: true, sitting_state: opts.sitting ?? '',
      phase: 'needs-review', takeaway: ask, takeaway_at: iso(Math.max(1, h - 2)),
      takeaway_by: opts.by ?? 'first-reaction', needs: ask,
      frontier: 'needs-review · routed to the operator — no agent will take it',
      pr_owed_since: iso(h), updated_at: iso(int(1, Math.max(1, h))),
    });
    if (opts.accept) {
      row.acceptable = true;
      row.accept_formula = 'mol-polecat-work';
      row.recommendation = `## Proposal\n${opts.accept}\n\n## Decision needed\nAccept to dispatch it on mol-polecat-work, or discuss it first.`;
    }
    if (opts.sitting) sitting(row, opts.sitting, ask, opts.sitting === 'in_session' ? 1 : int(4, 60));
    return row;
  },
  dispose(rig, title, p, h = int(8, 200)) {
    return tile({
      id: newId(rig), rig, kind: 'parked', title, priority: p, severity: 'ELEVATED', owed: true,
      section: 'gate', disposition_due: true, phase: 'needs-review', waiting_on: [newId(rig)],
      needs: 'blocker landed — dispose or resume', frontier: 'needs-review · blocker landed',
      pr_owed_since: iso(h), updated_at: iso(h),
    });
  },
  revalidate(rig, title, p, h = int(8, 120)) {
    return tile({
      id: newId(rig), rig, kind: 'gate', title, priority: p, severity: 'ELEVATED', owed: true,
      section: 'gate', held: true, work_held: true, sitting_state: 'waiting', phase: 'needs-review',
      needs: 'proposed close did not validate: accept or redirect',
      frontier: 'needs-review · routed to the operator — no agent will take it',
      pr_owed_since: iso(h), updated_at: iso(h),
    });
  },
  conversation(rig, title, p, headline) {
    const row = tile({
      id: newId(rig), rig, kind: 'conversation', title, priority: p, severity: 'NORMAL',
      section: 'active', held: true, sitting_state: 'in_session', phase: 'working',
      needs: 'in conversation', frontier: 'working · in conversation', updated_at: iso(0),
    });
    sitting(row, 'in_session', headline, 1);
    return row;
  },
  rework(rig, title, p) {
    const id = newId(rig);
    return tile({
      id, rig, kind: 'rework', title, priority: p, section: 'active', phase: 'working',
      pr_phase: 'working', ...prFields(rig, id), pr_machine: 'progressing', pr_conversation: 'answered',
      pr_approval: 'required', in_progress_live: 1, in_flight: 1, needs: 'rework in flight',
      frontier: 'working · rework in flight', updated_at: iso(int(0, 3)),
    });
  },
  working(rig, title, p) {
    const id = newId(rig);
    const pr = prFields(rig, id);
    return tile({
      id, rig, kind: 'merge', title, priority: p, section: 'active', phase: 'working',
      pr_phase: 'working', ...pr, pr_machine: 'progressing', pr_conversation: 'quiet',
      pr_approval: 'required', in_progress_live: 1, in_flight: 1, needs: 'in flight',
      frontier: `working · PR #${pr.pr_number}`, updated_at: iso(int(0, 4)),
    });
  },
  merging(rig, title, p) {
    const row = make.working(rig, title, p);
    Object.assign(row, {
      phase: 'merging', pr_phase: 'merging', pr_approval: 'met', needs: 'approved — the city is landing it',
      frontier: `merging · PR #${row.pr_number}`,
    });
    return row;
  },
  queued(rig, title, p, behind) {
    return tile({
      id: newId(rig), rig, kind: 'parked', title, priority: p, severity: 'LOW', section: 'cleanup',
      phase: 'needs-review', waiting_on: [newId(rig)], waiting_on_open: [],
      needs: `queued behind ${behind} — starts by itself`,
      frontier: 'needs-review · queued · waiting on 1 · starts by itself', updated_at: iso(int(30, 500)),
      stale_days: int(1, 20),
    });
  },
  parked(rig, title, p) {
    return tile({
      id: newId(rig), rig, kind: 'parked', title, priority: p, severity: 'LOW', section: 'cleanup',
      phase: 'needs-review', waiting_on: [PARK_GATE], waiting_on_open: [PARK_GATE],
      needs: 'parked: Parked 2026-10-10 while steer-by-epic lands; the operator releases it',
      frontier: 'needs-review · parked · waiting on 1', updated_at: iso(int(400, 740)),
      stale_days: int(17, 30),
    });
  },
  stalled(rig, title, p) {
    const id = newId(rig);
    return tile({
      id, rig, kind: 'parked', title, priority: p, severity: 'HIGH', section: 'stalled',
      phase: 'needs-attention', stranded: true, open: 1, open_heads: [id],
      needs: 'nothing moving — assign or host', frontier: 'needs-attention · 1 open · 0 in flight (stranded)',
      updated_at: iso(int(100, 400)), stale_days: int(4, 16),
    });
  },
  done(rig, title, p, kind = 'merge') {
    const id = newId(rig);
    const h = int(2, 160);
    const row = tile({
      id, rig, kind, title, priority: p, severity: 'DONE', section: 'done', phase: '',
      closed_at: iso(h), updated_at: iso(h), needs: kind === 'merge' ? 'merged' : 'answered',
      frontier: 'closed',
    });
    if (kind === 'merge') Object.assign(row, prFields(rig, id), { pr_phase: 'merged' });
    return row;
  },
};

// The areas: each epic, its own state, and the anchors under it. A row spec is
// [maker, title, ...args]; the epic's counts cover children that are not rows.
const AREAS = [
  {
    rig: 'gc-toolkit', title: 'Steer by epic', p: 1, state: 'gate', m: 26, closed: 15,
    takeaway: 'Unit 6 is in review; units 7 and 8 start when it lands. Two holds need your ruling.',
    kids: [
      ['review', 'Hold new work on the platform hold, worked by the po'],
      ['review', "Read an ancestor epic's hold before dispatch"],
      ['ask', 'Release order for the parked queue', 'The parked queue holds 31 beads: release them in epic priority order, or all at once?', { sitting: 'in_session', by: 'converse' }],
      ['decision', 'Whether the po may re-prioritize inside an epic'],
      ['rework', 'Move the hold reads onto one Go reader'],
      ['working', 'Stamp the epic ruling on every member'],
      ['queued', 'Retire the placement marker readers', 'the platform hold'],
      ['queued', 'Doctor check for beads carrying a stale hold', 'the platform hold'],
      ['done', 'Retire the placement marker and flag beads carrying it'],
      ['done', 'Hold a pre-PR bead with its human gate alone'],
      ['done', 'Name what holds each parked bead on the board'],
    ],
  },
  {
    rig: 'gc-toolkit', title: 'Built-once migration', p: 1, state: 'active', m: 64, closed: 41,
    takeaway: 'Batch B is landing; the board reader and the parity test retire next.',
    kids: [
      ['merging', 'Retire the escalation hand-offs'],
      ['working', 'Read the board through the supervisor API only'],
      ['working', 'Retire the contract parity test and the TypeScript mirror'],
      ['review', 'Move the incident ledger onto events'],
      ['answered', 'Retire the liveness census gates'],
      ['dispose', 'Retire the gc-helm verbs that only call Gas City'],
      ['stalled', 'Dated warrant for the store reader'],
      ['done', 'Trust a bd write exit, and refuse a wait across two stores'],
      ['done', 'Retire the terminal board and its tmux menus'],
      ['done', 'Retire the stored lane marker'],
      ['done', 'Retire the round-cap leftovers'],
    ],
    subs: [
      {
        title: 'Native gates cutover', p: 1, state: 'active', m: 12, closed: 9,
        takeaway: 'Gates are native; two readers still read the old route stamp.',
        kids: [
          ['working', 'Drop the route stamp from the gate readers'],
          ['review', 'Name every human gate that holds a PR'],
          ['revalidate', 'Close the migrated visit beads'],
          ['done', 'Move the city questions onto native human gates'],
          ['done', 'A discussion becomes a conversation that holds nothing'],
        ],
      },
    ],
  },
  {
    rig: 'rig-a', title: 'Checkout rebuild', p: 1, state: 'active', m: 18, closed: 7,
    takeaway: 'Saved-card payments fail in one region; the fallback is ready if you want it now.',
    kids: [
      ['ask', 'Saved-card fallback for the EU region', 'Payments with saved cards fail for EU users: ship the fallback now, or wait for the provider fix (due Friday)?', { sitting: 'waiting', by: 'converse', h: 30 }],
      ['review', 'Address form validation rewrite'],
      ['review', 'One-page checkout behind a flag'],
      ['working', 'Tax calculation service client'],
      ['working', 'Order summary component'],
      ['rework', 'Cart persistence across devices'],
      ['queued', 'Remove the legacy checkout routes', 'one-page checkout'],
      ['done', 'Payment step error states'],
      ['done', 'Shipping method picker'],
    ],
  },
  {
    rig: 'rig-b', title: 'Billing migration', p: 1, state: 'gate', m: 15, closed: 5,
    takeaway: 'Blocked on the provider agreement; nothing moves until it is signed.',
    kids: [
      ['ask', 'Data-processing agreement for the new provider', 'The provider switch needs a signed data-processing agreement before any card data moves. Sign it, or pause the migration?', { h: 190, by: 'converse', sitting: 'waiting' }],
      ['decision', 'Proration rule for mid-cycle plan changes'],
      ['review', 'Invoice PDF renderer'],
      ['done', 'Export the current plans and prices'],
    ],
    subs: [
      {
        title: 'Payment provider switch', p: 1, state: 'stalled', m: 6, closed: 1,
        takeaway: null,
        kids: [
          ['stalled', 'Webhook receiver for the new provider'],
          ['stalled', 'Dual-write customer records'],
          ['queued', 'Cut over recurring charges', 'the data-processing agreement'],
        ],
      },
    ],
  },
  {
    rig: 'gc-toolkit', title: 'Board UI design', p: 2, state: 'active', m: 3, closed: 0,
    takeaway: 'Three prototype directions are ready for your reaction.',
    kids: [
      ['conversation', 'Board design pass: pick the direction', 'Which direction should the board take: Briefing, Portfolio or Canvas?'],
      ['queued', 'Build the board design', 'the design pass'],
      ['queued', 'Write the effort summary', 'the build'],
    ],
  },
  {
    rig: 'gc-toolkit', title: 'Where things stand', p: 2, state: 'gate', m: 9, closed: 3,
    takeaway: 'Three members are parked for you; the held-PR row is approved and conflicting.',
    kids: [
      ['prAsk', "Read a PR whose work waits on a person as held", 'rebase onto main, or close in favour of the new reader?'],
      ['decision', 'Whether closed anchors stay a week or a day'],
      ['parkedKid', 'Progress only where it means something'],
      ['parkedKid', 'Visit lifecycle state: engaged or waiting'],
      ['done', 'Show a landed delivery as waiting for its checkpoint'],
    ],
  },
  {
    rig: 'gc-toolkit', title: 'What needs you', p: 2, state: 'cleanup', m: 5, closed: 0,
    takeaway: null,
    kids: [
      ['parkedKid', 'Most important first in the owed list'],
      ['parkedKid', 'Clear an ask once it is answered'],
      ['parkedKid', 'A green PR that conflicts is not ready for you'],
    ],
  },
  {
    rig: 'gc-toolkit', title: 'Merge cadence', p: 2, state: 'active', m: 14, closed: 10,
    takeaway: null,
    kids: [
      ['review', 'Pace the pr-open arm on its own rotation'],
      ['working', 'Bring a stage current by merge, never rebase'],
      ['merging', 'Hold a PR while a conversation on it is open'],
      ['done', 'Explicit lease on every push'],
      ['done', 'Draft PRs read working until flipped ready'],
    ],
  },
  {
    rig: 'gc-toolkit', title: 'Review lanes', p: 2, state: 'active', m: 11, closed: 6,
    takeaway: null,
    kids: [
      ['review', 'Demo check delivers every message the app sends'],
      ['ask', 'Lane order after a conflicted merge-in', "A merge-in conflicted on the review formula: keep the branch's lane order or main's?", { h: 52 }],
      ['done', 'Triage records each added check'],
    ],
    subs: [
      {
        title: 'Lane pipeline', p: 2, state: 'active', m: 5, closed: 3,
        takeaway: null,
        kids: [
          ['working', 'Run the checks as lanes of one formula'],
          ['queued', 'Retire the per-check formulas', 'the lane formula'],
        ],
      },
    ],
  },
  {
    rig: 'gascity', title: 'Session lifecycle', p: 2, state: 'active', m: 9, closed: 4,
    takeaway: null,
    kids: [
      ['ask', 'Idle sleep versus always-on patrols', 'Waking on idle conflicts with always-on patrols: which wins for named sessions?', { h: 75 }],
      ['working', 'Resume a slept session with its conversation'],
      ['review', 'Fingerprint drift restarts only drifted sessions'],
      ['done', 'Release a claim by assignee on close'],
    ],
  },
  {
    rig: 'gascity', title: 'Supervisor API reads', p: 2, state: 'stalled', m: 7, closed: 2,
    takeaway: null,
    kids: [
      ['stalled', 'Serve updated_at on the beads list'],
      ['stalled', 'Filter the beads list by parent'],
      ['ask', 'Retire the direct store reader', 'The API serves updated_at since 1.4: retire the board\'s direct store reader now?', { h: 140, accept: 'Retire the direct store reader and read the board through the supervisor API.' }],
    ],
  },
  {
    rig: 'rig-a', title: 'Search relevance', p: 2, state: 'gate', m: 8, closed: 3,
    takeaway: 'The ranking test finished; B wins on clicks and loses on speed.',
    kids: [
      ['ask', 'Ship ranking B', 'Ranking B lifts clicks 4% but slows p95 by 80 ms: ship B, or tune it first?', { h: 22, by: 'converse' }],
      ['working', 'Synonym table for product names'],
      ['done', 'Click-through logging'],
    ],
  },
  {
    rig: 'rig-b', title: 'Mobile onboarding', p: 2, state: 'stalled', m: 10, closed: 4,
    takeaway: null,
    kids: [
      ['ask', 'Third onboarding screen', 'The third screen loses 18% of new users: redesign it, or cut it?', { h: 260 }],
      ['stalled', 'Permission prompt timing'],
      ['stalled', 'Skip button on every screen'],
      ['done', 'Welcome screen copy'],
    ],
  },
  {
    rig: 'gc-toolkit', title: 'Patrol on core orders', p: 3, state: 'cleanup', m: 8, closed: 2,
    takeaway: null,
    kids: [
      ['queued', "Move the witness's sweep onto a core order", 'patrols'],
      ['queued', "Move the deacon's doctor run onto a core order", 'patrols'],
      ['parkedKid', 'Retire the pack reaper for review workspaces'],
    ],
  },
  {
    rig: 'gc-toolkit', title: 'Demo capture', p: 3, state: 'cleanup', m: 6, closed: 6,
    takeaway: null,
    kids: [['done', 'Show each message the app sends']],
  },
  {
    rig: 'gc-toolkit', title: 'Feedback learning loop', p: 3, state: 'active', m: 7, closed: 5,
    takeaway: null,
    kids: [
      ['working', "Distill this week's observations"],
      ['review', 'Promote two standing rules'],
    ],
  },
  {
    rig: 'rig-c', title: 'Data pipeline', p: 3, state: 'active', m: 9, closed: 5,
    takeaway: null,
    kids: [
      ['ask', 'Nightly job window', 'The nightly job overran twice this week: widen its window, or split it in two?', { h: 40 }],
      ['working', 'Backfill the events table'],
      ['done', 'Schema for the orders feed'],
    ],
  },
  {
    rig: 'rig-c', title: 'Docs site refresh', p: 4, state: 'cleanup', m: 4, closed: 4,
    takeaway: null,
    kids: [],
  },
];

make.parkedKid = (rig, title, p) => make.parked(rig, title, p);

// Work outside any epic: a family of its own per row, as most live rows are.
const LOOSE = {
  'gc-toolkit': {
    parked: [
      'Engagement trail on each conversation', 'Board search box', 'Doctor check for orphan arms',
      'One reader for the rig map', 'Skill for retiring a name', 'Lint the formula step sizes',
      'Merge-tree survey before a bring-current', 'Rename the takeaway field', 'Session title on resume',
      'Scratch reclaim for review workspaces', 'Hand-back with one guarded write', 'Cap the transcript scan',
      'Escalation re-file keys', 'Pool claim order by priority', 'Fork sync checklist',
      'Template rename keeps old sessions', 'Codex model probe in a clean env', 'One lock path from the city root',
      'Stale census visit sweep', 'Arm a sibling on one landing', 'Report the dolt reclaim window',
      'Gate notify off by default', 'Warrant index for the doctor', 'Retire the convoy cleanup order',
      'Queue priority in the creator suites', 'Settle seam for the tool shim', 'Package the pack for a second city',
      'Explain a held step on the board', 'Note times from the clock', 'Read a session id by its type',
    ],
    queued: [
      "Witness HELP triage on a core order", "Deacon's doctor run on a core order", 'Retire the patrol continue wisp',
      'Space an always-on patrol with defer', 'Recycle a stale patrol session on pack drift', 'Move the incident notes onto events',
    ],
    dispose: [
      'Follow-up on the claim release rework', 'Clean the leftover review workspaces', 'Re-run the arm survey',
      'Repair the scratch city recipe', 'Re-check the bring-current audit text',
    ],
    review: [
      'Name a re-run, not a write, when a sitting never starts', 'Start and return to conversations from one form',
      'Run the Fable sitting on the new model', 'Flag beads carrying the retired marker',
      'Warn when a step grows past the hook cap', 'Trust bd exits in the merge path',
    ],
    decision: ['Whether the mayor keeps a coded role', 'Whether review time counts as a cost', 'Keep or drop the CLI board', 'One converse pool or two'],
    asks: [
      ['A one-line fix was routed to the wrong pool', 'A proven one-line fix was routed to another rig\'s pool: move it here, or close it there?'],
      ['Alert monitors under your sign-in', 'Apply the alert monitors under your own sign-in; the city cannot hold that credential.'],
      ['Branch with no change against main', 'The branch introduces no change against main: close the bead, or name what was lost?'],
      ['Weekly digest', 'The weekly digest repeats the board: stop sending it?'],
      ['Canvas epic leftovers', "Close the canvas epic's three leftover beads as moot?"],
      ['Board word for parked', "Rename 'parked' on the board to 'held for you'?"],
    ],
    revalidate: ['Close the duplicate reaper bead', 'Close the stale fork-sync bead'],
  },
  gascity: {
    parked: ['Typed 400 for a legacy cursor', 'Event payload filter for orders', 'Batch the session list read', 'Wisp compaction metrics', 'Rig rename keeps the prefix', 'Order trigger on bead close', 'Reaper skips attached sessions', 'Mail recipients include session names'],
    review: ['Order event triggers carry the payload', 'Session rename event', 'Gate list by await type'],
    asks: [['Upstream sync cadence', 'The fork is 40 commits behind upstream: rebase this week, or after the release?']],
  },
  'rig-a': {
    parked: ['Gift card balance check', 'Wishlist sharing', 'Recently viewed carousel', 'Store locator map', 'Price drop alerts', 'Bundle discounts', 'Guest order lookup', 'Size guide overlay', 'Product Q&A', 'Back-in-stock email'],
    review: ['Image CDN for product photos', 'Coupon code field', 'Faster category pages'],
    decision: ['Free shipping threshold'],
    asks: [['Black Friday freeze', 'Freeze deploys from the 24th to the 1st, or keep shipping behind flags?']],
  },
  'rig-b': {
    parked: ['Dark mode', 'Biometric sign-in', 'Offline drafts', 'Share sheet', 'Tablet layout', 'Push opt-in screen', 'Crash-free rate dashboard', 'App store screenshots', 'Haptics on save'],
    decision: ['Minimum OS version', 'Rating prompt frequency'],
    asks: [['Beta testers', 'Open the beta to 500 more testers, or hold at 100 until crashes drop?']],
  },
  'rig-c': {
    parked: ['Search for the docs site', 'Versioned API pages', 'Changelog feed', 'Broken link checker', 'Code sample tabs'],
    review: ['Retry policy for the loader'],
    asks: [['Retention for raw events', 'Keep raw events 90 days or 30? Storage doubles at 90.']],
  },
};

const tiles = [];
function addArea(a, parent, top) {
  const rig = parent ? parent.rig : a.rig;
  const id = parent ? `${parent.id}.${parent.nextChild++}` : newId(rig);
  used.add(id);
  const epic = tile({
    id, rig, kind: 'epic', title: a.title, priority: a.p, m_total: a.m, n_closed: a.closed,
    group_root: top ? top.id : id, group_parent: parent ? parent.id : '', updated_at: iso(int(1, 60)),
    takeaway: a.takeaway ?? null, takeaway_at: a.takeaway ? iso(int(3, 40)) : null,
    takeaway_by: a.takeaway ? 'converse' : null,
  });
  epic.nextChild = 1;
  tiles.push(epic);
  const rows = [];
  for (const [kind, title, ...args] of a.kids) {
    const row = make[kind](rig, title, a.p, ...args);
    const childId = `${id}.${epic.nextChild++}`;
    used.add(childId);
    for (const s of sittings) if (s.subject === row.id) s.subject = childId;
    if (row.pr_branch) {
      row.pr_branch = `polecat/${childId}`;
      row.pr_branch_url = `${ORG}/${rig}/tree/polecat/${childId}`;
    }
    if (row.open_heads.length) row.open_heads = [childId];
    row.id = childId;
    row.group_root = top ? top.id : id;
    row.group_parent = id;
    rows.push(row);
    tiles.push(row);
  }
  for (const sub of a.subs ?? []) rows.push(...addArea(sub, epic, top ?? epic));
  const live = rows.filter((r) => r.section !== 'done' && r.kind !== 'epic');
  const open = a.m - a.closed;
  epic.open = open;
  epic.in_progress_live = live.filter((r) => r.phase === 'working' || r.phase === 'merging').length;
  epic.in_progress = epic.in_progress_live;
  epic.in_flight = epic.in_progress_live;
  epic.in_flight_heads = live.filter((r) => r.in_flight).map((r) => r.id);
  epic.parked_heads = live.filter((r) => r.owed || r.kind === 'parked').map((r) => r.id);
  epic.open_heads = live.filter((r) => r.stranded).map((r) => r.id);
  epic.complete = a.m === a.closed;
  epic.stale_days = a.state === 'stalled' ? int(5, 14) : 0;
  epic.weight = a.m + (5 - a.p) * 4;
  const owedKids = live.filter((r) => r.owed).length;
  const states = {
    active: [`nothing idle — ${epic.in_progress_live} in flight`, 'NORMAL', 'working'],
    gate: [`${owedKids || 1} parked for the operator — release or rule on them`, 'ELEVATED', 'needs-review'],
    stalled: ['decomposed, idle — assign or host', 'HIGH', 'needs-attention'],
    cleanup: epic.complete
      ? [`all ${a.m} closed — close or extend`, 'LOW', 'needs-review']
      : [`${open} open · parked behind the new-work pause`, 'LOW', 'needs-review'],
  };
  const [needs, severity, phase] = states[a.state];
  Object.assign(epic, {
    section: a.state, severity, phase, needs: a.takeaway ?? needs, stranded: a.state === 'stalled',
    owed: a.state === 'gate', pr_owed_since: a.state === 'gate' ? iso(int(20, 200)) : undefined,
    held: a.state === 'gate', work_held: a.state === 'gate',
    frontier: `${phase} · ${open} open · ${epic.in_progress_live} in flight${a.state === 'stalled' ? ' (stranded)' : ''}`,
  });
  delete epic.nextChild;
  return rows;
}
for (const a of AREAS) addArea(a, null, null);

for (const [rig, sets] of Object.entries(LOOSE)) {
  const p = () => int(2, 3);
  for (const t of sets.parked ?? []) tiles.push(make.parked(rig, t, int(2, 4)));
  for (const t of sets.queued ?? []) tiles.push(make.queued(rig, t, 3, 'patrols: move witness and deacon duties onto core orders'));
  for (const t of sets.dispose ?? []) tiles.push(make.dispose(rig, t, p()));
  for (const t of sets.review ?? []) tiles.push(make.review(rig, t, p()));
  for (const t of sets.decision ?? []) tiles.push(make.decision(rig, t, p()));
  for (const [t, ask] of sets.asks ?? []) tiles.push(make.ask(rig, t, p(), ask, { sitting: rnd() < 0.4 ? 'waiting' : '' }));
  for (const t of sets.revalidate ?? []) tiles.push(make.revalidate(rig, t, p()));
}
const LOOSE_DONE = [
  ['gc-toolkit', 'Retire the CLI board legend'], ['gc-toolkit', 'Explicit lease on the bring-current push'],
  ['gc-toolkit', 'Session list liveness read'], ['gc-toolkit', 'Hook cap measure in the step lint'],
  ['gc-toolkit', 'Fold the visit rows into conversations'], ['gc-toolkit', 'Rig map timeout'],
  ['gascity', 'Gate await types'], ['gascity', 'Claim release by assignee'],
  ['rig-a', 'Cart badge count'], ['rig-a', 'Checkout analytics events'], ['rig-b', 'Splash screen timing'],
  ['rig-c', 'Loader retries'],
];
for (const [rig, t] of LOOSE_DONE) tiles.push(make.done(rig, t, 3));
for (let i = 0; i < 9; i++) {
  const row = make.done('gc-toolkit', `Answered: ${['merge order', 'pool split', 'lane rename', 'park release', 'fork sync', 'review budget', 'digest', 'board legend', 'canvas'][i]}`, 2, 'decision');
  tiles.push(row);
}

// The recent conversation record: sittings that ended in the last day.
const CLOSED_TALKS = [
  ['Board UI design', 'Released the design pass at P2 and filed the Board UI design epic'],
  ['Board UI design', 'Closed the Attention Canvas epic; its idea moves to the design pass'],
  ['Where things stand', 'Split the board epic into Where things stand and What needs you'],
  ['Where things stand', 'Kept the CLI board retired; the web page is the one view'],
  ['Steer by epic', 'Ruled the hold reader moves onto Go'],
  ['Feedback learning loop', 'Dismissed: the digest question is moot'],
];
for (const [epic, h] of CLOSED_TALKS) sitting(tiles.find((t) => t.kind === 'epic' && t.title === epic), 'closed', h, int(6, 22));

// cluster_key: a needs sentence three or more rows of one section share.
const bySection = new Map();
for (const t of tiles) {
  const key = `${t.section}\u0000${t.needs}`;
  bySection.set(key, (bySection.get(key) ?? 0) + 1);
}
for (const t of tiles) if (bySection.get(`${t.section}\u0000${t.needs}`) >= 3 && t.section !== 'done') t.cluster_key = t.needs;

const SEV = { HIGH: 400, ELEVATED: 300, NORMAL: 200, LOW: 100, DONE: 0 };
for (const t of tiles) t.rank_score = SEV[t.severity] + t.weight + (5 - (t.priority ?? 4));

// The wire's order: owed rows oldest-owed first, then the rest by rank, closed last.
const owed = tiles.filter((t) => t.owed).sort((a, b) => a.pr_owed_since.localeCompare(b.pr_owed_since));
const rest = tiles
  .filter((t) => !t.owed && t.section !== 'done')
  .sort((a, b) => b.rank_score - a.rank_score);
const done = tiles.filter((t) => t.section === 'done').sort((a, b) => b.closed_at.localeCompare(a.closed_at));
const ordered = [...owed, ...rest, ...done];

const board = {
  generated_at: iso(0),
  total: ordered.length,
  tiles: ordered,
  sittings: [
    ...sittings.filter((s) => s.state !== 'closed').sort((a, b) => a.opened_at.localeCompare(b.opened_at)),
    ...sittings.filter((s) => s.state === 'closed').sort((a, b) => b.closed_at.localeCompare(a.closed_at)),
  ],
  pack_health: [
    {
      component: 'helm', built_at: iso(2), source_rev: 'f9ed6bf', binary_rev: 'f9ed6bf', last_build_rc: 0,
      restart_pending: false, probe_status: 'ok', checked_at: iso(0), severity: 'LOW', detail: 'serving f9ed6bf',
    },
    {
      component: 'gctk', built_at: iso(9), source_rev: 'f9ed6bf', binary_rev: '545b605', last_build_rc: 2,
      restart_pending: false, probe_status: 'ok', checked_at: iso(0), severity: 'ELEVATED',
      detail: 'the last build failed (exit 2); serving 545b605',
    },
  ],
};

if (process.argv.includes('--json')) {
  process.stdout.write(`${JSON.stringify(board, null, 1)}\n`);
} else {
  // The prototypes' copy leaves out each tile field that holds its empty
  // default, which model.js restores, so the file stays small.
  const blank = tile({ id: 'x' });
  const lean = {
    ...board,
    tiles: board.tiles.map((t) =>
      Object.fromEntries(
        Object.entries(t).filter(([k, v]) => k === 'id' || JSON.stringify(v) !== JSON.stringify(blank[k])),
      ),
    ),
  };
  const here = dirname(fileURLToPath(import.meta.url));
  writeFileSync(
    join(here, 'sample-board.js'),
    `// Written by gen-sample.mjs; edit that, not this. Today's board envelope, each tile's empty defaults left out.\nwindow.SAMPLE_BOARD = ${JSON.stringify(lean)};\n`,
  );
  const open = ordered.filter((t) => t.section !== 'done');
  process.stderr.write(
    `sample-board.js: ${open.length} open rows (${owed.length} owed), ${done.length} closed, ${board.sittings.length} sittings\n`,
  );
}
