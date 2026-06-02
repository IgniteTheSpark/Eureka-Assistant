import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../chat/chat_card.dart';
import '../theme/app_theme.dart';
import 'flash.dart';

/// Open the 闪念 capture sheet. Typed-flash for v0 (BLE capture lands in E3).
Future<void> showFlashSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _FlashSheet(),
  );
}

class _FlashSheet extends StatefulWidget {
  const _FlashSheet();

  @override
  State<_FlashSheet> createState() => _FlashSheetState();
}

class _FlashSheetState extends State<_FlashSheet> {
  final _api = ApiClient();
  final _input = TextEditingController();
  String _state = 'input'; // input | sending | result | error
  FlashResult? _result;
  String _error = '';

  Future<void> _send() async {
    final t = _input.text.trim();
    if (t.isEmpty) return;
    setState(() => _state = 'sending');
    try {
      final r = await sendFlash(_api, t);
      if (!mounted) return;
      setState(() {
        _result = r;
        _state = 'result';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _state = 'error';
      });
    }
  }

  void _again() {
    _input.clear();
    setState(() {
      _state = 'input';
      _result = null;
    });
  }

  @override
  void dispose() {
    _api.close();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
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
                    style: TextStyle(
                        color: eu.textHi, fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: eu.textMid)),
              ],
            ),
            const SizedBox(height: 8),
            if (_state == 'input' || _state == 'sending') ...[
              TextField(
                controller: _input,
                autofocus: true,
                minLines: 3,
                maxLines: 5,
                enabled: _state != 'sending',
                style: TextStyle(color: eu.textHi),
                decoration: InputDecoration(
                  hintText: '说点什么 / 写点什么… AI 帮你拆成待办、日程、联系人…',
                  hintStyle: TextStyle(color: eu.textLo),
                  filled: true,
                  fillColor: eu.surfaceRaised,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: eu.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: eu.border),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _state == 'sending' ? null : _send,
                  style: FilledButton.styleFrom(backgroundColor: eu.brand),
                  child: Text(_state == 'sending' ? '整理中…' : '记下来'),
                ),
              ),
            ],
            if (_state == 'result' && _result != null) ...[
              if (_result!.summary.isNotEmpty || _result!.reply.isNotEmpty)
                Text(_result!.summary.isNotEmpty ? _result!.summary : _result!.reply,
                    style: TextStyle(color: eu.textHi, fontSize: 15)),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [for (final c in _result!.cards) ChatCard(c)],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(onPressed: _again, child: const Text('再记一条')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(backgroundColor: eu.brand),
                      child: const Text('完成'),
                    ),
                  ),
                ],
              ),
            ],
            if (_state == 'error') ...[
              Text('出错了：$_error', style: TextStyle(color: eu.accentRed)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _again,
                  style: FilledButton.styleFrom(backgroundColor: eu.brand),
                  child: const Text('重试'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
