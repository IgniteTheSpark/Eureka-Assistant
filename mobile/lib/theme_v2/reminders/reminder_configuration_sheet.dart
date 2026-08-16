import 'package:flutter/material.dart';

import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import 'reminder_preferences.dart';

const reminderPresetOffsets = <int>[0, 5, 15, 30, 60, 1440];

Future<List<int>?> showReminderConfigurationSheet(
  BuildContext context, {
  List<int>? initialOffsets,
}) => showModalBottomSheet<List<int>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _ReminderConfigurationSheet(
    initialOffsets: normalizeReminderOffsets(initialOffsets),
  ),
);

class _ReminderConfigurationSheet extends StatefulWidget {
  const _ReminderConfigurationSheet({required this.initialOffsets});

  final List<int> initialOffsets;

  @override
  State<_ReminderConfigurationSheet> createState() =>
      _ReminderConfigurationSheetState();
}

class _ReminderConfigurationSheetState
    extends State<_ReminderConfigurationSheet> {
  late final Set<int> _selected = widget.initialOffsets.toSet();
  final _customController = TextEditingController();
  bool _customVisible = false;

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _toggle(int minutes, bool selected) {
    setState(() {
      if (selected) {
        _selected.add(minutes);
      } else {
        _selected.remove(minutes);
      }
    });
  }

  void _addCustom() {
    final minutes = int.tryParse(_customController.text.trim());
    if (minutes == null || minutes <= 0) return;
    setState(() => _selected.add(minutes));
    _customController.clear();
  }

  void _save() {
    Navigator.of(context).pop<List<int>>(
      normalizeReminderOffsets(
        _selected.toList(growable: false),
        missingUsesDefault: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Material(
      color: tokens.surface,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(ThemeV2Radii.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: tokens.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  '提醒我',
                  style: TextStyle(
                    color: tokens.foreground,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final minutes in reminderPresetOffsets)
                SizedBox(
                  key: ValueKey('reminder-option-$minutes'),
                  height: ThemeV2Sizes.minTouchTarget,
                  child: CheckboxListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    title: Text(reminderOffsetLabel(minutes)),
                    value: _selected.contains(minutes),
                    onChanged: (value) => _toggle(minutes, value ?? false),
                    controlAffinity: ListTileControlAffinity.trailing,
                  ),
                ),
              SizedBox(
                key: const ValueKey('reminder-option-custom'),
                height: ThemeV2Sizes.minTouchTarget,
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: const Text('自定义'),
                  trailing: const Icon(Icons.add_rounded, size: 20),
                  onTap: () => setState(() => _customVisible = true),
                ),
              ),
              if (_customVisible)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('reminder-custom-input'),
                          controller: _customController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '提前分钟数',
                            isDense: true,
                          ),
                          onSubmitted: (_) => _addCustom(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        key: const ValueKey('reminder-custom-add'),
                        onPressed: _addCustom,
                        child: const Text('添加'),
                      ),
                    ],
                  ),
                ),
              SizedBox(
                key: const ValueKey('reminder-option-none'),
                height: ThemeV2Sizes.minTouchTarget,
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: const Text('不提醒'),
                  trailing: _selected.isEmpty
                      ? Icon(
                          Icons.check_rounded,
                          color: tokens.accent,
                          size: 20,
                        )
                      : null,
                  onTap: () => setState(_selected.clear),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      key: const ValueKey('reminder-cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('reminder-save'),
                      onPressed: _save,
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
