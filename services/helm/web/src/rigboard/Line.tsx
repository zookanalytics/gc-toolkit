// The one row structure every object and every heading is drawn with:
//
//   line 1: chevron, priority, a marker or tag, the title, then three fixed
//           columns on the right: the signal, Details and the bead id. In a
//           narrow board (board.css) the title takes line 1 whole, and the
//           three flow beneath it;
//   line 2: one longer sentence where the row has one, clipped to two lines;
//   line 3: short facts and actions where the row has any.
//
// An empty line takes no height. Only size, weight and background change from
// an epic to a bead. The chevron shows children and nothing else: a row with
// none keeps the chevron's slot empty, and a click on its title opens Details.

import type { ReactNode } from 'react';
import { STEP, useView } from './view';

export interface LineProps {
  /** How far under its parent the row sits, in steps. */
  depth: number;
  /** Which row this is, which sets only its size, weight and padding. */
  look: 'epic' | 'delivery' | 'section' | 'heading' | 'item';
  bg?: string;
  /** The colour of the rule above the row. */
  rule?: string;
  /** Space above the row, in pixels. */
  gap?: number;
  hasKids: boolean;
  open: boolean;
  onToggle: () => void;
  priority?: number;
  /** An epic's square, in its hue. */
  hue?: string;
  /** A heading's dot, in its group's colours. */
  dot?: { fill: string; ring: string };
  tag?: { text: string; ink: string; weight?: number };
  title: string;
  /** A heading's count, beside its title. */
  count?: number;
  titleInk?: string;
  /** A closed row's title reads lighter. */
  quiet?: boolean;
  signal?: { text: string; note?: string; ink: string };
  details?: { open: boolean; onToggle: () => void };
  id?: string;
  line2?: string;
  bits?: ReactNode[];
}

export function Line(p: LineProps) {
  const main = p.hasKids ? p.onToggle : p.details?.onToggle;
  const bits = p.bits ?? [];
  return (
    <div
      className={`line line--${p.look}`}
      style={{
        paddingLeft: p.depth * STEP,
        marginTop: p.gap,
        background: p.bg,
        borderTopColor: p.rule,
      }}
    >
      <div className="line-body">
        <div className="line-1">
          <button
            type="button"
            className="line-main"
            aria-expanded={p.hasKids ? p.open : undefined}
            onClick={main}
          >
            <svg
              className="chevron"
              width="12"
              height="12"
              viewBox="0 0 12 12"
              aria-hidden="true"
              style={{ visibility: p.hasKids ? 'visible' : 'hidden', transform: `rotate(${p.open ? 90 : 0}deg)` }}
            >
              <path d="M4 2l4 4-4 4" />
            </svg>
            <span className="priority">{p.priority !== undefined ? `P${p.priority}` : ''}</span>
            {p.hue !== undefined && <span className="hue" aria-hidden="true" style={{ background: p.hue, borderColor: p.hue }} />}
            {p.dot !== undefined && (
              <span className="dot" aria-hidden="true" style={{ background: p.dot.fill, borderColor: p.dot.ring }} />
            )}
            {p.tag !== undefined && (
              <span className="tag" style={{ color: p.tag.ink, fontWeight: p.tag.weight }}>
                {p.tag.text}
              </span>
            )}
            <span className={p.quiet ? 'title title--quiet' : 'title'} style={{ color: p.titleInk }}>
              {p.title}
              {p.count !== undefined && <span className="count">{p.count}</span>}
            </span>
          </button>
          <span className="signal">
            {p.signal !== undefined && p.signal.text !== '' && (
              <span style={{ color: p.signal.ink }}>{p.signal.text}</span>
            )}
            {p.signal?.note !== undefined && p.signal.note !== '' && (
              <span className="note" title={p.signal.note}>
                {p.signal.note}
              </span>
            )}
          </span>
          <span className="details-slot">
            {p.details !== undefined && (
              <button
                type="button"
                className={p.details.open ? 'link details details--open' : 'link details'}
                aria-expanded={p.details.open}
                onClick={p.details.onToggle}
              >
                Details
              </button>
            )}
          </span>
          <span className="bead-slot">{p.id !== undefined && <BeadId id={p.id} />}</span>
        </div>
        {p.line2 !== undefined && p.line2 !== '' && <div className="line-2">{p.line2}</div>}
        {bits.length > 0 && <div className="line-3">{bits}</div>}
      </div>
    </div>
  );
}

/** A bead id that copies itself on a click. */
export function BeadId({ id }: { id: string }) {
  const v = useView();
  return (
    <button type="button" className="link bead-id" title="Copy the bead ID" onClick={() => v.copy(id)}>
      {v.copied === id ? 'copied' : id}
    </button>
  );
}

/** A "show" link that fills search with an id. */
export function Show({ id }: { id: string }) {
  const v = useView();
  return (
    <button type="button" className="link show" title="Find this bead on the board" onClick={() => v.show(id)}>
      show
    </button>
  );
}
