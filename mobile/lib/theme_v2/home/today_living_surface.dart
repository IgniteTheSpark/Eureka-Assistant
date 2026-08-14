import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../today/today_data.dart';
import '../foundation/theme_v2_theme.dart';
import 'theme_v2_asset_bubble_field.dart';
import 'today_dither_material.dart';
import 'today_next_capsule.dart';
import 'today_output_coordinator.dart';
import 'today_output_overlay.dart';
import 'today_signal_band.dart';

class TodayLivingSurface extends StatefulWidget {
  const TodayLivingSurface({
    super.key,
    required this.data,
    required this.now,
    required this.active,
    this.onOpenSignal,
    this.onOpenAgenda,
    this.clock,
    this.rekaCenter = Offset.zero,
    this.suppressProduction = false,
    this.outputCoordinator,
  });

  final TodayData data;
  final DateTime now;
  final bool active;
  final ValueChanged<TodayRekaItem>? onOpenSignal;
  final VoidCallback? onOpenAgenda;
  final ValueListenable<DateTime>? clock;
  final Offset rekaCenter;
  final bool suppressProduction;
  final TodayOutputCoordinator? outputCoordinator;

  @override
  State<TodayLivingSurface> createState() => _TodayLivingSurfaceState();
}

class _TodayLivingSurfaceState extends State<TodayLivingSurface> {
  late final TodayOutputCoordinator _coordinator =
      widget.outputCoordinator ?? TodayOutputCoordinator();
  late final bool _ownsCoordinator = widget.outputCoordinator == null;
  bool _reconciling = false;
  final Map<String, Offset> _assetSpawnCenters = {};

  @override
  void initState() {
    super.initState();
    _coordinator.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reconcile();
  }

  @override
  void didUpdateWidget(covariant TodayLivingSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active && oldWidget.active) _coordinator.cancelAll();
    _reconcile();
  }

  void _reconcile() {
    _reconciling = true;
    try {
      _coordinator.reconcile(
        assetIds: widget.data.pool.map((asset) => asset.id),
        signalIds: widget.data.rekaQueue.map((signal) => signal.id),
        rekaCenter: widget.rekaCenter,
        suppressProduction: widget.suppressProduction,
        capacityAvailable: widget.active,
        reduceMotion: MediaQuery.disableAnimationsOf(context),
      );
    } finally {
      _reconciling = false;
    }
  }

  void _changed() {
    if (mounted && !_reconciling) setState(() {});
  }

  @override
  void dispose() {
    _coordinator.removeListener(_changed);
    if (_ownsCoordinator) _coordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stableAssetIds = _coordinator
        .stableAssetIds(widget.data.pool.map((asset) => asset.id))
        .toSet();
    final stableSignalIds = _coordinator
        .stableSignalIds(widget.data.rekaQueue.map((signal) => signal.id))
        .toSet();
    final stableAssets = widget.data.pool
        .where((asset) => stableAssetIds.contains(asset.id))
        .toList(growable: false);
    final stableSignals = widget.data.rekaQueue
        .where((signal) => stableSignalIds.contains(signal.id))
        .toList(growable: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentHeight = constraints.maxHeight - 74;
        final assetChamberTop = 74 + contentHeight / 3;
        return Padding(
          key: const ValueKey('today-living-surface'),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                top: 74,
                child: IgnorePointer(
                  child: TodayDitherMaterial(
                    key: const ValueKey('today-local-dither-field'),
                    shape: TodayDitherShape.field,
                    color: context.themeV2.foreground.withValues(alpha: .09),
                    strength: .24,
                  ),
                ),
              ),
              Column(
                children: [
                  SizedBox(
                    height: 74,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: _TodayDate(now: widget.now)),
                        const SizedBox(width: 12),
                        Flexible(
                          flex: 2,
                          child: TodayNextCapsule(
                            items: widget.data.chain,
                            now: widget.now,
                            clock: widget.clock,
                            onOpenAgenda: widget.onOpenAgenda ?? _noop,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: TodaySignalBand(
                      items: stableSignals,
                      onOpenSignal: widget.onOpenSignal,
                    ),
                  ),
                  Expanded(
                    key: const ValueKey('today-asset-chamber'),
                    flex: 2,
                    child: ThemeV2AssetBubbleField(
                      assets: stableAssets,
                      trueCount: widget.data.poolTrueCount,
                      skills: widget.data.skills,
                      active: widget.active,
                      spawnCenters: _assetSpawnCenters,
                    ),
                  ),
                ],
              ),
              if (_coordinator.producing case final output?)
                Positioned.fill(
                  child: TodayOutputOverlay(
                    key: ValueKey(
                      'today-output-owner-${output.kind.name}-${output.id}',
                    ),
                    item: output,
                    onHandoff: output.kind == TodayOutputKind.asset
                        ? (point) {
                            _assetSpawnCenters[output.id] = Offset(
                              point.dx - 18,
                              point.dy - assetChamberTop,
                            );
                          }
                        : null,
                    onComplete: _coordinator.completeCurrent,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TodayDate extends StatelessWidget {
  const _TodayDate({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) => Text(
    '${now.month}月${now.day}日 · ${_weekday(now.weekday)}',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: context.themeV2.foreground,
      fontSize: 18,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: -.35,
    ),
  );
}

void _noop() {}

String _weekday(int weekday) =>
    const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][weekday - 1];
