"use client";

import { useEffect, useRef } from "react";

interface Args {
  enabled: boolean;
  captureFrame: (maxDim?: number) => string | null;
  onDetect: () => void;
  onHint?: (hint: string) => void;
}

/**
 * Whoop-style auto start-of-eating detection — heuristic, on-device, no ML model.
 *
 * Every ~2.5s it samples a small frame and measures:
 *  - "scene richness": color variance in the center region (a plate of food is
 *    visually busier than an empty table or a wall).
 *  - "stability": the scene stopped changing a lot (you've settled in front of
 *    the meal rather than walking around).
 *
 * When the center is rich AND stable across a couple of samples, it fires
 * onDetect(). This is intentionally approximate; the UI always offers a manual
 * "Start eating" button so a demo never depends on the heuristic.
 */
export function useEatingDetector({ enabled, captureFrame, onDetect, onHint }: Args) {
  const prevHistogram = useRef<number[] | null>(null);
  const richStreak = useRef(0);
  const firedRef = useRef(false);

  useEffect(() => {
    if (!enabled) {
      firedRef.current = false;
      richStreak.current = 0;
      prevHistogram.current = null;
      return;
    }

    const tmp = document.createElement("canvas");
    tmp.width = 64;
    tmp.height = 64;
    const ctx = tmp.getContext("2d", { willReadFrequently: true });

    const tick = () => {
      if (firedRef.current || !ctx) return;
      const dataURL = captureFrame(256);
      if (!dataURL) return;

      const img = new Image();
      img.onload = () => {
        ctx.drawImage(img, 0, 0, 64, 64);
        // Center region = inner 32x32 (where the reticle is).
        const { data } = ctx.getImageData(16, 16, 32, 32);

        // Build a coarse color histogram + overall brightness.
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

        // Scene richness = histogram spread (entropy-ish). Food plates spread across buckets.
        const total = hist.reduce((a, c) => a + c, 0) || 1;
        let entropy = 0;
        for (const h of hist) {
          if (h > 0) {
            const p = h / total;
            entropy -= p * Math.log2(p);
          }
        }

        // Stability = low change vs previous histogram.
        let change = 0;
        if (prevHistogram.current) {
          for (let i = 0; i < hist.length; i++) {
            change += Math.abs(hist[i] / total - prevHistogram.current[i]);
          }
        }
        prevHistogram.current = hist.map((h) => h / total);

        const isRich = entropy > 2.1 && brightness > 28 && brightness < 240;
        const isStable = change < 0.35;

        if (isRich && isStable) {
          richStreak.current += 1;
          onHint?.(richStreak.current >= 1 ? "Meal detected — getting ready…" : "Watching for your meal…");
        } else {
          richStreak.current = Math.max(0, richStreak.current - 1);
          onHint?.("Watching for your meal…");
        }

        // Two consecutive rich+stable samples → start.
        if (richStreak.current >= 2) {
          firedRef.current = true;
          onDetect();
        }
      };
      img.src = dataURL;
    };

    const id = setInterval(tick, 2500);
    // Run one soon after enabling.
    const warm = setTimeout(tick, 800);
    return () => {
      clearInterval(id);
      clearTimeout(warm);
    };
  }, [enabled, captureFrame, onDetect, onHint]);
}
