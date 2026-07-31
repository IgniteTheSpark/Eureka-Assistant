import 'dart:async';

import 'package:flutter/material.dart';

import '../../today/today_data.dart';
import '../asset_detail/asset_entity_ref.dart';
import '../asset_detail/open_asset_detail.dart';
import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';

const double homePanelRadius = 18;

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
    this.date,
  });

  final TodayData data;
  final VoidCallback onOpenAgenda;
  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final queue = supportedHomeQueueItems(data.noTimeTodos);
    final chain = supportedHomeQueueItems(data.chain);
    final currentDate = date ?? DateTime.now();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(homePanelRadius),
        border: Border.all(color: tokens.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(homePanelRadius),
        child: Column(
          children: [
            _TodayHeader(date: currentDate, data: data),
            Divider(height: 1, color: tokens.border),
            Expanded(
              child: ListView(
                key: const PageStorageKey('theme-v2-today-scroll'),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                children: [
                  const _SectionHeading(title: '下一时刻'),
                  const SizedBox(height: ThemeV2Spacing.sm),
                  _NextMomentCard(item: chain.firstOrNull),
                  const SizedBox(height: ThemeV2Spacing.xl),
                  _SectionHeading(title: 'Reka 队列', count: queue.length),
                  const SizedBox(height: ThemeV2Spacing.sm),
                  _QueuePreview(items: queue),
                  const SizedBox(height: ThemeV2Spacing.xl),
                  _SectionHeading(title: '今日生成', count: data.poolTrueCount),
                  const SizedBox(height: ThemeV2Spacing.sm),
                  _AssetBubbleField(assets: data.pool),
                ],
              ),
            ),
            Divider(height: 1, color: tokens.border),
            _AgendaEntry(onPressed: onOpenAgenda),
          ],
        ),
      ),
    );
  }
}

class _TodayHeader extends StatelessWidget {
  const _TodayHeader({required this.date, required this.data});

