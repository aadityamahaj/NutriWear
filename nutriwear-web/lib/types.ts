// Shared domain types for the NutriWear web app + sync layer.

export interface Macros {
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
}

export interface FoodItem {
  name: string;
  portion: string;
  macros: Macros;
  confidence: "high" | "medium" | "low";
}

export type SessionStatus = "idle" | "eating" | "ended";

/** A Whoop-style eating session: auto-detected start, live timer, logged meal. */
export interface EatingSession {
  id: string;
  status: SessionStatus;
  startedAt: number | null; // epoch ms
  endedAt: number | null; // epoch ms
  detectedBy: "auto" | "manual" | null;
  items: FoodItem[]; // what was actually eaten (macros reflect consumed amount)
  coachTip: string | null;
  usedLiveAI: boolean;
  note: string | null;
  // Before/after consumption estimate:
  startCalories?: number; // total on the plate at start
  eatenCalories?: number; // estimated actually eaten
  leftoverCalories?: number; // left on the plate
}

/** The full synced state for one pairing code. */
export interface ChannelState {
  code: string;
  current: EatingSession | null; // active or most-recent session
  history: EatingSession[]; // completed sessions, newest first
  updatedAt: number;
}

export type SyncEvent =
  | { type: "session.started"; session: EatingSession }
  | { type: "session.updated"; session: EatingSession }
  | { type: "session.ended"; session: EatingSession }
  | { type: "state"; state: ChannelState };

export function emptySession(id: string): EatingSession {
  return {
    id,
    status: "idle",
    startedAt: null,
    endedAt: null,
    detectedBy: null,
    items: [],
    coachTip: null,
    usedLiveAI: false,
    note: null,
  };
}

export function sessionTotals(session: EatingSession): Macros {
  return session.items.reduce<Macros>(
    (acc, item) => ({
      calories: acc.calories + item.macros.calories,
      protein: acc.protein + item.macros.protein,
      carbs: acc.carbs + item.macros.carbs,
      fat: acc.fat + item.macros.fat,
    }),
    { calories: 0, protein: 0, carbs: 0, fat: 0 }
  );
}
