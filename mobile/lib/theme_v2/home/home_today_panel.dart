import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../today/today_data.dart';
import '../asset_detail/asset_entity_ref.dart';
import '../asset_detail/open_asset_detail.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';

const double homePanelRadius = 19;

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

  static const nextMomentKey = ValueKey<String>('theme-v2-today-next-moment');
  static const rekaQueueKey = ValueKey<String>('theme-v2-today-reka-queue');
  static const assetBubbleFieldKey = ValueKey<String>(
    'theme-v2-today-asset-bubble-field',
  );

  final TodayData data;
  final VoidCallback onOpenAgenda;
  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final queue = supportedHomeQueueItems(data.noTimeTodos);
    final chain = supportedHomeQueueItems(data.chain);
    final now = date ?? DateTime.now();
    final todayCount = chain.length;
    final upcoming = chain.where((item) {
      final end = item.dur == null ? item.at : item.at.add(item.dur!);
      return !end.isBefore(now);
    }).toList();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(homePanelRadius),
        border: Border.all(color: tokens.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A101828),
            offset: Offset(0, 10),
            blurRadius: 28,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(homePanelRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _AssetBubbleField(
              key: assetBubbleFieldKey,
              assets: data.pool,
              trueCount: data.poolTrueCount,
            ),
            Positioned(
              left: 12,
              top: 14,
              child: Text(
                '今日',
                style: _geist(
                  color: tokens.foreground,
                  size: 16,
                  weight: FontWeight.w600,
                ),
              ),
            ),
            Positioned(
              left: 57,
              top: 18,
              child: Text(
                '$todayCount 项 · ${data.poolTrueCount} 个生成',
                style: _mono(
                  color: tokens.muted,
                  size: 8.5,
                  weight: FontWeight.w600,
                ),
              ),
            ),
            Positioned(
              left: 173,
              top: 9,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: const SizedBox(width: 48, height: 3),
              ),
            ),
            Positioned(
              left: 12,
              top: 52,
              width: 371,
              height: 126,
              child: _NextMomentCard(
                key: nextMomentKey,
                item: upcoming.firstOrNull,
                sameTimeItems: _sameTimeItems(upcoming),
                now: now,
                todayCount: todayCount,
                onOpenAgenda: onOpenAgenda,
              ),
            ),
            Positioned(
              left: 12,
              top: 186,
              width: 371,
              height: 188,
              child: _RekaQueue(
                key: rekaQueueKey,
                items: queue,
                onOpenAgenda: onOpenAgenda,
              ),
            ),
          ],
        ),
      ),
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
    super.key,
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
                  child: Text(
                    '${_minutesUntil(value.at, now)}',
                    style: _geist(
                      color: tokens.foreground,
                      size: 34,
                      weight: FontWeight.w600,
                      letterSpacing: -1.4,
                    ),
                  ),
                ),
                Positioned(
                  left: 58,
                  top: 50,
                  child: Text(
                    '分钟后',
                    style: _geist(
                      color: tokens.muted,
                      size: 11,
                      weight: FontWeight.w500,
                    ),
                  ),
                ),
                Positioned(
                  left: 126,
                  top: 29,
                  width: 220,
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
                  left: 4,
                  bottom: 0,
                  width: 116,
                  height: 44,
                  child: Semantics(
                    button: true,
                    label: '打开日程',
                    onTap: onOpenAgenda,
                    child: ExcludeSemantics(
                      child: TextButton(
                        onPressed: onOpenAgenda,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.only(left: 12),
                          alignment: Alignment.centerLeft,
                          foregroundColor: tokens.muted,
                          textStyle: _mono(
                            color: tokens.muted,
                            size: 9,
                            weight: FontWeight.w600,
                          ),
                        ),
                        child: Text('今日共 $todayCount 项  ↗'),
                      ),
                    ),
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
          left: 4,
          bottom: 0,
          width: 116,
          height: 44,
          child: TextButton(
            onPressed: onOpenAgenda,
            child: const Text('打开今日日程  ↗'),
          ),
        ),
      ],
    );
  }
}

