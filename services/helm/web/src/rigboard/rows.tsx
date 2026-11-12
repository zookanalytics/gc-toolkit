// The rows the pages are made of. An object is drawn the same way wherever it
// sits; the page decides only what nests under it. On the Epics page and the
// Work queue a bead is the row and the asks that stop it are its children; on
// Needs you the ask is the row and the beads it holds are its children.

import type { ReactNode } from 'react';
import type { Counts, DeliveryEntry, EpicEntry, Group, GroupList, Ref, Row } from './document.gen';
import { Description } from './Description';
import { BeadId, Line, Show } from './Line';
import {
  AMBER,
  EPIC_HUES,
  GROUP_LOOK,
  GROUPS,
  INK,
  MUTE,
  STEP,
  groupOpenByDefault,
  signalInk,
  useView,
  type View,
} from './view';

const WHITE = '#FFFFFF';
const BAND = '#ECEDE7';
const RULE = '#E6E7E2';
const ASK_TINT = '#FFF8E3';

/** The word a row's tag reads when the row is not drawn as an ask. */
const KIND_WORD: Partial<Record<Row['kind'], string>> = {
  delivery: 'Delivery',
  gate: 'Gate',
  decision: 'Decision',
  conversation: 'Conversation',
};

export interface ObjectRowProps {
  id: string;
  /** The key of the place it is drawn in, so each place folds on its own. */
  ctx: string;
  depth: number;
  /** As an ask, the row reads its ask and nests what it holds; as an item, it
   *  nests the asks that stop it. */
  role: 'item' | 'ask';
  /** Draw no children, as under a parent that already lists them. */
  bare?: boolean;
  /** The children a section gives it, in place of its own. */
  kids?: string[];
}

export function ObjectRow({ id, ctx, depth, role, bare, kids }: ObjectRowProps) {
  const v = useView();
  const row = v.doc.rows[id];
  if (row === undefined) {
    return (
      <Line depth={depth} look="item" rule={RULE} hasKids={false} open={false} onToggle={() => {}} title="Not in the board's document" titleInk={MUTE} id={id} />
    );
  }
  const asAsk = role === 'ask' && row.ask !== undefined;
  const key = `${ctx}/${asAsk ? 'n' : 'w'}:${id}`;
  const childIds = kids ?? (bare === true ? [] : asAsk ? row.holds : row.asks);
  const childRole: ObjectRowProps['role'] = kids !== undefined || asAsk ? 'item' : 'ask';
  const kidsKey = `${key}/kids`;
  const kidsOpen = v.isOpen(kidsKey, true);
  const detailsKey = `${key}/details`;
  const detailsOpen = v.isOpen(detailsKey, false);
  const closed = row.group === 'Closed';

  const bits: ReactNode[] = [...pullRequestBits(row), ...refBits(row.line3 ?? [], 'line3')];
  if (asAsk) {
    for (const [i, r] of (row.reasons ?? []).entries()) {
      bits.push(
        <span key={`reason${i}`} className="bit bit--ref">
          {r.held}: {r.title}
          {r.id !== undefined && r.id !== '' && (
            <>
              {' '}
              <BeadId id={r.id} /> <Show id={r.id} />
            </>
          )}
        </span>,
      );
    }
    if (bare === true && row.holds.length > 0) {
      bits.push(
        <span key="holds" className="bit">
          holds up {row.holds.length} {row.holds.length === 1 ? 'bead' : 'beads'}
        </span>,
      );
    }
    bits.push(...askActions(v, row));
  }

  return (
    <>
      <Line
        depth={depth}
        look="item"
        bg={asAsk && row.group === 'Waiting on you' ? ASK_TINT : WHITE}
        rule={RULE}
        hasKids={childIds.length > 0}
        open={kidsOpen}
        onToggle={() => v.flip(kidsKey, true)}
        priority={row.priority}
        tag={tagOf(row, asAsk)}
        title={titleOf(row)}
        quiet={closed}
        titleInk={closed ? MUTE : INK}
        signal={{ text: row.signal, note: row.note, ink: signalInk(row) }}
        details={{ open: detailsOpen, onToggle: () => v.flip(detailsKey, false) }}
        id={row.id}
        line2={row.line2}
        bits={bits}
      />
      {detailsOpen && <DetailsBlock row={row} depth={depth} />}
      {kidsOpen &&
        childIds.map((c) => <ObjectRow key={c} id={c} ctx={key} depth={depth + 1} role={childRole} bare />)}
    </>
  );
}

