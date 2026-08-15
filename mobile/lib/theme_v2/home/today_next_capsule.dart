import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../today/today_data.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';

List<ChainItem> todayNextGroup(List<ChainItem> items, DateTime now) {
  final nowMinute = _minuteOf(now);
  final future =
      items
          .where((item) {
            return item.timed &&
                (item.kind == 'event' || item.kind == 'todo') &&
                _minuteOf(item.at).isAfter(nowMinute);
          })
          .toList(growable: false)
        ..sort((a, b) {
          final byMinute = _minuteOf(a.at).compareTo(_minuteOf(b.at));
          if (byMinute != 0) return byMinute;
          final byKind = _kindRank(a.kind).compareTo(_kindRank(b.kind));
          if (byKind != 0) return byKind;
          return a.id.compareTo(b.id);
        });
  if (future.isEmpty) return const [];
  final first = future.first.at;
  return future
      .where(
        (item) =>
            item.at.year == first.year &&
            item.at.month == first.month &&
            item.at.day == first.day &&
            item.at.hour == first.hour &&
            item.at.minute == first.minute,
      )
      .toList(growable: false);
}

String todayNextSummary(List<ChainItem> group) {
  final first = group.firstOrNull;
  if (first == null) return '';
  final remaining = group.length - 1;
  return remaining > 0 ? '${first.title} +$remaining' : first.title;
}

String todayCountdownLabel(DateTime target, DateTime now) {
  final seconds = target.difference(now).inSeconds;
  final minutes = math.max(1, (seconds / 60).ceil());
  if (minutes < 60) return '$minutes 分钟后';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '$hours 小时后' : '$hours 小时 $remainder 分钟后';
}

class TodayNextCapsule extends StatefulWidget {
  const TodayNextCapsule({
    super.key,
    required this.items,
    required this.now,
    required this.onOpenAgenda,
    this.clock,
  });

  final List<ChainItem> items;
  final DateTime now;
  final ValueListenable<DateTime>? clock;
  final VoidCallback onOpenAgenda;

  @override
  State<TodayNextCapsule> createState() => _TodayNextCapsuleState();
}

class _TodayNextCapsuleState extends State<TodayNextCapsule> {
  Timer? _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = widget.clock?.value ?? widget.now;
    widget.clock?.addListener(_clockChanged);
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant TodayNextCapsule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.clock, widget.clock)) {
      oldWidget.clock?.removeListener(_clockChanged);
      widget.clock?.addListener(_clockChanged);
      _now = widget.clock?.value ?? widget.now;
      _syncTimer();
    } else if (widget.clock == null && oldWidget.now != widget.now) {
      _now = widget.now;
    }
  }

  void _syncTimer() {
    _timer?.cancel();
    _timer = widget.clock == null
        ? Timer.periodic(const Duration(seconds: 15), (_) {
            if (mounted) setState(() => _now = DateTime.now());
          })
        : null;
  }

  void _clockChanged() {
    if (mounted) setState(() => _now = widget.clock!.value);
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.clock?.removeListener(_clockChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final group = todayNextGroup(widget.items, _now);
    final first = group.firstOrNull;
    final tokens = context.themeV2;
    final semanticsLabel = first == null
        ? '今天暂无安排，打开今日安排'
        : '${_timeLabel(first.at)}，${todayNextSummary(group)}，'
              '${todayCountdownLabel(first.at, _now)}，打开今日安排';
    return SizedBox(
      width: 204,
      child: Semantics(
        button: true,
        label: semanticsLabel,
        excludeSemantics: true,
        child: Material(
          key: const ValueKey('today-next-schedule'),
          color: tokens.surface.withValues(alpha: .78),
          borderRadius: BorderRadius.circular(20),
          elevation: 0,
          shadowColor: tokens.foreground.withValues(alpha: .12),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: widget.onOpenAgenda,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: ThemeV2Sizes.minTouchTarget,
                maxWidth: 204,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 9, 6),
                child: first == null
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            '今天暂无安排',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: tokens.muted,
                            size: 15,
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            key: const ValueKey('today-next-meta-column'),
                            width: 54,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _timeLabel(first.at),
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: tokens.foreground,
                                    fontSize: 12,
                                    height: 1,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -.2,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  todayCountdownLabel(first.at, _now),
                                  maxLines: 1,
                                  overflow: TextOverflow.fade,
                                  softWrap: false,
                                  style: TextStyle(
                                    color: tokens.muted,
                                    fontSize: 7.5,
                                    height: 1,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Row(
                              key: const ValueKey('today-next-title-column'),
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Text(
                                    todayNextSummary(group),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      color: tokens.foreground,
                                      fontSize: 10,
                                      height: 1,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: tokens.muted,
                                  size: 14,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _timeLabel(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

DateTime _minuteOf(DateTime value) =>
    DateTime(value.year, value.month, value.day, value.hour, value.minute);

int _kindRank(String kind) => kind == 'event' ? 0 : 1;
