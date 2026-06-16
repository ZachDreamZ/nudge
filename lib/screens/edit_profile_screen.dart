// lib/screens/edit_profile_screen.dart
import 'package:flutter/material.dart';

import '../main.dart' show NudgePalette, NudgePaletteContext;
import '../src/profiles/profile.dart';
import '../src/profiles/profile_hive_provider.dart';

class EditProfileScreen extends StatefulWidget {
  final ProfileHiveProvider profilesProvider;
  final bool isNew;
  final Profile? existing;

  const EditProfileScreen({
    super.key,
    required this.profilesProvider,
    required this.isNew,
    this.existing,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _nameController;
  late int _iconIndex;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existing?.name ?? '',
    );
    _iconIndex = widget.existing?.iconIndex ?? 0;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name.')),
      );
      return;
    }
    Profile result;
    if (widget.isNew) {
      result = await widget.profilesProvider.value.create(
        name: name,
        iconIndex: _iconIndex,
      );
    } else {
      final existing = widget.existing!;
      await widget.profilesProvider.value.rename(existing.id, name);
      await widget.profilesProvider.value.setIcon(existing.id, _iconIndex);
      result = existing.copyWith(name: name, iconIndex: _iconIndex);
    }
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'New profile' : 'Edit profile'),
        titleSpacing: 20,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _Label(text: 'NAME', palette: p),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: TextStyle(color: p.textPrimary, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'e.g. Work, Travel, Gym',
              prefixIcon: Icon(
                Icons.label_outline,
                color: p.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 24),
          _Label(text: 'ICON', palette: p),
          const SizedBox(height: 12),
          _IconPickerGrid(
            selected: _iconIndex,
            onSelect: (i) => setState(() => _iconIndex = i),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded, size: 20),
            label: Text(widget.isNew ? 'Create profile' : 'Save changes'),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final NudgePalette palette;
  const _Label({required this.text, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          color: palette.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _IconPickerGrid extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;

  const _IconPickerGrid({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1,
      ),
      itemCount: kProfileIcons.length,
      itemBuilder: (context, index) {
        final isSelected = index == selected;
        return InkWell(
          onTap: () => onSelect(index),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? p.accent.withValues(alpha: 0.22)
                  : p.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? p.accent : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Icon(
              kProfileIcons[index],
              color: isSelected ? p.accent : p.textPrimary,
              size: 22,
            ),
          ),
        );
      },
    );
  }
}