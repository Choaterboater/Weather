# BiteCast Product Redesign and Community Design

**Date:** 2026-07-12

**Status:** Approved direction; implementation planning pending

**Scope:** Native iOS product redesign, resilient weather, interactive BiteTime guidance, map-first discovery, private catch logging, and optional CloudKit community publishing

## Summary

BiteCast will move from six loosely connected utility tabs to a coherent fishing product organized around five jobs:

1. See what anglers are catching.
2. Discover useful water and nearby access.
3. Log a catch quickly.
4. Decide when and how to fish.
5. Review personal history and preferences.

The permanent navigation becomes **Community**, **Map**, a central **Log Catch** action, **BiteTime**, and **You**. Weather remains essential, but it becomes supporting context inside BiteTime and the map instead of occupying a separate top-level destination.

The visual direction takes the hierarchy, photo-forward presentation, map layering, compact glass controls, and large native typography from the supplied references without copying their brand, wording, proprietary data, or exact layouts. BiteCast retains its marine color identity and Bite Gauge while removing the repeated “generated dashboard” pattern of monospaced text inside identical cards.

This is a master design split into four independently verifiable delivery phases. All four phases are required.

## Product principles

- **Decision first:** Each screen answers a fishing question instead of merely listing data.
- **Local first:** Catch history and photos are usable without an account or network.
- **Private by default:** Exact catch coordinates are never published automatically.
- **Honest intelligence:** Generated advice is labeled, grounded in named inputs, and backed by deterministic guidance when Apple Intelligence is unavailable.
- **Native iOS:** Use SwiftUI, MapKit, Charts, CloudKit, PhotosUI, Core Location, and Apple Foundation Models before adding third-party dependencies.
- **Resilient data:** A single provider outage cannot blank every weather-dependent screen.
- **Progressive detail:** The glance view is simple; taps and chart selection reveal the underlying evidence.
- **Accessible and dynamic:** Native text styles, Dynamic Type, VoiceOver chart descriptions, adequate contrast, and reduced-motion behavior are requirements.

## Information architecture

### Community

The Community destination contains three feeds:

- **Feed:** Recent public posts from joined groups and explicitly followed anglers.
- **My Area:** Public catches near an approximate location, using a user-selected radius.
- **Groups:** Waterbody, regional, and species groups the user joins.

A post is photo-first and may show species, length, weight, bait, waterbody, approximate area, time bucket, and a short note. It supports like, comment, share, save, report, and block. Exact coordinates, private notes, raw conditions snapshots, and unpublished photos never leave the device.

Community is readable without publishing. Creating posts, comments, likes, groups, or reports requires an active iCloud account.

### Map

The Map destination is the primary discovery surface. It uses MapKit and supports these independently toggled layers:

- Current location and selected saved spot
- Curated fishing spots
- Saved spots
- Boat ramps and piers
- Personal catches
- Public community catches, clustered and location-obscured
- Personal catch heatmap
- Weather, tide, and bite-condition summary overlays where data is available

Top controls provide search, species filters, map style, and layer selection. A bottom sheet moves between a compact summary and a browsable results list. Selecting a pin or cluster updates the sheet rather than immediately pushing a full-screen card.

BiteCast will not claim proprietary depth contours, navigation charts, private property boundaries, or live vessel information unless a licensed source is added later.

### Central Log Catch action

The middle tab control is an action, not a destination. It opens a photo-forward catch composer with:

- Camera or photo library
- Species, bait, length, weight, and notes
- Optional on-device fish identification
- Automatic time, active place, weather, wind, pressure, moon, and tide snapshot
- A preview card matching the personal feed presentation
- A **Save Privately** primary action
- A separate **Publish** option that exposes privacy controls before upload

Saving locally never depends on AI, WeatherKit, CloudKit, or internet access. A missing bait value no longer blocks saving; species and date are the minimum meaningful fields.

### BiteTime

BiteTime combines current conditions, fishing score, hourly bite guidance, forecasts, tides, pressure, solunar data, planning, and bait advice.

The top hierarchy is:

1. **Location:** validated `City, ST` or saved-spot name with area subtitle; coordinates are never the primary title.
2. **Current decision:** current bite rating, best upcoming window, selected species, temperature, wind, and pressure.
3. **Best Bait Today:** the current conditions-aware bait pick with transparent provenance.
4. **Interactive timeline:** hourly bite score and weather factors.
5. **Species list:** compact cards for other relevant species.
6. **Plan ahead:** expandable daily forecast and weekly trip planner.

The current Fishing score remains deterministic. AI explains and recommends; it does not fabricate the score.

