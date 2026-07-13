# BiteCast Deep Debug Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the reproducible runtime races, location-access lockout, release credential exposure, App Store privacy-manifest gap, resource-identity defects, and false-positive UI coverage found by the second full debug pass.

**Architecture:** Keep network and system frameworks behind the existing observable services, but add request identity/provenance at every async boundary before state is committed. Keep secret-backed integrations available for local Debug builds while using a separate Release plist that cannot embed long-lived credentials. Add pure/internal seams only where needed to prove cache identity, provenance, and parsing behavior under Swift Testing.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, Observation, CoreLocation/MapKit, XcodeGen, Swift Testing, XCTest UI tests.

## Global Constraints

- Keep the deployment target at iOS 26.5 and Swift language mode at 6.0.
- Preserve the existing `BiteCast` bundle identifier and XcodeGen project workflow.
- Long-lived Amazon, eBay, and Replicate credentials may be present only in Debug build resources; Release must not contain their plist keys or sentinel values.
- Every production-code bug fix gets a regression test that is observed failing before the fix and passing after it.
- Preserve the DEBUG-only `-uiTesting` location fixture and all existing persisted user data behavior outside UI tests.

---

### Task 1: Release secrets, privacy manifest, and build documentation

**Files:**
- Create: `Sources/Support/Info-Debug.plist`
- Create: `Sources/Support/PrivacyInfo.xcprivacy`
- Modify: `Sources/Support/Info.plist`
- Modify: `project.yml`
- Modify: `README.md`

**Interfaces:**
- Consumes: the existing `AppConfig.xcconfig` optional include of local `Secrets.xcconfig`.
- Produces: Debug builds use `Info-Debug.plist`; Release builds use credential-free `Info.plist`; both bundle `PrivacyInfo.xcprivacy`.

- [x] **Step 1: Reproduce Release credential embedding**

Run a Release simulator build with `AMAZON_SECRET_KEY`, `EBAY_CLIENT_SECRET`, and `REPLICATE_API_TOKEN` set to `AUDIT_SENTINEL`, then inspect the built plist without printing real local values. Expected before the fix: at least one sentinel is present.

- [x] **Step 2: Split Debug and Release plists**

Copy the current plist structure to `Info-Debug.plist`. Remove `AmazonAccessKey`, `AmazonSecretKey`, `EbayClientID`, `EbayClientSecret`, and `ReplicateAPIToken` from the Release `Info.plist`; retain public affiliate identifiers/templates and the bundle-restricted YouTube key placeholders. Configure XcodeGen as follows:

```yaml
configFiles:
  Debug: AppConfig.xcconfig
settings:
  base:
    INFOPLIST_FILE: Sources/Support/Info.plist
  configs:
    Debug:
      INFOPLIST_FILE: Sources/Support/Info-Debug.plist
```

- [x] **Step 3: Add the required-reason privacy manifest**

Create a valid plist containing these exact entries:

```xml
<key>NSPrivacyAccessedAPITypes</key>
<array>
  <dict>
    <key>NSPrivacyAccessedAPIType</key>
    <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
    <key>NSPrivacyAccessedAPITypeReasons</key>
    <array><string>CA92.1</string></array>
  </dict>
  <dict>
    <key>NSPrivacyAccessedAPIType</key>
    <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
    <key>NSPrivacyAccessedAPITypeReasons</key>
    <array><string>C617.1</string></array>
  </dict>
</array>
```

- [x] **Step 4: Correct the build README**

Document `BiteCast.xcodeproj`, iOS 26.5, Swift 6.0, `app.choatelabs.bitecast`, and `Sources/Support/BiteCast.entitlements`. State that long-lived service secrets are Debug-only and production use requires a server-side proxy/token broker.

- [x] **Step 5: Verify the build resources**

Run `plutil -lint` on both info plists and the privacy manifest, regenerate the project, build Debug and Release, verify the privacy manifest is at the app-bundle root, and verify the Release Info.plist contains none of the three sentinel values and none of the five long-lived credential keys.

---

### Task 2: Location-denial access and reverse-geocode freshness

**Files:**
- Create: `Tests/LocationStateTests.swift`
- Modify: `Sources/Views/RootView.swift`
- Modify: `Sources/Services/LocationManager.swift`

