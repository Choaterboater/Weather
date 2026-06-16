# Fishing Weather App — Build Plan

A SwiftUI weather app that doubles as an AI-powered fishing assistant. Start as a
clean, "ditch-the-other-app" weather app, then layer fishing intelligence on top.

> **Updated for WWDC 2026** (June 2026). Targets iOS 27 / Xcode 27 / Swift 6.4.

---

## Decisions already made

- **Species picker at the top.** Tap **Bass / Crappie / Catfish / Bluegill / All**.
  The advice focuses on whatever is tapped. Chosen because it's the cleanest to
  build and the cleanest to use — no per-species onboarding, no settings spelunking.

---

## Stack

| Concern          | Choice                                                        |
| ---------------- | ------------------------------------------------------------ |
| UI               | SwiftUI + Liquid Glass                                        |
| Weather data     | WeatherKit                                                    |
| On-device AI     | Foundation Models (structured output for bait tips)          |
| Location         | CoreLocation (current + saved spots)                          |
| Image generation | Replicate (bait/species art, hero card imagery)              |
| Platform         | iOS 27, Xcode 27, Swift 6.4 (strict concurrency)             |

### What's new from WWDC 2026 (and why it matters here)

- **Foundation Models — multi-provider `LanguageModel` protocol.** The same Swift
  API can now route to the on-device model, Private Cloud Compute, *or* a
  third-party provider (Anthropic and Google ship Swift packages that plug into
  the same surface). We design the bait engine against this protocol so we can
  start on-device and swap in a bigger model later **without changing app logic**.
- **Free Private Cloud Compute tier** for developers under ~2M first-time
  downloads. This largely removes the "older iPhone can't run the AI" problem —
  devices without an on-device model can fall back to PCC instead of losing the
  feature entirely. We still keep a non-AI rule-based path for full offline use.
- **Image input (multimodal).** Foundation Models can now take images. Future
  option: let the user photograph their lure/water and have the model factor it in.
- **No third-party UI package needed.** (The earlier "plaster/PlastersSwift" note
  was a mistake and has been dropped — native SwiftUI + Liquid Glass covers it.)

### Dependencies

- **Replicate** — HTTP API for image generation. No SDK needed; a thin
  `URLSession` client (submit prediction → poll → fetch output URL) is enough.
  API token stays out of git (xcconfig / secrets manager).
- **Solunar** — hand-roll the known formulas or pull a small Swift package
  (decide in Phase 2 on accuracy vs. dependency cost).

---

## Build order — 5 phases

### Phase 1 — Plain weather app first  *(in progress — scaffolded in this repo)*

Get a working, genuinely usable weather app before any fishing logic exists.

- Xcode project, WeatherKit capability, Apple Developer entitlement.
- Request location permission (CoreLocation); handle denied / restricted states.
- Screens / sections: current conditions, hourly, 10-day, active alerts.
- **Exit criteria:** good enough to replace the weather app you use today.

See `FishingWeather/` for the scaffold and `FishingWeather/README.md` for how to
generate and run the project.

### Phase 2 — Fishing conditions layer (no AI yet)  *(scaffolded in this repo)*

Deterministic math/facts layer — computed directly, no model.

- From WeatherKit: wind speed/direction, pressure, UV, moon phase, sunrise/sunset.
- Compute **pressure trend** (last few hours → rising / falling / steady) and
  **solunar bite windows** (major/minor feeding times).
- New **Fishing** screen showing these as plain facts.
- **Exit criteria:** pressure trend + today's bite windows, validated against a
  couple of public solunar calculators.

### Phase 3 — Species picker  *(scaffolded in this repo)*

- Tap-to-pick row: Bass / Crappie / Catfish / Bluegill / All.
- Persist the choice (`@AppStorage`); it scopes the Fishing screen and feeds Phase 4.

### Phase 4 — AI bait engine  *(scaffolded in this repo)*

Foundation Models with **structured output** so the model fills tidy fields:

```
BaitRecommendation
├─ topBait:    String
├─ color:      String
├─ technique:  String
├─ depth:      String
├─ confidence: Int      // 0–100 or Low/Med/High
└─ whyReason:  String
```

- **Input:** Phase 2 facts + picked species. **Output:** the bait card above.
- **Daily report:** plain-language summary —
  *"pressure's dropping, light chop, good crappie window 4–6pm."*
- **Optional:** ask-it-anything box (*"why aren't they biting?"*).
- **Provider strategy (WWDC 2026):** code against the `LanguageModel` protocol;
  default to on-device, fall back to Private Cloud Compute, keep a rule-based
  path for full offline. Optional bigger-model provider for the free-text box.
- **Replicate hook-in:** generate matching art for the bait card (illustration of
  recommended bait + color) or a conditions hero image. Cache by
  (species + bait + color) so we don't regenerate the same art.

### Phase 5 — Polish  *(scaffolded in this repo)*

- Liquid Glass styling pass; saved fishing spots; bite-window notifications.
- Replicate art polish (consistent style, caching, static-asset fallback).

### Beyond the plan  *(scaffolded in this repo)*

- **Real product photos.** Bait card pulls a real product photo + "Buy" link from
  Amazon's Product Advertising API (`BaitImageProvider` chain), falling back to
  Replicate art. Tackle retailers (Tackle Warehouse, Bass Pro, FishUSA) plug into
  the same protocol.
- **Scout the Water.** Take/pick a photo of the spot; Vision detects scene
  features and Foundation Models turns them + conditions into structured "where to
  cast" guidance. When the WWDC 2026 FM native image-input API is confirmed for
  the shipped SDK, the Vision pre-pass can be swapped for direct image input.
- **Catch Log.** Record catches (species, bait, size, photo) with an automatic
  conditions snapshot (pressure trend, moon phase, air temp, spot), persisted to
  disk as JSON + photo files, with quick stats (top species / top bait).

---

## Things to know before starting

- **WeatherKit needs a paid Apple Developer account ($99/yr).** Free tier is
  500k calls/month — far more than this app will use.
- **Foundation Models AI tiers:** on-device on newer iPhones; Private Cloud
  Compute (free tier) extends it to more devices; rule-based path covers offline.
- **Secrets:** Replicate token (and any keys) stay out of git — local xcconfig
  that's `.gitignore`d, or a secrets manager.

---

## Open questions

1. Solunar: hand-roll vs. small Swift package?
2. Replicate model choice for image generation (which image model, target style).
3. Bundle identifier / Team ID for signing (currently a placeholder in the scaffold).
