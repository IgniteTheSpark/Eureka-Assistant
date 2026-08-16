import 'package:flutter/material.dart';

import '../../data_revision.dart';
import '../../pages/create_asset.dart' show openThemeV2SkillCapture;
import '../../timeline/timeline.dart';
import '../../today/today_data.dart';
import '../asset_detail/asset_detail_repository.dart';
import '../asset_detail/asset_entity_ref.dart';
import '../asset_detail/open_asset_detail.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../library/asset/asset_list_page.dart';
import '../library/asset/asset_detail_sheet.dart';
import '../report/report_run_page.dart';
import '../report/report_notification_target.dart';
import 'reka_report_detail_sheet.dart';
import 'reka_rhythm_detail_sheet.dart';
import 'reka_signal_repository.dart';

typedef RekaSignalMutationCallback =
    Future<void> Function(TodayRekaItem item, String action);

typedef RekaSignalTargetCallback =
    Future<void> Function(BuildContext context, TodayRekaItem item);

Future<void> openRekaSignalTarget(
  BuildContext context,
  TodayRekaItem item, {
  RekaSignalRepository? repository,
  AssetDetailRepository? assetRepository,
}) async {
  if (item.targetId.isEmpty) return;
  if (item.type == 'rhythm_gap') {
    return _openRhythmSignal(context, item, repository);
  }
  if (item.type == 'report') {
    return _openReportSignal(context, item, repository);
  }
  if (item.targetType == 'trigger_execution') {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportRunPage(triggerExecutionId: item.targetId),
      ),
    );
    return;
  }
  if (item.targetType == 'asset') {
    ApiRekaSignalRepository? ownedRepository;
    final resolvedRepository = item.type == 'overdue'
        ? repository ?? (ownedRepository = ApiRekaSignalRepository())
        : repository;
    try {
      return await openAssetDetail(
        context,
        AssetEntityRef(kind: AssetEntityKind.asset, id: item.targetId),
        repository: assetRepository,
        coreRecordsOnly: true,
        overdueReminder: item.type == 'overdue' && resolvedRepository != null
            ? RekaOverdueReminderContext(
                onSnooze: (value) async {
                  await resolvedRepository.snooze(item.id, value);
                  bumpData();
                },
                onDismiss: () async {
                  await resolvedRepository.dismiss(item.id);
                  bumpData();
                },
              )
            : null,
      );
    } finally {
      ownedRepository?.dispose();
    }
  }
  if (item.targetType != 'skill') return;

  final label = item.title.replaceFirst(RegExp(r'\s*还没有记录\s*$'), '').trim();
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (routeContext) => Scaffold(
        backgroundColor: routeContext.themeV2.background,
        body: SafeArea(
          bottom: false,
          child: ThemeV2AssetListPage.assets(
            meta: SkillMeta('◌', label.isEmpty ? item.targetId : label, 'gray'),
            skillName: item.targetId,
            initialAssets: const [],
            specs: const {},
            coreRecordsOnly: true,
            contentBottomPadding: ThemeV2Spacing.lg,
            onBack: () => Navigator.of(routeContext).maybePop(),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openRhythmSignal(
  BuildContext context,
  TodayRekaItem item,
  RekaSignalRepository? repository,
) async {
  final action = await showRekaRhythmDetailSheet(context, item);
  if (action == null || !context.mounted) return;
  if (action == RekaRhythmDetailAction.record) {
    final displayName = item.title
        .replaceFirst(RegExp(r'\s*还没有记录\s*$'), '')
        .trim();
    await openThemeV2SkillCapture(
      context,
      skillName: item.targetId,
      displayName: displayName.isEmpty ? item.targetId : displayName,
    );
    return;
  }
  try {
    await _dismissSignal(repository, item.id);
  } catch (_) {
    if (context.mounted) _showMutationError(context);
  }
}

Future<void> _openReportSignal(
  BuildContext context,
  TodayRekaItem item,
  RekaSignalRepository? repository,
) async {
  final action = await showRekaReportDetailSheet(context, item);
  if (action == null || !context.mounted) return;
  if (action == RekaReportDetailAction.dismiss) {
    try {
      await _dismissSignal(repository, item.id);
    } catch (_) {
      if (context.mounted) _showMutationError(context);
    }
    return;
  }

  switch (item.reportPhase) {
    case 'plan_ready':
      final runId = item.reportRunId ?? item.targetId;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => ReportRunPage(runId: runId)),
      );
      return;
    case 'report_ready':
      final reportId = item.reportId ?? item.targetId;
      final page = await loadReportNotificationTargetPage(
        'report_done',
        'report:$reportId',
      );
      if (page == null || !context.mounted) return;
      try {
        await _dismissSignal(repository, item.id);
      } catch (_) {
        if (context.mounted) _showMutationError(context);
      }
      if (!context.mounted) return;
      await Navigator.of(
        context,
      ).push<void>(MaterialPageRoute<void>(builder: (_) => page));
      return;
    default:
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ReportRunPage(triggerExecutionId: item.targetId),
        ),
      );
      return;
  }
}

void _showMutationError(BuildContext context) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(const SnackBar(content: Text('操作失败，保留这条 Reka 信号')));
}

Future<void> _dismissSignal(
  RekaSignalRepository? repository,
  String signalId,
) async {
  ApiRekaSignalRepository? owned;
  final resolved = repository ?? (owned = ApiRekaSignalRepository());
  try {
    await resolved.dismiss(signalId);
    bumpData();
  } finally {
    owned?.dispose();
  }
}
