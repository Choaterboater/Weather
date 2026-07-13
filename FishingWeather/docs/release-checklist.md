# BiteCast Release Checklist

## Owner legal review — blocks App Store submission

The bundled Privacy Notice and Terms are an owner-authored draft suitable for local and signed-device testing. They are not represented as legal approval. Before any App Store submission, the owner must review and explicitly approve:

- [ ] The correct owner or legal-entity name to publish.
- [ ] The July 13, 2026 effective date, or a replacement launch date.
- [ ] Any governing-law, jurisdiction, warranty, and liability language advised for the owner.
- [ ] Public Privacy Policy, Terms, and Support URLs that remain reachable outside the app.
- [ ] App Store Connect privacy answers, age rating, support URL, marketing text, and review notes.
- [ ] Affiliate relationships and every externally configured service used by the Release build.

Do not infer approval from a successful build, archive, device install, or test run.

## Engineering release gate

- [ ] Clean Xcode project generation and support-file lint pass.
- [ ] Full unit and UI suites pass on the release simulator target.
- [ ] Debug simulator, Debug device, Release device, and archive builds pass.
- [ ] Release app contains no Debug fixtures, long-lived credentials, or unsafe species media.
- [ ] WeatherKit entitlement, attribution, temporary retention, and fallback behavior are verified.
- [ ] Catch-file protection and signed in-place upgrade are verified on the physical device.
- [ ] Normal and Accessibility XXXL smoke passes cover the four main destinations and legal center.
- [ ] Local `main`, `origin/main`, and GitHub `main` resolve to the exact verified commit.
