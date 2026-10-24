"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { usePairingCode } from "@/lib/useChannel";
import { ChannelState, EatingSession, SyncEvent, sessionTotals } from "@/lib/types";

export default function DashboardPage() {
  const [code, setCode] = usePairingCode();
  const [state, setState] = useState<ChannelState | null>(null);
  const [connected, setConnected] = useState(false);
  const esRef = useRef<EventSource | null>(null);

  // Live clock for the active session timer.
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 500);
    return () => clearInterval(id);
  }, []);

  // Subscribe to the SSE stream whenever the code changes.
  useEffect(() => {
    if (!code) return;
    esRef.current?.close();
    const es = new EventSource(`/api/stream?code=${code}`);
    esRef.current = es;
    es.onopen = () => setConnected(true);
    es.onerror = () => setConnected(false);
    es.onmessage = (e) => {
      try {
        const event: SyncEvent = JSON.parse(e.data);
        if (event.type === "state") setState(event.state);
        else setState((prev) => applyEvent(prev, event, code));
      } catch {
        /* ignore */
      }
    };
    return () => es.close();
  }, [code]);

  const current = state?.current ?? null;
  const active = current?.status === "eating";

  const dayTotals = (state?.history ?? []).reduce(
    (acc, s) => {
      const t = sessionTotals(s);
      return {
        calories: acc.calories + t.calories,
        protein: acc.protein + t.protein,
        carbs: acc.carbs + t.carbs,
        fat: acc.fat + t.fat,
      };
    },
    { calories: 0, protein: 0, carbs: 0, fat: 0 }
  );

  return (
    <main className="app">
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 18 }}>
        <div>
          <div className="dim" style={{ fontSize: 13 }}>Companion Dashboard</div>
          <h1 style={{ fontSize: 30, fontWeight: 800 }}>NutriWear</h1>
        </div>
        <Link href="/" className="pill" style={{ background: "var(--card)" }}>✕</Link>
      </div>

      {/* Pairing / connection */}
      <div className="card" style={{ marginBottom: 16, display: "flex", alignItems: "center", gap: 12 }}>
        <span className={connected ? "live-dot" : "rec-dot"} style={!connected ? { background: "var(--text-3)", animation: "none" } : undefined} />
        <div>
          <div style={{ fontWeight: 700 }}>{connected ? "Synced with wearable" : "Waiting for wearable…"}</div>
          <div className="dim" style={{ fontSize: 12 }}>Channel {code}</div>
        </div>
        <input
          value={code}
          onChange={(e) => setCode(e.target.value)}
          maxLength={4}
          style={{
            marginLeft: "auto", width: 88, textAlign: "center", textTransform: "uppercase",
            background: "var(--card-2)", border: "1px solid var(--stroke)", borderRadius: 10,
            color: "var(--text)", fontSize: 18, fontWeight: 800, letterSpacing: 4, padding: "8px 6px",
            fontFamily: "ui-monospace, monospace",
          }}
        />
      </div>

      {/* Live session banner */}
      {active && current?.startedAt && (
        <div className="card" style={{ marginBottom: 16, borderColor: "rgba(255,140,41,0.4)", background: "linear-gradient(180deg, rgba(255,140,41,0.12), rgba(255,140,41,0.03))" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <span className="rec-dot" />
            <span style={{ fontWeight: 800 }}>Eating now</span>
            <span style={{ marginLeft: "auto", fontSize: 28, fontWeight: 800, fontFamily: "ui-monospace, monospace" }}>
              {fmtDuration(Math.floor((now - current.startedAt) / 1000))}
            </span>
          </div>
          <p className="muted" style={{ fontSize: 13, marginTop: 8 }}>
            Detected {current.detectedBy === "auto" ? "automatically" : "manually"} at {fmtTime(current.startedAt)}. Waiting for &ldquo;done eating&rdquo;…
          </p>
          {current.items.length > 0 && (
            <div style={{ display: "flex", flexWrap: "wrap", gap: 6, marginTop: 10 }}>
              {current.items.map((it, i) => (
                <span key={i} className="pill" style={{ background: "rgba(255,140,41,0.9)", color: "#000", fontWeight: 700 }}>
                  {it.name} · {Math.round(it.macros.calories)} kcal
                </span>
              ))}
            </div>
          )}
        </div>
      )}

      {/* Today totals */}
      <div className="card" style={{ marginBottom: 16 }}>
        <div className="dim" style={{ fontSize: 12, fontWeight: 700, letterSpacing: 1, marginBottom: 6 }}>TODAY</div>
        <div style={{ display: "flex", alignItems: "baseline", gap: 8 }}>
          <span style={{ fontSize: 40, fontWeight: 800 }}>{Math.round(dayTotals.calories)}</span>
          <span className="dim">kcal logged</span>
        </div>
        <div style={{ display: "flex", gap: 18, marginTop: 12 }}>
          <Macro label="Protein" value={dayTotals.protein} color="var(--yellow)" />
          <Macro label="Carbs" value={dayTotals.carbs} color="var(--blue)" />
          <Macro label="Fat" value={dayTotals.fat} color="var(--violet)" />
        </div>
      </div>

      {/* Session history */}
      <div style={{ fontWeight: 800, fontSize: 16, margin: "4px 2px 10px" }}>Meal sessions</div>
      {(!state || state.history.length === 0) && !active && (
        <div className="card" style={{ textAlign: "center", padding: 30 }}>
          <div style={{ fontSize: 34, marginBottom: 8 }}>🍽️</div>
          <div style={{ fontWeight: 700 }}>No meals yet</div>
          <p className="dim" style={{ fontSize: 13, marginTop: 4 }}>
            Open the wearable and start eating — sessions appear here live.
          </p>
        </div>
      )}
      <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
        {state?.history.map((s) => <SessionRow key={s.id} session={s} />)}
      </div>
    </main>
  );
}

