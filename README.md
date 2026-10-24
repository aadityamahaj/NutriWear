# NutriWear

**Your AI wearable eating coach.** Point a camera at your plate, NutriWear recognizes the food and estimates macros, then an AI coach guides you in real time while you eat — proactively, by voice, and personalized to your goals.

**Live web demo:** https://nutriwear-web.vercel.app

NutriWear has two surfaces that share one Groq-backed brain and sync live:

- **iOS app** (`Sources/`) — SwiftUI, iOS 17+. Scan meals, track macros, chat with the coach, review eating-habit insights.
- **Web companion** (`nutriwear-web/`) — Next.js. Acts as the "wearable" camera (auto-detects eating, before/after consumption) and a live dashboard. Deployed on Vercel.

---

## Features

- **Food recognition** — a multimodal LLM reads a photo of the plate and returns structured food items with per-item macros and confidence.
- **Proactive AI coach** — watches your eating pace during a meal and nudges you (slow down, halfway check-in, hydration, finish summary) on its own. Cues are user-configurable (auto, or pick specific cues) and delivered as voice (TTS), notifications, or both.
- **Voice control** — hands-free commands ("let's eat" / "I'm done") plus spoken coach questions. On the web, an always-listening mode uses a wake word ("Hey NutriWear" / "coach, …") so it ignores ambient conversation, and the mic only runs while the site is the active page.
- **Live sync** — the web wearable detects eating, compares before/after plates to estimate what you actually ate, and streams completed sessions to the phone, which logs them automatically.
- **Insights** — analyzes your logged meals for pace, meal timing, late-night eating, leftovers, and protein share, then generates a personalized improvement plan.
- **Accounts** — continue as a guest (local only) or sign in with a 6-digit email code (Supabase) to sync your profile and food log across devices.
- **Bluetooth** — scan and connect to BLE devices, built for future NutriWear hardware.

---

## Running it

### iOS app

Prerequisites: Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen), a free [Groq key](https://console.groq.com/keys).

```bash
cp Secrets.example.xcconfig Secrets.xcconfig   # add your GROQ_API_KEY (and optional Supabase values)
xcodegen generate                              # the .xcodeproj is generated, not committed
open NutriWear.xcodeproj                        # run on an iOS 17+ simulator or device
```

Notes:
- The `.xcodeproj` is generated from `project.yml` (gitignored). Run `xcodegen generate` after cloning.
- Voice input needs a real device or a simulator with a working mic route; it degrades gracefully otherwise.

### Web companion

Prerequisites: Node 18+, a Groq key.

```bash
cd nutriwear-web
cp .env.local.example .env.local               # add GROQ_API_KEY (+ optional Upstash/Supabase)
npm install
npm run dev                                     # http://localhost:3000
```

Open `/wear` on a phone (camera) and `/dashboard` on a laptop; pair them with the 4-character code. In the iOS app's **Live** tab, set the server URL and pairing code to sync.

> Microphone and camera need a secure context (HTTPS or localhost), so on a phone use the deployed HTTPS URL, not a LAN IP.

---

## Configuration

Secrets are injected at build time and never committed (`Secrets.xcconfig` and `.env.local` are gitignored).

| Purpose | iOS (`Secrets.xcconfig`) | Web (`.env.local` / Vercel) |
| --- | --- | --- |
| AI (required) | `GROQ_API_KEY` | `GROQ_API_KEY` |
| Live sync across instances | — | `UPSTASH_REDIS_REST_URL`, `UPSTASH_REDIS_REST_TOKEN` |
| Accounts (optional) | `SUPABASE_URL` (host only), `SUPABASE_ANON_KEY` | `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` |

Without the optional values, the app still runs: guest-only accounts, and in-memory (single-process) sync. See `nutriwear-web/DEPLOY.md` for the full Vercel + Supabase + Upstash setup.

---

## Project structure

```
Sources/              iOS app (App, Features, Models, Services)
Resources/            Info.plist, asset catalog
project.yml           XcodeGen spec (the .xcodeproj is generated from this)
nutriwear-web/        Next.js web companion (app/, lib/, API routes)
.kiro/                Kiro steering (project context for the AI dev environment)
```

More detail lives in `.kiro/steering/` (product overview, structure/conventions, build-and-run).

---

## Tech

Swift 6 / SwiftUI · Next.js / React · Groq (vision + text LLMs) · Upstash Redis (live sync) · Supabase (auth + per-user storage) · CoreBluetooth · Web Speech API / `Speech` framework.
