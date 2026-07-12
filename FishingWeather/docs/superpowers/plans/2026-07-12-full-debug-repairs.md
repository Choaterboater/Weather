# Full Debug Repairs Plan

> **For Codex:** Use TDD. Add each regression test first, confirm it fails for the current behavior, then make the smallest production change and rerun the targeted test before the full suite.

**Goal:** complete the full debug pass, fix confirmed issues, commit on `main`, and push `origin/main`.

## Confirmed Finding

`YouTubeClient` tries to fall back from `high` to `default` thumbnails, but its decoding model requires `high` to exist. A valid YouTube search response that only contains `default` thumbnails throws during decoding before the fallback can run.

The full UI test can launch behind the real location permission gate, so the tab walk fails before reaching the main surface. The app needs a DEBUG-only automation fixture and the UI test must opt into it explicitly.

## Implementation Steps

- [x] Add `YouTubeClientTests` with a regression fixture that omits the `high` thumbnail and expects one decoded `YouTubeVideo` with the `default` thumbnail URL.
- [x] Run the targeted test and confirm it fails against the existing decoder.
- [x] Extract/adjust YouTube search response decoding so `high`, `medium`, and `default` thumbnails are optional and fallback order is `high`, `medium`, then `default`.
- [x] Rerun the targeted test and confirm it passes.
- [x] Add `-uiTesting` launch coverage to the tab-walk UI test.
- [x] Add a DEBUG-only `LocationManager` fixture for UI testing and guard delegate callbacks from overwriting it.
- [x] Rerun the focused UI test and confirm it passes.
- [x] Run project generation/build/test verification.
- [ ] Request code review, address actionable feedback if any, then commit and push `main`.
