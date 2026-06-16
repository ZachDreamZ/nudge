// lib/screens/profiles_screen.dart
import 'package:flutter/material.dart';
// ignore: unused_import
import '../main.dart' show NudgePaletteContext;
import '../src/profiles/profile.dart';
import '../src/profiles/profile_hive_provider.dart';
import '../src/rules/hive_rules.dart' show kDefaultProfileId;
import '../src/rules/rules_hive_provider.dart';
import 'edit_profile_screen.dart';

class ProfilesScreen extends StatelessWidget {
  final RulesHiveProvider rulesProvider;
  final ProfileHiveProvider profilesProvider;

  const ProfilesScreen({
    super.key,
    required this.rulesProvider,
    required this.profilesProvider,
  });

  Future<void> _createProfile(BuildContext context) async {
    final result = await Navigator.push<Profile>(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(
          profilesProvider: profilesProvider,
          isNew: true,
        ),
      ),
    );
    if (result != null) {
      // Make the freshly created profile active so the user lands on it.
      await profilesProvider.value.setActiveProfileId(result.id);
    }
  }

  Future<void> _confirmDelete(BuildContext context, Profile p) async {
    final ruleCount = rulesProvider.value
        .getRulesForProfile(p.id)
        .length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete profile?'),
        content: Text(
          ruleCount == 0
              ? '"${p.name}" will be deleted. This cannot be undone.'
              : '"${p.name}" has $ruleCount rule${ruleCount == 1 ? '' : 's'}. '
                  'Deleting the profile will also delete its rules. '
                  'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade400),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await rulesProvider.value.removeRulesForProfile(p.id);
    await profilesProvider.value.delete(p.id);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Profiles'),
      titleSpacing: 20,
    ),
    body: ValueListenableBuilder<ProfileService>(
      valueListenable: profilesProvider,
      builder: (context, service, _) {
        final profiles = service.getAll();
        final activeId = service.activeProfileId;
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
          itemCount: profiles.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            if (index == profiles.length) {
              return _NewProfileCard(onTap: () => _createProfile(context));
            }
            final p = profiles[index];
            final ruleCount = rulesProvider.value
                .getRulesForProfile(p.id)
                .length;
            return _ProfileCard(
              profile: p,
              isActive: p.id == activeId,
              isDefault: p.id == kDefaultProfileId,
              ruleCount: ruleCount,
              onTap: () async {
                await service.setActiveProfileId(p.id);
              },
              onEdit: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EditProfileScreen(
                    profilesProvider: profilesProvider,
                    isNew: false,
                    existing: p,
                  ),
                ),
              ),
              onDelete: () => _confirmDelete(context, p),
            );
          },
        );
      },
    ),
  );
}

class _ProfileCard extends StatelessWidget {
  final Profile profile;
  final bool isActive;
  final bool isDefault;
  final int ruleCount;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProfileCard({
    required this.profile,
    required this.isActive,
    required this.isDefault,
    required this.ruleCount,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isActive
                      ? p.accent.withValues(alpha: 0.18)
                      : p.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  profile.icon,
                  color: isActive ? p.accent : p.textSecondary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile.name,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: p.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isDefault) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: p.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Default',
                              style: TextStyle(
                                color: p.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                        if (isActive) ...[
                          const SizedBox(width: 8),
                           Icon(Icons.check_circle, size: 16, color: p.accent),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$ruleCount rule${ruleCount == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: p.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit',
                icon: Icon(Icons.edit_outlined, color: p.textSecondary),
                onPressed: onEdit,
              ),
              if (!isDefault)
                IconButton(
                  tooltip: 'Delete',
                  icon: Icon(Icons.delete_outline, color: p.textSecondary),
                  onPressed: onDelete,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewProfileCard extends StatelessWidget {
  final VoidCallback onTap;
  const _NewProfileCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Card(
      color: p.background,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: p.accent.withValues(alpha: 0.4),
          width: 1.2,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
               Icon(Icons.add_circle_outline, color: p.accent),
              const SizedBox(width: 10),
              Text(
                'New profile',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: p.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}