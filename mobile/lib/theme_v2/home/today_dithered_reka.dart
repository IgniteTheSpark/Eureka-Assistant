import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'today_dithered_reka_config.dart';
import 'today_output_coordinator.dart';
import 'today_reka_capture_cue.dart';
import 'today_reka_fallback_painter.dart';
import 'today_reka_motion_controller.dart';

enum TodayRekaRenderStatus { loading, ready, fallback }

@visibleForTesting
String buildRekaHtml({
  required String template,
  required String threeSource,
  required String engineSource,
  required Map<String, Object?> options,
}) => template
    .replaceFirst('/*__THREE_SOURCE_JSON__*/', jsonEncode(threeSource))
    .replaceFirst('/*__ENGINE_SOURCE__*/', engineSource)
    .replaceFirst('/*__OPTIONS_JSON__*/', jsonEncode(options));

class TodayDitheredReka extends StatefulWidget {
  const TodayDitheredReka({
    super.key,
    required this.pose,
    required this.active,
    required this.reduceMotion,
    required this.refreshSignal,
    this.cue = const TodayOutputCue.idle(),
    this.captureCue = const TodayRekaCaptureCue.idle(),
    this.config = const TodayDitheredRekaConfig(),
    this.forceFallback = false,
  });

  static const fallbackKey = ValueKey('today-reka-fallback');
  static const leftEyeKey = ValueKey('today-reka-left-eye');
  static const rightEyeKey = ValueKey('today-reka-right-eye');

  final TodayRekaPose pose;
  final bool active;
  final bool reduceMotion;
  final int refreshSignal;
  final TodayOutputCue cue;
  final TodayRekaCaptureCue captureCue;
  final TodayDitheredRekaConfig config;
  final bool forceFallback;

  @override
  State<TodayDitheredReka> createState() => _TodayDitheredRekaState();
}

