import 'dart:math' as math;

import 'package:flutter/material.dart';

enum TodayRekaMotionState { idle, dragging, settling }

class TodayDotFieldController extends ChangeNotifier {
  static const breathPeriodSeconds = 5.2;
  static const rekaVisualRadius = 45.0;
  static const maxDragSpeed = 1800.0;
  static const maxInertiaSpeed = 520.0;
  static const edgeAttractionDistance = 72.0;

  TodayRekaMotionState _state = TodayRekaMotionState.idle;
  Rect _safeBounds = Rect.zero;
  Offset _rekaCenter = Offset.zero;
  Offset _dragVelocity = Offset.zero;
  Offset _lastPointer = Offset.zero;
  Offset _normalizedRekaPosition = const Offset(.24, .46);
  double _breathPhase = 0;
  double _dragEngagement = 0;
  bool _laidOut = false;
  bool _reduceMotion = false;

  TodayRekaMotionState get state => _state;
  Rect get safeBounds => _safeBounds;
  Offset get rekaCenter => _rekaCenter;
  Offset get dragVelocity => _dragVelocity;
  Offset get normalizedRekaPosition => _normalizedRekaPosition;
  double get breathPhase => _breathPhase;
  double get dragEngagement => _dragEngagement;
  bool get isSettled => _state == TodayRekaMotionState.idle;

  double get breathAmount {
    if (_reduceMotion || _state != TodayRekaMotionState.idle) return 0;
    final wave = math.sin(_breathPhase * math.pi * 2 - math.pi / 2);
    return (wave + 1) / 2;
  }

  double get eyeOpacity {
    if (_state != TodayRekaMotionState.idle) return 0;
    if (_reduceMotion) return .42;
    return eyeOpacityForPhase(_breathPhase);
  }

  static double eyeOpacityForPhase(double phase) {
    final p = phase % 1;
    if (p < .58 || p > .96) return 0;
    final fadeIn = ((p - .58) / .14).clamp(0.0, 1.0);
    final fadeOut = ((.96 - p) / .12).clamp(0.0, 1.0);
    return _smooth(math.min(fadeIn, fadeOut));
  }

  void layout(Size size, {required EdgeInsets reservedInsets}) {
    if (size.isEmpty) return;
    final horizontalMargin = rekaVisualRadius + 12;
    final verticalMargin = rekaVisualRadius + 12;
    final next = Rect.fromLTRB(
      reservedInsets.left + horizontalMargin,
      reservedInsets.top + verticalMargin,
      size.width - reservedInsets.right - horizontalMargin,
      size.height - reservedInsets.bottom - verticalMargin,
    );
    assert(next.width > 0 && next.height > 0);
    _safeBounds = next;
    _rekaCenter = Offset(
      next.left + next.width * _normalizedRekaPosition.dx,
      next.top + next.height * _normalizedRekaPosition.dy,
    );
    _laidOut = true;
    _clampAndNormalize();
    notifyListeners();
  }

  void beginDrag(Offset localPosition) {
    if (!_laidOut) return;
    _state = TodayRekaMotionState.dragging;
    _lastPointer = localPosition;
    _dragVelocity = Offset.zero;
    _dragEngagement = 0;
    notifyListeners();
  }

  void updateDrag(Offset localPosition, Duration elapsed) {
    if (_state != TodayRekaMotionState.dragging) return;
    final seconds = math.max(
      elapsed.inMicroseconds / Duration.microsecondsPerSecond,
      1 / 240,
    );
    final delta = localPosition - _lastPointer;
    final rawVelocity = delta / seconds;
    final speed = rawVelocity.distance;
    _dragVelocity = speed > maxDragSpeed
        ? rawVelocity / speed * maxDragSpeed
        : rawVelocity;
    _dragEngagement = (_dragVelocity.distance / 900).clamp(0.0, 1.0);
    _rekaCenter = _clamp(localPosition);
    _lastPointer = localPosition;
    _normalize();
    notifyListeners();
  }

