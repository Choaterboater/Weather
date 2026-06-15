# Fishing Weather App — Build Plan

A SwiftUI weather app that doubles as an AI-powered fishing assistant. Start as a
clean, "ditch-the-other-app" weather app, then layer fishing intelligence on top.

---

## Decisions already made

- **Species picker at the top.** Tap **Bass / Crappie / Catfish / Bluegill / All**.
  The advice focuses on whatever is tapped. Chosen because it's the cleanest to
  build and the cleanest to use — no per-species onboarding, no settings spelunking.

---

## Stack

| Concern            | Choice                                              |
| ------------------ | --------------------------------------------------- |
| UI                 | SwiftUI + Liquid Glass styling                      |
| Weather data       | WeatherKit                                          |
| On-device AI       | Foundation Models (structured output for bait tips) |
| Location           | CoreLocation (current + saved spots)                |
| Image generation   | Replicate (bait/species art, hero card imagery)     |
| Language / toolset  | Swift 6.4                                            |

### Dependencies to confirm

- **`PlastersSwift`** *(name needs confirmation)* — noted from the request as a
  package to pull in. Before Phase 1 wiring, confirm the exact package name, its
  repo URL, and what role it plays (UI helpers? networking? something else) so we
  add it to the right phase. Flagged here so it isn't lost.
- **Replicate** — HTTP API for image generation. No official Swift SDK is
  required; a thin `URLSession` client is enough (submit prediction, poll until
  complete, fetch the output image URL). API token lives in a config not checked
  into git.

---

## Build order — 5 phases

### Phase 1 — Plain weather app first

Get a working, genuinely usable weather app before any fishing logic exists.

- Set up the Xcode project, WeatherKit capability, and the Apple Developer entitlement.
- Request location permission (CoreLocation), handle denied / restricted states.
- Screens / sections:
  - Current conditions (temp, feels-like, condition, wind, humidity, UV).
  - Hourly forecast.
  - 10-day forecast.
  - Active weather alerts.
- **Exit criteria:** the app is good enough to replace the weather app you use today.

### Phase 2 — Fishing conditions layer (no AI yet)

The math/facts layer. These are deterministic calculations, so we compute them
directly — no model involved.

- Pull from WeatherKit: wind speed/direction, barometric pressure, UV, moon
  phase, sunrise/sunset.
- Compute:
  - **Pressure trend** — compare the last several hours → rising / falling / steady
    (fish behavior tracks pressure changes more than absolute values).
  - **Solunar bite windows** — major/minor feeding times from moon position and
    sunrise/sunset. Hand-roll the known formulas, or pull a small Swift package.
    Decide based on accuracy vs. dependency cost.
- New **Fishing** screen showing all of the above as plain facts.
- **Exit criteria:** Fishing screen shows pressure trend + today's bite windows,
  validated against a couple of public solunar calculators.

### Phase 3 — Species picker

- Add the tap-to-pick row: Bass / Crappie / Catfish / Bluegill / All.
- Persist the choice (e.g. `@AppStorage` / UserDefaults) so it's remembered.
- Selected species scopes the Fishing screen and feeds Phase 4.

### Phase 4 — AI bait engine

Set up Foundation Models with **structured output** so the model fills tidy
fields instead of returning loose prose.

```
BaitRecommendation
├─ topBait:    String
├─ color:      String
├─ technique:  String
├─ depth:      String
├─ confidence: Int      // 0–100 or Low/Med/High
└─ whyReason:  String
```

- **Input:** Phase 2 facts (pressure trend, wind, UV, moon, bite windows,
  sunrise/sunset) + the picked species.
- **Output:** the bait card above.
- **Daily report:** a plain-language summary —
  *"pressure's dropping, light chop, good crappie window 4–6pm."*
- **Optional:** an ask-it-anything box (*"why aren't they biting?"*) that answers
  using the same conditions context.
- **Replicate hook-in:** generate a matching visual for the bait card / daily
  report — e.g. an illustration of the recommended bait + color, or a hero image
  for the current conditions. Submit a prediction, poll, cache the resulting
  image by (species + bait + color) so we don't regenerate the same art.

### Phase 5 — Polish

- Liquid Glass styling pass across all screens.
- Saved fishing spots (multiple CoreLocation locations).
- Local notification when a good bite window is approaching.
- Replicate-generated art polish (consistent style, caching, graceful fallback to
  a static asset if generation fails or is offline).

---

## Things to know before starting

- **WeatherKit needs a paid Apple Developer account ($99/yr).** Free tier is
  500k calls/month — far more than this app will use.
- **Foundation Models only runs on newer iPhones.** Add a simple fallback for
  older devices: hide the AI tips, or show the Phase 2 facts + a non-AI
  rule-based suggestion. The whole app must remain useful without the AI layer.
- **Solunar math:** known formulas exist. Hand-roll or grab a small Swift package.
- **Secrets:** Replicate API token (and any other keys) must stay out of git.
  Use a local config / xcconfig that's `.gitignore`d, or a secrets manager.

---

## Open questions

1. Exact identity of the **`PlastersSwift`** dependency (name / repo / role).
2. Solunar: hand-roll vs. package?
3. Replicate model choice for image generation (which image model, target style).
