"use client";

import { useState } from "react";
import { useSession } from "@/lib/session";
import { getSupabase, isAuthConfigured } from "@/lib/supabase";

/**
 * First-open choice: continue as guest (local only) or sign in with a 6-digit
 * email code (synced account). Shown only while the session mode is unchosen;
 * once chosen, the app renders normally.
 */
export default function WelcomeGate({ children }: { children: React.ReactNode }) {
  const { mode, ready, chooseGuest, setSignedIn } = useSession();

  // Avoid a flash before we've read persisted choice.
  if (!ready) return null;
  if (mode !== "unchosen") return <>{children}</>;

  return <Chooser onGuest={chooseGuest} onSignedIn={setSignedIn} />;
}

type Step = "choose" | "email" | "code";

function Chooser({
  onGuest,
  onSignedIn,
}: {
  onGuest: () => void;
  onSignedIn: (u: { id: string; email: string }) => void;
}) {
  const [step, setStep] = useState<Step>("choose");
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const configured = isAuthConfigured();

  const sendCode = async () => {
    setError(null);
    const addr = email.trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(addr)) {
      setError("Enter a valid email address.");
      return;
    }
    const supabase = getSupabase();
    if (!supabase) {
      setError("Sign-in isn't configured yet. You can continue as a guest for now.");
      return;
    }
    setBusy(true);
    try {
      const { error } = await supabase.auth.signInWithOtp({
        email: addr,
        options: { shouldCreateUser: true },
      });
      if (error) throw error;
      setStep("code");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Couldn't send the code. Try again.");
    } finally {
      setBusy(false);
    }
  };

  const verifyCode = async () => {
    setError(null);
    const token = code.trim();
    if (token.length < 6) {
      setError("Enter the 6-digit code from your email.");
      return;
    }
    const supabase = getSupabase();
    if (!supabase) return;
    setBusy(true);
    try {
      const { data, error } = await supabase.auth.verifyOtp({
        email: email.trim().toLowerCase(),
        token,
        type: "email",
      });
      if (error) throw error;
      const u = data.user;
      if (!u) throw new Error("Sign-in failed. Try again.");
      onSignedIn({ id: u.id, email: u.email ?? email.trim().toLowerCase() });
    } catch (e) {
      setError(e instanceof Error ? e.message : "That code didn't work. Try again.");
    } finally {
      setBusy(false);
    }
  };

  return (
    <main className="app" style={{ justifyContent: "center" }}>
      <div style={{ textAlign: "center", marginBottom: 26 }}>
        <div
          style={{
            width: 72, height: 72, borderRadius: "50%", margin: "0 auto 16px",
            background: "linear-gradient(135deg, var(--orange), var(--yellow))",
            display: "flex", alignItems: "center", justifyContent: "center",
            fontSize: 32, boxShadow: "0 10px 30px rgba(255,140,41,0.45)",
          }}
        >
          ✦
        </div>
        <h1 style={{ fontSize: 34, fontWeight: 800, letterSpacing: -1 }}>NutriWear</h1>
        <p className="muted" style={{ fontSize: 15, marginTop: 6 }}>
          Your AI wearable eating coach.
        </p>
      </div>

      {step === "choose" && (
        <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          <button className="btn-primary" onClick={() => setStep("email")}>
            Sign in with email
          </button>
          <button className="btn-ghost" onClick={onGuest}>
            Continue as guest
          </button>
          <p className="dim" style={{ fontSize: 12, textAlign: "center", marginTop: 4 }}>
            {configured
              ? "Sign in to save your food log and preferences across devices. Guest data stays on this device only."
              : "Guest mode stores data on this device. Email sign-in turns on once the backend is configured."}
          </p>
        </div>
      )}

      {step === "email" && (
        <div className="card" style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          <div style={{ fontWeight: 700, fontSize: 16 }}>What&apos;s your email?</div>
          <p className="dim" style={{ fontSize: 13 }}>We&apos;ll send you a 6-digit code — no password needed.</p>
          <input
            type="email" inputMode="email" autoComplete="email" autoFocus
            value={email} onChange={(e) => setEmail(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter") sendCode(); }}
            placeholder="you@example.com"
            style={inputStyle}
          />
          {error && <p style={errStyle}>{error}</p>}
          <button className="btn-primary" onClick={sendCode} disabled={busy}>
            {busy ? "Sending…" : "Send code"}
          </button>
          <button className="btn-ghost" onClick={() => { setStep("choose"); setError(null); }}>
            Back
          </button>
        </div>
      )}

      {step === "code" && (
        <div className="card" style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          <div style={{ fontWeight: 700, fontSize: 16 }}>Enter your code</div>
          <p className="dim" style={{ fontSize: 13 }}>
            We sent a 6-digit code to <span style={{ color: "var(--text)" }}>{email}</span>.
          </p>
          <input
            inputMode="numeric" autoComplete="one-time-code" autoFocus maxLength={6}
            value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
            onKeyDown={(e) => { if (e.key === "Enter") verifyCode(); }}
            placeholder="123456"
            style={{ ...inputStyle, textAlign: "center", letterSpacing: 8, fontSize: 24, fontFamily: "ui-monospace, monospace" }}
          />
          {error && <p style={errStyle}>{error}</p>}
          <button className="btn-primary" onClick={verifyCode} disabled={busy}>
            {busy ? "Verifying…" : "Verify & sign in"}
          </button>
          <button className="btn-ghost" onClick={() => { setStep("email"); setCode(""); setError(null); }}>
            Use a different email
          </button>
        </div>
      )}
    </main>
  );
}

const inputStyle: React.CSSProperties = {
  background: "var(--card-2)", border: "1px solid var(--stroke)", borderRadius: 12,
  color: "var(--text)", padding: "13px 15px", fontSize: 16, width: "100%",
};
const errStyle: React.CSSProperties = { color: "var(--yellow)", fontSize: 12 };
