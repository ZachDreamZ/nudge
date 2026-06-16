# lib/services/ — Cross-cutting services

## Purpose

Side-effect-heavy helpers that screens and the data layer call into: structured logging, runtime permission UX, JSON export / import, and the export-history provider used by the Settings screen.

## Ownership

- Owns: every file in `lib/services/`.
- Does **not** own: any Hive box or data model (see `lib/src/AGENTS.md`), any UI screen (see `lib/screens/AGENTS.md`).

## Local Contracts

- **Static utility classes only.** All services in this folder are static-only (`AppLogger`, `PermissionService`, `RuleBackupService`, `ExportHistoryService`) or are constructed once in `main.dart` and injected (`ExportHistoryProvider`). No service should be instantiated in a screen.
- **Logging goes through `AppLogger` (`d` / `w` / `e` / `i`).** Never use `print` or `debugPrint` in feature code. `AppLogger` strips timestamps in release builds for readability.
- **Permissions are gated by `PermissionService` with the "Triple-Ask" pattern:**
  1. `checkAndRequestInitial()` once on first launch — requests **only** `POST_NOTIFICATIONS`. Location is intentionally deferred so a brand-new user is not slammed with two dialogs before they have seen the app.
  2. `ensurePermissionBeforeSaving(context)` before any save that would create a notification.
  3. `requestWifiPermissions()` is invoked from `add_rule_screen.dart` (and from any future Wi-Fi rule edit flow) so a battery-only user never sees the location prompt. The call returns the raw [PermissionStatus] so the caller can decide whether to follow up with a dialog.
  Do not call `Permission.notification.request()` or `Permission.locationWhenInUse.request()` from anywhere else — every permission dialog must flow through `PermissionService` so the rationale copy stays consistent.
  - **System status snapshots** (`PermissionStatusSnapshot`): `PermissionService.notificationStatus()` and `PermissionService.batteryOptimizationStatus()` are the single source of truth for the Settings screen's `SYSTEM STATUS` tiles. The Settings screen re-reads them on `AppLifecycleState.resumed` so the tile reflects the post-OS-settings state without a manual pull-to-refresh.
  - `PermissionService.openBatteryOptimizationSettings()` deep-links the user to the OS battery-optimization page; the tile in `settings_screen.dart` calls it on tap.
- **Backup format is versioned JSON** — top-level keys `app: "Nudge"`, `formatVersion: 1`, `exportedAt`, `ruleCount`, `rules`. `RuleBackupService.importFromJson` is the single source of truth for parsing / dedup; the native file-picker code in `MainActivity.java` only returns the file contents as a string.
- **Export history** lives in its own Hive box (`export_history`) and is the only place that tracks when the user last shared a backup. New fields on `ExportRecord` must default safely in `fromJson`.

## Work Guidance

- **Adding a new service.** Keep it static-only, expose a clear async API, and document it in this file. Update the Child DOX Index if you split it into a sub-folder.
- **No `BuildContext` references in services** unless the service is permission-related (`PermissionService.ensurePermissionBeforeSaving`). Other helpers stay UI-free.
- **Do not duplicate permission prompts.** A user-visible notification dialog belongs in the screen; the system permission dialog must be initiated by `PermissionService`.

## Verification

- `flutter analyze` from repo root must be clean.
- After changing a service, walk the dependent screens manually on a connected device.

## Child DOX Index

No further child docs; this folder is flat by design.