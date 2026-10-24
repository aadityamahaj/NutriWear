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
