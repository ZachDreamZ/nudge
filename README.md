# Nudge

Context-aware reminders for Android. Set a trigger, pick an alert tone, get notified at exactly the right moment.

Nudge is a privacy-respecting reminder app built on a single principle: it does exactly one thing, and it does it without sending a single byte of your data to anyone.

---

## What it does

Nudge monitors two system signals on your phone and fires a notification when a rule you create matches:

- **Battery level** — "Notify me when battery drops below 20%" or "when charge reaches 80%."
- **Wi-Fi connection** — "Notify me when I connect to Home Wi-Fi."

Each rule is fully under your control:

- **Alert tone**: Standard notification sound or a loud alarm ringtone (Urgent Alarm).
- **Quiet hours**: Mute notifications inside a daily time window. Wraps midnight cleanly (e.g. 23:00 to 07:00).
- **Profiles**: Group rules under a named profile. The default "Personal" profile is created on first launch; you can add more.

A 15-minute background worker evaluates every active rule. From the Settings screen you can also force an immediate "Test all rules now" run to verify a rule works without waiting.

## Why Nudge

There is no shortage of reminder apps. What is short is reminder apps that:

- Do not require an account.
- Do not upload your data to a server.
- Do not show ads.
- Do not track you across other apps.

Nudge does none of those. It does not ask for your email. It does not connect to a backend. The only network call the app makes is an anonymous font fetch from `fonts.gstatic.com` on first launch, used to render the typography. All rules, profiles, and history live in the app's private storage on your device.

If you delete the app, your data is gone. If you want it gone before that, Settings has a "Delete all data" action that requires you to type the word `DELETE` to confirm.

## Project layout

```
.
|-- android/                 # Native Android Java + Gradle config
|-- lib/                     # Dart / Flutter source
|   |-- main.dart            # App entry point
|   |-- screens/             # Onboarding, home, settings, add/edit rule, profiles, about
|   |-- src/                 # Data layer: Hive boxes, Rule + Profile models
|   |-- services/            # Permissions, backups, export history, logging
|   `-- widgets/             # Shared widget primitives (staggered fade-in)
|-- test/                    # Unit tests (quiet hours edge cases, alert type normalization)
|-- assets/                   # App icon, splash
|-- PRIVACY_POLICY.md         # Plain-language privacy policy
|-- DATA_SAFETY.md            # Play Console Data Safety form answers
|-- analysis_options.yaml     # Dart lints
|-- pubspec.yaml              # Dart dependencies
|-- flutter_launcher_icons.yaml
`-- flutter_native_splash.yaml
```

The repo also contains an `AGENTS.md` hierarchy that documents the per-folder ownership and contracts; the root document explains the global structure and conventions.

## Build and run

Prerequisites:

- Flutter SDK (Dart 3.12 or later)
- Android SDK with build-tools matching the project's `compileSdk`
- A connected Android device or emulator

Install dependencies, then build the release APK:

```sh
flutter pub get
flutter analyze         # must report "No issues found!"
flutter test            # 10 tests, must all pass
flutter build apk --release
```

The signed release APK is written to `build/app/outputs/flutter-apk/app-release.apk`. Install it with `adb install -r build/app/outputs/flutter-apk/app-release.apk`.

## Architecture

The app is structured as a thin Dart layer over a native Java worker:

- **Dart side** owns the UI, the rule models, the Hive persistence, the in-app screens, and the MethodChannel surface.
- **Java side** owns the persistent background worker (`RuleWorker`), the broadcast receivers that fire on battery and Wi-Fi changes, and the system notification channels.
- **Hive** (`hive` and `hive_flutter`) stores rules, profiles, and export history as JSON in the app's private box.
- **SharedPreferences** is the only transport between Dart and the worker; the Dart side calls `syncRules` on the `com.nudge.app/rules` MethodChannel, the worker reads the rules JSON from a fixed SharedPreferences key (`stored_rules_json`) on every evaluation.

Quiet hours and alert type are persisted on each `Rule` and consulted both at evaluation time (in the worker, to suppress firing) and at render time (on the rule card, to show a Standard / Urgent badge).

A walkthrough of the contract between the two sides lives in `android/AGENTS.md`; the Dart side's contract lives in `lib/AGENTS.md`.

## Privacy

- No analytics SDK. No crash reporter. No advertising SDK.
- No remote server. The only network call is the standard Google Fonts fetch.
- Location is requested only when you create or edit a Wi-Fi rule (Android 8.0+ requires it to read the connected SSID). Battery-only users never see a location prompt.
- Battery optimization is requested from the Settings screen so the background worker is not killed by Doze. You can revoke it at any time.

The full privacy policy is in `PRIVACY_POLICY.md`. The Play Console Data Safety form answers are in `DATA_SAFETY.md`.

## Permissions

The app declares the minimum it needs and prompts for each one at the moment it becomes useful:

| Permission | When requested | Why |
|------------|----------------|-----|
| `POST_NOTIFICATIONS` | First launch | Show reminder notifications. |
| `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` | Creating or editing a Wi-Fi rule | Read the connected SSID on Android 8.0+. |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Settings → Battery optimization tile | Keep the background worker alive. |

No other runtime permissions are requested.

## Testing

`flutter test` runs the unit suite. Notable coverage:

- `Rule.isInQuietHours` edge cases: same-day window, window that crosses midnight, 1-minute degenerate window, 00:00 to 00:00 empty window, 00:00 to 23:59 maximal window.
- `Rule.toJson` / `Rule.fromJson` round-trip preserves `quietStartMinutes`, `quietEndMinutes`, and the alert type.
- `AlertType.normalize` accepts every whitelisted value and falls back to standard for malformed inputs.

## Contributing

Issues and pull requests are welcome. Please open an issue first to discuss significant changes. See `CONTRIBUTING.md` for development setup, code style, and the commit-message convention.

## License

This project is licensed under the MIT License. See `LICENSE` for the full text.