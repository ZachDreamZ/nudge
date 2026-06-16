// lib/screens/onboarding_screen.dart
//
// Three-page introductory carousel shown on first launch.
//
// UX notes:
//   - Slide 3 (the rocket) gets a continuous gentle "bob" + scale on the
//     halo ring so it feels alive while the user reads it.
//   - Tapping "Get Started" triggers a one-shot lift-off animation
//     (translate up + scale up + fade out on icon and text) before we
//     persist `first_run_complete = true` in [SharedPreferences] and
//     invoke [OnboardingScreen.onComplete].
//   - Both the "Skip" / "Maybe later" button and the "Next" / "Get
//     Started" button are always visible. On the final slide the right
//     button swaps its label to "Get Started" and gains a leading
//     rocket icon.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ignore: unused_import
import '../main.dart' show NudgePaletteContext;
import '../services/app_logger.dart';

/// `SharedPreferences` key consulted by [main.dart] to decide whether to
/// show this screen. Exposed so it can be reset for QA or future "show
/// onboarding again" settings entry points.
const String kFirstRunCompleteKey = 'first_run_complete';

class OnboardingScreen extends StatefulWidget {
  /// Invoked after the user finishes (or skips) the flow. The host widget
  /// should swap the root to the real app shell.
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isFinishing = false;

  // Gentle up-and-down bob applied only on the final slide.
  late final AnimationController _bobController;
  // One-shot lift-off animation that runs when the user taps "Get Started".
  late final AnimationController _flyController;
  late final Animation<double> _flyProgress;

  static const List<_OnboardingPageData> _pages = [
    _OnboardingPageData(
      icon: Icons.notifications_active_rounded,
      title: 'Welcome to Nudge',
      description:
          'Smart, automatic reminders that fire exactly when you need them ? '
          'no setup, no clutter, just timely nudges.',
    ),
    _OnboardingPageData(
      icon: Icons.bolt_rounded,
      title: 'Set Your Triggers',
      description:
          'Nudge quietly watches your battery level and Wi-Fi status, so a '
          'reminder pops up only when the right condition is met.',
    ),
    _OnboardingPageData(
      icon: Icons.notifications_active_rounded,
      title: 'Choose Your Sound',
      description:
          'Each rule can fire as a Standard notification (your usual sound) '
          'or as an Urgent Alarm that plays even through silent mode. Long-press '
          'a rule to pick.',
    ),
    _OnboardingPageData(
      icon: Icons.rocket_launch_rounded,
      title: 'Get Started',
      description:
          'Create your first context-aware reminder and let Nudge handle '
          'the rest. Everything stays on your device — no cloud, no analytics.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _bobController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _flyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _flyProgress = CurvedAnimation(
      parent: _flyController,
      curve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _bobController.dispose();
    _flyController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    if (!mounted) return;
    setState(() => _currentPage = index);
  }

  void _next() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    if (_isFinishing) return;
    setState(() => _isFinishing = true);

    // Run the lift-off animation. We tolerate cancellation from a
    // widget unmount so we always reach the persistence step.
    try {
      await _flyController.forward();
    } catch (e) {
      AppLogger.w('Onboarding: fly-away animation interrupted.', error: e);
    }

    if (!mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kFirstRunCompleteKey, true);
      AppLogger.d('Onboarding complete: $kFirstRunCompleteKey=true.');
    } catch (e, st) {
      // Persistence is best-effort ? if SharedPreferences fails (extremely
      // unlikely) we still let the user into the app rather than trapping
      // them on the welcome screen forever.
      AppLogger.w(
        'Onboarding: failed to persist $kFirstRunCompleteKey.',
        error: e,
      );
      AppLogger.d('Stack: $st');
    }
    if (!mounted) return;
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isLast = _currentPage == _pages.length - 1;
    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) {
                  return _OnboardingPage(
                    data: _pages[index],
                    // Bob + halo only animate on the final slide so the
                    // user knows that's the "launch" slide.
                    bobController: index == _pages.length - 1
                        ? _bobController
                        : null,
                    flyProgress: _flyProgress,
                  );
                },
              ),
            ),
            _PageDots(count: _pages.length, current: _currentPage),
            _BottomBar(
              isLast: isLast,
              isFinishing: _isFinishing,
              onSkip: _finish,
              onNext: _next,
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPageData {
  final IconData icon;
  final String title;
  final String description;

  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.description,
  });
}

