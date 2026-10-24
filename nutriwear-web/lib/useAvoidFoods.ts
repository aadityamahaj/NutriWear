"use client";

import { useCallback, useEffect, useState } from "react";

const KEY = "nutriwear.avoidFoods";

/**
 * The user's "foods to avoid" list, persisted locally. Learned from meals rated
 * poorly after eating, plus manual edits. Matching is substring both ways so
 * "fries" matches "French fries".
 */
export function useAvoidFoods() {
  const [foods, setFoods] = useState<string[]>([]);

  useEffect(() => {
    try {
      const raw = localStorage.getItem(KEY);
      if (raw) setFoods(JSON.parse(raw));
    } catch {
      /* ignore */
    }
  }, []);

  const persist = useCallback((next: string[]) => {
    const deduped = Array.from(new Set(next.map((f) => f.toLowerCase().trim()).filter(Boolean))).sort();
    setFoods(deduped);
    try {
      localStorage.setItem(KEY, JSON.stringify(deduped));
    } catch {
      /* ignore */
    }
  }, []);

  const add = useCallback((name: string) => persist([...foods, name]), [foods, persist]);
  const addMany = useCallback((names: string[]) => persist([...foods, ...names]), [foods, persist]);
  const remove = useCallback(
    (name: string) => persist(foods.filter((f) => f !== name.toLowerCase().trim())),
    [foods, persist]
  );

  /** Names from `items` that are on the avoid list. */
  const matches = useCallback(
    (items: { name: string }[]): string[] =>
      items
        .filter((it) => {
          const n = it.name.toLowerCase();
          return foods.some((a) => n.includes(a) || a.includes(n));
        })
        .map((it) => it.name),
    [foods]
  );

  return { foods, add, addMany, remove, matches };
}