  final DateTime date;
  final TodayData data;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final progress = data.todoTotal == 0 ? 0.0 : data.todoDone / data.todoTotal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '今日',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${date.month}月${date.day}日  星期${_weekdays[date.weekday - 1]}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tokens.muted),
                ),
              ],
            ),
          ),
          Semantics(
            label: '今日待办完成 ${data.todoDone}/${data.todoTotal}',
            child: ExcludeSemantics(
              child: SizedBox.square(
                dimension: 42,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 3,
                      backgroundColor: tokens.border,
                      color: tokens.accent,
                    ),
                    Text(
                      '${data.todoDone}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tokens.foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.count});

  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (count != null) ...[
          const SizedBox(width: ThemeV2Spacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: tokens.accentSoft,
              borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
            ),
            child: Text(
              '$count',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: tokens.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _NextMomentCard extends StatelessWidget {
  const _NextMomentCard({required this.item});

  final ChainItem? item;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    if (item == null) {
      return _QuietEmpty(icon: Icons.wb_sunny_outlined, message: '接下来没有已安排的事项');
    }
    final value = item!;
    return Semantics(
      button: true,
      label: '打开 ${value.title}',
      child: Material(
        color: tokens.accentSoft,
        borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
          onTap: () => unawaited(_openChainItem(context, value)),
          child: Padding(
            padding: const EdgeInsets.all(ThemeV2Spacing.lg),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 54,
                  decoration: BoxDecoration(
                    color: tokens.accent,
                    borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
                  ),
                ),
                const SizedBox(width: ThemeV2Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _clock(value.at),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: tokens.accent,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (value.sub.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          value.sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: tokens.muted),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward, size: 18, color: tokens.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QueuePreview extends StatelessWidget {
  const _QueuePreview({required this.items});

  final List<ChainItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _QuietEmpty(
        icon: Icons.check_circle_outline,
        message: '队列已清空',
      );
    }
    final visible = items.take(3).toList();
    return Column(
      children: [
        for (var index = 0; index < visible.length; index++) ...[
          _QueueRow(item: visible[index]),
          if (index != visible.length - 1)
            const SizedBox(height: ThemeV2Spacing.sm),
        ],
        if (items.length > visible.length) ...[
          const SizedBox(height: ThemeV2Spacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '另有 ${items.length - visible.length} 条，展开日程查看',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.themeV2.muted),
            ),
          ),
        ],
      ],
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.item});

  final ChainItem item;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      button: true,
      label: '打开 ${item.title}',
      child: Material(
        color: tokens.background,
        borderRadius: BorderRadius.circular(ThemeV2Radii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(ThemeV2Radii.md),
          onTap: () => unawaited(_openChainItem(context, item)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 7, color: tokens.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: tokens.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AssetBubbleField extends StatelessWidget {
  const _AssetBubbleField({required this.assets});

  final List<PoolAsset> assets;

  @override
  Widget build(BuildContext context) {
    if (assets.isEmpty) {
      return const _QuietEmpty(
        icon: Icons.bubble_chart_outlined,
        message: '记录会在这里聚成今日资产',
      );
    }
    final visible = assets.take(5).toList();
    final overflow = assets.length - visible.length;
    return Container(
      constraints: const BoxConstraints(minHeight: 116),
      padding: const EdgeInsets.symmetric(vertical: ThemeV2Spacing.sm),
      child: Wrap(
        alignment: WrapAlignment.spaceEvenly,
        spacing: 8,
        runSpacing: 10,
        children: [
          for (final asset in visible) _AssetBubble(asset: asset),
          if (overflow > 0) _OverflowBubble(count: overflow),
        ],
      ),
    );
  }
}

class _AssetBubble extends StatelessWidget {
  const _AssetBubble({required this.asset});

  final PoolAsset asset;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      button: true,
      label: '打开资产 ${asset.title}',
      child: Material(
        color: tokens.accentSoft,
        shape: CircleBorder(side: BorderSide(color: tokens.border)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => unawaited(
            openAssetDetail(
              context,
              AssetEntityRef(kind: AssetEntityKind.asset, id: asset.id),
            ),
          ),
          child: SizedBox.square(
            dimension: 76,
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_assetIcon(asset.type), size: 18, color: tokens.accent),
                  const SizedBox(height: 4),
                  Text(
                    asset.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: tokens.foreground,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OverflowBubble extends StatelessWidget {
  const _OverflowBubble({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Container(
      width: 76,
      height: 76,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.background,
        shape: BoxShape.circle,
        border: Border.all(color: tokens.border),
      ),
      child: Text(
        '+$count',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: tokens.muted,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _QuietEmpty extends StatelessWidget {
  const _QuietEmpty({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Container(
      constraints: const BoxConstraints(minHeight: 68),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.background,
        borderRadius: BorderRadius.circular(ThemeV2Radii.md),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: tokens.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgendaEntry extends StatelessWidget {
  const _AgendaEntry({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return SizedBox(
      height: 62,
      child: Padding(
        padding: const EdgeInsets.only(left: 20, right: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '日程',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '展开今天的时间脉络',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: tokens.muted),
                  ),
                ],
              ),
            ),
            ThemeV2IconButton(
              semanticLabel: '打开日程',
              icon: Icons.keyboard_arrow_up,
              color: tokens.foreground,
              onPressed: onPressed,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openChainItem(BuildContext context, ChainItem item) {
  return openAssetDetail(
    context,
    AssetEntityRef(
      kind: item.kind == 'event'
          ? AssetEntityKind.event
          : AssetEntityKind.asset,
      id: item.id,
    ),
  );
}

String _clock(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

IconData _assetIcon(String type) {
  return switch (type.toLowerCase()) {
    'note' => Icons.notes,
    'todo' => Icons.check_circle_outline,
    'contact' => Icons.person_outline,
    'expense' => Icons.receipt_long_outlined,
    _ => Icons.auto_awesome_outlined,
  };
}
