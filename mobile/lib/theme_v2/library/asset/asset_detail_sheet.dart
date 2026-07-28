import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../pages/create_asset.dart' show ContactForm, EventForm;
import '../../../render/render_spec.dart';
import '../../foundation/theme_v2_semantics.dart';
import '../../foundation/theme_v2_theme.dart';
import '../../foundation/theme_v2_tokens.dart';
import '../../foundation/theme_v2_typography.dart';
import 'asset_detail_presentation.dart';
import 'asset_editor.dart';
import 'set_goal_action.dart';

Future<SetGoalIntent?> showThemeV2AssetDetail(
  BuildContext context, {
  required CardData data,
  required Map<String, dynamic> payload,
  required String cardType,
  String? assetId,
  String? userSkillId,
  String? sessionId,
  RenderSpec? spec,
  ApiClient? api,
  ValueChanged<SetGoalIntent>? onSetGoal,
}) async {
  final controller = AssetDetailController(
    api: api,
    data: data,
    payload: payload,
    cardType: cardType,
    assetId: assetId,
    userSkillId: userSkillId,
    sessionId: sessionId,
    spec: spec,
  );
  try {
    return await showModalBottomSheet<SetGoalIntent>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final routeTheme = buildThemeV2Theme(Theme.of(sheetContext).brightness);
        return Theme(
          data: routeTheme,
          child: ThemeV2AssetDetailSurface(
            controller,
            onSetGoal: (intent) {
              onSetGoal?.call(intent);
              Navigator.of(sheetContext).pop(intent);
            },
          ),
        );
      },
    );
  } finally {
    controller.dispose();
  }
}

class ThemeV2AssetDetailSurface extends StatefulWidget {
  const ThemeV2AssetDetailSurface(this.controller, {super.key, this.onSetGoal});

  final AssetDetailController controller;
  final ValueChanged<SetGoalIntent>? onSetGoal;

  @override
  State<ThemeV2AssetDetailSurface> createState() =>
      _ThemeV2AssetDetailSurfaceState();
}