### You

The You destination contains:

- Personal catch gallery and list
- Catch statistics and learned patterns
- Saved spots and groups
- Published-post management
- Bite alerts and notification settings
- Weather units and map preferences
- Community privacy, blocked users, and reporting history
- AI availability and data-source disclosures
- App settings and diagnostics

## Visual system

### Typography

- Use native rounded/sans-serif text styles for navigation, titles, body copy, buttons, cards, and explanations.
- Reserve monospaced digits for measurements where alignment matters: temperatures, pressure, times, lengths, weights, and chart callouts.
- Replace hard-coded 10–14 point prose with semantic styles such as `headline`, `body`, `callout`, `caption`, and `title2`.
- Preserve Dynamic Type and avoid scale factors that make labels unreadably small.

### Surfaces and hierarchy

- Use a restrained condition-aware background rather than the same static gradient on every screen.
- Keep primary content mostly unboxed; use spacing, dividers, and typography to form sections.
- Use real Liquid Glass for floating map controls, filters, the tab bar, selected chips, and the compact weather strip.
- Use opaque panels only when content needs legibility over a map or photo.
- Remove the global fade/scale transition currently applied to every scrolling card.
- Keep the `Ink` marine palette and score-band semantics, but use color as status and selection rather than decoration everywhere.

### Photography

- Personal and community catches use aspect-aware large imagery and fast thumbnails.
- Missing photos use a deliberate species illustration/icon treatment, not an empty placeholder.
- Generated lure artwork is visually secondary and labeled as generated.

## Location and units

Introduce a single `LocationDescriptor` value used by every screen:

```swift
struct LocationDescriptor: Equatable, Sendable {
    let city: String?
    let stateCode: String?
    let featureName: String?
    let displayName: String
    let subtitle: String?
}
```

The location builder trims whitespace, rejects coordinate-shaped MapKit names, composes `City, ST`, and falls back to a meaningful waterbody/feature name or `Current Location`. Saved-spot names remain the title; `City, ST` becomes their subtitle when available.

Introduce one unit/formatting layer shared by labels, cards, charts, catch snapshots, and accessibility:

- Temperatures display as rounded whole degrees.
- Chart plots retain unrounded values.
- Chart values and adjacent labels always use the same selected unit.
- Pressure, wind, visibility, length, and weight use explicit locale-aware precision.
- A unit appears in every chart detail even when axis labels are abbreviated.

## Interactive charts

Create a reusable hourly selection model from one captured `now` value. The same array powers the chart and its hourly cells so the two cannot drift at an hour boundary.

The primary forecast chart supports:

- Temperature, wind/gust, pressure, precipitation, and bite-score metrics
- Horizontal 12-hour viewport over 24–48 hours
- Tap and drag selection snapped to the nearest sample
- Selected-hour rule and point marks
- A pinned detail strip with time, condition, rounded temperature, precipitation, wind/gust, pressure, and bite interpretation
- Haptic feedback only when the selected hour changes
- Linked selection between chart and hourly cells
- Accessible chart descriptors and a non-visual data table

Tide selection uses the same interaction pattern and reports height, rising/falling/slack state, rate, and time until the next high/low. Bite-window bands expose reason, peak time, duration, and an alert action.

Daily rows show high/low, precipitation, wind peak, bite score, and best window. Selecting a day expands it or opens a detailed day plan.

## Bite scoring and Best Bait Today

### Existing intelligence

The bait recommendation uses Apple Foundation Models through `SystemLanguageModel.default` and `LanguageModelSession`. The specific underlying Apple model is not selectable by the app. The fishing score, solunar windows, personal tuning, and static bait profiles remain deterministic.

Replicate is not the bait decision engine. It is optional for generated lure artwork and a fish-photo fallback. Release builds must not ship long-lived Replicate or retailer credentials.

### New Best Bait behavior

Replace the current “AI Bait Engine” stack with one primary `Best Bait Today` card immediately below the current BiteTime decision.

For a selected species and live conditions, an eligible device generates one recommendation per context key. The key includes species, active location, weather generation, tide generation, and a coarse time bucket. A stale recommendation is never silently reused after its inputs change.

The card shows:

- Bait and color
- Technique and depth
- A concise reason tied to named conditions
- `On-device Apple Intelligence` and generation time
- `Why this pick`, `Refresh`, and `More advice`

The current model-authored percentage must not be presented as calibrated probability. Use `Model estimate` only if retained, or remove the percentage entirely.

If Apple Intelligence is unavailable or generation fails, show a deterministic `BaitProfile` starting point labeled **General species guidance — not adjusted for today**. Selecting “All species” asks the user to choose a species before claiming a best bait.

