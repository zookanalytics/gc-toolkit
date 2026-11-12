// The four pages and search, each a layout of the document's own lists. The
// Epics page shows the two views, Needs you and the Work queue, for each epic
// and each Delivery; the Needs you and Work queue pages show the same views
// across the rig, drawn and ordered the same way. The document chooses what
// each page lists and in what order; a page lays it out, folds it and filters
// it.

import { EpicBlock, Heading, NeedsList, Note, ObjectRow, QueueList, queueSize } from './rows';
import { AMBER, useView } from './view';

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
      {n.needs.length === 0 ? <Note>Nothing in this rig needs you.</Note> : <NeedsList needs={n.needs} ctx="needs" depth={0} />}
    </>
  );
}

export function WorkQueuePage() {
  const { doc } = useView();
  if (queueSize(doc.work_queue) === 0) return <Note>The Work queue is empty.</Note>;
  return <QueueList queue={doc.work_queue} ctx="queue" depth={0} />;
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
            <ObjectRow key={id} id={id} ctx={`desk/P${p.priority}`} depth={1} />
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
          <ObjectRow key={r.id} id={r.id} ctx="q" depth={1} />
        ))}
        {matches.length === 0 && <Note>Nothing in this rig matches.</Note>}
      </Heading>
    </>
  );
}
