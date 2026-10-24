"use client";

import { useSession } from "@/lib/session";
import { getSupabase } from "@/lib/supabase";

/**
 * Compact account chip: shows guest vs. signed-in, with sign-out / sign-in.
 * Signing out returns to the choice screen.
 */
export default function AccountStatus() {
  const { mode, user, signOut } = useSession();

  const handleSignOut = async () => {
    const supabase = getSupabase();
    if (supabase) {
      try { await supabase.auth.signOut(); } catch { /* ignore */ }
    }
    signOut();
  };

  if (mode === "signedIn" && user) {
    return (
      <div className="card" style={{ display: "flex", alignItems: "center", gap: 12, padding: 14 }}>
        <div
          style={{
            width: 36, height: 36, borderRadius: "50%", flexShrink: 0,
            background: "linear-gradient(135deg, var(--orange), var(--yellow))",
            display: "flex", alignItems: "center", justifyContent: "center",
            color: "#000", fontWeight: 800,
          }}
        >
          {user.email.charAt(0).toUpperCase()}
        </div>
        <div style={{ minWidth: 0 }}>
          <div style={{ fontWeight: 700, fontSize: 13 }}>Signed in</div>
          <div className="dim" style={{ fontSize: 12, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
            {user.email}
          </div>
        </div>
        <button
          onClick={handleSignOut}
          style={{ marginLeft: "auto", background: "var(--card-2)", border: "1px solid var(--stroke)", borderRadius: 10, color: "var(--text-2)", padding: "8px 12px", fontSize: 12, fontWeight: 600 }}
        >
          Sign out
        </button>
      </div>
    );
  }

  // Guest
  return (
    <div className="card" style={{ display: "flex", alignItems: "center", gap: 12, padding: 14 }}>
      <div style={{ fontSize: 20 }}>👤</div>
      <div style={{ minWidth: 0 }}>
        <div style={{ fontWeight: 700, fontSize: 13 }}>Guest</div>
        <div className="dim" style={{ fontSize: 12 }}>Data saved on this device only</div>
      </div>
      <button
        onClick={signOut}
        style={{ marginLeft: "auto", background: "var(--card-2)", border: "1px solid var(--stroke)", borderRadius: 10, color: "var(--orange)", padding: "8px 12px", fontSize: 12, fontWeight: 700 }}
      >
        Sign in
      </button>
    </div>
  );
}