**Interfaces:**
- Produces: `RootView.canEnterMainContent(status:hasSavedSpots:) -> Bool` and `LocationManager.isCurrentGeocode(_:current:) -> Bool` as internal pure test seams.

- [x] **Step 1: Write failing access-policy and geocode-identity tests**

```swift
@Test func deniedLocationStillEntersWhenSavedSpotsExist() {
    #expect(RootView.canEnterMainContent(status: .denied, hasSavedSpots: true))
    #expect(!RootView.canEnterMainContent(status: .denied, hasSavedSpots: false))
}

@Test func onlyTheCurrentCoordinateMayApplyAGeocodeResult() {
    let a = CLLocationCoordinate2D(latitude: 27.1, longitude: -82.1)
    let b = CLLocation(latitude: 28.1, longitude: -83.1)
    #expect(!LocationManager.isCurrentGeocode(a, current: b))
    #expect(LocationManager.isCurrentGeocode(b.coordinate, current: b))
}
```

- [x] **Step 2: Run the targeted tests and verify RED**

Expected: compile failure because both internal seams do not exist.

- [x] **Step 3: Implement saved-spot access**

Use `!spots.spots.isEmpty`, not `selectedSpot != nil`, when authorization is denied/restricted so the Spots tab remains reachable and the user can select a saved location.

- [x] **Step 4: Make reverse geocoding latest-request-wins**

Store and cancel a `geocodeTask`, clear `placeName` and `administrativeArea` immediately when accepting a new coordinate, and after awaiting MapKit apply labels only when the task is not cancelled and `isCurrentGeocode(requested,current:)` is true. Failed lookups must leave labels nil rather than retaining the prior coordinate's labels.

- [x] **Step 5: Run the targeted tests and verify GREEN**

Expected: both location-state tests pass.

---

### Task 3: Fish-recognition completion and photo-selection ordering

**Files:**
- Modify: `Tests/FishRecognizerTests.swift`
- Modify: `Sources/Services/FishRecognizer.swift`
- Modify: `Sources/Views/LogCatchView.swift`
- Modify: `Sources/Views/ScoutView.swift`

**Interfaces:**
- Produces: `FishRecognizer.identify(image:) async` does not return until the active recognition task has committed a terminal state; an internal async worker seam accepts encoded image data for deterministic tests.

- [x] **Step 1: Write the failing completion test**

Create a recognizer with a delayed test worker returning a known `FishIdentification`, call `await identify(image:)`, then assert `status == .ready` and `result == expected`. Expected before the fix: the API/seam is missing or `identify` returns while status remains `.working`.

- [x] **Step 2: Run the targeted test and verify RED**

Run only `FishRecognizerTests`; confirm the failure is the early-return behavior or missing seam.

- [x] **Step 3: Await the owned recognition task**

Keep cancellation ownership in `FishRecognizer`, but assign the detached operation to a local `activeTask`, store it in `task`, and `await activeTask.value` before returning. The optional internal worker must execute inside that same task and use the same cancellation checks as Core ML/Replicate.

- [x] **Step 4: Make PhotosPicker loads latest-selection-wins**

Replace each untracked `.onChange` transfer task with `.task(id: pickerItem)`. Capture the selected item, await its data, then guard `!Task.isCancelled` and that the current selection still equals the captured item before mutating `photo`/`image` or starting analysis.

- [x] **Step 5: Run the targeted tests and verify GREEN**

Expected: fish-recognition tests pass and the species assignment after `await recognizer.identify` observes the completed result.

---

### Task 4: Tide provenance, trip-planner request identity, and AI reset

**Files:**
- Create: `Tests/AsyncStateIdentityTests.swift`
- Modify: `Sources/Services/TideService.swift`
- Modify: `Sources/Views/LogCatchView.swift`
- Modify: `Sources/Services/TripForecastLoader.swift`
- Modify: `Sources/Views/TripPlannerView.swift`
- Modify: `Sources/Services/BaitEngine.swift`

**Interfaces:**
- Produces: `TideService.hasData(for:on:)`, `LogCatchView.tidePhase(events:hasMatchingData:now:)`, and `TripForecastLoader.requestKey(location:species:locationName:)`.

- [x] **Step 1: Write failing identity/provenance tests**

Test that a mismatched-tide flag always yields nil, that two location names at the same coordinate produce different trip request keys, and that two rounded coordinates produce different tide keys. Expected before the fix: the helpers are absent and the trip keys cannot distinguish names.