function Macro({ label, value, color }: { label: string; value: number; color: string }) {
  return (
    <div>
      <div style={{ display: "flex", alignItems: "center", gap: 5 }}>
        <span style={{ width: 8, height: 8, borderRadius: "50%", background: color, display: "inline-block" }} />
        <span className="dim" style={{ fontSize: 12 }}>{label}</span>
      </div>
      <div style={{ fontWeight: 800, fontSize: 18, marginTop: 2 }}>{Math.round(value)}g</div>
    </div>
  );
}

function SessionRow({ session }: { session: EatingSession }) {
  const totals = sessionTotals(session);
  const title = session.items.length
    ? session.items[0].name + (session.items.length > 1 ? ` +${session.items.length - 1}` : "")
    : "Meal";
  const dur =
    session.startedAt && session.endedAt
      ? fmtDuration(Math.floor((session.endedAt - session.startedAt) / 1000))
      : "—";
  const hasStory = typeof session.startCalories === "number" && session.startCalories > totals.calories + 1;
  const pct = hasStory ? Math.round((totals.calories / session.startCalories!) * 100) : 100;
  return (
    <div className="card" style={{ padding: 14, display: "flex", alignItems: "center", gap: 12 }}>
      <div style={{ width: 44, height: 44, borderRadius: "50%", background: "var(--card-2)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 20 }}>🍴</div>
      <div style={{ flex: 1 }}>
        <div style={{ fontWeight: 700 }}>{title}</div>
        <div className="dim" style={{ fontSize: 12 }}>
          {session.startedAt ? fmtTime(session.startedAt) : ""} · {dur}
          {session.detectedBy === "auto" ? " · auto" : ""}
          {hasStory ? ` · ate ${pct}%` : ""}
        </div>
      </div>
      <div style={{ textAlign: "right" }}>
        <div style={{ fontWeight: 800 }}>{Math.round(totals.calories)}</div>
        <div className="dim" style={{ fontSize: 11 }}>{hasStory ? `of ${Math.round(session.startCalories!)}` : "kcal"}</div>
      </div>
    </div>
  );
}

function applyEvent(prev: ChannelState | null, event: SyncEvent, code: string): ChannelState {
  const base: ChannelState = prev ?? { code, current: null, history: [], updatedAt: Date.now() };
  if (event.type === "session.started" || event.type === "session.updated") {
    return { ...base, current: event.session, updatedAt: Date.now() };
  }
  if (event.type === "session.ended") {
    return {
      ...base,
      current: event.session,
      history: [event.session, ...base.history.filter((s) => s.id !== event.session.id)].slice(0, 50),
      updatedAt: Date.now(),
    };
  }
  return base;
}

function fmtDuration(sec: number): string {
  const m = Math.floor(sec / 60).toString().padStart(2, "0");
  const s = (sec % 60).toString().padStart(2, "0");
  return `${m}:${s}`;
}
function fmtTime(ms: number): string {
  return new Date(ms).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}
