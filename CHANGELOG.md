# Changelog

All notable changes to this project are documented in this file. Dates are in YYYY-MM-DD format. The project follows [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-06-16

### Added

- Battery and Wi-Fi rule triggers. A rule fires when the configured comparison against the current system value is true.
- Standard and Urgent alarm alert tones. Urgent routes through a dedicated high-importance notification channel with a custom alarm ringtone.
- Per-rule quiet hours with a half-open `[start, end)` window that wraps midnight cleanly.
- Multiple profiles. The default "Personal" profile is created on first launch; the user can add, rename, and delete profiles from the Profiles screen.
- 15-minute background worker (`RuleWorker`) that re-evaluates every active rule and persists the updated `lastFired` timestamps.
- "Test all rules now" action in Settings that enqueues a one-time worker run via WorkManager, bypassing the periodic schedule.
- Backup and restore via the Android Storage Access Framework. Exported files are JSON, share a schema, and skip duplicates on import.
- Export history that records the last 20 exports with their file name, size, rule count, and timestamp.
- Recent activity screen that shows the rules that have fired, reverse-chronological.
- Onboarding carousel that walks new users through the rule model, the alert types, the profiles feature, and a "Choose Your Sound" frame.
- "Delete all data" action in Settings that requires the user to type the word `DELETE` to confirm.
- 10 unit tests covering quiet-hours edge cases, JSON round-trips, and `AlertType` normalization.

### Changed

- Notification permission prompt moved to first launch only. Location permission is now deferred until the user creates a Wi-Fi rule.
- The Settings screen has a dedicated "System Status" section with a live-updating "Notification access" and "Battery optimization" tile that deep-link into the OS settings page.
- `AppLogger` now compiles out `d`/`w`/`e` calls in release builds so logcat stays clean in shipped apps.

### Fixed

- Broadcast receivers that previously fired duplicate notifications due to being registered both statically in the manifest and dynamically in `MainActivity.onCreate`. The static declarations were removed; the dynamic registration is the single source of truth.
- `RuleWorker.isInQuietHours` was not applied to Wi-Fi rules; the gate now covers both battery and Wi-Fi evaluators.
- `duplicateRule` was not copying the source rule's quiet-hours window. The copy now carries `quietStartMinutes` and `quietEndMinutes` across.
- Hive read methods (`getAllRules`, `getAllRulesWithKeys`, `getRule`) and the mutation methods (`updateLastFired`, `toggleEnabled`, `updateRule`, `duplicateRule`) all now tolerate a single corrupt JSON entry: they log a warning and skip / return false instead of throwing an unhandled `FormatException`.
- `MainActivity.handleSyncRules`, `handleTestRule`, and `getStoredRulesJson` were logging user data (raw rules JSON, reminder text) to logcat in release builds. They now log the size only with a redaction note.

### Security

- All logcat output is now free of user-typed rule text, SSIDs, and full rules JSON in release builds. The "no telemetry" promise is now actually honored.

### Known limitations

- The Recent activity view is backed by the per-rule `lastFired` timestamp, not a dedicated per-firing history. A user who fires the same rule many times in a day will see it once.
- Battery-only rules do not require location; Wi-Fi rules do (Android 8.0+ requirement). The two are intentional and documented in the privacy policy.
- The Dart side has not yet been split into feature modules. The repo is organised by layer (screens, src, services) rather than by feature; a future refactor can introduce per-feature folders without breaking the public Dart API.

## [0.1.0] - 2025-12-08

### Added

- Initial proof-of-concept: a single battery rule, no profiles, no quiet hours, no UI theming. The worker ran every 15 minutes via WorkManager and posted a hardcoded notification on each fire.