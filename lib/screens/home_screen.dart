// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart' show NudgePaletteContext;
import '../services/app_logger.dart';
import '../services/export_history_provider.dart';
import '../src/profiles/profile.dart';
import '../src/profiles/profile_hive_provider.dart';
import '../src/rules/hive_rules.dart';
import '../src/rules/rules_hive_provider.dart';
// AboutScreen is reached via the Settings overflow menu; we don't
// import it directly here any more.
import '../widgets/staggered_fade_in.dart';
import 'add_rule_screen.dart';
import 'profiles_screen.dart';
import 'settings_screen.dart';

/// MethodChannel for triggering a test notification on the native side.
/// Re-uses the same channel name as [main.dart] so we don't multiply
/// platform-side handlers; the `testRule` method dispatches to
/// [NotificationHelper.showRuleEvaluationNotification] in `MainActivity.java`.
const MethodChannel _rulesChannel = MethodChannel('com.nudge.app/rules');

class HomeScreen extends StatelessWidget {
  final RulesHiveProvider provider;
  final ProfileHiveProvider profilesProvider;
  final ExportHistoryProvider exportHistory;

  const HomeScreen({
    super.key,
    required this.provider,
    required this.profilesProvider,
    required this.exportHistory,
  });

  @override
  Widget build(BuildContext context) {
    return _HomeScaffold(
      provider: provider,
      profilesProvider: profilesProvider,
      exportHistory: exportHistory,
    );
  }
}

class _HomeScaffold extends StatelessWidget {
  final RulesHiveProvider provider;
  final ProfileHiveProvider profilesProvider;
  final ExportHistoryProvider exportHistory;

  const _HomeScaffold({
    required this.provider,
    required this.profilesProvider,
    required this.exportHistory,
  });

  static IconData _iconForTrigger(TriggerType t) {
    switch (t) {
      case TriggerType.battery:
        return Icons.battery_alert_rounded;
      case TriggerType.wifi:
        return Icons.wifi_rounded;
    }
  }

  static String _subtitleFor(Rule r) {
    final unit = r.triggerType == TriggerType.battery ? '%' : '';
    return 'IF ${r.triggerType.displayName} '
        '${r.comparisonOperator.displayLabel} ${r.triggerValue}$unit';
  }

