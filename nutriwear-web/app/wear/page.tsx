"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { usePairingCode } from "@/lib/useChannel";
import { EatingSession, FoodItem } from "@/lib/types";
import { useEatingDetector } from "@/lib/useEatingDetector";
import { useVoiceCommand } from "@/lib/useVoiceCommand";
import { useProactivePace } from "@/lib/useProactivePace";
import { classifyDirected } from "@/lib/directedSpeech";
import { useAvoidFoods } from "@/lib/useAvoidFoods";

type Phase = "idle" | "eating" | "analyzing" | "done";

interface ConsumptionItem {
  name: string;
  startCalories: number;
  leftoverFraction: number;
  eatenCalories: number;
  protein: number;
  carbs: number;
  fat: number;
  confidence: "high" | "medium" | "low";
}
interface CoachLine { role: "user" | "coach"; text: string }

export default function WearPage() {
  const [code] = usePairingCode();
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const streamRef = useRef<MediaStream | null>(null);

  const [cameraReady, setCameraReady] = useState(false);
  const [cameraError, setCameraError] = useState<string | null>(null);
  const [phase, setPhase] = useState<Phase>("idle");
  const [startedAt, setStartedAt] = useState<number | null>(null);
  const [elapsed, setElapsed] = useState(0);
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [detectHint, setDetectHint] = useState("Watching for your meal…");

  const [startItems, setStartItems] = useState<FoodItem[]>([]); // recognized at start
  const [scanningStart, setScanningStart] = useState(false);
  const [result, setResult] = useState<{
    items: ConsumptionItem[];
    startCalories: number;
    eatenCalories: number;
    leftoverCalories: number;
    note: string | null;
  } | null>(null);

  const [coachLines, setCoachLines] = useState<CoachLine[]>([]);
  const [coachBusy, setCoachBusy] = useState(false);

  // Foods-to-avoid list (learned from poorly-rated meals + manual).
  const avoid = useAvoidFoods();

  // Collapsible bottom HUD — reclaims the camera view on mobile.
  const [hudCollapsed, setHudCollapsed] = useState(false);

  // "Always listening" — keep the mic on continuously (persisted).
  const [alwaysListen, setAlwaysListen] = useState(false);
  const alwaysListenRef = useRef(false);
  useEffect(() => { alwaysListenRef.current = alwaysListen; }, [alwaysListen]);
  useEffect(() => {
    setAlwaysListen(localStorage.getItem("nutriwear.alwaysListen") === "1");
  }, []);
  const toggleAlwaysListen = useCallback(() => {
    setAlwaysListen((prev) => {
      const next = !prev;
      localStorage.setItem("nutriwear.alwaysListen", next ? "1" : "0");
      return next;
    });
  }, []);

  // Snapshots held in refs (not re-rendered, used by compare).
  const beforeImageRef = useRef<string | null>(null);
  const phaseRef = useRef<Phase>("idle");
  const sessionIdRef = useRef<string | null>(null);
  const startedAtRef = useRef<number | null>(null);
  const startItemsRef = useRef<FoodItem[]>([]);
  useEffect(() => { phaseRef.current = phase; }, [phase]);
  useEffect(() => { sessionIdRef.current = sessionId; }, [sessionId]);
  useEffect(() => { startedAtRef.current = startedAt; }, [startedAt]);
  useEffect(() => { startItemsRef.current = startItems; }, [startItems]);

  // --- Camera ---
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: "environment", width: { ideal: 1280 } },
          audio: false,
        });
        if (cancelled) { stream.getTracks().forEach((t) => t.stop()); return; }
        streamRef.current = stream;
        if (videoRef.current) {
          videoRef.current.srcObject = stream;
          await videoRef.current.play().catch(() => {});
        }
        setCameraReady(true);
      } catch (e) {
        setCameraError(
          e instanceof Error && e.name === "NotAllowedError"
            ? "Camera permission denied. Allow camera access and reload."
            : "No camera available on this device/browser."
        );
      }
    })();
    return () => { cancelled = true; streamRef.current?.getTracks().forEach((t) => t.stop()); };
  }, []);

  // Smaller default + modest JPEG quality. Vision models tokenize images by
  // resolution, so keeping frames small is the biggest lever on Groq's
  // tokens-per-minute limit — it's what keeps the AI from hitting 429s.
  const captureFrame = useCallback((maxDim = 512): string | null => {
    const video = videoRef.current, canvas = canvasRef.current;
    if (!video || !canvas || !video.videoWidth) return null;
    const scale = Math.min(1, maxDim / Math.max(video.videoWidth, video.videoHeight));
    canvas.width = Math.round(video.videoWidth * scale);
    canvas.height = Math.round(video.videoHeight * scale);
    const ctx = canvas.getContext("2d");
    if (!ctx) return null;
    ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
    return canvas.toDataURL("image/jpeg", 0.6);
  }, []);

  const postSession = useCallback(
    async (action: "start" | "update" | "end", session?: Partial<EatingSession>, detectedBy?: "auto" | "manual") => {
      try {
        const res = await fetch("/api/session", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ code, action, session, detectedBy }),
        });
        return (await res.json()).session as EatingSession | undefined;
      } catch { return undefined; }
    },
    [code]
  );

  // --- Start: capture BEFORE snapshot, recognize it once ---
  const startEating = useCallback(
    async (detectedBy: "auto" | "manual") => {
      if (phaseRef.current !== "idle") return;
      setPhase("eating");
      setStartedAt(Date.now());
      setElapsed(0);
      setStartItems([]);
      setResult(null);
      setCoachLines([]);
      const session = await postSession("start", undefined, detectedBy);
      if (session) setSessionId(session.id);

      // Grab the "before" plate after the camera settles.
      setTimeout(async () => {
        const img = captureFrame();
        beforeImageRef.current = img;
        if (!img) return;
        setScanningStart(true);
        try {
          const res = await fetch("/api/analyze", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ image: img }),
          });
          const data = await res.json();
          if (Array.isArray(data.items) && data.items.length) {
            setStartItems(data.items);
            postSession("update", { id: sessionIdRef.current ?? undefined, items: data.items, startedAt: startedAtRef.current });
          }
        } catch { /* ignore */ } finally { setScanningStart(false); }
      }, 1400);
    },
    [postSession, captureFrame]
  );

  // --- Done: capture AFTER snapshot, compare to BEFORE ---
  const doneEating = useCallback(async () => {
    if (phaseRef.current !== "eating") return;
    setPhase("analyzing");
    const after = captureFrame();
    const before = beforeImageRef.current;

    let res: {
      items: ConsumptionItem[]; startCalories: number; eatenCalories: number; leftoverCalories: number; note: string | null; usedLiveAI?: boolean;
    };

    // Send the already-recognized start items so the comparison is anchored to
    // them (consistent numbers; eating everything == the start calories).
    const startItemsPayload = startItemsRef.current.map((i) => ({
      name: i.name,
      calories: i.macros.calories,
      protein: i.macros.protein,
      carbs: i.macros.carbs,
      fat: i.macros.fat,
      confidence: i.confidence,
    }));

    if (before && after && startItemsPayload.length > 0) {
      try {
        const r = await fetch("/api/compare", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ before, after, startItems: startItemsPayload }),
        });
        res = await r.json();
      } catch {
        res = fallbackFromStart();
      }
    } else {
      // No before/after image or nothing recognized — assume the start plate
      // was fully eaten (still consistent with what was shown).
      res = fallbackFromStart();
    }

    setResult(res);
    setPhase("done");

    // Log the EATEN amounts as the meal.
    const eatenItems: FoodItem[] = res.items.map((it) => ({
      name: it.name,
      portion: `${Math.round((1 - it.leftoverFraction) * 100)}% eaten`,
      macros: { calories: Math.round(it.eatenCalories), protein: Math.round(it.protein), carbs: Math.round(it.carbs), fat: Math.round(it.fat) },
      confidence: it.confidence,
    }));

    await postSession("end", {
      id: sessionIdRef.current ?? undefined,
      items: eatenItems,
      note: res.note,
      usedLiveAI: res.usedLiveAI ?? true,
      startedAt: startedAtRef.current,
      startCalories: Math.round(res.startCalories),
      eatenCalories: Math.round(res.eatenCalories),
      leftoverCalories: Math.round(res.leftoverCalories),
    });
  }, [captureFrame, postSession]);

  function fallbackFromStart() {
    const items = startItemsRef.current;
    const start = items.reduce((a, i) => a + i.macros.calories, 0);
    return {
      items: items.map((i) => ({
        name: i.name, startCalories: i.macros.calories, leftoverFraction: 0,
        eatenCalories: i.macros.calories, protein: i.macros.protein, carbs: i.macros.carbs, fat: i.macros.fat,
        confidence: i.confidence,
      })),
      startCalories: start, eatenCalories: start, leftoverCalories: 0,
      note: items.length ? "Couldn't compare before/after — assumed you ate it all." : "No food was recognized.",
      usedLiveAI: items.length > 0,
    };
  }

  // --- Timer ---
  useEffect(() => {
    if (phase !== "eating" || !startedAt) return;
    const id = setInterval(() => setElapsed(Math.floor((Date.now() - startedAt) / 1000)), 500);
    return () => clearInterval(id);
  }, [phase, startedAt]);

  // --- Auto detection while idle ---
  useEatingDetector({
    enabled: cameraReady && phase === "idle",
    captureFrame,
    onDetect: () => startEating("auto"),
    onHint: setDetectHint,
  });

  // --- Voice assistant ---
  const speak = useCallback((text: string) => {
    try {
      window.speechSynthesis.cancel();
      const u = new SpeechSynthesisUtterance(text);
      u.lang = "en-US";
      window.speechSynthesis.speak(u);
    } catch { /* no tts */ }
  }, []);

  const askCoach = useCallback(async (question: string) => {
    setCoachLines((p) => [...p, { role: "user", text: question }]);
    setCoachBusy(true);
    const context = buildContext(startItemsRef.current, startedAtRef.current);
    try {
      const res = await fetch("/api/coach", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ question, context }),
      });
      const data = await res.json();
      const answer = data.answer ?? "Sorry, I couldn't get that.";
      setCoachLines((p) => [...p, { role: "coach", text: answer }]);
      speak(answer);
    } catch {
      setCoachLines((p) => [...p, { role: "coach", text: "I had trouble answering." }]);
    } finally { setCoachBusy(false); }
  }, [speak]);

  const handleUtterance = useCallback((text: string) => {
    // In always-on mode, require a wake word ("hey NutriWear", "coach, …") for
    // questions so ambient conversation is ignored. Session commands ("I'm
    // done", "let's eat") always act. In manual tap mode, the tap is the signal
    // so any speech is treated as directed at the coach.
    const intent = classifyDirected(text, alwaysListenRef.current);
    switch (intent.kind) {
      case "start":
        if (phaseRef.current === "idle") startEating("manual");
        return;
      case "done":
        doneEating();
        return;
      case "question":
        if (!intent.text) {
          // Bare wake word with no question — acknowledge without calling the LLM.
          const ack = "Yes? Ask me anything about your meal.";
          setCoachLines((p) => [...p, { role: "coach", text: ack }]);
          speak(ack);
          return;
        }
        askCoach(intent.text);
        return;
      case "ignore":
      default:
        return;
    }
  }, [doneEating, askCoach, startEating, speak]);

  // Voice is active both while idle (to catch "let's eat") and while eating.
  const { listening, supported: voiceSupported, lastHeard, error: voiceError, toggle } = useVoiceCommand({
    enabled: phase === "idle" || phase === "eating",
    onCommand: handleUtterance,
    alwaysOn: alwaysListen,
  });

  // Proactive pace coaching: nudge to slow down if food disappears too fast.
  const proactiveCue = useCallback((text: string) => {
    setCoachLines((p) => [...p, { role: "coach", text }]);
    speak(text);
  }, [speak]);

  useProactivePace({
    enabled: phase === "eating",
    captureFrame,
    startCalories: startItemsRef.current.reduce((a, i) => a + i.macros.calories, 0),
    startedAt,
    onCue: proactiveCue,
  });

  // "Foods to avoid" warning: once the plate is recognized, if it contains a
  // food that hasn't sat well before, tell the user to stop.
  const warnedRef = useRef(false);
  useEffect(() => {
    if (phase !== "eating") { warnedRef.current = false; return; }
    if (warnedRef.current || startItems.length === 0) return;
    const flagged = avoid.matches(startItems);
    if (flagged.length) {
      warnedRef.current = true;
      const warn = `Stop — ${flagged.join(", ")} is on your avoid list. It hasn't sat well with you before; maybe skip it or go light.`;
      setCoachLines((p) => [...p, { role: "coach", text: warn }]);
      speak(warn);
    }
  }, [startItems, phase, avoid, speak]);

  const reset = useCallback(() => {
    setPhase("idle"); setStartedAt(null); setElapsed(0); setSessionId(null);
    setStartItems([]); setResult(null); setCoachLines([]); beforeImageRef.current = null;
  }, []);

  const startCals = startItems.reduce((a, i) => a + i.macros.calories, 0);
  const mm = String(Math.floor(elapsed / 60)).padStart(2, "0");
  const ss = String(elapsed % 60).padStart(2, "0");

  return (
    <div style={{ position: "relative", minHeight: "100dvh", background: "#000", overflow: "hidden" }}>
      <video ref={videoRef} playsInline muted style={{ position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover", opacity: cameraReady ? 1 : 0, transition: "opacity 0.4s" }} />
      <canvas ref={canvasRef} style={{ display: "none" }} />
      <div style={{ position: "absolute", inset: 0, background: "linear-gradient(180deg, rgba(0,0,0,0.5), rgba(0,0,0,0.12) 28%, rgba(0,0,0,0.72))" }} />

      {cameraError && (
        <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 10, padding: 30, textAlign: "center" }}>
          <div style={{ fontSize: 40 }}>📷</div><p className="muted">{cameraError}</p>
        </div>
      )}

      <div style={{ position: "absolute", top: 0, left: 0, right: 0, padding: "calc(14px + env(safe-area-inset-top)) 18px 14px", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <Link href="/" className="pill" style={{ background: "rgba(0,0,0,0.5)" }}>✕</Link>
        <div className="pill" style={{ background: "rgba(0,0,0,0.5)" }}><span className="live-dot" /> Synced · {code}</div>
      </div>

      {(phase === "idle" || phase === "eating") && cameraReady && <Reticle active={phase === "eating"} />}

      {phase === "eating" && startItems.length > 0 && (
        <div style={{ position: "absolute", top: "calc(70px + env(safe-area-inset-top))", left: 0, right: 0, display: "flex", flexWrap: "wrap", gap: 6, justifyContent: "center", padding: "0 20px" }}>
          {startItems.map((it, i) => (
            <span key={i} className="pill" style={{ background: "rgba(255,140,41,0.92)", color: "#000", fontWeight: 700 }}>
              {it.name} · {Math.round(it.macros.calories)} kcal
            </span>
          ))}
        </div>
      )}

      <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, padding: "0 16px calc(76px + env(safe-area-inset-bottom))" }}>
        {phase === "idle" && (
          <div style={{ textAlign: "center", marginBottom: 18 }}>
            <div className="pill" style={{ background: "rgba(0,0,0,0.55)", marginBottom: 14 }}>
              <span className="live-dot" style={{ background: "var(--yellow)" }} /> {detectHint}
            </div>
            <button className="btn-primary" onClick={() => startEating("manual")}>Start eating</button>
            <p className="dim" style={{ fontSize: 12, marginTop: 8 }}>I snapshot your full plate now, then compare when you&apos;re done.</p>
            {voiceSupported && (
              <AlwaysListenToggle
                on={alwaysListen}
                listening={listening}
                error={voiceError}
                onToggle={toggleAlwaysListen}
              />
            )}
          </div>
        )}

        {phase === "eating" && (
          <EatingHud
            time={`${mm}:${ss}`} scanningStart={scanningStart} startCals={Math.round(startCals)}
            startCount={startItems.length} listening={listening} voiceSupported={voiceSupported}
            lastHeard={lastHeard} voiceError={voiceError} coachLines={coachLines} coachBusy={coachBusy}
            alwaysListen={alwaysListen} onToggleAlwaysListen={toggleAlwaysListen}
            collapsed={hudCollapsed} onToggleCollapsed={() => setHudCollapsed((c) => !c)}
            onToggleVoice={toggle} onDone={doneEating} onAsk={askCoach}
          />
        )}

        {phase === "analyzing" && (
          <div className="card" style={{ textAlign: "center", marginBottom: 10 }}>
            <div className="spinner" /><p style={{ fontWeight: 700, marginTop: 10 }}>Comparing before &amp; after…</p>
            <p className="dim" style={{ fontSize: 12 }}>Working out how much you actually ate</p>
          </div>
        )}

        {phase === "done" && result && (
          <ConsumptionResultCard
            result={result}
            durationLabel={`${mm}:${ss}`}
            onReset={reset}
            onRate={(feeling) => {
              // A negative rating learns the eaten foods into the avoid list.
              if (feeling === "sluggish" || feeling === "bad") {
                avoid.addMany(result.items.map((i) => i.name));
              }
            }}
          />
        )}
      </div>

      <style>{`.spinner{width:28px;height:28px;border-radius:50%;border:3px solid rgba(255,255,255,0.2);border-top-color:var(--orange);margin:0 auto;animation:spin 0.8s linear infinite}@keyframes spin{to{transform:rotate(360deg)}}`}</style>
    </div>
  );
}

