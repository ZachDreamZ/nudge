// lib/src/rules/hive_rules.dart
import 'dart:convert';
import 'dart:ui' show VoidCallback;
import 'package:hive/hive.dart';

import '../../services/app_logger.dart';

/// ID of the "Personal" profile that's auto-created on first launch so that
/// existing users (and freshly installed ones) always have at least one
/// profile to land in.
const String kDefaultProfileId = 'profile_personal';

// Enums for rule trigger types (uppercase to match spec)
enum TriggerType {
  battery,
  wifi;

  String get displayName {
    switch (this) {
      case TriggerType.battery:
        return 'Battery Drops';
      case TriggerType.wifi:
        return 'Wi-Fi Connects To';
    }
  }

  /// Returns uppercase string for JSON serialization (e.g. "BATTERY", "WIFI")
  String get jsonValue => name.toUpperCase();
}

/// Comparison operators with user-friendly display
enum ComparisonOperator {
  lt,
  gt,
  eq,
  lte,
  gte;

  String get displaySymbol {
    switch (this) {
      case ComparisonOperator.lt:
        return '<';
      case ComparisonOperator.gt:
        return '>';
      case ComparisonOperator.eq:
        return '==';
      case ComparisonOperator.lte:
        return '<=';
      case ComparisonOperator.gte:
        return '>=';
    }
  }

  String get displayLabel {
    switch (this) {
      case ComparisonOperator.lt:
        return 'below';
      case ComparisonOperator.gt:
        return 'above';
      case ComparisonOperator.eq:
        return 'equal to';
      case ComparisonOperator.lte:
        return 'at or below';
      case ComparisonOperator.gte:
        return 'at or above';
    }
  }

  /// Returns the string for JSON serialization (e.g. "<=", ">=")
  String get jsonValue => displaySymbol;
}

/// Canonical alert types persisted on [Rule.alertType] and forwarded to
/// the native [MethodChannel] / notification channel router. New values
/// must be added here AND in `NotificationHelper.java` (`routeForAlertType`)
/// in lock-step.
class AlertType {
  /// Default OS notification sound. Goes through `nudge_default_channel`.
  static const String standard = 'default';

  /// Loud alarm ringtone. Goes through `nudge_alarm_channel` with
  /// `IMPORTANCE_HIGH`. Use sparingly — overrides the user's silent mode.
  static const String urgent = 'alarm';

  /// Whitelist of values accepted by the model. Anything else falls back
  /// to [standard] during [Rule.fromJson].
  static const List<String> values = <String>[standard, urgent];

  /// Defensive parser used by [Rule.fromJson] when round-tripping JSON
  /// from an older version of the app (or from a malformed backup file).
  static String normalize(String? raw) {
    if (raw == null) return standard;
    final lower = raw.toLowerCase();
    return values.contains(lower) ? lower : standard;
  }
}

class Rule {
  final int? id;

  /// ID of the [Profile] this rule belongs to. Defaults to the auto-created
  /// personal profile so old JSON / fresh constructions never produce an
  /// orphaned rule.
  String profileId;

  String reminderText;
  TriggerType triggerType;
  String triggerValue; // String to support both numeric (%) and text (SSID)
  ComparisonOperator comparisonOperator;
  bool isEnabled;
  DateTime lastFired;

  /// Which notification sound / channel to route to when this rule fires.
  /// Defaults to [AlertType.standard] for backward compatibility with
  /// rules written by older app versions that had no concept of alert
  /// type. Persisted as a plain string in JSON so it round-trips through
  /// backup files without needing a Hive TypeAdapter.
  String alertType;

  /// Minutes-since-midnight for the start of the quiet-hours window.
  /// `null` means "no quiet hours" (the default). When non-null,
  /// [quietEndMinutes] must also be set; the worker suppresses
  /// notifications (and logs the suppression to the fire log) when the
  /// current local time falls inside the window. Stored as a plain
  /// int (0-1439) for easy comparison on the Java side.
  int? quietStartMinutes;

  /// Minutes-since-midnight for the end of the quiet-hours window.
  /// The window is `[start, end)` — a 23:00 → 07:00 rule (start > end)
  /// is interpreted as wrapping midnight, so the active range is
  /// 23:00–23:59 + 00:00–06:59 inclusive.
  int? quietEndMinutes;

  Rule({
    this.id,
    String? profileId,
    required this.reminderText,
    required this.triggerType,
    required this.triggerValue,
    this.comparisonOperator = ComparisonOperator.lte,
    this.isEnabled = true,
    DateTime? lastFired,
    String? alertType,
    this.quietStartMinutes,
    this.quietEndMinutes,
  })  : profileId = profileId ?? kDefaultProfileId,
        lastFired = lastFired ?? DateTime(1970, 1, 1),
        alertType = AlertType.normalize(alertType);

