# lib/screens/ — UI screens

## Purpose

User-facing Flutter screens. Every page in the app is rooted here, plus the native-channel call sites that the home screen uses to talk to the Java side.

## Ownership

- Owns: every file in `lib/screens/`.
- Does **not** own: data models (see `lib/src/AGENTS.md`), cross-cutting services (see `lib/services/AGENTS.md`), or the shared `AppColors`/`ThemeData` (see `lib/main.dart`).

## Local Contracts

- **Use `context.palette` (the `NudgePaletteContext` extension) for every brand colour.** Never hard-code `AppColors.X` or `AppColorsLight.X` in a screen — the extension auto-picks the right palette from `Theme.of(context).brightness` so the app renders correctly in both OS themes. Fall back to `Theme.of(context).colorScheme` only for non-brand surfaces. The only known brand greys (e.g. amber cooldowns in `_RuleCard`) may stay hard-coded since they read fine on both surfaces.
- **Empty state on the home screen is `_SampleRulesEmptyState`, not a generic icon.** The empty state must show three "Try a sample" cards (battery ≤ 20 %, battery ≥ 80 %, Wi-Fi SSID match) that one-tap-create a real rule via `provider.value.addRule(rule)`. This is the single biggest activation lever in the app — never replace it with a static "no rules" message.
- **Long-press on a rule card opens `_FullEditRuleDialog`, not a label-only dialog.** The dialog must support editing every persisted field: `reminderText` (label), `triggerType` (battery / Wi-Fi, a chip toggle), `comparisonOperator` (a dropdown filtered by trigger type), `triggerValue` (a `TextFormField` with type-specific validation), and `alertType` (a `Wrap` of two `ChoiceChip`s: `Standard` ↔ `Urgent Alarm`). Persist via `provider.value.updateRule(id, mutator)` where the mutator rewrites *all five* fields, not just the label. The "Duplicate" action remains as a quick-action button and copies `alertType` from the source rule.
- **Alert type mirrors between create and edit flows.** The `AddRuleScreen` form (`_AlertTypeSelector`) and `_FullEditRuleDialog` both render the same two `ChoiceChip`s backed by `AlertType.values` from `lib/src/rules/hive_rules.dart`. Use the same icons and labels so a brand-new user immediately recognises the choice in both flows.
- **Add-rule screen requests Wi-Fi permission on save, not before.** `AddRuleScreen._saveRule` calls `PermissionService.ensurePermissionBeforeSaving` first, then `PermissionService.requestWifiPermissions` only when the rule's trigger type is `wifi`. The location prompt is never shown for battery rules. The save proceeds even if the user denies location; the rule will just see `<unknown ssid>` until the permission is granted. The Settings "System Status" section surfaces the missing permission.
- **Settings "SYSTEM STATUS" section is the first thing on the page.** Two `_SystemStatusTile`s (Notification access, Battery optimization) sit above the BACKUP & RESTORE section. The screen is a `StatefulWidget` with `WidgetsBindingObserver` and re-reads the permission states on `AppLifecycleState.resumed` so a user who toggles a permission in the OS settings page sees the new state on return. `_StatusPill` renders a green "Enabled"/"Unrestricted" or amber "Disabled"/"Restricted" pill; a neutral "Checking…" pill is shown while the futures are in flight (first frame).
- **Settings tile taps deep-link into the OS settings page.** Notification tile calls `openAppSettings()` (from `permission_handler`); battery tile calls `PermissionService.openBatteryOptimizationSettings()`. Both refresh the status on return.
- **Home AppBar uses a single overflow menu.** The trailing action on `HomeScreen` is one `PopupMenuButton` (the `Icons.more_vert_rounded` "⋯") with three items: Profiles, Settings, and Rate Nudge (or whatever the current placeholder is). Do not re-introduce individual `IconButton`s in the AppBar actions — the menu is the established pattern for secondary navigation. Use the `_HomeOverflowMenu` private widget in `home_screen.dart` as the template.
- **Inject providers.** Each screen takes the providers it needs as `required` constructor parameters and never instantiates a `ValueNotifier` itself.
- **Use `ValueListenableBuilder`** to react to provider changes; do not call `.value` from `initState`.
- **Use `ScaffoldMessenger.of(context).showSnackBar(...)` for transient feedback.** Never block the UI thread with `AlertDialog`s to surface success / failure.
- **SnackBar message for the "Test rule" Play button is exactly `Notification test sent!`.** If you change the message, also update the home-screen test in `test/widget_test.dart` (when one exists) and the AGENTS.md copy.
- **Rule card swipe-to-delete uses a `Dismissible`** with `key: ValueKey<int>(rule.id)`, `direction: DismissDirection.horizontal`, and a red `_SwipeBackground` placeholder. The actual delete + Undo SnackBar runs in `onDismissed` so the `BuildContext` is the home-screen `ScaffoldMessenger` (not the dismissed subtree). Undo calls `RulesService.restoreRule` to put the row back at the same Hive key — never use `Box.add` for the restore path.
- **Rule card long-press opens the edit / duplicate dialog.** The dialog uses a `Form` + `TextFormField` (renaming) plus a Duplicate action that calls `RulesService.duplicateRule` (which offsets battery by +5 % and Wi-Fi by appending ` 2G`). The dialog returns a typed `_EditRuleResult` (save | duplicate | null) so the scaffold knows which persistence call to make.
- **Per-scope busy flags on settings-screen export cards.** The two export `_BackupCard`s ("Export current profile" + "Export all rules") must NOT share a single `bool isBusy` — the spinner would then show on the card the user *didn't* tap. Use a typed enum (`_ExportScope { idle, currentProfile, allRules }`) and derive each card's `isBusy` from `_isExporting(scope)`. This is the bug we shipped + fixed in the "Rule Management" sprint; do not regress.
- **Onboarding finish callback.** `OnboardingScreen` accepts `VoidCallback onComplete` and is wired by `_SmartReminderAppState` to flip its state. Do not call `Navigator.pushReplacement` from inside `OnboardingScreen`.
- **Onboarding bottom bar must always show both buttons** — a left "Skip" / "Maybe later" text button and a right "Next" / "Get Started" elevated button. Never replace either with a `SizedBox.shrink`, or the row's `SpaceBetween` / `Spacer` will leave one of them off-screen on narrow phones. The `ElevatedButton` here explicitly overrides the theme's `Size.fromHeight(56)` minimum (which expands to infinity width) with `Size(0, 56)` so it sits inline.
- **Onboarding slide content lives inside `Center > ConstrainedBox(maxWidth: 360) > Padding(horizontal: 32) > Column(crossAxisAlignment: center)`.** This is the only pattern that keeps the icon, title, and description horizontally aligned across slides.
- **Onboarding slide 3 (the rocket) animates.** A `TickerProviderStateMixin` drives a continuous bob + halo-ring scale, plus a one-shot lift-off (translate up + scale up + fade) when "Get Started" is tapped. Persist `first_run_complete` *after* the lift-off completes so the home screen appears as the rocket is leaving the frame.

## Work Guidance

- **Card sizing.** Rule / profile / option cards live inside a `Card` from the theme (16 px radius). Use the existing `Card` widget — do not roll a new rounded surface.
- **Padding.** Standard list padding is `EdgeInsets.fromLTRB(20, 12, 20, 96)` to clear the floating action button. Profile chip strip is `EdgeInsets.symmetric(horizontal: 12, vertical: 8)` inside a 56-px-tall container.
- **Empty states** use a tinted circular icon well (`AppColors.surface` background, `AppColors.accent` border at 18% alpha) plus a `titleLarge` headline and `bodyMedium` description. Match `_EmptyState` in `home_screen.dart` when adding new empties.
- **Do not import a Hive box directly** from a screen. All persistence goes through the providers from `lib/src/`.

## Verification

- Manual smoke: launch on a connected device, walk through onboarding → home → add rule → test rule → profiles → settings → export.
- Static check: `flutter analyze` from repo root must be clean.

## Child DOX Index

No further child docs; this is the leaf boundary for the UI layer.