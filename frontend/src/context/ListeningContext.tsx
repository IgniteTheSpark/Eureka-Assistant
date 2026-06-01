import { createContext, useContext, useState } from "react";
import type { ReactNode } from "react";

/**
 * ListeningContext — global "the hardware mic is capturing" flag.
 *
 * Set live from the SSE `listening` event (pushed when the W1/W2 card's
 * flash-memo button is held down). The ListeningOverlay reads it to show a
 * full-screen「正在聆听」indicator while the user speaks into the card.
 *
 * Fail-soft: if there's no provider (unit tests), the hook returns a no-op
 * so callers never crash.
 */
interface ListeningContextValue {
  isListening: boolean;
  setListening: (v: boolean) => void;
}

const ListeningContext = createContext<ListeningContextValue | null>(null);

export function ListeningProvider({ children }: { children: ReactNode }) {
  const [isListening, setListening] = useState(false);
  return (
    <ListeningContext.Provider value={{ isListening, setListening }}>
      {children}
    </ListeningContext.Provider>
  );
}

export function useListening(): ListeningContextValue {
  const ctx = useContext(ListeningContext);
  return ctx ?? { isListening: false, setListening: () => {} };
}