function buildContext(items: FoodItem[], startedAt: number | null): string {
  const parts: string[] = [];
  if (items.length) {
    parts.push("Foods on the plate: " + items.map((i) => `${i.name} (~${Math.round(i.macros.calories)} kcal)`).join("; ") + ".");
  } else parts.push("No food recognized on the plate yet.");
  if (startedAt) parts.push(`Eating for about ${Math.floor((Date.now() - startedAt) / 1000 / 60)} minutes.`);
  return parts.join(" ");
}

function Reticle({ active }: { active: boolean }) {
  const color = active ? "var(--orange)" : "rgba(255,255,255,0.85)";
  return (
    <div style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center", pointerEvents: "none" }}>
      <div style={{ position: "relative", width: 260, height: 260, borderRadius: 28, border: `2px solid ${color}`, overflow: "hidden" }}>
        <div style={{ position: "absolute", left: 0, right: 0, height: 3, background: `linear-gradient(90deg, transparent, ${active ? "var(--orange)" : "rgba(255,255,255,0.9)"}, transparent)`, top: "50%", animation: "scanmove 2.2s ease-in-out infinite alternate" }} />
      </div>
    </div>
  );
}

function EatingHud(props: {
  time: string; scanningStart: boolean; startCals: number; startCount: number;
  listening: boolean; voiceSupported: boolean; lastHeard: string; voiceError: string | null;
  coachLines: CoachLine[]; coachBusy: boolean;
  alwaysListen: boolean; onToggleAlwaysListen: () => void;
  collapsed: boolean; onToggleCollapsed: () => void;
  onToggleVoice: () => void; onDone: () => void; onAsk: (q: string) => void;
}) {
  const [typed, setTyped] = useState("");
  const lastCoach = [...props.coachLines].reverse().find((l) => l.role === "coach");

  // Collapsed: a slim bar that reclaims the camera view. Tap it (or the
  // chevron) to pop the full controls back up.
  if (props.collapsed) {
    return (
      <div
        className="card"
        style={{ marginBottom: 10, padding: "10px 14px", display: "flex", alignItems: "center", gap: 10 }}
      >
        <button
          onClick={props.onToggleCollapsed}
          aria-label="Expand controls"
          style={{ display: "flex", alignItems: "center", gap: 10, background: "none", border: "none", color: "var(--text)", cursor: "pointer", flex: 1, padding: 0, textAlign: "left" }}
        >
          <span className="rec-dot" />
          <span style={{ fontWeight: 800, fontSize: 14, fontFamily: "ui-monospace, monospace" }}>{props.time}</span>
          {props.listening && <span style={{ fontSize: 12, color: "var(--orange)" }}>🎙️</span>}
          {props.coachBusy && <span style={{ fontSize: 12, color: "var(--yellow)" }}>✦ …</span>}
          <span style={{ marginLeft: "auto", fontSize: 18, color: "var(--text-3)" }}>▲</span>
        </button>
        <button className="btn-primary" style={{ width: "auto", padding: "8px 16px", fontSize: 14 }} onClick={props.onDone}>✓ Done</button>
      </div>
    );
  }

  return (
    <div className="card" style={{ marginBottom: 10 }}>
      {/* Grab handle + collapse control */}
      <button
        onClick={props.onToggleCollapsed}
        aria-label="Collapse controls"
        style={{ display: "block", width: 44, height: 5, margin: "0 auto 12px", borderRadius: 999, background: "var(--text-3)", border: "none", cursor: "pointer", padding: 0 }}
      />

      <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 10 }}>
        <span className="rec-dot" /><span style={{ fontWeight: 800, fontSize: 15 }}>Eating</span>
        <span style={{ marginLeft: "auto", fontSize: 26, fontWeight: 800, fontFamily: "ui-monospace, monospace" }}>{props.time}</span>
        <button
          onClick={props.onToggleCollapsed}
          aria-label="Collapse"
          style={{ background: "var(--card-2)", border: "1px solid var(--stroke)", borderRadius: 10, color: "var(--text-2)", cursor: "pointer", width: 32, height: 32, fontSize: 14 }}
        >▼</button>
      </div>
      <div className="dim" style={{ fontSize: 12, marginBottom: 10 }}>
        {props.scanningStart ? "Snapshotting your full plate…"
          : props.startCount > 0 ? `Starting plate: ${props.startCount} item${props.startCount > 1 ? "s" : ""} · ~${props.startCals} kcal`
          : "Point at your plate; I captured it at start."}
      </div>

      {(lastCoach || props.coachBusy) && (
        <div style={{ background: "var(--card-2)", borderRadius: 14, padding: 12, marginBottom: 10, display: "flex", gap: 8 }}>
          <span style={{ color: "var(--yellow)" }}>✦</span>
          <span style={{ fontSize: 13 }}>{props.coachBusy ? "Thinking…" : lastCoach?.text}</span>
        </div>
      )}

      {props.voiceSupported && !props.alwaysListen && (
        <button className="btn-ghost" onClick={props.onToggleVoice} style={{ marginBottom: 8, color: props.listening ? "var(--orange)" : undefined }}>
          {props.listening ? "🎙️ Listening — say a question or “done”" : "🎙️ Tap to talk to coach"}
        </button>
      )}
      {props.voiceSupported && (
        <AlwaysListenToggle
          on={props.alwaysListen}
          listening={props.listening}
          error={props.voiceError}
          onToggle={props.onToggleAlwaysListen}
        />
      )}
      {props.lastHeard ? <p className="dim" style={{ fontSize: 11, marginBottom: 6 }}>heard: “{props.lastHeard}”</p> : null}
      {props.voiceError && !props.alwaysListen ? <p style={{ fontSize: 11, marginBottom: 6, color: "var(--yellow)" }}>{props.voiceError}</p> : null}
      {!props.voiceSupported ? <p className="dim" style={{ fontSize: 11, marginBottom: 6 }}>Voice needs Chrome or Safari — type below instead.</p> : null}

      <form onSubmit={(e) => { e.preventDefault(); if (typed.trim()) { props.onAsk(typed.trim()); setTyped(""); } }} style={{ display: "flex", gap: 8, marginBottom: 10 }}>
        <input value={typed} onChange={(e) => setTyped(e.target.value)} placeholder="Ask the coach (e.g. calories in a banana)"
          style={{ flex: 1, background: "var(--card-2)", border: "1px solid var(--stroke)", borderRadius: 12, color: "var(--text)", padding: "11px 14px", fontSize: 14 }} />
        {typed.trim() && <button type="submit" className="btn-ghost" style={{ width: "auto", padding: "0 16px" }}>Ask</button>}
      </form>

      <button className="btn-primary" onClick={props.onDone}>✓ Done eating</button>
    </div>
  );
}