class _RekaQueue extends StatelessWidget {
  const _RekaQueue({
    super.key,
    required this.items,
    required this.onOpenAgenda,
  });

  final List<ChainItem> items;
  final VoidCallback onOpenAgenda;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final priority = items.firstOrNull;
    final secondary = items.skip(1).take(1).toList();
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
              '${items.length} 条待处理',
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
              onPressed: onOpenAgenda,
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
          if (priority != null)
            Positioned(
              left: 12,
              top: 42,
              width: 351,
              height: 62,
              child: _PriorityCandidate(item: priority),
            )
          else
            Positioned(
              left: 12,
              top: 50,
              width: 351,
              height: 104,
              child: Center(
                child: Text(
                  '暂时没有待处理',
                  style: _geist(color: tokens.muted, size: 11),
                ),
              ),
            ),
          for (var index = 0; index < secondary.length; index++)
            Positioned(
              left: 12,
              top: 112 + index * 36,
              width: 351,
              height: 32,
              child: _SecondaryCandidate(item: secondary[index]),
            ),
          Positioned(
            right: 4,
            top: 45,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.background,
                borderRadius: BorderRadius.circular(1),
              ),
              child: const SizedBox(width: 2, height: 128),
            ),
          ),
          Positioned(
            right: 4,
            top: 45,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.accent,
                borderRadius: BorderRadius.circular(1),
              ),
              child: SizedBox(
                width: 2,
                height: items.length > 3
                    ? 34
                    : math.max(34, 128 - items.length * 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PriorityCandidate extends StatelessWidget {
  const _PriorityCandidate({required this.item});

  final ChainItem item;

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
          onTap: () => unawaited(_openChainItem(context, item)),
          child: Stack(
            children: [
              Positioned(
                left: 12,
                top: 12,
                child: Icon(
                  Icons.business_center_outlined,
                  size: 18,
                  color: tokens.accent,
                ),
              ),
              Positioned(
                left: 40,
                top: 8,
                width: 236,
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _geist(
                    color: tokens.foreground,
                    size: 12,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
              Positioned(
                left: 40,
                top: 29,
                width: 236,
                child: Text(
                  _queueMeta(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _mono(
                    color: tokens.muted,
                    size: 8.5,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
              Positioned(
                right: 12,
                top: 22,
                child: Text(
                  '查看',
                  style: _geist(
                    color: tokens.accent,
                    size: 10,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryCandidate extends StatelessWidget {
  const _SecondaryCandidate({required this.item});

  final ChainItem item;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      button: true,
      label: '打开 ${item.title}',
      child: InkWell(
        onTap: () => unawaited(_openChainItem(context, item)),
        child: Row(
          children: [
            Icon(Icons.layers_outlined, size: 15, color: tokens.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _geist(
                  color: tokens.foreground,
                  size: 10.5,
                  weight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              item.sub.trim().isEmpty ? '待处理' : item.sub,
              style: _mono(
                color: tokens.muted,
                size: 7.5,
                weight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 36),
          ],
        ),
      ),
    );
  }
}

class _AssetBubbleField extends StatelessWidget {
  const _AssetBubbleField({
    super.key,
    required this.assets,
    required this.trueCount,
  });

  final List<PoolAsset> assets;
  final int trueCount;

  static const _slots = <({double x, double y, double size})>[
    (x: 4, y: 665, size: 70),
    (x: 63, y: 687, size: 48),
    (x: 105, y: 650, size: 72),
    (x: 165, y: 680, size: 58),
    (x: 215, y: 644, size: 80),
    (x: 288, y: 684, size: 52),
    (x: 330, y: 653, size: 64),
    (x: 15, y: 615, size: 52),
    (x: 57, y: 628, size: 44),
    (x: 135, y: 602, size: 50),
    (x: 180, y: 620, size: 38),
    (x: 300, y: 608, size: 46),
    (x: 350, y: 620, size: 38),
    (x: 30, y: 570, size: 38),
    (x: 78, y: 578, size: 54),
    (x: 150, y: 558, size: 42),
    (x: 244, y: 576, size: 56),
    (x: 318, y: 558, size: 46),
    (x: 198, y: 548, size: 34),
    (x: 12, y: 535, size: 30),
    (x: 356, y: 536, size: 34),
    (x: 114, y: 532, size: 32),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final visible = assets.take(_slots.length).toList();
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 238,
          top: 450,
          child: IgnorePointer(
            child: Text(
              '$trueCount',
              style: _geist(
                color: tokens.accent.withValues(alpha: 0.07),
                size: 112,
                weight: FontWeight.w700,
                letterSpacing: -6,
              ),
            ),
          ),
        ),
        Positioned(
          left: 286,
          top: 548,
          child: IgnorePointer(
            child: Text(
              '今日生成',
              style: _mono(
                color: tokens.accent.withValues(alpha: 0.28),
                size: 9,
                weight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
        for (var index = visible.length - 1; index >= 0; index--)
          Positioned(
            left: _slots[index].x,
            top: _slots[index].y,
            width: _slots[index].size,
            height: _slots[index].size,
            child: _AssetBubble(
              asset: visible[index],
              index: index,
              size: _slots[index].size,
            ),
          ),
      ],
    );
  }
}

class _AssetBubble extends StatelessWidget {
  const _AssetBubble({
    required this.asset,
    required this.index,
    required this.size,
  });

  final PoolAsset asset;
  final int index;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final highlighted = index < 5;
    final decoration = BoxDecoration(
      color: highlighted ? null : tokens.background.withValues(alpha: 0.78),
      gradient: highlighted ? _bubbleGradient(context, index) : null,
      shape: BoxShape.circle,
      border: Border.all(
        color: highlighted
            ? Colors.white.withValues(alpha: 0.4)
            : tokens.border,
      ),
      boxShadow: highlighted
          ? const [
              BoxShadow(
                color: Color(0x55697BFF),
                offset: Offset(0, 5),
                blurRadius: 14,
                spreadRadius: -5,
              ),
            ]
          : null,
    );
    return Semantics(
      button: true,
      label: '打开资产 ${asset.title}',
      child: DecoratedBox(
        decoration: decoration,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => unawaited(
              openAssetDetail(
                context,
                AssetEntityRef(kind: AssetEntityKind.asset, id: asset.id),
              ),
            ),
            child: Center(
              child: Icon(
                _assetIcon(asset.type),
                size: math.min(22, size * 0.31),
                color: highlighted ? Colors.white : tokens.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

LinearGradient _bubbleGradient(BuildContext context, int index) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (index) {
    0 => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        dark ? const Color(0xFF8A82FF) : const Color(0xFF25B6D6),
        const Color(0xFF58D6FF),
      ],
    ),
    1 => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF8A82FF), Color(0xFFD06BFF)],
    ),
    2 => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF32D7A1), Color(0xFF58D6FF)],
    ),
    3 => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFF9B68), Color(0xFFE36BFF)],
    ),
    _ => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF6F7CFF), Color(0xFF58D6FF)],
    ),
  };
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

int _minutesUntil(DateTime value, DateTime now) {
  return math.max(0, value.difference(now).inMinutes);
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

String _queueMeta(ChainItem item) {
  final time = item.timed ? _clock(item.at) : '待处理';
  if (item.sub.trim().isEmpty) return time;
  return '$time · ${item.sub}';
}

IconData _assetIcon(String type) {
  return switch (type.toLowerCase()) {
    'idea' => Icons.lightbulb_outline,
    'todo' => Icons.check_box_outlined,
    'event' || 'calendar' => Icons.calendar_today_outlined,
    'book' => Icons.menu_book_outlined,
    'expense' => Icons.restaurant_outlined,
    'contact' => Icons.person_outline,
    'audio' || 'voice' => Icons.mic_none_outlined,
    'image' || 'photo' => Icons.image_outlined,
    'location' => Icons.location_on_outlined,
    'note' => Icons.description_outlined,
    _ => Icons.auto_awesome_outlined,
  };
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
