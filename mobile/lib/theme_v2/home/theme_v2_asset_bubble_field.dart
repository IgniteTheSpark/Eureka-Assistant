import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../today/bubble_physics.dart';
import '../../today/today_data.dart';
import '../../timeline/timeline.dart';
import '../asset_detail/asset_entity_ref.dart';
import '../asset_detail/open_asset_detail.dart';
import '../foundation/theme_v2_theme.dart';
import 'today_dither_field.dart';
import 'today_region_watermark.dart';

Offset themeV2GravityForAcceleration(double x, double y) {
  const magnitude = 20.0;
  final length = math.sqrt(x * x + y * y);
  if (length < 1.2) return const Offset(0, magnitude);
  return Offset(-x / length, y / length) * magnitude;
}

AssetEntityRef assetEntityRefForPoolAsset(PoolAsset asset) => AssetEntityRef(
  kind: switch (asset.entityKind) {
    'event' => AssetEntityKind.event,
    'contact' => AssetEntityKind.contact,
    _ => AssetEntityKind.asset,
  },
  id: asset.id,
);

void _noop() {}

class _RetiringBubbleSnapshot {
  const _RetiringBubbleSnapshot({
    required this.asset,
    required this.center,
    required this.radius,
    required this.angle,
    required this.index,
  });

  final PoolAsset asset;
  final Offset center;
  final double radius;
  final double angle;
  final int index;
}

class ThemeV2AssetBubbleField extends StatefulWidget {
  const ThemeV2AssetBubbleField({
    super.key,
    required this.assets,
    required this.trueCount,
    this.skills = const {},
    this.active = true,
    this.gravityStream,
    this.onOpenAsset,
    this.spawnCenters = const {},
    this.motion,
  });

  final List<PoolAsset> assets;
  final int trueCount;
  final Map<String, SkillMeta> skills;
  final bool active;
  final Stream<Offset>? gravityStream;
  final ValueChanged<PoolAsset>? onOpenAsset;
  final Map<String, Offset> spawnCenters;
  final Animation<double>? motion;

  void _openAsset(BuildContext context, PoolAsset asset) {
    final callback = onOpenAsset;
    if (callback != null) {
      callback(asset);
      return;
    }
    unawaited(
      openAssetDetail(
        context,
        assetEntityRefForPoolAsset(asset),
        coreRecordsOnly: true,
      ),
    );
  }

  @override
  State<ThemeV2AssetBubbleField> createState() =>
      _ThemeV2AssetBubbleFieldState();
}

