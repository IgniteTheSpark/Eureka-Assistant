import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'today_dithered_reka_config.dart';

enum TodayRekaMotionState { idle, dragging, settling }

@immutable
class TodayRekaPose {
  const TodayRekaPose({
    required this.state,
    required this.tiltXDegrees,
    required this.tiltYDegrees,
    this.eyeOpacity = 1,
  });

  final TodayRekaMotionState state;
  final double tiltXDegrees;
  final double tiltYDegrees;
  final double eyeOpacity;
}

class TodayRekaMotionController extends ChangeNotifier {
  TodayRekaMotionController({this.config = const TodayDitheredRekaConfig()});

  static const maxDragSpeed = 1800.0;
  static const maxInertiaSpeed = 520.0;
  static const edgeAttractionDistance = 72.0;
  static const settleDurationSeconds = .22;

  final TodayDitheredRekaConfig config;

  TodayRekaMotionState _state = TodayRekaMotionState.idle;
  Rect _safeBounds = Rect.zero;
  Offset _rekaCenter = Offset.zero;
  Offset _dragVelocity = Offset.zero;
  Offset _lastPointer = Offset.zero;
  Offset _normalizedRekaPosition = const Offset(.24, .46);
  double _settleElapsed = 0;
  bool _laidOut = false;

  TodayRekaMotionState get state => _state;
  Rect get safeBounds => _safeBounds;
  Offset get rekaCenter => _rekaCenter;
  Offset get dragVelocity => _dragVelocity;
  Offset get normalizedRekaPosition => _normalizedRekaPosition;
  bool get isSettled => _state == TodayRekaMotionState.idle;

  TodayRekaPose get pose {
    if (_state == TodayRekaMotionState.idle) {
      return const TodayRekaPose(
        state: TodayRekaMotionState.idle,
        tiltXDegrees: 0,
        tiltYDegrees: 0,
      );
    }
    final horizontalRatio = (_dragVelocity.dx.abs() / maxDragSpeed)
        .clamp(0.0, 1.0)
        .toDouble();
    final horizontalTilt = horizontalRatio == 0
        ? 0.0
        : _dragVelocity.dx.sign *
              math.pow(horizontalRatio, .4).toDouble() *
              config.maxTiltDegrees;
    return TodayRekaPose(
      state: _state,
      tiltXDegrees: (-_dragVelocity.dy / maxDragSpeed * config.maxTiltDegrees)
          .clamp(-config.maxTiltDegrees, config.maxTiltDegrees)
          .toDouble(),
      tiltYDegrees: horizontalTilt,
    );
  }

  void layout(Size size, {required EdgeInsets reservedInsets}) {
    if (size.isEmpty) return;
    final margin = config.renderExtent / 2;
    final next = Rect.fromLTRB(
      reservedInsets.left + margin,
      reservedInsets.top + margin,
      size.width - reservedInsets.right - margin,
      size.height - reservedInsets.bottom - margin,
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
    _settleElapsed = 0;
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
    _settleElapsed = 0;
    _state = TodayRekaMotionState.settling;
    notifyListeners();
  }

  void cancelDrag() {
    _dragVelocity = Offset.zero;
    _settleElapsed = 0;
    _state = TodayRekaMotionState.idle;
    if (_laidOut) _clampAndNormalize();
    notifyListeners();
  }

  void step(double dtSeconds, {required bool reduceMotion}) {
    final dt = dtSeconds.clamp(0.0, 1 / 20);
    if (reduceMotion) {
      _dragVelocity = Offset.zero;
      _settleElapsed = 0;
      if (_state != TodayRekaMotionState.dragging) {
        _state = TodayRekaMotionState.idle;
      }
      notifyListeners();
      return;
    }
    if (_state != TodayRekaMotionState.settling) return;

    _settleElapsed += dt;
    _rekaCenter += _dragVelocity * dt;
    _dragVelocity *= math.pow(.00002, dt).toDouble();
    _applyEdgeAttraction(dt);
    _clampAndNormalize();
    if (_settleElapsed >= settleDurationSeconds) {
      _dragVelocity = Offset.zero;
      _settleElapsed = 0;
      _state = TodayRekaMotionState.idle;
    }
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
    value.dx.clamp(_safeBounds.left, _safeBounds.right).toDouble(),
    value.dy.clamp(_safeBounds.top, _safeBounds.bottom).toDouble(),
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
}

class _EdgeCandidate {
  const _EdgeCandidate(this.distance, this.target);

  final double distance;
  final Offset target;
}