Generation prioritizes the structured bait response. The longer daily report, tutorials, shopping, Q&A, and optional artwork live behind `More advice` so failures there cannot block the bait pick.

## Resilient weather architecture

WeatherKit remains the preferred provider, but view models no longer expose WeatherKit types directly. Introduce provider-neutral current, hourly, daily, alert, wind, pressure, and astronomy values.

```swift
protocol WeatherProvider: Sendable {
    func forecast(for location: CLLocation) async throws -> WeatherSnapshot
}
```

Provider order for the initial US-focused release:

1. WeatherKit
2. National Weather Service API for supported US points
3. The last matching on-device snapshot

The NWS adapter uses `/points`, the discovered hourly/grid forecast, the nearest observation station, and active alerts. It sends the required identifying User-Agent, respects cache metadata and rate limits, and clearly labels NWS data. NWS is open government data and does not add a paid dependency. Open-Meteo is not the default shipping fallback because its free endpoint is non-commercial; it may be added later only with compliant attribution and a suitable commercial plan.

Astronomy is a separate input rather than an accidental WeatherKit dependency. Use WeatherKit astronomy when available, then a locally computed ephemeris for sunrise, sunset, moon phase, moonrise, moonset, and transit inputs. The local calculator must use a documented algorithm, remain deterministic, and be validated against fixed location/date fixtures before it may drive bite windows. A missing astronomy field reduces the score with an explicit confidence/factor omission; it never invents a solunar event.

Each visible forecast names its source and freshness. Provider fallback is automatic, but partial data is explicit: for example, NWS may provide weather while a separate tide service supplies marine timing. The app never labels an authentication error as merely “offline.”

## Local catch data and migration

The existing JSON catch file and local photo directory remain the durable private source of truth during the redesign. The repository gains an interface so storage can evolve without binding views to file I/O:

```swift
protocol CatchRepository {
    var catches: [CatchEntry] { get }
    func save(_ draft: CatchDraft, photo: UIImage?) async throws -> CatchEntry
    func update(_ catch: CatchEntry) async throws
    func delete(_ catch: CatchEntry) async throws
}
```

`CatchEntry` gains optional schema fields for privacy, publication state, waterbody, display location, photo metadata, and source/version. Decoding remains backward-compatible. Existing catches and photos are backed up before any migration, and one malformed record never destroys the rest.

A public `CatchPost` is a copy derived from a private catch. Its CloudKit record ID is stored locally. Editing or deleting a public post never deletes the private catch. Deleting a private catch with a live publication requires a clear choice between unpublishing and keeping the public post.

## CloudKit community architecture

Use a dedicated iCloud container with the public database for shared content and private/local storage for drafts and user-owned settings.

Initial public record types:

- `PublicProfile`
- `FollowRelationship`
- `CatchPost`
- `Comment`
- `Reaction`
- `Group`
- `GroupMembership`
- `SavedPost`
- `Report`
- `BlockRelationship`

Catch photos use `CKAsset`. Public writes require an iCloud account; signed-out users can still browse cached and publicly readable content when CloudKit permits.

The app uses query subscriptions for relevant comment/reaction notifications rather than a public database subscription. Feed pages are cursor-based, cached locally, and deduplicated by record ID. Optimistic likes/comments roll back visibly when CloudKit rejects a write.

### Privacy defaults

- Publication is always opt-in per catch.
- Exact coordinates default to private.
- Published location defaults to a waterbody or coarse area, with coordinate jitter/rounding sufficient to prevent exposing a precise spot.
- Users can publish without length, weight, bait, or conditions.
- Photos are stripped of embedded metadata before upload.
- Blocked profiles disappear from feeds, comments, and notifications.
- Users can delete their posts, comments, reactions, profile, and cached community data.

### Safety and moderation

- Every post, comment, profile, and group exposes Report and Block.
- Client-side validation limits text length, file size, and unsupported content types.
- A report record captures category and target ID, not a duplicate of private user content.
- Reported content can be hidden locally immediately.
- Administrative review and removal use CloudKit Dashboard roles and documented moderation procedures.
- Community launches only after Terms, Privacy Policy, Community Guidelines, support contact, and account/content deletion flows exist.

## Error and offline behavior

- Local catch logging, personal feed, cached BiteTime, saved spots, regulations, and deterministic bait guidance remain available offline.
- Map and community surfaces show cached results with freshness indicators.
- Weather errors distinguish authentication, provider outage, unsupported region, rate limit, no network, and stale cache.
- CloudKit errors distinguish signed-out, restricted account, quota, conflict, moderation rejection, and temporary network failure.
- Failed public uploads remain private drafts with a retry action.
- Image operations are cancellable and bounded in size.
- All async stores use request identity so stale location/species/feed responses cannot overwrite newer state.

