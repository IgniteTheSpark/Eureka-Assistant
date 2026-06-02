import 'package:flutter/material.dart';

import '../chat/chat_card.dart';
import '../chat/chat_controller.dart';
import '../chat/chat_models.dart';
import '../theme/app_theme.dart';

/// Agent chat surface — streams POST /api/chat over SSE, renders the agent's
/// text + created cards. Sessions sidebar, markdown, and precipitate are later
/// E2 polish.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _chat = ChatController();
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _chat.addListener(_onChange);
  }

  void _onChange() {
    setState(() {});
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

  @override
  void dispose() {
    _chat.removeListener(_onChange);
    _chat.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final t = _input.text;
    if (t.trim().isEmpty || _chat.streaming) return;
    _input.clear();
    _chat.send(t);
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final msgs = _chat.messages;
    return Scaffold(
      backgroundColor: eu.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Text('Agent',
                      style: TextStyle(
                          color: eu.textHi, fontSize: 22, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Expanded(
              child: msgs.isEmpty
                  ? Center(
                      child: Text('问 Agent 任何事…',
                          style: TextStyle(color: eu.textMid, fontSize: 15)))
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      itemCount: msgs.length,
                      itemBuilder: (_, i) => _Bubble(msgs[i]),
                    ),
            ),
            _InputBar(controller: _input, onSend: _send, streaming: _chat.streaming),
            // Clearance for the floating dock.
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage m;
  const _Bubble(this.m);

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final maxW = MediaQuery.of(context).size.width * 0.84;

    if (m.isUser) {
      return Align(
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
          child: Text(m.text, style: TextStyle(color: eu.textHi)),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: maxW),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final p in m.parts) _part(context, p),
            if (m.streaming && m.parts.isEmpty)
              Text('分析中…',
                  style: TextStyle(color: eu.textLo, fontStyle: FontStyle.italic)),
            if (!m.streaming && (m.elapsedMs != null || m.tokens != null))
              _costFooter(context, m),
          ],
        ),
      ),
    );
  }

  Widget _part(BuildContext context, ChatPart p) {
    final eu = context.eu;
    switch (p) {
      case TextPart(:final text):
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(text, style: TextStyle(color: eu.text, height: 1.4)),
        );
      case ToolCallPart(:final name):
        return _chip(context, '${_toolLabel(name)}中…', eu.accentAmber);
      case ToolResultPart(:final name, :final response):
        final cards = extractCards(response);
        if (isQueryTool(name)) {
          return _chip(context, '↩ ${_toolLabel(name)} · 找到 ${cards.length} 项', eu.textLo);
        }
        if (cards.isEmpty) {
          return _chip(context, '↩ ${_toolLabel(name)} 完成', eu.textLo);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final c in cards) ChatCard(c)],
        );
      case ErrorPart(:final message):
        return _chip(context, message, eu.accentRed);
    }
  }

  Widget _chip(BuildContext context, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 12)),
      ),
    );
  }

  Widget _costFooter(BuildContext context, ChatMessage m) {
    final eu = context.eu;
    final bits = <String>[];
    final ms = m.elapsedMs;
    final tk = m.tokens;
    if (ms != null && ms > 0) {
      bits.add(ms < 1000 ? '用时 ${ms}ms' : '用时 ${(ms / 1000).toStringAsFixed(1)}s');
    }
    if (tk != null && tk > 0) {
      bits.add(tk < 1000 ? '$tk tokens' : '${(tk / 1000).toStringAsFixed(1)}k tokens');
    }
    if (bits.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(bits.join(' · '),
          style: TextStyle(color: eu.textLo, fontSize: 10)),
    );
  }

  String _toolLabel(String name) => _toolLabels[name] ?? name;
}

const _toolLabels = {
  'tool_create_asset': '创建资产',
  'tool_update_asset': '更新资产',
  'tool_query_asset': '查询资产',
  'tool_query_digest': '汇总数据',
  'tool_delete_asset': '删除资产',
  'tool_create_event': '创建事件',
  'tool_query_event': '查询事件',
  'tool_create_contact': '创建联系人',
  'tool_query_contact': '查询联系人',
  'tool_create_task': '触发外部任务',
  'tool_render_report': '生成报告',
};

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool streaming;
  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.streaming,
  });

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onSubmitted: (_) => onSend(),
              textInputAction: TextInputAction.send,
              style: TextStyle(color: eu.textHi),
              decoration: InputDecoration(
                hintText: '问 Agent 任何事…',
                hintStyle: TextStyle(color: eu.textLo),
                filled: true,
                fillColor: eu.surfaceRaised,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: eu.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: eu.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: eu.brand),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: streaming ? null : onSend,
            style: IconButton.styleFrom(backgroundColor: eu.brand),
            icon: streaming
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.arrow_upward, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
