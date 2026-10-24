import type { Metadata, Viewport } from "next";
import "./globals.css";
import NavBar from "./NavBar";
import { SessionProvider } from "@/lib/session";
import WelcomeGate from "./WelcomeGate";

export const metadata: Metadata = {
  title: "NutriWear",
  description: "AI wearable nutrition companion — the live eating coach.",
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
  themeColor: "#0a0a0c",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>
        <SessionProvider>
          <WelcomeGate>
            {children}
            <NavBar />
          </WelcomeGate>
        </SessionProvider>
      </body>
    </html>
  );
}
