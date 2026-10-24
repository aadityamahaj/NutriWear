"use client";

import { useEffect, useRef } from "react";

interface Args {
  enabled: boolean;
  /** Capture a downscaled JPEG data URL of the current camera frame. */
  captureFrame: (maxDim?: number) => string | null;
  /** Total calories on the plate at the start, for sizing the nudge. */
  startCalories: number;
  /** When the meal started (epoch ms), to reason about pace. */
  startedAt: number | null;
  /** Fired (at most a few times) with a short proactive line to speak/show. */
  onCue: (text: string) => void;
}

/**
 * Watches the plate WHILE eating and proactively nudges when food is
 * disappearing too fast. It estimates "plate fullness" from a coarse texture
 * measure of the center region and compares it to the starting fullness; a
 * steep early drop on a sizeable meal triggers a slow-down cue.
 *
 * This is intentionally heuristic (no server round-trip) so it's responsive
 * and works offline. The AI before/after comparison still runs at the end for
 * the accurate consumption story.
 */
export function useProactivePace({ enabled, captureFrame, startCalories, startedAt, onCue }: Args) {
  const baselineRef = useRef<number | null>(null);
  const firedSlowDown = useRef(false);
  const firedHalfway = useRef(false);
  const onCueRef = useRef(onCue);
  onCueRef.current = onCue;

  useEffect(() => {
    if (!enabled) {
      baselineRef.current = null;
      firedSlowDown.current = false;
      firedHalfway.current = false;
      return;
    }

    const tmp = document.createElement("canvas");
    tmp.width = 48;
    tmp.height = 48;
    const ctx = tmp.getContext("2d", { willReadFrequently: true });

    // "Fullness" proxy: texture richness of the plate center. A full plate of
    // food has more color/brightness variance than an empty/near-empty one.
    const sampleFullness = (): Promise<number | null> =>
      new Promise((resolve) => {
        if (!ctx) return resolve(null);
        const dataURL = captureFrame(256);
        if (!dataURL) return resolve(null);
        const img = new Image();
        img.onload = () => {
          ctx.drawImage(img, 0, 0, 48, 48);
          const { data } = ctx.getImageData(12, 12, 24, 24); // center region
          let mean = 0;
          const lum: number[] = [];
          for (let i = 0; i < data.length; i += 4) {
            const l = (data[i] + data[i + 1] + data[i + 2]) / 3;
            lum.push(l);
            mean += l;
          }
          mean /= lum.length;
          let variance = 0;
          for (const l of lum) variance += (l - mean) * (l - mean);
          variance /= lum.length;
          resolve(Math.sqrt(variance)); // std-dev of luminance = texture richness
        };
        img.onerror = () => resolve(null);
        img.src = dataURL;
      });

    const tick = async () => {
      const fullness = await sampleFullness();
      if (fullness == null) return;

      if (baselineRef.current == null) {
        baselineRef.current = fullness;
        return;
      }

      const baseline = baselineRef.current || 1;
      const remainingRatio = Math.min(1, Math.max(0, fullness / baseline));
      const eatenRatio = 1 - remainingRatio;
      const minutes = startedAt ? (Date.now() - startedAt) / 60000 : 0;

      // Slow-down: a big meal >40% gone inside the first ~4 minutes.
      if (
        !firedSlowDown.current &&
        startCalories > 400 &&
        minutes > 0.75 &&
        minutes < 4 &&
        eatenRatio > 0.4
      ) {
        firedSlowDown.current = true;
        onCueRef.current(
          "Hey, slow down a little — that plate's going fast. Set the fork down between bites and let your body catch up."
        );
      }

      // Halfway check-in once the plate is roughly half gone.
      if (!firedHalfway.current && eatenRatio > 0.5) {
        firedHalfway.current = true;
        onCueRef.current("You're about halfway. Check in — still genuinely hungry, or just on a roll?");
      }
    };

    const id = setInterval(tick, 15000);
    const warm = setTimeout(tick, 3000); // establish baseline shortly after start
    return () => {
      clearInterval(id);
      clearTimeout(warm);
    };
  }, [enabled, captureFrame, startCalories, startedAt]);
}
