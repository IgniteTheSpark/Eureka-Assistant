import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../today/today_data.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import 'today_dither_field.dart';
import 'today_region_watermark.dart';

typedef TodaySignalOpenCallback = Future<void> Function(TodayRekaItem item);

enum TodaySignalBirthState { idle, clearing, unfolding }

class TodaySignalBand extends StatefulWidget {
  const TodaySignalBand({
    super.key,
    required this.items,
    this.motion,
    this.onOpenSignal,
    this.onOpenAll,
    this.birthState = TodaySignalBirthState.idle,
    this.birthSignalId,
  });

  final List<TodayRekaItem> items;
  final Animation<double>? motion;
  final TodaySignalOpenCallback? onOpenSignal;
  final VoidCallback? onOpenAll;
  final TodaySignalBirthState birthState;
  final String? birthSignalId;

  @override
  State<TodaySignalBand> createState() => _TodaySignalBandState();
}

class _TodaySignalBandState extends State<TodaySignalBand> {
  static const _laneSpeeds = <double>[24, 31, 27];
  static const _laneGaps = <double>[72, 104, 88];
  static const _stripWidth = 252.0;
  static const _stripHeight = 48.0;

  final Map<String, int> _laneById = {};
  final Map<String, double> _lastX = {};
  final Map<String, double> _pausedX = {};
  final Set<String> _opening = {};

  @override
  void initState() {
    super.initState();
    _reconcileLanes();
  }

  @override
  void didUpdateWidget(covariant TodaySignalBand oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reconcileLanes();
  }

  void _reconcileLanes() {
    final active = widget.items.map((item) => item.id).toSet();
    _laneById.removeWhere((id, _) => !active.contains(id));
    _lastX.removeWhere((id, _) => !active.contains(id));
    _pausedX.removeWhere((id, _) => !active.contains(id));
    _opening.removeWhere((id) => !active.contains(id));

    final loads = List<int>.filled(3, 0);
    for (final lane in _laneById.values) {
      loads[lane]++;
    }
    for (final item in widget.items) {
      if (_laneById.containsKey(item.id)) continue;
      final preferred = item.id.hashCode.abs() % 3;
      var selected = preferred;
      for (var offset = 1; offset < 3; offset++) {
        final candidate = (preferred + offset) % 3;
        if (loads[candidate] < loads[selected]) selected = candidate;
      }
      _laneById[item.id] = selected;
      loads[selected]++;
    }
    final birthSignalId = widget.birthSignalId;
    if (birthSignalId != null && active.contains(birthSignalId)) {
      _laneById[birthSignalId] = 0;
    }
  }

  void _pause(String id) {
    final x = _lastX[id];
    if (x == null || _pausedX.containsKey(id)) return;
    setState(() => _pausedX[id] = x);
  }

  void _resume(String id) {
    if (_opening.contains(id) || !_pausedX.containsKey(id)) return;
    setState(() => _pausedX.remove(id));
  }

