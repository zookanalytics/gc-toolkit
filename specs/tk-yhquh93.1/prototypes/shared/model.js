// model.js turns today's board envelope into what every direction draws: areas
// (the epics, nested, then the work in no epic, by rig), each row's state, and
// the asks. It reads only fields today's board serves (contract.ts); where a
// direction mocks something the board does not serve, its own file says so.
(function () {
  'use strict';

  const DEFAULTS = {
    severity: 'NORMAL', owed: false, weight: 1, held: false, sitting_state: '', n_closed: 0, m_total: 0,
    open: 0, in_progress: 0, assigned: 0, in_progress_live: 0, in_progress_dead: 0, dead_owner: false,
    in_flight: 0, in_flight_heads: [], owned: null, stranded: false, empty: false, complete: false,
    stale_days: 0, priority: 2, cross_rig_refs: [], open_heads: [], dead_owner_heads: [], parked_heads: [],
    waiting_on: [], waiting_on_open: [], disposition_due: false, takeaway: null, takeaway_at: null,
    takeaway_by: null, frontier: '', needs: '', rank_score: 0, pr_number: 0, pr_url: '', pr_branch: '',
    pr_machine: '', pr_conversation: '', pr_approval: '', section: 'active', group_root: '',
    group_parent: '', acceptable: false, accept_formula: '', pr_branch_url: '', pr_phase: '',
    phase: 'working', recommendation: null, accept_withheld: null, gates_in_session: null,
    sitting_start_failure: '', pr_held: null, work_held: false,
  };

  // The six states a row reads as, in the order a bar draws them.
  const STATES = ['done', 'moving', 'you', 'stuck', 'queued', 'held'];
  const STATE_WORDS = {
    done: 'landed',
    moving: 'moving',
    you: 'needs you',
    stuck: 'stuck',
    queued: 'queued',
    held: 'on hold',
  };

  // stateOf reads one row: owed first, because it is the operator's own queue.
  function stateOf(t) {
    if (t.section === 'done') return 'done';
    if (t.owed) return 'you';
    if (t.section === 'stalled' || t.stranded || t.dead_owner) return 'stuck';
    if (t.section === 'active') return 'moving';
    if (/^queued/.test(t.needs)) return 'queued';
    return 'held';
  }

  // verbOf is the move an ask asks for, read from wire fields alone: approve a
  // pull request in review, clear a hold whose blockers all landed, or decide.
  function verbOf(t) {
    if (t.pr_number && t.section === 'review') return 'approve';
    if (t.disposition_due) return 'clear';
    return 'decide';
  }
  const VERB_WORDS = { approve: 'Approve', decide: 'Decide', clear: 'Clear' };

  // attentionOf answers "has it had my attention" from the sitting state and
  // the takeaway's author, both on the wire today.
  function attentionOf(t, now) {
    if (t.sitting_state === 'in_session') return { key: 'live', words: 'with you now' };
    if (t.sitting_state === 'start-failed') return { key: 'failed', words: 'sitting failed to start' };
    if (t.sitting_state === 'waiting') return { key: 'waiting', words: 'conversation waiting' };
    if (t.takeaway_by === 'converse' && t.takeaway_at) {
      return { key: 'seen', words: `discussed ${ageWords(now - Date.parse(t.takeaway_at))} ago` };
    }
    return { key: 'new', words: 'not discussed yet' };
  }

  function ageWords(ms) {
    const h = Math.max(0, Math.round(ms / 3600e3));
    if (h < 1) return 'minutes';
    if (h < 24) return `${h}h`;
    const d = Math.round(h / 24);
    return d === 1 ? '1 day' : `${d} days`;
  }
  function shortAge(ms) {
    const h = Math.max(0, Math.round(ms / 3600e3));
    if (h < 24) return `${h}h`;
    return `${Math.round(h / 24)}d`;
  }

  // An area's hue comes from its id, so it keeps its color across visits.
  function hueOf(id) {
    let h = 2166136261;
    for (let i = 0; i < id.length; i++) h = Math.imul(h ^ id.charCodeAt(i), 16777619);
    return ((h >>> 0) % 360);
  }

  function build(board) {
    const now = Date.parse(board.generated_at);
    const tiles = (board.tiles || []).map((t) => Object.assign({}, DEFAULTS, t, { group_root: t.group_root || t.id }));
    const byId = new Map(tiles.map((t) => [t.id, t]));
    for (const t of tiles) {
      t.state = stateOf(t);
      t.verb = t.owed ? verbOf(t) : '';
      t.attention = attentionOf(t, now);
      t.owedMs = t.pr_owed_since ? now - Date.parse(t.pr_owed_since) : 0;
      t.movedMs = t.closed_at ? now - Date.parse(t.closed_at) : t.updated_at ? now - Date.parse(t.updated_at) : 0;
      t.ask = t.owed ? t.needs : '';
    }

    // Areas: every epic is one, nested under its group_parent.
    const areas = [];
    const areaById = new Map();
    for (const t of tiles) {
      if (t.kind !== 'epic') continue;
      const a = {
        id: t.id, tile: t, title: t.title, rig: t.rig, priority: t.priority ?? 4, hue: hueOf(t.id),
        parentId: t.group_parent || '', depth: 0, subs: [], rows: [], loose: false,
      };
      areas.push(a);
      areaById.set(t.id, a);
    }
    for (const a of areas) {
      if (a.parentId && areaById.has(a.parentId)) areaById.get(a.parentId).subs.push(a);
      else a.parentId = '';
    }
    // A row belongs to its immediate parent's area when that is an epic, else
    // to its family root's, else to the work in no epic of its rig.
    const looseByRig = new Map();
    for (const t of tiles) {
      if (t.kind === 'epic') continue;
      const home = areaById.get(t.group_parent) || areaById.get(t.group_root);
      if (home) {
        home.rows.push(t);
        t.areaId = home.id;
        continue;
      }
      let a = looseByRig.get(t.rig);
      if (!a) {
        a = {
          id: `loose:${t.rig}`, tile: null, title: `Not in an epic`, rig: t.rig, priority: 9,
          hue: 220, parentId: '', depth: 0, subs: [], rows: [], loose: true,
        };
        looseByRig.set(t.rig, a);
      }
      a.rows.push(t);
      t.areaId = a.id;
    }
    for (const t of tiles) if (t.kind === 'epic') t.areaId = t.id;

    const all = (a) => a.rows.concat(...a.subs.map(all));
    for (const a of areas.concat([...looseByRig.values()])) {
      const rows = all(a);
      const live = rows.filter((r) => r.state !== 'done');
      const count = Object.fromEntries(STATES.map((s) => [s, 0]));
      for (const r of live) count[r.state] += 1;
      if (a.tile && a.tile.owed) count.you += 1;
      count.done = rows.filter((r) => r.state === 'done').length;
      a.count = count;
      a.landedRows = rows.filter((r) => r.state === 'done');
      a.liveRows = live;
      if (a.tile) {
        // The epic's own counts cover its children that are not rows.
        const t = a.tile;
        a.progress = t.m_total ? { done: t.n_closed, total: t.m_total } : null;
        const notRows = Math.max(0, t.open - live.length);
        a.bar = {
          done: t.n_closed,
          moving: Math.max(count.moving, t.in_progress_live),
          you: count.you,
          stuck: Math.max(count.stuck, t.open_heads.length),
          queued: count.queued,
          held: count.held + notRows,
        };
        a.headline = t.takeaway || t.needs;
        a.state = t.state;
      } else {
        a.progress = null;
        a.bar = Object.assign({}, count);
        a.headline = '';
        a.state = count.you ? 'you' : count.stuck ? 'stuck' : count.moving ? 'moving' : 'held';
      }
      a.needsYou = count.you;
      a.lastMovedMs = Math.min(...rows.map((r) => r.movedMs).concat(a.tile ? [a.tile.movedMs] : []), Infinity);
    }
    // Stable order: priority, then title. A change of state never moves an area.
    const byPriority = (x, y) => x.priority - y.priority || x.title.localeCompare(y.title);
    const top = areas.filter((a) => !a.parentId).sort(byPriority);
    const setDepth = (a, d) => {
      a.depth = d;
      a.subs.sort(byPriority).forEach((s) => setDepth(s, d + 1));
    };
    top.forEach((a) => setDepth(a, 0));
    const loose = [...looseByRig.values()].sort((x, y) => x.rig.localeCompare(y.rig));

    // The asks: every owed row, most important first, then oldest. Rows that
    // share a cluster_key fold into one entry.
    const owed = tiles.filter((t) => t.owed && t.kind !== 'epic');
    const byImportance = (x, y) => (x.priority ?? 4) - (y.priority ?? 4) || y.owedMs - x.owedMs;
    owed.sort(byImportance);
    const asks = [];
    const clusterAt = new Map();
    for (const t of owed) {
      if (t.cluster_key) {
        const at = clusterAt.get(t.cluster_key);
        if (at !== undefined) {
          asks[at].rows.push(t);
          continue;
        }
        clusterAt.set(t.cluster_key, asks.length);
        asks.push({ key: `c:${t.cluster_key}`, cluster: true, needs: t.cluster_key, verb: t.verb, rows: [t] });
      } else {
        asks.push({ key: t.id, cluster: false, needs: t.needs, verb: t.verb, rows: [t] });
      }
    }
    for (const a of asks) {
      a.lead = a.rows[0];
      a.priority = a.lead.priority ?? 4;
      a.topCount = a.rows.filter((r) => (r.priority ?? 4) === a.priority).length;
    }
    // Epic-level asks (an epic parked for the operator) stay on their area.
    const sittings = board.sittings || [];
    const stats = {
      needsYou: owed.length,
      asks: asks.length,
      withYou: sittings.filter((s) => s.state === 'in_session').length,
      waitingForYou: sittings.filter((s) => s.state === 'waiting').length,
      moving: tiles.filter((t) => t.state === 'moving').length,
      stuck: tiles.filter((t) => t.state === 'stuck').length,
      held: tiles.filter((t) => t.state === 'held' || t.state === 'queued').length,
      landed: tiles.filter((t) => t.state === 'done').length,
      open: tiles.filter((t) => t.state !== 'done').length,
    };
    return {
      now, tiles, byId, areas: top, allAreas: areas, areaById, loose, asks, sittings,
      packHealth: board.pack_health || [], stats,
    };
  }

  window.HelmModel = {
    build, STATES, STATE_WORDS, VERB_WORDS, ageWords, shortAge, hueOf,
    esc(s) {
      return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
    },
  };
})();
