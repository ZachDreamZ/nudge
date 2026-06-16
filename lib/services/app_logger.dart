// lib/services/app_logger.dart
//
// Centralised logging facade. In release builds the calls are compiled
// out (via [kReleaseMode]) so nothing hits logcat or the developer
// console in shipped apps. In debug/profile builds messages are routed
// to the platform logger via `dart:developer.log`, which the IDE /
// `flutter logs` surface as nicely-formatted entries.
//
// The release-mode `return` is the privacy gate that keeps the "no
// telemetry, no cloud, no analytics" promise honest: even if a code
// path logs something that could conceivably be sensitive (a user's
// rule text, a Wi-Fi SSID, a permission decision), the call site
// cannot leak that data to the device log in a shipped app.
import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;

class AppLogger {
  AppLogger._();

  static void d(String message, {String tag = 'Nudge'}) {
    if (kReleaseMode) return;
    developer.log(message, name: tag, level: 500);
  }

  static void w(String message, {String tag = 'Nudge', Object? error}) {
    if (kReleaseMode) return;
    developer.log(message, name: tag, level: 900, error: error);
  }

  static void e(String message, {String tag = 'Nudge', Object? error, StackTrace? stack}) {
    if (kReleaseMode) return;
    developer.log(message, name: tag, level: 1000, error: error, stackTrace: stack);
  }
}