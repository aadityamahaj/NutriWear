"use client";

import { useCallback, useEffect, useState } from "react";

const KEY = "nutriwear.pairing.code";

/** Generate a short, readable pairing code (no ambiguous chars). */
export function generateCode(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let out = "";
  for (let i = 0; i < 4; i++) {
    out += alphabet[Math.floor(Math.random() * alphabet.length)];
  }
  return out;
}

/** Shared pairing code persisted in localStorage so both roles can reuse it. */
export function usePairingCode(): [string, (c: string) => void] {
  const [code, setCodeState] = useState("");

  useEffect(() => {
    let existing = localStorage.getItem(KEY);
    if (!existing) {
      existing = generateCode();
      localStorage.setItem(KEY, existing);
    }
    setCodeState(existing);
  }, []);

  const setCode = useCallback((c: string) => {
    const up = c.toUpperCase().slice(0, 4);
    localStorage.setItem(KEY, up);
    setCodeState(up);
  }, []);

  return [code, setCode];
}
