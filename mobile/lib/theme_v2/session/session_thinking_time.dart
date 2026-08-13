import 'dart:async';

import 'package:flutter/material.dart';

import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../foundation/theme_v2_typography.dart';

String formatThinkingTimer(Duration elapsed) {
  final seconds = elapsed.isNegative ? 0 : elapsed.inSeconds;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainder = seconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = remainder.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

String formatThinkingSummary(int elapsedMs, {String verb = '思考'}) {
  final milliseconds = elapsedMs < 0 ? 0 : elapsedMs;
  if (milliseconds < 1000) return '$verb不足 1 秒';
  final seconds = milliseconds ~/ 1000;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainder = seconds % 60;
  final parts = <String>[
    if (hours > 0) '$hours 小时',
    if (minutes > 0) '$minutes 分',
    if (remainder > 0 || (hours == 0 && minutes == 0)) '$remainder 秒',
  ];
  return '$verb ${parts.join(' ')}';
}

class SessionThinkingTimer extends StatefulWidget {
  const SessionThinkingTimer({super.key, required this.startedAt, this.now});

  final DateTime startedAt;
  final DateTime Function()? now;

  @override
  State<SessionThinkingTimer> createState() => _SessionThinkingTimerState();
}

class _SessionThinkingTimerState extends State<SessionThinkingTimer> {
  Timer? _timer;
  late String _label;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _label = _currentLabel();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant SessionThinkingTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startedAt != widget.startedAt) {
      _timer?.cancel();
      _label = _currentLabel();
      _startTimer();
    }
  }

  String _currentLabel() =>
      formatThinkingTimer(_now.difference(widget.startedAt));

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final nextLabel = _currentLabel();
      if (!mounted || nextLabel == _label) return;
      setState(() => _label = nextLabel);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      container: true,
      child: ExcludeSemantics(
        child: Text(
          _label,
          key: const ValueKey('session-thinking-timer'),
          style: ThemeV2Typography.mono(
            color: tokens.muted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class SessionThinkingFooter extends StatelessWidget {
  const SessionThinkingFooter({super.key, required this.elapsedMs});

  final int elapsedMs;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Container(
      key: const ValueKey('session-thinking-footer'),
      margin: const EdgeInsets.only(top: ThemeV2Spacing.sm),
      padding: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timelapse_rounded, size: 12, color: tokens.muted),
          const SizedBox(width: 5),
          Text(
            formatThinkingSummary(elapsedMs),
            style: TextStyle(color: tokens.muted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
