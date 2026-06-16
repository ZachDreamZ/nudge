// lib/screens/about_screen.dart
//
// "About Nudge" — the canonical app-info page reachable from the
// Settings menu. Version string, copyright notice, and a Privacy
// Policy dialog. The page consumes no providers; it is a static
// informational surface.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart' show NudgePaletteContext;
import '../services/app_logger.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  // Public, semver-ish — bumped per release. Kept here (not in
  // pubspec) because the About screen is the source of truth the
  // user sees; the build.gradle versionName is a separate concern.
  static const String _appName = 'Nudge';
  static const String _version = '1.0.0';
  static const String _tagline =
      'Context-aware reminders that fire exactly when your phone hits '
      'the conditions you care about.';
  static const String _copyright =
      '\u00A9 2026 Nudge. All rights reserved.';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        title: const Text('About'),
        titleSpacing: 20,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              const _AppMark(),
              const SizedBox(height: 24),
              Text(
                _appName,
                style: GoogleFonts.inter(
                  color: p.textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'v$_version',
                style: GoogleFonts.inter(
                  color: p.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _tagline,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: p.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              const _SectionDivider(),
              const SizedBox(height: 16),
              _InfoRow(label: 'App', value: _appName),
              _InfoRow(label: 'Version', value: _version),
              _InfoRow(label: 'Engine', value: 'Flutter (Dart 3.12)'),
              _InfoRow(label: 'Platform', value: 'Android'),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showPrivacyPolicy(context),
                  icon: Icon(
                    Icons.privacy_tip_outlined,
                    color: p.accent,
                  ),
                  label: const Text('Privacy Policy'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.textPrimary,
                    side: BorderSide(
                      color: p.accent.withValues(alpha: 0.4),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const StadiumBorder(),
                    textStyle: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Text(
                _copyright,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: p.textSecondary,
                  fontSize: 11,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPrivacyPolicy(BuildContext context) {
    final p = context.palette;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: Icon(
            Icons.privacy_tip_outlined,
            color: p.accent,
            size: 32,
          ),
          title: const Text('Privacy & Data'),
          // Scrollable so the long-form policy doesn't overflow on small
          // phones. The body is a private widget that lays out the
          // policy as a series of small sections — easier to scan than
          // a wall of text.
          content: const SingleChildScrollView(
            child: _PrivacyPolicyBody(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Got it'),
            ),
          ],
        );
      },
    );
  }
}

/// The app "mark" — a tinted disc with a bolt icon. Mirrors the
/// `onboarding_screen.dart` hero pattern so the brand feels consistent
/// across the first-run and About surfaces.
class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: p.surface,
        shape: BoxShape.circle,
        border: Border.all(
          color: p.accent.withValues(alpha: 0.18),
          width: 2,
        ),
      ),
      child: Icon(
        Icons.bolt_rounded,
        size: 52,
        color: p.accent,
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: p.accent.withValues(alpha: 0.18),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: GoogleFonts.inter(
                color: p.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                color: p.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyPolicyBody extends StatelessWidget {
  const _PrivacyPolicyBody();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Short, plain-language statement. This is the first thing the
        // user reads; if they only read one paragraph, this is the
        // one that needs to land.
        const Text(
          'Nudge processes every rule and every reminder entirely on your '
          'device. There is no analytics, no telemetry, no remote sync, and '
          'no server-side component of any kind.',
          style: TextStyle(height: 1.4),
        ),
        const SizedBox(height: 16),
        // "What we store" — a labelled section that mirrors the
        // Play Console Data Safety form. Three local stores + one
        // onboarding flag. This is the table reviewers will look for.
        Text(
          'What we store on this device',
          style: GoogleFonts.inter(
            color: p.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        _StorageRow(
          icon: Icons.rule_rounded,
          title: 'Rules',
          detail:
              'The reminder rules you create (label, trigger, threshold, alert type, quiet hours, last-fired).',
        ),
        _StorageRow(
          icon: Icons.account_circle_outlined,
          title: 'Profiles',
          detail: 'The named buckets that group your rules.',
        ),
        _StorageRow(
          icon: Icons.history_rounded,
          title: 'Export history',
          detail:
              'The last 20 backup files you have shared, with timestamps.',
        ),
        _StorageRow(
          icon: Icons.check_circle_outline,
          title: 'Onboarding flag',
          detail:
              'A single boolean that suppresses the welcome carousel after the first launch.',
        ),
        const SizedBox(height: 14),
        // "What we do NOT do" — the trust statement. After the table
        // above, the contrast is intentional: "we keep X, we do not do
        // Y" mirrors how a privacy audit reads.
        Text(
          'What we do NOT do',
          style: GoogleFonts.inter(
            color: p.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'No analytics. No telemetry. No tracking. No ads. No account. '
          'No remote servers are contacted in normal operation. The only '
          'network surface is the system file picker during the "Import" '
          'flow, where you choose a backup file you previously exported — '
          'nothing is uploaded.',
          style: TextStyle(height: 1.4),
        ),
        const SizedBox(height: 14),
        // Permissions rationale. Reviewers care about this; users care
        // when a permission prompt appears. Honest copy that ties the
        // permission to the feature it enables.
        Text(
          'Permissions we ask for',
          style: GoogleFonts.inter(
            color: p.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          '• Notifications — required to show reminders.\n'
          '• Location (in use) — only when you create or edit a Wi-Fi rule '
          'on Android 8.0+, so the SSID can be read.\n'
          '• Battery-optimisation whitelist — only from the Settings tile, '
          'so the background worker keeps running.',
          style: TextStyle(height: 1.4),
        ),
        const SizedBox(height: 14),
        // Escape hatch. Explicitly tell the user how to wipe the data,
        // and remind them of the typed confirmation in Delete all data.
        Text(
          'How to delete your data',
          style: GoogleFonts.inter(
            color: p.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Settings → DATA & PRIVACY → Delete all data (you will be asked '
          'to type "DELETE" to confirm). Or uninstall the app. Or use '
          'Android Settings → Apps → Nudge → Storage → Clear data.',
          style: TextStyle(height: 1.4),
        ),
      ],
    );
  }
}

/// Compact one-line entry inside the "What we store" list. Each row
/// has an icon, a bold title, and a one-line plain-language detail.
class _StorageRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _StorageRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: p.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: p.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: GoogleFonts.inter(
                    color: p.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Public helper so other screens (e.g. the "Rate Nudge" overflow item)
/// can ask us to launch a feedback / contact URL. Currently unused on
/// this screen but exported for sibling reuse without re-importing
/// url_launcher. Logs and silently swallows failures (no `PlatformException`
/// in the user's face).
Future<bool> launchExternalUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    AppLogger.w('launchExternalUrl: invalid URL "$url"');
    return false;
  }
  try {
    if (!await canLaunchUrl(uri)) {
      AppLogger.w('launchExternalUrl: no handler for $url');
      return false;
    }
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e, st) {
    AppLogger.w('launchExternalUrl: failed for $url', error: e);
    AppLogger.d('Stack: $st');
    return false;
  }
}