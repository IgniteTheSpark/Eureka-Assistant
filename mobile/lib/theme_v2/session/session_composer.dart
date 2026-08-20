import 'package:flutter/material.dart';

import '../../voice_input/voice_input_controller.dart';
import '../../voice_input/voice_input_field.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';

class SessionComposer extends StatelessWidget {
  const SessionComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.voiceController,
    required this.streaming,
    required this.onAddContext,
    required this.onSend,
  });

  final VoiceInputTextController controller;
  final FocusNode focusNode;
  final VoiceInputController voiceController;
  final bool streaming;
  final VoidCallback onAddContext;
  final Future<void> Function(String text) onSend;

  Future<void> _submit(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || streaming || voiceController.isBusy) return;
    controller.clear();
    focusNode.unfocus();
    await onSend(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        bottom: keyboardInset == 0,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Container(
          key: const ValueKey('session-composer'),
          padding: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            color: tokens.background,
            border: Border(top: BorderSide(color: tokens.border)),
          ),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final enabled =
                  value.text.trim().isNotEmpty &&
                  !streaming &&
                  !voiceController.isBusy;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: VoiceInputField(
                      key: const ValueKey('session-composer-voice'),
                      controller: voiceController,
                      enabled: !streaming,
                      builder: (context, voice) => TextField(
                        key: const ValueKey('session-composer-field'),
                        controller: controller,
                        focusNode: focusNode,
                        readOnly: voice.isBusy,
                        minLines: 1,
                        maxLines: 5,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        style: TextStyle(
                          color: tokens.foreground,
                          fontSize: 13,
                          height: 1.35,
                        ),
                        decoration: InputDecoration(
                          hintText: '问 Agent 任何事…',
                          hintStyle: TextStyle(color: tokens.muted),
                          prefixIcon: IconButton(
                            tooltip: '添加上下文资产',
                            onPressed: voice.isBusy ? null : onAddContext,
                            constraints: const BoxConstraints(
                              minWidth: ThemeV2Sizes.minTouchTarget,
                              minHeight: ThemeV2Sizes.minTouchTarget,
                            ),
                            icon: Icon(
                              Icons.auto_awesome_outlined,
                              color: tokens.accent,
                              size: 18,
                            ),
                          ),
                          suffixIcon: voice.statusIcon(color: tokens.accent),
                          suffixIconConstraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                          filled: true,
                          fillColor: tokens.surface,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              ThemeV2Radii.pill,
                            ),
                            borderSide: BorderSide(color: tokens.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              ThemeV2Radii.pill,
                            ),
                            borderSide: BorderSide(color: tokens.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              ThemeV2Radii.pill,
                            ),
                            borderSide: BorderSide(color: tokens.accent),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    label: streaming ? '正在发送' : '发送消息',
                    button: true,
                    enabled: enabled,
                    child: SizedBox.square(
                      dimension: ThemeV2Sizes.minTouchTarget,
                      child: IconButton(
                        key: const ValueKey('session-send'),
                        onPressed: enabled ? () => _submit(value.text) : null,
                        style: IconButton.styleFrom(
                          backgroundColor: enabled
                              ? tokens.accent
                              : tokens.border,
                          foregroundColor: tokens.background,
                          disabledForegroundColor: tokens.muted,
                        ),
                        icon: streaming
                            ? SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: tokens.muted,
                                ),
                              )
                            : const Icon(Icons.arrow_upward_rounded, size: 20),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
