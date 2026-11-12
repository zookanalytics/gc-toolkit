// What every part of the page shares: the document, the page's own view state
// (what is open, what search holds, which bead id control just copied), and
// the moves a row can make. The document decides every group, signal, count,
// ask, section and order; the view decides only what is folded and what is
// shown.

import { createContext, useContext } from 'react';
import type { ActuateError, ActuateResult } from '../actuate/client';
import type { Counts, Document, Group, Row } from './document.gen';

/** Where an engage the page sent stands. */
export type EngageAnswer =
  | { phase: 'running' }
  | { phase: 'done'; result: ActuateResult }
  | { phase: 'failed'; error: ActuateError };

/** The side panel, where the design draws its terminal: an engage's answer, or
 *  Discuss's form, for one bead. */
export type PanelState =
  | { kind: 'engage'; bead: string; title: string; answer: EngageAnswer }
  | { kind: 'discuss'; bead: string; title: string };

export interface View {
  doc: Document;
  /** Whether the part at key is open, def when the operator has not set it. */
  isOpen(key: string, def: boolean): boolean;
  /** Fold or unfold the part at key. */
  flip(key: string, def: boolean): void;
  /** Set several parts at once, as a count's click opens one group. */
  setOpen(parts: Record<string, boolean>): void;
  /** Copy an id to the clipboard for the bead id control whose key is from
   *  (useCopy, CopyButton). */
  copy(id: string, from: string): void;
  /** The key of the bead id control whose copy shows its success, for a
   *  moment once the clipboard has taken it. */
  copied: string | null;
  /** Fill search with an id, which lists the rows that match it. */
  show(id: string): void;
  /** Open Discuss's form for a bead in the side panel. */
  openPanel(panel: Extract<PanelState, { kind: 'discuss' }>): void;
  /** Engage a question, a decision or a conversation, and show the answer in
   *  the side panel. */
  engage(bead: string, title: string): void;
}

export const ViewContext = createContext<View | null>(null);

export function useView(): View {
  const v = useContext(ViewContext);
  if (v === null) throw new Error('helm: a row rendered outside the board');
  return v;
}

/** The depth step, in pixels: each level under a row sits this much further in. */
export const STEP = 20;

/** The look of each group: its word for a count, its ink, and its dot. */
export const GROUP_LOOK: Record<Group, { word: string; ink: string; fill: string; ring: string }> = {
  'Waiting on you': { word: 'on you', ink: '#8A5300', fill: '#D98A00', ring: '#D98A00' },
  Queued: { word: 'queued', ink: '#1F5FBF', fill: '#2F6FDE', ring: '#2F6FDE' },
  'Not moving': { word: 'not moving', ink: '#55606B', fill: 'transparent', ring: '#7A838C' },
  Closed: { word: 'closed', ink: '#1E7A4C', fill: '#2E9B63', ring: '#2E9B63' },
};

/** The groups in the order a container lists them, and each one's count. */
export const GROUPS: { group: Group; count: keyof Counts }[] = [
  { group: 'Waiting on you', count: 'waiting_on_you' },
  { group: 'Queued', count: 'queued' },
  { group: 'Not moving', count: 'not_moving' },
  { group: 'Closed', count: 'closed' },
];

/** Waiting on you and Queued open by default, and Not moving and Closed fold,
 *  as the export draws them. */
export function groupOpenByDefault(g: Group): boolean {
  return g === 'Waiting on you' || g === 'Queued';
}

export const INK = '#1B1F23';
export const MUTE = '#55606B';
export const AMBER = '#8A5300';

/** The ink of a row's signal: its group's, and muted for a row no group holds. */
export function signalInk(row: Row): string {
  return row.group !== undefined ? GROUP_LOOK[row.group].ink : MUTE;
}

/** Each epic's hue on the Epics page, by its place in the list. */
export const EPIC_HUES: { hue: string; tint: string }[] = [
  { hue: '#6F6AA8', tint: '#EFEEF8' },
  { hue: '#4E8C8C', tint: '#E8F3F3' },
  { hue: '#A8708F', tint: '#F8EDF3' },
];
