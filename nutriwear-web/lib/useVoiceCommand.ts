"use client";

import { useCallback, useEffect, useRef, useState } from "react";

interface Args {
  enabled: boolean;
  onCommand: (text: string) => void;
  /** Keep listening continuously and auto-recover from transient errors. */
  alwaysOn?: boolean;
}

/**
 * Web Speech API voice listener. Reports status/errors so the UI can explain
 * failures instead of silently doing nothing. Falls back to text input when
 * unsupported (e.g. Firefox) or permission is denied.
 *
 * Chrome streams audio to a Google speech backend, so a `network` error means
 * that endpoint was unreachable (blocked browser build, firewall, offline). We
 * retry with backoff rather than giving up, and only surface a hard message
 * after several consecutive failures so a brief blip self-heals.
 */
export function useVoiceCommand({ enabled, onCommand, alwaysOn = false }: Args) {
  const [listening, setListening] = useState(false);
  const [supported, setSupported] = useState(false);
  const [lastHeard, setLastHeard] = useState("");
  const [error, setError] = useState<string | null>(null);

  const recognitionRef = useRef<any>(null);
  const wantListeningRef = useRef(false); // user intent; drives auto-restart
  const alwaysOnRef = useRef(alwaysOn);
  alwaysOnRef.current = alwaysOn;
  const networkFailuresRef = useRef(0);
  const restartTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const onCommandRef = useRef(onCommand);
  onCommandRef.current = onCommand;

  useEffect(() => {
    const SR =
      typeof window !== "undefined"
        ? (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition
        : null;
    setSupported(!!SR);
  }, []);

  const clearRestartTimer = () => {
    if (restartTimerRef.current) {
      clearTimeout(restartTimerRef.current);
      restartTimerRef.current = null;
    }
  };

  const pageActive = () =>
    typeof document === "undefined" || document.visibilityState === "visible";

  const scheduleRestart = useCallback((delay: number) => {
    clearRestartTimer();
    restartTimerRef.current = setTimeout(() => {
      // Never (re)start while the page is backgrounded — the mic must be off
      // whenever the site isn't the active, visible page.
      if (!wantListeningRef.current || !recognitionRef.current || !pageActive()) return;
      try {
        recognitionRef.current.start();
      } catch {
        // Still too soon — back off a bit more.
        scheduleRestart(Math.min(delay * 2, 4000));
      }
    }, delay);
  }, []);

  const buildRecognition = useCallback(() => {
    const SR = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
    if (!SR) return null;
    const rec = new SR();
    rec.continuous = true;
    rec.interimResults = true;
    rec.lang = "en-US";

    rec.onstart = () => {
      setListening(true);
      setError(null);
    };

    rec.onresult = (event: any) => {
      // A successful result means the backend is reachable — reset failures.
      networkFailuresRef.current = 0;
      let interim = "";
      let finalText = "";
      for (let i = event.resultIndex; i < event.results.length; i++) {
        const r = event.results[i];
        if (r.isFinal) finalText += r[0].transcript;
        else interim += r[0].transcript;
      }
      if (interim.trim()) setLastHeard(interim.trim());
      const done = finalText.trim();
      if (done) {
        setLastHeard(done);
        onCommandRef.current(done);
      }
    };

    rec.onerror = (e: any) => {
      const code = e?.error ?? "unknown";
      if (code === "no-speech" || code === "aborted") return; // benign; onend restarts
      if (code === "not-allowed" || code === "service-not-allowed") {
        setError("Microphone blocked. Allow mic access in your browser settings, then try again.");
        wantListeningRef.current = false;
        setListening(false);
        return;
      }
      if (code === "network") {
        networkFailuresRef.current += 1;
        if (networkFailuresRef.current >= 4) {
          // Repeated failures → the speech backend is genuinely unreachable here.
          setError(
            "Can't reach the speech service in this browser. Try Chrome or Safari (with Google speech enabled), check your connection, or type your question."
          );
        } else {
          setError("Reconnecting to the speech service…");
        }
        // Keep trying — onend will fire next and restart with backoff.
        return;
      }
      setError(`Voice error: ${code}. You can type instead.`);
    };

    rec.onend = () => {
      // Only keep listening if the user still wants it AND the page is active.
      if (wantListeningRef.current && recognitionRef.current && pageActive()) {
        // Back off when recovering from network errors; restart quickly otherwise.
        const delay = networkFailuresRef.current > 0
          ? Math.min(600 * networkFailuresRef.current, 4000)
          : 250;
        scheduleRestart(delay);
      } else {
        setListening(false);
      }
    };

    return rec;
  }, [scheduleRestart]);

  const start = useCallback(() => {
    if (!supported) {
      setError("Voice isn't supported in this browser. Use Chrome or Safari, or type your question.");
      return;
    }
    networkFailuresRef.current = 0;
    wantListeningRef.current = true;
    if (!recognitionRef.current) recognitionRef.current = buildRecognition();
    try {
      recognitionRef.current?.start();
      setListening(true);
    } catch {
      // Already started — treat as listening.
      setListening(true);
    }
  }, [supported, buildRecognition]);

  const stop = useCallback(() => {
    wantListeningRef.current = false;
    clearRestartTimer();
    try {
      recognitionRef.current?.stop();
    } catch {
      /* noop */
    }
    setListening(false);
  }, []);

  const toggle = useCallback(() => {
    if (listening) stop();
    else start();
  }, [listening, start, stop]);

  // Auto-start when always-on is enabled (and supported); stop when disabled.
  useEffect(() => {
    if (!enabled) return;
    if (alwaysOn && supported && !wantListeningRef.current) {
      start();
    } else if (!alwaysOn && wantListeningRef.current) {
      stop();
    }
  }, [alwaysOn, enabled, supported, start, stop]);

  // Privacy: the mic is ONLY on while this site is the active, visible page.
  // When the tab is hidden / backgrounded / the app is minimized, stop
  // recognition immediately (releasing the mic) but keep the user's intent so
  // it can resume when they return. Also stop on page unload/navigation.
  useEffect(() => {
    const suspend = () => {
      clearRestartTimer();
      try { recognitionRef.current?.stop(); } catch { /* noop */ }
      setListening(false);
    };

    const resumeIfWanted = () => {
      // Resume only if the user still wants it, it's enabled here, and the page
      // is actually visible/focused again.
      if (
        wantListeningRef.current &&
        enabled &&
        recognitionRef.current &&
        document.visibilityState === "visible"
      ) {
        scheduleRestart(300);
      }
    };

    const onVisibility = () => {
      if (document.visibilityState === "visible") resumeIfWanted();
      else suspend();
    };

    document.addEventListener("visibilitychange", onVisibility);
    // pagehide fires on tab close and bfcache navigation; blur covers losing
    // window focus on desktop (switching apps/windows). Both release the mic.
    window.addEventListener("pagehide", suspend);
    window.addEventListener("blur", suspend);
    // Returning focus to the window re-arms listening if still wanted.
    window.addEventListener("focus", resumeIfWanted);

    return () => {
      document.removeEventListener("visibilitychange", onVisibility);
      window.removeEventListener("pagehide", suspend);
      window.removeEventListener("blur", suspend);
      window.removeEventListener("focus", resumeIfWanted);
    };
  }, [enabled, scheduleRestart]);

  // Fully tear down when the hook is disabled (e.g. phase change).
  useEffect(() => {
    if (!enabled) {
      wantListeningRef.current = false;
      clearRestartTimer();
      try { recognitionRef.current?.stop(); } catch { /* noop */ }
      recognitionRef.current = null;
      setListening(false);
    }
  }, [enabled]);

  return { listening, supported, lastHeard, error, toggle, start, stop };
}