class _OnboardingPage extends StatelessWidget {
  final _OnboardingPageData data;
  // Null on slides 1-2; non-null on slide 3 so the rocket bobs.
  final AnimationController? bobController;
  // Always non-null; drives the lift-off on every slide so the fade is
  // uniform when the user finally taps Get Started.
  final Animation<double> flyProgress;

  const _OnboardingPage({
    required this.data,
    required this.bobController,
    required this.flyProgress,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final screenHeight = MediaQuery.of(context).size.height;

    // The icon: a tinted circle with a ring. The ring breathes (scales
    // gently) in sync with the bob on slide 3.
    Widget icon = SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Halo ring ? scales + fades with the bob animation when
          // present, otherwise sits static at scale 1.
          if (bobController != null)
            AnimatedBuilder(
              animation: bobController!,
              builder: (context, _) {
                final t = Curves.easeInOut.transform(bobController!.value);
                return Transform.scale(
                  scale: 1.0 + 0.12 * t,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: p.accent
                            .withValues(alpha: 0.18 + 0.22 * t),
                        width: 2,
                      ),
                    ),
                  ),
                );
              },
            )
          else
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: p.accent.withValues(alpha: 0.18),
                  width: 2,
                ),
              ),
            ),
          // Solid disc + icon.
          Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              color: p.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              data.icon,
              size: 72,
              color: p.accent,
            ),
          ),
        ],
      ),
    );

    // Bob: vertical translate when bobController is set.
    if (bobController != null) {
      icon = AnimatedBuilder(
        animation: bobController!,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(bobController!.value);
          return Transform.translate(
            offset: Offset(0, -10 * t),
            child: child,
          );
        },
        child: icon,
      );
    }

    // Fly-away: lift the icon off the top of the screen, scale it up,
    // and fade it out. Same animation runs on every slide so the
    // cross-fade to the home screen is consistent.
    icon = AnimatedBuilder(
      animation: flyProgress,
      builder: (context, child) {
        final t = flyProgress.value;
        final easedT = Curves.easeInCubic.transform(t);
        return Transform.translate(
          offset: Offset(0, -screenHeight * 0.6 * easedT),
          child: Transform.scale(
            scale: 1 + 0.6 * easedT,
            child: Opacity(
              opacity: (1 - easedT).clamp(0.0, 1.0),
              child: child,
            ),
          ),
        );
      },
      child: icon,
    );

    final textOpacity = (1 - flyProgress.value).clamp(0.0, 1.0);

    return Center(
      child: ConstrainedBox(
        // Caps the content width so the visual block stays balanced on
        // tablets and small phones alike. The icon, title, and body all
        // live inside the same 360 px column, so their horizontal
        // centres are perfectly aligned.
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              icon,
              const SizedBox(height: 40),
              Opacity(
                opacity: textOpacity,
                child: Text(
                  data.title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: p.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Opacity(
                opacity: textOpacity,
                child: Text(
                  data.description,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: p.textSecondary,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  final int count;
  final int current;

  const _PageDots({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (index) {
          final isActive = index == current;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 8,
            width: isActive ? 24 : 8,
            decoration: BoxDecoration(
              color: isActive ? p.accent : p.textSecondary,
              borderRadius: BorderRadius.circular(8),
            ),
          );
        }),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final bool isLast;
  final bool isFinishing;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  const _BottomBar({
    required this.isLast,
    required this.isFinishing,
    required this.onSkip,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Always-visible Skip / Maybe-later button. TextButton shrinks
          // to its intrinsic width and stays on the left.
          TextButton(
            onPressed: isFinishing ? null : onSkip,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              minimumSize: const Size(0, 48),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              isLast ? 'Maybe later' : 'Skip',
              style: GoogleFonts.inter(
                color: p.textSecondary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const Spacer(),
          // Primary action: explicit Size(0, 56) for height so the
          // theme's Size.fromHeight(56) (which expands to infinity wide)
          // doesn't blow out the Row layout on narrow phones.
          ElevatedButton(
            onPressed: isFinishing ? null : onNext,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 56),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              shape: const StadiumBorder(),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(isLast ? 'Get Started' : 'Next'),
                if (isLast) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 20),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}