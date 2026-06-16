// test/quiet_hours_test.dart
//
// Unit tests for `Rule.isInQuietHours`. The helper gates the
// background worker, so an off-by-one in the time comparison would
// either spam the user with notifications at the wrong hour or
// silently drop them. Both ends of the edge case are exercised
// here.
//
// All tests use a synthetic [DateTime] so the assertion does not
// depend on the wall clock.
import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/src/rules/hive_rules.dart';

void main() {
  group('Rule.isInQuietHours', () {
    // Build a Rule with no quiet hours configured. isInQuietHours
    // must always return false so the worker never silently drops
    // a notification when the user has not opted in to quiet hours.
    test('returns false when quiet hours are not configured', () {
      final r = Rule(
        reminderText: 'Plug in before bed',
        triggerType: TriggerType.battery,
        triggerValue: '20',
      );
      expect(r.isInQuietHours(DateTime(2026, 6, 16, 12, 0)), isFalse);
      expect(r.isInQuietHours(DateTime(2026, 6, 16, 3, 0)), isFalse);
      expect(r.isInQuietHours(DateTime(2026, 6, 16, 23, 59)), isFalse);
    });

    // Same-day window (e.g. 13:00–14:00). The active range is
    // [start, end) — end is exclusive — so 14:00 exactly should
    // already be out of the window.
    test('honours a same-day window with an exclusive end', () {
      final r = Rule(
        reminderText: 't',
        triggerType: TriggerType.battery,
        triggerValue: '1',
        quietStartMinutes: 13 * 60,
        quietEndMinutes: 14 * 60,
      );
      expect(r.isInQuietHours(DateTime(2026, 6, 16, 12, 59)), isFalse);
      expect(r.isInQuietHours(DateTime(2026, 6, 16, 13, 0)), isTrue);
      expect(r.isInQuietHours(DateTime(2026, 6, 16, 13, 30)), isTrue);
      expect(r.isInQuietHours(DateTime(2026, 6, 16, 13, 59)), isTrue);
      // 14:00 exactly is the exclusive end — must NOT be in quiet hours.
      expect(r.isInQuietHours(DateTime(2026, 6, 16, 14, 0)), isFalse);
      expect(r.isInQuietHours(DateTime(2026, 6, 16, 14, 30)), isFalse);
    });

    // Window that crosses midnight (e.g. 23:00 → 07:00). The
    // active range is 23:00–23:59 and 00:00–06:59.
    test('honours a window that crosses midnight', () {
      final r = Rule(
        reminderText: 't',
        triggerType: TriggerType.battery,
        triggerValue: '1',
        quietStartMinutes: 23 * 60,
        quietEndMinutes: 7 * 60,
      );
      // Before the window.
      expect(r.isInQuietHours(DateTime(2026, 6, 16, 22, 59)), isFalse);
      // Inside the late-evening half.
      expect(r.isInQuietHours(DateTime(2026, 6, 16, 23, 0)), isTrue);
      expect(r.isInQuietHours(DateTime(2026, 6, 16, 23, 30)), isTrue);
      // Just past midnight.
      expect(r.isInQuietHours(DateTime(2026, 6, 17, 0, 0)), isTrue);
      expect(r.isInQuietHours(DateTime(2026, 6, 17, 6, 59)), isTrue);
      // 07:00 is the exclusive end.
      expect(r.isInQuietHours(DateTime(2026, 6, 17, 7, 0)), isFalse);
      expect(r.isInQuietHours(DateTime(2026, 6, 17, 12, 0)), isFalse);
    });

    // 1-minute window (start == end). The window is [start, end) so a
    // 1-minute window is actually zero minutes long. The model
    // should never report "in quiet hours" for that case, because
    // there is no real quiet period.
    test('treats start == end as no quiet hours', () {
      final r = Rule(
        reminderText: 't',
        triggerType: TriggerType.battery,
        triggerValue: '1',
        quietStartMinutes: 12 * 60,
        quietEndMinutes: 12 * 60,
      );
      expect(r.isInQuietHours(DateTime(2026, 6, 16, 12, 0)), isFalse);
      expect(r.isInQuietHours(DateTime(2026, 6, 16, 11, 59)), isFalse);
      expect(r.isInQuietHours(DateTime(2026, 6, 16, 12, 30)), isFalse);
    });

    // "Full-day" quiet hours via 00:00 → 00:00. Because the window
    // is half-open `[start, end)`, this is actually an empty window
    // — equivalent to "no quiet hours" in practice. The model is
    // honest about this: every minute falls outside the window.
    //
    // The UI prevents the user from setting 00:00 → 00:00 (the time
    // pickers round to the nearest minute and the model treats it as
    // empty), so this case is theoretical. The test pins the
    // behaviour so a future refactor cannot silently change it.
    test('00:00 → 00:00 is treated as an empty window', () {
      final r = Rule(
        reminderText: 't',
        triggerType: TriggerType.battery,
        triggerValue: '1',
        quietStartMinutes: 0,
        quietEndMinutes: 0,
      );
      // No minute in the day is in the window.
      expect(r.isInQuietHours(DateTime(2026, 6, 16, 0, 0)), isFalse);
      expect(r.isInQuietHours(DateTime(2026, 6, 16, 0, 1)), isFalse);
      expect(r.isInQuietHours(DateTime(2026, 6, 16, 12, 0)), isFalse);
      expect(r.isInQuietHours(DateTime(2026, 6, 16, 23, 59)), isFalse);
    });

    // The "largest possible" non-empty window is 00:00 → 23:59.
    // This is the closest a user can get to "all day" without the
    // boundary case. The 23:59 end is exclusive, so 23:59 is NOT
    // in the window — but every other minute is.
    test('00:00 → 23:59 is the largest non-empty window', () {
      final r = Rule(
        reminderText: 't',
        triggerType: TriggerType.battery,
        triggerValue: '1',
        quietStartMinutes: 0,
        quietEndMinutes: 23 * 60 + 59,
      );
      expect(r.isInQuietHours(DateTime(2026, 6, 16, 0, 0)), isTrue);
      expect(r.isInQuietHours(DateTime(2026, 6, 16, 12, 0)), isTrue);
      expect(r.isInQuietHours(DateTime(2026, 6, 16, 23, 58)), isTrue);
      // 23:59 is the exclusive end — NOT in the window.
      expect(r.isInQuietHours(DateTime(2026, 6, 16, 23, 59)), isFalse);
    });
  });

  group('Rule JSON round-trip', () {
    test('quietStartMinutes / quietEndMinutes survive toJson → fromJson', () {
      final original = Rule(
        reminderText: 't',
        triggerType: TriggerType.battery,
        triggerValue: '20',
        quietStartMinutes: 22 * 60 + 30,
        quietEndMinutes: 7 * 60,
      );
      final json = original.toJson();
      final restored = Rule.fromJson(json);
      expect(restored.quietStartMinutes, 1350);
      expect(restored.quietEndMinutes, 420);
      expect(restored.isInQuietHours(DateTime(2026, 6, 16, 3, 0)), isTrue);
      expect(restored.isInQuietHours(DateTime(2026, 6, 16, 12, 0)), isFalse);
    });

    test('null quiet hours round-trip cleanly', () {
      final original = Rule(
        reminderText: 't',
        triggerType: TriggerType.battery,
        triggerValue: '20',
      );
      final json = original.toJson();
      final restored = Rule.fromJson(json);
      expect(restored.quietStartMinutes, isNull);
      expect(restored.quietEndMinutes, isNull);
      expect(restored.isInQuietHours(DateTime(2026, 6, 16, 3, 0)), isFalse);
    });
  });

  group('AlertType', () {
    test('normalize always returns a whitelisted value', () {
      expect(AlertType.normalize(null), AlertType.standard);
      expect(AlertType.normalize(''), AlertType.standard);
      expect(AlertType.normalize('garbage'), AlertType.standard);
      expect(AlertType.normalize('default'), AlertType.standard);
      expect(AlertType.normalize('alarm'), AlertType.urgent);
      // Case-insensitive: backup files written by an older version
      // might use 'ALARM'.
      expect(AlertType.normalize('ALARM'), AlertType.urgent);
      expect(AlertType.normalize('Default'), AlertType.standard);
    });
  });
}