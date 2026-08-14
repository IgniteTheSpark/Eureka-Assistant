import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../today/today_data.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';

List<ChainItem> todayNextGroup(List<ChainItem> items, DateTime now) {
  final nowMinute = DateTime(
    now.year,
    now.month,
    now.day,
    now.hour,
    now.minute,
  );
  final future =
      items
          .where((item) {
            final at = item.at;
            final itemMinute = DateTime(
              at.year,
              at.month,
              at.day,
              at.hour,
              at.minute,
            );
            return item.timed && itemMinute.isAfter(nowMinute);
          })
          .toList(growable: false)
        ..sort((a, b) => a.at.compareTo(b.at));
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
        : '${_timeLabel(first.at)}，${first.title}，'
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
                        mainAxisAlignment: MainAxisAlignment.center,
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
                        children: [
                          SizedBox(
                            width: 54,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _timeLabel(first.at),
                                  style: TextStyle(
                                    color: tokens.foreground,
                                    fontSize: 14,
                                    height: 1,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -.2,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  todayCountdownLabel(first.at, _now),
                                  maxLines: 1,
                                  overflow: TextOverflow.fade,
                                  softWrap: false,
                                  style: TextStyle(
                                    color: tokens.muted,
                                    fontSize: 8,
                                    height: 1,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              first.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.foreground,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (group.length > 1) ...[
                            const SizedBox(width: 4),
                            Text(
                              '+${group.length - 1}',
                              style: TextStyle(
                                color: tokens.muted,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                          Icon(
                            Icons.chevron_right_rounded,
                            color: tokens.muted,
                            size: 15,
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
