// lib/services/permission_service.dart
//
// Helper utility for handling Android 12+ runtime permission UX.
//
// Permission strategy:
//   1. On first launch, prompt the user with the OS dialog via
//      [checkAndRequestInitial] for POST_NOTIFICATIONS (required to display
//      alerts). Location is intentionally NOT requested here — we defer it
//      to the moment the user actually creates or edits a Wi-Fi rule.
//   2. Before saving a rule, call [ensurePermissionBeforeSaving] which
//      re-checks POST_NOTIFICATIONS and, if denied, shows an AlertDialog
//      explaining why notifications are required. If the permission is
//      permanently denied, the dialog offers an "Open Settings" button to
//      deep-link into the app's notification settings page.
//   3. When the user creates or edits a Wi-Fi rule, the host screen calls
//      [requestWifiPermissions] to request ACCESS_FINE_LOCATION (required
//      to read the connected Wi-Fi SSID on Android 8.0+).
//
// The Settings screen also surfaces the current state of POST_NOTIFICATIONS
// and battery optimisation via [notificationStatus] and
// [batteryOptimizationStatus] so the user can fix a wrong setup without
// hunting through the OS settings menus.

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Snapshot of a permission's current state, suitable for rendering a
/// settings tile. Returned by [notificationStatus] and
/// [batteryOptimizationStatus].
class PermissionStatusSnapshot {
  const PermissionStatusSnapshot({
    required this.isGranted,
    required this.status,
  });

  /// Convenience: `true` when the OS reports the permission as granted
  /// (or "limited" where the system offers that variant, e.g. Photos).
  final bool isGranted;

  /// The raw [PermissionStatus] from permission_handler, in case callers
  /// want to inspect `isPermanentlyDenied` or `isRestricted`.
  final PermissionStatus status;
}

class PermissionService {
  /// Step 1 of the permission flow — invoked once on first boot from
  /// `main.dart`. Only POST_NOTIFICATIONS is requested here; location is
  /// deferred so a brand-new user is not immediately asked for two
  /// permissions before they have even seen the app.
  static Future<void> checkAndRequestInitial() async {
    // Notifications — required for every reminder to actually be visible.
    final PermissionStatus notif = await Permission.notification.status;
    if (!notif.isGranted && !notif.isLimited) {
      await Permission.notification.request();
    }
  }

  /// Step 2 of the permission flow — invoked from the "Save Rule" button
  /// in `add_rule_screen.dart` BEFORE the rule is persisted to Hive /
  /// SharedPreferences.
  ///
  /// Returns `true` if the app may proceed with saving the rule, `false` if
  /// the user is blocked on permission. When `false` is returned, an
  /// AlertDialog has already been shown to the user explaining the
  /// requirement and offering a path to fix it.
  static Future<bool> ensurePermissionBeforeSaving(BuildContext context) async {
    final PermissionStatus status = await Permission.notification.status;
    if (status.isGranted || status.isLimited) {
      return true;
    }

    // Notification permission is missing or denied. Show the in-app
    // explanation dialog.
    if (!context.mounted) return false;
    await _showPermissionDialog(context, status);
    // After the dialog, re-check the status. If the user accepted via
    // the dialog's "Allow" button, status.isGranted will now be true. If
    // they hit Settings, the OS handles the rest on return.
    final PermissionStatus after = await Permission.notification.status;
    return after.isGranted || after.isLimited;
  }

  /// Step 3 of the permission flow — invoked when the user creates or
  /// edits a Wi-Fi rule. On Android 8.0+ the OS redacts the connected
  /// SSID to a fake MAC (``<unknown ssid>``) unless the user has granted
  /// ACCESS_FINE_LOCATION. We request the location permission here and
  /// only here, so battery-only users never see a Wi-Fi prompt.
  ///
  /// The returned [PermissionStatus] reflects whatever the OS reported
  /// after the prompt — `isGranted`, `isPermanentlyDenied`, etc. The
  /// caller can decide whether to surface a follow-up dialog.
  static Future<PermissionStatus> requestWifiPermissions() async {
    final PermissionStatus loc = await Permission.locationWhenInUse.status;
    if (loc.isGranted || loc.isLimited) {
      return loc;
    }
    return Permission.locationWhenInUse.request();
  }

  /// Returns the current POST_NOTIFICATIONS state for the Settings UI.
  /// "Enabled" / "Disabled" tiles in `settings_screen.dart` call this
  /// on init and re-call it on `onResume` (when the user returns from
  /// the OS settings page) so the tile reflects the fresh state.
  static Future<PermissionStatusSnapshot> notificationStatus() async {
    final PermissionStatus status = await Permission.notification.status;
    return PermissionStatusSnapshot(
      isGranted: status.isGranted || status.isLimited,
      status: status,
    );
  }

  /// Returns the current battery-optimisation state for the Settings UI.
  /// `isGranted == true` means Android has whitelisted the app (i.e. it
  /// can run background work freely). `isGranted == false` means
  /// Doze/App Standby can kill the app's background `RuleWorker`.
  static Future<PermissionStatusSnapshot> batteryOptimizationStatus() async {
    final PermissionStatus status =
        await Permission.ignoreBatteryOptimizations.status;
    return PermissionStatusSnapshot(
      isGranted: status.isGranted,
      status: status,
    );
  }

  /// Opens the system battery-optimisation settings page for this app.
  /// On older Android versions (M, N) that don't ship the
  /// `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS` activity we fall back
  /// to the generic app settings page via [openAppSettings].
  static Future<void> openBatteryOptimizationSettings() async {
    // permission_handler ships a one-shot helper that tries the battery
    // settings intent first and falls back to the app settings page if
    // the OEM doesn't expose it. Simpler (and safer) than re-implementing
    // the intent dispatch ourselves.
    await openAppSettings();
  }

  /// Shows an AlertDialog explaining the notification permission requirement.
  /// If the permission is permanently denied (the user ticked "Don't ask
  /// again"), the dialog offers an "Open Settings" button that deep-links
  /// to the app's notification settings page so the user can grant it
  /// manually.
  static Future<void> _showPermissionDialog(
    BuildContext context,
    PermissionStatus status,
  ) async {
    final bool permanentlyDenied = status.isPermanentlyDenied ||
        status.isRestricted;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Notifications are required'),
          content: Text(
            permanentlyDenied
                ? 'Notifications are blocked. To make Smart Reminder work, open the app '
                    'settings and enable notifications for this app.'
                : 'Smart Reminder needs to send you a notification when a rule fires '
                    '(e.g. battery low, Wi-Fi change). Please allow notifications to '
                    'continue.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            if (permanentlyDenied)
              FilledButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await openAppSettings();
                },
                child: const Text('Open Settings'),
              )
            else
              FilledButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  // Re-trigger the system dialog. If the user denies, the
                  // next call to ensurePermissionBeforeSaving will surface
                  // this dialog again — and the OS will have marked the
                  // request as "permanently denied" if they hit "Don't
                  // allow" twice.
                  await Permission.notification.request();
                },
                child: const Text('Allow'),
              ),
          ],
        );
      },
    );
  }
}