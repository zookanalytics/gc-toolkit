// Direction C, Canvas: the June Attention Canvas on today's board. Each epic is
// an island with a place, a color and an emblem that stay put; every item is a
// block colored by its state, so the whole city reads from altitude, and zoom
// is the level of detail. The operator pulls: a jump list and "next for you"
// fly the camera to what needs them. A place the operator drags an island to is
// kept in this browser, which today's board does not store.
(function () {
  'use strict';
  const M = window.HelmModel;
  const U = window.HelmUI;
  const esc = M.esc;
  const model = M.build(window.SAMPLE_BOARD);
  window.__model = model;
  const $ = (id) => document.getElementById(id);
  const stage = $('stage');
  const world = $('world');
  const ORDER = ['you', 'stuck', 'moving', 'queued', 'held'];
  const islands = [...model.areas, ...model.loose];
  const POS_KEY = 'helm-canvas-places-v1';
  const saved = JSON.parse(localStorage.getItem(POS_KEY) || '{}');

  const initials = (a) =>
    (a.loose ? a.rig : a.title)
      .split(/[\s-]+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((w) => w[0].toUpperCase())
      .join('');

  function chips(a) {
    const live = a.rows.filter((t) => t.state !== 'done').sort((x, y) => ORDER.indexOf(x.state) - ORDER.indexOf(y.state));
    const piles = new Map();
    const singles = [];
    for (const t of live) {
      if (t.cluster_key) (piles.get(t.cluster_key) || piles.set(t.cluster_key, []).get(t.cluster_key)).push(t);
      else singles.push(t);
    }
    const out = [];
    for (const t of live) {
      if (!t.cluster_key || piles.get(t.cluster_key).length < 3) {
        out.push(`<div class="chip2 s-${t.state}" data-item="${esc(t.id)}" title="${esc(`${t.title} — ${t.needs}`)}"><span class="dot s-${t.state}"></span><span class="lbl">${esc(t.title)}</span></div>`);
      } else if (piles.get(t.cluster_key)[0] === t) {
        const ms = piles.get(t.cluster_key);
        out.push(`<div class="chip2 pile s-${t.state}" data-pile="${esc(`${a.id}|${t.cluster_key}`)}" title="${esc(`${ms.length} × ${t.cluster_key}`)}"><span class="dot s-${t.state}"></span><span class="lbl"><span class="n">${ms.length}×</span> ${esc(t.cluster_key)}</span></div>`);
      }
    }
    return out.join('');
  }

  function islandBody(a, sub) {
    const landed = a.rows.filter((t) => t.state === 'done').length;
    const prog = a.progress ? `${a.progress.done}/${a.progress.total} landed` : `${a.liveRows.length} open`;
    return `<div class="ih" data-fly="${esc(a.id)}">
        <div class="emb">${esc(initials(a))}</div>
        <div style="min-width:0;flex:1"><div class="it">${esc(a.loose ? a.rig : a.title)}</div>
        <div class="isub">${a.loose ? 'not in an epic' : `P${a.priority} · ${esc(a.rig)}`} · ${prog}</div></div>
        ${a.needsYou ? `<span class="badge-you">● ${a.needsYou}</span>` : ''}
      </div>
      ${U.bar(a.bar)}
      <div class="chips">${chips(a)}</div>
      ${a.subs.map((s) => `<div class="sub" style="--h:${s.hue}">${islandBody(s, true)}</div>`).join('')}
      ${landed ? `<div class="landed"><span class="dot s-done"></span>${landed} landed this week</div>` : ''}`;
  }

  // Lay the islands out once: a remembered place wins, then the shortest of
  // four columns, in priority order, so a new island never moves an old one.
  world.innerHTML = islands
    .map((a) => `<div class="island${a.loose ? ' loose' : ''}${a.needsYou ? ' wants' : ''}" id="i-${esc(a.id)}" style="--h:${a.hue}">${islandBody(a)}</div>`)
    .join('');
  const COLS = 4;
  const W = 380;
  const GAP = 70;
  const colH = new Array(COLS).fill(0);
  for (const a of islands) {
    const el = document.getElementById(`i-${a.id}`);
    a.el = el;
    a.w = W;
    a.h = el.offsetHeight;
    if (saved[a.id]) {
      a.x = saved[a.id].x;
      a.y = saved[a.id].y;
      continue;
    }
    const c = colH.indexOf(Math.min(...colH));
    a.x = c * (W + GAP);
    a.y = colH[c] + (a.loose && colH[c] < 10 ? 0 : 0);
    colH[c] += a.h + GAP;
  }
  const place = (a) => {
    a.el.style.left = `${a.x}px`;
    a.el.style.top = `${a.y}px`;
  };
  islands.forEach(place);

  // The camera: screen = world × s + (x, y).
  const cam = { x: 0, y: 0, s: 1 };
  const leftPad = () => ($('jump').offsetWidth || 0) + 24;
  const rightPad = () => ($('panel').classList.contains('open') ? 434 : 24);
  function bounds(list) {
    const xs = list.map((a) => a.x);
    const ys = list.map((a) => a.y);
    const x2 = list.map((a) => a.x + a.w);
    const y2 = list.map((a) => a.y + a.h);
    return { x: Math.min(...xs), y: Math.min(...ys), w: Math.max(...x2) - Math.min(...xs), h: Math.max(...y2) - Math.min(...ys) };
  }
  function fitTarget(r, maxS) {
    const vw = innerWidth - leftPad() - rightPad();
    const vh = innerHeight - 80;
    const s = Math.min(maxS || 1.5, vw / (r.w + 60), vh / (r.h + 60));
    return { s, x: leftPad() + (vw - r.w * s) / 2 - r.x * s, y: 64 + (vh - r.h * s) / 2 - r.y * s };
  }
  let anim = null;
  function fly(t, ms = 420) {
    cancelAnimationFrame(anim);
    const from = Object.assign({}, cam);
    const t0 = performance.now();
    const ease = (k) => (k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2);
    const step = (now) => {
      const k = Math.min(1, (now - t0) / ms);
      const e = ease(k);
      cam.s = from.s + (t.s - from.s) * e;
      cam.x = from.x + (t.x - from.x) * e;
      cam.y = from.y + (t.y - from.y) * e;
      apply();
      if (k < 1) anim = requestAnimationFrame(step);
    };
    anim = requestAnimationFrame(step);
  }
  function apply() {
    world.style.transform = `translate(${cam.x}px, ${cam.y}px) scale(${cam.s})`;
    const far = cam.s < 0.62;
    world.classList.toggle('far', far);
    $('zoomv').textContent = `${Math.round(cam.s * 100)}%`;
    labels(far);
    mini();
  }
  function labels(far) {
    const L = $('labels');
    if (!far) {
      L.innerHTML = '';
      return;
    }
    L.innerHTML = islands
      .map((a) => {
        const x = a.x * cam.s + cam.x;
        const y = a.y * cam.s + cam.y - 16;
        return `<div class="flabel" data-fly="${esc(a.id)}" style="left:${x}px;top:${y}px;--h:${a.hue}"><span class="emb" style="${a.loose ? 'background:#a6adb8' : ''}">${esc(initials(a))}</span>${esc(a.loose ? `${a.rig} · loose` : a.title)}${a.needsYou ? `<span class="badge-you">● ${a.needsYou}</span>` : ''}</div>`;
      })
      .join('');
  }
  const all = bounds(islands);
  function mini() {
    const m = $('mini');
    const k = Math.min(170 / all.w, 140 / all.h);
    const ox = (180 - all.w * k) / 2 - all.x * k;
    const oy = (150 - all.h * k) / 2 - all.y * k;
    const vx = (-cam.x / cam.s) * k + ox;
    const vy = (-cam.y / cam.s) * k + oy;
    m.innerHTML =
      islands
        .map((a) => `<div style="left:${a.x * k + ox}px;top:${a.y * k + oy}px;width:${a.w * k}px;height:${a.h * k}px;background:${a.loose ? '#cfd3d9' : `hsl(${a.hue} 52% 70%)`};${a.needsYou ? 'box-shadow:0 0 0 1.5px var(--you)' : ''}"></div>`)
        .join('') + `<div class="vp" style="left:${vx}px;top:${vy}px;width:${(innerWidth / cam.s) * k}px;height:${(innerHeight / cam.s) * k}px"></div>`;
    m._k = { k, ox, oy };
  }

  // The pull list: what needs you, most important first; a click flies there.
  const asks = model.asks;
  function jumpList() {
    $('jump').innerHTML = `<header><b>Needs you · ${model.stats.needsYou}</b><p>Most important first. A click flies there; nothing here moves on its own.</p></header>
      <div class="list">${asks
        .map((ask, i) => {
          const t = ask.lead;
          const a = islands.find((x) => x.id === t.areaId) || model.allAreas.find((x) => x.id === t.areaId);
          const words = ask.cluster && ask.rows.length > 1 ? `${ask.rows.length} × ${ask.needs}` : t.title;
          return `<div class="j" data-jump="${i}">${U.prio(ask.priority)}<div class="t">${esc(words)}</div><div class="m">${U.verb(ask.verb)}<span class="area-dot" style="background:${a && !a.loose ? `hsl(${a.hue} 52% 56%)` : '#c9ced6'}"></span>${esc(a ? U.areaName(a) : '')}</div></div>`;
        })
        .join('')}</div>`;
  }
  let nextIdx = -1;
  function islandOf(t) {
    let a = model.areaById.get(t.areaId) || model.loose.find((x) => x.id === t.areaId);
    while (a && a.parentId) a = model.areaById.get(a.parentId);
    return a;
  }
  function selectItem(id, flyThere) {
    const t = model.byId.get(id);
    document.querySelectorAll('.chip2.sel').forEach((el) => el.classList.remove('sel'));
    const chip = world.querySelector(`[data-item="${CSS.escape(id)}"]`) || (t.cluster_key && world.querySelector(`[data-pile$="|${CSS.escape(t.cluster_key)}"]`));
    if (chip) chip.classList.add('sel');
    $('pbody').innerHTML = U.detail(t, model);
    $('panel').classList.add('open');
    if (flyThere) {
      const a = islandOf(t);
      if (a) fly(fitTarget(a, 1.35));
    }
  }
  function openPile(key) {
    const [areaId, ck] = [key.slice(0, key.indexOf('|')), key.slice(key.indexOf('|') + 1)];
    const a = [...model.allAreas, ...model.loose].find((x) => x.id === areaId);
    const ms = a.rows.filter((t) => t.cluster_key === ck && t.state !== 'done');
    $('pbody').innerHTML = `<div class="detail"><div class="crumbs">${U.areaDot(a)}${esc(U.areaName(a))}</div><h2>${ms.length} × ${esc(ck)}</h2>
      <p class="muted" style="font-size:13px">Alike items fold into one pile. Each one:</p>
      ${ms.map((t) => `<div class="j" data-open="${esc(t.id)}">${U.prio(t.priority)}<div class="t">${esc(t.title)}</div><div class="m"><span class="mono">${esc(t.id)}</span> · ${M.shortAge(t.movedMs)}</div></div>`).join('')}</div>`;
    $('panel').classList.add('open');
  }
  const closePanel = () => {
    $('panel').classList.remove('open');
    document.querySelectorAll('.chip2.sel').forEach((el) => el.classList.remove('sel'));
  };

  // Pointer: drag the background to pan, drag an island's name to move it.
  let drag = null;
  stage.addEventListener('pointerdown', (e) => {
    const head = e.target.closest('.ih');
    const isl = head && head.parentElement.classList.contains('island') ? islands.find((a) => a.el === head.parentElement) : null;
    drag = { x: e.clientX, y: e.clientY, cx: cam.x, cy: cam.y, isl, ix: isl && isl.x, iy: isl && isl.y, moved: false, target: e.target };
    stage.setPointerCapture(e.pointerId);
  });
  stage.addEventListener('pointermove', (e) => {
    if (!drag) return;
    const dx = e.clientX - drag.x;
    const dy = e.clientY - drag.y;
    if (!drag.moved && Math.hypot(dx, dy) < 4) return;
    drag.moved = true;
    if (drag.isl) {
      drag.isl.x = drag.ix + dx / cam.s;
      drag.isl.y = drag.iy + dy / cam.s;
      place(drag.isl);
      mini();
    } else {
      stage.classList.add('panning');
      cam.x = drag.cx + dx;
      cam.y = drag.cy + dy;
      apply();
    }
  });
  stage.addEventListener('pointerup', () => {
    if (!drag) return;
    const d = drag;
    drag = null;
    stage.classList.remove('panning');
    if (d.moved) {
      if (d.isl) {
        saved[d.isl.id] = { x: Math.round(d.isl.x), y: Math.round(d.isl.y) };
        localStorage.setItem(POS_KEY, JSON.stringify(saved));
      }
      return;
    }
    const el = d.target;
    const item = el.closest('[data-item]');
    if (item) return selectItem(item.dataset.item, cam.s < 0.62);
    const pile = el.closest('[data-pile]');
    if (pile) return openPile(pile.dataset.pile);
    const flyEl = el.closest('[data-fly]');
    if (flyEl) {
      const a = islands.find((x) => x.id === flyEl.dataset.fly) || model.allAreas.find((x) => x.id === flyEl.dataset.fly);
      const top = islandOf(a.tile || { areaId: a.id }) || a;
      return fly(fitTarget(top, 1.35));
    }
  });
  stage.addEventListener(
    'wheel',
    (e) => {
      e.preventDefault();
      if (e.ctrlKey || e.metaKey) zoomAt(e.clientX, e.clientY, Math.exp(-e.deltaY * 0.01));
      else {
        cam.x -= e.deltaX;
        cam.y -= e.deltaY;
        apply();
      }
    },
    { passive: false },
  );
  function zoomAt(px, py, f) {
    const s2 = Math.min(2.4, Math.max(0.12, cam.s * f));
    cam.x = px - ((px - cam.x) / cam.s) * s2;
    cam.y = py - ((py - cam.y) / cam.s) * s2;
    cam.s = s2;
    apply();
  }
  const zoomBy = (f) => {
    const t = { s: Math.min(2.4, Math.max(0.12, cam.s * f)) };
    const px = innerWidth / 2;
    const py = innerHeight / 2;
    t.x = px - ((px - cam.x) / cam.s) * t.s;
    t.y = py - ((py - cam.y) / cam.s) * t.s;
    fly(t, 260);
  };
  const fitAll = () => fly(fitTarget(all, 1));
  function next() {
    nextIdx = (nextIdx + 1) % asks.length;
    document.querySelectorAll('.j.on').forEach((el) => el.classList.remove('on'));
    const j = document.querySelector(`[data-jump="${nextIdx}"]`);
    if (j) {
      j.classList.add('on');
      j.scrollIntoView({ block: 'nearest' });
    }
    selectItem(asks[nextIdx].lead.id, true);
  }
  $('labels').addEventListener('click', (e) => {
    const f = e.target.closest('[data-fly]');
    if (f) fly(fitTarget(islands.find((x) => x.id === f.dataset.fly), 1.35));
  });
  document.addEventListener('click', (e) => {
    if (e.target.closest('[data-act],[data-golive]')) return;
    const j = e.target.closest('[data-jump]');
    if (j) {
      nextIdx = Number(j.dataset.jump) - 1;
      return next();
    }
    const o = e.target.closest('[data-open]');
    if (o) return selectItem(o.dataset.open, true);
  });
  $('mini').addEventListener('click', (e) => {
    const r = $('mini').getBoundingClientRect();
    const { k, ox, oy } = $('mini')._k;
    const wx = (e.clientX - r.left - ox) / k;
    const wy = (e.clientY - r.top - oy) / k;
    fly({ s: cam.s, x: innerWidth / 2 - wx * cam.s, y: innerHeight / 2 - wy * cam.s }, 300);
  });
  $('fit').onclick = fitAll;
  $('zin').onclick = () => zoomBy(1.3);
  $('zout').onclick = () => zoomBy(1 / 1.3);
  $('next').onclick = next;
  $('pclose').onclick = closePanel;
  document.addEventListener('keydown', (e) => {
    if (e.key === '0') fitAll();
    else if (e.key === '+' || e.key === '=') zoomBy(1.3);
    else if (e.key === '-') zoomBy(1 / 1.3);
    else if (e.key === 'n') next();
    else if (e.key === 'Escape') closePanel();
    else if (e.key.startsWith('Arrow')) {
      const d = 80;
      if (e.key === 'ArrowLeft') cam.x += d;
      if (e.key === 'ArrowRight') cam.x -= d;
      if (e.key === 'ArrowUp') cam.y += d;
      if (e.key === 'ArrowDown') cam.y -= d;
      apply();
    }
  });
  addEventListener('resize', apply);

  jumpList();
  Object.assign(cam, fitTarget(all, 1));
  apply();
})();
