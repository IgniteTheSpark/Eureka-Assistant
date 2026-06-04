import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../api/api_client.dart';
import '../data_revision.dart';
import '../render/skill_card.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';
import 'flash.dart';

/// Open the 闪念 capture sheet — a conversational capture surface: each input
/// shows as a bubble + "分析中…" then the derived cards (web parity). Voice
/// (press-hold mic) streams a live transcription behind a listening overlay.
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
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _speech = stt.SpeechToText();
  final List<_Turn> _turns = [];
  bool _listening = false;
  bool _sending = false;
  OverlayEntry? _overlay;

  @override
  void dispose() {
    _hideOverlay();
    _speech.stop();
    _api.close();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final t = _input.text.trim();
    if (t.isEmpty || _sending) return;
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
      _toast(r.cards.length);
      // Refresh other surfaces now (don't wait on the SSE `capture` event).
      bumpData();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        turn.analyzing = false;
        turn.result = FlashResult(ok: false, reply: '', summary: '', cards: const [], error: '$e');
        _sending = false;
      });
    }
  }

  void _toast(int n) {
    final eu = context.eu;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: eu.surfaceRaised,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12), side: BorderSide(color: eu.border)),
        content: Row(
          children: [
            const Text('⚡', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('闪念已整理', style: TextStyle(color: eu.textHi, fontWeight: FontWeight.w600)),
                  Text('已记录 $n 项内容。', style: TextStyle(color: eu.textMid, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ));
  }

  /* ── voice (press-hold) ─────────────────────────────────────────────── */

  Future<void> _startListening() async {
    if (_listening) return;
    final ok = await _speech.initialize(
      onStatus: (s) {
        if ((s == 'done' || s == 'notListening')) _stopListening();
      },
      onError: (_) => _stopListening(),
    );
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('语音识别不可用，请检查麦克风权限')));
      }
      return;
    }
    setState(() => _listening = true);
    _showOverlay();
    await _speech.listen(
      listenOptions: stt.SpeechListenOptions(partialResults: true, localeId: 'zh_CN'),
      onResult: (r) {
        _input.text = r.recognizedWords;
        _input.selection = TextSelection.collapsed(offset: _input.text.length);
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _stopListening() async {
    if (!_listening) return;
    await _speech.stop();
    _hideOverlay();
    if (mounted) setState(() => _listening = false);
  }

  void _showOverlay() {
    _overlay = OverlayEntry(builder: (_) => const _ListeningOverlay());
    Overlay.of(context).insert(_overlay!);
  }

  void _hideOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
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
                Text('⚡ 闪念',
                    style: TextStyle(color: eu.textHi, fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: eu.textMid)),
              ],
            ),
            const SizedBox(height: 4),
            Flexible(
              child: _turns.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: Text('说点什么 / 写点什么…\nAI 帮你拆成待办、日程、联系人…',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: eu.textLo, fontSize: 14, height: 1.5)),
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
                    child: CircularProgressIndicator(strokeWidth: 1.6, color: eu.textLo)),
                const SizedBox(width: 8),
                Text('分析中…',
                    style: TextStyle(color: eu.textLo, fontStyle: FontStyle.italic, fontSize: 13)),
              ],
            ),
          )
        else if (t.result != null) ...[
          if (t.result!.error.isNotEmpty)
            Text('出错了：${t.result!.error}', style: TextStyle(color: eu.accentRed, fontSize: 13))
          else ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(
                t.result!.summary.isNotEmpty
                    ? t.result!.summary
                    : (t.result!.reply.isNotEmpty
                        ? t.result!.reply
                        : '已记录 ${t.result!.cards.length} 项内容。'),
                style: TextStyle(color: eu.textHi, fontSize: 14),
              ),
            ),
            for (final c in t.result!.cards) SkillCard(c, layoutOverride: 'horizontal'),
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
          child: TextField(
            controller: _input,
            minLines: 1,
            maxLines: 4,
            enabled: !_sending,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            style: TextStyle(color: eu.textHi),
            decoration: InputDecoration(
              hintText: '说点什么 / 写点什么…',
              hintStyle: TextStyle(color: eu.textLo),
              filled: true,
              fillColor: eu.surfaceRaised,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: eu.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: eu.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: eu.brand)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Press-hold mic → listening overlay; release to end (松开结束录音).
        GestureDetector(
          onTapDown: (_) => _startListening(),
          onTapUp: (_) => _stopListening(),
          onTapCancel: _stopListening,
          child: Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _listening ? eu.accentRed.withValues(alpha: 0.16) : eu.surfaceRaised,
              shape: BoxShape.circle,
              border: Border.all(color: _listening ? eu.accentRed : eu.border),
            ),
            child: Icon(Icons.mic_none, color: _listening ? eu.accentRed : eu.textMid, size: 22),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _sending ? null : _send,
          child: Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: eu.brand, shape: BoxShape.circle),
            child: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.arrow_upward, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

/// Full-screen listening overlay — big gradient mic + animated waveform +
/// 「正在聆听… / 松开按钮结束录音」. Mirrors the web ListeningOverlay. IgnorePointer
/// so the release (pointer-up) still reaches the press-hold mic below.
class _ListeningOverlay extends StatefulWidget {
  const _ListeningOverlay();
  @override
  State<_ListeningOverlay> createState() => _ListeningOverlayState();
}

class _ListeningOverlayState extends State<_ListeningOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return IgnorePointer(
      child: Container(
        color: eu.bg.withValues(alpha: 0.82),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [eu.brand, eu.accentPurple]),
                boxShadow: [BoxShadow(color: eu.brand.withValues(alpha: 0.5), blurRadius: 40, spreadRadius: 6)],
              ),
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (_, child) => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    for (var i = 0; i < 7; i++) ...[
                      _bar(i),
                      if (i < 6) const SizedBox(width: 4),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text('正在聆听…',
                style: TextStyle(color: eu.textHi, fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('松开按钮结束录音', style: TextStyle(color: eu.textMid, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _bar(int i) {
    final phase = (_ctrl.value * 2 * math.pi) + i * 0.7;
    final h = 14 + 22 * (0.5 + 0.5 * math.sin(phase));
    return Container(
      width: 5,
      height: h,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3)),
    );
  }
}
