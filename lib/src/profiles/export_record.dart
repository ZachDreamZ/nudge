// lib/src/profiles/export_record.dart
import 'dart:convert';
import 'dart:ui' show VoidCallback;

import 'package:hive/hive.dart';

/// Persisted record of a single export. Stored in the `exports` Hive box,
/// keyed by the export's [id].
class ExportRecord {
  final String id;
  final String filePath;
  final String fileName;
  final DateTime exportedAt;
  final int ruleCount;
  final int sizeBytes;
  final String? label;

  ExportRecord({
    required this.id,
    required this.filePath,
    required this.fileName,
    required this.exportedAt,
    required this.ruleCount,
    required this.sizeBytes,
    this.label,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'filePath': filePath,
    'fileName': fileName,
    'exportedAt': exportedAt.toIso8601String(),
    'ruleCount': ruleCount,
    'sizeBytes': sizeBytes,
    'label': label,
  };

  factory ExportRecord.fromJson(Map<String, dynamic> json) => ExportRecord(
    id: json['id'] as String,
    filePath: json['filePath'] as String,
    fileName: json['fileName'] as String,
    exportedAt: DateTime.parse(json['exportedAt'] as String),
    ruleCount: (json['ruleCount'] as int?) ?? 0,
    sizeBytes: (json['sizeBytes'] as int?) ?? 0,
    label: json['label'] as String?,
  );
}

/// Bounded list of recent exports. The list is capped at [maxRecords] (default
/// 20) and old entries are evicted FIFO when the cap is exceeded.
class ExportHistoryService {
  static const int maxRecords = 20;

  final Box<String> _box;
  VoidCallback? _onChange;

  ExportHistoryService(this._box);

  void setOnChange(VoidCallback? callback) {
    _onChange = callback;
  }

  void _notify() {
    final cb = _onChange;
    if (cb != null) cb();
  }

  /// Most-recent-first list of saved exports.
  List<ExportRecord> getAll() {
    final out = <ExportRecord>[];
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw == null) continue;
      try {
        out.add(ExportRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {
        // Skip malformed entries.
      }
    }
    out.sort((a, b) => b.exportedAt.compareTo(a.exportedAt));
    return out;
  }

  Future<void> add(ExportRecord record) async {
    await _box.put(record.id, jsonEncode(record.toJson()));
    await _enforceCap();
    _notify();
  }

  Future<void> delete(String id) async {
    await _box.delete(id);
    _notify();
  }

  Future<void> clearAll() async {
    await _box.clear();
    _notify();
  }

  Future<void> _enforceCap() async {
    final all = getAll();
    if (all.length <= maxRecords) return;
    final toRemove = all.sublist(maxRecords);
    final keys = toRemove.map((e) => e.id).toList();
    await _box.deleteAll(keys);
  }

  int get length => _box.length;
}