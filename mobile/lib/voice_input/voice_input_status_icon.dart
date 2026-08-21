import 'package:flutter/material.dart';

import 'voice_input_controller.dart';

@immutable
final class VoiceInputPresentation {
  const VoiceInputPresentation(this.state);

  final VoiceInputControllerState state;

  bool get isBusy => state != VoiceInputControllerState.idle;

  String? get statusLabel => switch (state) {
    VoiceInputControllerState.idle => null,
    VoiceInputControllerState.connecting => '正在连接语音',
    VoiceInputControllerState.listening => '正在聆听',
    VoiceInputControllerState.stopping => '正在完成转录',
  };

  Widget? statusIcon({Color? color, double size = 18}) {
    if (!isBusy) return null;
    return VoiceInputStatusIcon(state: state, color: color, size: size);
  }
}

final class VoiceInputStatusIcon extends StatefulWidget {
  const VoiceInputStatusIcon({
    super.key,
    required this.state,
    this.color,
    this.size = 18,
  });

  static const statusKey = Key('voice-input-status');
  static const pulseKey = Key('voice-input-listening-pulse');

  final VoiceInputControllerState state;
  final Color? color;
  final double size;

  @override
  State<VoiceInputStatusIcon> createState() => _VoiceInputStatusIconState();
}

class _VoiceInputStatusIconState extends State<VoiceInputStatusIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(VoiceInputStatusIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _syncPulse();
  }

  void _syncPulse() {
    final animate =
        widget.state == VoiceInputControllerState.listening &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.state == VoiceInputControllerState.idle) {
      return const SizedBox.shrink();
    }
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    final label = VoiceInputPresentation(widget.state).statusLabel!;
    final indicator = switch (widget.state) {
      VoiceInputControllerState.connecting ||
      VoiceInputControllerState.stopping => SizedBox.square(
        dimension: widget.size,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      ),
      VoiceInputControllerState.listening => _listeningIcon(color),
      VoiceInputControllerState.idle => const SizedBox.shrink(),
    };
    return Semantics(
      key: VoiceInputStatusIcon.statusKey,
      label: label,
      liveRegion: true,
      child: ExcludeSemantics(
        child: SizedBox.square(dimension: 32, child: Center(child: indicator)),
      ),
    );
  }

  Widget _listeningIcon(Color color) {
    final icon = Icon(
      Icons.graphic_eq_rounded,
      size: widget.size,
      color: color,
    );
    if (MediaQuery.disableAnimationsOf(context)) return icon;
    return FadeTransition(
      key: VoiceInputStatusIcon.pulseKey,
      opacity: Tween<double>(
        begin: 0.58,
        end: 1,
      ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
      child: ScaleTransition(
        scale: Tween<double>(
          begin: 0.9,
          end: 1,
        ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
        child: icon,
      ),
    );
  }
}
