import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../today/bubble_physics.dart';
import '../../today/today_data.dart';
import '../asset_detail/asset_entity_ref.dart';
import '../asset_detail/open_asset_detail.dart';
import '../foundation/theme_v2_theme.dart';

Offset themeV2GravityForAcceleration(double x, double y) {
  const magnitude = 20.0;
  final length = math.sqrt(x * x + y * y);
  if (length < 1.2) return const Offset(0, magnitude);
  return Offset(-x / length, y / length) * magnitude;
}

class ThemeV2AssetBubbleField extends StatefulWidget {
  const ThemeV2AssetBubbleField({
    super.key,
    required this.assets,
    required this.trueCount,
    this.active = true,
    this.gravityStream,
    this.onOpenAsset,
  });

  final List<PoolAsset> assets;
  final int trueCount;
  final bool active;
  final Stream<Offset>? gravityStream;
  final ValueChanged<PoolAsset>? onOpenAsset;

  void _openAsset(BuildContext context, PoolAsset asset) {
    final callback = onOpenAsset;
    if (callback != null) {
      callback(asset);
      return;
    }
    unawaited(
      openAssetDetail(
        context,
        AssetEntityRef(kind: AssetEntityKind.asset, id: asset.id),
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
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  final Map<String, PoolAsset> _assetsById = {};
  final Map<String, double> _diametersById = {};
  BubbleField? _field;
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

  Offset _spawnCenter(int index, double radius) {
    final usableWidth = math.max(1.0, _box.width - radius * 2);
    final fraction = ((index % 7) + 1) / 8;
    return Offset(radius + usableWidth * fraction, radius + 2 + index ~/ 7 * 4);
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextReduceMotion = MediaQuery.disableAnimationsOf(context);
    if (nextReduceMotion == _reduceMotion) return;
    _reduceMotion = nextReduceMotion;
    _rebuildField(_box);
  }

  @override
  void didUpdateWidget(covariant ThemeV2AssetBubbleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_assetKey(oldWidget.assets) != _assetKey(widget.assets)) {
      _syncAssets();
    } else {
      _assetsById
        ..clear()
        ..addEntries(widget.assets.map((asset) => MapEntry(asset.id, asset)));
      _repaint.value++;
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _syncLifecycle();
  }

  Stream<Offset> _productionGravityStream() {
    return accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 66),
    ).map((event) => themeV2GravityForAcceleration(event.x, event.y));
  }

  void _syncLifecycle() {
    if (!_physicsActive) {
      if (_ticker.isActive) _ticker.stop();
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
              if (!_ticker.isActive) _ticker.start();
            }
          },
          onError: (_) {
            const fallback = Offset(0, 20);
            _gravity = fallback;
            final field = _field;
            if (field != null) {
              field.gravity = fallback;
              field.wakeAll();
              if (_physicsActive && !_ticker.isActive) _ticker.start();
            }
            unawaited(_gravitySubscription?.cancel());
            _gravitySubscription = null;
          },
        );
    if ((_field?.anyAwake ?? false) && !_ticker.isActive) _ticker.start();
  }

  void _rebuildField(Size box) {
    _box = box;
    _assetsById
      ..clear()
      ..addEntries(widget.assets.map((asset) => MapEntry(asset.id, asset)));
    if (box == Size.zero || widget.assets.isEmpty) {
      _field = null;
      if (_ticker.isActive) _ticker.stop();
      return;
    }
    final field = BubbleField(box: box, gravity: _gravity);
    for (var index = 0; index < widget.assets.length; index++) {
      final asset = widget.assets[index];
      final radius = _diameter(asset, index) / 2;
      field.addBubble(
        asset.id,
        _reduceMotion
            ? _settledCenter(index, radius)
            : _spawnCenter(index, radius),
        radius,
      );
    }
    _field = field;
    _repaint.value++;
    _syncLifecycle();
  }

  void _syncAssets() {
    final field = _field;
    if (field == null || _box == Size.zero) {
      _rebuildField(_box);
      return;
    }
    _assetsById
      ..clear()
      ..addEntries(widget.assets.map((asset) => MapEntry(asset.id, asset)));
    final ids = widget.assets.map((asset) => asset.id).toSet();
    if (field.bubbles.any((bubble) => !ids.contains(bubble.id))) {
      field.release();
    }
    for (final bubble in List<Bubble>.of(field.bubbles)) {
      if (!ids.contains(bubble.id)) {
        field.removeBubble(bubble);
        _diametersById.remove(bubble.id);
      }
    }
    for (var index = 0; index < widget.assets.length; index++) {
      final asset = widget.assets[index];
      if (field.has(asset.id)) continue;
      final radius = _diameter(asset, index) / 2;
      field.addBubble(
        asset.id,
        _reduceMotion
            ? _settledCenter(index, radius)
            : _spawnCenter(index, radius),
        radius,
      );
    }
    _repaint.value++;
    _syncLifecycle();
  }

  void _onTick(Duration elapsed) {
    final field = _field;
    if (!_physicsActive || field == null) return;
    if (!field.anyAwake) {
      _ticker.stop();
      return;
    }
    field.step();
    _repaint.value++;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_gravitySubscription?.cancel());
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
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
            Positioned(
              left: 238,
              top: 450,
              child: IgnorePointer(
                child: Text(
                  '${widget.trueCount}',
                  style: TextStyle(
                    color: tokens.accent.withValues(alpha: 0.07),
                    fontFamily: 'Geist',
                    fontSize: 112,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -6,
                    height: 1.15,
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
                  style: TextStyle(
                    color: tokens.accent.withValues(alpha: 0.28),
                    fontFamily: 'Geist Mono',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    height: 1.15,
                  ),
                ),
              ),
            ),
            if (field != null)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (details) {
                    final bubble = field.hit(details.localPosition);
                    if (bubble == null) return;
                    final asset = _assetsById[bubble.id];
                    if (asset != null) widget._openAsset(context, asset);
                  },
                  onPanStart: (details) {
                    final bubble = field.hit(details.localPosition);
                    if (bubble == null) {
                      field.release();
                      return;
                    }
                    field.grab(bubble);
                    _syncLifecycle();
                  },
                  onPanUpdate: (details) {
                    field.dragTo(details.localPosition);
                    _syncLifecycle();
                  },
                  onPanEnd: (_) => field.release(),
                  onPanCancel: field.release,
                  child: AnimatedBuilder(
                    animation: _repaint,
                    builder: (context, _) {
                      final indexById = <String, int>{
                        for (
                          var index = 0;
                          index < widget.assets.length;
                          index++
                        )
                          widget.assets[index].id: index,
                      };
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          for (final bubble in field.bubbles.reversed)
                            if (_assetsById[bubble.id] case final asset?)
                              Builder(
                                builder: (context) {
                                  final index = indexById[bubble.id] ?? 0;
                                  final hitSize = math.max(44.0, bubble.r * 2);
                                  return Positioned(
                                    key: ValueKey(
                                      'theme-v2-asset-bubble-${asset.id}',
                                    ),
                                    left: bubble.x - hitSize / 2,
                                    top: bubble.y - hitSize / 2,
                                    width: hitSize,
                                    height: hitSize,
                                    child: Semantics(
                                      label: '打开资产 ${asset.title}',
                                      button: true,
                                      onTap: () =>
                                          widget._openAsset(context, asset),
                                      child: ExcludeSemantics(
                                        child: Center(
                                          child: Transform.rotate(
                                            key: ValueKey(
                                              'theme-v2-asset-bubble-rotation-${asset.id}',
                                            ),
                                            angle: bubble.angle,
                                            child: SizedBox.square(
                                              dimension: bubble.r * 2,
                                              child: _ThemeV2BubbleVisual(
                                                asset: asset,
                                                index: index,
                                                onTap: () => widget._openAsset(
                                                  context,
                                                  asset,
                                                ),
                                              ),
                                            ),
                                          ),
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
          ],
        );
      },
    );
  }
}

class _ThemeV2BubbleVisual extends StatelessWidget {
  const _ThemeV2BubbleVisual({
    required this.asset,
    required this.index,
    required this.onTap,
  });

  final PoolAsset asset;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final highlighted = index < 5;
    return DecoratedBox(
      decoration: BoxDecoration(
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
              child: Icon(
                _assetIcon(asset.type),
                size: math.min(22, constraints.maxWidth * 0.31),
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
