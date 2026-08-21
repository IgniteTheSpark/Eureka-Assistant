import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../voice_input/voice_input_controller.dart';
import '../../voice_input/voice_input_field.dart';
import '../../voice_input/voice_input_status_icon.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import 'session_composer_state.dart';

class SessionComposer extends StatefulWidget {
  const SessionComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.voiceController,
    required this.streaming,
    required this.onSend,
  });

  static const maxVisibleLines = 5;
  static const actionSize = 48.0;

  final VoiceInputTextController controller;
  final FocusNode focusNode;
  final VoiceInputController voiceController;
  final bool streaming;
  final Future<void> Function(String text) onSend;

  @override
  State<SessionComposer> createState() => _SessionComposerState();
}

class _SessionComposerState extends State<SessionComposer> {
  final ScrollController _textScrollController = ScrollController();
  bool _tailFollowScheduled = false;
  late int _lastTerminalCount;

  @override
  void initState() {
    super.initState();
    _lastTerminalCount = widget.voiceController.terminalCount;
    _addListeners(widget);
  }

  @override
  void didUpdateWidget(SessionComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller) ||
        !identical(oldWidget.focusNode, widget.focusNode) ||
        !identical(oldWidget.voiceController, widget.voiceController)) {
      _removeListeners(oldWidget);
      _lastTerminalCount = widget.voiceController.terminalCount;
      _addListeners(widget);
    }
  }

  void _addListeners(SessionComposer composer) {
    composer.controller.addListener(_onComposerChanged);
    composer.focusNode.addListener(_onComposerChanged);
    composer.voiceController.addListener(_onComposerChanged);
  }

  void _removeListeners(SessionComposer composer) {
    composer.controller.removeListener(_onComposerChanged);
    composer.focusNode.removeListener(_onComposerChanged);
    composer.voiceController.removeListener(_onComposerChanged);
  }

  void _onComposerChanged() {
    final terminalCount = widget.voiceController.terminalCount;
    final terminalChanged = terminalCount != _lastTerminalCount;
    _lastTerminalCount = terminalCount;
    if (widget.voiceController.isBusy && widget.focusNode.hasFocus) {
      widget.focusNode.unfocus();
    }
    if (widget.voiceController.isBusy || terminalChanged) {
      _scheduleVoiceTailFollow();
    }
    if (mounted) setState(() {});
  }

  void _scheduleVoiceTailFollow() {
    if (_tailFollowScheduled) return;
    _tailFollowScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tailFollowScheduled = false;
      if (!mounted || !_textScrollController.hasClients) return;
      final position = _textScrollController.position;
      _textScrollController.jumpTo(position.maxScrollExtent);
    });
  }

  Future<void> _submit(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || widget.streaming || widget.voiceController.isBusy) {
      return;
    }
    widget.controller.clear();
    widget.focusNode.unfocus();
    await widget.onSend(trimmed);
  }

  SessionComposerPresentation _presentation(
    VoiceInputControllerState voiceState,
  ) {
    return SessionComposerPresentation.derive(
      hasFocus: widget.focusNode.hasFocus,
      text: widget.controller.text,
      voiceState: voiceState,
      agentReplying: widget.streaming,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final scaledLineHeight = MediaQuery.textScalerOf(context).scale(13) * 1.35;
    final maxFieldHeight = math.max(
      ThemeV2Sizes.minTouchTarget,
      scaledLineHeight * SessionComposer.maxVisibleLines + 24,
    );
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
          child: VoiceInputField(
            key: const ValueKey('session-composer-voice'),
            controller: widget.voiceController,
            enabled: !widget.streaming,
            layoutBuilder: (context, voice, field, voiceAction) {
              final presentation = _presentation(voice.state);
              final body =
                  presentation.mode == SessionComposerMode.collapsedIdle
                  ? _buildIdleBody(field, voiceAction)
                  : _buildExpandedBody(
                      context,
                      tokens: tokens,
                      presentation: presentation,
                      voice: voice,
                      field: field,
                      voiceAction: voiceAction,
                    );
              return body;
            },
            builder: (context, voice) {
              final presentation = _presentation(voice.state);
              return ConstrainedBox(
                key: const ValueKey('session-composer-field-bound'),
                constraints: BoxConstraints(maxHeight: maxFieldHeight),
                child: TextField(
                  key: const ValueKey('session-composer-field'),
                  controller: widget.controller,
                  scrollController: _textScrollController,
                  focusNode: widget.focusNode,
                  readOnly: voice.isBusy,
                  minLines: 1,
                  maxLines: SessionComposer.maxVisibleLines,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: TextStyle(
                    color: tokens.foreground,
                    fontSize: 13,
                    height: 1.35,
                  ),
                  decoration: _inputDecoration(
                    tokens,
                    expanded: presentation.showFooter,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildIdleBody(Widget field, Widget voiceAction) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: field),
        const SizedBox(width: 8),
        SizedBox.square(
          dimension: SessionComposer.actionSize,
          child: voiceAction,
        ),
      ],
    );
  }

  Widget _buildExpandedBody(
    BuildContext context, {
    required ThemeV2Tokens tokens,
    required SessionComposerPresentation presentation,
    required VoiceInputPresentation voice,
    required Widget field,
    required Widget voiceAction,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          field,
          Container(
            key: const ValueKey('session-composer-footer'),
            height: SessionComposer.actionSize + 16,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 7),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: tokens.border)),
            ),
            child: presentation.showVoiceStatus
                ? _buildVoiceFooter(
                    tokens: tokens,
                    voice: voice,
                    voiceAction: voiceAction,
                  )
                : _buildEditingFooter(
                    tokens: tokens,
                    presentation: presentation,
                    voiceAction: voiceAction,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceFooter({
    required ThemeV2Tokens tokens,
    required VoiceInputPresentation voice,
    required Widget voiceAction,
  }) {
    final statusIcon = voice.statusIcon(color: tokens.accent);
    return Row(
      children: [
        if (statusIcon != null) statusIcon,
        if (voice.statusLabel != null) ...[
          const SizedBox(width: 4),
          ExcludeSemantics(
            child: Text(
              voice.statusLabel!,
              key: const ValueKey('session-voice-status-label'),
              style: TextStyle(
                color: tokens.accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        const Spacer(),
        SizedBox.square(
          dimension: SessionComposer.actionSize,
          child: voiceAction,
        ),
      ],
    );
  }

  Widget _buildEditingFooter({
    required ThemeV2Tokens tokens,
    required SessionComposerPresentation presentation,
    required Widget voiceAction,
  }) {
    return Row(
      children: [
        const Spacer(),
        SizedBox.square(
          dimension: SessionComposer.actionSize,
          child: voiceAction,
        ),
        if (presentation.showSend) ...[
          const SizedBox(width: 8),
          _buildSendAction(tokens, enabled: presentation.canSend),
        ],
      ],
    );
  }

  Widget _buildSendAction(ThemeV2Tokens tokens, {required bool enabled}) {
    return Semantics(
      label: widget.streaming ? '正在发送' : '发送消息',
      button: true,
      enabled: enabled,
      child: SizedBox.square(
        dimension: SessionComposer.actionSize,
        child: IconButton(
          key: const ValueKey('session-send'),
          onPressed: enabled
              ? () => unawaited(_submit(widget.controller.text))
              : null,
          style: IconButton.styleFrom(
            fixedSize: const Size.square(SessionComposer.actionSize),
            backgroundColor: enabled ? tokens.accent : tokens.border,
            foregroundColor: tokens.background,
            disabledForegroundColor: tokens.muted,
          ),
          icon: widget.streaming
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
    );
  }

  InputDecoration _inputDecoration(
    ThemeV2Tokens tokens, {
    required bool expanded,
  }) {
    final idleBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
      borderSide: BorderSide(color: tokens.border),
    );
    return InputDecoration(
      hintText: '问 Agent 任何事…',
      hintStyle: TextStyle(color: tokens.muted),
      prefixIcon: ExcludeSemantics(
        child: IgnorePointer(
          child: Icon(
            Icons.auto_awesome_outlined,
            key: const ValueKey('session-composer-sparkle'),
            color: tokens.accent.withValues(alpha: 0.72),
            size: 18,
          ),
        ),
      ),
      prefixIconConstraints: const BoxConstraints(
        minWidth: ThemeV2Sizes.minTouchTarget,
        minHeight: ThemeV2Sizes.minTouchTarget,
      ),
      filled: true,
      fillColor: tokens.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: expanded ? InputBorder.none : idleBorder,
      enabledBorder: expanded ? InputBorder.none : idleBorder,
      focusedBorder: expanded
          ? InputBorder.none
          : idleBorder.copyWith(borderSide: BorderSide(color: tokens.accent)),
    );
  }

  @override
  void dispose() {
    _removeListeners(widget);
    _textScrollController.dispose();
    super.dispose();
  }
}
