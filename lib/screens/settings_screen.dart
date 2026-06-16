// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

// ignore: unused_import
import '../main.dart' show NudgePaletteContext;
import '../services/app_logger.dart';
import '../services/export_history_provider.dart';
import '../services/permission_service.dart';
import '../services/rule_backup_service.dart';
import '../src/profiles/export_record.dart';
import '../src/profiles/profile_hive_provider.dart';
import '../src/rules/rules_hive_provider.dart';
import 'about_screen.dart';
import 'recent_activity_screen.dart';

/// Same channel name declared in `MainActivity.java` and used by
/// `home_screen.dart` for the per-rule "Test" play button. We use the
/// existing rules channel here for the `runRuleWorkerNow` method so the
/// Settings screen never has to declare its own.
const MethodChannel _rulesChannel = MethodChannel('com.nudge.app/rules');

class SettingsScreen extends StatefulWidget {
  final RulesHiveProvider provider;
  final ProfileHiveProvider profilesProvider;
  final ExportHistoryProvider exportHistory;

  const SettingsScreen({
    super.key,
    required this.provider,
    required this.profilesProvider,
    required this.exportHistory,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// Which export card is currently running. We track the scope (not just
/// a single `bool`) so the spinner shows on the card the user actually
/// tapped, not on every export card on the page.
enum _ExportScope { idle, currentProfile, allRules }

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  _ExportScope _exportScope = _ExportScope.idle;
  bool _importing = false;
  // True while a "Test all rules now" run is in flight. Drives the
  // spinner on the _TestAllRulesCard and prevents double-tap.
  bool _runningWorker = false;

  // System status: surfaced at the top of Settings so the user can see
  // (and fix) the two permissions that affect background reliability.
  // `null` means "not yet loaded" — the first frame shows a skeleton.
  PermissionStatusSnapshot? _notificationStatus;
  PermissionStatusSnapshot? _batteryStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Fire-and-forget; the UI swaps in real values as the futures
    // complete. We don't block the first frame on a permission read.
    _refreshPermissionStatuses();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the user returns from the OS settings page the OS may have
    // flipped a permission. Re-read so the tile reflects the new state
    // without a manual pull-to-refresh.
    if (state == AppLifecycleState.resumed) {
      _refreshPermissionStatuses();
    }
  }

  Future<void> _refreshPermissionStatuses() async {
    try {
      final notif = await PermissionService.notificationStatus();
      final battery = await PermissionService.batteryOptimizationStatus();
      if (!mounted) return;
      setState(() {
        _notificationStatus = notif;
        _batteryStatus = battery;
      });
    } catch (e, st) {
      AppLogger.w('Settings: permission status refresh failed.', error: e);
      AppLogger.d('Stack: $st');
    }
  }

  bool _isExporting(_ExportScope scope) => _exportScope == scope;

  Future<void> _handleExport({String? scopeProfileId}) async {
    final scope = scopeProfileId == null
        ? _ExportScope.allRules
        : _ExportScope.currentProfile;
    if (_exportScope != _ExportScope.idle) return;
    setState(() => _exportScope = scope);
    try {
      final count = await RuleBackupService.exportAndShare(
        widget.provider.value,
        history: widget.exportHistory.value,
        profileName: scopeProfileId,
      );
      if (!mounted) return;
      if (count > 0) {
        _showSnack('Exported $count rule${count == 1 ? '' : 's'}.');
      } else {
        _showSnack('No rules to export.');
      }
    } catch (e) {
      AppLogger.e('Export threw.', error: e);
      if (!mounted) return;
      _showSnack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _exportScope = _ExportScope.idle);
    }
  }

  /// Forwards the user's "Test all rules now" tap to the native side
  /// via the `com.nudge.app/rules` `runRuleWorkerNow` MethodChannel
  /// method. The Java side enqueues a `OneTimeWorkRequest` for the
  /// same `RuleWorker` class the periodic schedule uses, so the
  /// evaluation + alert-type routing is identical to a real trigger.
  ///
  /// We hold a `_runningWorker` flag so the button shows a spinner and
  /// the user can't double-fire. A SnackBar is the only feedback: the
  /// worker is async and there's no completion callback in the
  /// `enqueueUniqueWork` API, so we acknowledge the request immediately.
  Future<void> _handleRunWorkerNow() async {
    if (_runningWorker) return;
    setState(() => _runningWorker = true);
    try {
      await _rulesChannel.invokeMethod<bool>('runRuleWorkerNow');
      AppLogger.d('Settings: runRuleWorkerNow enqueued.');
      if (!mounted) return;
      _showSnack(
          'Checking all rules now — notifications should fire within a few seconds.');
    } catch (e, st) {
      AppLogger.e('Settings: runRuleWorkerNow threw.', error: e);
      AppLogger.d('Stack: $st');
      if (!mounted) return;
      _showSnack('Could not start the rule check: $e');
    } finally {
      if (mounted) setState(() => _runningWorker = false);
    }
  }

