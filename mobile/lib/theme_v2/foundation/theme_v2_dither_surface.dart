import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'theme_v2_dither_field.dart';
import 'theme_v2_theme.dart';

@immutable
class ThemeV2DitherRegistration {
  const ThemeV2DitherRegistration({
    required this.id,
    required this.rect,
    required this.shape,
    this.priority = 0,
    this.energy = 0,
  });

  final String id;
  final Rect rect;
  final ThemeV2DitherSourceShape shape;
  final int priority;
  final double energy;

  ThemeV2DitherSource toSource() => switch (shape) {
    ThemeV2DitherSourceShape.circle => ThemeV2DitherSource.circle(
      center: rect.center,
      radius: math.min(rect.width, rect.height) / 2,
      energy: energy,
    ),
    ThemeV2DitherSourceShape.capsule => ThemeV2DitherSource.capsule(
      center: rect.center,
      size: rect.size,
      energy: energy,
    ),
  };
}

List<ThemeV2DitherRegistration> selectThemeV2DitherRegistrations({
  required Iterable<ThemeV2DitherRegistration> registrations,
  required Rect viewport,
  int limit = ThemeV2DitherField.maxSources,
}) {
  final center = viewport.center;
  final visible = registrations
      .where((entry) => entry.rect.overlaps(viewport))
      .toList(growable: false);
  visible.sort((a, b) {
    final priority = b.priority.compareTo(a.priority);
    if (priority != 0) return priority;
    final distance = (a.rect.center - center).distanceSquared.compareTo(
      (b.rect.center - center).distanceSquared,
    );
    return distance != 0 ? distance : a.id.compareTo(b.id);
  });
  return visible.take(limit).toList(growable: false);
}

class ThemeV2DitherSurfaceController extends ChangeNotifier {
  final Map<Object, ThemeV2DitherRegistration> _registrations = {};
  bool _notificationScheduled = false;
  bool _disposed = false;

  List<ThemeV2DitherSource> sourcesFor(Rect viewport) =>
      selectThemeV2DitherRegistrations(
        registrations: _registrations.values,
        viewport: viewport,
      ).map((registration) => registration.toSource()).toList(growable: false);

  void upsert(Object handle, ThemeV2DitherRegistration registration) {
    final previous = _registrations[handle];
    if (previous != null &&
        previous.id == registration.id &&
        previous.rect == registration.rect &&
        previous.shape == registration.shape &&
        previous.priority == registration.priority &&
        previous.energy == registration.energy) {
      return;
    }
    _registrations[handle] = registration;
    _scheduleNotification();
  }

  void remove(Object handle) {
    if (_registrations.remove(handle) != null) _scheduleNotification();
  }

  void _scheduleNotification() {
    if (_notificationScheduled || _disposed) return;
    _notificationScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _notificationScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _registrations.clear();
    super.dispose();
  }
}

class ThemeV2DitherSurface extends StatefulWidget {
  const ThemeV2DitherSurface({
    super.key,
    required this.config,
    required this.active,
    required this.child,
  });

  final ThemeV2DitherFieldConfig config;
  final bool active;
  final Widget child;

  @override
  State<ThemeV2DitherSurface> createState() => _ThemeV2DitherSurfaceState();
}

