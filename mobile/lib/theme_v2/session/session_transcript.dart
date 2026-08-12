import 'package:flutter/material.dart';

import '../../capture_activity/capture_activity_event.dart';
import '../../chat/chat_models.dart';
import '../../pages/chat_page.dart' show ChatMessageBubble;
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import 'session_analysis_block.dart';
import '../capture/thinking_orb.dart';

class SessionTranscript extends StatefulWidget {
  const SessionTranscript({
    super.key,
    required this.messages,
    required this.turnCount,
    required this.analyzing,
    required this.error,
    required this.onRetry,
    required this.onKeepDraft,
    required this.onPrecipitate,
    required this.onStarter,
    this.emptyOpener,
    this.emptyStarters = const [],
    this.focusedInputTurnId,
    this.transientCapturePhase,
  });

  final List<ChatMessage> messages;
  final int turnCount;
  final bool analyzing;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onKeepDraft;
  final Future<void> Function(ChatMessage message, String skill) onPrecipitate;
  final ValueChanged<String> onStarter;
  final String? emptyOpener;
  final List<String> emptyStarters;
  final String? focusedInputTurnId;
  final CaptureActivityPhase? transientCapturePhase;

  @override
  State<SessionTranscript> createState() => _SessionTranscriptState();
}

class _SessionTranscriptState extends State<SessionTranscript> {
  final _scrollController = ScrollController();
  var _lastMessageCount = 0;
  late String _lastContentSignature;
  var _scrollScheduled = false;
  var _metricsFollowScheduled = false;
  var _followingTail = true;
  final _focusedTurnAnchor = GlobalKey();
  var _focusRevision = 0;
  var _focusedTurnHighlighted = false;

  @override
  void initState() {
    super.initState();
    _lastMessageCount = widget.messages.length;
    _lastContentSignature = _contentSignature();
    _scheduleFocusedTurn();
  }

  @override
  void didUpdateWidget(covariant SessionTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = _contentSignature();
    final contentChanged = signature != _lastContentSignature;
    _lastContentSignature = signature;
    final structuralChange =
        widget.messages.length != _lastMessageCount ||
        widget.analyzing != oldWidget.analyzing ||
        widget.transientCapturePhase != oldWidget.transientCapturePhase;
    if (structuralChange) _lastMessageCount = widget.messages.length;
    final wasFollowingTail = _followingTail;
    final hasFocusedTurn = _normalizedFocusedTurnId != null;
    if (hasFocusedTurn &&
        (structuralChange ||
            widget.focusedInputTurnId != oldWidget.focusedInputTurnId)) {
      _scheduleFocusedTurn();
    } else if (!hasFocusedTurn &&
        (structuralChange || (contentChanged && wasFollowingTail))) {
      _scheduleTailFollow();
    }
  }

