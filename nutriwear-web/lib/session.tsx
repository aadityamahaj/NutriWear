"use client";

import { createContext, useCallback, useContext, useEffect, useState } from "react";
import type { ReactNode } from "react";

/**
 * App session: either a guest (local-only) or a signed-in user (synced to the
 * backend). The choice screen sets this on first open. Supabase auth plugs into
 * `signIn`/`signOut` in a later layer; today "sign in" is wired but gated on
 * Supabase config being present.
 */

export type SessionMode = "unchosen" | "guest" | "signedIn";

export interface SessionUser {
  id: string;
  email: string;
}

interface SessionState {
  mode: SessionMode;
  user: SessionUser | null;
  /** True once we've read persisted state (avoids a flash of the chooser). */
  ready: boolean;
  chooseGuest: () => void;
  setSignedIn: (user: SessionUser) => void;
  signOut: () => void;
}

const MODE_KEY = "nutriwear.session.mode";
const USER_KEY = "nutriwear.session.user";

const SessionContext = createContext<SessionState | null>(null);

export function SessionProvider({ children }: { children: ReactNode }) {
  const [mode, setMode] = useState<SessionMode>("unchosen");
  const [user, setUser] = useState<SessionUser | null>(null);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    try {
      const savedMode = localStorage.getItem(MODE_KEY) as SessionMode | null;
      const savedUser = localStorage.getItem(USER_KEY);
      if (savedUser) setUser(JSON.parse(savedUser));
      if (savedMode === "guest" || savedMode === "signedIn") setMode(savedMode);
    } catch {
      /* ignore corrupt storage */
    }
    setReady(true);
  }, []);

  const chooseGuest = useCallback(() => {
    setMode("guest");
    setUser(null);
    localStorage.setItem(MODE_KEY, "guest");
    localStorage.removeItem(USER_KEY);
  }, []);

  const setSignedIn = useCallback((u: SessionUser) => {
    setMode("signedIn");
    setUser(u);
    localStorage.setItem(MODE_KEY, "signedIn");
    localStorage.setItem(USER_KEY, JSON.stringify(u));
  }, []);

  const signOut = useCallback(() => {
    setMode("unchosen");
    setUser(null);
    localStorage.removeItem(MODE_KEY);
    localStorage.removeItem(USER_KEY);
  }, []);

  return (
    <SessionContext.Provider value={{ mode, user, ready, chooseGuest, setSignedIn, signOut }}>
      {children}
    </SessionContext.Provider>
  );
}

export function useSession(): SessionState {
  const ctx = useContext(SessionContext);
  if (!ctx) throw new Error("useSession must be used within SessionProvider");
  return ctx;
}