- [x] **Step 2: Run the targeted tests and verify RED**

Expected: compile failure for the missing interfaces.

- [x] **Step 3: Guard tide snapshots by loaded request identity**

Expose a read-only match against `lastKey` using the same location/date key as `load`. In `LogCatchView`, require an active location and matching tide data before deriving `Slack`, `Rising`, or `Falling` through the pure helper.

- [x] **Step 4: Make trip loads latest-request-wins**

Include `locationName` in the request key and the view's `.task(id:)`. Increment a `loadID` before every request, clear the prior outlook when the key changes, and guard the ID before every success/error state write so A cannot overwrite B or remain visible while B loads.

- [x] **Step 5: Invalidate in-flight Q&A on reset**

Capture `generateID` at the start of `ask`. Append answers/errors and clear `isAnswering` only if the captured generation is still current. `reset()` must set `isAnswering = false` after incrementing the generation.

- [x] **Step 6: Run the targeted tests and verify GREEN**

Expected: async identity tests pass.

---

### Task 5: OpenStreetMap identity and bundled-resource coverage

**Files:**
- Create: `Tests/OpenStreetMapClientTests.swift`
- Modify: `Tests/CuratedSpotIDTests.swift`
- Modify: `Sources/Services/OpenStreetMapClient.swift`

**Interfaces:**
- Produces: `RampPin.id: String` namespaced as `<osm-type>/<numeric-id>` and `OpenStreetMapClient.pins(from:) throws -> [RampPin]` for parser tests.

- [x] **Step 1: Write failing duplicate-ID and resource tests**

Decode an Overpass fixture containing `node` id 42 and `way` id 42 and expect two distinct `RampPin.id` values. Instantiate `CuratedSpotCatalog` and expect exactly 12 spots including `Grayton Beach Surf`.

- [x] **Step 2: Run targeted tests and verify RED**

Expected: parser seam is missing and numeric IDs collide; the resource test must prove target membership.

- [x] **Step 3: Namespace OSM IDs and expose the pure parser**

Build `RampPin(id: "\(type)/\(id)", ...)` and route production fetch decoding through `pins(from:)`.

- [x] **Step 4: Run targeted tests and verify GREEN**

Expected: both node/way pins survive with distinct identities and the bundled catalog test sees all 12 spots.

---

### Task 6: Honest, deterministic UI coverage

**Files:**
- Modify: `UITests/GlassPassUITests.swift`

**Interfaces:**
- Consumes: `-uiTesting` location fixture and launch-argument UserDefaults overrides.
- Produces: UI failures when Planner, map, satellite mode, or species detail cannot be reached.

- [x] **Step 1: Strengthen assertions and verify current failure**

Launch with deterministic `selectedTab=weather` and `spotMapStyle=standard` overrides. Locate Planner by its visible static text/navigation link representation, require it to exist, require the map and Satellite control, and require Bass detail plus its marker. Run the UI test and confirm any unreachable advertised screen fails instead of silently skipping.

- [x] **Step 2: Fix accessibility lookup only where the failing hierarchy proves it necessary**

Use stable accessibility identifiers/labels on the production controls only if visible labels are ambiguous. Do not add sleep-only fixes.

- [x] **Step 3: Run the focused UI test and verify GREEN**

Expected: all required screens are reached and the test passes without conditional skips.

---

### Task 7: Whole-project verification, review, and GitHub main

**Files:**
- Modify: this plan's checkboxes only as work is completed.

- [x] **Step 1: Run static validation**

Run XcodeGen, `plutil -lint` for all plists/entitlements/privacy manifests, `jq empty` for bundled JSON, and `git diff --check`.

- [x] **Step 2: Run the complete test suite from a clean DerivedData path**

```bash
xcodebuild test -project BiteCast.xcodeproj -scheme BiteCast \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/gofish-deep-debug-final
```

Expected: `** TEST SUCCEEDED **`, all Swift tests pass, and the required UI walk passes.

- [x] **Step 3: Request whole-diff code review**

Address every Critical/Important finding, rerun covering tests, and repeat review until clean.

- [ ] **Step 4: Commit and push intentionally**

Stage only the files in this plan, commit on the explicitly authorized `main`, push `origin/main`, fetch, and verify `main`, `origin/main`, and `git ls-remote origin main` resolve to the same commit with a clean worktree.
