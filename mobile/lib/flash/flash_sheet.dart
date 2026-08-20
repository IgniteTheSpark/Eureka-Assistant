import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data_revision.dart';
import '../render/skill_card.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';
import '../voice_input/voice_input_controller.dart';
import '../voice_input/voice_input_field.dart';
import '../voice_input/voice_input_scope.dart';
import 'flash.dart';

/// Open the 闪念 capture sheet — a conversational capture surface: each input
/// shows as a bubble + "分析中…" then the derived cards (web parity).
Future<void> showFlashSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _FlashSheet(),
  );
}

class _Turn {
  final String text;
  bool analyzing = true;
  FlashResult? result;
  _Turn(this.text);
}

class _FlashSheet extends StatefulWidget {
  const _FlashSheet();
  @override
  State<_FlashSheet> createState() => _FlashSheetState();
}

class _FlashSheetState extends State<_FlashSheet> {
  final _api = ApiClient();
  final _input = VoiceInputTextController();
  final _scroll = ScrollController();
  late final VoiceInputController _voiceController;
  final List<_Turn> _turns = [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _voiceController = VoiceInputController(
      textController: _input,
      service: VoiceInputScope.sharedService,
    )..addListener(_voiceChanged);
  }

  void _voiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _voiceController.removeListener(_voiceChanged);
    unawaited(_voiceController.close());
    _voiceController.dispose();
    _api.close();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final t = _input.text.trim();
    if (t.isEmpty || _sending || _voiceController.isBusy) return;
    _input.clear();
    final turn = _Turn(t);
    setState(() {
      _turns.add(turn);
      _sending = true;
    });
    _scrollEnd();
    try {
      final r = await sendFlash(_api, t);
      if (!mounted) return;
      setState(() {
        turn.analyzing = false;
        turn.result = r;
        _sending = false;
      });
      _scrollEnd();
      // Refresh other surfaces now (don't wait on the SSE `capture` event).
      bumpData();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        turn.analyzing = false;
        turn.result = FlashResult(
          ok: false,
          sessionId: '',
          recordingId: '',
          physicalSessionId: '',
          inputTurnId: '',
          reply: '',
          summary: '',
          cards: const [],
          error: '$e',
          hasPending: false,
        );
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: eu.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: eu.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '⚡ 闪念',
                  style: TextStyle(
                    color: eu.textHi,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: eu.textMid),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Flexible(
              child: _turns.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: Text(
                          '说点什么 / 写点什么…\nAI 帮你拆成待办、日程、联系人…',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: eu.textLo,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _turns.length,
                      itemBuilder: (_, i) => _turnView(eu, _turns[i]),
                    ),
            ),
            const SizedBox(height: 10),
            _inputBar(eu),
          ],
        ),
      ),
    );
  }

  Widget _turnView(EurekaColors eu, _Turn t) {
    final maxW = MediaQuery.of(context).size.width * 0.7;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(maxWidth: maxW),
            decoration: BoxDecoration(
              color: eu.brand.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: eu.brand.withValues(alpha: 0.3)),
            ),
            child: Text(t.text, style: TextStyle(color: eu.textHi)),
          ),
        ),
        if (t.analyzing)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: eu.textLo,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '分析中…',
                  style: TextStyle(
                    color: eu.textLo,
                    fontStyle: FontStyle.italic,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          )
        else if (t.result != null) ...[
          if (t.result!.error.isNotEmpty)
            Text(
              '出错了：${t.result!.error}',
              style: TextStyle(color: eu.accentRed, fontSize: 13),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(
                t.result!.summary.isNotEmpty
                    ? t.result!.summary
                    : (t.result!.reply.isNotEmpty
                          ? t.result!.reply
                          : (t.result!.cards.length == 1
                                ? '我帮你记好了。'
                                : '这些我都帮你记好了。')),
                style: TextStyle(color: eu.textHi, fontSize: 14),
              ),
            ),
            for (final c in t.result!.cards)
              SkillCard(c, layoutOverride: 'horizontal'),
          ],
        ],
      ],
    );
  }

  Widget _inputBar(EurekaColors eu) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: VoiceInputField(
            key: const ValueKey('flash-input-voice'),
            controller: _voiceController,
            enabled: !_sending,
            builder: (context, voiceBusy) => TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              enabled: !_sending,
              readOnly: voiceBusy,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              style: TextStyle(color: eu.textHi),
              decoration: InputDecoration(
                hintText: '说点什么 / 写点什么…',
                hintStyle: TextStyle(color: eu.textLo),
                filled: true,
                fillColor: eu.surfaceRaised,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: eu.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: eu.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: eu.brand),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _sending || _voiceController.isBusy ? null : _send,
          child: Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: eu.brand, shape: BoxShape.circle),
            child: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.arrow_upward, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
