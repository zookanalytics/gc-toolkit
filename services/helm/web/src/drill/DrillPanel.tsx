// The drill-in panel: one anchor, live.
//
// Structure only, like the rest of the app until U6 — a readable panel, not a
// designed one. The visual direction is the Claude Design loop's output and
// lands on top of this; what it needs from here is that every piece of state
// the operator dives in for is present and honest, including the states where
// something is missing.

import type { CityEvent, Session } from './client';
import { PartialNotice } from './PartialNotice';
import { useDrill } from './useDrill';

export interface DrillPanelProps {
  /** Bead id of the tile being drilled into; null closes the panel. */
  beadId: string | null;
  onClose: () => void;
}

const STREAM_LABEL: Record<string, string> = {
  connecting: 'connecting…',
  open: 'live',
  degraded: 'live (some frames unreadable)',
  closed: 'reconnecting…',
};

export function DrillPanel({ beadId, onClose }: DrillPanelProps) {
  const {
    bead,
    session,
    sessionUncertain,
    activity,
    activityIncomplete,
    partialErrors,
    loading,
    error,
    stream,
    unavailable,
    reload,
  } = useDrill(beadId);

  if (beadId === null) return null;

  return (
    <aside className="drill" aria-label={`detail for ${beadId}`}>
      <header className="drill-head">
        <div>
          <h2>{bead?.title ?? beadId}</h2>
          <p className="sub">
            {bead === null ? beadId : `${beadId} · ${bead.issue_type} · ${bead.status}`}
            {' · '}
            <span className={`stream stream-${stream}`}>{STREAM_LABEL[stream] ?? stream}</span>
          </p>
        </div>
        <div className="drill-actions">
          <button type="button" onClick={reload} disabled={loading}>
            {loading ? 'loading…' : 'refresh'}
          </button>
          <button type="button" onClick={onClose}>
            close
          </button>
        </div>
      </header>

      {unavailable && (
        <p className="error" role="alert">
          The drill-in plane could not work out which city this board belongs to. It reads the city
          name from the service mount path (/v0/city/&lt;city&gt;/svc/helm/), so this happens when
          the app is served from somewhere else.
        </p>
      )}

      {error !== null && (
        <p className="error" role="alert">
          {error}
        </p>
      )}

      {/* One notice for the whole drill: the sections below each say what they
          can and cannot claim, and this carries the reasons behind all of it. */}
      <PartialNotice
        partial={sessionUncertain || activityIncomplete}
        what="part of this drill"
        reasons={partialErrors}
      />

      {bead !== null && (
        <dl className="drill-facts">
          <dt>assignee</dt>
          <dd>{bead.assignee !== undefined && bead.assignee !== '' ? bead.assignee : '—'}</dd>
          <dt>priority</dt>
          <dd>{bead.priority ?? '—'}</dd>
          <dt>updated</dt>
          <dd>{bead.updated_at ?? '—'}</dd>
          {bead.labels != null && bead.labels.length > 0 && (
            <>
              <dt>labels</dt>
              <dd>{bead.labels.join(', ')}</dd>
            </>
          )}
        </dl>
      )}

      {bead?.description !== undefined && bead.description !== '' && (
        <details className="drill-desc">
          <summary>description</summary>
          <pre>{bead.description}</pre>
        </details>
      )}

      <SessionSection session={session} uncertain={sessionUncertain} loading={loading} />

      <section className="drill-activity">
        <h3>activity</h3>
        {activity.length === 0 ? (
          <p className="muted">
            {loading
              ? 'loading…'
              : activityIncomplete
                ? // Nothing matched, but the log did not fully answer — so this
                  // is not the same statement as "nothing happened".
                  'No matching activity in the part of the city log that answered.'
                : 'Nothing for this anchor in the recent city log.'}
          </p>
        ) : (
          <ol>
            {activity.map((event) => (
              <li key={event.seq}>
                <ActivityRow event={event} />
              </li>
            ))}
          </ol>
        )}
      </section>
    </aside>
  );
}

function SessionSection({
  session,
  uncertain,
  loading,
}: {
  session: Session | null;
  uncertain: boolean;
  loading: boolean;
}) {
  if (session === null) {
    return (
      <section className="drill-session">
        <h3>session</h3>
        {/* "Nobody is working this" and "the session list did not answer" look
            identical from here unless this says which one it is, and only one of
            them means the operator can stop watching. */}
        <p className="muted" role={uncertain && !loading ? 'status' : undefined}>
          {loading
            ? 'loading…'
            : uncertain
              ? 'Could not tell whether an agent is working this anchor — the session list came back incomplete.'
              : 'No agent is working this anchor right now.'}
        </p>
      </section>
    );
  }
  return (
    <section className="drill-session">
      <h3>session</h3>
      <p>
        <strong>{session.title || session.alias || session.id}</strong>
        {' · '}
        {session.running ? 'running' : session.state}
        {session.attached ? ' · attached' : ''}
        {session.context_pct !== undefined ? ` · context ${session.context_pct}%` : ''}
      </p>
      {/* The peek snapshot. A live attached terminal is U9's job; this is the
          resting-tile "read the latest output" the epic asks for. */}
      {session.last_output !== undefined && session.last_output !== '' && (
        <pre className="peek">{session.last_output}</pre>
      )}
    </section>
  );
}

function ActivityRow({ event }: { event: CityEvent }) {
  return (
    <>
      <code>{event.type}</code> <span className="muted">{event.ts}</span>
      {event.actor !== '' && <span className="muted"> · {event.actor}</span>}
      {event.message !== undefined && event.message !== '' && <div>{event.message}</div>}
    </>
  );
}
