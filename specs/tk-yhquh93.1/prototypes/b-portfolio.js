// Direction B, Portfolio: an overview of every epic as a card, in priority
// order, with what needs you in a queue beside it; a click on a card opens that
// epic's page, its work in lanes by state, and the queue narrows to its asks.
// Reads only fields the board serves today, except where a lane says what the
// board counts but does not list.
(function () {
  'use strict';
  const M = window.HelmModel;
  const U = window.HelmUI;
  const esc = M.esc;
  const model = M.build(window.SAMPLE_BOARD);
  window.__model = model;
  const $ = (id) => document.getElementById(id);
  const view = { area: null, item: null, q: '', open: new Set(), talks: false };
  const allAreas = [...model.allAreas, ...model.loose];
  const findArea = (id) => allAreas.find((a) => a.id === id);
  const hueCss = (a) => (a.loose ? '#cdd2da' : `hsl(${a.hue} 52% 56%)`);
  const rowsOf = (a) => a.rows.concat(...a.subs.map(rowsOf));
  const matchQ = (t) => !view.q || `${t.title} ${t.needs} ${t.id}`.toLowerCase().includes(view.q.toLowerCase());
  const areaMatches = (a) => !view.q || a.title.toLowerCase().includes(view.q.toLowerCase()) || rowsOf(a).some(matchQ);

  function readHash() {
    const h = new URLSearchParams(location.hash.slice(1));
    view.area = h.get('area');
    view.item = h.get('item');
  }
  // go renders at once rather than on hashchange, which fires later, so a
  // second key pressed before it still reads where the first one went.
  function go(area, item) {
    const h = new URLSearchParams();
    if (area) h.set('area', area);
    if (item) h.set('item', item);
    location.hash = h.toString();
    render();
  }

  function glance() {
    const s = model.stats;
    const p1 = model.tiles.filter((t) => t.owed && t.priority === 1).length;
    return `<div class="glance">
      <div class="g you"><small>Needs you</small><b class="num">${s.needsYou}</b><span>in ${s.asks} asks · ${p1} at P1</span></div>
      <div class="g talks" data-talks tabindex="0" style="cursor:pointer"><small>With you</small><b class="num">${s.withYou}</b><span>in session · ${s.waitingForYou} conversations wait for you</span></div>
      <div class="g"><small>In motion</small><b class="num">${s.moving}</b><span>moving · ${s.stuck} stuck · ${s.held} on hold</span></div>
      <div class="g"><small>Landed this week</small><b class="num">${s.landed}</b><span>closed in the last 7 days</span></div>
    </div>`;
  }

  function card(a) {
    const rows = rowsOf(a);
    const wants = a.needsYou > 0;
    const prog = a.progress ? `${a.progress.done} of ${a.progress.total} landed` : `${a.liveRows.length} open`;
    const badge = wants
      ? `<span class="badge-you">● ${a.needsYou} need${a.needsYou === 1 ? 's' : ''} you</span>`
      : a.bar.stuck
        ? `<span class="badge-stuck">${a.bar.stuck} stuck</span>`
        : '';
    let headline = a.headline;
    if (a.loose) {
      const counts = new Map();
      for (const t of rows) if (t.state !== 'done' && t.cluster_key && !t.owed) counts.set(t.cluster_key, (counts.get(t.cluster_key) || 0) + 1);
      headline = [...counts].sort((x, y) => y[1] - x[1]).slice(0, 2).map(([k, n]) => `${n} ${k.split(':')[0].split(' — ')[0]}`).join(' · ') || `${a.liveRows.length} open items`;
    }
    const subs = a.subs.length
      ? `<div class="subs">${a.subs.map((s) => `<span class="chip">${U.areaDot(s)}${esc(s.title)}${s.needsYou ? ` · <b style="color:var(--you)">${s.needsYou}</b>` : ''}</span>`).join('')}</div>`
      : '';
    return `<div class="card${wants ? ' wants' : ''}${a.loose ? ' loose' : ''}${areaMatches(a) ? '' : ' dim'}" style="--hue:${hueCss(a)}" data-area="${esc(a.id)}" tabindex="0">
      <div class="hd">${a.loose ? '' : U.prio(a.priority)}<span class="t">${esc(a.loose ? a.rig : a.title)}</span><span class="rig">${esc(a.loose ? 'not in an epic' : a.rig)}</span></div>
      ${U.bar(a.bar, { thick: true })}
      <div class="mid"><span class="num">${prog}</span>${badge}</div>
      <div class="hl">${esc(headline)}</div>
      ${subs}
      <div class="ft">${U.barWords(a.bar, { only: ['moving', 'queued', 'held'] })}<span class="age num">${Number.isFinite(a.lastMovedMs) ? (a.lastMovedMs < 3600e3 ? 'moved just now' : `moved ${M.shortAge(a.lastMovedMs)} ago`) : ''}</span></div>
    </div>`;
  }

  function overview() {
    return `${glance()}
      <div class="sec"><h2>Epics</h2><span>by priority · a card keeps its place</span>${U.legend()}</div>
      <div class="grid">${model.areas.map(card).join('')}</div>
      <div class="sec"><h2>Not in an epic</h2><span>by rig</span></div>
      <div class="grid">${model.loose.map(card).join('')}</div>`;
  }

  function laneCard(t, a) {
    const sub = t.areaId !== a.id ? findArea(t.areaId) : null;
    return `<div class="k${view.item === t.id ? ' sel' : ''}${t.state === 'stuck' ? ' stuck' : ''}" data-item="${esc(t.id)}">
      <div class="t">${esc(t.title)}</div>
      <div class="s">${esc(t.owed ? t.ask : t.needs)}</div>
      <div class="m">${U.prio(t.priority)}${t.pr_number ? `<span>PR #${t.pr_number}</span>` : `<span>${esc(t.kind)}</span>`}${sub ? `<span class="chip">${U.areaDot(sub)}${esc(sub.title)}</span>` : ''}${t.owed || t.attention.key === 'live' ? U.attn(t) : ''}</div>
    </div>`;
  }
  function laneBody(rows, a, laneKey) {
    const byKey = new Map();
    const singles = [];
    for (const t of rows) {
      if (t.cluster_key && !view.q) (byKey.get(t.cluster_key) || byKey.set(t.cluster_key, []).get(t.cluster_key)).push(t);
      else singles.push(t);
    }
    let html = '';
    for (const [k, ms] of byKey) {
      if (ms.length < 3) {
        singles.push(...ms);
        continue;
      }
      const key = `${a.id}|${laneKey}|${k}`;
      const open = view.open.has(key);
      html += `<div class="k" data-fold="${esc(key)}"><div class="t">${ms.length} × ${esc(k.split(';')[0])}</div><div class="m">${open ? 'fold' : 'show each'}</div></div>${open ? ms.map((t) => laneCard(t, a)).join('') : ''}`;
    }
    return singles.map((t) => laneCard(t, a)).join('') + html;
  }

  function focus(a) {
    const rows = rowsOf(a).filter(matchQ);
    const lane = (key, word, states, extra) => {
      const rs = rows.filter((t) => states.includes(t.state)).sort((x, y) => states.indexOf(x.state) - states.indexOf(y.state));
      return `<div class="lane${key === 'you' ? ' you' : ''}"><h3><span class="dot s-${states[0]}"></span>${word}<span class="num">${rs.length}</span></h3>${laneBody(rs, a, key)}${extra || ''}</div>`;
    };
    const t = a.tile;
    const unlisted = t ? Math.max(0, t.open - rowsOf(a).filter((r) => r.state !== 'done').length) : 0;
    const unlistedNote = unlisted
      ? `<div class="unlisted">${unlisted} more open children are counted, not listed: today's board serves their count, not their titles.</div>`
      : '';
    const parent = a.parentId ? findArea(a.parentId) : null;
    return `<div class="${shownArea !== view.area ? 'fade-in' : ''}">
      <div class="crumb"><button data-home>← All epics</button>${parent ? `<span>/</span><button data-area="${esc(parent.id)}">${esc(parent.title)}</button>` : ''}<span>/</span><span>${esc(a.loose ? `${a.rig} · not in an epic` : a.title)}</span></div>
      <div class="fhead" style="--hue:${hueCss(a)}">
        <div class="row1">${a.loose ? '' : U.prio(a.priority)}<h1>${esc(a.loose ? `${a.rig}: not in an epic` : a.title)}</h1><span class="chip">${esc(a.rig)}</span>
        ${a.needsYou ? `<span class="badge-you" style="margin-left:auto">● ${a.needsYou} need you</span>` : ''}</div>
        ${a.headline ? `<p class="hl">${esc(a.headline)}</p>` : '<p class="hl"></p>'}
        ${U.bar(a.bar, { thick: true })}
        <div class="legend">${a.progress ? `<span class="num"><b>${a.progress.done} of ${a.progress.total}</b>&nbsp;landed</span>` : ''}${U.barWords(a.bar, { only: a.progress ? ['moving', 'you', 'stuck', 'queued', 'held'] : undefined })}</div>
      </div>
      ${a.subs.length ? `<div class="subrow">${a.subs.map((s) => `<button data-area="${esc(s.id)}" style="--hue:${hueCss(s)};border-left-color:${hueCss(s)}"><b>${esc(s.title)}</b>${U.bar(s.bar)}<span class="num">${s.progress ? `${s.progress.done}/${s.progress.total}` : ''}</span>${s.needsYou ? `<span class="badge-you">${s.needsYou}</span>` : ''}</button>`).join('')}</div>` : ''}
      <div class="lanes">
        ${lane('you', 'Needs you', ['you'])}
        ${lane('moving', 'Moving', ['moving'])}
        ${lane('wait', 'Stuck · queued · on hold', ['stuck', 'queued', 'held'], unlistedNote)}
        ${lane('done', 'Landed this week', ['done'])}
      </div>
    </div>`;
  }

  function queueEntry(ask) {
    const t = ask.lead;
    if (ask.cluster && ask.rows.length > 1) {
      const open = view.open.has(ask.key);
      const p1 = ask.rows.filter((r) => r.priority === 1).length;
      const n = ask.rows.length;
      const words = ask.verb === 'approve'
        ? `${n} pull requests are green and wait on your review`
        : /^blocker landed/.test(ask.needs)
          ? `${n} blockers landed: dispose of or resume each`
          : /^proposed close/.test(ask.needs)
            ? `${n} proposed closes did not validate`
            : ask.needs === 'operator decision'
              ? `${n} decisions wait on you`
              : `${n} × ${ask.needs}`;
      const areas = new Set(ask.rows.map((r) => r.areaId)).size;
      return `<div class="q cluster" data-fold="${esc(ask.key)}" data-nav>
          ${U.prio(ask.priority)}<div class="t">${esc(words)}</div>
          <div class="s">across ${areas} ${areas === 1 ? 'area' : 'areas'} · ${open ? 'click to fold' : 'click to show each'}</div>
          <div class="m">${U.verb(ask.verb)}${p1 ? `<span>${p1} at P1</span>` : ''}<span>oldest ${M.ageWords(Math.max(...ask.rows.map((r) => r.owedMs)))}</span></div>
        </div>
        <div class="q-members${open ? ' open' : ''}">${ask.rows.map((r) => `<div class="q" data-ask="${esc(r.id)}" data-nav><span></span><div class="t" style="font-weight:500">${esc(r.title)}</div><div class="m">${U.prio(r.priority)}${U.areaDot(findArea(r.areaId))}${esc(U.areaName(findArea(r.areaId)))} · ${M.shortAge(r.owedMs)}</div></div>`).join('')}</div>`;
    }
    const a = findArea(t.areaId);
    return `<div class="q" data-ask="${esc(t.id)}" data-area-of="${esc(t.areaId)}" data-nav>
      ${U.prio(t.priority)}<div class="t">${esc(t.title)}</div>
      <div class="s">${esc(t.ask)}</div>
      <div class="m">${U.verb(t.verb)}<span class="chip">${U.areaDot(a)}${esc(U.areaName(a))}</span>${U.attn(t)}<span class="num">${M.shortAge(t.owedMs)}</span></div>
    </div>`;
  }

  // The conversation record: in session, waiting for you, then ended today.
  function talks() {
    const word = { in_session: ['live', 'with you now'], waiting: ['waiting', 'waiting for you'], 'start-failed': ['failed', 'failed to start'], closed: ['seen', 'ended'] };
    return `<div class="fade-in"><button class="back" data-close-talks>← Needs you</button>
      <div class="rail-h"><h2>Conversations</h2><span class="num">${model.sittings.length}</span></div>
      <p class="muted" style="font-size:12.5px;margin:-4px 0 10px">Open first, then the ones that ended today. A click opens what it is about.</p>
      ${model.sittings
        .map((c) => {
          const [k, w] = word[c.state] || ['new', c.state];
          const t = model.byId.get(c.subject);
          return `<div class="q"${t ? ` data-ask="${esc(t.id)}"` : ''} data-nav><span class="attn a-${k}"><i></i></span><div class="t">${esc(c.headline)}</div>
            <div class="s">${esc(c.subject_title)}</div><div class="m"><span class="attn a-${k}">${w}</span><span class="num">${M.shortAge(model.now - Date.parse(c.closed_at || c.opened_at))}</span></div></div>`;
        })
        .join('')}</div>`;
  }

  function rail() {
    if (view.talks && !view.item) return talks();
    if (view.item && model.byId.get(view.item)) {
      return `<div class="fade-in"><button class="back" data-close-item>← ${view.area ? 'This epic' : 'Needs you'}</button>${U.detail(model.byId.get(view.item), model)}</div>`;
    }
    const a = view.area && findArea(view.area);
    const inArea = (t) => !a || rowsOf(a).includes(t) || t.id === a.id;
    const asks = model.asks
      .map((ask) => Object.assign({}, ask, { rows: ask.rows.filter((t) => inArea(t) && matchQ(t)) }))
      .filter((ask) => ask.rows.length)
      .map((ask) => Object.assign(ask, { lead: ask.rows[0] }));
    const n = asks.reduce((k, ask) => k + ask.rows.length, 0);
    return `<div class="rail-h"><h2>Needs you${a ? ` in ${esc(a.loose ? a.rig : a.title)}` : ''}</h2><span class="num">${n}</span></div>
      <p class="muted" style="font-size:12.5px;margin:-4px 0 10px">Most important first, then oldest. Alike asks fold.${a ? ' <button class="back" data-home style="margin:0">All asks →</button>' : ''}</p>
      ${asks.map(queueEntry).join('') || '<p class="muted">Nothing here needs you.</p>'}`;
  }

  let shownArea = undefined;
  let renderedHash = null;
  function render() {
    readHash();
    renderedHash = location.hash;
    const a = view.area && findArea(view.area);
    $('main').innerHTML = a ? focus(a) : overview();
    if (shownArea !== view.area) $('main').scrollTop = 0;
    shownArea = view.area;
    $('rail').innerHTML = rail();
    placeCursor();
  }

  let cursor = -1;
  const navs = () => [...$('rail').querySelectorAll('[data-nav]')].filter((el) => el.offsetParent !== null);
  function placeCursor() {
    document.querySelectorAll('.cursor').forEach((el) => el.classList.remove('cursor'));
    const all = navs();
    if (all[cursor]) all[cursor].classList.add('cursor');
  }
  // n opens the next thing that needs you, in the queue's order: the pull.
  let nextIdx = -1;
  function nextForYou() {
    const order = model.asks.flatMap((ask) => ask.rows);
    if (!order.length) return;
    nextIdx = (nextIdx + 1) % order.length;
    openAsk(order[nextIdx].id);
  }
  function openAsk(id) {
    const t = model.byId.get(id);
    go(t.areaId, t.id);
  }

  document.addEventListener('click', (e) => {
    if (e.target.closest('[data-act],[data-golive]')) return;
    const el = e.target.closest('[data-home],[data-close-item],[data-close-talks],[data-talks],[data-fold],[data-ask],[data-item],[data-area]');
    if (!el) return;
    if (el.dataset.talks !== undefined) {
      view.talks = true;
      return go(null, null);
    }
    if (el.dataset.closeTalks !== undefined) {
      view.talks = false;
      return render();
    }
    if (el.dataset.home !== undefined) {
      view.talks = false;
      return go(null, null);
    }
    if (el.dataset.closeItem !== undefined) return go(view.area, null);
    if (el.dataset.fold) {
      view.open.has(el.dataset.fold) ? view.open.delete(el.dataset.fold) : view.open.add(el.dataset.fold);
      return render();
    }
    if (el.dataset.ask) return openAsk(el.dataset.ask);
    if (el.dataset.item) return go(view.area, el.dataset.item);
    if (el.dataset.area) return go(el.dataset.area, null);
  });
  // Hovering an ask lights its epic's card, so the queue points into the map.
  $('rail').addEventListener('mouseover', (e) => {
    const q = e.target.closest('[data-area-of]');
    document.querySelectorAll('.card.lit').forEach((c) => c.classList.remove('lit'));
    if (q) {
      const c = document.querySelector(`.card[data-area="${CSS.escape(q.dataset.areaOf)}"]`);
      if (c) c.classList.add('lit');
    }
  });
  $('q').addEventListener('input', (e) => {
    view.q = e.target.value.trim();
    render();
  });
  document.addEventListener('keydown', (e) => {
    if (e.target === $('q')) {
      if (e.key === 'Escape') {
        e.target.value = '';
        view.q = '';
        e.target.blur();
        render();
      }
      return;
    }
    if (e.key === '/') {
      e.preventDefault();
      return $('q').focus();
    }
    if (e.key === 'n') return nextForYou();
    if (e.key === 'Escape') {
      if (view.talks && !view.item) {
        view.talks = false;
        return render();
      }
      if (view.item) return go(view.area, null);
      if (view.area) return go(null, null);
      return;
    }
    if (e.key === 'Enter' && document.activeElement && document.activeElement.dataset.area) {
      return go(document.activeElement.dataset.area, null);
    }
    const all = navs();
    if (e.key === 'j') cursor = Math.min(all.length - 1, cursor + 1);
    else if (e.key === 'k') cursor = Math.max(0, cursor - 1);
    else if (e.key === 'Enter' && all[cursor]) return all[cursor].click();
    else return;
    e.preventDefault();
    placeCursor();
    all[cursor] && all[cursor].scrollIntoView({ block: 'nearest' });
  });
  // The back and forward buttons change the hash without go.
  window.addEventListener('hashchange', () => location.hash !== renderedHash && render());
  render();
})();
