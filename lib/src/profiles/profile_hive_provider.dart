// lib/src/profiles/profile_hive_provider.dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'profile.dart';

class ProfileHiveProvider extends ValueNotifier<ProfileService> {
  ProfileHiveProvider(ProfileService value) : super(value) {
    // Forward every mutation on the underlying service to ValueNotifier
    // listeners (e.g. ValueListenableBuilder in the UI), so screens
    // refresh automatically when profiles are created/renamed/deleted or
    // when the active profile is changed.
    value.setOnChange(notifyListeners);
  }
}

Future<ProfileHiveProvider> initProfilesHive() async {
  // Hive is already initialised in main.dart; just open the box.
  final box = await Hive.openBox<String>('profiles');
  final service = ProfileService(box);
  await service.ensureDefaultProfile();
  return ProfileHiveProvider(service);
}