  Future<void> _handleSampleRule(BuildContext context, Rule sample) async {
    final messenger = ScaffoldMessenger.of(context);
    final profileId = profilesProvider.value.activeProfileId;
    sample.profileId = profileId;
    try {
      final id = await provider.value.addRule(sample);
      AppLogger.d('Sample rule created id=$id label="${sample.reminderText}"');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Added — ${sample.reminderText}'),
            duration: const Duration(seconds: 2),
          ),
        );
    } catch (e, st) {
      AppLogger.e('Sample rule add failed.', error: e);
      AppLogger.d('Stack: $st');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Could not add sample: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
    }
  }

  Future<void> _handleSwipeDelete(BuildContext context, Rule rule) async {
    final messenger = ScaffoldMessenger.of(context);
    final id = rule.id;
    if (id == null) return;
    final snapshot = Rule(
      id: rule.id,
      profileId: rule.profileId,
      reminderText: rule.reminderText,
      triggerType: rule.triggerType,
      triggerValue: rule.triggerValue,
      comparisonOperator: rule.comparisonOperator,
      isEnabled: rule.isEnabled,
      lastFired: rule.lastFired,
      alertType: rule.alertType,
      quietStartMinutes: rule.quietStartMinutes,
      quietEndMinutes: rule.quietEndMinutes,
    );
    // ignore: discarded_futures
    provider.value.removeRule(id);
    AppLogger.d('Rule $id deleted (awaiting undo window).');
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted — ${rule.reminderText}'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              // ignore: discarded_futures
              provider.value.restoreRule(snapshot);
              AppLogger.d('Rule $id restored from undo.');
            },
          ),
        ),
      );
  }

  Future<void> _showFullEditDialog(BuildContext context, Rule rule) async {
    final id = rule.id;
    if (id == null) return;
    final result = await showDialog<Object>(
      context: context,
      builder: (dialogContext) => _FullEditRuleDialog(initial: rule),
    );
    if (result == null) return;

    if (result is _EditRuleDuplicate) {
      // ignore: discarded_futures
      provider.value.duplicateRule(id);
      AppLogger.d('Rule $id duplicated.');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Duplicated — ${rule.reminderText}'),
            duration: const Duration(seconds: 2),
          ),
        );
      return;
    }

    if (result is _EditRuleResult && result.updated != null) {
      final updated = result.updated!;
      // ignore: discarded_futures
      provider.value.updateRule(
        id,
        (r) {
          r.reminderText = updated.reminderText;
          r.triggerType = updated.triggerType;
          r.triggerValue = updated.triggerValue;
          r.comparisonOperator = updated.comparisonOperator;
          r.alertType = updated.alertType;
          r.quietStartMinutes = updated.quietStartMinutes;
          r.quietEndMinutes = updated.quietEndMinutes;
          return r;
        },
      );
      AppLogger.d('Rule $id fully edited.');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Rule updated.'),
            duration: Duration(seconds: 2),
          ),
        );
    }
  }

  Future<void> _testRuleTrigger(BuildContext context, Rule rule) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _rulesChannel.invokeMethod<void>('testRule', {
        'ruleId': rule.id,
        'reminderText': rule.reminderText,
        'triggerType': rule.triggerType.jsonValue,
        'alertType': rule.alertType,
      });
      AppLogger.d('Test notification fired for rule ${rule.id}.');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Notification test sent!'),
            duration: Duration(seconds: 2),
          ),
        );
    } catch (e, st) {
      AppLogger.w(
        'Test notification failed for rule ${rule.id}.',
        error: e,
      );
      AppLogger.d('Stack: $st');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Test failed: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProfileService>(
      valueListenable: profilesProvider,
      builder: (context, profileService, _) {
        final profiles = profileService.getAll();
        final activeId = profileService.activeProfileId;
        return ValueListenableBuilder<RulesService>(
          valueListenable: provider,
          builder: (context, ruleService, _) {
            final allForProfile = ruleService
                .getRulesForProfile(activeId)
                .where((r) => r.id != null)
                .toList();
            return Scaffold(
              appBar: AppBar(
                title: const Text('Nudge'),
                titleSpacing: 20,
                actions: [
                  _HomeOverflowMenu(
                    onProfiles: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfilesScreen(
                          rulesProvider: provider,
                          profilesProvider: profilesProvider,
                        ),
                      ),
                    ),
                    onSettings: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SettingsScreen(
                          provider: provider,
                          profilesProvider: profilesProvider,
                          exportHistory: exportHistory,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              body: Column(
                children: [
                  if (profiles.length > 1)
                    _ProfileChipStrip(
                      profiles: profiles,
                      activeId: activeId,
                      onSelect: (id) => profileService.setActiveProfileId(id),
                    ),
                  Expanded(
                    child: allForProfile.isEmpty
                        ? _SampleRulesEmptyState(
                            onPick: (sample) =>
                                _handleSampleRule(context, sample),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
                            itemCount: allForProfile.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final rule = allForProfile[index];
                              final id = rule.id!;
                              // Cascade in. The stagger caps at 12 so
                              // a 50-rule list doesn't drag out past
                              // ~300ms total.
                              final delayMs = (index.clamp(0, 12)) * 22;
                              return Dismissible(
                                key: ValueKey<int>(id),
                                direction: DismissDirection.horizontal,
                                onDismissed: (direction) =>
                                    _handleSwipeDelete(context, rule),
                                background: const _SwipeBackground(
                                  alignment: Alignment.centerLeft,
                                ),
                                secondaryBackground: const _SwipeBackground(
                                  alignment: Alignment.centerRight,
                                ),
                                child: StaggeredFadeIn(
                                  delayMs: delayMs,
                                  child: _RuleCard(
                                    rule: rule,
                                    leadingIcon: _iconForTrigger(rule.triggerType),
                                    subtitle: _subtitleFor(rule),
                                    onToggle: (value) {
                                      // ignore: discarded_futures
                                      ruleService.toggleEnabled(id);
                                      AppLogger.d('Toggled rule $id to $value');
                                    },
                                    onTest: () => _testRuleTrigger(context, rule),
                                    onLongPress: () =>
                                        _showFullEditDialog(context, rule),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
              floatingActionButton: FloatingActionButton.extended(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddRuleScreen(
                      provider: provider,
                      activeProfileId: activeId,
                    ),
                  ),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text(
                  'New rule',
                  style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.3),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ProfileChipStrip extends StatelessWidget {
  final List<Profile> profiles;
  final String activeId;
  final ValueChanged<String> onSelect;

  const _ProfileChipStrip({
    required this.profiles,
    required this.activeId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: profiles.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final pf = profiles[index];
          final isActive = pf.id == activeId;
          return StaggeredFadeIn(
            delayMs: 60 + (index * 50),
            child: ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    pf.icon,
                    size: 16,
                    color: isActive ? const Color(0xFF1A1A1A) : p.textPrimary,
                  ),
                  const SizedBox(width: 6),
                  Text(pf.name),
                ],
              ),
              selected: isActive,
              onSelected: (_) => onSelect(pf.id),
              selectedColor: p.accent,
              backgroundColor: p.surface,
              labelStyle: TextStyle(
                color: isActive ? const Color(0xFF1A1A1A) : p.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              shape: const StadiumBorder(),
              side: BorderSide.none,
            ),
          );
        },
      ),
    );
  }
}

class _SampleRulesEmptyState extends StatelessWidget {
  final void Function(Rule sample) onPick;
  const _SampleRulesEmptyState({required this.onPick});

  static final List<Rule> _samples = [
    Rule(
      reminderText: 'Battery drops below 20%',
      triggerType: TriggerType.battery,
      triggerValue: '20',
      comparisonOperator: ComparisonOperator.lte,
    ),
    Rule(
      reminderText: 'Charge reaches 80%',
      triggerType: TriggerType.battery,
      triggerValue: '80',
      comparisonOperator: ComparisonOperator.gte,
    ),
    Rule(
      reminderText: 'Connect to home Wi-Fi',
      triggerType: TriggerType.wifi,
      triggerValue: 'Home Wi-Fi',
      comparisonOperator: ComparisonOperator.eq,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Try a sample',
              style: GoogleFonts.inter(
                color: p.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Tap a card to drop a ready-made rule into this profile. '
              'You can edit, duplicate, or delete it from the home list.',
              style: GoogleFonts.inter(
                color: p.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < _samples.length; i++) ...[
            StaggeredFadeIn(
              // Header text first (60ms), then the three samples
              // stagger in 70ms apart.
              delayMs: 60 + (i * 70),
              child: _SampleRuleCard(
                sample: _samples[i],
                onTap: () => onPick(_samples[i]),
              ),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          Center(
            child: Text(
              '— or use the “New rule” button to build your own.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: p.textSecondary,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SampleRuleCard extends StatelessWidget {
  final Rule sample;
  final VoidCallback onTap;
  const _SampleRuleCard({required this.sample, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isBattery = sample.triggerType == TriggerType.battery;
    return _PressableCard(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isBattery
                        ? Icons.battery_alert_rounded
                        : Icons.wifi_rounded,
                    color: p.accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        sample.reminderText,
                        style: GoogleFonts.inter(
                          color: p.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${isBattery ? 'Battery' : 'Wi-Fi'} '
                        '${sample.comparisonOperator.displayLabel} '
                        '${sample.triggerValue}${isBattery ? '%' : ''}',
                        style: GoogleFonts.inter(
                          color: p.textSecondary,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.add_circle_rounded,
                  color: p.accent,
                  size: 26,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  final Rule rule;
  final IconData leadingIcon;
  final String subtitle;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTest;
  final VoidCallback onLongPress;

  const _RuleCard({
    required this.rule,
    required this.leadingIcon,
    required this.subtitle,
    required this.onToggle,
    required this.onTest,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bool on = rule.isEnabled;
    final bool cooling = rule.isWithinCooldown();

    return _PressableCard(
      onLongPress: onLongPress,
      onTap: () {
        // Tapping the card (outside the action buttons) does nothing
        // for now — the user has the play button, the toggle, and
        // long-press for the three meaningful actions. Future
        // expansion: quick stats, snooze, etc.
      },
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: on
                      ? p.accent.withValues(alpha: 0.18)
                      : p.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  leadingIcon,
                  color: on ? p.accent : p.textSecondary,
                  size: 24,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            rule.reminderText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: on ? p.textPrimary : p.textSecondary,
                                  fontWeight: FontWeight.w600,
                                  decoration: on
                                      ? null
                                      : TextDecoration.lineThrough,
                                ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _AlertTypeBadge(alertType: rule.alertType),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: p.textSecondary,
                      ),
                    ),
                    if (cooling) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.hourglass_top_rounded,
                            size: 12,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Cooldown — fired '
                            '${DateTime.now().difference(rule.lastFired).inMinutes}m ago',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.amber,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Test rule',
                onPressed: onTest,
                icon: Icon(
                  Icons.play_arrow_rounded,
                  color: p.accent,
                  size: 28,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: p.accent.withValues(alpha: 0.12),
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(8),
                ),
              ),
              const SizedBox(width: 4),
              Switch(
                value: on,
                onChanged: onToggle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Subtle press feedback: scales the child down to 0.98 on tap down
/// and back to 1.0 on tap up / cancel. Adds the "alive" feel of a
/// premium app without overpowering the existing Material ripples
/// inside the child (e.g. on the play button or the switch).
class _PressableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _PressableCard({
    required this.child,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<_PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<_PressableCard> {
  // 1.0 at rest, 0.98 on tap down. Animated via the framework's
  // implicit AnimatedScale widget so the change is a smooth ~120ms
  // transition.
  double _scale = 1.0;

  void _setPressed(bool pressed) {
    setState(() => _scale = pressed ? 0.98 : 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class _AlertTypeBadge extends StatelessWidget {
  final String alertType;
  const _AlertTypeBadge({required this.alertType});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bool isUrgent =
        AlertType.normalize(alertType) == AlertType.urgent;
    return Tooltip(
      message: isUrgent ? 'Urgent alarm' : 'Standard',
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: isUrgent
              ? const Color(0x33FFB74D)
              : p.surface,
          shape: BoxShape.circle,
          border: Border.all(
            color: isUrgent
                ? const Color(0xFFFFB74D)
                : p.textSecondary.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Icon(
          isUrgent
              ? Icons.notifications_active_rounded
              : Icons.notifications_rounded,
          size: 12,
          color: isUrgent
              ? const Color(0xFFFFC56F)
              : p.textSecondary,
        ),
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  final Alignment alignment;
  const _SwipeBackground({required this.alignment});

  @override
  Widget build(BuildContext context) {
    final isLeft = alignment == Alignment.centerLeft;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFCF4B4B),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isLeft) const SizedBox.shrink(),
          const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Text(
            'Delete',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          if (isLeft) const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _HomeOverflowMenu extends StatelessWidget {
  final VoidCallback onProfiles;
  final VoidCallback onSettings;

  const _HomeOverflowMenu({
    required this.onProfiles,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_HomeMenuAction>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (action) {
        switch (action) {
          case _HomeMenuAction.profiles:
            onProfiles();
            break;
          case _HomeMenuAction.settings:
            onSettings();
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem<_HomeMenuAction>(
          value: _HomeMenuAction.profiles,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.account_circle_outlined),
            title: Text('Profiles'),
            dense: true,
          ),
        ),
        const PopupMenuItem<_HomeMenuAction>(
          value: _HomeMenuAction.settings,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.tune_rounded),
            title: Text('Settings'),
            dense: true,
          ),
        ),
      ],
    );
  }
}

enum _HomeMenuAction { profiles, settings }

class _EditRuleDuplicate {
  const _EditRuleDuplicate();
}

class _EditRuleResult {
  final Rule? updated;
  const _EditRuleResult._({this.updated});

  factory _EditRuleResult.save(Rule updated) =>
      _EditRuleResult._(updated: updated);
}

class _FullEditRuleDialog extends StatefulWidget {
  final Rule initial;
  const _FullEditRuleDialog({required this.initial});

  @override
  State<_FullEditRuleDialog> createState() => _FullEditRuleDialogState();
}

class _FullEditRuleDialogState extends State<_FullEditRuleDialog> {
  late final TextEditingController _labelController;
  late final TextEditingController _valueController;
  final _formKey = GlobalKey<FormState>();
  late TriggerType _triggerType;
  late ComparisonOperator _comparison;
  late String _alertType;
  late bool _quietEnabled;
  late TimeOfDay _quietStart;
  late TimeOfDay _quietEnd;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.initial.reminderText);
    _valueController = TextEditingController(text: widget.initial.triggerValue);
    _triggerType = widget.initial.triggerType;
    _comparison = widget.initial.comparisonOperator;
    _alertType = widget.initial.alertType;
    final s = widget.initial.quietStartMinutes;
    final e = widget.initial.quietEndMinutes;
    _quietEnabled = s != null && e != null;
    _quietStart = s != null
        ? TimeOfDay(hour: s ~/ 60, minute: s % 60)
        : const TimeOfDay(hour: 22, minute: 0);
    _quietEnd = e != null
        ? TimeOfDay(hour: e ~/ 60, minute: e % 60)
        : const TimeOfDay(hour: 7, minute: 0);
  }

  @override
  void dispose() {
    _labelController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  List<ComparisonOperator> _opsFor(TriggerType t) {
    switch (t) {
      case TriggerType.battery:
        return const [
          ComparisonOperator.lt,
          ComparisonOperator.lte,
          ComparisonOperator.gt,
          ComparisonOperator.gte,
        ];
      case TriggerType.wifi:
        return const [ComparisonOperator.eq];
    }
  }

  String? _validateValue(String? raw) {
    final v = raw?.trim() ?? '';
    if (v.isEmpty) return 'Required';
    if (_triggerType == TriggerType.battery) {
      final n = int.tryParse(v);
      if (n == null) return 'Enter a number 0-100';
      if (n < 0 || n > 100) return 'Must be 0-100';
    } else {
      if (v.length > 64) return 'SSID is too long';
    }
    return null;
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final normalizedAlertType = AlertType.normalize(_alertType);
    final int? quietStart = _quietEnabled
        ? _quietStart.hour * 60 + _quietStart.minute
        : null;
    final int? quietEnd =
        _quietEnabled ? _quietEnd.hour * 60 + _quietEnd.minute : null;
    final updated = Rule(
      id: widget.initial.id,
      profileId: widget.initial.profileId,
      reminderText: _labelController.text.trim(),
      triggerType: _triggerType,
      triggerValue: _valueController.text.trim(),
      comparisonOperator: _comparison,
      isEnabled: widget.initial.isEnabled,
      lastFired: widget.initial.lastFired,
      alertType: normalizedAlertType,
      quietStartMinutes: quietStart,
      quietEndMinutes: quietEnd,
    );
    Navigator.of(context).pop(_EditRuleResult.save(updated));
  }

  Future<void> _pickQuietStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _quietStart,
      helpText: 'Quiet hours — start',
    );
    if (picked != null) {
      setState(() => _quietStart = picked);
    }
  }

  Future<void> _pickQuietEnd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _quietEnd,
      helpText: 'Quiet hours — end',
    );
    if (picked != null) {
      setState(() => _quietEnd = picked);
    }
  }

  ({IconData icon, String label}) _alertTypeMeta(String value) {
    switch (value) {
      case AlertType.urgent:
        return (
          icon: Icons.notifications_active_rounded,
          label: 'Urgent Alarm',
        );
      case AlertType.standard:
      default:
        return (
          icon: Icons.notifications_rounded,
          label: 'Standard',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isBattery = _triggerType == TriggerType.battery;
    final ops = _opsFor(_triggerType);
    if (!ops.contains(_comparison)) {
      _comparison = ops.first;
    }
    return AlertDialog(
      title: const Text('Edit rule'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _labelController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Reminder label',
                  hintText: 'e.g. Plug in before bed',
                ),
                textInputAction: TextInputAction.next,
                maxLength: 80,
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'Label cannot be empty';
                  return null;
                },
              ),
              const SizedBox(height: 4),
              Text(
                'Trigger',
                style: GoogleFonts.inter(
                  color: p.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final t in TriggerType.values)
                    ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            t == TriggerType.battery
                                ? Icons.battery_alert_rounded
                                : Icons.wifi_rounded,
                            size: 16,
                            color: _triggerType == t
                                ? const Color(0xFF1A1A1A)
                                : p.textPrimary,
                          ),
                          const SizedBox(width: 6),
                          Text(t == TriggerType.battery ? 'Battery' : 'Wi-Fi'),
                        ],
                      ),
                      selected: _triggerType == t,
                      onSelected: (_) => setState(() => _triggerType = t),
                      selectedColor: p.accent,
                      backgroundColor: p.surface,
                      labelStyle: TextStyle(
                        color: _triggerType == t
                            ? const Color(0xFF1A1A1A)
                            : p.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      shape: const StadiumBorder(),
                      side: BorderSide.none,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<ComparisonOperator>(
                      initialValue: _comparison,
                      decoration: const InputDecoration(
                        labelText: 'When',
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: [
                        for (final op in ops)
                          DropdownMenuItem(
                            value: op,
                            child: Text(
                              '${op.displaySymbol}  ${op.displayLabel}',
                            ),
                          ),
                      ],
                      onChanged: (op) {
                        if (op == null) return;
                        setState(() => _comparison = op);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 110,
                    child: TextFormField(
                      controller: _valueController,
                      keyboardType: isBattery
                          ? const TextInputType.numberWithOptions(
                              decimal: false, signed: false,
                            )
                          : TextInputType.text,
                      decoration: InputDecoration(
                        labelText: isBattery ? 'Threshold' : 'SSID',
                        suffixText: isBattery ? '%' : null,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                      validator: _validateValue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Alert type',
                style: GoogleFonts.inter(
                  color: p.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in AlertType.values)
                    () {
                      final meta = _alertTypeMeta(value);
                      final selected = _alertType == value;
                      return ChoiceChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              meta.icon,
                              size: 16,
                              color: selected
                                  ? const Color(0xFF1A1A1A)
                                  : p.textPrimary,
                            ),
                            const SizedBox(width: 6),
                            Text(meta.label),
                          ],
                        ),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => _alertType = value),
                        selectedColor: p.accent,
                        backgroundColor: p.surface,
                        labelStyle: TextStyle(
                          color: selected
                              ? const Color(0xFF1A1A1A)
                              : p.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        shape: const StadiumBorder(),
                        side: BorderSide.none,
                      );
                    }(),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Quiet hours',
                style: GoogleFonts.inter(
                  color: p.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                value: _quietEnabled,
                onChanged: (v) => setState(() => _quietEnabled = v),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Mute during these hours',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  _quietEnabled
                      ? 'Notifications will be suppressed in this window.'
                      : 'Off — rule will fire any time the trigger is met.',
                  style: TextStyle(
                      color: p.textSecondary, fontSize: 12, height: 1.3),
                ),
              ),
              if (_quietEnabled) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickQuietStart,
                        icon: const Icon(Icons.bedtime_outlined, size: 18),
                        label: Text('From ${_quietStart.format(context)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickQuietEnd,
                        icon: const Icon(Icons.wb_sunny_outlined, size: 18),
                        label: Text('Until ${_quietEnd.format(context)}'),
                      ),
                    ),
                  ],
                ),
                if (_quietStart.hour * 60 + _quietStart.minute >
                    _quietEnd.hour * 60 + _quietEnd.minute) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 14,
                        color: p.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Window crosses midnight.',
                          style: TextStyle(
                              color: p.textSecondary,
                              fontSize: 11,
                              fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            const _EditRuleDuplicate(),
          ),
          child: const Text('Duplicate'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}