class _TodayDitheredRekaState extends State<TodayDitheredReka>
    with WidgetsBindingObserver {
  static const _readyTimeout = Duration(seconds: 5);
  static Future<_RekaAssetSources>? _assetSources;

  WebViewController? _controller;
  Timer? _readyTimer;
  TodayRekaRenderStatus _status = TodayRekaRenderStatus.loading;
  bool _appIsResumed = true;
  bool _pendingRefreshPulse = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.forceFallback) {
      _status = TodayRekaRenderStatus.fallback;
    } else {
      unawaited(_bootstrap());
    }
  }

  @override
  void didUpdateWidget(covariant TodayDitheredReka oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.forceFallback && !oldWidget.forceFallback) {
      _useFallback();
      return;
    }
    if (_status != TodayRekaRenderStatus.ready) {
      if (widget.refreshSignal != oldWidget.refreshSignal) {
        _pendingRefreshPulse = true;
      }
      return;
    }
    if (!_samePose(widget.pose, oldWidget.pose)) _sendMotion();
    if (widget.active != oldWidget.active) _sendPaused();
    if (widget.reduceMotion != oldWidget.reduceMotion) {
      _sendReduceMotion();
      _sendPaused();
    }
    if (widget.refreshSignal != oldWidget.refreshSignal) _pulseRefresh();
    if (!_sameCue(widget.cue, oldWidget.cue)) _sendProduction();
    if (widget.captureCue != oldWidget.captureCue) _sendCapture();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (_appIsResumed == resumed) return;
    _appIsResumed = resumed;
    _sendPaused();
  }

  Future<void> _bootstrap() async {
    try {
      final sources = await (_assetSources ??= _loadAssetSources());
      if (!mounted || _status == TodayRekaRenderStatus.fallback) return;

      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(Colors.transparent);
      await controller.addJavaScriptChannel(
        'RekaHost',
        onMessageReceived: _handleHostMessage,
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            final isLocalDocument =
                uri == null || uri.scheme == 'about' || uri.scheme == 'data';
            return isLocalDocument
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onWebResourceError: (_) => _useFallback(),
        ),
      );

      final html = buildRekaHtml(
        template: sources.template,
        threeSource: sources.three,
        engineSource: sources.engine,
        options: widget.config.rendererOptions(
          reduceMotion: widget.reduceMotion,
        ),
      );
      if (!mounted || _status == TodayRekaRenderStatus.fallback) return;
      setState(() => _controller = controller);
      await controller.loadHtmlString(html);
      _readyTimer = Timer(_readyTimeout, _useFallback);
    } catch (_) {
      _useFallback();
    }
  }

  static Future<_RekaAssetSources> _loadAssetSources() async {
    final values = await Future.wait([
      rootBundle.loadString('assets/reka_dither/reka_dither.html'),
      rootBundle.loadString('assets/reka_dither/three.bundle.min.js'),
      rootBundle.loadString('assets/reka_dither/reka_dither_engine.js'),
    ]);
    return _RekaAssetSources(
      template: values[0],
      three: values[1],
      engine: values[2],
    );
  }

  void _handleHostMessage(JavaScriptMessage message) {
    if (!mounted || _status == TodayRekaRenderStatus.fallback) return;
    try {
      final payload = jsonDecode(message.message) as Map<String, Object?>;
      switch (payload['type']) {
        case 'ready':
          _readyTimer?.cancel();
          setState(() => _status = TodayRekaRenderStatus.ready);
          _sendMotion();
          _sendReduceMotion();
          _sendPaused();
          _sendProduction();
          _sendCapture();
          if (_pendingRefreshPulse) {
            _pendingRefreshPulse = false;
            _pulseRefresh();
          }
        case 'error':
          _useFallback();
      }
    } catch (_) {
      _useFallback();
    }
  }

  void _sendMotion() => _runJavaScript(
    'window.RekaRenderer && window.RekaRenderer.setMotion('
    '${jsonEncode(<String, Object?>{'state': widget.pose.state.name, 'tiltXDegrees': widget.pose.tiltXDegrees, 'tiltYDegrees': widget.pose.tiltYDegrees})})',
  );

  void _sendReduceMotion() => _runJavaScript(
    'window.RekaRenderer && window.RekaRenderer.setReduceMotion('
    '${jsonEncode(widget.reduceMotion)})',
  );

  void _sendPaused() => _runJavaScript(
    'window.RekaRenderer && window.RekaRenderer.setPaused('
    '${jsonEncode(!widget.active || !_appIsResumed)})',
  );

  void _pulseRefresh() => _runJavaScript(
    'window.RekaRenderer && window.RekaRenderer.pulseRefresh()',
  );

  void _sendProduction() => _runJavaScript(
    'window.RekaRenderer && window.RekaRenderer.setProduction('
    '${jsonEncode(<String, Object?>{'kind': widget.cue.kind?.name, 'phase': widget.cue.phase.name, 'side': widget.cue.side.name})})',
  );

  void _sendCapture() => _runJavaScript(
    'window.RekaRenderer && window.RekaRenderer.setCapture('
    '${jsonEncode(widget.captureCue.toRendererPayload())})',
  );

  void _runJavaScript(String script) {
    final controller = _controller;
    if (controller == null || _status != TodayRekaRenderStatus.ready) return;
    unawaited(
      controller.runJavaScript(script).catchError((_) => _useFallback()),
    );
  }

  void _useFallback() {
    if (!mounted || _status == TodayRekaRenderStatus.fallback) return;
    _readyTimer?.cancel();
    setState(() {
      _status = TodayRekaRenderStatus.fallback;
      _controller = null;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _readyTimer?.cancel();
    final controller = _controller;
    if (controller != null) {
      unawaited(
        controller.runJavaScript(
          'window.RekaRenderer && window.RekaRenderer.destroy()',
        ),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final extent = widget.config.renderExtent;
    return SizedBox.square(
      dimension: extent,
      child: ExcludeSemantics(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_status != TodayRekaRenderStatus.ready) _buildFallback(),
            if (_controller case final controller?)
              IgnorePointer(child: WebViewWidget(controller: controller)),
          ],
        ),
      ),
    );
  }

  Widget _buildFallback() {
    final pitchMultiplier = switch (widget.pose.state) {
      TodayRekaMotionState.dragging => 3.0,
      TodayRekaMotionState.settling => 1.8,
      TodayRekaMotionState.idle => 1.0,
    };
    final x = widget.pose.tiltXDegrees * pitchMultiplier * math.pi / 180;
    final yawMultiplier = switch (widget.pose.state) {
      TodayRekaMotionState.dragging => 4.0,
      TodayRekaMotionState.settling => 2.4,
      TodayRekaMotionState.idle => 1.0,
    };
    final y = widget.pose.tiltYDegrees * yawMultiplier * math.pi / 180;
    final transform = Matrix4.identity()
      ..setEntry(3, 2, .0015)
      ..rotateX(x)
      ..rotateY(y);
    final eyeOffset = _fallbackEyeOffset(widget.cue);

    return Transform(
      key: TodayDitheredReka.fallbackKey,
      transform: transform,
      alignment: Alignment.center,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: TodayRekaFallbackPainter()),
          Positioned(
            left: 94 + eyeOffset.dx,
            top: 108 + eyeOffset.dy,
            child: Opacity(
              opacity: widget.pose.eyeOpacity,
              child: _PixelEye(
                key: TodayDitheredReka.leftEyeKey,
                action: widget.captureCue.action,
                left: true,
              ),
            ),
          ),
          Positioned(
            left: 162 + eyeOffset.dx,
            top: 108 + eyeOffset.dy,
            child: Opacity(
              opacity: widget.pose.eyeOpacity,
              child: _PixelEye(
                key: TodayDitheredReka.rightEyeKey,
                action: widget.captureCue.action,
                left: false,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static bool _samePose(TodayRekaPose a, TodayRekaPose b) =>
      a.state == b.state &&
      a.tiltXDegrees == b.tiltXDegrees &&
      a.tiltYDegrees == b.tiltYDegrees &&
      a.eyeOpacity == b.eyeOpacity;

  static bool _sameCue(TodayOutputCue a, TodayOutputCue b) =>
      a.phase == b.phase &&
      a.kind == b.kind &&
      a.id == b.id &&
      a.side == b.side;

  static Offset _fallbackEyeOffset(TodayOutputCue cue) {
    final horizontal = switch (cue.phase) {
      TodayOutputPhase.charge => cue.side == TodayOutputSide.right ? 4.0 : -4.0,
      _ => 0.0,
    };
    final vertical = switch ((cue.kind, cue.phase)) {
      (TodayOutputKind.signal, TodayOutputPhase.emit) ||
      (TodayOutputKind.signal, TodayOutputPhase.handoff) => -9.0,
      (TodayOutputKind.asset, TodayOutputPhase.emit) ||
      (TodayOutputKind.asset, TodayOutputPhase.handoff) => 9.0,
      (TodayOutputKind.signal, TodayOutputPhase.recover) => -3.0,
      (TodayOutputKind.asset, TodayOutputPhase.recover) => 3.0,
      _ => 0.0,
    };
    return Offset(horizontal, vertical);
  }
}

class _PixelEye extends StatelessWidget {
  const _PixelEye({super.key, required this.action, required this.left});

  static const _terminalGreen = Color(0xFF78FF74);
  final TodayRekaCaptureAction action;
  final bool left;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 28,
    child: Stack(
      children: [
        for (final index in todayRekaEyePattern(action, left: left))
          Positioned(
            left: (index % 3) * 10,
            top: (index ~/ 3) * 10,
            width: 8,
            height: 8,
            child: const ColoredBox(color: _terminalGreen),
          ),
      ],
    ),
  );
}

@visibleForTesting
List<int> todayRekaEyePattern(
  TodayRekaCaptureAction action, {
  required bool left,
}) => switch (action) {
  TodayRekaCaptureAction.idle => const [0, 1, 2, 3, 5, 6, 7, 8],
  TodayRekaCaptureAction.listening => const [0, 1, 2, 3, 4, 5, 6, 7, 8],
  TodayRekaCaptureAction.receiving => left ? const [0, 3, 6] : const [2, 5, 8],
  TodayRekaCaptureAction.transcribing => const [0, 1, 2, 6, 7, 8],
  TodayRekaCaptureAction.understanding => const [1, 3, 4, 5, 7],
  TodayRekaCaptureAction.organizing => const [0, 4, 8],
  TodayRekaCaptureAction.done => const [1, 3, 4, 5],
  TodayRekaCaptureAction.empty => const [3, 5],
  TodayRekaCaptureAction.failed => left ? const [0, 4, 8] : const [2, 4, 6],
};

class _RekaAssetSources {
  const _RekaAssetSources({
    required this.template,
    required this.three,
    required this.engine,
  });

  final String template;
  final String three;
  final String engine;
}