class _ThemeV2AssetDetailSurfaceState extends State<ThemeV2AssetDetailSurface> {
  AssetDetailController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_changed);
    controller.hydrate();
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final full =
        controller.presentation == AssetDetailPresentationKind.fullPage;
    final tokens = context.themeV2;
    final surface = Material(
      key: ValueKey(full ? 'theme-v2-asset-full-page' : 'theme-v2-asset-sheet'),
      color: tokens.surface,
      clipBehavior: Clip.antiAlias,
      borderRadius: full
          ? BorderRadius.zero
          : const BorderRadius.vertical(top: Radius.circular(ThemeV2Radii.lg)),
      child: Column(
        children: [
          _DetailHeader(controller: controller, onClose: _requestClose),
          Expanded(
            child: controller.editing
                ? ThemeV2AssetEditor(
                    draft: controller.draft,
                    scrollController: controller.scrollController,
                    onSave: controller.saveDraft,
                  )
                : _DetailBody(
                    controller: controller,
                    onSetGoal: widget.onSetGoal,
                    onEdit: _beginEditing,
                    onDelete: _confirmDelete,
                  ),
          ),
        ],
      ),
    );
    final routeHeight = MediaQuery.sizeOf(context).height;
    final result = SizedBox(
      width: double.infinity,
      height: full ? routeHeight : routeHeight * 0.68,
      child: surface,
    );
    return PopScope(
      canPop: !(controller.editing && controller.draft.isDirty),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose();
      },
      child: result,
    );
  }

  Future<void> _requestClose() async {
    if (controller.editing && controller.draft.isDirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('放弃未保存的修改？'),
          content: const Text('离开后，这些修改不会保留。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('继续编辑'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('放弃'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
      controller.cancelEditing();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    Navigator.of(context).maybePop();
  }

  Future<void> _beginEditing() async {
    if (controller.cardType != 'event' && controller.cardType != 'contact') {
      controller.beginEditing();
      return;
    }
    await controller.hydrate();
    if (!mounted || controller.assetId == null) return;
    final editor = controller.cardType == 'event'
        ? EventForm(eventId: controller.assetId, existing: controller.payload)
        : ContactForm(
            contactId: controller.assetId,
            existing: controller.payload,
          );
    final changed = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => editor));
    if (changed == true && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: const Text('删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await controller.delete();
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('删除失败，请稍后重试')));
    }
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.controller, required this.onClose});

  final AssetDetailController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final full =
        controller.presentation == AssetDetailPresentationKind.fullPage;
    return GestureDetector(
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) < -240) controller.expand();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ThemeV2Spacing.md,
          ThemeV2Spacing.sm,
          ThemeV2Spacing.md,
          ThemeV2Spacing.sm,
        ),
        child: Column(
          children: [
            if (!full)
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: tokens.border,
                  borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
                ),
              ),
            Row(
              children: [
                if (full)
                  ThemeV2IconButton(
                    semanticLabel: '收起详情',
                    icon: Icons.keyboard_arrow_down,
                    onPressed: controller.collapse,
                  )
                else
                  ThemeV2IconButton(
                    key: const ValueKey('asset-detail-close'),
                    semanticLabel: '关闭详情',
                    icon: Icons.close,
                    onPressed: onClose,
                  ),
                Expanded(
                  child: Text(
                    controller.cardType.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: ThemeV2Typography.mono(
                      fontSize: 9,
                      color: tokens.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!full)
                  ThemeV2IconButton(
                    key: const ValueKey('asset-detail-expand'),
                    semanticLabel: '展开为全页',
                    icon: Icons.open_in_full,
                    onPressed: controller.expand,
                  )
                else
                  ThemeV2IconButton(
                    key: const ValueKey('asset-detail-close'),
                    semanticLabel: '关闭详情',
                    icon: Icons.close,
                    onPressed: onClose,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.controller,
    required this.onSetGoal,
    required this.onEdit,
    required this.onDelete,
  });

  final AssetDetailController controller;
  final ValueChanged<SetGoalIntent>? onSetGoal;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final fields = [
      ...controller.spec.schemaFields,
      for (final key in controller.payload.keys)
        if (!controller.spec.schemaFields.contains(key)) key,
    ];
    return ListView(
      key: const ValueKey('theme-v2-asset-detail-scroll'),
      controller: controller.scrollController,
      padding: const EdgeInsets.fromLTRB(
        ThemeV2Spacing.xl,
        ThemeV2Spacing.sm,
        ThemeV2Spacing.xl,
        ThemeV2Spacing.xl,
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
          if (controller.payload[field] != null &&
              '${controller.payload[field]}'.trim().isNotEmpty)
            _SchemaField(
              label: controller.spec.fieldLabels[field] ?? field,
              value: applyFormat(
                controller.payload[field],
                controller.spec.formatForField(field),
              ),
              long: controller.spec.longFields.contains(field),
            ),
        const SizedBox(height: ThemeV2Spacing.lg),
        Wrap(
          spacing: ThemeV2Spacing.sm,
          runSpacing: ThemeV2Spacing.sm,
          children: [
            ThemeV2HitTarget(
              child: FilledButton.icon(
                key: const ValueKey('asset-detail-edit'),
                onPressed: controller.assetId == null ? null : onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('编辑'),
              ),
            ),
            if (controller.assetId != null)
              ThemeV2HitTarget(
                child: OutlinedButton.icon(
                  key: const ValueKey('asset-detail-delete'),
                  onPressed: controller.busy ? null : onDelete,
                  icon: Icon(Icons.delete_outline, color: tokens.critical),
                  label: const Text('删除'),
                ),
              ),
            if (controller.cardType == 'todo')
              ThemeV2HitTarget(
                child: OutlinedButton.icon(
                  onPressed: controller.busy ? null : controller.toggleTodo,
                  icon: Icon(
                    controller.isDone ? Icons.undo : Icons.check_circle_outline,
                  ),
                  label: Text(controller.isDone ? '撤销完成' : '标记完成'),
                ),
              ),
            SetGoalAction(
              state: SetGoalActionState(userSkillId: controller.userSkillId),
              onIntent: (intent) {
                if (onSetGoal != null) {
                  onSetGoal!(intent);
                } else {
                  Navigator.of(context).pop(intent);
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _SchemaField extends StatelessWidget {
  const _SchemaField({
    required this.label,
    required this.value,
    required this.long,
  });

  final String label;
  final String value;
  final bool long;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Padding(
      padding: const EdgeInsets.only(bottom: ThemeV2Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: ThemeV2Typography.mono(
              fontSize: 8,
              color: tokens.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: ThemeV2Spacing.xs),
          SelectableText(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: long ? 1.55 : 1.3),
          ),
        ],
      ),
    );
  }
}