function tagOf(row: Row, asAsk: boolean): { text: string; ink: string; weight?: number } | undefined {
  if (asAsk && row.ask !== undefined) {
    return { text: row.ask, ink: row.group === 'Waiting on you' ? AMBER : MUTE };
  }
  const word = KIND_WORD[row.kind];
  if (word === undefined) return undefined;
  return { text: word, ink: '#65707B', weight: row.kind === 'delivery' ? 400 : 600 };
}

/** An epic's row reads its handle where it records one, as the export draws an
 *  epic; every other row reads its title. Details holds an epic's title. */
function titleOf(row: Row): string {
  const handle = row.contract?.handle?.trim() ?? '';
  return row.kind === 'epic' && handle !== '' ? handle : row.title;
}

/** Start the conversation on a question no conversation answers yet, and
 *  Rejoin the conversation where one exists. */
function askActions(v: View, row: Row): ReactNode[] {
  let target: string | undefined;
  let label = '';
  if (row.ask === 'Conversation') {
    target = row.id;
    label = 'Rejoin the conversation';
  } else if (row.ask === 'Question') {
    if (row.conversation !== undefined && row.conversation !== '') {
      target = row.conversation;
      label = 'Rejoin the conversation';
    } else {
      target = row.id;
      label = 'Start the conversation';
    }
  }
  if (target === undefined) return [];
  const bead = target;
  return [
    <button
      key="engage"
      type="button"
      className="button button--primary button--small"
      onClick={() => v.engage(bead, row.title)}
    >
      {label}
    </button>,
  ];
}

function pullRequestBits(row: Row): ReactNode[] {
  const pr = row.pull_request;
  if (pr === undefined) return [];
  const facts = [`#${pr.number}`];
  if (pr.state !== undefined && pr.state !== '') facts.push(pr.state);
  if (pr.held !== undefined && pr.held.length > 0) facts.push(`held: ${pr.held.join(', ')}`);
  return [
    <span key="pr" className="bit bit--mono">
      {facts.join(' · ')}
    </span>,
  ];
}

function refBits(refs: Ref[], prefix: string): ReactNode[] {
  return refs.map((r) => (
    <span key={`${prefix}:${r.id}`} className="bit bit--ref">
      <BeadId id={r.id} /> <span className="ref-title">{r.title}</span> <Show id={r.id} />
    </span>
  ));
}

// ── Details ───────────────────────────────────────────────────────────────

/** Details, opened in place under its row and above its children: the bead's
 *  whole description, an epic's contract and last ruling, the pull request's
 *  facts with its link, what the bead waits on and what waits on it. */
