import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../pages/create_asset.dart' show ContactForm, EventForm;
import '../../asset_detail/asset_detail_model.dart';
import '../../asset_detail/asset_entity_ref.dart';
import '../../capture/capture_session_page.dart';
import '../../foundation/theme_v2_semantics.dart';
import '../../foundation/theme_v2_theme.dart';
import '../../foundation/theme_v2_tokens.dart';
import '../../foundation/theme_v2_typography.dart';
import '../../report/report_notification_target.dart';
import '../../reminders/reminder_configuration_sheet.dart';
import '../../reminders/reminder_preferences.dart';
import '../../session/theme_v2_session_page.dart';
import 'asset_detail_content.dart';
import 'asset_detail_presentation.dart';
import 'asset_editors.dart';

class RekaOverdueReminderContext {
  const RekaOverdueReminderContext({
    required this.onSnooze,
    required this.onDismiss,
    this.now,
  });

  final Future<void> Function(DateTime remindAgainAt) onSnooze;
  final Future<void> Function() onDismiss;
  final DateTime Function()? now;

  DateTime currentTime() => now?.call() ?? DateTime.now();
}

class ThemeV2AssetDetailSurface extends StatefulWidget {
  const ThemeV2AssetDetailSurface(
    this.controller, {
    super.key,
    this.api,
    this.overdueReminder,
  });

  final AssetDetailController controller;
  final ApiClient? api;
  final RekaOverdueReminderContext? overdueReminder;

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
                ? AssetEditorRouter(
                    cardType: controller.cardType,
                    draft: controller.draft,
                    scrollController: controller.scrollController,
                    onSave: controller.saveDraft,
                  )
                : _DetailBody(
                    controller: controller,
                    api: widget.api,
                    overdueReminder: widget.overdueReminder,
                    onEdit: _beginEditing,
                    onDelete: _confirmDelete,
                  ),
          ),
        ],
      ),
    );
    final routeHeight = MediaQuery.sizeOf(context).height;
    final result = Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: double.infinity,
        height: full ? routeHeight : math.min(576, routeHeight),
        child: surface,
      ),
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
    await controller.hydrate();
    if (!mounted || !controller.canEdit) return;
    controller.expand();
    final Widget? dedicatedEditor = switch (controller.ref.kind) {
      AssetEntityKind.event => EventForm(
        eventId: controller.assetId,
        existing: controller.payload,
        api: widget.api,
        coreRecordsOnly: controller.coreRecordsOnly,
      ),
      AssetEntityKind.contact => ContactForm(
        contactId: controller.assetId,
        existing: controller.payload,
      ),
      AssetEntityKind.asset => null,
    };
    if (dedicatedEditor != null) {
      final changed = await Navigator.of(context).push<dynamic>(
        MaterialPageRoute<dynamic>(builder: (_) => dedicatedEditor),
      );
      if (changed == true && mounted) await controller.retry();
      return;
    }
    controller.beginEditing();
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

class _DetailHeader extends StatefulWidget {
  const _DetailHeader({required this.controller, required this.onClose});

  final AssetDetailController controller;
  final VoidCallback onClose;

  @override
  State<_DetailHeader> createState() => _DetailHeaderState();
}

class _DetailHeaderState extends State<_DetailHeader> {
  double _dragDistance = 0;

