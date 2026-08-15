import 'dart:async';

import 'package:flutter/material.dart';

import '../../timeline/timeline.dart';
import '../../today/today_data.dart';
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
    final items = supportedHomeAgendaItems(data.chain)
      ..sort((a, b) => a.at.compareTo(b.at));
    final groups = _groupByMoment(items);

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
        child: Column(
          children: [
            _AgendaHeader(
              date: currentDate,
              itemCount: items.length,
              onClose: onCloseAgenda,
            ),
            Expanded(
              child: groups.isEmpty
                  ? Center(
                      child: Text(
                        '今天的时间脉络还很安静',
                        style: _geist(color: tokens.muted, size: 11),
                      ),
                    )
                  : Stack(
                      children: [
                        Positioned(
                          key: spineKey,
                          left: 77,
                          top: 0,
                          bottom: 0,
                          width: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  tokens.border.withValues(alpha: .3),
                                  tokens.accent.withValues(alpha: .62),
                                  tokens.border.withValues(alpha: .3),
                                ],
                              ),
                            ),
                          ),
                        ),
                        ListView.separated(
                          key: const ValueKey('theme-v2-agenda-scroll'),
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                          itemCount: groups.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) => _AgendaMomentRow(
                            index: index,
                            items: groups[index],
                            skills: data.skills,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgendaHeader extends StatelessWidget {
  const _AgendaHeader({
    required this.date,
    required this.itemCount,
    required this.onClose,
  });

  final DateTime date;
  final int itemCount;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return SizedBox(
      height: 72,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 7),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '今日安排',
                        style: _geist(
                          color: tokens.foreground,
                          size: 16,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '$itemCount 项 · 现在 ${_clock(date)}',
                        style: _mono(
                          color: tokens.muted,
                          size: 8.5,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    _dateLine(date),
                    style: _mono(
                      color: tokens.accent,
                      size: 9,
                      weight: FontWeight.w700,
                      letterSpacing: .4,
                    ),
                  ),
                ],
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -7),
              child: ThemeV2IconButton(
                semanticLabel: '收起日程',
                icon: Icons.keyboard_arrow_up_rounded,
                iconSize: 20,
                color: tokens.muted,
                onPressed: onClose,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgendaMomentRow extends StatelessWidget {
  const _AgendaMomentRow({
    required this.index,
    required this.items,
    required this.skills,
  });

  final int index;
  final List<ChainItem> items;
  final Map<String, SkillMeta> skills;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          key: ValueKey('theme-v2-agenda-time-$index'),
          width: 53,
          child: Padding(
            padding: const EdgeInsets.only(top: 11),
            child: Text(
              _agendaTimeLabel(items),
              textAlign: TextAlign.right,
              style: _mono(
                color: tokens.accent,
                size: 9,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ),
        SizedBox(
          width: 21,
          child: Padding(
            padding: const EdgeInsets.only(top: 13),
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: tokens.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: tokens.surface, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: tokens.accent.withValues(alpha: .24),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Material(
            key: ValueKey('theme-v2-agenda-group-$index'),
            color: tokens.background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
              side: BorderSide(color: tokens.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (
                  var itemIndex = 0;
                  itemIndex < items.length;
                  itemIndex++
                ) ...[
                  if (itemIndex > 0) Divider(height: 1, color: tokens.border),
                  _AgendaItemRow(item: items[itemIndex], skills: skills),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AgendaItemRow extends StatelessWidget {
  const _AgendaItemRow({required this.item, required this.skills});

  final ChainItem item;
  final Map<String, SkillMeta> skills;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final meta = resolveMeta(item.kind, skills);
    final duration = item.kind == 'event' ? item.dur : null;
    return Semantics(
      button: true,
      label: '打开 ${item.title}',
      child: InkWell(
        key: ValueKey('theme-v2-agenda-item-${item.kind}-${item.id}'),
        onTap: () => unawaited(_openItem(context, item)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Text(
                  meta.icon,
                  key: ValueKey('theme-v2-agenda-icon-${item.kind}-${item.id}'),
                  style: TextStyle(
                    fontSize: 16,
                    height: 1,
                    color: item.done ? tokens.muted : null,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        _geist(
                          color: item.done ? tokens.muted : tokens.foreground,
                          size: 11,
                          weight: FontWeight.w600,
                        ).copyWith(
                          decoration: item.done
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                  ),
                ),
                if (duration != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${duration.inMinutes}m',
                    style: _mono(color: tokens.muted, size: 8),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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

bool _sameMinute(DateTime a, DateTime b) =>
    a.year == b.year &&
    a.month == b.month &&
    a.day == b.day &&
    a.hour == b.hour &&
    a.minute == b.minute;

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

String _agendaTimeLabel(List<ChainItem> items) {
  final first = items.first;
  final duration = first.dur;
  if (items.length != 1 ||
      first.kind != 'event' ||
      duration == null ||
      duration <= Duration.zero) {
    return _clock(first.at);
  }
  return '${_clock(first.at)}–${_clock(first.at.add(duration))}';
}

TextStyle _geist({
  required Color color,
  required double size,
  FontWeight weight = FontWeight.w400,
  double? letterSpacing,
}) => TextStyle(
  color: color,
  fontFamily: 'Geist',
  fontSize: size,
  fontWeight: weight,
  letterSpacing: letterSpacing,
  height: 1.15,
);

TextStyle _mono({
  required Color color,
  required double size,
  FontWeight weight = FontWeight.w400,
  double? letterSpacing,
}) => TextStyle(
  color: color,
  fontFamily: 'Geist Mono',
  fontSize: size,
  fontWeight: weight,
  letterSpacing: letterSpacing,
  height: 1.15,
);
