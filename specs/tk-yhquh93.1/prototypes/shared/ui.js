// ui.js draws the pieces every direction shares: the state bar, the markers,
// one item's detail, and the terminal that rests as a peek and goes live on a
// click. Actions are inert: a click says what the board would do, in place.
(function () {
  'use strict';
  const M = window.HelmModel;
  const esc = M.esc;

  function bar(b, opts) {
    const order = M.STATES;
    const total = order.reduce((n, s) => n + (b[s] || 0), 0) || 1;
    const title = order.filter((s) => b[s]).map((s) => `${b[s]} ${M.STATE_WORDS[s]}`).join(' · ');
    const parts = order
      .filter((s) => b[s])
      .map((s) => `<span class="s-${s}" style="flex:${b[s]} 1 0"></span>`)
      .join('');
    return `<div class="bar${opts && opts.thick ? ' thick' : ''}" title="${esc(title)}" aria-label="${esc(title)}">${parts}</div>`;
  }

  function barWords(b, opts) {
    const keep = (opts && opts.only) || M.STATES;
    return keep
      .filter((s) => b[s])
      .map((s) => `<span><i class="dot s-${s}"></i>${b[s]} ${M.STATE_WORDS[s]}</span>`)
      .join('');
  }

  function legend() {
    return `<div class="legend">${M.STATES.map((s) => `<span><i class="dot s-${s}"></i>${M.STATE_WORDS[s]}</span>`).join('')}</div>`;
  }

  const prio = (p) => `<span class="prio p${p ?? 4}">P${p ?? '–'}</span>`;
  const verb = (v) => (v ? `<span class="verb v-${v}">${M.VERB_WORDS[v]}</span>` : '');
  const attn = (t) => `<span class="attn a-${t.attention.key}"><i></i>${esc(t.attention.words)}</span>`;
  const areaDot = (a) =>
    a.loose
      ? `<span class="area-dot" style="background:repeating-linear-gradient(135deg,#c9ced6 0 2px,#e6e9ee 2px 4px)"></span>`
      : `<span class="area-dot" style="background:hsl(${a.hue} 52% 56%)"></span>`;
  const areaName = (a) => (a.loose ? `Not in an epic · ${a.rig}` : a.title);

  // The actions are today's write routes: accept on a row that can be
  // accepted; file a conversation (open), Discuss (engage) and Dismiss on any
  // item, as the drill panel offers them; the pull request is a link. Rejoin
  // attaches the terminal.
  const CONVERSATION_ACTIONS = ['File a conversation', 'Discuss', 'Dismiss'];
  function primaryAction(t) {
    if (t.verb === 'approve') return `Open PR #${t.pr_number}`;
    if (t.acceptable) return 'Accept';
    if (t.attention.key === 'live') return 'Rejoin';
    return 'Discuss';
  }
  function secondaryActions(t) {
    const first = primaryAction(t);
    return CONVERSATION_ACTIONS.filter((a) => a !== first);
  }

  function terminalText(t, live) {
    const id = t.id;
    if (t.kind === 'conversation' || t.attention.key === 'live') {
      return [
        `converse · ${id}`,
        `> ${t.title}`,
        '',
        'po: Three directions are drawn on the sample board. The table you',
        '    use today, regrouped; a portfolio of epics you dive into; and',
        '    the spatial canvas from June. Which one reads best at a glance?',
        '',
        live ? 'you: ' : 'you: (waiting)',
      ].join('\n');
    }
    if (t.state === 'moving') {
      return [
        `polecat · ${id}`,
        `$ go test ./...`,
        'ok   services/helm/internal/board   1.284s',
        'ok   services/helm/internal/source  0.912s',
        `$ git push origin polecat/${id}`,
        'To github.com:example-org/repo.git',
        ` * [new branch]  polecat/${id} -> polecat/${id}`,
        live ? '$ ' : '',
      ].join('\n');
    }
    return [
      `no session holds ${id} right now`,
      '',
      'Discuss starts a conversation about it.',
    ].join('\n');
  }

  function terminal(t) {
    const session = t.attention.key === 'live' ? `converse-${t.id.slice(3, 7)}` : t.state === 'moving' ? `polecat-${t.id.slice(3, 7)}` : 'none';
    return `<div class="term peek" data-term="${esc(t.id)}">
      <header><span>⌁ ${esc(session)}</span><span class="st peek">peek</span>
      <button class="btn small" data-golive style="margin-left:6px">Go live</button></header>
      <pre>${esc(terminalText(t, false))}</pre></div>`;
  }

  function detail(t, model) {
    const area = model.areaById.get(t.areaId) || model.loose.find((a) => a.id === t.areaId);
    const crumbs = area ? `${areaDot(area)}<span>${esc(areaName(area))}</span><span>·</span>` : '';
    const sittings = model.sittings.filter((s) => s.subject === t.id || s.id === t.id);
    const facts = [
      ['State', `<span class="dot s-${t.state}"></span> ${esc(M.STATE_WORDS[t.state])}`],
      t.owed ? ['Waiting on you', `${esc(M.ageWords(t.owedMs))}`] : null,
      ['Attention', attn(t)],
      t.pr_number ? ['Pull request', `<a href="${esc(t.pr_url)}" target="_blank" rel="noreferrer">#${t.pr_number}</a> · ${esc(t.pr_phase)}${t.pr_held ? ` · held: ${esc(t.pr_held.join(', '))}` : ''}`] : null,
      t.m_total ? ['Progress', `${t.n_closed} of ${t.m_total} landed`] : null,
      ['Next', esc(t.frontier.replace(/^[a-z-]+ · /, ''))],
      ['Id', `<span class="mono">${esc(t.id)}</span> · ${esc(t.rig)} · ${esc(t.kind)}`],
    ].filter(Boolean);
    const actions = [primaryAction(t), ...secondaryActions(t)];
    return `<div class="detail">
      <div class="crumbs">${crumbs}${prio(t.priority)}</div>
      <h2>${esc(t.title)}</h2>
      ${t.owed ? `<div class="ask"><b>${esc(M.VERB_WORDS[t.verb])} · asks you</b>${esc(t.ask)}</div>` : `<p class="muted">${esc(t.needs)}</p>`}
      <div class="actions">${actions.map((a, i) => `<button class="btn${i === 0 ? ' primary' : ''}" data-act="${esc(a)}">${esc(a)}</button>`).join('')}<span class="did"></span></div>
      ${t.recommendation ? `<div class="rec">${esc(t.recommendation.replace(/## /g, ''))}</div>` : ''}
      <dl class="facts">${facts.map(([k, v]) => `<dt>${k}</dt><dd>${v}</dd>`).join('')}</dl>
      ${sittings.length ? `<p class="muted" style="font-size:12px;margin:0 0 6px">Conversations: ${sittings.map((s) => esc(`${s.state.replace('_', ' ')} — ${s.headline}`)).join(' · ')}</p>` : ''}
      ${terminal(t)}
    </div>`;
  }

  // Inert actions and the terminal's go-live, wired once for the page.
  document.addEventListener('click', (e) => {
    const act = e.target.closest('[data-act]');
    if (act) {
      const did = act.parentElement.querySelector('.did');
      if (did) {
        did.textContent = `prototype: “${act.dataset.act}” would run here`;
        did.classList.add('on');
        clearTimeout(did._t);
        did._t = setTimeout(() => did.classList.remove('on'), 2200);
      }
      e.stopPropagation();
      return;
    }
    const go = e.target.closest('[data-golive]');
    if (go) {
      const term = go.closest('.term');
      const t = window.__model && window.__model.byId.get(term.dataset.term);
      term.classList.remove('peek');
      term.querySelector('.st').className = 'st live';
      term.querySelector('.st').textContent = 'live';
      term.querySelector('pre').innerHTML = `${esc(terminalText(t, true))}<span class="cursor"></span>`;
      go.remove();
      e.stopPropagation();
    }
  });

  window.HelmUI = { bar, barWords, legend, prio, verb, attn, areaDot, areaName, detail, terminal, primaryAction };
})();