  void _finishDrag(DragEndDetails details) {
    final full =
        widget.controller.presentation == AssetDetailPresentationKind.fullPage;
    final velocity = details.primaryVelocity ?? 0;
    if (!full && (_dragDistance <= -24 || velocity < -240)) {
      widget.controller.expand();
    } else if (full && (_dragDistance >= 24 || velocity > 240)) {
      widget.controller.collapse();
    }
    _dragDistance = 0;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final full =
        widget.controller.presentation == AssetDetailPresentationKind.fullPage;
    return GestureDetector(
      key: const ValueKey('asset-detail-drag-region'),
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => _dragDistance = 0,
      onVerticalDragUpdate: (details) => _dragDistance += details.delta.dy,
      onVerticalDragEnd: _finishDrag,
      onVerticalDragCancel: () => _dragDistance = 0,
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
                    onPressed: widget.controller.collapse,
                  )
                else
                  ThemeV2IconButton(
                    key: const ValueKey('asset-detail-close'),
                    semanticLabel: '关闭详情',
                    icon: Icons.close,
                    onPressed: widget.onClose,
                  ),
                Expanded(
                  child: Text(
                    widget.controller.skillDisplayName,
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
                    onPressed: widget.controller.expand,
                  )
                else
                  ThemeV2IconButton(
                    key: const ValueKey('asset-detail-close'),
                    semanticLabel: '关闭详情',
                    icon: Icons.close,
                    onPressed: widget.onClose,
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
    required this.api,
    required this.overdueReminder,
    required this.onEdit,
    required this.onDelete,
  });

  final AssetDetailController controller;
  final ApiClient? api;
  final RekaOverdueReminderContext? overdueReminder;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: AssetDetailContent(controller: controller, api: api),
        ),
        if (controller.sourceLabel case final source?)
          AssetDetailSourceBar(
            label: source,
            onOpen: controller.sourceCanOpen
                ? () => _openSource(context)
                : null,
          ),
        _ReminderControls(
          controller: controller,
          overdueReminder: overdueReminder,
        ),
        _DetailActions(
          controller: controller,
          onEdit: onEdit,
          onDelete: onDelete,
        ),
      ],
    );
  }

  Future<void> _openSource(BuildContext context) async {
    final offset = controller.scrollController.hasClients
        ? controller.scrollController.offset
        : 0.0;
    if (controller.sourceKind == AssetDetailSourceKind.report) {
      await _openReportSource(context);
      controller.restoreScrollOffset(offset);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => controller.sourceKind == AssetDetailSourceKind.flash
            ? CaptureSessionPage(
                recordingId: controller.sessionId!,
                focusedInputTurnId: controller.inputTurnId,
              )
            : ThemeV2SessionPage(
                boundSessionId: controller.sessionId!,
                focusedInputTurnId: controller.inputTurnId!,
              ),
      ),
    );
    controller.restoreScrollOffset(offset);
  }

  Future<void> _openReportSource(BuildContext context) async {
    final reportId = controller.reportId;
    if (reportId == null) return;
    final ownedClient = api == null ? ApiClient() : null;
    final client = api ?? ownedClient!;
    try {
      final response = await client.getJson('/api/reports/$reportId');
      if (response is! Map || !context.mounted) return;
      final page = buildThemeV2ReportViewerPage(
        response,
        reportId: reportId,
        api: api,
      );
      await Navigator.of(
        context,
      ).push<void>(MaterialPageRoute(builder: (_) => page));
    } on ApiException catch (error) {
      if (!context.mounted) return;
      final message = error.statusCode == 404 ? '来源报告已不存在' : '报告暂时无法加载';
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } finally {
      ownedClient?.close();
    }
  }
}

class _ReminderControls extends StatefulWidget {
  const _ReminderControls({
    required this.controller,
    required this.overdueReminder,
  });

  final AssetDetailController controller;
  final RekaOverdueReminderContext? overdueReminder;

  @override
  State<_ReminderControls> createState() => _ReminderControlsState();
}

class _ReminderControlsState extends State<_ReminderControls> {
  bool _busy = false;

  bool get _isTodo => widget.controller.cardType == 'todo';
  bool get _supportsPreDueReminder =>
      _isTodo || widget.controller.cardType == 'event';

  Future<void> _editPreDueReminders() async {
    final selected = await showReminderConfigurationSheet(
      context,
      initialOffsets: normalizeReminderOffsets(
        widget.controller.payload['reminder_offsets_minutes'],
      ),
    );
    if (selected == null || !mounted) return;
    try {
      await widget.controller.saveDraft({'reminder_offsets_minutes': selected});
    } catch (_) {
      if (!mounted) return;
      _showError('提醒设置保存失败，请稍后重试');
    }
  }

  Future<void> _snooze(Duration duration) async {
    final overdue = widget.overdueReminder;
    if (overdue == null) return;
    await _runOverdueAction(
      () => overdue.onSnooze(overdue.currentTime().add(duration)),
    );
  }

  Future<void> _snoozeTomorrow() async {
    final overdue = widget.overdueReminder;
    if (overdue == null) return;
    final now = overdue.currentTime();
    await _runOverdueAction(
      () => overdue.onSnooze(DateTime(now.year, now.month, now.day + 1, 9)),
    );
  }

