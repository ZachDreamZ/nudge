# Contributing to Nudge

Thanks for your interest in improving Nudge. This document covers the development setup, code style, and contribution process. Please read it before opening a pull request.

## Development setup

Nudge is a Flutter app with a small Java side. You need:

- Flutter SDK (Dart 3.12 or later)
- Android SDK with build-tools matching `compileSdk` in `android/app/build.gradle.kts`
- A connected Android device or emulator (API 26 or later recommended)
- An IDE of your choice; VS Code with the Flutter extension and Android Studio both work well

Clone the repository, fetch dependencies, and verify the build:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

All three of the verification commands must succeed before you open a pull request.

## Code style

The project follows a small number of conventions. Please match the surrounding style when you write new code.

- Dart uses the `flutter_lints` package. Run `flutter analyze` and resolve every warning before submitting.
- Keep widgets small. The home screen's `_HomeScaffold` is a useful example: it is laid out as a series of small, named widgets (`_SampleRulesEmptyState`, `_RuleCard`, `_AlertTypeBadge`, etc.) so that each piece can be reasoned about in isolation.
- Use the `context.palette` extension from `lib/main.dart` instead of hard-coding `AppColors` reads in screens. New themed components should be reachable through the palette.
- Do not import `AppColors` directly from a screen. The only place `AppColors` is read is the `_buildNudgeTheme` helper in `lib/main.dart`. New constants belong there.
- Add doc comments to public Dart symbols. The AGENTS.md files in the repo document the per-folder contracts; read the nearest one before editing a file.
- Java follows the existing class layout: each broadcast receiver or helper has its own file, a top-of-file comment that explains its lifecycle, and a single `Log` call per interesting branch.

## Architecture

The repo is organized so that every folder has a single, well-defined contract documented in the nearest `AGENTS.md`:

- `lib/AGENTS.md` documents the Flutter app's entry point, brand palette, persistence layer, and how to wire new screens.
- `lib/screens/AGENTS.md` documents the user-facing screen inventory and the MethodChannel call sites.
- `lib/src/AGENTS.md` documents the data layer: Hive boxes, models, providers, and migrations.
- `lib/services/AGENTS.md` documents cross-cutting services: permissions, backups, export history, logging.
- `android/AGENTS.md` documents the Java side: notifications, worker, broadcast receivers, MethodChannel contract.
- `test/AGENTS.md` documents the test strategy and infrastructure.

When you change code that affects any of these contracts, update the nearest `AGENTS.md` in the same change. See `AGENTS.md` at the repo root for the global rules.

## Commit messages

Use a short imperative subject line (50 characters or fewer), followed by an empty line, followed by a wrapped body (72 characters per line). The body should explain *what* changed and *why*, not *how*. Common prefixes that work well in this project:

- `feat:` for new user-facing features
- `fix:` for bug fixes
- `refactor:` for internal changes that do not alter behavior
- `docs:` for documentation-only changes
- `test:` for test additions or fixes
- `chore:` for tooling or build configuration

A good first line: `fix: redacted raw rules JSON from MainActivity logs`. A bad first line: `updated some files`.

## Pull request process

1. Open an issue first for significant changes so we can discuss direction before code is written.
2. Fork the repository and create a feature branch from `main`.
3. Make your changes, run `flutter analyze` and `flutter test`, and update the nearest `AGENTS.md` if the change affects a contract.
4. Open a pull request with a short title and a description that links the issue, summarizes the change, and lists the verification steps you ran.
5. Address review feedback by pushing additional commits to the same branch; do not force-push after review has begun.
6. Once approved, the maintainer will squash-merge the change.

## Reporting bugs

Open an issue using the bug report template. Include:

- Device model and Android version
- Steps to reproduce
- Expected vs actual behavior
- A `adb logcat` excerpt if the bug involves a crash or a notification that did not fire

## Security disclosures

If you discover a security issue, please email the maintainer directly rather than opening a public issue. Do not file a public bug for vulnerabilities until a fix is available.