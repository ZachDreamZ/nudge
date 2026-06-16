// lib/main.dart — Flutter App Entry Point with MethodChannel bridge
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/app_logger.dart';
import 'services/export_history_provider.dart';
import 'services/permission_service.dart';
import 'src/profiles/profile_hive_provider.dart';
import 'src/rules/hive_rules.dart';
import 'src/rules/rules_hive_provider.dart';

// MethodChannel for Dart → Java rule sync.
// Must match the channel name declared in MainActivity.java.
const MethodChannel _channel = MethodChannel('com.nudge.app/rules');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.d('Boot: initialising Hive and loading rules + profiles.');

  final rulesProvider = await initRulesHive();

  // Stamp the personal profile id on any pre-profile rules (older app
  // versions never wrote `profileId`). This is a one-time no-op on
  // subsequent launches.
  final migrated = await rulesProvider.value.migrateLegacyRulesToDefaultProfile();
  if (migrated > 0) {
    AppLogger.d('Migration: stamped $migrated legacy rule(s) with the default profile.');
  }

  final profilesProvider = await initProfilesHive();
  final exportHistory = await initExportHistory();

  // Read the first-run flag up front so the very first frame we paint is
  // the correct one (onboarding vs. home). We never block the cold start
  // for long here — SharedPreferences is a quick in-process read.
  bool firstRunComplete = false;
  try {
    final prefs = await SharedPreferences.getInstance();
    firstRunComplete = prefs.getBool(kFirstRunCompleteKey) ?? false;
    AppLogger.d('Boot: first_run_complete=$firstRunComplete');
  } catch (e, st) {
    AppLogger.w('Boot: failed to read $kFirstRunCompleteKey.', error: e);
    AppLogger.d('Stack: $st');
  }

  // Push rule changes to the native side so WorkManager + broadcast
  // receivers can evaluate them in the background.
  rulesProvider.addListener(() => _syncRulesToNative(rulesProvider.value));
  // Initial sync on cold start.
  _syncRulesToNative(rulesProvider.value);

  // Surface the OS permission dialogs on first launch. Fire-and-forget so
  // the home screen renders immediately; the dialogs appear on top.
  // ignore: unawaited_futures
  PermissionService.checkAndRequestInitial();

  runApp(SmartReminderApp(
    rulesProvider: rulesProvider,
    profilesProvider: profilesProvider,
    exportHistory: exportHistory,
    initialFirstRunComplete: firstRunComplete,
  ));
}

/// Pushes all rules as a JSON array to the native Android side via
/// [MethodChannel]. Failures are logged but do not crash the app — the
/// foreground UI keeps working even if the engine hasn't bound the
/// channel yet (e.g. during hot reload or very early startup).
void _syncRulesToNative(RulesService service) {
  try {
    final rules = service.getAllRulesWithKeys();
    final rulesJson = rules.map((r) => r.toJson()).toList();
    _channel.invokeMethod('syncRules', {'rules': rulesJson});
    AppLogger.d('Synced ${rules.length} rule(s) to native side.');
  } catch (e, st) {
    AppLogger.w('MethodChannel sync skipped.', error: e);
    AppLogger.d('Stack: $st');
  }
}

// ---------------------------------------------------------------------------
// Brand palette
// ---------------------------------------------------------------------------

/// Dark-theme brand constants (the original Nudge palette).
/// Light-theme variants live in [AppColorsLight].
class AppColors {
  static const Color background = Color(0xFF121212);   // deep dark gray
  static const Color surface = Color(0xFF1E1E2C);      // elevated surface (dark blue-gray)
  static const Color accent = Color(0xFFBB86FC);       // vibrant purple
  static const Color accentSecondary = Color(0xFF9C6FE3); // deeper purple for pressed states
  static const Color textPrimary = Color(0xFFEDEDED);   // near-white
  static const Color textSecondary = Color(0xFFA0A0B0); // muted grey
}

/// Light-theme brand constants. Sibling of [AppColors] — both palettes
/// share the same accent so the brand identity is consistent.
class AppColorsLight {
  static const Color background = Color(0xFFF7F7FA);   // off-white
  static const Color surface = Color(0xFFFFFFFF);      // pure white card
  static const Color accent = AppColors.accent;       // same vibrant purple
  static const Color textPrimary = Color(0xFF1A1A1A);   // near-black
  static const Color textSecondary = Color(0xFF6B6B7B); // muted gray
}

/// Brightness-aware palette picker. Use this from screens instead of
/// hard-coding [AppColors] (which is the dark-only palette) or doing a
/// `Theme.of(context).brightness == Brightness.dark ? AppColors : AppColorsLight`
/// ternary at every call site.
///
/// The shared `accent` is the same brand purple in both modes so accents
/// (FAB, focus ring, branded buttons) feel identical across the OS theme.
class NudgePalette {
  final Color background;
  final Color surface;
  final Color accent;
  final Color accentSecondary;
  final Color textPrimary;
  final Color textSecondary;

  const NudgePalette({
    required this.background,
    required this.surface,
    required this.accent,
    required this.accentSecondary,
    required this.textPrimary,
    required this.textSecondary,
  });

