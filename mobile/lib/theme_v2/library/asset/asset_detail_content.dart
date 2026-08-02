import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../data_revision.dart';
import '../../../pages/create_asset.dart' show ContactForm;
import '../../../pages/event_attendees.dart';
import '../../../render/render_spec.dart';
import '../../asset_detail/asset_entity_ref.dart';
import '../../asset_detail/asset_text_value.dart';
import '../../foundation/theme_v2_theme.dart';
import '../../foundation/theme_v2_tokens.dart';
import '../../foundation/theme_v2_typography.dart';
import 'asset_detail_presentation.dart';

class AssetDetailContent extends StatelessWidget {
  const AssetDetailContent({super.key, required this.controller, this.api});

  final AssetDetailController controller;
  final ApiClient? api;

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
            if (controller.ref.kind == AssetEntityKind.event &&
                field == 'attendees' &&
                controller.payload[field] is List)
              _EventAttendeesValue(
                controller: controller,
                api: api,
                attendees: controller.payload[field] as List,
              )
            else
              _AssetDetailField(
                label: controller.spec.fieldLabels[field] ?? _fieldLabel(field),
                value: applyFormat(
                  controller.payload[field],
                  controller.spec.formatForField(field),
                ),
                markdown: controller.spec.longFields.contains(field),
                full: full,
                onExpand: controller.expand,
              ),
      ],
    );
  }
}

class _EventAttendeesValue extends StatefulWidget {
  const _EventAttendeesValue({
    required this.controller,
    required this.attendees,
    this.api,
  });

  final AssetDetailController controller;
  final List attendees;
  final ApiClient? api;

  @override
  State<_EventAttendeesValue> createState() => _EventAttendeesValueState();
}

class _EventAttendeesValueState extends State<_EventAttendeesValue> {
  late final ApiClient _api = widget.api ?? ApiClient();
  late final bool _ownsApi = widget.api == null;
  var _busy = false;

  List<EventAttendeeDraft> get _attendees => widget.attendees
      .whereType<Map>()
      .map(EventAttendeeDraft.fromJson)
      .where((attendee) => attendee.displayName.isNotEmpty)
      .toList();

  @override
  void dispose() {
    if (_ownsApi) _api.close();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _openContactForm(
    BuildContext context,
    String initialName,
  ) async {
    final receipt = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute<dynamic>(
        builder: (_) => ContactForm(
          existing: initialName.isEmpty ? null : {'name': initialName},
        ),
      ),
    );
    return receipt is Map ? Map<String, dynamic>.from(receipt) : null;
  }

  Future<void> _bind(EventAttendeeDraft attendee) async {
    final attendeeId = attendee.id;
    if (_busy || attendeeId == null) return;
    final excludedIds = _attendees
        .map((item) => item.contactId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final selected = await showEventAttendeeSelector(
      context,
      api: _api,
      excludedContactIds: excludedIds,
      initialQuery: attendee.nameRaw ?? attendee.displayName,
      singleSelect: true,
      onCreateContact: _openContactForm,
    );
    if (!mounted || selected == null || selected.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _api.patchJson(
        '/api/events/${widget.controller.assetId}/attendees/$attendeeId',
        {'contact_id': selected.first.id},
      );
      await widget.controller.retry();
      bumpData();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('关联联系人失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final attendees = _attendees;
    if (attendees.isEmpty) return const SizedBox.shrink();
    final tokens = context.themeV2;
    return Padding(
      padding: const EdgeInsets.only(bottom: ThemeV2Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '参会人',
            style: ThemeV2Typography.mono(
              fontSize: 8,
              color: tokens.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: ThemeV2Spacing.xs),
          for (final attendee in attendees)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: ThemeV2Spacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attendee.displayName,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (attendee.contactSummary.isNotEmpty)
                          Text(
                            attendee.contactSummary,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: tokens.muted),
                          )
                        else if (!attendee.isResolved)
                          Text(
                            '未关联联系人',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: tokens.muted),
                          ),
                      ],
                    ),
                  ),
                  if (!attendee.isResolved && attendee.id != null)
                    TextButton(
                      onPressed: _busy ? null : () => _bind(attendee),
                      child: const Text('关联'),
                    ),
                ],
              ),
            ),
        ],
      ),
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
    final content = Padding(
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
    );
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
        child: onOpen == null
            ? content
            : Semantics(
                button: true,
                label: '$label，打开原始输入',
                child: InkWell(
                  onTap: onOpen,
                  borderRadius: BorderRadius.circular(ThemeV2Radii.md),
                  child: content,
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
    required this.markdown,
    required this.full,
    required this.onExpand,
  });

  final String label;
  final String value;
  final bool markdown;
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
          AssetTextValue(
            text: value,
            markdown: markdown,
            full: full,
            onExpand: onExpand,
          ),
        ],
      ),
    );
  }
}

List<String> _orderedFields(AssetDetailController controller) {
  final declared = controller.spec.schemaFields;
  final available = declared.isEmpty
      ? <String>{...controller.payload.keys}
      : <String>{...declared};
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
      'description',
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
