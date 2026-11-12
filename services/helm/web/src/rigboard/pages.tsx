// The four pages and search, each a layout of the document's own lists. The
// document chooses what each page lists and in what order; a page lays it out,
// folds it and filters it.

import type { Group, Row, Section } from './document.gen';
import { EpicBlock, Heading, Note, ObjectRow } from './rows';
import { AMBER, GROUP_LOOK, INK, MUTE, useView } from './view';

export function EpicsPage() {
  const { doc } = useView();
  if (doc.epics.length === 0) return <Note>No epic is open in this rig.</Note>;
  return (
    <>
      {doc.epics.map((e, i) => (
        <EpicBlock key={e.id} entry={e} index={i} />
      ))}
    </>
  );
}

export function NeedsYouPage() {
  const { doc } = useView();
  const n = doc.needs_you;
  const fresh = new Set<string>();
  for (const e of n.no_conversation_yet) for (const a of e.asks) fresh.add(a);
  for (const a of n.no_epic) fresh.add(a);
  return (
    <>
      <div className="lead">
        <span className="lead-count" style={{ color: n.count > 0 ? AMBER : '#1E7A4C' }}>
          {n.count}
        </span>
        <span className="lead-text">
          {n.count === 0
            ? 'Nothing in an epic is waiting on you.'
            : `${n.count === 1 ? 'thing' : 'things'} in an epic ${n.count === 1 ? 'is' : 'are'} waiting on you.`}
        </span>
      </div>
      <Heading openKey="needs/conv" def gap={12} depth={0} label="In conversation" count={n.in_conversation.length} section>
        {n.in_conversation.map((id) => (
          <ObjectRow key={id} id={id} ctx="needs/conv" depth={1} role="ask" />
        ))}
        {n.in_conversation.length === 0 && <Note>No conversation is open.</Note>}
      </Heading>
      <Heading
        openKey="needs/fresh"
        def
        gap={20}
        depth={0}
        label="No conversation yet"
        count={fresh.size}
        section
        ink={fresh.size > 0 ? AMBER : INK}
      >
        {n.no_conversation_yet.map((e) => {
          const epic = doc.rows[e.epic];
          const label = epic !== undefined ? `P${epic.priority} · ${epicName(epic)}` : e.epic;
          return (
            <Heading key={e.epic} openKey={`needs/fresh/${e.epic}`} def depth={1} label={label} count={e.asks.length}>
              {e.asks.map((id) => (
                <ObjectRow key={id} id={id} ctx={`needs/fresh/${e.epic}`} depth={2} role="ask" />
              ))}
            </Heading>
          );
        })}
        {n.no_epic.length > 0 && (
          <Heading openKey="needs/fresh/none" def depth={1} label="No epic" count={n.no_epic.length} ink={MUTE}>
            {n.no_epic.map((id) => (
              <ObjectRow key={id} id={id} ctx="needs/fresh/none" depth={2} role="ask" />
            ))}
          </Heading>
        )}
        {fresh.size === 0 && <Note>Nothing here. Every ask already has a conversation.</Note>}
      </Heading>
    </>
  );
}

function epicName(epic: Row): string {
  const handle = epic.contract?.handle?.trim() ?? '';
  return handle !== '' ? handle : epic.title;
}

export function WorkQueuePage() {
  const { doc } = useView();
  return (
    <>
      {doc.work_queue.length === 0 && <Note>The Work queue is empty.</Note>}
      {doc.work_queue.map((s, i) => (
        <QueueSection key={s.name} section={s} ctx={`queue/${s.name}`} depth={0} gap={i > 0 ? 16 : 0} />
      ))}
      <Note>Work that waits on you directly is on Needs you.</Note>
    </>
  );
}

function QueueSection({ section, ctx, depth, gap }: { section: Section; ctx: string; depth: number; gap?: number }) {
  const { doc } = useView();
  const rows = section.rows.length + (section.parts ?? []).reduce((n, p) => n + p.rows.length, 0);
  const group = sharedGroup(doc.rows, section);
  return (
    <Heading
      openKey={ctx}
      def={section.name !== 'Not scheduled'}
      depth={depth}
      gap={gap}
      label={section.name}
      count={rows}
      section={depth === 0}
      group={group}
    >
      {section.rows.map((e) => (
        <ObjectRow key={e.id} id={e.id} ctx={ctx} depth={depth + 1} role="item" kids={e.children} />
      ))}
      {(section.parts ?? []).map((p) => (
        <QueueSection key={p.name} section={p} ctx={`${ctx}/${p.name}`} depth={depth + 1} />
      ))}
    </Heading>
  );
}

/** The group every row a section draws shares, which colours its heading, or
 *  undefined when its rows sit in more than one. */
function sharedGroup(rows: Record<string, Row>, section: Section): Group | undefined {
  const groups = new Set<Group | undefined>();
  const visit = (s: Section) => {
    for (const e of s.rows) {
      for (const id of e.children !== undefined && e.children.length > 0 ? e.children : [e.id]) groups.add(rows[id]?.group);
    }
    for (const p of s.parts ?? []) visit(p);
  };
  visit(section);
  if (groups.size !== 1) return undefined;
  const [g] = groups;
  return g !== undefined && g in GROUP_LOOK ? g : undefined;
}

export function UnprioritizedPage() {
  const { doc } = useView();
  return (
    <>
      <Note>New work carries the label hold:mayor until the Product Owner places it in an epic.</Note>
      {doc.unprioritized.length === 0 && <Note>No open bead in this rig carries hold:mayor.</Note>}
      {doc.unprioritized.map((p) => (
        <Heading key={p.priority} openKey={`desk/P${p.priority}`} def depth={0} label={`P${p.priority}`} count={p.ids.length} section>
          {p.ids.map((id) => (
            <ObjectRow key={id} id={id} ctx={`desk/P${p.priority}`} depth={1} role="item" />
          ))}
        </Heading>
      ))}
    </>
  );
}

/** Every row of the document whose id, title or second line holds the search,
 *  in the document's own order. */
export function MatchesPage({ query, onBack }: { query: string; onBack: () => void }) {
  const { doc } = useView();
  const q = query.trim().toLowerCase();
  const matches = Object.values(doc.rows).filter((r) =>
    `${r.id}\n${r.title}\n${r.line2 ?? ''}`.toLowerCase().includes(q),
  );
  return (
    <>
      <Note
        actions={
          <button type="button" className="button" onClick={onBack}>
            Back to the board
          </button>
        }
      >
        Showing matches only.
      </Note>
      <Heading openKey="q/head" def depth={0} label={`Matches for “${query.trim()}”`} count={matches.length} section>
        {matches.map((r) => (
          <ObjectRow key={r.id} id={r.id} ctx="q" depth={1} role={r.ask !== undefined ? 'ask' : 'item'} />
        ))}
        {matches.length === 0 && <Note>Nothing in this rig matches.</Note>}
      </Heading>
    </>
  );
}
