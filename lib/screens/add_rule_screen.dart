// lib/screens/add_rule_screen.dart
import 'package:flutter/material.dart';

import '../main.dart' show NudgePalette, NudgePaletteContext;
import '../services/app_logger.dart';
import '../services/permission_service.dart';
import '../src/rules/hive_rules.dart';
import '../src/rules/rules_hive_provider.dart';

class AddRuleScreen extends StatefulWidget {
  final RulesHiveProvider provider;

  /// The profile this new rule should be saved into. Typically the active
  /// profile selected on the home screen.
  final String activeProfileId;

  const AddRuleScreen({
    super.key,
    required this.provider,
    required this.activeProfileId,
  });

  @override
  State<AddRuleScreen> createState() => _AddRuleScreenState();
}

class _AddRuleScreenState extends State<AddRuleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reminderController = TextEditingController();
  final _thresholdController = TextEditingController();

  TriggerType _triggerType = TriggerType.battery;
  ComparisonOperator _comparisonOperator = ComparisonOperator.lte;
  bool _isEnabled = true;
  // Defaults to Standard; if the user picks Urgent Alarm here the value
  // is forwarded into the Hive box and then to the native channel.
  String _alertType = AlertType.standard;
  // Quiet hours default to off. The two `TimeOfDay` fields are only
  // persisted when the user toggles the switch on.
  bool _quietEnabled = false;
  TimeOfDay _quietStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _quietEnd = const TimeOfDay(hour: 7, minute: 0);

  @override
  void dispose() {
    _reminderController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  Future<void> _saveRule() async {
    if (!_formKey.currentState!.validate()) return;

    final reminderText = _reminderController.text.trim();
    if (reminderText.isEmpty) return;

    // Step 2 of the "Double-Ask" permission flow — ensure the user has
    // granted POST_NOTIFICATIONS before persisting the rule. If denied, an
    // in-app dialog will guide them to the system settings. The rule is
    // NOT saved until the permission is granted, since a saved rule
    // without a working notification channel would silently fail when
    // fired.
    final bool canProceed =
        await PermissionService.ensurePermissionBeforeSaving(context);
    if (!canProceed) {
      AppLogger.d('Rule save aborted: notification permission not granted.');
      return;
    }

    // Wi-Fi rules need ACCESS_FINE_LOCATION on Android 8.0+ so the
    // system returns the real SSID instead of the redacted "<unknown
    // ssid>". Battery-only users never see this prompt; it's only fired
    // when the user is actually about to save a Wi-Fi rule.
    if (_triggerType == TriggerType.wifi) {
      final locStatus = await PermissionService.requestWifiPermissions();
      AppLogger.d('Wi-Fi rule save: location permission = ${locStatus.name}.');
      // We don't abort the save if the user denies — the rule will just
      // see "<unknown ssid>" until they grant the permission. Better to
      // persist the rule and let the Settings status card surface the
      // missing permission than to lock the user out of the flow.
    }

    // triggerValue is stored as String (supports both numeric thresholds
    // and SSID names)
    final thresholdValue = _thresholdController.text.trim();

    // Quiet hours: when the switch is off we emit null bounds so the
    // worker (and the model) both treat the rule as "always fire".
    final int? quietStart = _quietEnabled
        ? _quietStart.hour * 60 + _quietStart.minute
        : null;
    final int? quietEnd =
        _quietEnabled ? _quietEnd.hour * 60 + _quietEnd.minute : null;

    final rule = Rule(
      profileId: widget.activeProfileId,
      reminderText: reminderText,
      triggerType: _triggerType,
      triggerValue: thresholdValue,
      comparisonOperator: _comparisonOperator,
      isEnabled: _isEnabled,
      alertType: AlertType.normalize(_alertType),
      quietStartMinutes: quietStart,
      quietEndMinutes: quietEnd,
    );

    try {
      await widget.provider.value.addRule(rule);
    } catch (e, st) {
      // Persisting failed for some reason (corrupt box, disk full,
      // etc.). Surface a SnackBar so the user is never left wondering
      // why their rule didn't appear.
      AppLogger.e('Add rule failed.', error: e);
      AppLogger.d('Stack: $st');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Could not save rule: $e')));
      return;
    }
    AppLogger.d(
        'Rule saved: ${rule.reminderText} | ${rule.triggerType.jsonValue} ${rule.comparisonOperator.jsonValue} ${rule.triggerValue}');

    if (!mounted) return;
    // Pop back to HomeScreen. RulesHiveProvider notifies listeners on every
    // mutation, so the home list rebuilds automatically with the new rule.
    Navigator.of(context).pop();
  }

  /// Opens the standard Material time picker for the start bound. Mirrors
  /// the equivalent in [_FullEditRuleDialog] (home_screen.dart).
  Future<void> _pickQuietStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _quietStart,
      helpText: 'Quiet hours — start',
    );
    if (picked != null) {
      setState(() => _quietStart = picked);
    }
  }

  Future<void> _pickQuietEnd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _quietEnd,
      helpText: 'Quiet hours — end',
    );
    if (picked != null) {
      setState(() => _quietEnd = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: const Text('New rule'),
        titleSpacing: 20,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Section header: IF
              _SectionLabel(text: 'IF', palette: p),
              const SizedBox(height: 12),
              _TriggerTypeSelector(
                value: _triggerType,
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _triggerType = value;
                      if (value == TriggerType.wifi) {
                        _thresholdController.clear();
                      }
                    });
                  }
                },
              ),
              const SizedBox(height: 20),

              // Comparison operator (battery only)
              if (_triggerType == TriggerType.battery) ...[
                _SectionLabel(text: 'CONDITION', palette: p),
                const SizedBox(height: 12),
                _OperatorSelector(
                  value: _comparisonOperator,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _comparisonOperator = value);
                    }
                  },
                ),
                const SizedBox(height: 20),
              ],

              _SectionLabel(text: 'VALUE', palette: p),
              const SizedBox(height: 12),
              _ThresholdField(
                controller: _thresholdController,
                triggerType: _triggerType,
              ),
              const SizedBox(height: 28),

              // Section header: THEN
              _SectionLabel(text: 'THEN REMIND ME TO', palette: p),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reminderController,
                style: TextStyle(color: p.textPrimary, fontSize: 16),
                decoration: InputDecoration(
                  labelText: 'Reminder text',
                  hintText: 'e.g. Plug in the power bank',
                  prefixIcon: Icon(
                    Icons.notifications_active_rounded,
                    color: p.textSecondary,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter reminder text';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Enabled toggle in a styled card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Rule enabled',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    _isEnabled
                        ? 'Active and evaluating in background'
                        : 'Disabled — will not fire',
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  value: _isEnabled,
                  onChanged: (value) => setState(() => _isEnabled = value),
                ),
              ),
              const SizedBox(height: 24),

              // Alert type selector. Wraps so both chips stay visible on
              // narrow phones; the Standard chip is the safe default.
              _SectionLabel(text: 'ALERT TYPE', palette: p),
              const SizedBox(height: 12),
              _AlertTypeSelector(
                value: _alertType,
                onChanged: (v) => setState(() => _alertType = v),
              ),
              const SizedBox(height: 20),
              // Quiet hours. Switch + (when on) two time pickers. Mirrors
              // the equivalent in [_FullEditRuleDialog] (home_screen.dart)
              // so the create and edit flows look identical.
              _SectionLabel(text: 'QUIET HOURS', palette: p),
              const SizedBox(height: 4),
              SwitchListTile(
                value: _quietEnabled,
                onChanged: (v) => setState(() => _quietEnabled = v),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Mute during these hours',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  _quietEnabled
                      ? 'Notifications will be suppressed in this window.'
                      : 'Off — rule will fire any time the trigger is met.',
                  style: TextStyle(
                      color: p.textSecondary, fontSize: 12, height: 1.3),
                ),
              ),
              if (_quietEnabled) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickQuietStart,
                        icon: const Icon(Icons.bedtime_outlined, size: 18),
                        label: Text('From ${_quietStart.format(context)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickQuietEnd,
                        icon: const Icon(Icons.wb_sunny_outlined, size: 18),
                        label: Text('Until ${_quietEnd.format(context)}'),
                      ),
                    ),
                  ],
                ),
                if (_quietStart.hour * 60 + _quietStart.minute >
                    _quietEnd.hour * 60 + _quietEnd.minute) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 14,
                        color: p.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Window crosses midnight.',
                          style: TextStyle(
                              color: p.textSecondary,
                              fontSize: 11,
                              fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: 20),

              // Live sentence preview
              _SentencePreview(text: _buildSentencePreview()),
              const SizedBox(height: 32),

              ElevatedButton.icon(
                onPressed: _saveRule,
                icon: const Icon(Icons.check_rounded, size: 20),
                label: const Text('Save rule'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildSentencePreview() {
    final threshold = _thresholdController.text.trim();
    if (_triggerType == TriggerType.battery) {
      return 'IF Battery ${_comparisonOperator.displayLabel} $threshold% '
          'THEN remind me: "${_reminderController.text.trim()}"';
    } else {
      return 'IF Wi-Fi connects to "$threshold" '
          'THEN remind me: "${_reminderController.text.trim()}"';
    }
  }
}

/// Small uppercase section label used as visual divider between form sections.
class _SectionLabel extends StatelessWidget {
  final String text;
  final NudgePalette palette;
  const _SectionLabel({required this.text, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: palette.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

/// Polished trigger-type selector with an icon-aware leading decoration.
class _TriggerTypeSelector extends StatelessWidget {
  final TriggerType value;
  final ValueChanged<TriggerType?> onChanged;
  const _TriggerTypeSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            value == TriggerType.battery
                ? Icons.battery_alert_rounded
                : Icons.wifi_rounded,
            color: p.accent,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<TriggerType>(
                value: value,
                isExpanded: true,
                dropdownColor: p.surface,
                icon: Icon(
                  Icons.expand_more_rounded,
                  color: p.textSecondary,
                ),
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 16,
                ),
                items: TriggerType.values.map((t) {
                  return DropdownMenuItem(
                    value: t,
                    child: Text(t.displayName),
                  );
                }).toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Polished comparison-operator selector styled like the trigger-type one.
class _OperatorSelector extends StatelessWidget {
  final ComparisonOperator value;
  final ValueChanged<ComparisonOperator?> onChanged;
  const _OperatorSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            Icons.compare_arrows_rounded,
            color: p.accent,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<ComparisonOperator>(
                value: value,
                isExpanded: true,
                dropdownColor: p.surface,
                icon: Icon(
                  Icons.expand_more_rounded,
                  color: p.textSecondary,
                ),
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 16,
                ),
                items: ComparisonOperator.values.map((op) {
                  return DropdownMenuItem(
                    value: op,
                    child: Text(op.displayLabel),
                  );
                }).toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Two ChoiceChips for the alert type. Mirrors the selector in
/// `_FullEditRuleDialog` (home_screen.dart) so the create and edit flows
/// feel identical.
class _AlertTypeSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _AlertTypeSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in AlertType.values)
          () {
            final selected = option == value;
            final isUrgent = option == AlertType.urgent;
            return ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isUrgent
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_rounded,
                    size: 16,
                    color: selected
                        ? const Color(0xFF1A1A1A)
                        : p.textPrimary,
                  ),
                  const SizedBox(width: 6),
                  Text(isUrgent ? 'Urgent Alarm' : 'Standard'),
                ],
              ),
              selected: selected,
              onSelected: (_) => onChanged(option),
              selectedColor: p.accent,
              backgroundColor: p.surface,
              labelStyle: TextStyle(
                color: selected
                    ? const Color(0xFF1A1A1A)
                    : p.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              shape: const StadiumBorder(),
              side: BorderSide.none,
            );
          }(),
      ],
    );
  }
}