  /// Wipes every piece of data the app has ever stored on the device:
  /// all rules (RulesService), all profiles (ProfileService — then
  /// re-creates the default "Personal" profile), and the export history
  /// (ExportHistoryService). The home list immediately shows the empty
  /// state via the providers' `notifyListeners` callbacks. We keep the
  /// `first_run_complete` flag so the user is not thrown back to
  /// onboarding — they're already familiar with the app and just want
  /// a clean slate.
  ///
  /// This is intentionally called from a double-confirmation dialog so
  /// the red "Delete all data" tile cannot be triggered by accident.
  Future<void> _handleFactoryReset() async {
    try {
      // Clear in a sensible order: rules first (because they're the
      // biggest payload), then profiles (which re-creates the default),
      // then export history. Each call invokes _notify() so the UI
      // rebuilds incrementally and a failure in one doesn't block the
      // others.
      await widget.provider.value.clearAll();
      await widget.profilesProvider.value.clearAll();
      await widget.exportHistory.value.clearAll();
      AppLogger.d('Settings: factory reset complete.');
      if (!mounted) return;
      _showSnack('All data deleted. Your rules and profiles are gone.');
    } catch (e, st) {
      AppLogger.e('Settings: factory reset failed.', error: e);
      AppLogger.d('Stack: $st');
      if (!mounted) return;
      _showSnack('Could not delete data: $e');
    }
  }

