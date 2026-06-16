// lib/services/rule_backup_service.dart
//
// Local-only backup / restore of rules. The exported file is a versioned JSON
// document so the format can evolve without breaking older backups:
//
//   {
//     "app": "Nudge",
//     "formatVersion": 1,
//     "exportedAt": "<ISO-8601 timestamp>",
//     "profileName": "<optional>",
//     "ruleCount": 2,
//     "rules": [ { ...Rule.toJson()... }, ... ]
//   }
//
// On import the service validates the document, drops the incoming `id` field
// so each rule gets a fresh Hive key on the new device, and hands the
// resulting [Rule] objects back to the caller for persistence.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'app_logger.dart';
import '../src/profiles/export_record.dart';
import '../src/rules/hive_rules.dart';

/// Outcome of an [importFromFile] call.
class ImportResult {
  ImportResult({
    required this.imported,
    required this.skipped,
    required this.errors,
  });

  /// Number of rules successfully added to the local store.
  final int imported;

  /// Number of rules in the file that were skipped (e.g. duplicates).
  final int skipped;

  /// Human-readable error messages (e.g. invalid file, wrong app).
  final List<String> errors;

  bool get isSuccess => errors.isEmpty && imported > 0;
  bool get isEmpty => imported == 0 && skipped == 0 && errors.isEmpty;
}

class RuleBackupService {
  RuleBackupService._();

  static const String _appTag = 'Nudge';
  static const int _formatVersion = 1;

  // ---------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------

  /// Builds the JSON document for the supplied rules. Public for testing.
  static String buildExportJson(
    List<Rule> rules, {
    String? profileName,
  }) {
    final body = <String, dynamic>{
      'app': _appTag,
      'formatVersion': _formatVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      // ignore: use_null_aware_elements
      if (profileName != null) 'profileName': profileName,
      'ruleCount': rules.length,
      'rules': rules.map((r) => r.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(body);
  }

  /// Writes the supplied rules to a temp file and presents the system share
  /// sheet so the user can hand the file to another app (Bluetooth, email,
  /// Nearby Share, Files manager, …).
  ///
  /// If [history] is provided, the export is also recorded there for the
  /// "Recent backups" list in Settings.
  ///
  /// Returns the number of rules written, or `-1` if there was nothing to
  /// export / the share sheet could not be shown.
  static Future<int> exportAndShare(
    RulesService service, {
    ExportHistoryService? history,
    String? profileName,
  }) async {
    // If a profile name was supplied, only export that profile's rules.
    // Otherwise export every rule (all profiles).
    final List<Rule> rules = (profileName == null)
        ? service.getAllRulesWithKeys()
        : service
            .getAllRulesWithKeys()
            .where((r) => r.profileId == profileName)
            .toList();

    if (rules.isEmpty) {
      AppLogger.d('Export skipped: no rules to export.');
      return -1;
    }

    final json = buildExportJson(rules, profileName: profileName);
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-')
        .substring(0, 19);
    final fileName = 'nudge_rules_$stamp.json';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(json, flush: true);
    AppLogger.d('Exported ${rules.length} rule(s) to ${file.path}');

    final result = await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json', name: fileName)],
      text: 'Nudge rules backup (${rules.length} rule${rules.length == 1 ? '' : 's'})',
      subject: 'Nudge rules backup',
    );
    AppLogger.d('Share sheet result: ${result.raw}');

    if (history != null) {
      final size = await file.length();
      // ignore: discarded_futures
      history.add(ExportRecord(
        id: 'exp_${DateTime.now().microsecondsSinceEpoch}',
        filePath: file.path,
        fileName: fileName,
        exportedAt: DateTime.now(),
        ruleCount: rules.length,
        sizeBytes: size,
        label: profileName,
      ));
    }
    return rules.length;
  }

  // ---------------------------------------------------------------------
  // Import
  // ---------------------------------------------------------------------

  /// Opens the system file picker (via the native [MethodChannel] declared
  /// in `MainActivity.java`), lets the user choose a `.json` file, reads
  /// it, validates it, and (after dedup) inserts the rules into the
  /// supplied [RulesService]. Returns an [ImportResult] summarising what
  /// happened.
  static const MethodChannel _channel =
      MethodChannel('com.nudge.app/import');

  static Future<ImportResult> importFromFile(RulesService service) async {
    try {
      final dynamic raw = await _channel.invokeMethod<String>('pickFile');
      if (raw == null) {
        AppLogger.d('Import cancelled by user.');
        return ImportResult(imported: 0, skipped: 0, errors: const []);
      }
      final String contents = raw as String;
      return importFromJson(service, contents);
    } catch (e, st) {
      AppLogger.e('Import failed.', error: e, stack: st);
      return ImportResult(imported: 0, skipped: 0, errors: [e.toString()]);
    }
  }

  /// Parses a JSON string and inserts the rules into [service]. Public for
  /// testing / advanced callers who already have the bytes.
  static ImportResult importFromJson(RulesService service, String jsonString) {
    final errors = <String>[];
    final existing = service.getAllRulesWithKeys();

    Map<String, dynamic> doc;
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic>) {
        return ImportResult(
          imported: 0,
          skipped: 0,
          errors: const ['Backup file is not a valid Nudge document.'],
        );
      }
      doc = decoded;
    } catch (e) {
      return ImportResult(
        imported: 0,
        skipped: 0,
        errors: ['Backup file is not valid JSON: $e'],
      );
    }

    if (doc['app'] != _appTag) {
      return ImportResult(
        imported: 0,
        skipped: 0,
        errors: ['Backup file is for "${doc['app']}", not Nudge.'],
      );
    }

    final version = doc['formatVersion'];
    if (version is! int || version > _formatVersion) {
      return ImportResult(
        imported: 0,
        skipped: 0,
        errors: ['Backup file version $version is newer than this app supports.'],
      );
    }

    final rawRules = doc['rules'];
    if (rawRules is! List) {
      return ImportResult(
        imported: 0,
        skipped: 0,
        errors: const ['Backup file is missing the "rules" array.'],
      );
    }

    // Build a dedup fingerprint: (profileId, reminderText, triggerType,
    // comparison, triggerValue) — the same rule from another device or
    // profile should not be added twice.
    String fingerprint(Rule r) =>
        '${r.profileId}|${r.reminderText.trim().toLowerCase()}|'
        '${r.triggerType.jsonValue}|${r.comparisonOperator.jsonValue}|'
        '${r.triggerValue.trim().toLowerCase()}';

    final existingFingerprints = existing.map(fingerprint).toSet();

    int imported = 0;
    int skipped = 0;
    for (final raw in rawRules) {
      if (raw is! Map<String, dynamic>) {
        errors.add('Skipped a malformed rule entry.');
        skipped++;
        continue;
      }
      try {
        // Strip the incoming id so Hive assigns a fresh one.
        final cleaned = Map<String, dynamic>.from(raw)..remove('id');
        final rule = Rule.fromJson(cleaned);
        if (existingFingerprints.contains(fingerprint(rule))) {
          skipped++;
          continue;
        }
        // ignore: discarded_futures
        service.addRule(rule);
        existingFingerprints.add(fingerprint(rule));
        imported++;
      } catch (e) {
        errors.add('Skipped a rule that could not be parsed: $e');
        skipped++;
      }
    }

    AppLogger.d('Import finished: +$imported, skipped $skipped, errors ${errors.length}.');
    return ImportResult(imported: imported, skipped: skipped, errors: errors);
  }
}