  Future<void> _open(TodayRekaItem item) async {
    final callback = widget.onOpenSignal;
    if (callback == null || !_opening.add(item.id)) return;
    _pause(item.id);
    try {
      await callback(item);
    } finally {
      _opening.remove(item.id);
      if (mounted) setState(() => _pausedX.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final motion = widget.motion ?? const AlwaysStoppedAnimation<double>(0);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final lanes = List.generate(3, (_) => <TodayRekaItem>[]);
    for (final item in widget.items) {
      lanes[_laneById[item.id] ?? 0].add(item);
    }
    final birthSignalId = widget.birthSignalId;
    if (birthSignalId != null) {
      lanes[0].sort((a, b) {
        if (a.id == birthSignalId) return -1;
        if (b.id == birthSignalId) return 1;
        return 0;
      });
    }

    return Stack(
      key: const ValueKey('today-signal-band'),
      fit: StackFit.expand,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => AnimatedBuilder(
            animation: motion,
            builder: (context, _) {
              final laneHeight = constraints.maxHeight / 3;
              final placements = <_SignalPlacement>[
                for (var lane = 0; lane < 3; lane++)
                  for (var index = 0; index < lanes[lane].length; index++)
                    _placementFor(
                      item: lanes[lane][index],
                      index: index,
                      lane: lane,
                      laneHeight: laneHeight,
                      viewportWidth: constraints.maxWidth,
                      phase: motion.value,
                      reduceMotion: reduceMotion,
                    ),
              ];
              final visiblePlacements =
                  widget.birthState == TodaySignalBirthState.idle
                  ? placements
                  : placements
                        .where((placement) => placement.lane != 0)
                        .toList(growable: false);
              final tokens = context.themeV2;
              final dark = Theme.of(context).brightness == Brightness.dark;
              return BackdropGroup(
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned.fill(
                      child: TodayDitherField(
                        key: const ValueKey('today-signal-dither-field'),
                        config: TodayDitherFieldConfig.signal(
                          waveColor: tokens.foreground,
                          opacity: dark ? .32 : .40,
                        ),
                        sources: [
                          for (final placement in visiblePlacements)
                            TodayDitherSource.capsule(
                              center: placement.center,
                              size: const Size(_stripWidth, _stripHeight),
                              energy: placement.isPaused ? .18 : 0,
                            ),
                        ],
                        motion: motion,
                        reduceMotion: reduceMotion,
                      ),
                    ),
                    for (var lane = 0; lane < 3; lane++)
                      Positioned(
                        key: ValueKey('today-signal-lane-$lane'),
                        left: 0,
                        right: 0,
                        top: lane * laneHeight,
                        height: laneHeight,
                        child: Stack(
                          clipBehavior: Clip.hardEdge,
                          children: [
                            if (lane == 0 &&
                                widget.birthState != TodaySignalBirthState.idle)
                              const SizedBox.expand(
                                key: ValueKey('today-signal-lane-0-cleared'),
                              )
                            else
                              for (final placement in placements.where(
                                (placement) => placement.lane == lane,
                              ))
                                _positionedStrip(placement: placement),
                          ],
                        ),
                      ),
                    TodayRegionWatermark(
                      count: widget.items.length,
                      label: 'Reka 发现',
                      alignment: Alignment.bottomLeft,
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                      onPressed: widget.onOpenAll,
                      semanticLabel: '查看全部 Reka 发现',
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  _SignalPlacement _placementFor({
    required TodayRekaItem item,
    required int index,
    required int lane,
    required double laneHeight,
    required double viewportWidth,
    required double phase,
    required bool reduceMotion,
  }) {
    final gap = _laneGaps[lane];
    final itemsOnLane = widget.items
        .where((candidate) => _laneById[candidate.id] == lane)
        .length;
    final cycle = viewportWidth + itemsOnLane * (_stripWidth + gap);
    final travel = phase * 120 * _laneSpeeds[lane];
    final slot = index * (_stripWidth + gap) + lane * viewportWidth * .18;
    final movingX = -_stripWidth + ((travel + slot) % cycle);
    final staticX = math.max(0, (viewportWidth - _stripWidth) * .5).toDouble();
    final x = _pausedX[item.id] ?? (reduceMotion ? staticX : movingX);
    _lastX[item.id] = x;
    final localTop = math.max(0, (laneHeight - _stripHeight) / 2).toDouble();
    return _SignalPlacement(
      item: item,
      lane: lane,
      x: x,
      localTop: localTop,
      top: lane * laneHeight + localTop,
      isPaused: _pausedX.containsKey(item.id),
    );
  }

  Widget _positionedStrip({required _SignalPlacement placement}) {
    return Positioned(
      key: ValueKey('today-signal-${placement.item.id}'),
      left: placement.x,
      top: placement.localTop,
      width: _stripWidth,
      height: _stripHeight,
      child: _SignalStrip(
        item: placement.item,
        onTapDown: widget.onOpenSignal == null
            ? null
            : () => _pause(placement.item.id),
        onTapCancel: widget.onOpenSignal == null
            ? null
            : () => _resume(placement.item.id),
        onTap: widget.onOpenSignal == null
            ? null
            : () => unawaited(_open(placement.item)),
      ),
    );
  }
}

class _SignalPlacement {
  const _SignalPlacement({
    required this.item,
    required this.lane,
    required this.x,
    required this.localTop,
    required this.top,
    required this.isPaused,
  });

  final TodayRekaItem item;
  final int lane;
  final double x;
  final double localTop;
  final double top;
  final bool isPaused;

  Offset get center => Offset(x + 126, top + 24);
}

class _SignalStrip extends StatelessWidget {
  const _SignalStrip({
    required this.item,
    this.onTapDown,
    this.onTapCancel,
    this.onTap,
  });

  final TodayRekaItem item;
  final VoidCallback? onTapDown;
  final VoidCallback? onTapCancel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      button: onTap != null,
      label: '${_kindLabel(item.type)}，${item.title}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
        child: BackdropFilter.grouped(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: ColoredBox(
            key: ValueKey('today-signal-glass-${item.id}'),
            color: _signalGlassColor(context, item.type),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
                onTapDown: onTapDown == null ? null : (_) => onTapDown!(),
                onTapCancel: onTapCancel,
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Icon(_kindIcon(item.type), color: tokens.muted, size: 15),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.foreground,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _signalGlassColor(BuildContext context, String type) {
  final base = switch (type) {
    'overdue' => const Color(0xFFE46A5D),
    'rhythm_gap' => const Color(0xFF28A9B8),
    'report' => const Color(0xFF8B6CE8),
    _ => const Color(0xFF25B6D6),
  };
  final dark = Theme.of(context).brightness == Brightness.dark;
  return base.withValues(alpha: dark ? .10 : .055);
}

String _kindLabel(String type) => switch (type) {
  'overdue' => '逾期提醒',
  'rhythm_gap' => '节律发现',
  'report' => '报告发现',
  _ => 'Reka 发现',
};

IconData _kindIcon(String type) => switch (type) {
  'overdue' => Icons.schedule_rounded,
  'rhythm_gap' => Icons.waves_rounded,
  'report' => Icons.description_outlined,
  _ => Icons.auto_awesome_rounded,
};