export function DetailsBlock({ row, depth }: { row: Row; depth: number }) {
  const v = useView();
  const fields: [string, ReactNode][] = [];
  if (row.kind === 'epic') {
    const c = row.contract ?? {};
    const none = 'None recorded.';
    fields.push(['Title', row.title]);
    fields.push(['Hypothesis', c.hypothesis || none]);
    fields.push(['Boundaries', c.boundaries || none]);
    fields.push(['Closure condition', c.closure_condition || none]);
    fields.push(['Leading indicators', c.indicators || none]);
    fields.push(['Last ruling', rulingOf(row) || none]);
  }
  if (row.pull_request !== undefined) {
    const pr = row.pull_request;
    const facts = [pr.state, pr.held !== undefined && pr.held.length > 0 ? `held: ${pr.held.join(', ')}` : '']
      .filter((x) => x !== undefined && x !== '')
      .join(', ');
    fields.push([
      'Pull request',
      <>
        {pr.url !== undefined && pr.url !== '' ? (
          <a href={pr.url} target="_blank" rel="noreferrer noopener">
            #{pr.number}
          </a>
        ) : (
          `#${pr.number}`
        )}
        {facts !== '' && <span className="muted"> {facts}</span>}
      </>,
    ]);
  }
  fields.push(['Status', row.status + (row.assignee !== undefined && row.assignee !== '' ? `, assigned to ${row.assignee}` : '')]);

  const refs: [string, Ref[]][] = [];
  if (row.conversation !== undefined && row.conversation !== '') {
    refs.push(['Conversation', [{ id: row.conversation, title: v.doc.rows[row.conversation]?.title ?? '' }]]);
  }
  refs.push(['Waits on', row.waits]);
  refs.push(['What waits on it', row.waited_on_by]);
  refs.push(['Holds', row.holds.map((id) => ({ id, title: v.doc.rows[id]?.title ?? '' }))]);
  refs.push(['Anchored to it', row.anchored ?? []]);

  return (
    <div className="details-block" style={{ marginLeft: depth * STEP + 12 + 60 }}>
      <Description id={row.id} />
      {fields.map(([k, val]) => (
        <div key={k} className="field">
          <span className="field-key">{k}</span>
          <span className="field-value">{val}</span>
        </div>
      ))}
      {refs.map(([k, list]) =>
        list.map((r, i) => <RefLine key={`${k}:${r.id}`} label={i === 0 ? k : ''} target={r} />),
      )}
      <div className="details-actions">
        <button type="button" className="button button--small" onClick={() => v.openPanel({ kind: 'discuss', bead: row.id, title: row.title })}>
          Discuss
        </button>
      </div>
    </div>
  );
}

function rulingOf(row: Row): string {
  const c = row.contract;
  if (c === undefined || c.ruling === undefined || c.ruling === '') return '';
  let s = c.ruling;
  if (c.ruling_reason !== undefined && c.ruling_reason !== '') s += `: ${c.ruling_reason}`;
  if (c.ruling_at !== undefined && c.ruling_at !== '') s += ` (${c.ruling_at})`;
  return s;
}

/** One bead a Details block names: its id, which copies, its title, which
 *  finds it on the board, and where it stands. */
function RefLine({ label, target }: { label: string; target: Ref }) {
  const v = useView();
  const far = v.doc.rows[target.id];
  return (
    <div className="ref">
      <span className="field-key">{label}</span>
      <span className="ref-id">
        <BeadId id={target.id} />
      </span>
      <button type="button" className="link ref-name" title="Find this bead on the board" onClick={() => v.show(target.id)}>
        {target.title !== '' ? target.title : target.id}
      </button>
      <span className="ref-state" style={{ color: far !== undefined ? signalInk(far) : MUTE }}>
        {far?.signal ?? ''}
      </span>
    </div>
  );
}

// ── Epics, Deliveries and their groups ─────────────────────────────────────

/** An epic and everything under it: its own asks, its Deliveries, and the rest
 *  of its work in the four groups. */
