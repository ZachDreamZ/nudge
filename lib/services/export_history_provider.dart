// lib/services/export_history_provider.dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../src/profiles/export_record.dart';

class ExportHistoryProvider extends ValueNotifier<ExportHistoryService> {
  ExportHistoryProvider(ExportHistoryService value) : super(value) {
    value.setOnChange(notifyListeners);
  }
}

Future<ExportHistoryProvider> initExportHistory() async {
  final box = await Hive.openBox<String>('exports');
  final service = ExportHistoryService(box);
  return ExportHistoryProvider(service);
}