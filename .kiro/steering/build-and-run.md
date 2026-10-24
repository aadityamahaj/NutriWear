---
inclusion: always
---

# Build & Run

## Prerequisites

- **Xcode 16+** (iOS 17 deployment target, Swift 6).
- **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** — the `.xcodeproj` is
  generated from `project.yml` and is **gitignored**. Regenerate it with
  `xcodegen generate` after cloning or whenever `project.yml` changes.
- **A Groq API key** — free at https://console.groq.com/keys.
- **Node 18+** (for the `nutriwear-web/` companion).

## iOS app

1. `cp Secrets.example.xcconfig Secrets.xcconfig` and paste your Groq key into
   `GROQ_API_KEY`. This file is gitignored; the key is injected into Info.plist
   at build time and read via `GroqClient.apiKey`.
2. `xcodegen generate` to produce `NutriWear.xcodeproj`.
3. Open the project in Xcode and run on an iOS 17+ simulator or device.

Notes:
- **Voice input needs a real device or a simulator with a working mic route.**
  `SpeechService` bails gracefully when no mic input is available and shows a
  message instead of crashing.
- Speech recognition uses the `.spokenAudio` audio session mode and checks
  `SFSpeechRecognizer.isAvailable` before starting — don't switch the mode back
  to `.measurement`, which starves the recognizer of usable audio.

### Command-line build (CI / quick check)

```
xcodebuild -project NutriWear.xcodeproj -scheme NutriWear \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

## Web companion (`nutriwear-web/`)

1. `cp .env.local.example .env.local` and add your Groq key (server-side only).
2. `npm install`
3. `npm run dev` — serves on `0.0.0.0:3000` so the phone can reach it over LAN.

Pair the iOS **Live** tab with the web app using the machine's LAN URL
(`http://<your-ip>:3000`) and the pairing code shown in the web UI.

## Secrets

Never commit real keys. `Secrets.xcconfig` and `nutriwear-web/.env.local` are
gitignored; only the `.example` templates are tracked.