class _ThemeV2AssetBubbleFieldState extends State<ThemeV2AssetBubbleField>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  Ticker? _ticker;
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  final Map<String, PoolAsset> _assetsById = {};
  final Map<String, double> _diametersById = {};
  final List<_RetiringBubbleSnapshot> _retiring = [];
  BubbleField? _field;
  String? _grabbedAssetId;
  List<PoolAsset>? _pendingAssets;
  StreamSubscription<Offset>? _gravitySubscription;
  Size _box = Size.zero;
  bool _reduceMotion = false;
  Offset _gravity = const Offset(0, 20);

  bool get _foreground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  bool get _physicsActive =>
      widget.active &&
      !_reduceMotion &&
      _foreground &&
      widget.assets.isNotEmpty;

  static const _diameters = <double>[
    70,
    48,
    72,
    58,
    80,
    52,
    64,
    52,
    44,
    50,
    38,
    46,
    38,
    38,
    54,
    42,
    56,
    46,
    34,
    30,
    34,
    32,
  ];
  static const _settledSlotCount = 22;
  static const _compactDiameter = 36.0;
  static const _minimumTargetSize = 44.0;

  bool get _usesCompactGrid =>
      _reduceMotion && widget.assets.length > _settledSlotCount;

  String _assetKey(List<PoolAsset> assets) =>
      assets.map((asset) => asset.id).join('|');

  double _diameter(PoolAsset asset, int index) {
    return _diametersById.putIfAbsent(
      asset.id,
      () => _diameters[index % _diameters.length],
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  List<Offset> _spawnCenters(List<double> radii) {
    const inset = 2.0;
    const gap = 4.0;
    final centers = <Offset>[];
    var cursorX = inset;
    var rowTop = inset;
    var rowHeight = 0.0;
    for (final radius in radii) {
      final diameter = radius * 2;
      if (cursorX > inset && cursorX + diameter > _box.width - inset) {
        cursorX = inset;
        rowTop += rowHeight + gap;
        rowHeight = 0;
      }
      centers.add(
        Offset(
          (cursorX + radius).clamp(
            radius,
            math.max(radius, _box.width - radius),
          ),
          (rowTop + radius).clamp(
            radius,
            math.max(radius, _box.height - radius),
          ),
        ),
      );
      cursorX += diameter + gap;
      rowHeight = math.max(rowHeight, diameter);
    }
    return centers;
  }

  Offset _settledCenter(int index, double radius) {
    const slots = [
      Offset(39, 700),
      Offset(87, 711),
      Offset(141, 686),
      Offset(194, 709),
      Offset(255, 684),
      Offset(314, 710),
      Offset(362, 685),
      Offset(41, 641),
      Offset(79, 650),
      Offset(160, 627),
      Offset(199, 639),
      Offset(323, 631),
      Offset(369, 639),
      Offset(49, 589),
      Offset(105, 605),
      Offset(171, 579),
      Offset(272, 604),
      Offset(341, 581),
      Offset(215, 565),
      Offset(27, 550),
      Offset(373, 553),
      Offset(130, 548),
    ];
    final source = slots[index % slots.length];
    return Offset(
      source.dx.clamp(radius, math.max(radius, _box.width - radius)),
      (source.dy - (790 - _box.height)).clamp(
        radius,
        math.max(radius, _box.height - radius),
      ),
    );
  }

  Offset _spawnCenter(PoolAsset asset, double radius, Offset fallback) {
    final configured = widget.spawnCenters[asset.id];
    if (configured == null) return fallback;
    return Offset(
      configured.dx.clamp(radius, math.max(radius, _box.width - radius)),
      configured.dy.clamp(radius, math.max(radius, _box.height - radius)),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextReduceMotion = MediaQuery.disableAnimationsOf(context);
    if (nextReduceMotion == _reduceMotion) return;
    if (nextReduceMotion) {
      _retiring.clear();
      _grabbedAssetId = null;
      _pendingAssets = null;
      _field?.release();
    }
    _reduceMotion = nextReduceMotion;
    _rebuildField(_box);
  }

  @override
  void didUpdateWidget(covariant ThemeV2AssetBubbleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextIds = widget.assets.map((asset) => asset.id).toSet();
    final grabbedAssetId = _grabbedAssetId;
    final deferReplacement =
        grabbedAssetId != null &&
        _assetsById.containsKey(grabbedAssetId) &&
        !nextIds.contains(grabbedAssetId);
    if (deferReplacement) {
      _pendingAssets = List<PoolAsset>.of(widget.assets);
      for (final asset in widget.assets) {
        if (_assetsById.containsKey(asset.id)) {
          _assetsById[asset.id] = asset;
        }
      }
      _repaint.value++;
    } else {
      _pendingAssets = null;
      _syncWidgetAssets(oldWidget);
    }
    if (oldWidget.gravityStream != widget.gravityStream) {
      unawaited(_gravitySubscription?.cancel());
      _gravitySubscription = null;
    }
    if (oldWidget.active != widget.active ||
        oldWidget.gravityStream != widget.gravityStream) {
      _syncLifecycle();
    }
  }

  void _syncWidgetAssets(ThemeV2AssetBubbleField oldWidget) {
    final crossedCompactThreshold =
        _reduceMotion &&
        (oldWidget.assets.length > _settledSlotCount) !=
            (widget.assets.length > _settledSlotCount);
    if (crossedCompactThreshold) {
      _rebuildField(_box);
    } else if (_assetKey(oldWidget.assets) != _assetKey(widget.assets)) {
      _syncAssetsTo(widget.assets);
    } else {
      _assetsById
        ..clear()
        ..addEntries(widget.assets.map((asset) => MapEntry(asset.id, asset)));
      _repaint.value++;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        (_retiring.isNotEmpty || _pendingAssets != null)) {
      setState(() {
        _retiring.clear();
        _grabbedAssetId = null;
        final pending = _pendingAssets;
        _pendingAssets = null;
        _field?.release();
        if (pending != null) _syncAssetsTo(pending);
      });
    }
    _syncLifecycle();
  }

  Stream<Offset> _productionGravityStream() {
    return accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 66),
    ).map((event) => themeV2GravityForAcceleration(event.x, event.y));
  }

  void _syncLifecycle() {
    if (!_physicsActive) {
      _ticker?.stop();
      unawaited(_gravitySubscription?.cancel());
      _gravitySubscription = null;
      return;
    }
    _gravitySubscription ??=
        (widget.gravityStream ?? _productionGravityStream()).listen(
          (gravity) {
            if ((gravity - _gravity).distance < 0.04) return;
            _gravity = gravity;
            final field = _field;
            if (field != null) {
              field.gravity = gravity;
              field.wakeAll();
              if (!(_ticker?.isActive ?? false)) _startTicker();
            }
          },
          onError: (_) {
            const fallback = Offset(0, 20);
            _gravity = fallback;
            final field = _field;
            if (field != null) {
              field.gravity = fallback;
              field.wakeAll();
              if (_physicsActive && !(_ticker?.isActive ?? false)) {
                _startTicker();
              }
            }
            unawaited(_gravitySubscription?.cancel());
            _gravitySubscription = null;
          },
        );
    if ((_field?.anyAwake ?? false) && !(_ticker?.isActive ?? false)) {
      _startTicker();
    }
  }

  void _startTicker() {
    (_ticker ??= createTicker(_onTick)).start();
  }

  void _rebuildField(Size box) {
    _box = box;
    _assetsById
      ..clear()
      ..addEntries(widget.assets.map((asset) => MapEntry(asset.id, asset)));
    if (box == Size.zero || widget.assets.isEmpty) {
      _field = null;
      _ticker?.stop();
      return;
    }
    if (_usesCompactGrid) {
      _field = null;
      _ticker?.stop();
      _repaint.value++;
      _syncLifecycle();
      return;
    }
    final field = BubbleField(box: box, gravity: _gravity);
    final radii = <double>[
      for (var index = 0; index < widget.assets.length; index++)
        _diameter(widget.assets[index], index) / 2,
    ];
    final spawnCenters = _spawnCenters(radii);
    for (var index = 0; index < widget.assets.length; index++) {
      final asset = widget.assets[index];
      final radius = radii[index];
      field.addBubble(
        asset.id,
        _reduceMotion
            ? _settledCenter(index, radius)
            : _spawnCenter(asset, radius, spawnCenters[index]),
        radius,
      );
    }
    _field = field;
    _repaint.value++;
    _syncLifecycle();
  }

  void _syncAssetsTo(List<PoolAsset> nextAssets) {
    final field = _field;
    if (field == null || _box == Size.zero) {
      _rebuildField(_box);
      return;
    }
    final previousAssets = Map<String, PoolAsset>.of(_assetsById);
    final nextById = {for (final asset in nextAssets) asset.id: asset};
    final ids = nextById.keys.toSet();
    if (field.bubbles.any((bubble) => !ids.contains(bubble.id))) {
      field.release();
    }
    final currentBubbles = List<Bubble>.of(field.bubbles);
    for (var index = 0; index < currentBubbles.length; index++) {
      final bubble = currentBubbles[index];
      if (!ids.contains(bubble.id)) {
        final asset = previousAssets[bubble.id];
        if (asset != null && widget.active && !_reduceMotion && _foreground) {
          _retiring.removeWhere((snapshot) => snapshot.asset.id == asset.id);
          _retiring.add(
            _RetiringBubbleSnapshot(
              asset: asset,
              center: Offset(bubble.x, bubble.y),
              radius: bubble.r,
              angle: bubble.angle,
              index: index,
            ),
          );
        }
        field.removeBubble(bubble);
        _diametersById.remove(bubble.id);
      }
    }
    _assetsById
      ..clear()
      ..addAll(nextById);
    final additions = <({PoolAsset asset, int index, double radius})>[];
    for (var index = 0; index < nextAssets.length; index++) {
      final asset = nextAssets[index];
      if (field.has(asset.id)) continue;
      final radius = _diameter(asset, index) / 2;
      additions.add((asset: asset, index: index, radius: radius));
    }
    final spawnCenters = _spawnCenters([
      for (final addition in additions) addition.radius,
    ]);
    for (
      var additionIndex = 0;
      additionIndex < additions.length;
      additionIndex++
    ) {
      final addition = additions[additionIndex];
      field.addBubble(
        addition.asset.id,
        _reduceMotion
            ? _settledCenter(addition.index, addition.radius)
            : _spawnCenter(
                addition.asset,
                addition.radius,
                spawnCenters[additionIndex],
              ),
        addition.radius,
      );
    }
    _repaint.value++;
    _syncLifecycle();
  }

  void _releaseGrab() {
    _field?.release();
    _grabbedAssetId = null;
    final pending = _pendingAssets;
    _pendingAssets = null;
    if (pending == null) return;
    setState(() => _syncAssetsTo(pending));
  }

  void _removeRetiring(String assetId) {
    if (!mounted) return;
    setState(() {
      _retiring.removeWhere((snapshot) => snapshot.asset.id == assetId);
    });
  }

  void _onTick(Duration elapsed) {
    final field = _field;
    if (!_physicsActive || field == null) return;
    if (!field.anyAwake) {
      _ticker?.stop();
      return;
    }
    field.step();
    _repaint.value++;
  }

  Rect _targetRect(Bubble bubble) {
    final size = math.max(_minimumTargetSize, bubble.r * 2);
    return Rect.fromLTWH(
      (bubble.x - size / 2).clamp(0, math.max(0, _box.width - size)),
      (bubble.y - size / 2).clamp(0, math.max(0, _box.height - size)),
      size,
      size,
    );
  }

  Bubble? _hitBubbleAt(BubbleField field, Offset position) {
    Bubble? best;
    var bestDistance = double.infinity;
    for (final bubble in field.bubbles) {
      if (!_targetRect(bubble).contains(position)) continue;
      final distance = (Offset(bubble.x, bubble.y) - position).distanceSquared;
      if (distance < bestDistance) {
        best = bubble;
        bestDistance = distance;
      }
    }
    return best;
  }

  double _ditherEnergy(Bubble bubble) {
    if (_grabbedAssetId == bubble.id) return 1;
    final velocity = bubble.body.linearVelocity;
    final speed = math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y);
    return (speed / 18).clamp(0, .72).toDouble();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_gravitySubscription?.cancel());
    _ticker?.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = constraints.biggest;
        if (box != _box) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && box != _box) setState(() => _rebuildField(box));
          });
        }
        final field = _field;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (!_usesCompactGrid)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _repaint,
                  builder: (context, _) => TodayDitherField(
                    key: const ValueKey('today-asset-dither-field'),
                    config: TodayDitherFieldConfig.asset(
                      waveColor: context.themeV2.foreground,
                      opacity: .30,
                    ),
                    sources: [
                      for (final bubble in field?.bubbles ?? const <Bubble>[])
                        TodayDitherSource.circle(
                          center: Offset(bubble.x, bubble.y),
                          radius: bubble.r,
                          energy: _ditherEnergy(bubble),
                        ),
                      for (final snapshot in _retiring)
                        TodayDitherSource.circle(
                          center: snapshot.center,
                          radius: snapshot.radius,
                          energy: .16,
                        ),
                    ],
                    motion: widget.motion,
                    reduceMotion: _reduceMotion,
                  ),
                ),
              ),
            for (final snapshot in _retiring)
              Positioned(
                key: ValueKey('theme-v2-retiring-bubble-${snapshot.asset.id}'),
                left: snapshot.center.dx - snapshot.radius,
                top: snapshot.center.dy - snapshot.radius,
                child: ExcludeSemantics(
                  child: IgnorePointer(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 260),
                      onEnd: () => _removeRetiring(snapshot.asset.id),
                      builder: (context, progress, child) => Opacity(
                        opacity: 1 - progress,
                        child: Transform.translate(
                          offset: Offset(0, 12 * progress),
                          child: Transform.scale(
                            scale: 1 - 0.28 * progress,
                            child: child,
                          ),
                        ),
                      ),
                      child: Transform.rotate(
                        angle: snapshot.angle,
                        child: SizedBox.square(
                          dimension: snapshot.radius * 2,
                          child: _ThemeV2BubbleVisual(
                            asset: snapshot.asset,
                            skills: widget.skills,
                            index: snapshot.index,
                            motion: widget.motion,
                            onTap: _noop,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_usesCompactGrid)
              Positioned.fill(
                child: _ThemeV2CompactAssetGrid(
                  assets: widget.assets,
                  skills: widget.skills,
                  motion: widget.motion,
                  onOpenAsset: (asset) => widget._openAsset(context, asset),
                ),
              )
            else if (field != null)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanDown: (details) {
                    final bubble = _hitBubbleAt(field, details.localPosition);
                    if (bubble == null) return;
                    _grabbedAssetId = bubble.id;
                    field.grab(bubble);
                    _syncLifecycle();
                  },
                  onTapUp: (details) {
                    final bubble = _hitBubbleAt(field, details.localPosition);
                    final asset = bubble == null
                        ? null
                        : _assetsById[bubble.id];
                    _releaseGrab();
                    if (asset != null) widget._openAsset(context, asset);
                  },
                  onPanStart: (details) {
                    if (_grabbedAssetId != null) {
                      _syncLifecycle();
                      return;
                    }
                    final bubble = _hitBubbleAt(field, details.localPosition);
                    if (bubble == null) {
                      _releaseGrab();
                      return;
                    }
                    _grabbedAssetId = bubble.id;
                    field.grab(bubble);
                    _syncLifecycle();
                  },
                  onPanUpdate: (details) {
                    field.dragTo(details.localPosition);
                    _syncLifecycle();
                  },
                  onPanEnd: (_) => _releaseGrab(),
                  onPanCancel: _releaseGrab,
                  child: AnimatedBuilder(
                    animation: _repaint,
                    builder: (context, _) {
                      final indexById = <String, int>{
                        for (
                          var index = 0;
                          index < field.bubbles.length;
                          index++
                        )
                          field.bubbles[index].id: index,
                      };
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          for (final bubble in field.bubbles.reversed)
                            if (_assetsById[bubble.id] case final asset?)
                              Builder(
                                builder: (context) {
                                  final index = indexById[bubble.id] ?? 0;
                                  final target = _targetRect(bubble);
                                  return Positioned(
                                    key: ValueKey(
                                      'theme-v2-asset-bubble-${asset.id}',
                                    ),
                                    left: target.left,
                                    top: target.top,
                                    width: target.width,
                                    height: target.height,
                                    child: Semantics(
                                      label: '打开资产 ${asset.title}',
                                      button: true,
                                      onTap: () =>
                                          widget._openAsset(context, asset),
                                      child: ExcludeSemantics(
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Positioned(
                                              left:
                                                  bubble.x -
                                                  target.left -
                                                  bubble.r,
                                              top:
                                                  bubble.y -
                                                  target.top -
                                                  bubble.r,
                                              width: bubble.r * 2,
                                              height: bubble.r * 2,
                                              child: Transform.rotate(
                                                key: ValueKey(
                                                  'theme-v2-asset-bubble-rotation-${asset.id}',
                                                ),
                                                angle: bubble.angle,
                                                child: _ThemeV2BubbleVisual(
                                                  asset: asset,
                                                  skills: widget.skills,
                                                  index: index,
                                                  motion: widget.motion,
                                                  onTap: () =>
                                                      widget._openAsset(
                                                        context,
                                                        asset,
                                                      ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            TodayRegionWatermark(
              count: widget.trueCount,
              label: 'Reka 生成',
              alignment: Alignment.topRight,
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
            ),
          ],
        );
      },
    );
  }
}

class _ThemeV2CompactAssetGrid extends StatelessWidget {
  const _ThemeV2CompactAssetGrid({
    required this.assets,
    required this.skills,
    required this.motion,
    required this.onOpenAsset,
  });

  final List<PoolAsset> assets;
  final Map<String, SkillMeta> skills;
  final Animation<double>? motion;
  final ValueChanged<PoolAsset> onOpenAsset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = math.max(
          1,
          (constraints.maxWidth /
                  _ThemeV2AssetBubbleFieldState._minimumTargetSize)
              .floor(),
        );
        final cellWidth = constraints.maxWidth / columns;
        final rowCount = (assets.length / columns).ceil();
        final contentHeight =
            rowCount * _ThemeV2AssetBubbleFieldState._minimumTargetSize;
        final top = math.max(0.0, constraints.maxHeight - contentHeight);
        return Stack(
          fit: StackFit.expand,
          children: [
            TodayDitherField(
              key: const ValueKey('today-asset-dither-field'),
              config: TodayDitherFieldConfig.asset(
                waveColor: context.themeV2.foreground,
                opacity: .30,
              ),
              sources: [
                for (var index = 0; index < assets.length; index++)
                  TodayDitherSource.circle(
                    center: Offset(
                      (index % columns + .5) * cellWidth,
                      top +
                          (index ~/ columns + .5) *
                              _ThemeV2AssetBubbleFieldState._minimumTargetSize,
                    ),
                    radius: _ThemeV2AssetBubbleFieldState._compactDiameter / 2,
                  ),
              ],
              motion: motion,
              reduceMotion: true,
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Wrap(
                children: [
                  for (var index = 0; index < assets.length; index++)
                    SizedBox(
                      width: cellWidth,
                      height: _ThemeV2AssetBubbleFieldState._minimumTargetSize,
                      child: _compactAssetTarget(assets[index], index),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _compactAssetTarget(PoolAsset asset, int index) {
    return Semantics(
      key: ValueKey('theme-v2-asset-bubble-${asset.id}'),
      label: '打开资产 ${asset.title}',
      button: true,
      onTap: () => onOpenAsset(asset),
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onOpenAsset(asset),
          child: Center(
            child: IgnorePointer(
              child: Transform.rotate(
                key: ValueKey('theme-v2-asset-bubble-rotation-${asset.id}'),
                angle: 0,
                child: SizedBox.square(
                  dimension: _ThemeV2AssetBubbleFieldState._compactDiameter,
                  child: _ThemeV2BubbleVisual(
                    asset: asset,
                    skills: skills,
                    index: index,
                    motion: motion,
                    onTap: () => onOpenAsset(asset),
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

class _ThemeV2BubbleVisual extends StatelessWidget {
  const _ThemeV2BubbleVisual({
    required this.asset,
    required this.skills,
    required this.index,
    required this.motion,
    required this.onTap,
  });

  final PoolAsset asset;
  final Map<String, SkillMeta> skills;
  final int index;
  final Animation<double>? motion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final highlighted = index < 5;
    final bubbleColor = highlighted
        ? _bubbleDitherColor(context, index)
        : tokens.muted;
    return DecoratedBox(
      key: ValueKey('theme-v2-asset-bubble-outline-${asset.id}'),
      decoration: BoxDecoration(
        color: Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: bubbleColor.withValues(alpha: highlighted ? .58 : .36),
          width: 1.35,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: LayoutBuilder(
            builder: (context, constraints) => Center(
              child: Text(
                resolveMeta(asset.type, skills).icon,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: math.min(22, constraints.maxWidth * 0.31),
                  height: 1,
                  color: bubbleColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _bubbleDitherColor(BuildContext context, int index) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (index) {
    0 => dark ? const Color(0xFF8A82FF) : const Color(0xFF159DBE),
    1 => const Color(0xFFA25BE3),
    2 => const Color(0xFF20B985),
    3 => const Color(0xFFE7764C),
    _ => const Color(0xFF6574E8),
  };
}
