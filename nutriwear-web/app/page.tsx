"use client";

import Link from "next/link";
import { usePairingCode } from "@/lib/useChannel";
import AccountStatus from "./AccountStatus";

export default function Home() {
  const [code] = usePairingCode();

  return (
    <main className="app">
      <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", gap: 28 }}>
        <div>
          <div
            style={{
              width: 76,
              height: 76,
              borderRadius: "50%",
              background: "linear-gradient(135deg, var(--orange), var(--yellow))",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              boxShadow: "0 10px 30px rgba(255,140,41,0.45)",
              marginBottom: 18,
              fontSize: 34,
            }}
          >
            ✦
          </div>
          <h1 style={{ fontSize: 40, fontWeight: 800, letterSpacing: -1 }}>NutriWear</h1>
          <p className="muted" style={{ fontSize: 17, marginTop: 8, lineHeight: 1.4 }}>
            Your AI wearable eating coach. It sees your plate, auto-detects when you
            start eating, and logs your meal the moment you&apos;re done.
          </p>
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          <Link href="/wear" className="btn-primary" style={{ display: "block", textAlign: "center" }}>
            📷 Start as Wearable
          </Link>
          <Link href="/dashboard" className="btn-ghost" style={{ display: "block", textAlign: "center" }}>
            📊 Open Companion Dashboard
          </Link>
        </div>

        <div className="card" style={{ display: "flex", alignItems: "center", gap: 14 }}>
          <div>
            <div className="dim" style={{ fontSize: 12, fontWeight: 700, letterSpacing: 1 }}>
              PAIRING CODE
            </div>
            <div style={{ fontSize: 34, fontWeight: 800, letterSpacing: 6, fontFamily: "ui-monospace, monospace" }}>
              {code || "···· "}
            </div>
          </div>
          <div className="muted" style={{ fontSize: 12, marginLeft: "auto", textAlign: "right", maxWidth: 150 }}>
            Enter this on your phone&apos;s NutriWear app to sync live.
          </div>
        </div>

        <AccountStatus />
      </div>

      <p className="dim" style={{ fontSize: 11, textAlign: "center", marginTop: 20 }}>
        The wearable is the camera. The phone is the companion. They sync in real time.
      </p>
    </main>
  );
}
