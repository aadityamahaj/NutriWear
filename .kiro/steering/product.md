---
inclusion: always
---

# NutriWear — Product Overview

NutriWear is an AI eating coach. A user points their camera (or a paired web
"wearable") at a plate, the app recognizes the food and estimates macros, then
an AI coach guides them in real time while they eat. Users can ask the coach
questions by typing or **by voice**.

## Core capabilities

- **Food recognition** — a multimodal LLM (Groq vision model) reads a photo of
  the plate and returns structured food items with per-item macros and a
  confidence level.
- **AI coach** — a text LLM answers eating questions using the user's goals,
  what they've eaten today, and the current meal as context. Replies can be
  spoken aloud.
- **Voice commands** — the user asks the coach out loud. On iOS this uses
  `Speech` + `AVAudioEngine` (`SpeechService`); on the web wearable it uses the
  Web Speech API (`useVoiceCommand.ts`).
- **Live sync** — a Next.js web app (`nutriwear-web/`) acts as a stand-in
  wearable camera. It detects eating sessions and streams them to the iOS app,
  which logs completed sessions as meals automatically.
- **Dashboard & history** — daily macro totals, a weekly calorie chart, and a
  log of past meals.

## Two surfaces, one product

- `Sources/` — the native **iOS app** (SwiftUI, iOS 17+).
- `nutriwear-web/` — the **Next.js web companion** (the "wearable" camera and
  its API routes), which talks to Groq and streams sessions to the phone.

Both surfaces share the same Groq-backed intelligence and the same nutrition
concepts (food items, macros, eating sessions).

## Proactive coaching & voice control

- **Proactive, not just reactive.** During a live eating session the coach
  watches pace and fires cues on its own (slow-down, halfway check-in, hydration,
  finish summary). On iOS pace is time-vs-meal-size (`CoachService.PaceSnapshot`);
  on the web wearable it's a real plate-fullness watcher (`useProactivePace.ts`)
  that nudges "slow down" when food disappears too fast.
- **User-controlled cues + delivery.** `CoachingPreferences` lets the user turn
  auto-coaching on (all cues) or off (pick specific cues). Delivery channel is
  the user's choice: spoken (TTS), local notifications, or both.
- **Voice commands.** `VoiceCommandRouter` classifies a transcript into intents:
  "let's eat" / "start eating" → start a session; "I'm done" / "finished" → stop
  logging; "pause"/"resume"; anything else → a coach question. The iOS
  `SpeechService` supports a hands-free command mode that keeps listening and
  auto-restarts so "I'm done" is caught without tapping.

## Device connectivity (forward-looking)

- `BluetoothService` (CoreBluetooth) scans for and connects to BLE devices so
  future NutriWear hardware can pair. Accessible from Settings → Devices.

## Insights

- The **Insights** tab (`EatingInsights` + `InsightsView`) analyzes logged meals
  for pace, meal timing, late-night eating, portion leftovers, and protein share,
  then asks the LLM for personalized improvement suggestions (digestion, habits,
  eating length).

## Accounts

- On first open both surfaces show a choice: **continue as guest** (data stays
  on-device) or **sign in** with a 6-digit email code.
- Auth is **Supabase email OTP**. Web uses the Supabase JS SDK; iOS calls the
  same Supabase GoTrue REST endpoints directly (no SDK dependency). Both
  gracefully run guest-only until Supabase env vars are set.
- Signed-in users get **per-user cloud storage**: web stores profile/prefs in a
  `profiles` table; iOS syncs profile + meals to a `user_data` table. Both use
  Postgres **row-level security** keyed on `auth.uid()` so users only see their
  own data.
- The 4-char **pairing code** is unrelated to auth — it only links the phone to
  the web wearable session. Don't conflate the two.
- Config: iOS reads `SUPABASE_URL` (host only, no scheme — xcconfig treats `//`
  as a comment) and `SUPABASE_ANON_KEY` from Secrets.xcconfig; web reads
  `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY`.
