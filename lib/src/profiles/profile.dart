// lib/src/profiles/profile.dart
//
// A Profile is a named bucket of rules. Every rule belongs to exactly one
// profile (the field is stamped on the rule at creation time). The "active"
// profile is whatever the user has selected in the home-screen chip strip
// and only its rules are shown there, but the background monitor evaluates
// all enabled rules across all profiles.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../rules/hive_rules.dart' show kDefaultProfileId;

/// 12 icons selectable for a profile. Adding more is safe; existing indexes
/// are preserved.
const List<IconData> kProfileIcons = <IconData>[
  Icons.person_rounded,
  Icons.home_rounded,
  Icons.work_rounded,
  Icons.flight_rounded,
  Icons.school_rounded,
  Icons.fitness_center_rounded,
  Icons.shopping_cart_rounded,
  Icons.restaurant_rounded,
  Icons.beach_access_rounded,
  Icons.local_hospital_rounded,
  Icons.pets_rounded,
  Icons.music_note_rounded,
];

class Profile {
  final String id;
  String name;
  int iconIndex;
  DateTime createdAt;

  Profile({
    required this.id,
    required this.name,
    required this.iconIndex,
    required this.createdAt,
  });

  IconData get icon {
    if (iconIndex < 0 || iconIndex >= kProfileIcons.length) {
      return kProfileIcons.first;
    }
    return kProfileIcons[iconIndex];
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'iconIndex': iconIndex,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String,
    name: json['name'] as String,
    iconIndex: (json['iconIndex'] as int?) ?? 0,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  Profile copyWith({String? name, int? iconIndex}) => Profile(
    id: id,
    name: name ?? this.name,
    iconIndex: iconIndex ?? this.iconIndex,
    createdAt: createdAt,
  );
}

/// Wraps the `profiles` Hive box. Stores one JSON-serialised [Profile] per
/// key, and tracks the active profile id under the special key
/// [activeProfileKey].
class ProfileService {
  static const String activeProfileKey = '__active__';

  final Box<String> _box;
  VoidCallback? _onChange;

  ProfileService(this._box);

  void setOnChange(VoidCallback? callback) {
    _onChange = callback;
  }

  void _notify() {
    final cb = _onChange;
    if (cb != null) cb();
  }

  /// Returns every profile, ordered by [Profile.createdAt].
  List<Profile> getAll() {
    final out = <Profile>[];
    for (final key in _box.keys) {
      if (key == activeProfileKey) continue;
      final raw = _box.get(key);
      if (raw == null) continue;
      try {
        out.add(Profile.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {
        // Skip malformed entries.
      }
    }
    out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  Profile? getById(String id) {
    final raw = _box.get(id);
    if (raw == null) return null;
    try {
      return Profile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(Profile profile) async {
    await _box.put(profile.id, jsonEncode(profile.toJson()));
    _notify();
  }

  /// Creates a new profile and persists it. Does NOT change the active
  /// profile — the caller decides whether to switch.
  Future<Profile> create({required String name, required int iconIndex}) async {
    final id = 'profile_${DateTime.now().microsecondsSinceEpoch}';
    final profile = Profile(
      id: id,
      name: name.trim().isEmpty ? 'Untitled' : name.trim(),
      iconIndex: iconIndex,
      createdAt: DateTime.now(),
    );
    await save(profile);
    return profile;
  }

  Future<void> rename(String id, String newName) async {
    final p = getById(id);
    if (p == null) return;
    await save(p.copyWith(name: newName.trim().isEmpty ? p.name : newName.trim()));
  }

  Future<void> setIcon(String id, int iconIndex) async {
    final p = getById(id);
    if (p == null) return;
    await save(p.copyWith(iconIndex: iconIndex));
  }

  Future<void> delete(String id) async {
    if (id == kDefaultProfileId) return; // can't delete the default
    await _box.delete(id);
    if (activeProfileId == id) {
      await setActiveProfileId(kDefaultProfileId);
    }
    _notify();
  }

  // ---------------------------------------------------------------------
  // Active profile
  // ---------------------------------------------------------------------

  String get activeProfileId {
    final raw = _box.get(activeProfileKey);
    if (raw == null || raw.isEmpty) return kDefaultProfileId;
    return raw;
  }

  Future<void> setActiveProfileId(String id) async {
    await _box.put(activeProfileKey, id);
    _notify();
  }

  Profile get activeProfile {
    return getById(activeProfileId) ??
        (throw StateError('Active profile "$activeProfileId" is missing from the box.'));
  }

  /// Wipes every profile (and the active-profile key) and re-creates
  /// the default [kDefaultProfileId] "Personal" profile. Used by the
  /// Settings → "Delete all data" flow (factory reset).
  Future<void> clearAll() async {
    await _box.clear();
    await ensureDefaultProfile();
    _notify();
  }

  /// First-launch bootstrap. Always makes sure the [kDefaultProfileId]
  /// "Personal" profile exists, and the active profile is set to it.
  Future<void> ensureDefaultProfile() async {
    if (getById(kDefaultProfileId) == null) {
      await save(Profile(
        id: kDefaultProfileId,
        name: 'Personal',
        iconIndex: 0,
        createdAt: DateTime.now(),
      ));
    }
    if (getById(activeProfileId) == null) {
      await setActiveProfileId(kDefaultProfileId);
    }
    _notify();
  }

  int get length => _box.length;
}