import 'package:flutter/material.dart';

import 'reka_terminal_models.dart';
import 'thinking_orb.dart';

class RekaTerminal extends StatefulWidget {
  const RekaTerminal({
    super.key,
    required this.model,
    required this.onClose,
    this.onOpenDetail,
  });

  static const bodyKey = ValueKey<String>('reka-terminal-body');
  static const closeKey = ValueKey<String>('reka-terminal-close');
  static const transcriptViewportKey = ValueKey<String>(
    'reka-terminal-transcript-viewport',
  );
  static const double maximumWidth = 340;
  static const double transcriptFontSize = 17;
  static const double transcriptLineHeight = 1.35;
  static const int transcriptVisibleLines = 4;

  final RekaTerminalModel model;
  final VoidCallback onClose;
  final VoidCallback? onOpenDetail;

  @override
  State<RekaTerminal> createState() => _RekaTerminalState();
}

class _RekaTerminalState extends State<RekaTerminal> {
  final ScrollController _transcriptScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _followTranscriptTail();
  }

  @override
  void didUpdateWidget(covariant RekaTerminal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model.transcript != widget.model.transcript) {
      _followTranscriptTail();
    }
  }

  @override
  void dispose() {
    _transcriptScrollController.dispose();
    super.dispose();
  }

  void _followTranscriptTail() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_transcriptScrollController.hasClients) return;
      _transcriptScrollController.jumpTo(
        _transcriptScrollController.position.maxScrollExtent,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final headerTint = Color.lerp(
      const Color(0xFF171B24),
      widget.model.headerTint(brightness),
      brightness == Brightness.dark ? .42 : .3,
    )!;
    final transcript = widget.model.transcript.trim();
    final canOpen = widget.model.canOpenDetail && widget.onOpenDetail != null;
    final textScale = MediaQuery.textScalerOf(
      context,
    ).scale(RekaTerminal.transcriptFontSize);
    final transcriptHeight =
        textScale *
        RekaTerminal.transcriptLineHeight *
        RekaTerminal.transcriptVisibleLines;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: RekaTerminal.maximumWidth),
      child: Material(
        color: const Color(0xFF101319),
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: .32),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(
              color: headerTint,
              child: Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Row(
                  children: [
                    ThinkingOrb(state: widget.model.orbState, size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        label: widget.model.statusLabel,
                        child: ExcludeSemantics(
                          child: Text(
                            widget.model.statusLabel,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFF5F7FB),
                              fontSize: 13,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      key: RekaTerminal.closeKey,
                      onPressed: widget.onClose,
                      tooltip: '关闭闪念状态',
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 19,
                        color: Color(0xFFCBD2DE),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            InkWell(
              key: RekaTerminal.bodyKey,
              onTap: canOpen ? widget.onOpenDetail : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 13, 16, 15),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.model.sourceCommand,
                            style: const TextStyle(
                              color: Color(0xFF8994A6),
                              fontFamily: 'monospace',
                              fontSize: 10,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                              letterSpacing: .5,
                            ),
                          ),
                        ),
                        if (widget.model.queuedCount > 0)
                          Text(
                            '另有 ${widget.model.queuedCount} 条',
                            style: const TextStyle(
                              color: Color(0xFF8994A6),
                              fontFamily: 'monospace',
                              fontSize: 10,
                              height: 1.2,
                            ),
                          ),
                      ],
                    ),
                    if (transcript.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      ExcludeSemantics(
                        child: ConstrainedBox(
                          key: RekaTerminal.transcriptViewportKey,
                          constraints: BoxConstraints(
                            maxHeight: transcriptHeight,
                          ),
                          child: SingleChildScrollView(
                            controller: _transcriptScrollController,
                            child: Text(
                              transcript,
                              style: const TextStyle(
                                color: Color(0xFFF3F5F8),
                                fontSize: RekaTerminal.transcriptFontSize,
                                height: RekaTerminal.transcriptLineHeight,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (_hintFor(widget.model.phase) case final hint?) ...[
                      const SizedBox(height: 9),
                      Text(
                        hint,
                        style: const TextStyle(
                          color: Color(0xFF788396),
                          fontFamily: 'monospace',
                          fontSize: 10,
                          height: 1.2,
                        ),
                      ),
                    ],
                    if (canOpen) ...[
                      const SizedBox(height: 9),
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_outward_rounded,
                            size: 14,
                            color: Color(0xFFAAB4C4),
                          ),
                          SizedBox(width: 4),
                          Text(
                            '查看整理结果',
                            style: TextStyle(
                              color: Color(0xFFAAB4C4),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String? _hintFor(RekaTerminalPhase phase) => switch (phase) {
  RekaTerminalPhase.connecting || RekaTerminalPhase.listening => '上滑取消 · 松开发送',
  RekaTerminalPhase.cancelArmed => '移回下方继续 · 松开取消',
  RekaTerminalPhase.transcribing => '正在整理最后一句',
  RekaTerminalPhase.sending => '松手后已直接发送',
  _ => null,
};