  String? get _normalizedFocusedTurnId {
    final value = widget.focusedInputTurnId?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  int get _focusedMessageIndex {
    final target = _normalizedFocusedTurnId;
    if (target == null) return -1;
    return widget.messages.indexWhere(
      (message) => message.isUser && message.inputTurnId == target,
    );
  }

  void _scheduleFocusedTurn() {
    final targetIndex = _focusedMessageIndex;
    if (targetIndex < 0) return;
    final revision = ++_focusRevision;
    _focusedTurnHighlighted = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealFocusedTurn(revision, targetIndex);
    });
  }

  Future<void> _revealFocusedTurn(int revision, int targetIndex) async {
    if (!mounted || revision != _focusRevision) return;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_focusedTurnAnchor.currentContext == null &&
        _scrollController.hasClients) {
      final position = _scrollController.position;
      final denominator = (widget.messages.length - 1).clamp(1, 1 << 20);
      final fraction = targetIndex / denominator;
      final estimatedOffset =
          position.minScrollExtent +
          (position.maxScrollExtent - position.minScrollExtent) * fraction;
      if (reduceMotion) {
        _scrollController.jumpTo(estimatedOffset);
      } else {
        await _scrollController.animateTo(
          estimatedOffset,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
      if (!mounted || revision != _focusRevision) return;
      await WidgetsBinding.instance.endOfFrame;
    }
    final anchorContext = _focusedTurnAnchor.currentContext;
    if (anchorContext == null ||
        !anchorContext.mounted ||
        !mounted ||
        revision != _focusRevision) {
      return;
    }
    setState(() => _focusedTurnHighlighted = true);
    await Scrollable.ensureVisible(
      anchorContext,
      alignment: 0.46,
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  String _contentSignature() {
    final buffer = StringBuffer()
      ..write(widget.analyzing)
      ..write('|')
      ..write(widget.error)
      ..write('|')
      ..write(widget.transientCapturePhase);
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
      // A streaming Text widget can report its new extent one frame after the
      // parent transcript rebuild. Read the target after that layout settles,
      // otherwise we animate to the previous bottom and leave the latest token
      // below the viewport.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollScheduled = false;
        if (!mounted || !_followingTail || !_scrollController.hasClients) {
          return;
        }
        final target = _scrollController.position.maxScrollExtent;
        if (MediaQuery.disableAnimationsOf(context)) {
          _scrollController.jumpTo(target);
          return;
        }
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
        );
      });
    });
  }

  void _followTailAfterMetricsChange() {
    if (_metricsFollowScheduled) return;
    _metricsFollowScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _metricsFollowScheduled = false;
      if (!mounted ||
          !_followingTail ||
          _normalizedFocusedTurnId != null ||
          !_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      final target = position.maxScrollExtent;
      if (target - position.pixels <= 1) return;
      // The metrics notification already occurs after layout. Keeping the
      // bottom anchor exact here prevents the next token from inheriting a
      // partially completed animation and gradually drifting off-screen.
      _scrollController.jumpTo(target);
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
    if (widget.messages.isEmpty &&
        widget.error == null &&
        widget.transientCapturePhase == null &&
        !widget.analyzing) {
      return SessionEmptyState(
        opener: widget.emptyOpener,
        starters: widget.emptyStarters,
        onStarter: widget.onStarter,
      );
    }
    final hasInlineRunning = widget.messages.any(
      (message) => !message.isUser && message.streaming,
    );
    final hasTurnFailure = widget.messages.any(
      (message) =>
          !message.isUser && message.parts.whereType<ErrorPart>().isNotEmpty,
    );
    return Stack(
      key: const ValueKey('session-transcript'),
      children: [
        Positioned(
          right: 10,
          bottom: 72,
          child: IgnorePointer(
            child: Text(
              widget.turnCount.toString().padLeft(2, '0'),
              style: TextStyle(
                color: tokens.watermark,
                fontSize: 96,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ),
        ),
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) {
            if (_followingTail &&
                notification.metrics.maxScrollExtent -
                        notification.metrics.pixels >
                    1) {
              _followTailAfterMetricsChange();
            }
            return false;
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollStartNotification &&
                  notification.dragDetails != null) {
                _followingTail = false;
              } else if (notification is ScrollUpdateNotification &&
                  notification.dragDetails != null) {
                _followingTail =
                    notification.metrics.maxScrollExtent -
                        notification.metrics.pixels <=
                    16;
              }
              return false;
            },
            child: ListView(
              key: const PageStorageKey('theme-v2-session-transcript-scroll'),
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              children: [
                for (final message in widget.messages)
                  _messageRow(context, message),
                if (widget.transientCapturePhase case final phase?) ...[
                  const SizedBox(height: 4),
                  _SessionTransientCaptureTurn(phase: phase),
                ],
                if (widget.analyzing && !hasInlineRunning) ...[
                  const SizedBox(height: 4),
                  const SessionAnalysisBlock(),
                ],
                if (widget.error != null && !hasTurnFailure) ...[
                  const SizedBox(height: 12),
                  SessionErrorBlock(
                    message: widget.error!,
                    onRetry: widget.onRetry,
                    onKeepDraft: widget.onKeepDraft,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _messageRow(BuildContext context, ChatMessage message) {
    final renderedBubble = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ChatMessageBubble(
        message,
        showStreamingStatus: false,
        onPrecipitate: message.isUser
            ? null
            : (skill) => widget.onPrecipitate(message, skill),
      ),
    );
    final hasFailure =
        !message.isUser && message.parts.whereType<ErrorPart>().isNotEmpty;
    final bubble = !message.isUser && message.streaming
        ? Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.parts.isNotEmpty) renderedBubble,
                SessionAnalysisBlock(phase: message.workPhase),
              ],
            ),
          )
        : hasFailure
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              renderedBubble,
              SessionTurnFailureBlock(onRetry: widget.onRetry),
            ],
          )
        : renderedBubble;
    final target = _normalizedFocusedTurnId;
    if (!message.isUser || target == null || message.inputTurnId != target) {
      return bubble;
    }
    return KeyedSubtree(
      key: _focusedTurnAnchor,
      child: AnimatedContainer(
        key: ValueKey('session-focused-turn-$target'),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: _focusedTurnHighlighted
              ? context.themeV2.accentSoft
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: bubble,
      ),
    );
  }
}

class _SessionTransientCaptureTurn extends StatelessWidget {
  const _SessionTransientCaptureTurn({required this.phase});

  final CaptureActivityPhase phase;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        key: const ValueKey('session-transient-capture-turn'),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.72,
        ),
        padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
        decoration: BoxDecoration(
          color: tokens.accentSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.accent.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ThinkingOrb(state: thinkingOrbStateForCapture(phase), size: 22),
            const SizedBox(width: 8),
            Text(
              phase.label,
              style: TextStyle(
                color: tokens.foreground,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
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