  /// True if this rule fired within the last [cooldown] duration.
  /// Prevents spamming the user with repeated notifications.
  bool isWithinCooldown({Duration cooldown = const Duration(minutes: 5)}) {
    return DateTime.now().difference(lastFired) < cooldown;
  }

  /// True when quiet hours are configured AND the supplied [now] falls
  /// inside the configured window. Returns `false` if either bound is
  /// missing, so callers can use this as a simple "should I suppress?"
  /// guard. The window is `[start, end)` so a 23:00 → 07:00 rule
  /// (start > end) is interpreted as wrapping midnight.
  bool isInQuietHours([DateTime? now]) {
    final s = quietStartMinutes;
    final e = quietEndMinutes;
    if (s == null || e == null) return false;
    final t = now ?? DateTime.now();
    final minutes = t.hour * 60 + t.minute;
    if (s <= e) {
      return minutes >= s && minutes < e;
    }
    // Window wraps midnight (e.g. 23:00 → 07:00).
    return minutes >= s || minutes < e;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'profileId': profileId,
    'reminderText': reminderText,
    'triggerType': triggerType.jsonValue,
    'triggerValue': triggerValue,
    'comparisonOperator': comparisonOperator.jsonValue,
    'isEnabled': isEnabled,
    'lastFired': lastFired.toIso8601String(),
    'alertType': alertType,
    // null fields are intentionally emitted so an import that pre-dates
    // quiet hours can still deserialise without losing information.
    'quietStartMinutes': quietStartMinutes,
    'quietEndMinutes': quietEndMinutes,
  };

  factory Rule.fromJson(Map<String, dynamic> json, {int? id}) => Rule(
    id: id ?? json['id'] as int?,
    profileId: (json['profileId'] as String?) ?? kDefaultProfileId,
    reminderText: json['reminderText'] as String,
    triggerType: TriggerType.values.firstWhere(
      (e) => e.jsonValue == (json['triggerType'] as String).toUpperCase(),
    ),
    triggerValue: json['triggerValue'] as String,
    comparisonOperator: _parseOperator(json['comparisonOperator'] as String),
    isEnabled: json['isEnabled'] as bool? ?? true,
    lastFired: json['lastFired'] != null
        ? DateTime.parse(json['lastFired'] as String)
        : DateTime(1970, 1, 1),
    alertType: json['alertType'] as String?,
    quietStartMinutes: json['quietStartMinutes'] as int?,
    quietEndMinutes: json['quietEndMinutes'] as int?,
  );

  static ComparisonOperator _parseOperator(String op) {
    for (final e in ComparisonOperator.values) {
      if (e.jsonValue == op) return e;
    }
    return ComparisonOperator.lte; // safe default
  }
}

// Service class wrapping a Hive Box<String> storing JSON-encoded rules.
//
// All read methods that decode JSON ([getAllRules], [getAllRulesWithKeys],
// [getRule]) tolerate a single corrupt entry: they log + skip that
// entry instead of throwing. The mutation methods that decode then
// re-encode ([updateLastFired], [toggleEnabled], [updateRule],
// [duplicateRule]) are wrapped in try/catch so a corrupt entry never
// turns into an unhandled exception on the home screen.
class RulesService {
  final Box<String> _box;
  VoidCallback? _onChange;

  RulesService(this._box);

  /// Registers a callback to be invoked after any mutation (add, update,
  /// toggle, remove). Used by [RulesHiveProvider] to forward change events
  /// to listeners (e.g. UI rebuilds via [ValueListenableBuilder]).
  void setOnChange(VoidCallback? callback) {
    _onChange = callback;
  }

  void _notify() {
    final cb = _onChange;
    if (cb != null) cb();
  }

  /// Adds a rule to the default box. The rule's [Rule.profileId] decides
  /// which profile it lives under.
  Future<int> addRule(Rule rule) async {
    final json = jsonEncode(rule.toJson());
    final key = await _box.add(json);
    _notify();
    return key;
  }

  /// All rules (no Hive key on the model — use [getAllRulesWithKeys]
  /// if you need stable identity for navigation). Silently skips entries
  /// whose stored JSON is malformed (logged at warn level).
  List<Rule> getAllRules() {
    return _box.values
        .map((jsonStr) => _safeFromJson(jsonStr, null))
        .whereType<Rule>()
        .toList();
  }