function AlwaysListenToggle({ on, listening, error, onToggle }: {
  on: boolean; listening: boolean; error: string | null; onToggle: () => void;
}) {
  return (
    <div style={{ marginTop: 8, marginBottom: 6 }}>
      <button
        onClick={onToggle}
        className="btn-ghost"
        style={{
          display: "flex", alignItems: "center", gap: 10, width: "100%",
          color: on ? "var(--orange)" : undefined,
        }}
      >
        <span
          style={{
            width: 36, height: 20, borderRadius: 999, position: "relative", flexShrink: 0,
            background: on ? "var(--orange)" : "var(--card-2)",
            border: "1px solid var(--stroke)", transition: "background 0.15s",
          }}
        >
          <span
            style={{
              position: "absolute", top: 1, left: on ? 17 : 1, width: 16, height: 16,
              borderRadius: "50%", background: "#fff", transition: "left 0.15s",
            }}
          />
        </span>
        <span style={{ fontSize: 13, fontWeight: 700 }}>
          {on ? (listening ? "Always listening — on" : "Always listening (reconnecting…)") : "Always listening — off"}
        </span>
      </button>
      {on && (
        <p className="dim" style={{ fontSize: 11, marginTop: 4, textAlign: "left" }}>
          {error && error.startsWith("Can't reach")
            ? error
            : "Mic stays on but ignores ambient talk. Say \u201cHey NutriWear, \u2026\u201d to ask a question. \u201cLet\u2019s eat\u201d and \u201cI\u2019m done\u201d always work."}
        </p>
      )}
    </div>
  );
}

