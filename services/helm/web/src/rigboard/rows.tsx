// The rows the pages are made of, and the two views every page lays out. An
// object is drawn the same way wherever it sits: a need reads as a need on
// every page, with its tint, its kind and what holds it. A page decides only
// what nests under a row. On a Needs you view a need is the row and the beads
// it holds there are its children; on a Work queue a bead nests nothing, since
// the Needs you view beside it lists what holds it.

import type { ReactNode } from 'react';
import type { Counts, DeliveryEntry, EpicEntry, Group, Need, Ref, Row, WorkQueue } from './document.gen';
import { Description } from './Description';
import { BeadId, Line, Show } from './Line';
import {
  AMBER,
  COUNTS,
  EPIC_HUES,
  GROUP_LOOK,
  INK,
  MUTE,
  STEP,
  signalInk,
  useView,
  type Part,
  type View,
} from './view';

const WHITE = '#FFFFFF';
const BAND = '#ECEDE7';
const RULE = '#E6E7E2';
const ASK_TINT = '#FFF8E3';

/** The word a row's tag reads when the row is no need. */
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
  /** The rows drawn beneath it: under a need on a Needs you view, the beads it
   *  holds there. A row anywhere else nests none. */
  kids?: string[];
}

export function ObjectRow({ id, ctx, depth, kids }: ObjectRowProps) {
  const v = useView();
  const row = v.doc.rows[id];
  if (row === undefined) {
    return (
      <Line depth={depth} look="item" rule={RULE} hasKids={false} open={false} onToggle={() => {}} title="Not in the board's document" titleInk={MUTE} id={id} />
    );
  }
  const key = `${ctx}/${id}`;
  const childIds = kids ?? [];
  const kidsKey = `${key}/kids`;
  const kidsOpen = v.isOpen(kidsKey, true);
  const detailsKey = `${key}/details`;
  const detailsOpen = v.isOpen(detailsKey, false);
  const closed = row.group === 'Closed';
  const need = row.ask !== undefined;

  const bits: ReactNode[] = [...pullRequestBits(row), ...refBits(row.line3 ?? [], 'line3')];
  if (need) {
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
    if (row.holds.length > 0) {
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
        bg={need && row.group === 'Waiting on you' ? ASK_TINT : WHITE}
        rule={RULE}
        hasKids={childIds.length > 0}
        open={kidsOpen}
        onToggle={() => v.flip(kidsKey, true)}
        priority={row.priority}
        tag={tagOf(row)}
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
      {kidsOpen && childIds.map((c) => <ObjectRow key={c} id={c} ctx={key} depth={depth + 1} />)}
    </>
  );
}

/** A need's tag is its kind, in amber while it waits on you, and any other
 *  row's is its kind of object where it is no piece of work. */
function tagOf(row: Row): { text: string; ink: string; weight?: number } | undefined {
  if (row.ask !== undefined) {
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

// ── The two views ─────────────────────────────────────────────────────────

/** What a container lays out: its two views and its closed work. An epic's
 *  and a Delivery's entries are each one. */
interface Views {
  needs: Need[];
  queue: WorkQueue;
  closed: string[];
}

/** A Needs you view: each need, in the document's order, with the beads it
 *  holds there beneath it. */
export function NeedsList({ needs, ctx, depth }: { needs: Need[]; ctx: string; depth: number }) {
  return (
    <>
      {needs.map((n) => (
        <ObjectRow key={n.id} id={n.id} ctx={ctx} depth={depth} kids={n.holds} />
      ))}
    </>
  );
}

/** A Work queue view: the queue in its order, then the work after it under
 *  Not scheduled, folded, then the work a reader could not answer. */
export function QueueList({ queue, ctx, depth }: { queue: WorkQueue; ctx: string; depth: number }) {
  const { doc } = useView();
  return (
    <>
      {queue.queue.map((id) => (
        <ObjectRow key={id} id={id} ctx={ctx} depth={depth} />
      ))}
      {queue.not_scheduled.length > 0 && (
        <Heading
          openKey={`${ctx}/not-scheduled`}
          def={false}
          depth={depth}
          label="Not scheduled"
          count={queue.not_scheduled.length}
          group={sharedGroup(doc.rows, queue.not_scheduled)}
        >
          {queue.not_scheduled.map((id) => (
            <ObjectRow key={id} id={id} ctx={`${ctx}/not-scheduled`} depth={depth + 1} />
          ))}
        </Heading>
      )}
      {queue.unread.length > 0 && (
        <Heading openKey={`${ctx}/unread`} def depth={depth} label="Unread" count={queue.unread.length}>
          {queue.unread.map((id) => (
            <ObjectRow key={id} id={id} ctx={`${ctx}/unread`} depth={depth + 1} />
          ))}
        </Heading>
      )}
    </>
  );
}

/** How many rows a Work queue view lists. */
export function queueSize(q: WorkQueue): number {
  return q.queue.length + q.not_scheduled.length + q.unread.length;
}

/** The group every row of a list reads in, which colours its heading, or
 *  undefined when they read in more than one. */
function sharedGroup(rows: Record<string, Row>, ids: string[]): Group | undefined {
  const groups = new Set(ids.map((id) => rows[id]?.group));
  if (groups.size !== 1) return undefined;
  const [g] = groups;
  return g !== undefined && g in GROUP_LOOK ? g : undefined;
}

/** A container's two views and its closed work: Needs you, the Work queue, and
 *  its closed work, folded. A view with nothing in it is not drawn. */
function ContainerViews({ views, ctx, depth }: { views: Views; ctx: string; depth: number }) {
  const { doc } = useView();
  const queued = queueSize(views.queue);
  return (
    <>
      {views.needs.length > 0 && (
        <Heading
          openKey={`${ctx}/needs`}
          def
          depth={depth}
          label="Needs you"
          count={views.needs.length}
          group={sharedGroup(
            doc.rows,
            views.needs.map((n) => n.id),
          )}
        >
          <NeedsList needs={views.needs} ctx={`${ctx}/needs`} depth={depth + 1} />
        </Heading>
      )}
      {queued > 0 && (
        <Heading
          openKey={`${ctx}/queue`}
          def
          depth={depth}
          label="Work queue"
          count={queued}
          group={sharedGroup(doc.rows, [...views.queue.queue, ...views.queue.not_scheduled, ...views.queue.unread])}
        >
          <QueueList queue={views.queue} ctx={`${ctx}/queue`} depth={depth + 1} />
        </Heading>
      )}
      {views.closed.length > 0 && (
        <Heading openKey={`${ctx}/closed`} def={false} depth={depth} label="Closed" count={views.closed.length} group="Closed">
          {views.closed.map((id) => (
            <ObjectRow key={id} id={id} ctx={`${ctx}/closed`} depth={depth + 1} />
          ))}
        </Heading>
      )}
    </>
  );
}

/** Whether a container's views hold anything of one part a count opens. */
function holdsPart(views: Views, part: Part): boolean {
  switch (part) {
    case 'needs':
      return views.needs.length > 0;
    case 'queue':
      return views.queue.queue.length > 0;
    case 'not_scheduled':
      return views.queue.not_scheduled.length > 0;
    case 'closed':
      return views.closed.length > 0;
  }
}

/** The folds that show one part of the views at ctx and nothing else. */
function showOnly(ctx: string, part: Part): Record<string, boolean> {
  return {
    [`${ctx}/needs`]: part === 'needs',
    [`${ctx}/queue`]: part === 'queue' || part === 'not_scheduled',
    [`${ctx}/queue/not-scheduled`]: part === 'not_scheduled',
    [`${ctx}/closed`]: part === 'closed',
  };
}

// ── Epics and Deliveries ──────────────────────────────────────────────────

/** An epic and everything under it: its Deliveries, each with its two views
 *  and its closed work, and the same for the work the epic holds nearest. */
export function EpicBlock({ entry, index }: { entry: EpicEntry; index: number }) {
  const v = useView();
  const row = v.doc.rows[entry.id];
  if (row === undefined) return <ObjectRow id={entry.id} ctx="epics" depth={0} />;
  const key = `e:${entry.id}`;
  const open = v.isOpen(key, false);
  const detailsKey = `${key}/details`;
  const detailsOpen = v.isOpen(detailsKey, false);
  const hue = EPIC_HUES[index % EPIC_HUES.length];
  const restKey = `${key}/rest`;
  const hasDeliveries = entry.deliveries.length > 0;
  const ownKey = hasDeliveries ? restKey : key;
  const hasOwn = entry.needs.length > 0 || queueSize(entry.queue) > 0 || entry.closed.length > 0;

  // A count's click opens its epic, and in each place under it, that part only.
  const focus = (part: Part) => {
    const parts: Record<string, boolean> = { [key]: true };
    for (const d of entry.deliveries) {
      const dKey = `${key}/d:${d.id}`;
      parts[dKey] = holdsPart(d, part);
      Object.assign(parts, showOnly(dKey, part));
    }
    if (hasDeliveries) parts[restKey] = holdsPart(entry, part);
    Object.assign(parts, showOnly(ownKey, part));
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
          {entry.deliveries.map((d) => (
            <DeliveryBlock key={d.id} entry={d} epicKey={key} />
          ))}
          {hasDeliveries ? (
            hasOwn && <RestOfEpic entry={entry} ctx={restKey} />
          ) : (
            <ContainerViews views={entry} ctx={key} depth={1} />
          )}
        </div>
      )}
    </>
  );
}

function RestOfEpic({ entry, ctx }: { entry: EpicEntry; ctx: string }) {
  const v = useView();
  const open = v.isOpen(ctx, true);
  const counts: Counts = {
    needs: entry.needs.length,
    queue: entry.queue.queue.length,
    not_scheduled: entry.queue.not_scheduled.length,
    closed: entry.closed.length,
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
        onToggle={() => v.flip(ctx, true)}
        title="The rest of the epic"
        bits={countBits(counts, (part) => v.setOpen({ [ctx]: true, ...showOnly(ctx, part) }))}
      />
      {open && <ContainerViews views={entry} ctx={ctx} depth={2} />}
    </>
  );
}

function DeliveryBlock({ entry, epicKey }: { entry: DeliveryEntry; epicKey: string }) {
  const v = useView();
  const row = v.doc.rows[entry.id];
  if (row === undefined) return <ObjectRow id={entry.id} ctx={epicKey} depth={1} />;
  const key = `${epicKey}/d:${entry.id}`;
  // A Delivery whose work has all closed folds by default.
  const done = entry.needs.length === 0 && queueSize(entry.queue) === 0 && entry.closed.length > 0;
  const open = v.isOpen(key, !done);
  const detailsKey = `${key}/details`;
  const detailsOpen = v.isOpen(detailsKey, false);
  const focus = (part: Part) => v.setOpen({ [epicKey]: true, [key]: true, ...showOnly(key, part) });
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
        tag={tagOf(row)}
        title={row.title}
        signal={{ text: row.signal, note: row.note, ink: signalInk(row) }}
        details={{ open: detailsOpen, onToggle: () => v.flip(detailsKey, false) }}
        id={row.id}
        line2={row.line2}
        bits={countBits(row.counts, focus)}
      />
      {detailsOpen && <DetailsBlock row={row} depth={1} />}
      {open && <ContainerViews views={entry} ctx={key} depth={2} />}
    </>
  );
}

/** A container's counts, needs first, each opening its part of the views
 *  only. */
function countBits(counts: Counts | undefined, focus: (part: Part) => void): ReactNode[] {
  if (counts === undefined) return [];
  return COUNTS.map(({ part, count, one, many, look: group }) => {
    const n = counts[count];
    const look = GROUP_LOOK[group];
    const dot = (
      <span
        className="dot dot--small"
        aria-hidden="true"
        style={{ background: n > 0 ? look.fill : 'transparent', borderColor: n > 0 ? look.ring : '#A9B0B6' }}
      />
    );
    const text = `${n} ${n === 1 ? one : many}`;
    return (
      <span key={part} className="bit bit--count" style={{ color: n > 0 ? look.ink : '#65707B' }}>
        {dot}
        {n > 0 ? (
          <button type="button" className="link" title="Open just this part" onClick={() => focus(part)}>
            {text}
          </button>
        ) : (
          <span>{text}</span>
        )}
      </span>
    );
  });
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
