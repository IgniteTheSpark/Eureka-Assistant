import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../today/today_data.dart';
import '../../timeline/timeline.dart';
import '../asset_detail/asset_entity_ref.dart';
import '../asset_detail/open_asset_detail.dart';
import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import 'home_today_panel.dart';
import 'theme_v2_gravity_chamber.dart';

class HomeAgendaPanel extends StatelessWidget {
  const HomeAgendaPanel({
    super.key,
    required this.data,
    required this.onCloseAgenda,
    this.date,
  });

  static const spineKey = ValueKey<String>('theme-v2-agenda-spine');

  final TodayData data;
  final VoidCallback onCloseAgenda;
  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final currentDate = date ?? DateTime.now();
    final items = supportedHomeQueueItems(data.chain)
      ..sort((a, b) => a.at.compareTo(b.at));
    final groups = _groupByMoment(items).take(_agendaSlots.length).toList();
    final currentMarkerTop = _markerTop(groups, currentDate);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(themeV2HomePanelRadius),
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
        borderRadius: BorderRadius.circular(themeV2HomePanelRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _AgendaBubbleBackdrop(assets: data.pool, skills: data.skills),
            const Positioned(
              left: 0,
              top: 40,
              right: 0,
              bottom: 0,
              child: _AgendaGlass(),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _FishboneConnectorPainter(
                    color: tokens.border,
                    accent: tokens.accent,
                    visibleCount: groups.length,
                  ),
                ),
              ),
            ),
            Positioned(
              key: spineKey,
              left: 197,
              top: 96,
              width: 1,
              height: 606,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      tokens.border.withValues(alpha: 0.35),
                      tokens.accent.withValues(alpha: 0.58),
                      tokens.border.withValues(alpha: 0.35),
                    ],
                  ),
                ),
              ),
            ),
            for (var index = 0; index < groups.length; index++)
              Positioned(
                left: _agendaSlots[index].left,
                top: _agendaSlots[index].top,
                width: 148,
                height: groups[index].length > 1
                    ? math.min(164, 78 + (groups[index].length - 1) * 43)
                    : 78,
                child: _AgendaCard(
                  key: ValueKey<String>('theme-v2-agenda-card-$index'),
                  items: groups[index],
                ),
              ),
            if (groups.isEmpty)
              Positioned(
                left: 58,
                top: 292,
                width: 279,
                child: Text(
                  '今天的时间脉络还很安静',
                  textAlign: TextAlign.center,
                  style: _geist(color: tokens.muted, size: 11),
                ),
              ),
            Positioned(
              left: 158,
              top: currentMarkerTop + 12,
              width: 78,
              height: 1,
              child: ColoredBox(color: tokens.accent.withValues(alpha: 0.6)),
            ),
            Positioned(
              left: 166,
              top: currentMarkerTop,
              width: 62,
              height: 24,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.accent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: tokens.accent.withValues(alpha: 0.24),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    _clock(currentDate),
                    style: _mono(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF101319)
                          : Colors.white,
                      size: 8.5,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              top: 14,
              child: Text(
                '今日安排',
                style: _geist(
                  color: tokens.foreground,
                  size: 16,
                  weight: FontWeight.w600,
                ),
              ),
            ),
            Positioned(
              left: 82,
              top: 18,
              child: Text(
                '${items.length} 项 · 现在 ${_clock(currentDate)}',
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
              left: 16,
              top: 54,
              child: Text(
                _dateLine(currentDate),
                style: _mono(
                  color: tokens.accent,
                  size: 9,
                  weight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            Positioned(
              right: 7,
              top: 37,
              width: 44,
              height: 44,
              child: ThemeV2IconButton(
                semanticLabel: '收起日程',
                icon: Icons.keyboard_arrow_down_rounded,
                iconSize: 20,
                color: tokens.muted,
                onPressed: onCloseAgenda,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _agendaSlots = <({double left, double top})>[
  (left: 18, top: 84),
  (left: 229, top: 168),
  (left: 18, top: 252),
  (left: 229, top: 374),
  (left: 18, top: 576),
];

List<List<ChainItem>> _groupByMoment(List<ChainItem> items) {
  final groups = <List<ChainItem>>[];
  for (final item in items) {
    if (groups.isNotEmpty && _sameMinute(groups.last.first.at, item.at)) {
      groups.last.add(item);
    } else {
      groups.add([item]);
    }
  }
  return groups;
}

bool _sameMinute(DateTime a, DateTime b) {
  return a.year == b.year &&
      a.month == b.month &&
      a.day == b.day &&
      a.hour == b.hour &&
      a.minute == b.minute;
}

double _markerTop(List<List<ChainItem>> groups, DateTime now) {
  final passed = groups.where((group) => !group.first.at.isAfter(now)).length;
  return switch (passed) {
    0 => 72,
    1 => 130,
    2 => 218,
    3 => 328,
    4 => 548,
    _ => 676,
  };
}

class _AgendaGlass extends StatelessWidget {
  const _AgendaGlass();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: dark
                  ? const [
                      Color(0x800A0D15),
                      Color(0xA60A0D15),
                      Color(0xC70A0D15),
                    ]
                  : const [
                      Color(0x66F8FAFC),
                      Color(0x8FF8FAFC),
                      Color(0xB8F8FAFC),
                    ],
            ),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _AgendaBubbleBackdrop extends StatelessWidget {
  const _AgendaBubbleBackdrop({required this.assets, required this.skills});

  final List<PoolAsset> assets;
  final Map<String, SkillMeta> skills;

  static const _slots = <({double x, double y, double size})>[
    (x: 3, y: 640, size: 74),
    (x: 58, y: 680, size: 50),
    (x: 103, y: 628, size: 76),
    (x: 168, y: 676, size: 60),
    (x: 216, y: 625, size: 82),
    (x: 289, y: 676, size: 54),
    (x: 331, y: 642, size: 66),
    (x: 18, y: 590, size: 54),
    (x: 81, y: 578, size: 46),
    (x: 146, y: 566, size: 52),
    (x: 244, y: 570, size: 58),
    (x: 320, y: 552, size: 48),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final visible = assets.take(_slots.length).toList();
    return IgnorePointer(
      child: Opacity(
        opacity: 0.22,
        child: Stack(
          fit: StackFit.expand,
          children: [
            for (var index = 0; index < visible.length; index++)
              Positioned(
                left: _slots[index].x,
                top: _slots[index].y,
                width: _slots[index].size,
                height: _slots[index].size,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index < 5 ? null : tokens.background,
                    gradient: index < 5
                        ? _agendaBubbleGradient(context, index)
                        : null,
                    border: Border.all(color: tokens.border),
                  ),
                  child: Center(
                    child: Text(
                      resolveMeta(visible[index].type, skills).icon,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: math.min(22, _slots[index].size * 0.3),
                        height: 1,
                        color: index < 5 ? Colors.white : tokens.muted,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AgendaCard extends StatelessWidget {
  const _AgendaCard({super.key, required this.items});

  final List<ChainItem> items;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final grouped = items.length > 1;
    return Material(
      color: tokens.surface.withValues(alpha: 0.9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
        side: BorderSide(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: grouped
          ? _GroupedAgendaCard(items: items)
          : _SingleAgendaCard(item: items.single),
    );
  }
}

class _SingleAgendaCard extends StatelessWidget {
  const _SingleAgendaCard({required this.item});

  final ChainItem item;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      button: true,
      label: '打开 ${item.title}',
      child: InkWell(
        onTap: () => unawaited(_openItem(context, item)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _clock(item.at),
                style: _mono(
                  color: tokens.accent,
                  size: 8.5,
                  weight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    _geist(
                      color: tokens.foreground,
                      size: 11,
                      weight: FontWeight.w600,
                    ).copyWith(
                      decoration: item.done ? TextDecoration.lineThrough : null,
                    ),
              ),
              const SizedBox(height: 5),
              Text(
                _agendaMeta(item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _mono(
                  color: tokens.muted,
                  size: 7.5,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupedAgendaCard extends StatelessWidget {
  const _GroupedAgendaCard({required this.items});

  final List<ChainItem> items;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 7),
          child: Row(
            children: [
              Text(
                _clock(items.first.at),
                style: _mono(
                  color: tokens.accent,
                  size: 8.5,
                  weight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${items.length} 项',
                style: _mono(
                  color: tokens.muted,
                  size: 7.5,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        for (final item in items.take(3))
          Expanded(
            child: Semantics(
              button: true,
              label: '打开 ${item.title}',
              child: InkWell(
                onTap: () => unawaited(_openItem(context, item)),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: tokens.border)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: tokens.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              _geist(
                                color: tokens.foreground,
                                size: 10,
                                weight: FontWeight.w600,
                              ).copyWith(
                                decoration: item.done
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FishboneConnectorPainter extends CustomPainter {
  const _FishboneConnectorPainter({
    required this.color,
    required this.accent,
    required this.visibleCount,
  });

  final Color color;
  final Color accent;
  final int visibleCount;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var index = 0; index < visibleCount; index++) {
      final slot = _agendaSlots[index];
      final fromLeft = index.isEven;
      final y = slot.top + 33;
      final path = Path();
      if (fromLeft) {
        path
          ..moveTo(197, y)
          ..cubicTo(186, y, 180, y + 6, 166, y + 6);
      } else {
        path
          ..moveTo(198, y)
          ..cubicTo(209, y, 215, y + 6, 229, y + 6);
      }
      canvas.drawPath(path, paint);
      canvas.drawCircle(
        Offset(fromLeft ? 197 : 198, y),
        2.2,
        Paint()..color = accent,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FishboneConnectorPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.accent != accent ||
        oldDelegate.visibleCount != visibleCount;
  }
}

Future<void> _openItem(BuildContext context, ChainItem item) {
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

String _clock(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _dateLine(DateTime value) {
  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return '${value.month}月${value.day}日 · ${weekdays[value.weekday - 1]}';
}

String _agendaMeta(ChainItem item) {
  final duration = item.dur;
  final prefix = duration == null ? '' : '${duration.inMinutes} 分钟';
  final sub = item.sub.trim();
  if (prefix.isEmpty) return sub.isEmpty ? (item.done ? '已完成' : '待处理') : sub;
  if (sub.isEmpty) return prefix;
  return '$prefix · $sub';
}

LinearGradient _agendaBubbleGradient(BuildContext context, int index) {
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
