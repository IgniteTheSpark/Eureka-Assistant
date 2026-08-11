import 'package:flutter/material.dart';

import '../../timeline/timeline.dart';
import '../../today/today_data.dart';
import '../asset_detail/asset_entity_ref.dart';
import '../asset_detail/open_asset_detail.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../library/asset/asset_list_page.dart';
import '../report/report_run_page.dart';

typedef RekaSignalMutationCallback =
    Future<void> Function(TodayRekaItem item, String action);

typedef RekaSignalTargetCallback =
    Future<void> Function(BuildContext context, TodayRekaItem item);

Future<void> openRekaSignalTarget(
  BuildContext context,
  TodayRekaItem item,
) async {
  if (item.targetId.isEmpty) return;
  if (item.targetType == 'trigger_execution') {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportRunPage(triggerExecutionId: item.targetId),
      ),
    );
    return;
  }
  if (item.targetType == 'asset') {
    return openAssetDetail(
      context,
      AssetEntityRef(kind: AssetEntityKind.asset, id: item.targetId),
      coreRecordsOnly: true,
    );
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
