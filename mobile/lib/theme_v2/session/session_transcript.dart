import 'package:flutter/material.dart';

import '../../chat/chat_models.dart';
import '../../pages/chat_page.dart' show ChatMessageBubble;
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import 'session_analysis_block.dart';

class SessionTranscript extends StatefulWidget {
  const SessionTranscript({
    super.key,
    required this.messages,
    required this.analyzing,
    required this.error,
    required this.onRetry,
    required this.onKeepDraft,
    required this.onPrecipitate,
    required this.onStarter,
    this.emptyOpener,
    this.emptyStarters = const [],
  });

  final List<ChatMessage> messages;
  final bool analyzing;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onKeepDraft;
  final Future<void> Function(ChatMessage message, String skill) onPrecipitate;
  final ValueChanged<String> onStarter;
  final String? emptyOpener;
  final List<String> emptyStarters;

  @override
  State<SessionTranscript> createState() => _SessionTranscriptState();
}

class _SessionTranscriptState extends State<SessionTranscript> {
  final _scrollController = ScrollController();
  var _lastMessageCount = 0;
  late String _lastContentSignature;
  var _scrollScheduled = false;

  @override
  void initState() {
    super.initState();
    _lastMessageCount = widget.messages.length;
    _lastContentSignature = _contentSignature();
  }

  @override
  void didUpdateWidget(covariant SessionTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = _contentSignature();
    final contentChanged = signature != _lastContentSignature;
    _lastContentSignature = signature;
    final structuralChange =
        widget.messages.length != _lastMessageCount ||
        widget.analyzing != oldWidget.analyzing;
    final wasFollowingTail =
        !_scrollController.hasClients ||
        _scrollController.position.maxScrollExtent -
                _scrollController.position.pixels <=
            72;
    if (structuralChange || (contentChanged && wasFollowingTail)) {
      _lastMessageCount = widget.messages.length;
      _scheduleTailFollow();
    }
  }

  String _contentSignature() {
    final buffer = StringBuffer()
      ..write(widget.analyzing)
      ..write('|')
      ..write(widget.error);
    for (final message in widget.messages) {
      buffer
        ..write('|')
        ..write(message.id)
        ..write(':')
        ..write(message.streaming)
        ..write(':')
        ..write(message.text.length)
        ..write(':')
        ..write(message.parts.length);
      for (final part in message.parts) {
        switch (part) {
          case TextPart(:final text):
            buffer
              ..write('t')
              ..write(text.length);
          case ToolCallPart(:final name):
            buffer
              ..write('c')
              ..write(name);
          case ToolResultPart(:final name, :final response):
            buffer
              ..write('r')
              ..write(name)
              ..write(response.length);
          case ErrorPart(:final message):
            buffer
              ..write('e')
              ..write(message);
          case CardsPart(:final cards):
            buffer
              ..write('a')
              ..write(cards.length);
        }
      }
    }
    return buffer.toString();
  }

  void _scheduleTailFollow() {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    if (widget.messages.isEmpty && widget.error == null) {
      return SessionEmptyState(
        opener: widget.emptyOpener,
        starters: widget.emptyStarters,
        onStarter: widget.onStarter,
      );
    }
    return Stack(
      key: const ValueKey('session-transcript'),
      children: [
        Positioned(
          right: 10,
          bottom: 72,
          child: IgnorePointer(
            child: Text(
              widget.messages.length.toString().padLeft(2, '0'),
              style: TextStyle(
                color: tokens.watermark,
                fontSize: 96,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ),
        ),
        ListView(
          key: const PageStorageKey('theme-v2-session-transcript-scroll'),
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          children: [
            for (final message in widget.messages)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ChatMessageBubble(
                  message,
                  onPrecipitate: message.isUser
                      ? null
                      : (skill) => widget.onPrecipitate(message, skill),
                ),
              ),
            if (widget.analyzing) ...[
              const SizedBox(height: 4),
              const SessionAnalysisBlock(),
            ],
            if (widget.error != null) ...[
              const SizedBox(height: 12),
              SessionErrorBlock(
                message: widget.error!,
                onRetry: widget.onRetry,
                onKeepDraft: widget.onKeepDraft,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class SessionEmptyState extends StatelessWidget {
  const SessionEmptyState({
    super.key,
    required this.opener,
    required this.starters,
    required this.onStarter,
  });

  final String? opener;
  final List<String> starters;
  final ValueChanged<String> onStarter;

  static const _defaults = ['整理今天的闪念', '回顾最近的记录', '安排明天的待办'];

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final options = starters.isEmpty ? _defaults : starters.take(3).toList();
    return SingleChildScrollView(
      key: const ValueKey('session-empty'),
      padding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.accentSoft,
              shape: BoxShape.circle,
            ),
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tokens.surface,
                shape: BoxShape.circle,
                border: Border.all(color: tokens.border),
              ),
              child: Icon(
                Icons.auto_awesome_outlined,
                color: tokens.accent,
                size: 23,
              ),
            ),
          ),
          const SizedBox(height: 26),
          Text(
            '从一句话开始',
            style: TextStyle(
              color: tokens.foreground,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            opener ?? '记录想法、创建资产，或让 UReka 帮你整理今天。',
            textAlign: TextAlign.center,
            style: TextStyle(color: tokens.muted, fontSize: 11, height: 1.45),
          ),
          const SizedBox(height: 24),
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                height: ThemeV2Sizes.minTouchTarget,
                child: OutlinedButton(
                  onPressed: () => onStarter(option),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    foregroundColor: tokens.foreground,
                    backgroundColor: tokens.surface,
                    side: BorderSide(color: tokens.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          option,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        Icons.north_east_rounded,
                        color: tokens.accent,
                        size: 15,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