  /// Returns rules with their Hive keys mapped to [Rule.id]. Silently
  /// skips entries whose stored JSON is malformed (logged at warn level).
  List<Rule> getAllRulesWithKeys() {
    final result = <Rule>[];
    for (final key in _box.keys) {
      final jsonStr = _box.get(key);
      if (jsonStr == null) continue;
      final r = _safeFromJson(jsonStr, key);
      if (r != null) result.add(r);
    }
    return result;
  }

  /// All rules for a given profile. Includes disabled ones.
  List<Rule> getRulesForProfile(String profileId) {
    return getAllRulesWithKeys()
        .where((r) => r.profileId == profileId)
        .toList();
  }

  /// Returns enabled rules matching the given [triggerType] across all
  /// profiles. The background monitor (native side) still fires for any
  /// enabled rule regardless of which profile it belongs to.
  List<Rule> getEnabledRulesByType(TriggerType type) {
    return getAllRulesWithKeys().where((rule) {
      return rule.triggerType == type && rule.isEnabled;
    }).toList();
  }

  /// Generic filtered query for rule management screens.
  List<Rule> getFilteredRules({TriggerType? type, bool? isEnabled, String? profileId}) {
    return getAllRulesWithKeys().where((rule) {
      if (type != null && rule.triggerType != type) return false;
      if (isEnabled != null && rule.isEnabled != isEnabled) return false;
      if (profileId != null && rule.profileId != profileId) return false;
      return true;
    }).toList();
  }

