import { useCallback } from 'react';
import type { Response as RigResponse } from './document.gen';
import { readRig } from './read';
import { usePolledRead, type ReadState } from './usePolledRead';

// The service serves one rig's document from its cache for a minute
// (server.RigBoardTTL), so reading more often than every half minute re-reads
// the same bytes.
export const REFRESH_MS = 30_000;

export type RigDocumentState = ReadState<RigResponse>;

/**
 * One rig's document, read on mount, every REFRESH_MS, and whenever the tab is
 * shown again. A failed read keeps the last good document and records the
 * failure beside it, so the page never draws an empty list from a read that
 * failed. The returned refresh reads again at once, as after a write.
 */
export function useRigDocument(rig: string): [RigDocumentState, () => void] {
  const read = useCallback((signal: AbortSignal) => readRig(rig, signal), [rig]);
  return usePolledRead(read, REFRESH_MS);
}
