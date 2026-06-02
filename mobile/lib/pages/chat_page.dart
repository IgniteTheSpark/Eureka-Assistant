import 'package:flutter/material.dart';

import '../chat/chat_card.dart';
import '../chat/chat_controller.dart';
import '../chat/chat_models.dart';
import '../chat/markdown_text.dart';
import '../render/skill_card.dart';
import '../theme/app_theme.dart';

/// Agent chat surface — streams POST /api/chat over SSE, renders the agent's
/// markdown text + created cards, and offers 沉淀为资产 on pure Q&A answers.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _chat = ChatController();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

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

  Future<void> _precipitate(ChatMessage m, String skill) {
    final text = m.parts.whereType<TextPart>().map((p) => p.text).join();
    return _chat.precipitate(text, skill);
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final msgs = _chat.messages;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: eu.bg,
      drawer: _SessionsDrawer(chat: _chat),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '历史对话',
                    icon: Icon(Icons.history, color: eu.textMid),
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                  Text('Agent',
                      style: TextStyle(
                          color: eu.textHi, fontSize: 22, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    tooltip: '新对话',
                    icon: Icon(Icons.add_comment_outlined, color: eu.textMid),
                    onPressed: _chat.reset,
                  ),
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
                      itemBuilder: (_, i) => _Bubble(
                        msgs[i],
                        onPrecipitate: (skill) => _precipitate(msgs[i], skill),
                      ),
                    ),
            ),
            _InputBar(controller: _input, onSend: _send, streaming: _chat.streaming),
            const SizedBox(height: 80), // dock clearance
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage m;
  final Future<void> Function(String skill)? onPrecipitate;
  const _Bubble(this.m, {this.onPrecipitate});

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

    final fullText = m.parts.whereType<TextPart>().map((p) => p.text).join();
    final hasCards = m.parts.any((p) =>
        p is ToolResultPart && !isQueryTool(p.name) && extractCards(p.response).isNotEmpty);
    final showPrecipitate =
        !m.streaming && onPrecipitate != null && fullText.length > 8 && !hasCards;

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
            if (showPrecipitate) _PrecipitateMenu(onPick: onPrecipitate!),
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
          child: MarkdownText(text),
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
          children: [for (final c in cards) SkillCard(c)],
        );
      case CardsPart(:final cards):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final c in cards) SkillCard(c)],
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
      child: Text(bits.join(' · '), style: TextStyle(color: eu.textLo, fontSize: 10)),
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

/// 沉淀为资产 — a dropdown of the four free-text asset types; picking one calls
/// onPick(skill) and shows inline saving / done / error state.
class _PrecipitateMenu extends StatefulWidget {
  final Future<void> Function(String skill) onPick;
  const _PrecipitateMenu({required this.onPick});

  @override
  State<_PrecipitateMenu> createState() => _PrecipitateMenuState();
}

class _PrecipitateMenuState extends State<_PrecipitateMenu> {
  static const _types = [
    ('todo', '✅', '待办'),
    ('notes', '📝', '笔记'),
    ('idea', '💡', '想法'),
    ('misc', '🗂', '其它'),
  ];

  String _state = 'idle'; // idle | saving | done | error
  String _label = '';

  Future<void> _pick(String skill, String label) async {
    setState(() => _state = 'saving');
    try {
      await widget.onPick(skill);
      if (mounted) {
        setState(() {
          _state = 'done';
          _label = label;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _state = 'error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    if (_state == 'done') {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, size: 14, color: eu.accentGreen),
            const SizedBox(width: 4),
            Text('已沉淀为$_label', style: TextStyle(color: eu.accentGreen, fontSize: 12)),
          ],
        ),
      );
    }
    final isError = _state == 'error';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: PopupMenuButton<String>(
        enabled: _state != 'saving',
        onSelected: (v) {
          final t = _types.firstWhere((e) => e.$1 == v);
          _pick(t.$1, t.$3);
        },
        itemBuilder: (_) => [
          for (final t in _types) PopupMenuItem(value: t.$1, child: Text('${t.$2} ${t.$3}')),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isError ? eu.accentRed : eu.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_state == 'saving' ? Icons.hourglass_empty : Icons.bookmark_border,
                  size: 13, color: isError ? eu.accentRed : eu.textLo),
              const SizedBox(width: 4),
              Text(isError ? '沉淀失败,重试' : '沉淀为资产',
                  style: TextStyle(color: isError ? eu.accentRed : eu.textLo, fontSize: 12)),
              Icon(Icons.arrow_drop_down, size: 16, color: eu.textLo),
            ],
          ),
        ),
      ),
    );
  }
}

/// Drawer listing the user's sessions; tap to replay one, or start 新对话.
class _SessionsDrawer extends StatefulWidget {
  final ChatController chat;
  const _SessionsDrawer({required this.chat});

  @override
  State<_SessionsDrawer> createState() => _SessionsDrawerState();
}

class _SessionsDrawerState extends State<_SessionsDrawer> {
  late final Future<List<SessionInfo>> _future = widget.chat.listSessions();

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Drawer(
      backgroundColor: eu.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Text('历史对话',
                      style: TextStyle(
                          color: eu.textHi, fontSize: 18, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      widget.chat.reset();
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('新对话'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<SessionInfo>>(
                future: _future,
                builder: (ctx, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final ss = snap.data ?? const [];
                  if (ss.isEmpty) {
                    return Center(child: Text('暂无会话', style: TextStyle(color: eu.textMid)));
                  }
                  return ListView.builder(
                    itemCount: ss.length,
                    itemBuilder: (_, i) {
                      final s = ss[i];
                      final active = s.id == widget.chat.sessionId;
                      return ListTile(
                        title: Text(s.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: active ? eu.brand : eu.textHi, fontSize: 14)),
                        subtitle: Text('${s.createdAt.month}月${s.createdAt.day}日',
                            style: TextStyle(color: eu.textLo, fontSize: 11)),
                        onTap: () async {
                          await widget.chat.loadSession(s.id);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