  Future<void> _confirmAndFactoryReset() async {
    // Two-step confirmation: the tile is a full-width tappable surface
    // (so it can be tapped by accident), but the actual destructive
    // action is gated by a typed-in confirmation string. The first tap
    // surfaces a dialog; the second requires the user to type "DELETE".
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => const _FactoryResetDialog(),
    );
    if (confirmed == true) {
      await _handleFactoryReset();
    }
  }

  Future<void> _handleImport() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final result =
          await RuleBackupService.importFromFile(widget.provider.value);
      if (!mounted) return;
      _showImportResult(result);
    } catch (e) {
      AppLogger.e('Import threw.', error: e);
      if (!mounted) return;
      _showSnack('Import failed: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _reshareRecord(ExportRecord r) async {
    try {
      await Share.shareXFiles(
        [XFile(r.filePath, mimeType: 'application/json', name: r.fileName)],
        text:
            'Nudge rules backup (${r.ruleCount} rule${r.ruleCount == 1 ? '' : 's'})',
        subject: 'Nudge rules backup',
      );
      AppLogger.d('Re-shared export ${r.id}');
    } catch (e) {
      AppLogger.e('Re-share failed.', error: e);
      if (mounted) _showSnack('Re-share failed: $e');
    }
  }

  Future<void> _deleteRecord(ExportRecord r) async {
    await widget.exportHistory.value.delete(r.id);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showImportResult(ImportResult result) {
    if (result.isEmpty) {
      _showSnack('Import cancelled.');
      return;
    }
    final pieces = <String>[];
    if (result.imported > 0) {
      pieces.add(
          'Imported ${result.imported} rule${result.imported == 1 ? '' : 's'}.');
    }
    if (result.skipped > 0) {
      pieces.add('${result.skipped} skipped (duplicates).');
    }
    if (result.errors.isNotEmpty) {
      pieces.add(
          '${result.errors.length} error${result.errors.length == 1 ? '' : 's'}.');
    }
    _showSnack(pieces.join(' '));
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  String _formatTimestamp(DateTime t) {
    final local = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        titleSpacing: 20,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          // System status lives at the TOP so a brand-new user with two
          // broken permissions sees the call-to-action before they get
          // lost in the backup / profile / about sections below.
          const _SectionHeader(text: 'SYSTEM STATUS'),
          const SizedBox(height: 8),
          _SystemStatusTile(
            icon: Icons.notifications_active_rounded,
            title: 'Notification access',
            subtitle:
                'Required to show reminders. Disabled rules will fire silently.',
            snapshot: _notificationStatus,
            grantedLabel: 'Enabled',
            deniedLabel: 'Disabled — tap to fix',
            onTap: () async {
              // Open the system app-info page; the user toggles the
              // notification permission there. After they return,
              // didChangeAppLifecycleState re-reads the status.
              await openAppSettings();
              if (mounted) await _refreshPermissionStatuses();
            },
          ),
          const SizedBox(height: 10),
          _SystemStatusTile(
            icon: Icons.battery_charging_full_rounded,
            title: 'Battery optimization',
            subtitle:
                'If restricted, Android may stop the background reminder worker.',
            snapshot: _batteryStatus,
            grantedLabel: 'Unrestricted',
            deniedLabel: 'Restricted — tap to fix',
            onTap: () async {
              await PermissionService.openBatteryOptimizationSettings();
              if (mounted) await _refreshPermissionStatuses();
            },
          ),
          const SizedBox(height: 28),
          const _SectionHeader(text: 'RULE TESTING'),
          const SizedBox(height: 8),
          // The "Test all rules now" tile. The native worker schedules
          // itself every 15 minutes; this button lets a user bypass
          // that schedule and verify a rule actually fires (e.g. after
          // they tweak a threshold). Without this button a first-time
          // user might wait 15 minutes before seeing anything happen.
          _BackupCard(
            icon: Icons.play_circle_outline_rounded,
            title: 'Test all rules now',
            subtitle:
                'Bypasses the 15-minute background schedule. Use this after creating a rule to confirm it actually fires.',
            isBusy: _runningWorker,
            actionLabel: 'Run now',
            onAction: _handleRunWorkerNow,
          ),
          const SizedBox(height: 28),
          // Recent activity is its own section because it answers a
          // different question from the rest of "RULE TESTING": that
          // section is about *forcing* the worker to run; this is
          // about *seeing what already happened*. Users coming back
          // after a day will look here first.
          const _SectionHeader(text: 'ACTIVITY'),
          const SizedBox(height: 8),
          _BackupCard(
            icon: Icons.history_rounded,
            title: 'Recent activity',
            subtitle:
                'See the most recent times Nudge delivered a reminder, reverse-chronological.',
            isBusy: false,
            actionLabel: 'View',
            onAction: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RecentActivityScreen(
                  rulesProvider: widget.provider,
                  profilesProvider: widget.profilesProvider,
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          const _SectionHeader(text: 'BACKUP & RESTORE'),
          const SizedBox(height: 8),
          _BackupCard(
            icon: Icons.ios_share_rounded,
            title: 'Export current profile',
            subtitle:
                "Share the active profile's rules. The file is also saved to Recent backups.",
            isBusy: _isExporting(_ExportScope.currentProfile),
            actionLabel: 'Export',
            onAction: () => _handleExport(
              scopeProfileId: widget.profilesProvider.value.activeProfileId,
            ),
          ),
          const SizedBox(height: 12),
          _BackupCard(
            icon: Icons.public_rounded,
            title: 'Export all rules',
            subtitle:
                'Share a backup file containing every rule from every profile.',
            isBusy: _isExporting(_ExportScope.allRules),
            actionLabel: 'Export',
            onAction: () => _handleExport(),
          ),
          const SizedBox(height: 12),
          _BackupCard(
            icon: Icons.file_download_rounded,
            title: 'Import rules',
            subtitle:
                'Pick a backup file to add its rules. Duplicates are skipped automatically.',
            isBusy: _importing,
            actionLabel: 'Import',
            onAction: _handleImport,
          ),
          const SizedBox(height: 28),
          const _SectionHeader(text: 'RECENT BACKUPS'),
          const SizedBox(height: 8),
          _RecentBackupsList(
            history: widget.exportHistory,
            onReshare: _reshareRecord,
            onDelete: _deleteRecord,
            formatSize: _formatSize,
            formatTimestamp: _formatTimestamp,
          ),
          const SizedBox(height: 28),
          // DATA & PRIVACY: the user-trust section. "Delete all data"
          // is intentionally the LAST thing on the page (after About)
          // so an accidental tap on it requires scrolling to the bottom
          // + a typed confirmation in the dialog. This is the right
          // shape for a destructive action: discoverable but never in
          // the way.
          const _SectionHeader(text: 'DATA & PRIVACY'),
          const SizedBox(height: 8),
          _DangerCard(
            icon: Icons.delete_forever_rounded,
            title: 'Delete all data',
            subtitle:
                'Permanently removes every rule, profile, and backup record stored on this device. This cannot be undone.',
            onAction: _confirmAndFactoryReset,
          ),
          const SizedBox(height: 28),
          const _SectionHeader(text: 'ABOUT'),
          const SizedBox(height: 8),
          _AboutCard(
            onOpen: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 8, bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          color: p.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// Single actionable status row. Renders a coloured "Enabled" /
/// "Unrestricted" pill (green) or a "Disabled" / "Restricted" pill
/// (amber), and forwards a tap to [onTap] so the caller can deep-link
/// into the OS settings page.
///
/// When [snapshot] is `null` the row is still rendered but the status
/// pill shows a neutral "Checking…" placeholder so the page never lays
/// out with an empty gap.
class _SystemStatusTile extends StatelessWidget {
  final IconData icon;
  final String title;
  // One-line explainer that sits under the title. Helps the user
  // understand *why* a permission matters and *what happens* if it's
  // denied — otherwise the green/amber pill is just a coloured label
  // with no context.
  final String subtitle;
  final PermissionStatusSnapshot? snapshot;
  final String grantedLabel;
  final String deniedLabel;
  final Future<void> Function() onTap;

  const _SystemStatusTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.snapshot,
    required this.grantedLabel,
    required this.deniedLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bool granted = snapshot?.isGranted ?? false;
    final bool loaded = snapshot != null;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: p.accent, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: p.textSecondary,
                                height: 1.3,
                              ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(
                granted: granted,
                loaded: loaded,
                grantedLabel: grantedLabel,
                deniedLabel: deniedLabel,
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: p.textSecondary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Coloured pill rendered on the right side of a [_SystemStatusTile].
/// Green when granted, amber when denied, neutral while loading.
class _StatusPill extends StatelessWidget {
  final bool granted;
  final bool loaded;
  final String grantedLabel;
  final String deniedLabel;

  const _StatusPill({
    required this.granted,
    required this.loaded,
    required this.grantedLabel,
    required this.deniedLabel,
  });

  @override
  Widget build(BuildContext context) {
    const Color goodBg = Color(0xFF1F3A2A);
    const Color goodFg = Color(0xFF6FE0A0);
    const Color warnBg = Color(0xFF3A2C1A);
    const Color warnFg = Color(0xFFFFC56F);

    final Color bg;
    final Color fg;
    final String text;
    if (!loaded) {
      bg = const Color(0xFF2C2C3A);
      fg = const Color(0xFFA0A0B0);
      text = 'Checking…';
    } else if (granted) {
      bg = goodBg;
      fg = goodFg;
      text = grantedLabel;
    } else {
      bg = warnBg;
      fg = warnFg;
      text = deniedLabel;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            loaded
                ? (granted
                    ? Icons.check_circle_rounded
                    : Icons.warning_amber_rounded)
                : Icons.hourglass_top_rounded,
            color: fg,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isBusy;
  final String actionLabel;
  final VoidCallback onAction;

  const _BackupCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isBusy,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Card(
      child: InkWell(
        onTap: isBusy ? null : onAction,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: p.accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: p.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: p.textSecondary,
                                height: 1.35,
                              ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              isBusy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : FilledButton(
                      onPressed: onAction,
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accent,
                        foregroundColor: const Color(0xFF1A1A1A),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        shape: const StadiumBorder(),
                      ),
                      child: Text(
                        actionLabel,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, letterSpacing: 0.3),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Destructive-action card. Visually identical to [_BackupCard] but
/// uses a red accent (the universal "stop" colour) and a red filled
/// button so the user immediately knows this is not a reversible
/// action. Lives in the DATA & PRIVACY section, intentionally at the
/// bottom of the page so it requires scrolling to reach.
class _DangerCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onAction;

  const _DangerCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    // Red is the universal "destructive" cue. The 0xCF4B4B tone is
    // the same red used for the swipe-to-delete placeholder so the
    // two destructive actions feel like part of the same vocabulary.
    const Color danger = Color(0xFFCF4B4B);
    return Card(
      child: InkWell(
        onTap: onAction,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: danger.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: danger, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                height: 1.35,
                              ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: danger,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 12),
                  shape: const StadiumBorder(),
                ),
                child: const Text(
                  'Delete',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, letterSpacing: 0.3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentBackupsList extends StatelessWidget {
  final ExportHistoryProvider history;
  final Future<void> Function(ExportRecord) onReshare;
  final Future<void> Function(ExportRecord) onDelete;
  final String Function(int) formatSize;
  final String Function(DateTime) formatTimestamp;

  const _RecentBackupsList({
    required this.history,
    required this.onReshare,
    required this.onDelete,
    required this.formatSize,
    required this.formatTimestamp,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ValueListenableBuilder<ExportHistoryService>(
      valueListenable: history,
      builder: (context, service, _) {
        final records = service.getAll();
        if (records.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.history_rounded, color: p.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No exports yet. Tap Export to create one — it will appear here so you can re-share or delete it later.',
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: p.textSecondary,
                                height: 1.4,
                              ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Column(
          children: [
            for (final r in records)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ExportRecordCard(
                  record: r,
                  onReshare: () => onReshare(r),
                  onDelete: () => onDelete(r),
                  formatSize: formatSize,
                  formatTimestamp: formatTimestamp,
                ),
              ),
            if (records.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => service.clearAll(),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('Clear all'),
                  style: TextButton.styleFrom(foregroundColor: p.textSecondary),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ExportRecordCard extends StatelessWidget {
  final ExportRecord record;
  final VoidCallback onReshare;
  final VoidCallback onDelete;
  final String Function(int) formatSize;
  final String Function(DateTime) formatTimestamp;

  const _ExportRecordCard({
    required this.record,
    required this.onReshare,
    required this.onDelete,
    required this.formatSize,
    required this.formatTimestamp,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.description_outlined,
                color: p.textSecondary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    record.fileName,
                    overflow: TextOverflow.ellipsis,
                    style:
                        Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: p.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatTimestamp(record.exportedAt)} · '
                    '${record.ruleCount} rule${record.ruleCount == 1 ? '' : 's'} · '
                    '${formatSize(record.sizeBytes)}'
                    '${record.label != null ? ' · ${record.label}' : ''}',
                    style:
                        Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: p.textSecondary,
                            ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Share again',
              icon: Icon(Icons.share_outlined, color: p.accent),
              onPressed: onReshare,
            ),
            IconButton(
              tooltip: 'Delete',
              icon: Icon(Icons.delete_outline, color: p.textSecondary),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  /// Tapped to push the full [AboutScreen]. Optional so the card can be
  /// embedded in contexts that want a static info display only.
  final VoidCallback? onOpen;

  const _AboutCard({this.onOpen});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.bolt_rounded,
                  color: p.accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nudge',
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: p.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Version 1.0.0 — context-aware reminders with profiles, backup, and transfer.',
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: p.textSecondary,
                                height: 1.4,
                              ),
                    ),
                  ],
                ),
              ),
              if (onOpen != null) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: p.textSecondary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Two-step confirmation for the "Delete all data" action. The user has
/// to type the literal word "DELETE" into a text field before the
/// confirm button activates; the cancel button is always available.
/// Returning `true` from `Navigator.pop` triggers the actual wipe.
class _FactoryResetDialog extends StatefulWidget {
  const _FactoryResetDialog();

  @override
  State<_FactoryResetDialog> createState() => _FactoryResetDialogState();
}

class _FactoryResetDialogState extends State<_FactoryResetDialog> {
  static const String _requiredPhrase = 'DELETE';
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _confirmed => _controller.text.trim() == _requiredPhrase;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AlertDialog(
      icon: Icon(
        Icons.warning_amber_rounded,
        color: const Color(0xFFCF4B4B),
        size: 32,
      ),
      title: const Text('Delete all data?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This permanently removes every rule, every profile (except the default "Personal" which will be recreated), and every backup record stored on this device.',
            style: TextStyle(height: 1.4),
          ),
          const SizedBox(height: 16),
          const Text(
            'Type DELETE below to confirm.',
            style: TextStyle(height: 1.4, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.characters,
            style: GoogleFonts.inter(
              color: p.textPrimary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
            decoration: InputDecoration(
              hintText: _requiredPhrase,
              hintStyle: TextStyle(
                color: p.textSecondary.withValues(alpha: 0.5),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          // Disabled until the user types the exact phrase. This is
          // the gold-standard pattern for destructive actions: explicit
          // and unambiguous, no "Are you sure?" that a thumb-tap can
          // blow through.
          onPressed: _confirmed ? () => Navigator.of(context).pop(true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFCF4B4B),
            foregroundColor: Colors.white,
            disabledBackgroundColor:
                const Color(0xFFCF4B4B).withValues(alpha: 0.35),
          ),
          child: const Text('Delete everything'),
        ),
      ],
    );
  }
}