class _ThemeV2DitherSurfaceState extends State<ThemeV2DitherSurface>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final GlobalKey _surfaceKey = GlobalKey();
  final ThemeV2DitherSurfaceController _sources =
      ThemeV2DitherSurfaceController();
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 120),
  );
  late AppLifecycleState _lifecycleState;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _lifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant ThemeV2DitherSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _syncMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _syncMotion();
  }

  void _syncMotion() {
    final shouldRun =
        widget.active &&
        !_reduceMotion &&
        _lifecycleState == AppLifecycleState.resumed;
    if (shouldRun && !_motion.isAnimating) {
      _motion.repeat();
    } else if (!shouldRun && _motion.isAnimating) {
      _motion.stop(canceled: false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sources.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final brightness = Theme.of(context).brightness;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        return ColoredBox(
          color: tokens.background,
          child: Stack(
            key: _surfaceKey,
            fit: StackFit.expand,
            children: [
              AnimatedBuilder(
                animation: _sources,
                builder: (context, _) => ThemeV2DitherField(
                  config: widget.config.copyWith(
                    waveColor: tokens.foreground,
                    opacity: brightness == Brightness.dark ? .26 : .28,
                  ),
                  sources: _sources.sourcesFor(Offset.zero & viewport),
                  motion: _motion,
                  reduceMotion: _reduceMotion,
                ),
              ),
              _ThemeV2DitherScope(
                controller: _sources,
                surfaceKey: _surfaceKey,
                child: widget.child,
              ),
            ],
          ),
        );
      },
    );
  }
}

class ThemeV2DitherSourceReporter extends StatefulWidget {
  const ThemeV2DitherSourceReporter({
    super.key,
    required this.id,
    required this.shape,
    required this.child,
    this.priority = 0,
    this.energy = 0,
  });

  final String id;
  final ThemeV2DitherSourceShape shape;
  final Widget child;
  final int priority;
  final double energy;

  @override
  State<ThemeV2DitherSourceReporter> createState() =>
      _ThemeV2DitherSourceReporterState();
}

class _ThemeV2DitherSourceReporterState
    extends State<ThemeV2DitherSourceReporter> {
  final Object _handle = Object();
  final GlobalKey _reporterKey = GlobalKey();
  _ThemeV2DitherScope? _scope;
  ScrollPosition? _scrollPosition;
  bool _reportScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextScope = _ThemeV2DitherScope.maybeOf(context);
    if (!identical(_scope, nextScope)) {
      _scope?.controller.remove(_handle);
      _scope = nextScope;
    }
    final nextPosition = Scrollable.maybeOf(context)?.position;
    if (!identical(_scrollPosition, nextPosition)) {
      _scrollPosition?.removeListener(_scheduleReport);
      _scrollPosition = nextPosition;
      _scrollPosition?.addListener(_scheduleReport);
    }
    _scheduleReport();
  }

  @override
  void didUpdateWidget(covariant ThemeV2DitherSourceReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleReport();
  }

  void _scheduleReport() {
    if (_reportScheduled || !mounted) return;
    _reportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportScheduled = false;
      if (mounted) _reportGeometry();
    });
  }

  void _reportGeometry() {
    final scope = _scope;
    final reporter = _reporterKey.currentContext?.findRenderObject();
    final surface = scope?.surfaceKey.currentContext?.findRenderObject();
    if (scope == null ||
        reporter is! RenderBox ||
        surface is! RenderBox ||
        !reporter.attached ||
        !surface.attached ||
        !reporter.hasSize) {
      scope?.controller.remove(_handle);
      return;
    }
    final topLeft = reporter.localToGlobal(Offset.zero, ancestor: surface);
    scope.controller.upsert(
      _handle,
      ThemeV2DitherRegistration(
        id: widget.id,
        rect: topLeft & reporter.size,
        shape: widget.shape,
        priority: widget.priority,
        energy: widget.energy,
      ),
    );
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_scheduleReport);
    _scope?.controller.remove(_handle);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _scheduleReport();
        return false;
      },
      child: SizeChangedLayoutNotifier(
        child: KeyedSubtree(key: _reporterKey, child: widget.child),
      ),
    );
  }
}

class _ThemeV2DitherScope extends InheritedWidget {
  const _ThemeV2DitherScope({
    required this.controller,
    required this.surfaceKey,
    required super.child,
  });

  final ThemeV2DitherSurfaceController controller;
  final GlobalKey surfaceKey;

  static _ThemeV2DitherScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ThemeV2DitherScope>();

  @override
  bool updateShouldNotify(_ThemeV2DitherScope oldWidget) =>
      !identical(controller, oldWidget.controller) ||
      !identical(surfaceKey, oldWidget.surfaceKey);
}
