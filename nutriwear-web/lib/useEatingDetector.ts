"use client";

import { useEffect, useRef } from "react";

interface Args {
  enabled: boolean;
  captureFrame: (maxDim?: number) => string | null;
  onDetect: (label?: string) => void;
  onHint?: (hint: string) => void;
}

/**
 * Auto start-of-eating detection. Two stages so food can be ANYWHERE in the
 * frame (not just inside the reticle box) without calling the vision model on
 * every tick:
 *
 *  1. Cheap on-device gate — samples the WHOLE frame and measures scene
 *     "richness" (color variance) + stability. A plate of food is visually
 *     busier than an empty table/wall. This just decides "worth a closer look".
 *  2. Vision confirmation — when the cheap gate is interested, send one frame to
 *     /api/detect which asks the model "is there food anywhere here?". Only a
 *     positive confirmation fires onDetect(), so patterned tablecloths and busy
 *     backgrounds no longer cause false starts.
 *
 * The manual "Start eating" button always remains as a fallback.
 */
export function useEatingDetector({ enabled, captureFrame, onDetect, onHint }: Args) {
  const prevHistogram = useRef<number[] | null>(null);
  const richStreak = useRef(0);
  const firedRef = useRef(false);
  const confirmingRef = useRef(false);
  const lastConfirmAt = useRef(0);

  useEffect(() => {
    if (!enabled) {
      firedRef.current = false;
      richStreak.current = 0;
      prevHistogram.current = null;
      confirmingRef.current = false;
      return;
    }

    const tmp = document.createElement("canvas");
    tmp.width = 64;
    tmp.height = 64;
    const ctx = tmp.getContext("2d", { willReadFrequently: true });

    const confirmWithVision = async () => {
      // Throttle vision calls: at most once every 4s.
      const now = Date.now();
      if (confirmingRef.current || now - lastConfirmAt.current < 4000) return;
      const full = captureFrame(640);
      if (!full) return;
      confirmingRef.current = true;
      lastConfirmAt.current = now;
      onHint?.("Checking the plate…");
      try {
        const res = await fetch("/api/detect", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ image: full }),
        });
        const data = await res.json();
        if (data.usedLiveAI) {
          if (data.food && data.confidence >= 0.5) {
            firedRef.current = true;
            onDetect(typeof data.label === "string" ? data.label : undefined);
            return;
          }
          // Model says no food — reset the streak so we don't keep re-asking.
          richStreak.current = 0;
          onHint?.("Watching for your meal…");
        } else {
          // No AI available — fall back to the heuristic alone.
          firedRef.current = true;
          onDetect();
        }
      } catch {
        // Network hiccup — let the heuristic try again next tick.
      } finally {
        confirmingRef.current = false;
      }
    };

    const tick = () => {
      if (firedRef.current || confirmingRef.current || !ctx) return;
      const dataURL = captureFrame(256);
      if (!dataURL) return;

      const img = new Image();
      img.onload = () => {
        // Sample the WHOLE frame (not just the center) so food anywhere counts.
        ctx.drawImage(img, 0, 0, 64, 64);
        const { data } = ctx.getImageData(0, 0, 64, 64);

        // Coarse brightness histogram + mean brightness.
        const hist = new Array(8).fill(0);
        let brightness = 0;
        for (let i = 0; i < data.length; i += 4) {
          const r = data[i], g = data[i + 1], b = data[i + 2];
          brightness += (r + g + b) / 3;
          const bucket = Math.min(7, Math.floor(((r + g + b) / 3) / 32));
          hist[bucket]++;
        }
        const n = data.length / 4;
        brightness /= n;

        // Scene richness = histogram spread (entropy-ish).
        const total = hist.reduce((a, c) => a + c, 0) || 1;
        let entropy = 0;
        for (const h of hist) {
          if (h > 0) {
            const p = h / total;
            entropy -= p * Math.log2(p);
          }
        }

        // Stability = low change vs the previous frame.
        let change = 0;
        if (prevHistogram.current) {
          for (let i = 0; i < hist.length; i++) {
            change += Math.abs(hist[i] / total - prevHistogram.current[i]);
          }
        }
        prevHistogram.current = hist.map((h) => h / total);

        const isRich = entropy > 2.0 && brightness > 25 && brightness < 245;
        const isStable = change < 0.4;

        if (isRich && isStable) {
          richStreak.current += 1;
          onHint?.("Looks like a meal — confirming…");
        } else {
          richStreak.current = Math.max(0, richStreak.current - 1);
          onHint?.("Watching for your meal…");
        }

        // Once the cheap gate is interested, confirm with the vision model.
        if (richStreak.current >= 2) {
          void confirmWithVision();
        }
      };
      img.src = dataURL;
    };

    const id = setInterval(tick, 2000);
    const warm = setTimeout(tick, 800);
    return () => {
      clearInterval(id);
      clearTimeout(warm);
    };
  }, [enabled, captureFrame, onDetect, onHint]);
}