  /// Updates lastFired for the given [ruleId] and persists to Hive.
  /// Returns false if the rule is missing OR the stored JSON is
  /// unparseable. The latter is treated as "no such rule" rather
  /// than a hard exception so a single corrupted entry never takes
  /// the app down.
  Future<bool> updateLastFired(int ruleId) async {
    final jsonStr = _box.get(ruleId);
    if (jsonStr == null) return false;
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final rule = Rule.fromJson(map, id: ruleId);
      rule.lastFired = DateTime.now();
      await _box.put(ruleId, jsonEncode(rule.toJson()));
      _notify();
      return true;
    } catch (e, st) {
      AppLogger.w('RulesService.updateLastFired: corrupt entry id=$ruleId.',
          error: e);
      AppLogger.d('Stack: $st');
      return false;
    }
  }

  /// Toggles isEnabled for the given [ruleId]. Same parse-failure
  /// handling as [updateLastFired] above.
  Future<bool> toggleEnabled(int ruleId) async {
    final jsonStr = _box.get(ruleId);
    if (jsonStr == null) return false;
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final rule = Rule.fromJson(map, id: ruleId);
      rule.isEnabled = !rule.isEnabled;
      await _box.put(ruleId, jsonEncode(rule.toJson()));
      _notify();
      return rule.isEnabled;
    } catch (e, st) {
      AppLogger.w('RulesService.toggleEnabled: corrupt entry id=$ruleId.',
          error: e);
      AppLogger.d('Stack: $st');
      return false;
    }
  }

  Future<bool> removeRule(int ruleId) async {
    await _box.delete(ruleId);
    _notify();
    return true;
  }

  /// Re-inserts a previously deleted rule under the SAME Hive key.
  /// Used by the "Undo" action on the home-screen swipe-to-delete
  /// SnackBar so the rule keeps its original id (and therefore its
  /// position / cooldown timestamps) when restored.
  Future<int?> restoreRule(Rule rule) async {
    final id = rule.id;
    if (id == null) return null;
    await _box.put(id, jsonEncode(rule.toJson()));
    _notify();
    return id;
  }

  /// Generic update-by-id helper. [mutate] is called with the current
  /// rule (re-hydrated from the stored JSON) and must return the new
  /// shape. The result is written back to the same Hive key. Returns
  /// `true` if a row was updated. Returns `false` on missing or
  /// unparseable JSON so the home-screen edit flow can surface a
  /// SnackBar without a crash.
  Future<bool> updateRule(int ruleId, Rule Function(Rule rule) mutate) async {
    final jsonStr = _box.get(ruleId);
    if (jsonStr == null) return false;
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final current = Rule.fromJson(map, id: ruleId);
      final updated = mutate(current);
      await _box.put(ruleId, jsonEncode(updated.toJson()));
      _notify();
      return true;
    } catch (e, st) {
      AppLogger.w('RulesService.updateRule: corrupt entry id=$ruleId.',
          error: e);
      AppLogger.d('Stack: $st');
      return false;
    }
  }

  /// Duplicates a rule, offsetting the trigger value so the copy fires
  /// at a slightly different threshold — useful for "graduated
  /// reminders" (e.g. warn at 30 % battery AND at 20 % battery). Returns
  /// the new rule's Hive key, or `null` if the source rule was missing
  /// OR unparseable.
  ///
  /// Offsets:
  ///   - battery: +5 % (capped at 100)
  ///   - wifi:    append " 2G" to the SSID (cheap, human-friendly)
  Future<int?> duplicateRule(int ruleId) async {
    Rule? original;
    try {
      original = getRule(ruleId);
    } catch (e, st) {
      AppLogger.w('RulesService.duplicateRule: corrupt source id=$ruleId.',
          error: e);
      AppLogger.d('Stack: $st');
      return null;
    }
    if (original == null) return null;
    String newLabel = '${original.reminderText} (copy)';
    String newTrigger = original.triggerValue;
    if (original.triggerType == TriggerType.battery) {
      final v = int.tryParse(original.triggerValue.trim());
      if (v != null) {
        newTrigger = (v + 5).clamp(0, 100).toString();
      } else {
        newTrigger = original.triggerValue;
      }
    } else {
      // Wi-Fi: nudge the SSID so it doesn't collide with the original.
      newTrigger = '${original.triggerValue} 2G';
    }
    final copy = Rule(
      profileId: original.profileId,
      reminderText: newLabel,
      triggerType: original.triggerType,
      triggerValue: newTrigger,
      comparisonOperator: original.comparisonOperator,
      isEnabled: original.isEnabled,
      lastFired: DateTime(1970, 1, 1),
      alertType: original.alertType,
      // The duplicate copies the quiet-hours window of the source
      // (e.g. useful for "warn 20 % AND 30 % after 11 PM"). If the
      // user wants a different window they can edit the copy.
      quietStartMinutes: original.quietStartMinutes,
      quietEndMinutes: original.quietEndMinutes,
    );
    return addRule(copy);
  }

  /// Wipes every rule from the box. Used by the Settings → "Delete all
  /// data" flow (factory reset). After this call the box is empty and
  /// the home list renders an empty state on the next rebuild.
  Future<void> clearAll() async {
    await _box.clear();
    _notify();
  }

  /// Removes all rules that belong to a given profile. Used by the profile
  /// delete flow.
  Future<int> removeRulesForProfile(String profileId) async {
    final ids = <dynamic>[];
    for (final key in _box.keys) {
      final jsonStr = _box.get(key);
      if (jsonStr == null) continue;
      try {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        if ((map['profileId'] as String?) == profileId) {
          ids.add(key);
        }
      } catch (_) {
        // Skip malformed entries.
      }
    }
    if (ids.isNotEmpty) {
      await _box.deleteAll(ids);
      _notify();
    }
    return ids.length;
  }

  /// On first launch, existing rules (saved by an older app version) have no
  /// [Rule.profileId]. This migration walks every entry and stamps it with
  /// [kDefaultProfileId]. Returns the number of rules rewritten.
  Future<int> migrateLegacyRulesToDefaultProfile() async {
    int rewritten = 0;
    for (final key in _box.keys.toList()) {
      final jsonStr = _box.get(key);
      if (jsonStr == null) continue;
      try {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        if (map['profileId'] is! String) {
          map['profileId'] = kDefaultProfileId;
          await _box.put(key, jsonEncode(map));
          rewritten++;
        }
      } catch (_) {
        // Skip malformed entries; they will be re-imported on next manual import.
      }
    }
    if (rewritten > 0) _notify();
    return rewritten;
  }

  /// Single-rule lookup. Returns `null` if the entry is missing or its
  /// stored JSON is unparseable (logged at warn level). Callers that
  /// do not need to distinguish "missing" from "corrupt" can treat
  /// both as "no such rule" by checking for null.
  Rule? getRule(int ruleId) {
    final jsonStr = _box.get(ruleId);
    if (jsonStr == null) return null;
    return _safeFromJson(jsonStr, ruleId);
  }

  int get length => _box.length;

  /// Decode-and-parse a stored rule JSON. Returns `null` on any
  /// failure (FormatException, type cast error, missing required
  /// fields). The call site decides what to do with the null; in
  /// practice the public read methods log + skip, the public mutation
  /// methods log + return false.
  Rule? _safeFromJson(String jsonStr, int? id) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return Rule.fromJson(map, id: id);
    } catch (e, st) {
      AppLogger.w(
        'RulesService: skipping unparseable rule${id == null ? '' : ' id=$id'}.',
        error: e,
      );
      AppLogger.d('Stack: $st');
      return null;
    }
  }
}