export function EpicBlock({ entry, index }: { entry: EpicEntry; index: number }) {
  const v = useView();
  const row = v.doc.rows[entry.id];
  if (row === undefined) return <ObjectRow id={entry.id} ctx="epics" depth={0} role="item" bare />;
  const key = `e:${entry.id}`;
  const open = v.isOpen(key, false);
  const detailsKey = `${key}/details`;
  const detailsOpen = v.isOpen(detailsKey, false);
  const hue = EPIC_HUES[index % EPIC_HUES.length];
  const restKey = `${key}/rest`;
  const hasRest = entry.groups.length > 0 || entry.unread.length > 0;

  // A count's click opens its epic, and in each place under it, that group only.
  const focus = (g: Group) => {
    const parts: Record<string, boolean> = { [key]: true };
    for (const d of entry.deliveries) {
      const dKey = `${key}/d:${d.id}`;
      const has = d.groups.some((l) => l.group === g);
      parts[dKey] = has;
      for (const { group } of GROUPS) parts[`${dKey}/g:${group}`] = group === g;
    }
    parts[restKey] = entry.groups.some((l) => l.group === g);
    const restCtx = entry.deliveries.length > 0 ? restKey : key;
    for (const { group } of GROUPS) parts[`${restCtx}/g:${group}`] = group === g;
    v.setOpen(parts);
  };

  return (
    <>
      <Line
        depth={0}
        look="epic"
        gap={10}
        bg={hue.tint}
        rule={hue.hue}
        hasKids
        open={open}
        onToggle={() => v.flip(key, false)}
        priority={row.priority}
        hue={hue.hue}
        title={titleOf(row)}
        signal={{ text: row.signal, note: row.note, ink: signalInk(row) }}
        details={{ open: detailsOpen, onToggle: () => v.flip(detailsKey, false) }}
        id={row.id}
        line2={row.line2}
        bits={countBits(row.counts, focus)}
      />
      {detailsOpen && <DetailsBlock row={row} depth={0} />}
      {open && (
        <div className="epic-body">
          {entry.asks.map((a) => (
            <ObjectRow key={a} id={a} ctx={key} depth={1} role="ask" bare />
          ))}
          {entry.deliveries.map((d) => (
            <DeliveryBlock key={d.id} entry={d} epicKey={key} />
          ))}
          {entry.deliveries.length > 0 && hasRest ? (
            <RestOfEpic entry={entry} ctx={restKey} />
          ) : (
            <Groups ctx={key} depth={1} groups={entry.groups} unread={entry.unread} />
          )}
        </div>
      )}
    </>
  );
}

function RestOfEpic({ entry, ctx }: { entry: EpicEntry; ctx: string }) {
  const v = useView();
  const open = v.isOpen(ctx, true);
  const counts = countsOf(entry.groups);
  return (
    <>
      <Line
        depth={1}
        look="delivery"
        bg={BAND}
        rule={RULE}
        hasKids
        open={open}
        onToggle={() => v.flip(ctx, true)}
        title="The rest of the epic"
        bits={countBits(counts, (g) => {
          const parts: Record<string, boolean> = { [ctx]: true };
          for (const { group } of GROUPS) parts[`${ctx}/g:${group}`] = group === g;
          v.setOpen(parts);
        })}
      />
      {open && <Groups ctx={ctx} depth={2} groups={entry.groups} unread={entry.unread} />}
    </>
  );
}

function DeliveryBlock({ entry, epicKey }: { entry: DeliveryEntry; epicKey: string }) {
  const v = useView();
  const row = v.doc.rows[entry.id];
  if (row === undefined) return <ObjectRow id={entry.id} ctx={epicKey} depth={1} role="item" bare />;
  const key = `${epicKey}/d:${entry.id}`;
  // A Delivery whose work has all closed folds by default.
  const done = entry.groups.length > 0 && entry.groups.every((l) => l.group === 'Closed');
  const open = v.isOpen(key, !done);
  const detailsKey = `${key}/details`;
  const detailsOpen = v.isOpen(detailsKey, false);
  const focus = (g: Group) => {
    const parts: Record<string, boolean> = { [epicKey]: true, [key]: true };
    for (const { group } of GROUPS) parts[`${key}/g:${group}`] = group === g;
    v.setOpen(parts);
  };
  return (
    <>
      <Line
        depth={1}
        look="delivery"
        bg={BAND}
        rule={RULE}
        hasKids
        open={open}
        onToggle={() => v.flip(key, !done)}
        priority={row.priority}
        tag={tagOf(row, false)}
        title={row.title}
        signal={{ text: row.signal, note: row.note, ink: signalInk(row) }}
        details={{ open: detailsOpen, onToggle: () => v.flip(detailsKey, false) }}
        id={row.id}
        line2={row.line2}
        bits={countBits(row.counts, focus)}
      />
      {detailsOpen && <DetailsBlock row={row} depth={1} />}
      {open && (
        <>
          {entry.asks.map((a) => (
            <ObjectRow key={a} id={a} ctx={key} depth={2} role="ask" bare />
          ))}
          <Groups ctx={key} depth={2} groups={entry.groups} unread={entry.unread} />
        </>
      )}
    </>
  );
}

