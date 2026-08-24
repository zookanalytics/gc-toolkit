import { useCallback, useEffect, useState } from 'react';
import type { Disposition, Dispositions } from '../contract';

// What was decided — the half of the board that the board cannot show.
//
// Every anchor gather filters on status open, so when a sitting concludes and
// its subject closes, the row simply LEAVES the board and nothing afterwards
// says what was decided or why. This panel is that answer, read from
// <mount>/helm/closed.
//
// PULL, NOT PUSH, and that is a ruling rather than a default (operator,
// 2026-08-23: "pull, I won't read a random digest nor can we easily have a
// cadence when my schedule varies"). So it renders only when the operator opens
// it, and unlike the board it does NOT poll: a window is a question asked once,
// and re-asking it on a timer would be the cadence the ruling refuses.

// The windows offered. Wider ones exist — the route takes any duration this
// pack spells — but a picker of four covers the glances an operator actually
// makes, and a free-text box would invite the "2w" the parser has to refuse.
const WINDOWS = ['24h', '7d', '30d'] as const;
type Window = (typeof WINDOWS)[number];

// Document-relative for the same reason the board URL is: the app is served
// under a runtime-city-named prefix, so an absolute path addresses the
// supervisor root and 404s.
const CLOSED_URL = 'helm/closed';

async function fetchClosed(since: Window, signal: AbortSignal): Promise<Dispositions> {
  const res = await fetch(`${CLOSED_URL}?since=${encodeURIComponent(since)}`, {
    signal,
    headers: { Accept: 'application/json' },
  });
  if (!res.ok) {
    // The route answers 502 for a failed gather and 501 where the source
    // backend cannot supply the view at all. Both carry a reason, and showing
    // it beats "something went wrong" — an operator who can read "dolt wedged"
    // knows this is not a quiet fortnight.
    let detail = `HTTP ${res.status}`;
    try {
      const body = (await res.json()) as { error?: string };
      if (body.error) detail = body.error;
    } catch {
      // A non-JSON error body is still an error; keep the status.
    }
    throw new Error(detail);
  }
  return (await res.json()) as Dispositions;
}

// An empty cell reads as "this row has none" rather than as a rendering fault.
const dash = (s: string) => (s === '' ? '—' : s);

function subjectCell(row: Disposition) {
  // A visit with neither a tracks edge nor a continuation-group stamp is still
  // a disposition that happened, so it earns a row that says what it is
  // missing instead of being dropped.
  return row.subject === '' ? '(unlinked)' : row.subject;
}

export function ClosedPanel() {
  const [open, setOpen] = useState(false);
  const [since, setSince] = useState<Window>('24h');
  const [view, setView] = useState<Dispositions | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [reloadToken, setReloadToken] = useState(0);

  const refresh = useCallback(() => setReloadToken((n) => n + 1), []);

  useEffect(() => {
    if (!open) return;
    const controller = new AbortController();
    setLoading(true);
    // The previous window's rows are dropped BEFORE the new ones arrive.
    // Leaving them up under a changed picker would show 7 days of decisions
    // labelled 24h — the same wrong-window failure the parser refuses.
    setView(null);
    fetchClosed(since, controller.signal)
      .then((next) => {
        setView(next);
        setError(null);
      })
      .catch((err: unknown) => {
        if (controller.signal.aborted) return;
        setError(err instanceof Error ? err.message : String(err));
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });
    return () => controller.abort();
  }, [open, since, reloadToken]);

  const rows = view?.rows ?? [];

  return (
    <section className="closed" aria-labelledby="closed-heading">
      <h2 id="closed-heading">
        <button type="button" className="closed-toggle" onClick={() => setOpen((v) => !v)} aria-expanded={open}>
          {open ? '▾' : '▸'} what was decided
        </button>
      </h2>

      {open && (
        <>
          <p className="sub">
            Visits that reached a disposition, newest first — the rows the board drops when a
            sitting concludes. Rows are per VISIT, so a subject with three sittings shows three.
            Read-only: the outcome comes off the closed visit, the takeaway off its subject.
          </p>

          <div className="closed-controls">
            {WINDOWS.map((w) => (
              <button
                key={w}
                type="button"
                className={w === since ? 'window active' : 'window'}
                aria-pressed={w === since}
                onClick={() => setSince(w)}
              >
                {w}
              </button>
            ))}
            <button type="button" onClick={refresh} disabled={loading}>
              {loading ? 'reading…' : 'refresh'}
            </button>
          </div>

          {error && (
            <p className="error" role="alert">
              Could not read what closed: {error}
            </p>
          )}

          {/* The distinction this surface exists to protect. "Nothing was
              decided" and "we could not look" are opposite answers, and only
              one of them means the window was quiet — so the quiet case says
              so in words and is never what an error renders as. */}
          {!error && !loading && view && rows.length === 0 && (
            <p>No visit reached a disposition in the last {view.since}.</p>
          )}

          {rows.length > 0 && (
            <table>
              <thead>
                <tr>
                  <th>closed (UTC)</th>
                  <th>subject</th>
                  <th>rig</th>
                  <th>outcome</th>
                  <th>title</th>
                  <th>why (takeaway at sign-off)</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((row) => (
                  // The visit id is the key, not the subject: rows are
                  // per-visit and one subject legitimately appears more than
                  // once, which a subject-keyed list would collapse or warn on.
                  <tr key={row.visit}>
                    <td>{row.closed_at.slice(0, 16).replace('T', ' ')}</td>
                    <td>{subjectCell(row)}</td>
                    <td>{row.rig}</td>
                    <td>{dash(row.outcome)}</td>
                    <td>{dash(row.subject_title)}</td>
                    <td>{dash(row.takeaway)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}

          {view && rows.length < view.total && (
            <p className="sub">
              Showing the newest {rows.length} of {view.total}.
            </p>
          )}
        </>
      )}
    </section>
  );
}
