import 'package:flutter/material.dart';

import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../foundation/theme_v2_typography.dart';
import 'asset_card_display.dart';

@immutable
class CardSelectableField {
  const CardSelectableField({
    required this.id,
    required this.label,
    required this.type,
  });

  final String id;
  final String label;
  final String type;
}

class CardFieldSelectionController extends ChangeNotifier {
  CardFieldSelectionController({
    required List<CardSelectableField> fields,
    required CardDisplayConfig config,
  }) : fields = List.unmodifiable(fields),
       _config = _normalizeInitial(fields, config);

  final List<CardSelectableField> fields;
  CardDisplayConfig _config;
  String? _errorMessage;

  CardDisplayConfig get config => _config;
  String? get errorMessage => _errorMessage;

  bool contains(String fieldId) => fields.any((field) => field.id == fieldId);

  int? secondaryOrder(String fieldId) {
    final index = _config.secondaryFieldIds.indexOf(fieldId);
    return index < 0 ? null : index + 1;
  }

  void selectPrimary(String fieldId) {
    if (!contains(fieldId) || fieldId == _config.primaryFieldId) return;
    _config = CardDisplayConfig(
      primaryFieldId: fieldId,
      secondaryFieldIds: _config.secondaryFieldIds,
    );
    _errorMessage = null;
    notifyListeners();
  }

  bool toggleSecondary(String fieldId) {
    if (!contains(fieldId) || fieldId == _config.primaryFieldId) return false;
    final secondary = List<String>.from(_config.secondaryFieldIds);
    if (secondary.remove(fieldId)) {
      _config = CardDisplayConfig(
        primaryFieldId: _config.primaryFieldId,
        secondaryFieldIds: secondary,
      );
      _errorMessage = null;
      notifyListeners();
      return true;
    }
    if (secondary.length >= 3) {
      _errorMessage = '次要字段最多选择 3 个';
      notifyListeners();
      return false;
    }
    secondary.add(fieldId);
    _config = CardDisplayConfig(
      primaryFieldId: _config.primaryFieldId,
      secondaryFieldIds: secondary,
    );
    _errorMessage = null;
    notifyListeners();
    return true;
  }

  static CardDisplayConfig _normalizeInitial(
    List<CardSelectableField> fields,
    CardDisplayConfig source,
  ) {
    if (fields.isEmpty) return source;
    final ids = fields.map((field) => field.id).toSet();
    final primary = ids.contains(source.primaryFieldId)
        ? source.primaryFieldId
        : fields.first.id;
    return CardDisplayConfig(
      primaryFieldId: primary,
      secondaryFieldIds: source.secondaryFieldIds.where(ids.contains),
    );
  }
}

class CardFieldSelector extends StatelessWidget {
  const CardFieldSelector({super.key, required this.controller});

  final CardFieldSelectionController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final tokens = context.themeV2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'CARD DISPLAY',
                    style: ThemeV2Typography.mono(
                      fontSize: 9,
                      color: tokens.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '主字段 · 次字段最多 3 个',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tokens.muted),
                ),
              ],
            ),
            const SizedBox(height: ThemeV2Spacing.sm),
            DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
                border: Border.all(color: tokens.border),
              ),
              child: Column(
                children: [
                  for (var index = 0; index < controller.fields.length; index++)
                    _FieldSelectionRow(
                      key: ValueKey(
                        'card-field-${controller.fields[index].id}',
                      ),
                      field: controller.fields[index],
                      primary:
                          controller.config.primaryFieldId ==
                          controller.fields[index].id,
                      order: controller.secondaryOrder(
                        controller.fields[index].id,
                      ),
                      onPrimary: () =>
                          controller.selectPrimary(controller.fields[index].id),
                      onSecondary: (enabled) => controller.toggleSecondary(
                        controller.fields[index].id,
                      ),
                      showDivider: index < controller.fields.length - 1,
                    ),
                ],
              ),
            ),
            if (controller.errorMessage case final message?)
              Padding(
                padding: const EdgeInsets.only(top: ThemeV2Spacing.sm),
                child: Text(
                  message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tokens.critical),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FieldSelectionRow extends StatelessWidget {
  const _FieldSelectionRow({
    super.key,
    required this.field,
    required this.primary,
    required this.order,
    required this.onPrimary,
    required this.onSecondary,
    required this.showDivider,
  });

  final CardSelectableField field;
  final bool primary;
  final int? order;
  final VoidCallback onPrimary;
  final ValueChanged<bool> onSecondary;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.only(left: ThemeV2Spacing.md),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: tokens.border))
            : null,
      ),
      child: Row(
        children: [
          IconButton(
            key: ValueKey('card-primary-${field.id}'),
            tooltip: '设为主字段',
            onPressed: onPrimary,
            icon: Icon(
              primary
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: primary ? tokens.accent : tokens.muted,
              size: 21,
            ),
          ),
          const SizedBox(width: ThemeV2Spacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  field.label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  field.type.toUpperCase(),
                  style: ThemeV2Typography.mono(
                    fontSize: 8,
                    color: tokens.muted,
                  ),
                ),
              ],
            ),
          ),
          if (order case final number?)
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tokens.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$number',
                style: ThemeV2Typography.mono(
                  fontSize: 9,
                  color: tokens.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Checkbox(
            key: ValueKey('card-secondary-${field.id}'),
            value: order != null,
            onChanged: primary ? null : (value) => onSecondary(value ?? false),
          ),
        ],
      ),
    );
  }
}
