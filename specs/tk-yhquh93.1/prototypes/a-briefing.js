// Direction A, Briefing: one page you read top to bottom. What needs you comes
// first, grouped by the move it asks for and most important first; then every
// epic in priority order on one line with its state bar, opening in place; then
// the work in no epic, folded by rig. Reads only fields the board serves today.
(function () {
  'use strict';
  const M = window.HelmModel;
  const U = window.HelmUI;
  const esc = M.esc;
  const model = M.build(window.SAMPLE_BOARD);
  window.__model = model;

  const view = { rig: '', q: '', openAreas: new Set(), openClusters: new Set(), showLanded: new Set() };
  const $ = (id) => document.getElementById(id);

  function matches(t) {
    if (view.rig && t.rig !== view.rig) return false;
    if (!view.q) return true;
    const q = view.q.toLowerCase();
    return `${t.title} ${t.needs} ${t.id}`.toLowerCase().includes(q);
  }
  const hl = (s) => {
    const text = esc(s);
    if (!view.q) return text;
    const i = text.toLowerCase().indexOf(esc(view.q).toLowerCase());
    return i < 0 ? text : `${text.slice(0, i)}<span class="hit">${text.slice(i, i + esc(view.q).length)}</span>${text.slice(i + esc(view.q).length)}`;
  };
  const areaOf = (t) => model.areaById.get(t.areaId) || model.loose.find((a) => a.id === t.areaId);

  function glance() {
    const s = model.stats;
    $('glance').innerHTML = `
      <h1><em>${s.needsYou} things need you</em>, in ${s.asks} asks.</h1>
      <p><b>${s.withYou}</b> conversations are with you now and <b>${s.waitingForYou}</b> wait for you.
      <b>${s.moving}</b> moving · <b>${s.stuck}</b> stuck · <b>${s.held}</b> on hold · <b>${s.landed}</b> landed this week.</p>
      ${U.legend()}`;
  }

  const GROUPS = [
    ['decide', 'Decide', 'questions only you can answer'],
    ['approve', 'Approve', 'pull requests waiting on your review'],
    ['clear', 'Clear', 'finished holds to dispose of'],
  ];
  function clusterWords(ask) {
    const n = ask.rows.length;
    if (ask.verb === 'approve') return `${n} pull requests are green and wait on your review`;
    if (/^blocker landed/.test(ask.needs)) return `${n} blockers landed: dispose of or resume each`;
    if (/^proposed close/.test(ask.needs)) return `${n} proposed closes did not validate`;
    if (ask.needs === 'operator decision') return `${n} decisions wait on you`;
    return `${n} × ${ask.needs}`;
  }

  function askRow(t, nested) {
    const a = areaOf(t);
    return `<div class="row" data-nav data-open="${esc(t.id)}">
      ${U.prio(t.priority)}
      <div class="main"><div class="t">${hl(t.title)}</div><div class="s">${hl(t.ask)}</div></div>
      <span class="chip">${U.areaDot(a)}${esc(U.areaName(a))}</span>
      ${U.attn(t)}
      <span class="age num">${M.shortAge(t.owedMs)}</span>
      <span class="go">${nested ? '' : `<button class="btn small" data-act="${esc(U.primaryAction(t))}">${esc(U.primaryAction(t))}</button>`}</span>
    </div>`;
  }

  function needs() {
    const asks = model.asks
      .map((ask) => Object.assign({}, ask, { rows: ask.rows.filter(matches) }))
      .filter((ask) => ask.rows.length);
    const groups = GROUPS.map(([verb, word, hint]) => {
      const mine = asks.filter((ask) => ask.verb === verb);
      if (!mine.length) return '';
      const count = mine.reduce((n, ask) => n + ask.rows.length, 0);
      const rows = mine
        .map((ask) => {
          if (!ask.cluster || ask.rows.length < 2) return ask.rows.map((t) => askRow(t)).join('');
          const open = view.openClusters.has(ask.key) || !!view.q;
          const p1 = ask.rows.filter((r) => r.priority === 1).length;
          const areas = new Set(ask.rows.map((r) => r.areaId)).size;
          const oldest = Math.max(...ask.rows.map((r) => r.owedMs));
          return `<div class="row cluster${open ? ' open' : ''}" data-nav data-cluster="${esc(ask.key)}">
              ${U.prio(ask.priority)}
              <div class="main"><div class="t">${esc(clusterWords(ask))}</div>
              <div class="s">${p1 ? `${p1} at P1 · ` : ''}oldest ${M.ageWords(oldest)} · across ${areas} areas</div></div>
              <span class="chip">${ask.rows.length} items</span><span></span>
              <span class="age num">${M.shortAge(oldest)}</span>
              <span class="go"><button class="btn small" data-cluster-toggle="${esc(ask.key)}">${open ? 'Fold' : 'Show all'}</button></span>
            </div>
            <div class="members${open ? ' open' : ''}">${ask.rows.map((t) => askRow(t, true)).join('')}</div>`;
        })
        .join('');
      return `<div class="group"><h3>${U.verb(verb)} ${count} <small>${hint}</small></h3>${rows}</div>`;
    });
    $('needs').innerHTML = `<h2>Needs you <span>most important first, then oldest</span></h2>${groups.join('') || '<p class="muted">Nothing here needs you.</p>'}`;
  }

  function areaHead(a, rows) {
    const p = a.progress ? `<span class="n num">${a.progress.done}/${a.progress.total} landed</span>` : `<span class="n num">${a.liveRows.length} open</span>`;
    const badge = a.needsYou
      ? `<span class="badge-you">● ${a.needsYou} need${a.needsYou === 1 ? 's' : ''} you</span>`
      : a.bar.stuck
        ? `<span class="badge-stuck">${a.bar.stuck} stuck</span>`
        : '<span></span>';
    const stripe = a.loose ? 'repeating-linear-gradient(180deg,#c9ced6 0 4px,#e6e9ee 4px 8px)' : `hsl(${a.hue} 52% 56%)`;
    const head = a.loose ? `${a.rig}` : a.title;
    const line = a.loose ? `${rows.length} items in no epic` : a.headline;
    return `<div class="area-head" data-nav data-area="${esc(a.id)}">
      <span class="stripe" style="background:${stripe}"></span>
      ${a.loose ? '<span class="prio p4">—</span>' : U.prio(a.priority)}
      <span class="t">${hl(head)}</span>
      ${U.bar(a.bar)}
      ${p}
      ${badge}
      <span class="h">${hl(line)}</span>
      <span class="n num">${Number.isFinite(a.lastMovedMs) ? M.shortAge(a.lastMovedMs) : ''}</span>
    </div>`;
  }

  function itemRow(t) {
    return `<div class="item" data-nav data-open="${esc(t.id)}">
      <span class="dot s-${t.state}"></span>
      <span class="t">${hl(t.title)}<small>${hl(t.owed ? t.ask : t.needs)}</small></span>
      ${t.owed || t.attention.key === 'live' ? U.attn(t) : `<span class="muted" style="font-size:12px">${esc(t.pr_number ? `PR #${t.pr_number}` : t.kind)}</span>`}
      <span class="age num">${M.shortAge(t.owed ? t.owedMs : t.movedMs)}</span>
    </div>`;
  }

  // The rows of one area, by state; rows sharing a needs sentence fold.
  function areaBody(a) {
    const own = a.rows.filter(matches);
    const parts = [];
    for (const s of ['you', 'moving', 'stuck', 'queued', 'held']) {
      const rows = own.filter((t) => t.state === s);
      if (!rows.length) continue;
      const byKey = new Map();
      const loose = [];
      for (const t of rows) {
        if (t.cluster_key && !view.q) {
          if (!byKey.has(t.cluster_key)) byKey.set(t.cluster_key, []);
          byKey.get(t.cluster_key).push(t);
        } else loose.push(t);
      }
      let html = '';
      for (const [k, ms] of byKey) {
        if (ms.length < 3) {
          loose.push(...ms);
          continue;
        }
        const key = `${a.id}|${k}`;
        const open = view.openClusters.has(key);
        html += `<div class="item" data-nav data-cluster="${esc(key)}"><span class="dot s-${s}"></span>
          <span class="t"><b>${ms.length}</b> × ${esc(k)}</span><span class="muted" style="font-size:12px">${open ? 'fold' : 'show all'}</span><span></span></div>
          ${open ? ms.map(itemRow).join('') : ''}`;
      }
      html = loose.map(itemRow).join('') + html;
      parts.push(`<h4><span class="dot s-${s}"></span>${M.STATE_WORDS[s]} · ${rows.length}</h4>${html}`);
    }
    const subs = a.subs.map((sub) => areaBlock(sub)).join('');
    const landed = a.rows.filter((t) => t.state === 'done' && matches(t));
    if (landed.length) {
      const open = view.showLanded.has(a.id);
      parts.push(`<h4><span class="dot s-done"></span>landed this week · ${landed.length}</h4>
        ${open ? landed.map(itemRow).join('') : `<button class="more" data-landed="${esc(a.id)}">Show the ${landed.length} that landed</button>`}`);
    }
    return subs + parts.join('');
  }

  function areaBlock(a) {
    const rows = a.rows.filter(matches);
    const subHit = (x) => x.subs.some((s) => s.rows.some(matches) || subHit(s));
    const titleHit = view.q && a.title.toLowerCase().includes(view.q.toLowerCase());
    if ((view.q || view.rig) && !rows.length && !subHit(a) && !(titleHit && (!view.rig || a.rig === view.rig))) return '';
    const open = view.openAreas.has(a.id) || (!!view.q && (rows.length > 0 || subHit(a)));
    return `<div class="area${open ? ' open' : ''}">${areaHead(a, rows)}<div class="area-body">${open ? areaBody(a) : ''}</div></div>`;
  }

  function stand() {
    $('stand').innerHTML = `<h2>Where things stand <span>every epic, by priority · its place never changes</span></h2>${model.areas.map(areaBlock).join('')}`;
    $('loose').innerHTML = `<h2>Not in an epic <span>by rig · alike rows folded</span></h2>${model.loose.map(areaBlock).join('')}`;
  }

  function talks() {
    const rows = model.sittings
      .filter((s) => !view.rig || s.rig === view.rig)
      .map((s) => {
        const w = s.state === 'in_session' ? '<span class="attn a-live"><i></i>with you now</span>' : s.state === 'waiting' ? '<span class="attn a-waiting"><i></i>waiting for you</span>' : '<span class="attn a-seen"><i></i>ended</span>';
        const when = s.closed_at || s.opened_at;
        return `<div class="talk">${w}<span>${esc(s.headline)} <span class="muted">· ${esc(s.subject_title)}</span></span><span class="muted num">${M.shortAge(model.now - Date.parse(when))}</span></div>`;
      });
    $('talks').innerHTML = `<h2>Conversations <span>open, then ended today</span></h2><div class="group">${rows.join('')}</div>`;
  }

  function rigs() {
    const names = ['', ...new Set(model.tiles.map((t) => t.rig))];
    $('rigs').innerHTML = names.map((r) => `<button aria-pressed="${view.rig === r}" data-rig="${esc(r)}">${esc(r || 'all rigs')}</button>`).join('');
  }

  function render() {
    rigs();
    glance();
    needs();
    stand();
    talks();
    placeCursor();
  }

  // Keyboard: j and k move through every row on the page, Enter opens.
  let cursor = -1;
  const navs = () => [...document.querySelectorAll('[data-nav]')].filter((el) => el.offsetParent !== null);
  function placeCursor() {
    document.querySelectorAll('.cursor').forEach((el) => el.classList.remove('cursor'));
    const all = navs();
    if (cursor >= 0 && all[cursor]) all[cursor].classList.add('cursor');
  }
  function activate(el) {
    if (el.dataset.area) {
      view.openAreas.has(el.dataset.area) ? view.openAreas.delete(el.dataset.area) : view.openAreas.add(el.dataset.area);
      render();
    } else if (el.dataset.cluster) {
      view.openClusters.has(el.dataset.cluster) ? view.openClusters.delete(el.dataset.cluster) : view.openClusters.add(el.dataset.cluster);
      render();
    } else if (el.dataset.open) openDetail(el.dataset.open);
  }
  function openDetail(id) {
    const t = model.byId.get(id);
    $('drawer-body').innerHTML = U.detail(t, model);
    $('drawer').classList.add('open');
  }
  const closeDetail = () => $('drawer').classList.remove('open');

  document.addEventListener('click', (e) => {
    if (e.target.closest('[data-act],[data-golive]')) return;
    const rig = e.target.closest('[data-rig]');
    if (rig) {
      view.rig = rig.dataset.rig;
      return render();
    }
    const landed = e.target.closest('[data-landed]');
    if (landed) {
      view.showLanded.add(landed.dataset.landed);
      return render();
    }
    const toggle = e.target.closest('[data-cluster-toggle]');
    if (toggle) {
      const k = toggle.dataset.clusterToggle;
      view.openClusters.has(k) ? view.openClusters.delete(k) : view.openClusters.add(k);
      return render();
    }
    if (e.target.closest('#close')) return closeDetail();
    if (e.target.closest('#drawer')) return;
    const nav = e.target.closest('[data-nav]');
    if (nav) {
      cursor = navs().indexOf(nav);
      activate(nav);
      placeCursor();
    }
  });
  $('q').addEventListener('input', (e) => {
    view.q = e.target.value.trim();
    cursor = -1;
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
    if (e.key === 'Escape') return closeDetail();
    const all = navs();
    if (e.key === 'j' || e.key === 'ArrowDown') cursor = Math.min(all.length - 1, cursor + 1);
    else if (e.key === 'k' || e.key === 'ArrowUp') cursor = Math.max(0, cursor - 1);
    else if (e.key === 'Enter' && all[cursor]) return activate(all[cursor]);
    else return;
    e.preventDefault();
    placeCursor();
    all[cursor] && all[cursor].scrollIntoView({ block: 'nearest' });
  });

  render();
})();
