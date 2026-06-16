# lib/src/ — Data layer

## Purpose

Owns the durable state of the app: `Rule` and `Profile` data classes, their Hive boxes, the `ValueNotifier`-based providers that UI screens listen to, and the legacy migration that stamps `profileId` on rules saved by older app versions.

## Ownership

- Owns: `lib/src/rules/` and `lib/src/profiles/` (Hive boxes, models, providers, migration).
- Does **not** own: any UI code (see `lib/screens/AGENTS.md`), any backup / import / export logic (see `lib/services/AGENTS.md`).
- Adding a new persisted entity? Create a new sibling folder under `lib/src/` and add a child entry here.

## Local Contracts

- **Every Hive box opens through a `init*Hive()` async function** exported from the matching `*_hive_provider.dart`. The pattern is:
  1. `await Hive.initFlutter();`
  2. `final box = await Hive.openBox<String>('<name>');`
  3. `return XxxHiveProvider(XxxService(box));`
  `main.dart` awaits these in fixed order: rules → migrate → profiles → export history.
- **Box names are part of the contract.** `rules` (rules JSON), `profiles` (profile JSON), `export_history` (export records). Changing a name is a breaking change requiring a migration.
- **Records are stored as JSON strings.** Hive's `Box<String>` holds the JSON encoding of each model produced by `Model.toJson()`. Decode with `Model.fromJson(map)` — never store binary blobs.
- **The `id` field is the Hive key.** `RulesService.getAllRulesWithKeys()` and friends hand the key back to the caller; UI code uses it for toggles / deletes. Never persist `id` inside the JSON (it is assigned by Hive on `add`).
- **Every service exposes a `setOnChange(VoidCallback)`** that the `*HiveProvider` wires to `notifyListeners()`. After every mutation, call `_notify()`.
- **Three new mutators added in the "Rule Management" sprint**:
  - `restoreRule(Rule rule)` — re-inserts a rule under its original Hive key. Used by swipe-to-delete Undo. Re-uses `_box.put(id, json)` so the id (and `lastFired`) survives.
  - `updateRule(int ruleId, Rule Function(Rule) mutate)` — generic rehydrate-mutate-write helper. Used by the rename flow.
  - `duplicateRule(int ruleId)` — clones a rule with a trigger-value offset (battery: +5 % clamped to 0-100; Wi-Fi: " 2G" suffix on the SSID) and a " (copy)" suffix on the label. Persists a brand-new rule (new Hive key, fresh `lastFired`).
  All three go through `_notify()` so the UI rebuilds immediately.
- **Legacy migration:** `RulesService.migrateLegacyRulesToDefaultProfile()` stamps rules with no `profileId` to `kDefaultProfileId`. It is invoked once at boot, after `initRulesHive()` and before any UI builds. Do not move it.

## Work Guidance

- **Default profile auto-creation.** `kDefaultProfileId` (`"profile_personal"`) is the constant identity of the always-present profile. `ProfileService` (when present) is responsible for ensuring it exists before any rule references it.
- **`Rule.alertType` is a free-form string field** (defaults to `AlertType.standard`, i.e. `"default"`) that the user picks on the home screen's full-edit dialog and the add-rule flow. Allowed values are whitelisted in the `AlertType` class in `hive_rules.dart`:
  - `AlertType.standard` (`"default"`) — `nudge_default_channel` on the Java side, standard notification sound.
  - `AlertType.urgent` (`"alarm"`) — `nudge_alarm_channel` on the Java side, `IMPORTANCE_HIGH` + alarm ringtone.
  `AlertType.normalize` is the only function that may write to `Rule.alertType` from JSON; any unknown / missing value falls back to `AlertType.standard`. The field is mirrored in the JSON via `toJson` / `fromJson` and round-trips through the backup file unchanged. The `testRule` `MethodChannel` payload forwards it as the `alertType` argument; `RuleWorker` reads it from the stored rule JSON and passes it to `NotificationHelper.showRuleEvaluationNotification`.
- **Adding a new field to `Rule` or `Profile`.** Provide a safe default in `fromJson` so older JSON (e.g. in a backup file) still deserialises. If the new field is a typed enum, mirror the canonical values on the Java side in `NotificationHelper.java` (`routeForAlertType`) in lock-step.
- **No `print` calls** — log through `AppLogger` from `lib/services/app_logger.dart`.
- **No async work in the constructor.** Services are constructed synchronously from a Hive box; the only async surface is `init*Hive()` in the `*_hive_provider.dart` file.

## Verification

- `flutter analyze` from repo root must be clean.
- After editing a model, run `flutter run` once on a real device and verify rules / profiles still round-trip through a kill-and-relaunch.

## Child DOX Index

No further child docs; the `lib/src/rules/` and `lib/src/profiles/` folders are small enough that their contracts above are sufficient.