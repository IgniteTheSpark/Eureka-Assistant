import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../today/today_data.dart';
import '../foundation/theme_v2_theme.dart';
import 'theme_v2_asset_bubble_field.dart';
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
  final TodaySignalOpenCallback? onOpenSignal;
  final VoidCallback? onOpenAgenda;
  final ValueListenable<DateTime>? clock;
  final Offset rekaCenter;
  final bool suppressProduction;
  final TodayOutputCoordinator? outputCoordinator;

  @override
  State<TodayLivingSurface> createState() => _TodayLivingSurfaceState();
}

class _TodayLivingSurfaceState extends State<TodayLivingSurface>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TodayOutputCoordinator _coordinator =
      widget.outputCoordinator ?? TodayOutputCoordinator();
  late final bool _ownsCoordinator = widget.outputCoordinator == null;
  late final AnimationController _ambientMotion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 120),
  );
  late AppLifecycleState _lifecycleState;
  bool _reconciling = false;
  bool _reduceMotion = false;
  final Map<String, Offset> _assetSpawnCenters = {};

  @override
  void initState() {
    super.initState();
    _lifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _coordinator.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncAmbientMotion();
    _reconcile();
  }

  @override
  void didUpdateWidget(covariant TodayLivingSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active && oldWidget.active) _coordinator.cancelAll();
    if (oldWidget.active != widget.active) _syncAmbientMotion();
    _reconcile();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _syncAmbientMotion();
  }

  void _syncAmbientMotion() {
    final shouldRun =
        widget.active &&
        !_reduceMotion &&
        _lifecycleState == AppLifecycleState.resumed;
    if (shouldRun && !_ambientMotion.isAnimating) {
      _ambientMotion.repeat();
    } else if (!shouldRun && _ambientMotion.isAnimating) {
      _ambientMotion.stop(canceled: false);
    }
  }

  void _reconcile() {
    _reconciling = true;
    try {
      _coordinator.reconcile(
        assetIds: widget.data.pool.map((asset) => asset.id),
        signalIds: widget.data.rekaQueue.map((signal) => signal.id),
        rekaCenter: Offset(widget.rekaCenter.dx - 18, widget.rekaCenter.dy),
        suppressProduction: widget.suppressProduction,
        capacityAvailable: widget.active,
        reduceMotion: MediaQuery.disableAnimationsOf(context),
        viewportWidth: MediaQuery.sizeOf(context).width - 36,
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
    WidgetsBinding.instance.removeObserver(this);
    _coordinator.removeListener(_changed);
    if (_ownsCoordinator) _coordinator.dispose();
    _ambientMotion.dispose();
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
    final cue = _coordinator.cue;
    final signalBirthState = switch ((cue.kind, cue.phase)) {
      (TodayOutputKind.signal, TodayOutputPhase.emit) =>
        TodaySignalBirthState.clearing,
      (TodayOutputKind.signal, TodayOutputPhase.handoff) =>
        TodaySignalBirthState.unfolding,
      _ => TodaySignalBirthState.idle,
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        const seamHeight = 14.0;
        final contentHeight = constraints.maxHeight - 74 - seamHeight;
        final signalHeight = contentHeight / 3;
        final assetChamberTop = 74 + signalHeight + seamHeight;
        return Padding(
          key: const ValueKey('today-living-surface'),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Stack(
            fit: StackFit.expand,
            children: [
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
                      motion: _ambientMotion,
                      onOpenSignal: widget.onOpenSignal,
                      birthState: signalBirthState,
                      birthSignalId: cue.kind == TodayOutputKind.signal
                          ? cue.id
                          : _coordinator.lastCompletedSignalId,
                    ),
                  ),
                  const SizedBox(
                    key: ValueKey('today-container-seam'),
                    height: seamHeight,
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
                      motion: _ambientMotion,
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
                    signalBoundaryY: 74,
                    assetFloorY: constraints.maxHeight,
                    side: output.side,
                    onPhaseChanged: _coordinator.updatePhase,
                    onHandoff: (point) {
                      if (output.kind == TodayOutputKind.asset) {
                        _assetSpawnCenters[output.id] = Offset(
                          point.dx,
                          point.dy - assetChamberTop,
                        );
                      }
                    },
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
