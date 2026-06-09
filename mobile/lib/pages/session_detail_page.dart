import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../chat/chat_card.dart';
import '../chat/chat_controller.dart';
import '../chat/chat_models.dart';
import '../chat/markdown_text.dart';
import '../data_revision.dart';
import '../render/skill_card.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';

/// One session opened from the timeline (a ⚡ flash capture or a chat thread).
/// Replays the transcript + the agent's「已记录 N 项内容」summary + the cards it
/// produced, and lets the user continue the conversation (the session stays
/// live — sending appends to it). Pushed as a route, so the app bar's back
/// returns to the previous page. The web hides the global dock on chat pages,
/// so there's no dock here — the input bar takes the bottom.
class SessionDetailPage extends StatefulWidget {
  final String sessionId;
  final String title;
  const SessionDetailPage({super.key, required this.sessionId, required this.title});

  @override
  State<SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<SessionDetailPage> {
  final _chat = ChatController();
  final _api = ApiClient();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late String _sessionId = widget.sessionId;
  late String _title = widget.title;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _chat.addListener(_onChange);
    _load();
    // Hardware capture / flash-done bumps dataRevision → reload so a new
    // capture's input +「正在整理」+ cards appear live in this open session.
    dataRevision.addListener(_reload);
  }

  void _reload() => _chat.loadSession(_sessionId);

  // Resolve the specific session name — flash → "M月D日 闪念", chat → its title.
  Future<void> _loadMeta() async {
    try {
      final res = await _api.getJson('/api/sessions/$_sessionId');
      final s = ((res is Map ? res['session'] : null) as Map?)?.cast<String, dynamic>();
      if (s == null) return;
      String t;
      if (s['session_type'] == 'flash') {
        final d = DateTime.tryParse((s['date'] as String?) ?? '')?.toLocal() ??
            DateTime.tryParse((s['created_at'] as String?) ?? '')?.toLocal();
        t = d != null ? '${d.month}月${d.day}日 闪念' : '闪念';
      } else {
        final st = (s['title'] as String?)?.trim();
        t = (st == null || st.isEmpty) ? widget.title : st;
      }
      if (mounted) setState(() => _title = t);
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      await Future.wait([_chat.loadSession(_sessionId), _loadMeta()]);
    } catch (e) {
      _error = e;
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollToEnd();
    }
  }

  void _openSession(String id) {
    _scaffoldKey.currentState?.closeDrawer();
    if (id == _sessionId) return;
    setState(() {
      _sessionId = id;
      _loading = true;
    });
    _load();
  }

  void _onChange() {
    if (mounted) setState(() {});
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _send() {
    final t = _input.text;
    if (t.trim().isEmpty || _chat.streaming) return;
    _input.clear();
    _chat.send(t);
  }

  @override
  void dispose() {
    dataRevision.removeListener(_reload);
    _chat.removeListener(_onChange);
    _chat.dispose();
    _api.close();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final msgs = _chat.messages;
    // 「正在整理」 when the last turn is a still-unanswered user message (a fresh
    // capture awaiting analysis) — web ChatPage parity.
    final analyzing = !_loading && msgs.isNotEmpty && msgs.last.isUser;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: eu.bg,
      drawer: _SessionsDrawer(chat: _chat, current: _sessionId, onPick: _openSession),
      appBar: AppBar(
        backgroundColor: eu.bg,
        foregroundColor: eu.textHi,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(_title,
            style: TextStyle(color: eu.textHi, fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: '历史会话',
            icon: Icon(Icons.history, color: eu.textMid),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('加载失败：$_error',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: eu.accentRed)),
                          ),
                        )
                      : msgs.isEmpty
                          ? Center(child: Text('没有记录', style: TextStyle(color: eu.textMid)))
                          : ListView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                              itemCount: msgs.length + (analyzing ? 1 : 0),
                              itemBuilder: (_, i) {
                                if (i >= msgs.length) return _analyzingRow(eu);
                                return _Bubble(msgs[i], _sessionId);
                              },
                            ),
            ),
            _InputBar(controller: _input, onSend: _send, streaming: _chat.streaming),
          ],
        ),
      ),
    );
  }

  Widget _analyzingRow(EurekaColors eu) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.6, color: eu.textLo)),
            const SizedBox(width: 8),
            Text('正在整理…',
                style: TextStyle(color: eu.textLo, fontStyle: FontStyle.italic, fontSize: 13)),
          ],
        ),
      );
}

/// History drawer — list sessions, tap to open one in place (web sessions sidebar).
class _SessionsDrawer extends StatefulWidget {
  final ChatController chat;
  final String current;
  final ValueChanged<String> onPick;
  const _SessionsDrawer({required this.chat, required this.current, required this.onPick});

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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('历史会话',
                    style: TextStyle(color: eu.textHi, fontSize: 18, fontWeight: FontWeight.w700)),
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
                      final active = s.id == widget.current;
                      return ListTile(
                        selected: active,
                        title: Text(s.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: active ? eu.brand : eu.textHi, fontSize: 14)),
                        subtitle: Text('${s.createdAt.month}月${s.createdAt.day}日',
                            style: TextStyle(color: eu.textLo, fontSize: 11)),
                        onTap: () => widget.onPick(s.id),
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

class _Bubble extends StatelessWidget {
  final ChatMessage m;
  final String sessionId;
  const _Bubble(this.m, this.sessionId);

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
          ],
        ),
      ),
    );
  }

  // Cards persisted in a flash/chat message may omit the session id (the agent
  // payload doesn't echo it). Stamp this session so the detail sheet shows
  // 「由对话/闪念创建」(not 手动创建) — provenance is consistent with 资产库. §9/§3.
  Map<String, dynamic> _withSession(Map<String, dynamic> c) =>
      (c['session_id'] is String && (c['session_id'] as String).isNotEmpty)
          ? c
          : {...c, 'session_id': sessionId};

  Widget _part(BuildContext context, ChatPart p) {
    final eu = context.eu;
    switch (p) {
      case TextPart(:final text):
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: MarkdownText(text),
        );
      case ToolCallPart():
        return const SizedBox.shrink();
      case ToolResultPart(:final name, :final response):
        final cards = extractCards(response);
        if (isQueryTool(name) || cards.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final c in cards) SkillCard(_withSession(c), layoutOverride: 'horizontal')],
        );
      case CardsPart(:final cards):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final c in cards) SkillCard(_withSession(c), layoutOverride: 'horizontal')],
        );
      case ErrorPart(:final message):
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(message, style: TextStyle(color: eu.accentRed, fontSize: 12)),
        );
    }
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool streaming;
  const _InputBar({required this.controller, required this.onSend, required this.streaming});

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
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
