# android/ — Native Android side

## Purpose

The Java side of Nudge: `MainActivity` (entry point + MethodChannel handlers), broadcast receivers that listen for battery / Wi-Fi state changes, `NotificationHelper` for posting the system notifications, and the periodic `RuleWorker` that re-evaluates rules from `SharedPreferences`. The Dart side never touches the OS directly — it goes through these two `MethodChannel`s.

## Ownership

- Owns: every file under `android/app/src/main/java/com/nudge/app/`, the manifest, the Gradle build files, the ProGuard rules, and the `res/` assets.
- Does **not** own: any Dart code (see `lib/AGENTS.md`), generated Flutter / Gradle artifacts (`build/`, `.gradle/`).

## Local Contracts

- **Two `MethodChannel`s, names must match Dart exactly:**
  - `com.nudge.app/rules` — methods:
    - `syncRules(rules: JSONArray)` (Dart → Java): persist the latest rules to `SharedPreferences` so `RuleWorker` can read them.
    - `testRule(ruleId: int?, reminderText: String, triggerType: String?, alertType: String?)` (Dart → Java): post a real notification through `NotificationHelper.showRuleEvaluationNotification`, bypassing the condition check. The `alertType` argument is routed to the matching notification channel by `NotificationHelper.routeForAlertType`. Optional — `null` falls back to the standard channel.
  - `com.nudge.app/import` — methods:
    - `pickFile()` (Dart → Java): launch the SAF picker, return the selected file's contents (or `null` on cancel).
  The channel name constants are declared as `CHANNEL_NAME` / `IMPORT_CHANNEL_NAME` in `MainActivity.java` and as `const MethodChannel('com.nudge.app/rules')` / `const MethodChannel('com.nudge.app/import')` in Dart. Mirror, never drift.
- **Notification channels are created in `NotificationHelper.createNotificationChannels(this)`** which is called from `configureFlutterEngine`. Channels:
  - `battery_low_channel` — `IMPORTANCE_LOW`, pinned notification ID 1001.
  - `wifi_change_channel` — `IMPORTANCE_DEFAULT`, pinned notification ID 1002.
  - `rule_evaluation_channel` — legacy `IMPORTANCE_DEFAULT`, pinned notification ID 1003. Kept around so user preferences survive an upgrade; new code paths should NOT post to this channel.
  - `nudge_default_channel` — `IMPORTANCE_DEFAULT`, sound = `RingtoneManager.getDefaultUri(TYPE_NOTIFICATION)`. Receives Standard-alert-type rules.
  - `nudge_alarm_channel` — `IMPORTANCE_HIGH`, vibration enabled, sound = `RingtoneManager.getDefaultUri(TYPE_ALARM)`. Receives Urgent-alert-type rules.
  The two `_evaluation`-family channels are user-visible in the OS settings as **"Smart Reminder Alerts"** (default) and **"Urgent Alarm Alerts"** (alarm). Renaming either channel breaks every existing user's per-channel preferences — always introduce a new channel ID instead.
- **`NotificationHelper.routeForAlertType(String)` is the single point of truth for alert-type routing.** Add new channels by extending this method's switch, never by inlining an `if` at the call site. The Dart side mirrors the canonical values in `AlertType` (`"default"` / `"alarm"`) — keep them in lock-step.
- **`SharedPreferences` keys live in `MainActivity.java`** (`PREFS_NAME = "nudge_prefs"`, `RULES_KEY = "stored_rules_json"`). `getStoredRulesJson` and `writeStoredRulesJson` are the public static accessors for `RuleWorker` and the broadcast receivers.
- **Broadcast receivers are dynamically registered** in `MainActivity.onCreate` using `ContextCompat.registerReceiver(... RECEIVER_EXPORTED)`. They are NOT declared in the manifest for runtime registration. The static entries in `AndroidManifest.xml` exist for boot-time safety only.
- **WorkManager is scheduled once** via `enqueueUniquePeriodicWork("rule_evaluation_work", KEEP, ...)` with a 15-minute minimum interval. Do not re-schedule on every receiver fire.
- **Permissions declared in `AndroidManifest.xml`** are the full set the app can ever request:
  - `POST_NOTIFICATIONS` (Android 13+) and `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (battery-optimization whitelist prompt) are the two permissions triggered via the Dart `PermissionService`.
  - `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` are required for the connected-Wi-Fi SSID read on Android 8.0+. Battery-only users never trigger this code path.
  - Bluetooth / `NEARBY_WIFI_DEVICES` are for the (currently queued) `flutter_nearby_connections` peer-to-peer transfer flow.
  Runtime requests flow through `PermissionService` (Dart) — never call `requestPermissions` from Java.

## Work Guidance

- **Java only, no Kotlin.** The project is intentionally Java to keep the AGP build fast and avoid the KGP-version-coupling warning. If a contributor wants to add Kotlin, they own upgrading `share_plus` / `flutter` to versions that pin Built-in Kotlin and updating the AGP / Gradle versions.
- **R8 / ProGuard keep rules** in `proguard-rules.pro` cover `androidx.work`, `androidx.startup`, and `google_fonts` reflection. New reflection-based libraries added here must be added to that file.
- **One `MainActivity` switch statement** dispatches all channel methods. When adding a new method:
  1. Add the `case` to the `switch` in `configureFlutterEngine`.
  2. Implement a `handle<MethodName>(MethodCall, MethodChannel.Result)` private method.
  3. Return `result.error("MISSING_ARG", ...)` for required-but-missing args, never a silent no-op.
  4. Log via `Log.d(TAG, ...)` and `Log.w(TAG, ...)` — do not use `System.out`.
- **Notification IDs are pinned** in `NotificationHelper` (1001 battery, 1002 Wi-Fi, 1003 rule). When adding a new notification type, pick a new pinned ID and document it here.
- **`RuleWorker` writes the updated rules JSON back** through `writeStoredRulesJson` after updating `lastFired`. This is what survives a reboot.

## Verification

- `flutter build apk --release` must succeed; the signed release artifact is `build/app/outputs/flutter-apk/app-release.apk`.
- Manual smoke on a real device: toggle battery saver, join a known Wi-Fi, force a WorkManager run with `adb shell cmd jobscheduler run -f com.nudge.app 999`, and confirm notifications fire.
- `flutter analyze` from repo root (Dart side) must remain clean.

## Child DOX Index

No further child docs; the `MainActivity.java` switch statement plus this file cover the entire Java surface.