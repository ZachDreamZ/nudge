// lib/src/rules/rules_hive_provider.dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import './hive_rules.dart';

class RulesHiveProvider extends ValueNotifier<RulesService> {
  RulesHiveProvider(RulesService value) : super(value) {
    // Forward every mutation on the underlying service to ValueNotifier
    // listeners (e.g. ValueListenableBuilder in the UI), so screens
    // refresh automatically when rules are added/toggled/removed.
    value.setOnChange(notifyListeners);
  }
}

Future<RulesHiveProvider> initRulesHive() async {
  await Hive.initFlutter();
  final box = await Hive.openBox<String>('rules');
  final service = RulesService(box);
  return RulesHiveProvider(service);
}
