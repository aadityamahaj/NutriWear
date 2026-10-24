"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";

interface NavItem {
  href: string;
  label: string;
  icon: string;
}

const ITEMS: NavItem[] = [
  { href: "/", label: "Home", icon: "✦" },
  { href: "/wear", label: "Wearable", icon: "📷" },
  { href: "/dashboard", label: "Dashboard", icon: "📊" },
];

/**
 * App-wide floating navigation. Collapsible so it doesn't eat screen space on
 * mobile: it shows as a small round button, and tapping it pops the menu up.
 * On the /wear camera screen it starts collapsed (the camera needs the room);
 * elsewhere it starts expanded. The open/closed choice is remembered.
 */
export default function NavBar() {
  const pathname = usePathname();
  const onWear = pathname === "/wear";
  const [open, setOpen] = useState(false);

  // Restore the last open/closed preference; default to open except on /wear.
  useEffect(() => {
    const saved = localStorage.getItem("nutriwear.nav.open");
    if (saved === "1") setOpen(true);
    else if (saved === "0") setOpen(false);
    else setOpen(!onWear);
  }, [onWear]);

  const toggle = () => {
    setOpen((prev) => {
      const next = !prev;
      localStorage.setItem("nutriwear.nav.open", next ? "1" : "0");
      return next;
    });
  };

  return (
    <div
      style={{
        position: "fixed",
        left: 0,
        right: 0,
        bottom: 0,
        display: "flex",
        justifyContent: "center",
        padding: "0 16px calc(14px + env(safe-area-inset-bottom))",
        pointerEvents: "none", // only children are interactive
        zIndex: 50,
      }}
    >
      {open ? (
        <nav
          aria-label="Primary"
          style={{
            pointerEvents: "auto",
            display: "flex",
            alignItems: "center",
            gap: 4,
            background: "rgba(20,20,22,0.82)",
            backdropFilter: "blur(16px)",
            WebkitBackdropFilter: "blur(16px)",
            border: "1px solid var(--stroke)",
            borderRadius: 999,
            padding: 6,
            boxShadow: "0 12px 34px rgba(0,0,0,0.5)",
            maxWidth: 460,
            width: "100%",
          }}
        >
          {ITEMS.map((item) => {
            const active = pathname === item.href;
            return (
              <Link
                key={item.href}
                href={item.href}
                style={{
                  flex: 1,
                  display: "flex",
                  flexDirection: "column",
                  alignItems: "center",
                  gap: 2,
                  padding: "8px 4px",
                  borderRadius: 999,
                  background: active ? "linear-gradient(120deg, var(--orange), var(--yellow))" : "transparent",
                  color: active ? "#000" : "var(--text-2)",
                  fontWeight: active ? 800 : 600,
                  transition: "background 0.15s",
                }}
              >
                <span style={{ fontSize: 18, lineHeight: 1 }}>{item.icon}</span>
                <span style={{ fontSize: 11 }}>{item.label}</span>
              </Link>
            );
          })}
          <button
            onClick={toggle}
            aria-label="Collapse menu"
            style={{
              width: 38,
              height: 38,
              borderRadius: "50%",
              background: "var(--card-2)",
              border: "1px solid var(--stroke)",
              color: "var(--text-2)",
              fontSize: 15,
              flexShrink: 0,
            }}
          >
            ▾
          </button>
        </nav>
      ) : (
        <button
          onClick={toggle}
          aria-label="Open menu"
          style={{
            pointerEvents: "auto",
            width: 52,
            height: 52,
            borderRadius: "50%",
            background: "rgba(20,20,22,0.82)",
            backdropFilter: "blur(16px)",
            WebkitBackdropFilter: "blur(16px)",
            border: "1px solid var(--stroke)",
            color: "var(--text)",
            fontSize: 20,
            boxShadow: "0 10px 28px rgba(0,0,0,0.5)",
            alignSelf: "flex-end",
            marginRight: 2,
          }}
        >
          ☰
        </button>
      )}
    </div>
  );
}