  Future<void> _pickCustomSnooze() async {
    final overdue = widget.overdueReminder;
    if (overdue == null) return;
    final now = overdue.currentTime();
    final initial = now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final value = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!value.isAfter(now)) {
      _showError('请选择一个未来时间');
      return;
    }
    await _runOverdueAction(() => overdue.onSnooze(value));
  }

  Future<void> _dismiss() async {
    final overdue = widget.overdueReminder;
    if (overdue == null) return;
    await _runOverdueAction(overdue.onDismiss);
  }

  Future<void> _runOverdueAction(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) await Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) _showError('操作失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller.loadState != AssetDetailLoadState.ready) {
      return const SizedBox.shrink();
    }
    if (_isTodo && widget.controller.isDone) return const SizedBox.shrink();
    if (_isTodo && widget.overdueReminder != null) {
      return _buildOverdue(context);
    }
    if (!_supportsPreDueReminder) return const SizedBox.shrink();
    final tokens = context.themeV2;
    final offsets = normalizeReminderOffsets(
      widget.controller.payload['reminder_offsets_minutes'],
    );
    return Material(
      color: tokens.surface,
      child: ListTile(
        key: const ValueKey('asset-detail-reminders'),
        minTileHeight: ThemeV2Sizes.minTouchTarget,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ThemeV2Spacing.xl,
        ),
        leading: const Icon(Icons.notifications_none_rounded),
        title: const Text('提醒'),
        subtitle: Text(formatReminderSummary(offsets)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: widget.controller.busy ? null : _editPreDueReminders,
      ),
    );
  }

  Widget _buildOverdue(BuildContext context) {
    final tokens = context.themeV2;
    Widget option(String label, Key key, VoidCallback onPressed) =>
        OutlinedButton(
          key: key,
          onPressed: _busy ? null : onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, ThemeV2Sizes.minTouchTarget),
          ),
          child: Text(label),
        );
    return Material(
      key: const ValueKey('asset-detail-overdue-reminder'),
      color: tokens.surface,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          ThemeV2Spacing.xl,
          ThemeV2Spacing.sm,
          ThemeV2Spacing.xl,
          ThemeV2Spacing.md,
        ),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: tokens.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '稍后提醒',
              style: TextStyle(
                color: tokens.foreground,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: ThemeV2Spacing.xs),
            Wrap(
              spacing: ThemeV2Spacing.sm,
              runSpacing: ThemeV2Spacing.xs,
              children: [
                option(
                  '15 分钟',
                  const ValueKey('overdue-snooze-15'),
                  () => _snooze(const Duration(minutes: 15)),
                ),
                option(
                  '1 小时',
                  const ValueKey('overdue-snooze-60'),
                  () => _snooze(const Duration(hours: 1)),
                ),
                option(
                  '3 小时',
                  const ValueKey('overdue-snooze-180'),
                  () => _snooze(const Duration(hours: 3)),
                ),
                option(
                  '明天 09:00',
                  const ValueKey('overdue-snooze-tomorrow'),
                  _snoozeTomorrow,
                ),
                option(
                  '自定义',
                  const ValueKey('overdue-snooze-custom'),
                  _pickCustomSnooze,
                ),
                TextButton(
                  key: const ValueKey('overdue-dismiss'),
                  onPressed: _busy ? null : _dismiss,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, ThemeV2Sizes.minTouchTarget),
                  ),
                  child: const Text('不再提醒'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailActions extends StatelessWidget {
  const _DetailActions({
    required this.controller,
    required this.onEdit,
    required this.onDelete,
  });

  final AssetDetailController controller;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Material(
      key: const ValueKey('asset-detail-actions'),
      color: tokens.surface,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          ThemeV2Spacing.xl,
          ThemeV2Spacing.sm,
          ThemeV2Spacing.xl,
          MediaQuery.paddingOf(context).bottom + ThemeV2Spacing.md,
        ),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: tokens.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (controller.cardType == 'todo' &&
                controller.loadState == AssetDetailLoadState.ready) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('asset-detail-toggle-todo'),
                  onPressed: controller.busy ? null : controller.toggleTodo,
                  icon: Icon(
                    controller.isDone ? Icons.undo : Icons.check_circle_outline,
                  ),
                  label: Text(controller.isDone ? '撤销完成' : '标记完成'),
                ),
              ),
              const SizedBox(height: ThemeV2Spacing.sm),
            ],
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('asset-detail-edit'),
                    onPressed: controller.canEdit ? onEdit : null,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('编辑'),
                  ),
                ),
                if (controller.canDelete) ...[
                  const SizedBox(width: ThemeV2Spacing.sm),
                  ThemeV2HitTarget(
                    child: IconButton.outlined(
                      key: const ValueKey('asset-detail-delete'),
                      onPressed: controller.busy ? null : onDelete,
                      icon: Icon(Icons.delete_outline, color: tokens.critical),
                      tooltip: '删除',
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
