// lib/screens/recent_activity_screen.dart
//
// Reverse-chronological list of "what fired and when". Today this is
// backed by the per-rule `lastFired` timestamp (always present on
// every rule), sorted desc. A future iteration can promote the
// per-firing history to a dedicated `fire_log.json` file on the Java
// side and surface a richer view here; the screen contract (entries
// with `ruleId`, `ruleLabel`, `alertType`, `firedAt`) is already
// shaped to accept it without a UI rewrite.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart' show NudgePalette, NudgePaletteContext;
import '../services/app_logger.dart';
import '../src/profiles/profile_hive_provider.dart';
import '../src/rules/hive_rules.dart';
import '../src/rules/rules_hive_provider.dart';
import '../widgets/staggered_fade_in.dart';

class RecentActivityScreen extends StatelessWidget {
  final RulesHiveProvider rulesProvider;
  final ProfileHiveProvider profilesProvider;

  const RecentActivityScreen({
    super.key,
    required this.rulesProvider,
    required this.profilesProvider,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        title: const Text('Recent activity'),
        titleSpacing: 20,
      ),
      body: ValueListenableBuilder<RulesService>(
        valueListenable: rulesProvider,
        builder: (context, service, _) {
          final allRules = service.getAllRulesWithKeys()
            ..sort((a, b) => b.lastFired.compareTo(a.lastFired));
          // Only show rules that have actually fired. lastFired
          // defaults to DateTime(1970, 1, 1) in the model, so an
          // un-fired rule has a "year" of 1970 — we filter those out
          // so the user only sees real activity.
          final fired = allRules
              .where((r) => r.lastFired.year > 1970)
              .toList();
          AppLogger.d('Recent activity: ${fired.length} fired rule(s).');
          if (fired.isEmpty) {
            return _EmptyState(palette: p);
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            itemCount: fired.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final r = fired[index];
              final profile = profilesProvider.value.getById(r.profileId);
              // Cascade in. Cap the index at 8 so a 50-item log
              // doesn't drag the animation out past 1 second.
              final delayMs = (index.clamp(0, 8)) * 40;
              return StaggeredFadeIn(
                delayMs: delayMs,
                child: _ActivityCard(
                  rule: r,
                  profileName: profile?.name ?? 'Unknown profile',
                  palette: p,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final Rule rule;
  final String profileName;
  final NudgePalette palette;

  const _ActivityCard({
    required this.rule,
    required this.profileName,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            // Alert-type icon (bell vs. urgent bell). Mirrors the
            // _AlertTypeBadge in the home list, but slightly larger
            // so the Recent activity page reads at a glance.
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isUrgent
                    ? const Color(0x33FFB74D)
                    : palette.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isUrgent
                      ? const Color(0xFFFFB74D)
                      : palette.textSecondary.withValues(alpha: 0.4),
                ),
              ),
              child: Icon(
                isUrgent
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_rounded,
                size: 16,
                color: isUrgent
                    ? const Color(0xFFFFC56F)
                    : palette.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    rule.reminderText,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get isUrgent => AlertType.normalize(rule.alertType) == AlertType.urgent;

  String _subtitle() {
    final unit = rule.triggerType == TriggerType.battery ? '%' : '';
    final condition = '${rule.triggerType.displayName} '
        '${rule.comparisonOperator.displayLabel} '
        '${rule.triggerValue}$unit';
    final when = _formatRelative(rule.lastFired);
    return '$condition  ·  $when  ·  $profileName';
  }
}

/// Renders a past timestamp as a short human string. e.g. "2 min ago",
/// "3 hr ago", "yesterday", or a `MMM d, HH:mm` absolute date for
/// anything older than a day.
String _formatRelative(DateTime t) {
  final now = DateTime.now();
  final diff = now.difference(t);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  final yesterday = DateTime(now.year, now.month, now.day - 1);
  if (t.year == yesterday.year &&
      t.month == yesterday.month &&
      t.day == yesterday.day) {
    return 'yesterday';
  }
  // Older than yesterday — show a short absolute date + time.
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${months[t.month - 1]} ${t.day}, ${two(t.hour)}:${two(t.minute)}';
}

class _EmptyState extends StatelessWidget {
  final NudgePalette palette;
  const _EmptyState({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: palette.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: palette.accent.withValues(alpha: 0.18),
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.history_toggle_off_rounded,
                color: palette.accent,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No activity yet',
              style: GoogleFonts.inter(
                color: palette.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Once a rule fires, the timestamp will appear here. "
              "Quiet-hours suppressions are not shown — you'll only see "
              "the times Nudge actually delivered a reminder.",
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: palette.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}