  /// Returns the palette that matches the current [BuildContext] theme.
  /// Use `context.palette` (the extension below) for the call-site shorthand.
  factory NudgePalette.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? NudgePalette.dark : NudgePalette.light;
  }

  static const _dark = NudgePalette(
    background: AppColors.background,
    surface: AppColors.surface,
    accent: AppColors.accent,
    accentSecondary: AppColors.accentSecondary,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
  );
  static const _light = NudgePalette(
    background: AppColorsLight.background,
    surface: AppColorsLight.surface,
    accent: AppColorsLight.accent,
    accentSecondary: AppColors.accentSecondary, // purple reads on both surfaces
    textPrimary: AppColorsLight.textPrimary,
    textSecondary: AppColorsLight.textSecondary,
  );

  /// Shared singleton — cheap const access, no const-constructor allocation.
  static NudgePalette get dark => _dark;
  static NudgePalette get light => _light;
}

/// Ergonomic call-site shorthand: `context.palette.surface`, etc.
extension NudgePaletteContext on BuildContext {
  NudgePalette get palette => NudgePalette.of(this);
}

class SmartReminderApp extends StatefulWidget {
  final RulesHiveProvider rulesProvider;
  final ProfileHiveProvider profilesProvider;
  final ExportHistoryProvider exportHistory;

  /// Whether the user has already finished the onboarding flow. We store
  /// this on first build so we can swap the root widget without flashing
  /// the wrong screen.
  final bool initialFirstRunComplete;

  const SmartReminderApp({
    super.key,
    required this.rulesProvider,
    required this.profilesProvider,
    required this.exportHistory,
    required this.initialFirstRunComplete,
  });

  @override
  State<SmartReminderApp> createState() => _SmartReminderAppState();
}

class _SmartReminderAppState extends State<SmartReminderApp> {
  /// Flipped by [OnboardingScreen] once the user finishes the flow.
  late bool _onboardingComplete;

  @override
  void initState() {
    super.initState();
    _onboardingComplete = widget.initialFirstRunComplete;
  }

  void _handleOnboardingComplete() {
    if (!mounted) return;
    setState(() => _onboardingComplete = true);
  }

  @override
  Widget build(BuildContext context) {
    final Widget home = _onboardingComplete
        ? HomeScreen(
            provider: widget.rulesProvider,
            profilesProvider: widget.profilesProvider,
            exportHistory: widget.exportHistory,
          )
        : OnboardingScreen(onComplete: _handleOnboardingComplete);

    return MaterialApp(
      title: 'Nudge',
      debugShowCheckedModeBanner: false,
      // Both themes are pre-built so the first frame already uses the
      // right palette (no flash of unstyled content when the OS theme
      // differs from the previous session's mode).
      theme: _buildNudgeTheme(Brightness.light),
      darkTheme: _buildNudgeTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: home,
    );
  }
}

/// Builds the Nudge [ThemeData] for the supplied [brightness]. Both light
/// and dark themes share the brand purple accent and identical component
/// shapes; only the surface + text colours swap.
ThemeData _buildNudgeTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final background = isDark ? AppColors.background : AppColorsLight.background;
  final surface = isDark ? AppColors.surface : AppColorsLight.surface;
  final textPrimary =
      isDark ? AppColors.textPrimary : AppColorsLight.textPrimary;
  final textSecondary =
      isDark ? AppColors.textSecondary : AppColorsLight.textSecondary;

  // Dark on accent in dark mode (the existing look) and white-ish on
  // accent in light mode — purple is dark enough to keep its contrast
  // in either direction.
  final onAccent = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFFFFFF);

  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: brightness,
  ).copyWith(
    primary: AppColors.accent,
    secondary: AppColors.accent,
    surface: surface,
    onPrimary: onAccent,
    onSurface: textPrimary,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: background,
    colorScheme: colorScheme,
    primaryColor: AppColors.accent,
    textTheme: GoogleFonts.interTextTheme(
      ThemeData(brightness: brightness).textTheme,
    ).apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.inter(
        textStyle: TextStyle(
          color: textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
      ),
      iconTheme: IconThemeData(color: textPrimary),
      actionsIconTheme: IconThemeData(color: textPrimary),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: onAccent,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: onAccent,
        minimumSize: const Size.fromHeight(56),
        shape: const StadiumBorder(),
        textStyle: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: textPrimary,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.accent, width: 2),
      ),
      labelStyle: GoogleFonts.inter(color: textSecondary),
      hintStyle: GoogleFonts.inter(color: textSecondary),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color>(
        (Set<WidgetState> states) => states.contains(WidgetState.selected)
            ? onAccent
            : textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith<Color>(
        (Set<WidgetState> states) => states.contains(WidgetState.selected)
            ? AppColors.accent.withValues(alpha: 0.5)
            : surface,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      titleTextStyle: GoogleFonts.inter(
        color: textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: GoogleFonts.inter(
        color: textPrimary,
        fontSize: 15,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: surface,
      contentTextStyle: GoogleFonts.inter(color: textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: GoogleFonts.inter(color: textPrimary, fontSize: 14),
    ),
  );
}