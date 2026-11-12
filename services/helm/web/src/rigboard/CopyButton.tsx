// A control that copies a text to the clipboard and says so in its own place.

import { useId } from 'react';

/**
 * A button that copies a text through useCopy. It reads its label until its
 * own copy shows its success, and then the word that says so. It copies under
 * a key of its own, so the word shows only on the control clicked, though one
 * bead id can show in many places on a page. Both readings stay laid out in
 * one cell (board.css, .copy), so the control keeps one size whichever it
 * reads, and nothing beside it moves. The reading it does not show is hidden
 * from sight and from assistive technology.
 */
export function CopyButton({
  text,
  label,
  done,
  copied,
  copy,
  className,
  title,
}: {
  /** What the control copies. */
  text: string;
  /** What the control reads at rest. */
  label: string;
  /** What it reads while its copy shows its success. */
  done: string;
  /** The key of the control whose copy shows its success (useCopy). */
  copied: string | null;
  /** The move that copies a text for the control with a key (useCopy). */
  copy: (text: string, from: string) => void;
  className: string;
  title?: string;
}) {
  const self = useId();
  const shown = copied === self;
  return (
    <button type="button" className={`copy ${className}`} title={title} onClick={() => copy(text, self)}>
      <span aria-hidden={shown || undefined}>{label}</span>
      <span aria-hidden={!shown || undefined}>{done}</span>
    </button>
  );
}
