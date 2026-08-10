import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../today/today_data.dart';
import '../asset_detail/asset_entity_ref.dart';
import '../asset_detail/open_asset_detail.dart';
import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../reka/reka_signal_actions.dart';
import 'theme_v2_asset_bubble_field.dart';
import 'theme_v2_gravity_chamber.dart';

const _goalMetadataKeys = <String>{
  'card_type',
  'kind',
  'notification_type',
  'queue_type',
  'skill_name',
  'source',
  'trigger_type',
  'user_skill_name',
};

const _goalMetadataValues = <String>{
  'goal',
  'goal_adjustment',
  'goal_check_in',
  'goal_creation',
  'goal_deadline',
  'goal_progress',
  'goal_settlement',
  'goal_suggestion',
};

/// Removes only records explicitly identified as Goal-generated.
///
/// User-entered titles and descriptions are deliberately ignored, so ordinary
/// content such as "更新个人目标" remains visible.
List<ChainItem> supportedHomeQueueItems(Iterable<ChainItem> items) {
  return items.where((item) => !_hasGoalMetadata(item.card)).toList();
}

List<ChainItem> supportedHomeAgendaItems(Iterable<ChainItem> items) {
  return supportedHomeQueueItems(
    items,
  ).where((item) => item.kind == 'event' || item.kind == 'todo').toList();
}

bool _hasGoalMetadata(Map<String, dynamic> metadata) {
  if (metadata['goal_id'] != null || metadata['goalId'] != null) return true;
  for (final entry in metadata.entries) {
    final key = _normalizeMetadata(entry.key);
    if (_goalMetadataKeys.contains(key)) {
      final value = _normalizeMetadata(entry.value?.toString() ?? '');
      if (_goalMetadataValues.contains(value) || value.startsWith('goal_')) {
        return true;
      }
    }
    if ((key == 'metadata' || key == 'context') && entry.value is Map) {
      if (_hasGoalMetadata((entry.value as Map).cast<String, dynamic>())) {
        return true;
      }
    }
  }
  return false;
}

String _normalizeMetadata(String value) =>
    value.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');

class HomeTodayPanel extends StatelessWidget {
  const HomeTodayPanel({
    super.key,
    required this.data,
    required this.onOpenAgenda,
    required this.chamberHeight,
    this.onOpenReka,
    this.onRekaAction,
    this.onOpenRekaTarget,
    this.onOpenReports,
    this.onCreateReport,
    this.date,
    this.active = true,
  });

  static const nextMomentKey = ValueKey<String>('theme-v2-today-next-moment');
  static const rekaQueueKey = ValueKey<String>('theme-v2-today-reka-queue');
  static const gravityChamberKey = ValueKey<String>(
    'theme-v2-today-gravity-chamber',
  );
  static const assetBubbleFieldKey = ValueKey<String>(
    'theme-v2-today-asset-bubble-field',
  );

  final TodayData data;
  final VoidCallback onOpenAgenda;
  final double chamberHeight;
  final VoidCallback? onOpenReka;
  final RekaSignalMutationCallback? onRekaAction;
  final RekaSignalTargetCallback? onOpenRekaTarget;
  final VoidCallback? onOpenReports;
  final VoidCallback? onCreateReport;
  final DateTime? date;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final queue = data.rekaQueue;
    final chain = supportedHomeQueueItems(data.chain);
    final now = date ?? DateTime.now();
    final todayCount = chain.length;
    final upcoming = chain.where((item) {
      final end = item.dur == null ? item.at : item.at.add(item.dur!);
      return !end.isBefore(now);
    }).toList();

