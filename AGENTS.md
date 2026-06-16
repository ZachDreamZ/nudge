# DOX framework

- DOX is highly performant AGENTS.md hierarchy installed here
- Agent must follow DOX instructions across any edits

## Core Contract

- AGENTS.md files are binding work contracts for their subtrees
- Work products, source materials, instructions, records, assets, and durable docs must stay understandable from the nearest applicable AGENTS.md plus every parent AGENTS.md above it

## Read Before Editing

1. Read the root AGENTS.md
2. Identify every file or folder you expect to touch
3. Walk from the repository root to each target path
4. Read every AGENTS.md found along each route
5. If a parent AGENTS.md lists a child AGENTS.md whose scope contains the path, read that child and continue from there
6. Use the nearest AGENTS.md as the local contract and parent docs for repo-wide rules
7. If docs conflict, the closer doc controls local work details, but no child doc may weaken DOX

Do not rely on memory. Re-read the applicable DOX chain in the current session before editing.

## Update After Editing

Every meaningful change requires a DOX pass before the task is done.

Update the closest owning AGENTS.md when a change affects:

- purpose, scope, ownership, or responsibilities
- durable structure, contracts, workflows, or operating rules
- required inputs, outputs, permissions, constraints, side effects, or artifacts
- user preferences about behavior, communication, process, organization, or quality
- AGENTS.md creation, deletion, move, rename, or index contents

Update parent docs when parent-level structure, ownership, workflow, or child index changes. Update child docs when parent changes alter local rules. Remove stale or contradictory text immediately. Small edits that do not change behavior or contracts may leave docs unchanged, but the DOX pass still must happen.

## Hierarchy

- Root AGENTS.md is the DOX rail: project-wide instructions, global preferences, durable workflow rules, and the top-level Child DOX Index
- Child AGENTS.md files own domain-specific instructions and their own Child DOX Index
- Each parent explains what its direct children cover and what stays owned by the parent
- The closer a doc is to the work, the more specific and practical it must be

## Child Doc Shape

- Create a child AGENTS.md when a folder becomes a durable boundary with its own purpose, rules, responsibilities, workflow, materials, or quality standards
- Work Guidance must reflect the current standards of the project or user instructions; if there are no specific standards or instructions yet, leave it empty
- Verification must reflect an existing check; if no verification framework exists yet, leave it empty and update it when one exists

Default section order:
- Purpose
- Ownership
- Local Contracts
- Work Guidance
- Verification
- Child DOX Index

## Style

- Keep docs concise, current, and operational
- Document stable contracts, not diary entries
- Put broad rules in parent docs and concrete details in child docs
- Prefer direct bullets with explicit names
- Do not duplicate rules across many files unless each scope needs a local version
- Delete stale notes instead of explaining history
- Trim obvious statements, repeated rules, misplaced detail, and warnings for risks that no longer exist

## Closeout

1. Re-check changed paths against the DOX chain
2. Update nearest owning docs and any affected parents or children
3. Refresh every affected Child DOX Index
4. Remove stale or contradictory text
5. Run existing verification when relevant
6. Report any docs intentionally left unchanged and why

## User Preferences

- **DOX is the source of truth for project context.** Future sessions must read the root `AGENTS.md` plus every AGENTS.md on the path to any file they will touch, in that order, before editing. The hierarchy is the only durable, token-efficient way to recover project state — never re-derive it from raw file dumps when an AGENTS.md covers the area.
- **Token economy first.** When choosing between an exhaustive read and a focused DOX walk, prefer the DOX walk. Read source files only after the closest AGENTS.md says you need them.
- **One DOX pass per meaningful change.** Every edit that affects contracts, structure, ownership, or behavior must be followed by a DOX pass (update nearest owning doc, refresh indexes, remove stale text) before the task is reported done.
- **Keep the tree shallow.** This project is small. Avoid creating an AGENTS.md for every subdirectory — only durable boundaries earn one (see `lib/AGENTS.md`, `lib/screens/AGENTS.md`, `lib/src/AGENTS.md`, `lib/services/AGENTS.md`, `android/AGENTS.md`, `test/AGENTS.md`).
- **No `AGENTS.md` inside `build/`, `.dart_tool/`, `ios/`, `linux/`, `macos/`, `windows/`, `web/`, or `assets/`.** Those are either generated, empty stubs, or static binaries and have no durable contract worth documenting.

## Project Snapshot (Nudge)

- Flutter app (Dart 3.12+ / Material 3 dark theme) + native Android Java side.
- Brand palette and text styles live in `AppColors` inside `lib/main.dart`; import with `import '../main.dart' show AppColors;` from any other file.
- Persistence is Hive (`hive` + `hive_flutter`); boxes open lazily via the `*_hive_provider.dart` initialisers.
- Native bridge: two `MethodChannel`s — `com.nudge.app/rules` (sync + testRule) and `com.nudge.app/import` (SAF file picker). Channel name constants live in Dart and the Java handler.
- Onboarding gate: `kFirstRunCompleteKey` in `SharedPreferences`; see `lib/screens/onboarding_screen.dart` and the stateful `SmartReminderApp` in `lib/main.dart`.
- Background evaluation: `RuleWorker` (periodic, 15 min) + `BatteryReceiver` + `WifiChangeBroadcastReceiver`; all push notifications via `NotificationHelper`.

## Build / Run / Verify

- Install deps: `flutter pub get`
- Static check: `flutter analyze` (must report "No issues found!" before merging)
- Run on connected device / emulator: `flutter run`
- Build a signed-release-ish APK using the debug keystore (configured in `android/app/build.gradle.kts`): `flutter build apk --release`
- Sideload: `adb install -r build\app\outputs\flutter-apk\app-release.apk`
- Launch on device: `adb shell am start -n com.nudge.app/.MainActivity`
- **Disk space gotcha:** `build/` can grow past 2 GB. If a build fails with `No space left on device`, run `rmdir /s /q build` then rebuild.

## Child DOX Index

- `lib/AGENTS.md` — Dart source tree, app entry point, dependencies, build flow.
- `lib/screens/AGENTS.md` — UI screens (Home, Onboarding, Add/Edit Rule, Profiles, Settings) and the native channel call sites.
- `lib/src/AGENTS.md` — Data layer: Hive boxes, `Rule` and `Profile` models, providers, legacy migration.
- `lib/services/AGENTS.md` — Cross-cutting services (logger, permissions, export, backup).
- `android/AGENTS.md` — Native Java side: `MainActivity`, broadcast receivers, `NotificationHelper`, `RuleWorker`, `MethodChannel` contract.
- `test/AGENTS.md` — Widget tests and verification strategy.