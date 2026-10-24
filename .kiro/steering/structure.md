---
inclusion: always
---

# Project Structure & Conventions

## Layout

```
Sources/                 iOS app (SwiftUI)
  App/                   App entry, AppModel (source of truth), RootView, Theme
  Features/              One folder per screen/feature
    Camera/              Scan + analysis + meal timer
    Coach/               AI coach chat + voice (CoachView)
    Dashboard/           Daily dashboard + settings
    History/             Past meals
    Live/                Wearable pairing + live session
    Onboarding/          First-run profile setup
    Shared/              Reusable views (macros, photo picker)
  Models/                Plain data types (Nutrition, UserProfile)
    Insights/            Analysis + personalized improvement plan
    Settings/            Bluetooth device pairing
  Services/              Non-UI logic (Groq, recognition, speech, sync,
                         persistence, voice routing, proactive coach,
                         notifications, insights analytics, bluetooth)
Resources/               Info.plist, asset catalog
nutriwear-web/           Next.js companion ("wearable" camera + API)
project.yml              XcodeGen spec — the project is generated from this
Secrets.xcconfig         Groq API key (gitignored; see Secrets.example.xcconfig)
```

## Architecture conventions

- **`AppModel` is the single source of truth** for app state (meals, profile,
  pending meal, live sync). It's `@MainActor` and `ObservableObject`; views
  observe it via `@EnvironmentObject`. Persisted state is written back through
  `PersistenceStore` in `didSet`.
- **Services hold logic, views stay thin.** Anything involving the network,
  speech, the camera, or persistence lives in `Sources/Services/`. Views call
  into the model/services and render published state.
- **Groq access goes through `GroqClient`** (an `actor`). It's OpenAI-compatible
  chat completions. Model IDs live in the `GroqModel` enum so they're easy to
  swap. Use `jsonMode: true` for structured extraction (food recognition).
- **The API key is injected at build time** from `Secrets.xcconfig` → Info.plist
  (`GROQ_API_KEY`) and read via `GroqClient.apiKey`. Never hardcode keys.
- **Concurrency:** Swift 6, but strict concurrency is set to `minimal` in
  `project.yml`. UI-facing types are `@MainActor`. System callbacks that fire on
  background queues (speech/mic permission, synthesizer/CoreBluetooth delegates)
  must hop back to the main actor with `Task { @MainActor in ... }` — see
  `SpeechService` and `BluetoothService`. Non-Sendable objects crossing that
  boundary (e.g. `CBPeripheral`) use a small `@unchecked Sendable` box; this is
  safe only because those delegate queues are `.main`.
- **Eating sessions & proactive coach** are driven from `AppModel`
  (`startEatingSession`/`finishEatingSession`, the pace loop, and `fireCue`),
  using `CoachingPreferences` to decide which cues fire and how they're
  delivered. Keep this logic in the model, not the views.
- **Voice intents** go through `VoiceCommandRouter.classify` — add new spoken
  commands there (pure, regex-based, unit-testable) rather than scattering
  keyword checks in views.

## Style

- SwiftUI with a shared `Theme` for colors/spacing; prefer `Theme.*` over inline
  colors.
- Keep feature views self-contained; factor shared UI into `Features/Shared`.
- Model types are value types (`struct`) with simple, serializable fields.
