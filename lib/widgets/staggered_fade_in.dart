// lib/widgets/staggered_fade_in.dart
//
// Tiny standalone animation primitive. On first render, the child
// fades in and slides up 20px, with a configurable per-instance delay
// so a list of these widgets renders as a smooth cascade.
//
// Used by the home list and the Recent activity screen. The widget
// is stateless from the caller's POV: rebuilds (e.g. when a rule's
// `lastFired` changes) do not re-run the animation because the key
// is the same.
import 'package:flutter/material.dart';

class StaggeredFadeIn extends StatefulWidget {
  final Widget child;
  final int delayMs;
  final Duration duration;

  const StaggeredFadeIn({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.duration = const Duration(milliseconds: 360),
  });

  @override
  State<StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<StaggeredFadeIn> {
  // Until the delay elapses, the child is rendered fully transparent
  // AND offset 20px down. Once [_start] flips, the TweenAnimationBuilder
  // animates from 0 -> 1 (so the user sees the slide-up + fade-in
  // smoothly). Without this two-state approach the tween would start
  // on the first frame regardless of [delayMs], defeating the
  // staggered cascade.
  bool _start = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) setState(() => _start = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_start) {
      // Pre-delay: invisible + offset. The child is still part of
      // the tree so layout matches the final state; we only offset
      // and hide it visually.
      return Opacity(
        opacity: 0,
        child: Transform.translate(
          offset: const Offset(0, 20),
          child: widget.child,
        ),
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - t)),
            child: child!,
          ),
        );
      },
      child: widget.child,
    );
  }
}