/// Themed threshold / SSID field with a context-aware prefix icon.
class _ThresholdField extends StatelessWidget {
  final TextEditingController controller;
  final TriggerType triggerType;
  const _ThresholdField({required this.controller, required this.triggerType});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isBattery = triggerType == TriggerType.battery;
    return TextFormField(
      controller: controller,
      keyboardType: isBattery ? TextInputType.number : TextInputType.text,
      style: TextStyle(color: p.textPrimary, fontSize: 16),
      decoration: InputDecoration(
        labelText: isBattery ? 'Battery level (%)' : 'Wi-Fi SSID',
        hintText: isBattery ? 'e.g. 20' : 'e.g. Campus_Mesh',
        prefixIcon: Icon(
          isBattery
              ? Icons.battery_5_bar_rounded
              : Icons.wifi_tethering_rounded,
          color: p.textSecondary,
        ),
        suffixText: isBattery ? '%' : null,
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please enter a value';
        }
        if (isBattery) {
          final v = int.tryParse(value.trim());
          if (v == null || v < 0 || v > 100) {
            return 'Enter a number between 0-100';
          }
        }
        return null;
      },
    );
  }
}

/// Live "IF … THEN …" sentence shown at the bottom of the form.
class _SentencePreview extends StatelessWidget {
  final String text;
  const _SentencePreview({required this.text});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.08),
        border: Border.all(
          color: p.accent.withValues(alpha: 0.35),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.format_quote_rounded,
            color: p.accent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: p.textPrimary,
                fontSize: 14,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}