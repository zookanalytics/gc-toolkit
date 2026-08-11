// The drill-in plane (U8): from a tile, live detail out of the supervisor.
//
// Public surface for the rest of the app. Everything else in this directory is
// an implementation detail — in particular gen/, which is generated from the
// supervisor's OpenAPI document by scripts/gen-supervisor-types.mjs and is not
// edited by hand.

export { CitySignals } from './CitySignals';
export { DrillPanel } from './DrillPanel';
export { PartialNotice } from './PartialNotice';
export { DrillProvider, useDrillContext } from './context';
export { useDrill } from './useDrill';
export { useCitySignals } from './useCitySignals';
export type {
  Bead,
  CityEvent,
  DrillReads,
  ListResult,
  MailCount,
  PendingEntry,
  Session,
} from './client';
export type { StreamState } from './events';
export type { SupervisorOrigin } from './origin';