  void endDrag() {
    if (_state != TodayRekaMotionState.dragging) return;
    final speed = _dragVelocity.distance;
    if (speed > maxInertiaSpeed) {
      _dragVelocity = _dragVelocity / speed * maxInertiaSpeed;
    }
    _state = TodayRekaMotionState.settling;
    notifyListeners();
  }

  void cancelDrag() {
    _dragVelocity = Offset.zero;
    _dragEngagement = 0;
    _state = TodayRekaMotionState.idle;
    if (_laidOut) _clampAndNormalize();
    notifyListeners();
  }

  void step(double dtSeconds, {required bool reduceMotion}) {
    _reduceMotion = reduceMotion;
    final dt = dtSeconds.clamp(0.0, 1 / 20);
    if (reduceMotion) {
      _dragVelocity = Offset.zero;
      if (_state != TodayRekaMotionState.dragging) {
        _dragEngagement = 0;
        _state = TodayRekaMotionState.idle;
      }
      notifyListeners();
      return;
    }
    if (_state == TodayRekaMotionState.idle) {
      _breathPhase = (_breathPhase + dt / breathPeriodSeconds) % 1;
    } else if (_state == TodayRekaMotionState.settling) {
      _rekaCenter += _dragVelocity * dt;
      _dragVelocity *= math.pow(.12, dt).toDouble();
      _applyEdgeAttraction(dt);
      _clampAndNormalize();
      _dragEngagement += (0 - _dragEngagement) * math.min(1, dt * 8);
      if (_dragVelocity.distance < .5 && _dragEngagement < .005) {
        _dragVelocity = Offset.zero;
        _dragEngagement = 0;
        _state = TodayRekaMotionState.idle;
      }
    }
    notifyListeners();
  }

  @visibleForTesting
  void debugSetBreathPhase(double value) {
    assert(value >= 0 && value <= 1);
    _breathPhase = value;
    notifyListeners();
  }

  void _applyEdgeAttraction(double dt) {
    final candidates = <_EdgeCandidate>[
      _EdgeCandidate(
        (_rekaCenter.dx - _safeBounds.left).abs(),
        Offset(_safeBounds.left, _rekaCenter.dy),
      ),
      _EdgeCandidate(
        (_safeBounds.right - _rekaCenter.dx).abs(),
        Offset(_safeBounds.right, _rekaCenter.dy),
      ),
      _EdgeCandidate(
        (_rekaCenter.dy - _safeBounds.top).abs(),
        Offset(_rekaCenter.dx, _safeBounds.top),
      ),
      _EdgeCandidate(
        (_safeBounds.bottom - _rekaCenter.dy).abs(),
        Offset(_rekaCenter.dx, _safeBounds.bottom),
      ),
    ]..sort((a, b) => a.distance.compareTo(b.distance));
    final nearest = candidates.first;
    if (nearest.distance >= edgeAttractionDistance) return;
    final strength = math
        .pow(1 - nearest.distance / edgeAttractionDistance, 2)
        .toDouble();
    _rekaCenter +=
        (nearest.target - _rekaCenter) * math.min(1, dt * 2.2 * strength);
  }

  Offset _clamp(Offset value) => Offset(
    value.dx.clamp(_safeBounds.left, _safeBounds.right),
    value.dy.clamp(_safeBounds.top, _safeBounds.bottom),
  );

  void _clampAndNormalize() {
    _rekaCenter = _clamp(_rekaCenter);
    _normalize();
  }

  void _normalize() {
    _normalizedRekaPosition = Offset(
      (_rekaCenter.dx - _safeBounds.left) / _safeBounds.width,
      (_rekaCenter.dy - _safeBounds.top) / _safeBounds.height,
    );
  }

  static double _smooth(double value) => value * value * (3 - 2 * value);
}

class _EdgeCandidate {
  const _EdgeCandidate(this.distance, this.target);

  final double distance;
  final Offset target;
}
