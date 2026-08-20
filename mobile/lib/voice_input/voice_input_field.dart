import 'dart:async';

import 'package:flutter/material.dart';

import 'voice_input_controller.dart';
import 'voice_input_models.dart';

typedef VoiceInputFieldBuilder =
    Widget Function(BuildContext context, bool voiceBusy);

final class VoiceInputField extends StatelessWidget {
  const VoiceInputField({
    super.key,
    required this.controller,
    required this.builder,
    this.enabled = true,
  });

  static const micKey = Key('voice-input-mic');
  static const cancelKey = Key('voice-input-cancel');

  final VoiceInputController controller;
  final VoiceInputFieldBuilder builder;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final busy = controller.isBusy;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: builder(context, busy)),
                const SizedBox(width: 6),
                IconButton(
                  key: micKey,
                  tooltip: busy ? '停止语音输入' : '开始语音输入',
                  onPressed: !enabled
                      ? null
                      : busy
                      ? controller.canStop
                            ? () => unawaited(controller.stop())
                            : null
                      : () => unawaited(controller.start()),
                  icon: Icon(
                    busy ? Icons.stop_circle_outlined : Icons.mic_none_rounded,
                  ),
                ),
                if (busy)
                  IconButton(
                    key: cancelKey,
                    tooltip: '取消语音输入',
                    onPressed: () => unawaited(controller.cancel()),
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
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
            if (!busy && controller.errorCode != null)
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
  VoiceInputErrorCode.busy => '另一个输入框正在使用麦克风',
  VoiceInputErrorCode.rateLimited => '语音输入过于频繁，请稍后再试',
  VoiceInputErrorCode.noSpeech => '没有识别到清晰语音，请重试',
  VoiceInputErrorCode.unsupportedAudio => '当前设备无法开始录音',
  VoiceInputErrorCode.connectionFailed ||
  VoiceInputErrorCode.connectionLost ||
  VoiceInputErrorCode.serviceUnavailable ||
  VoiceInputErrorCode.protocolError => '语音服务暂时不可用，请重试',
};
