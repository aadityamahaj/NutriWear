"use client";

import { useCallback, useEffect, useRef, useState } from "react";

interface Args {
  enabled: boolean;
  onCommand: (text: string) => void;
}

/**
 * Web Speech API voice listener. Reports status/errors so the UI can explain
 * failures instead of silently doing nothing. Falls back to text input when
 * unsupported (e.g. Firefox) or permission is denied.
 */
export function useVoiceCommand({ enabled, onCommand }: Args) {
  const [listening, setListening] = useState(false);
  const [supported, setSupported] = useState(false);
  const [lastHeard, setLastHeard] = useState("");
  const [error, setError] = useState<string | null>(null);

  const recognitionRef = useRef<any>(null);
  const wantListeningRef = useRef(false); // user intent; drives auto-restart
  const onCommandRef = useRef(onCommand);
  onCommandRef.current = onCommand;

  useEffect(() => {
    const SR =
      typeof window !== "undefined"
        ? (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition
        : null;
    setSupported(!!SR);
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
      if (code === "no-speech" || code === "aborted") return; // benign; restart handles it
      if (code === "not-allowed" || code === "service-not-allowed") {
        setError("Microphone blocked. Allow mic access in the browser and try again.");
        wantListeningRef.current = false;
        setListening(false);
      } else if (code === "network") {
        setError("Speech service network error. Try again, or type your question.");
      } else {
        setError(`Voice error: ${code}. You can type instead.`);
      }
    };

    rec.onend = () => {
      // The API stops itself periodically; restart if the user still wants to listen.
      if (wantListeningRef.current && recognitionRef.current) {
        try {
          recognitionRef.current.start();
        } catch {
          // A restart too soon throws; schedule a retry.
          setTimeout(() => {
            if (wantListeningRef.current && recognitionRef.current) {
              try { recognitionRef.current.start(); } catch { setListening(false); }
            }
          }, 300);
        }
      } else {
        setListening(false);
      }
    };

    return rec;
  }, []);

  const start = useCallback(() => {
    if (!supported) {
      setError("Voice isn't supported in this browser. Use Chrome/Safari, or type your question.");
      return;
    }
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

  useEffect(() => {
    if (!enabled) {
      wantListeningRef.current = false;
      try { recognitionRef.current?.stop(); } catch { /* noop */ }
      recognitionRef.current = null;
      setListening(false);
    }
  }, [enabled]);

  return { listening, supported, lastHeard, error, toggle, start, stop };
}