    return Column(
      children: [
        SizedBox(
          key: nextMomentKey,
          width: double.infinity,
          height: 126,
          child: _NextMomentCard(
            item: upcoming.firstOrNull,
            sameTimeItems: _sameTimeItems(upcoming),
            now: now,
            todayCount: todayCount,
            onOpenAgenda: onOpenAgenda,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          key: rekaQueueKey,
          width: double.infinity,
          height: 188,
          child: _RekaQueue(
            items: queue,
            onOpenAll: onOpenReka,
            onAction: onRekaAction,
            onOpenTarget: onOpenRekaTarget,
            onOpenReports: onOpenReports,
            onCreateReport: onCreateReport,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          key: gravityChamberKey,
          width: double.infinity,
          height: chamberHeight,
          child: ThemeV2GravityChamber(
            child: ThemeV2AssetBubbleField(
              key: assetBubbleFieldKey,
              assets: data.pool,
              trueCount: data.poolTrueCount,
              skills: data.skills,
              active: active,
            ),
          ),
        ),
      ],
    );
  }
}

List<ChainItem> _sameTimeItems(List<ChainItem> chain) {
  if (chain.isEmpty) return const [];
  final at = chain.first.at;
  return chain.skip(1).where((item) => item.at.isAtSameMomentAs(at)).toList();
}

class _NextMomentCard extends StatelessWidget {
  const _NextMomentCard({
    required this.item,
    required this.sameTimeItems,
    required this.now,
    required this.todayCount,
    required this.onOpenAgenda,
  });

