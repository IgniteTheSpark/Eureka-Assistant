import 'package:flutter/material.dart';

import '../../../render/render_spec.dart';
import '../../foundation/theme_v2_theme.dart';
import '../../foundation/theme_v2_tokens.dart';
import '../../foundation/theme_v2_typography.dart';
import 'asset_detail_presentation.dart';
import 'asset_long_text.dart';

class AssetDetailContent extends StatelessWidget {
  const AssetDetailContent({super.key, required this.controller});

  final AssetDetailController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final full =
        controller.presentation == AssetDetailPresentationKind.fullPage;
    final fields = _orderedFields(controller);
    return ListView(
      key: const ValueKey('theme-v2-asset-detail-scroll'),
      controller: controller.scrollController,
      padding: const EdgeInsets.fromLTRB(
        ThemeV2Spacing.xl,
        ThemeV2Spacing.sm,
        ThemeV2Spacing.xl,
        ThemeV2Spacing.lg,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tokens.accentSoft,
                borderRadius: BorderRadius.circular(ThemeV2Radii.md),
              ),
              child: Text(
                controller.data.icon,
                style: const TextStyle(fontSize: 20),
              ),
            ),
            const SizedBox(width: ThemeV2Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.data.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (controller.data.subtitle.isNotEmpty)
                    Text(
                      controller.data.subtitle,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: tokens.accent),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: ThemeV2Spacing.xl),
        if (controller.loadState == AssetDetailLoadState.error)
          Padding(
            padding: const EdgeInsets.only(bottom: ThemeV2Spacing.md),
            child: Text(
              controller.errorMessage ?? '内容加载失败',
              style: TextStyle(color: tokens.critical),
            ),
          ),
        for (final field in fields)
          if (_hasValue(controller.payload[field]))
            _AssetDetailField(
              label: controller.spec.fieldLabels[field] ?? _fieldLabel(field),
              value: applyFormat(
                controller.payload[field],
                controller.spec.formatForField(field),
              ),
              long:
                  controller.spec.longFields.contains(field) ||
                  _isDomainLongField(controller.cardType, field),
              full: full,
              onExpand: controller.expand,
            ),
      ],
    );
  }
}

class AssetDetailSourceBar extends StatelessWidget {
  const AssetDetailSourceBar({super.key, required this.label, this.onOpen});

  final String label;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ThemeV2Spacing.xl,
        0,
        ThemeV2Spacing.xl,
        ThemeV2Spacing.sm,
      ),
      child: Material(
        key: const ValueKey('asset-detail-source'),
        color: tokens.surface,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(ThemeV2Radii.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: ThemeV2Spacing.sm),
            child: Row(
              children: [
                Icon(Icons.bolt_outlined, size: 16, color: tokens.muted),
                const SizedBox(width: ThemeV2Spacing.sm),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: tokens.muted),
                  ),
                ),
                if (onOpen != null)
                  Icon(Icons.chevron_right, size: 18, color: tokens.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AssetDetailField extends StatelessWidget {
  const _AssetDetailField({
    required this.label,
    required this.value,
    required this.long,
    required this.full,
    required this.onExpand,
  });

  final String label;
  final String value;
  final bool long;
  final bool full;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ThemeV2Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: ThemeV2Typography.mono(
              fontSize: 8,
              color: context.themeV2.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: ThemeV2Spacing.xs),
          if (long)
            AssetLongText(text: value, expanded: full, onExpand: onExpand)
          else
            SelectableText(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.3),
            ),
        ],
      ),
    );
  }
}

List<String> _orderedFields(AssetDetailController controller) {
  final available = <String>{
    ...controller.spec.schemaFields,
    ...controller.payload.keys,
  };
  final priority = switch (controller.cardType) {
    'todo' => const [
      'title',
      'due_at',
      'due_date',
      'reminder_at',
      'notes',
      'status',
    ],
    'notes' || 'note' => const ['title', 'tags', 'body', 'content', 'domain'],
    'event' => const [
      'title',
      'start_at',
      'end_at',
      'location',
      'attendees',
      'notes',
    ],
    'contact' => const [
      'name',
      'company',
      'title',
      'phone',
      'email',
      'social',
      'notes',
    ],
    _ => controller.spec.schemaFields,
  };
  return [
    for (final field in priority)
      if (available.remove(field)) field,
    ...available,
  ];
}

bool _hasValue(dynamic value) =>
    value != null && value.toString().trim().isNotEmpty;

bool _isDomainLongField(String cardType, String field) =>
    (cardType == 'notes' || cardType == 'note') &&
        (field == 'body' || field == 'content') ||
    field == 'notes';

String _fieldLabel(String field) =>
    const {
      'title': '标题',
      'name': '姓名',
      'body': '正文',
      'content': '正文',
      'tags': '标签',
      'due_at': '截止时间',
      'due_date': '截止日期',
      'reminder_at': '提醒',
      'start_at': '开始',
      'end_at': '结束',
      'location': '地点',
      'attendees': '参与人',
      'company': '公司',
      'phone': '电话',
      'email': '邮箱',
      'social': '社交账号',
      'notes': '备注',
      'status': '状态',
      'domain': '领域',
    }[field] ??
    field;
