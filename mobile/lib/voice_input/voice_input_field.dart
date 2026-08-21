import 'dart:async';

import 'package:flutter/material.dart';

import 'voice_input_controller.dart';
import 'voice_input_models.dart';
import 'voice_input_scope.dart';
import 'voice_input_status_icon.dart';

typedef VoiceInputFieldBuilder =
    Widget Function(BuildContext context, VoiceInputPresentation voice);

typedef VoiceInputFieldLayoutBuilder =
    Widget Function(
      BuildContext context,
      VoiceInputPresentation voice,
      Widget field,
      Widget voiceAction,
    );

final class VoiceInputField extends StatelessWidget {
  const VoiceInputField({
    super.key,
    required this.controller,
    required this.builder,
    this.enabled = true,
    this.trailing,
    this.layoutBuilder,
  });

  static const micKey = Key('voice-input-mic');

  final VoiceInputController controller;
  final VoiceInputFieldBuilder builder;
  final bool enabled;
  final Widget? trailing;
  final VoiceInputFieldLayoutBuilder? layoutBuilder;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final voice = VoiceInputPresentation(controller.state);
        final field = builder(context, voice);
        final voiceAction = IconButton(
          key: micKey,
          tooltip: switch (controller.state) {
            VoiceInputControllerState.idle => '开始语音输入',
            VoiceInputControllerState.connecting => '正在连接语音',
            VoiceInputControllerState.listening => '停止语音输入',
            VoiceInputControllerState.stopping => '正在完成转录',
          },
          onPressed: !enabled
              ? null
              : controller.state == VoiceInputControllerState.idle
              ? () => unawaited(controller.start())
              : controller.canStop
              ? () => unawaited(controller.stop())
              : null,
          icon: Icon(
            controller.state == VoiceInputControllerState.idle
                ? Icons.mic_none_rounded
                : Icons.stop_rounded,
          ),
        );
        final body =
            layoutBuilder?.call(context, voice, field, voiceAction) ??
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: field),
                const SizedBox(width: 6),
                voiceAction,
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            body,
            if (controller.isDurationWarning)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '还可说 30 秒',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            if (!voice.isBusy && controller.errorCode != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _errorCopy(controller.errorCode!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

String _errorCopy(VoiceInputErrorCode code) => switch (code) {
  VoiceInputErrorCode.permissionDenied => '请先允许麦克风权限',
  VoiceInputErrorCode.unauthenticated => '登录已失效，请重新登录',
  VoiceInputErrorCode.rateLimited => '语音输入过于频繁，请稍后再试',
  VoiceInputErrorCode.noSpeech => '没有识别到清晰语音，请重试',
  VoiceInputErrorCode.unsupportedAudio => '当前设备无法开始录音',
  VoiceInputErrorCode.connectionFailed ||
  VoiceInputErrorCode.connectionLost ||
  VoiceInputErrorCode.serviceUnavailable ||
  VoiceInputErrorCode.busy ||
  VoiceInputErrorCode.protocolError => '语音服务暂时不可用，请重试',
};

typedef VoiceInputTextAdapterBuilder =
    Widget Function(
      BuildContext context,
      VoiceInputTextController controller,
      VoiceInputPresentation voice,
    );

/// Adds the shared voice lifecycle to an existing controller without forcing
/// older authoring surfaces to replace their controller ownership model.
final class VoiceInputTextAdapter extends StatefulWidget {
  const VoiceInputTextAdapter({
    super.key,
    required this.controller,
    required this.builder,
    this.enabled = true,
    this.onBusyChanged,
  });

  final TextEditingController controller;
  final VoiceInputTextAdapterBuilder builder;
  final bool enabled;
  final ValueChanged<bool>? onBusyChanged;

  @override
  State<VoiceInputTextAdapter> createState() => _VoiceInputTextAdapterState();
}

class _VoiceInputTextAdapterState extends State<VoiceInputTextAdapter> {
  late final VoiceInputTextController _textController;
  late final bool _ownsTextController;
  VoiceInputController? _voiceController;
  bool _lastBusy = false;

  @override
  void initState() {
    super.initState();
    final external = widget.controller;
    if (external is VoiceInputTextController) {
      _textController = external;
      _ownsTextController = false;
    } else {
      _textController = VoiceInputTextController.fromValue(external.value);
      _ownsTextController = true;
      _textController.addListener(_copyToExternal);
      external.addListener(_copyFromExternal);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_voiceController != null) return;
    final scope = VoiceInputScope.maybeOf(context);
    _voiceController = VoiceInputController(
      textController: _textController,
      coordinator: scope?.coordinator ?? VoiceInputScope.coordinatorOf(context),
    )..addListener(_onVoiceChanged);
  }

  @override
  void didUpdateWidget(VoiceInputTextAdapter oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      identical(oldWidget.controller, widget.controller),
      'VoiceInputTextAdapter controller must remain stable for its lifetime',
    );
  }

  void _copyToExternal() {
    if (widget.controller.value != _textController.value) {
      widget.controller.value = _textController.value;
    }
  }

  void _copyFromExternal() {
    if (widget.controller.value != _textController.value &&
        !(_voiceController?.isBusy ?? false)) {
      _textController.value = widget.controller.value;
    }
  }

  void _onVoiceChanged() {
    final busy = _voiceController?.isBusy ?? false;
    if (busy == _lastBusy) return;
    _lastBusy = busy;
    widget.onBusyChanged?.call(busy);
  }

  @override
  void dispose() {
    final voiceController = _voiceController;
    if (voiceController != null) {
      voiceController.removeListener(_onVoiceChanged);
      unawaited(voiceController.close());
      voiceController.dispose();
    }
    if (_ownsTextController) {
      _textController.removeListener(_copyToExternal);
      widget.controller.removeListener(_copyFromExternal);
      _textController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final voiceController = _voiceController!;
    return VoiceInputField(
      controller: voiceController,
      enabled: widget.enabled,
      builder: (context, voice) =>
          widget.builder(context, _textController, voice),
    );
  }
}
