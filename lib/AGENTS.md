# lib/ — Dart source tree

## Purpose

Owns the entire Flutter / Dart codebase for the Nudge app: app entry point, brand styling, screens, data layer, and cross-cutting services. Everything user-facing lives here.

## Ownership

- Owns: `lib/main.dart` (entry, `AppColors`, `SmartReminderApp`), all subdirectories.
- Does **not** own: native Java (see `android/AGENTS.md`), build artifacts (`build/`, `.dart_tool/`).
- If you add a new top-level Dart folder, add a new entry to the Child DOX Index below.

## Local Contracts

- **Brand palette lives in `lib/main.dart`.** It is the single source of truth for `AppColors` (dark) and `AppColorsLight` (light) constants, plus the brightness-aware `NudgePalette` picker, plus the `ThemeData` used by every screen. The accent purple is the same in both palettes. **From screens, always use `context.palette` (the `NudgePaletteContext` extension)** — never hard-code `AppColors.X` or `AppColorsLight.X`, and never write a `Theme.of(context).brightness == Brightness.dark ? … : …` ternary. Example:
  ```dart
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(color: p.surface, child: Text('hi', style: TextStyle(color: p.textPrimary)));
  }
  ```
  Direct `AppColors` / `AppColorsLight` reads are allowed only inside the `_buildNudgeTheme` builder in `main.dart` (where we are *constructing* the palettes). New themed components go inside that helper so both palettes stay in sync.
- **Theme mode is `ThemeMode.system`.** `MaterialApp` ships both `theme` (light) and `darkTheme` (dark) and follows the OS setting. The first frame already uses the correct palette — no flash of unstyled content.
- **MethodChannel name constants** must match the Java side exactly. Two channels:
  - `com.nudge.app/rules` — `syncRules` (Dart → Java), `testRule` (Dart → Java).
  - `com.nudge.app/import` — `pickFile` (Dart → Java, returns file contents).
  Keep the Dart string and the Java `CHANNEL_NAME` in lock-step; one source of truth in each language, mirror, never drift.
- **Onboarding gate** uses `kFirstRunCompleteKey` in `SharedPreferences`. `lib/main.dart` reads it during boot and `lib/screens/onboarding_screen.dart` writes `true` when the user finishes. Do not gate onboarding on anything else.
- **Hive boxes open lazily** through `initRulesHive()` / `initProfilesHive()` / `initExportHistory()` exported from the matching `*_hive_provider.dart`. Never open a Hive box from a screen directly.

## Work Guidance

- **Material 3 dark theme** is enforced globally. New screens inherit it; do not wrap with `Theme.of(context).copyWith` unless intentionally overriding.
- **No new top-level dependencies** without first checking for an existing `lib/services/` helper that does the same job, and verifying the dependency still supports Dart 3.12.
- **Files of any meaningful change** must also update the closest child `AGENTS.md` (sibling boundary).
- All new screens receive their `RulesHiveProvider` / `ProfileHiveProvider` / `ExportHistoryProvider` via constructor injection from `main.dart` so tests can substitute fakes.

## Verification

- `flutter analyze` from the repo root must report "No issues found!" before merging.
- `flutter build apk --release` must succeed; `app-release.apk` is the sideload artifact.

## Child DOX Index

- `lib/screens/AGENTS.md` — UI screens; entry points for user flows; `MethodChannel` call sites.
- `lib/src/AGENTS.md` — Data layer (Hive boxes, `Rule`, `Profile`, providers, legacy migration).
- `lib/services/AGENTS.md` — Cross-cutting services (logger, permissions, export, backup).