const FEELINGS: { key: string; emoji: string; label: string }[] = [
  { key: "great", emoji: "😀", label: "Great" },
  { key: "good", emoji: "🙂", label: "Good" },
  { key: "okay", emoji: "😐", label: "Okay" },
  { key: "sluggish", emoji: "😮‍💨", label: "Sluggish" },
  { key: "bad", emoji: "🤢", label: "Bad" },
];

function ConsumptionResultCard({ result, durationLabel, onReset, onRate }: {
  result: { items: ConsumptionItem[]; startCalories: number; eatenCalories: number; leftoverCalories: number; note: string | null };
  durationLabel: string;
  onReset: () => void;
  onRate: (feeling: string) => void;
}) {
  const [rated, setRated] = useState<string | null>(null);
  return (
    <div className="card" style={{ marginBottom: 10, maxHeight: "74dvh", overflowY: "auto" }}>
      <div className="dim" style={{ fontSize: 12, fontWeight: 700 }}>LOGGED · {durationLabel}</div>
      <div style={{ fontSize: 22, fontWeight: 800, marginBottom: 12 }}>How much you ate</div>

      {/* Three-number summary: started / ate / left */}
      <div style={{ display: "flex", gap: 8, marginBottom: 14 }}>
        <Stat label="On plate" value={Math.round(result.startCalories)} color="var(--text-2)" />
        <Stat label="You ate" value={Math.round(result.eatenCalories)} color="var(--orange)" big />
        <Stat label="Left over" value={Math.round(result.leftoverCalories)} color="var(--text-2)" />
      </div>

      {result.items.map((it, i) => (
        <div key={i} style={{ padding: "10px 0", borderTop: i ? "1px solid var(--stroke)" : "none" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
            <span style={{ fontWeight: 600, fontSize: 15 }}>{it.name}</span>
            <span style={{ fontWeight: 800, color: "var(--orange)" }}>{Math.round(it.eatenCalories)} kcal</span>
          </div>
          <div className="dim" style={{ fontSize: 12, marginTop: 2 }}>
            ate {Math.round((1 - it.leftoverFraction) * 100)}% of {Math.round(it.startCalories)} kcal · {Math.round(it.protein)}p {Math.round(it.carbs)}c {Math.round(it.fat)}f
          </div>
        </div>
      ))}

      {result.note && <p className="dim" style={{ fontSize: 11, marginTop: 10 }}>{result.note}</p>}

      {/* Post-meal feeling check-in */}
      <div style={{ marginTop: 16, paddingTop: 14, borderTop: "1px solid var(--stroke)" }}>
        {rated ? (
          <p className="dim" style={{ fontSize: 13 }}>
            Thanks — noted that you felt <strong style={{ color: "var(--text)" }}>{rated}</strong>.
            {(rated === "sluggish" || rated === "bad") ? " Added these foods to your avoid list; I'll warn you next time." : ""}
          </p>
        ) : (
          <>
            <div style={{ fontWeight: 700, fontSize: 14, marginBottom: 8 }}>How do you feel?</div>
            <div style={{ display: "flex", gap: 6 }}>
              {FEELINGS.map((f) => (
                <button
                  key={f.key}
                  onClick={() => { onRate(f.key); setRated(f.label); }}
                  style={{ flex: 1, background: "var(--card-2)", border: "1px solid var(--stroke)", borderRadius: 12, padding: "10px 4px", display: "flex", flexDirection: "column", alignItems: "center", gap: 4 }}
                >
                  <span style={{ fontSize: 22 }}>{f.emoji}</span>
                  <span className="dim" style={{ fontSize: 10, fontWeight: 600 }}>{f.label}</span>
                </button>
              ))}
            </div>
          </>
        )}
      </div>

      <button className="btn-ghost" style={{ marginTop: 14 }} onClick={onReset}>Watch for next meal</button>
    </div>
  );
}

function Stat({ label, value, color, big }: { label: string; value: number; color: string; big?: boolean }) {
  return (
    <div style={{ flex: 1, background: "var(--card-2)", borderRadius: 14, padding: "12px 10px", textAlign: "center" }}>
      <div style={{ fontSize: big ? 28 : 22, fontWeight: 800, color }}>{value}</div>
      <div className="dim" style={{ fontSize: 11 }}>{label}</div>
    </div>
  );
}
