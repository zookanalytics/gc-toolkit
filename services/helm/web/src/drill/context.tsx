// One place where the drill plane is wired to the running document: resolve the
// supervisor origin from the mount path, build the typed read surface, and open
// at most one shared event stream for everything below.
//
// It is a provider rather than props threaded from App so that the board's own
// component tree barely knows this plane exists — App opens a panel, and the
// panel finds its own data path.

import { createContext, useContext, useMemo, type ReactNode } from 'react';
import { createDrillReads, type DrillReads } from './client';
import { createEventHub, type EventHub } from './events';
import { resolveSupervisorOrigin, type SupervisorOrigin } from './origin';

export interface DrillContextValue {
  origin: SupervisorOrigin;
  reads: DrillReads;
  hub: EventHub;
}

const DrillContext = createContext<DrillContextValue | null>(null);

export interface DrillProviderProps {
  children: ReactNode;
  /**
   * Overrides the origin parsed from the document. Tests set this to avoid
   * depending on a jsdom URL; production never passes it.
   */
  origin?: SupervisorOrigin;
}

export function DrillProvider({ children, origin: override }: DrillProviderProps) {
  const value = useMemo<DrillContextValue | null>(() => {
    const origin = override ?? resolveSupervisorOrigin(window.location);
    if (origin === null) return null;
    return { origin, reads: createDrillReads(origin), hub: createEventHub(origin) };
  }, [override]);

  return <DrillContext.Provider value={value}>{children}</DrillContext.Provider>;
}

/**
 * The drill plane's data path, or null when the document is not served from a
 * service mount and no city could be resolved. Callers render an explanation
 * rather than guessing a city — see origin.ts.
 */
export function useDrillContext(): DrillContextValue | null {
  return useContext(DrillContext);
}
