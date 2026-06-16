# test/ — Widget tests and verification strategy

## Purpose

End-to-end and widget-level tests for the Flutter side. As of this writing the folder contains a single placeholder smoke test; the structure here exists to make adding more tests cheap and consistent.

## Ownership

- Owns: every file in `test/`.
- Does **not** own: build configuration (`pubspec.yaml`), the native side (see `android/AGENTS.md`).

## Local Contracts

- **Tests live in `test/`.** Flutter discovers them by file name (`*_test.dart`).
- **Hive must be initialised in tests** before any provider is constructed. Use `setUpAll` / `setUp` with `Hive.initFlutter()` (or `Hive.init(<tmp>)` for pure unit tests) and `await Hive.openBox<String>(...)` to match the real boot order from `lib/main.dart`.
- **Inject fakes, never real services.** Tests construct in-memory `RulesService` / `ProfileService` instances and pass them through the same constructor injection used by `SmartReminderApp`.
- **`flutter analyze` is the lint gate.** A red test file fails CI, but a red `flutter analyze` is the first thing reviewers will see.

## Work Guidance

- **Adding the first real widget test for the home screen.** Stub `MethodChannel` calls in `setUp` so the "Test rule" Play button can be tapped without a real engine binding. The placeholder `expect(1 + 1, equals(2))` proves the runner works; replace it before the next sprint.
- **Snapshot tests for screens are discouraged** — the brand palette changes too often. Prefer pump-and-interact widget tests.
- **Mirror the "Test rule" SnackBar message verbatim.** If the user-facing copy in `lib/screens/home_screen.dart` changes ("Notification test sent!"), update the matching assertion here.

## Verification

- `flutter analyze` from repo root must be clean.
- `flutter test` from repo root must finish with all tests green.

## Child DOX Index

No further child docs; this is a leaf boundary.