  final ChainItem? item;
  final List<ChainItem> sameTimeItems;
  final DateTime now;
  final int todayCount;
  final VoidCallback onOpenAgenda;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final value = item;
    final countdown = value == null
        ? null
        : _nextCountdown(value.at.difference(now));
    return Material(
      color: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
        side: BorderSide(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: value == null
          ? _NextMomentEmpty(onOpenAgenda: onOpenAgenda)
          : Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: 16,
                  top: 14,
                  child: Text(
                    'NEXT / ${_clock(value.at)}',
                    style: _mono(
                      color: tokens.accent,
                      size: 9,
                      weight: FontWeight.w700,
                      letterSpacing: 0.9,
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  top: 31,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        countdown!.value,
                        style: _geist(
                          color: tokens.foreground,
                          size: 34,
                          weight: FontWeight.w600,
                          letterSpacing: -1.4,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        countdown.unit,
                        style: _geist(
                          color: tokens.muted,
                          size: 11,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 126,
                  top: 29,
                  width: 186,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => unawaited(_openChainItem(context, value)),
                    child: Semantics(
                      button: true,
                      label: '打开 ${value.title}',
                      child: Text(
                        value.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _geist(
                          color: tokens.foreground,
                          size: 15,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 126,
                  top: 53,
                  child: Text(
                    _timeRange(value),
                    style: _mono(
                      color: tokens.muted,
                      size: 9,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                Positioned(
                  left: 126,
                  top: 73,
                  child: ColoredBox(
                    color: tokens.border,
                    child: const SizedBox(width: 228, height: 1),
                  ),
                ),
                Positioned(
                  left: 126,
                  top: 83,
                  width: 160,
                  child: Text(
                    _sameTimeSummary(sameTimeItems),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _geist(
                      color: tokens.foreground,
                      size: 11,
                      weight: FontWeight.w500,
                    ),
                  ),
                ),
                if (sameTimeItems.isNotEmpty)
                  Positioned(
                    right: 16,
                    top: 84,
                    child: Text(
                      '${sameTimeItems.length} 个代办',
                      style: _mono(
                        color: tokens.accent,
                        size: 8,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                Positioned(
                  left: 16,
                  bottom: 14,
                  width: 104,
                  child: Text(
                    '今日共 $todayCount 项',
                    style: _mono(
                      color: tokens.muted,
                      size: 9,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                Positioned(
                  right: 7,
                  top: 7,
                  width: 44,
                  height: 44,
                  child: ThemeV2IconButton(
                    semanticLabel: '打开日程',
                    icon: Icons.keyboard_arrow_down_rounded,
                    iconSize: 20,
                    color: tokens.muted,
                    onPressed: onOpenAgenda,
                  ),
                ),
              ],
            ),
    );
  }
}

class _NextMomentEmpty extends StatelessWidget {
  const _NextMomentEmpty({required this.onOpenAgenda});

  final VoidCallback onOpenAgenda;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Stack(
      children: [
        Positioned(
          left: 16,
          top: 16,
          child: Text(
            'NEXT',
            style: _mono(
              color: tokens.accent,
              size: 9,
              weight: FontWeight.w700,
              letterSpacing: 0.9,
            ),
          ),
        ),
        Center(
          child: Text(
            '接下来没有已安排的事项',
            style: _geist(color: tokens.muted, size: 11),
          ),
        ),
        Positioned(
          right: 7,
          top: 7,
          width: 44,
          height: 44,
          child: ThemeV2IconButton(
            semanticLabel: '打开日程',
            icon: Icons.keyboard_arrow_down_rounded,
            iconSize: 20,
            color: tokens.muted,
            onPressed: onOpenAgenda,
          ),
        ),
      ],
    );
  }
}

class _RekaQueue extends StatelessWidget {
  const _RekaQueue({
    required this.items,
    required this.onOpenAll,
    required this.onAction,
    required this.onOpenTarget,
    required this.onOpenReports,
    required this.onCreateReport,
  });

  final List<TodayRekaItem> items;
  final VoidCallback? onOpenAll;
  final RekaSignalMutationCallback? onAction;
  final RekaSignalTargetCallback? onOpenTarget;
  final VoidCallback? onOpenReports;
  final VoidCallback? onCreateReport;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Material(
      color: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
        side: BorderSide(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 14,
            top: 12,
            child: Text(
              'Reka',
              style: _geist(
                color: tokens.foreground,
                size: 15,
                weight: FontWeight.w600,
              ),
            ),
          ),
          Positioned(
            left: 58,
            top: 17,
            child: Text(
              '${items.length} 条发现',
              style: _mono(
                color: tokens.muted,
                size: 8.5,
                weight: FontWeight.w600,
              ),
            ),
          ),
          Positioned(
            right: 4,
            top: 0,
            width: 62,
            height: 44,
            child: TextButton(
              onPressed: onOpenAll,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                foregroundColor: tokens.accent,
                textStyle: _geist(
                  color: tokens.accent,
                  size: 10,
                  weight: FontWeight.w600,
                ),
              ),
              child: const Text('查看全部'),
            ),
          ),
          if (items.isNotEmpty)
            Positioned(
              left: 12,
              top: 44,
              width: 351,
              height: 132,
              child: ListView.separated(
                key: const ValueKey('theme-v2-reka-signal-list'),
                primary: false,
                padding: EdgeInsets.zero,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) => SizedBox(
                  key: ValueKey('theme-v2-reka-row-${items[index].id}'),
                  height: 56,
                  child: _RekaQueueRow(
                    item: items[index],
                    onAction: onAction,
                    onOpenTarget: onOpenTarget,
                  ),
                ),
              ),
            )
          else
            Positioned(
              left: 12,
              top: 50,
              width: 351,
              height: 104,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '暂时没有新的发现',
                    style: _geist(color: tokens.muted, size: 11),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: onOpenReports,
                        child: const Text('查看历史报告'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: onCreateReport,
                        child: const Text('生成新报告'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RekaQueueRow extends StatelessWidget {
  const _RekaQueueRow({
    required this.item,
    required this.onAction,
    required this.onOpenTarget,
  });

  final TodayRekaItem item;
  final RekaSignalMutationCallback? onAction;
  final RekaSignalTargetCallback? onOpenTarget;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      button: true,
      label: '打开 ${item.title}',
      child: Material(
        color: tokens.accentSoft,
        borderRadius: BorderRadius.circular(ThemeV2Radii.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: item.targetId.isEmpty
              ? null
              : () => unawaited(_openTarget(context)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(
                  _rekaIcon(item.type),
                  key: ValueKey('theme-v2-reka-icon-${item.type}'),
                  size: 18,
                  color: tokens.accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _geist(
                          color: tokens.foreground,
                          size: 11.5,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.body.isEmpty
                            ? _rekaTypeLabel(item.type)
                            : item.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _mono(
                          color: tokens.muted,
                          size: 8,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (_menuActions.isNotEmpty)
                  SizedBox.square(
                    dimension: 44,
                    child: Semantics(
                      button: true,
                      label: '更多操作 ${item.title}',
                      child: PopupMenuButton<String>(
                        key: ValueKey('theme-v2-reka-menu-${item.id}'),
                        tooltip: '',
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          size: 20,
                          color: tokens.muted,
                        ),
                        onSelected: (action) => unawaited(
                          action == 'reschedule'
                              ? _openTarget(context)
                              : onAction!(item, action),
                        ),
                        itemBuilder: (_) => [
                          for (final action in _menuActions)
                            PopupMenuItem<String>(
                              value: action,
                              child: Text(_actionLabel(action)),
                            ),
                        ],
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: tokens.muted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<String> get _menuActions => onAction == null
      ? const []
      : item.actions
            .where(
              (action) =>
                  action == 'complete' ||
                  action == 'reschedule' ||
                  action == 'dismiss',
            )
            .toList(growable: false);

  Future<void> _openTarget(BuildContext context) {
    final callback = onOpenTarget;
    return callback == null
        ? openRekaSignalTarget(context, item)
        : callback(context, item);
  }
}

IconData _rekaIcon(String type) => switch (type) {
  'overdue' => Icons.schedule_outlined,
  'rhythm_gap' => Icons.waves_outlined,
  _ => Icons.lightbulb_outline_rounded,
};

String _rekaTypeLabel(String type) => switch (type) {
  'overdue' => '逾期提醒',
  'rhythm_gap' => '节律提醒',
  _ => 'Reka 信号',
};

String _actionLabel(String action) => switch (action) {
  'complete' => '标记完成',
  'reschedule' => '调整时间',
  'dismiss' => '忽略提醒',
  _ => action,
};

Future<void> _openChainItem(BuildContext context, ChainItem item) {
  return openAssetDetail(
    context,
    AssetEntityRef(
      kind: item.kind == 'event'
          ? AssetEntityKind.event
          : AssetEntityKind.asset,
      id: item.id,
    ),
    coreRecordsOnly: true,
  );
}

({String value, String unit}) _nextCountdown(Duration duration) {
  final minutes = math.max(0, duration.inMinutes);
  if (minutes < 60) return (value: '$minutes', unit: '分钟后');
  final rounded = (minutes / 60).toStringAsFixed(1);
  return (
    value: rounded.endsWith('.0')
        ? rounded.substring(0, rounded.length - 2)
        : rounded,
    unit: '小时后',
  );
}

String _clock(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _timeRange(ChainItem item) {
  final start = _clock(item.at);
  final duration = item.dur;
  if (duration == null) return start;
  return '$start–${_clock(item.at.add(duration))}';
}

String _sameTimeSummary(List<ChainItem> items) {
  if (items.isEmpty) return '同一时刻暂无其他事项';
  return items.take(2).map((item) => item.title).join(' · ');
}

TextStyle _geist({
  required Color color,
  required double size,
  FontWeight weight = FontWeight.w400,
  double? letterSpacing,
}) {
  return TextStyle(
    color: color,
    fontFamily: 'Geist',
    fontSize: size,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: 1.15,
  );
}

TextStyle _mono({
  required Color color,
  required double size,
  FontWeight weight = FontWeight.w400,
  double? letterSpacing,
}) {
  return TextStyle(
    color: color,
    fontFamily: 'Geist Mono',
    fontSize: size,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: 1.15,
  );
}
