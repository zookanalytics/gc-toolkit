import { useCallback, useEffect, useRef, useState } from 'react';

// How long a copy's success shows, in milliseconds.
export const COPIED_MS = 1200;

/**
 * Copying to the clipboard, for a bead id on the board and a command in the
 * side panel. Returns the text copied last, while its success shows, and the
 * move that copies a text.
 *
 * A copy shows its success only once the browser has taken the text. A page
 * with no clipboard, or a browser that refuses the write, shows none, and the
 * text stays on screen to select by hand. A later copy clears an earlier one's
 * success and its timer. A write that answers after a later copy has started,
 * or after the component that holds the copy has unmounted, shows nothing.
 */
export function useCopy(): [string | null, (text: string) => void] {
  const [copied, setCopied] = useState<string | null>(null);
  const timer = useRef<number | undefined>(undefined);
  // The copy whose answer may show; a later copy, or leaving, replaces it.
  const latest = useRef(0);

  useEffect(
    () => () => {
      latest.current++;
      window.clearTimeout(timer.current);
    },
    [],
  );

  const copy = useCallback((text: string) => {
    const token = ++latest.current;
    window.clearTimeout(timer.current);
    setCopied(null);
    void writeClipboard(text).then((taken) => {
      if (!taken || latest.current !== token) return;
      setCopied(text);
      timer.current = window.setTimeout(() => setCopied(null), COPIED_MS);
    });
  }, []);

  return [copied, copy];
}

/** Whether the browser took text onto the clipboard. */
async function writeClipboard(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    // The page has no clipboard, as on an origin that is not secure, or the
    // browser refused the write.
    return false;
  }
}