/** A container's work in its groups, then the work a reader could not answer. */
function Groups({ ctx, depth, groups, unread }: { ctx: string; depth: number; groups: GroupList[]; unread: string[] }) {
  return (
    <>
      {groups.map((l) => (
        <Heading
          key={l.group}
          openKey={`${ctx}/g:${l.group}`}
          def={groupOpenByDefault(l.group)}
          depth={depth}
          label={l.group}
          count={l.ids.length}
          group={l.group}
        >
          {l.ids.map((id) => (
            <ObjectRow key={id} id={id} ctx={`${ctx}/g:${l.group}`} depth={depth + 1} role="item" />
          ))}
        </Heading>
      ))}
      {unread.length > 0 && (
        <Heading openKey={`${ctx}/unread`} def depth={depth} label="Unread" count={unread.length}>
          {unread.map((id) => (
            <ObjectRow key={id} id={id} ctx={`${ctx}/unread`} depth={depth + 1} role="item" />
          ))}
        </Heading>
      )}
    </>
  );
}

/** A container's counts, one per group, each opening that group only. */
function countBits(counts: Counts | undefined, focus: (g: Group) => void): ReactNode[] {
  if (counts === undefined) return [];
  return GROUPS.map(({ group, count }) => {
    const n = counts[count];
    const look = GROUP_LOOK[group];
    const dot = (
      <span
        className="dot dot--small"
        aria-hidden="true"
        style={{ background: n > 0 ? look.fill : 'transparent', borderColor: n > 0 ? look.ring : '#A9B0B6' }}
      />
    );
    const text = `${n} ${look.word}`;
    return (
      <span key={group} className="bit bit--count" style={{ color: n > 0 ? look.ink : '#65707B' }}>
        {dot}
        {n > 0 ? (
          <button type="button" className="link" title="Open just this group" onClick={() => focus(group)}>
            {text}
          </button>
        ) : (
          <span>{text}</span>
        )}
      </span>
    );
  });
}

/** The rows a container's groups list, by group, for a count line of its own. */
function countsOf(groups: GroupList[]): Counts {
  const c: Counts = { waiting_on_you: 0, queued: 0, not_moving: 0, closed: 0 };
  for (const l of groups) {
    const g = GROUPS.find((x) => x.group === l.group);
    if (g !== undefined) c[g.count] = l.ids.length;
  }
  return c;
}

// ── Headings ──────────────────────────────────────────────────────────────

export interface HeadingProps {
  openKey: string;
  def: boolean;
  depth: number;
  label: string;
  count: number;
  /** The group whose colours the heading takes, if one. */
  group?: Group;
  /** A page's own section, drawn larger than a group under a row. */
  section?: boolean;
  gap?: number;
  ink?: string;
  children?: ReactNode;
}

/** A heading row: a page's section, or a group under a container. Its chevron
 *  folds what it lists. */
export function Heading({ openKey, def, depth, label, count, group, section, gap, ink, children }: HeadingProps) {
  const v = useView();
  const open = v.isOpen(openKey, def);
  const look = group !== undefined ? GROUP_LOOK[group] : undefined;
  return (
    <>
      <Line
        depth={depth}
        look={section === true ? 'section' : 'heading'}
        gap={gap}
        hasKids
        open={open}
        onToggle={() => v.flip(openKey, def)}
        dot={look !== undefined ? { fill: look.fill, ring: look.ring } : undefined}
        title={label}
        count={count}
        titleInk={ink ?? look?.ink ?? INK}
      />
      {open && children}
    </>
  );
}

/** A line of the page's own prose, with any actions beside it. */
export function Note({ children, actions }: { children: ReactNode; actions?: ReactNode }) {
  return (
    <div className="note-line">
      <p>{children}</p>
      {actions}
    </div>
  );
}