## Debugging and quality plan

Before and after every phase:

- Build Debug and Release for simulator and generic iOS device.
- Run all unit and UI tests from a clean DerivedData directory.
- Verify signed device entitlements and provisioning profiles for WeatherKit, iCloud/CloudKit, notifications, and required privacy strings.
- Exercise real-device WeatherKit and NWS fallback paths.
- Test offline launch, airplane-mode recovery, stale cache, provider switching, and partial responses.
- Validate map layers with empty, malformed, duplicate, nonfinite, and out-of-range coordinates.
- Test old catch JSON migration, corrupt entries, missing photos, large photos, and low-storage failures.
- Test CloudKit signed-in/signed-out states, duplicate writes, conflicts, pagination, deletion, report/block, and upload retry.
- Run accessibility checks for Dynamic Type, VoiceOver, Reduce Motion, contrast, chart descriptions, and touch targets.
- Capture UI screenshots for all five destinations, empty/loading/error/offline states, chart selection, catch composer, post detail, and publication privacy.
- Verify Release bundles contain no long-lived service tokens or debug fixtures.
- Keep `main` clean and verify local `main`, `origin/main`, and GitHub `main` match after each completed phase.

System-framework console noise is not treated as an app defect unless correlated with an observable failure. Known PointerUI, PerfPowerTelemetry, MapKit PPS, transient zero-size Metal, and keyboard-scene messages are filtered during diagnosis; WeatherKit JWT failures, app crashes, hangs, stale data, blank visible rendering, and lost user data remain blocking.

## Delivery decomposition

### Phase 1 — Core product and BiteTime

- Provider-neutral weather model and NWS fallback
- Location descriptor and consistent unit formatting
- New typography and surface system
- Five-destination navigation shell with central Log Catch action
- BiteTime hero, interactive charts, daily expansion, and Best Bait Today
- Existing features rehomed without data loss
- Focused unit/UI tests and device verification

### Phase 2 — Map and private catches

- Full-screen map with layers, filters, clusters, and bottom sheet
- Photo-forward catch composer and personal catch cards
- Safe catch schema migration and repository boundary
- Personal heatmap, statistics, patterns, alerts, and saved content
- Offline behavior and data-integrity tests

### Phase 3 — Community

- CloudKit container, schema, repository, caching, and pagination
- Public profiles, feeds, optional publishing, comments, reactions, saves, and sharing
- Groups and memberships
- Notifications, report, block, privacy, deletion, and moderation operations
- Signed-out, conflict, failure, and abuse-path testing

### Phase 4 — Full hardening and release readiness

- Cross-feature race/cancellation audit
- Performance, memory, photo, map, and network profiling
- Accessibility and localization audit
- Real-device matrix and regression suite
- Release entitlement, privacy, secret-boundary, and archive checks
- Final independent code review before integration to `main`

Each phase receives its own implementation plan and verification checkpoint. A later phase may not weaken the local/private guarantees established by an earlier phase.

## Acceptance criteria

The redesign is complete when:

- The app opens into the five-destination structure and no feature is stranded in an inaccessible old tab.
- Visible locations use saved-spot names or `City, ST`, never raw coordinates as the primary label.
- All displayed temperatures are rounded consistently and chart units match adjacent labels.
- Hourly weather, tide, pressure, and bite charts support tap/drag detail and accessible inspection.
- Best Bait Today appears prominently, identifies Apple on-device AI, invalidates stale context, and has an honest deterministic fallback.
- WeatherKit failure automatically falls back to NWS for supported US locations and then to a labeled cache.
- A catch can be logged with a photo in seconds and remains safe offline.
- Publishing is optional, exact location is private by default, and public deletion does not erase private history.
- Community supports feeds, profiles, comments, reactions, groups, sharing, reporting, blocking, and content/account deletion.
- The map supports useful local and community layers without claiming unavailable proprietary data.
- Debug and Release builds, automated tests, real-device smoke tests, accessibility checks, and secret/entitlement audits pass.

## Explicit non-goals for this delivery

- Copying another app’s branding, proprietary map overlays, catch database, or scoring model
- Live chat or direct messaging
- Marketplace transactions between users
- Paid subscriptions or in-app purchases
- Android or web clients
- Server-side generative AI for bait decisions
- Precise public catch coordinates by default

These can be designed separately after the complete iOS product is stable.
