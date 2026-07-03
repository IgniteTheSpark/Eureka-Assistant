import 'package:flutter/material.dart';

import '../assets/assets.dart';
import '../chat/chat_card.dart';
import '../chat/chat_controller.dart';
import '../chat/chat_models.dart';
import '../chat/markdown_text.dart';
import '../render/skill_card.dart';
import '../theme/app_theme.dart';
import '../api/api_client.dart';
import '../theme/eureka_colors.dart';
import '../widgets/asset_picker.dart';
import '../widgets/toast.dart';

/// Agent chat surface — streams POST /api/chat over SSE, renders the agent's
/// markdown text + created cards, and offers 沉淀为资产 on pure Q&A answers.
class ChatPage extends StatefulWidget {
  /// When opened on an existing session (e.g. from history), replay it.
  final String? boundSessionId;

  /// When opened from an asset's 讨论 action, the subject is bound *lazily*:
  /// [subjectType]/[subjectId] identify it, [subjectLabel] is the readable
  /// header. No session is created until the first message is sent.
  final String? subjectType;
  final String? subjectId;
  final String? subjectLabel;

  /// Force a brand-new, empty conversation (no resume, no anchor, no context).
  /// Used by the REKA 「新建对话」 action so it never inherits the last thread.
  final bool startBlank;
  const ChatPage({
    super.key,
    this.boundSessionId,
    this.subjectType,
    this.subjectId,
    this.subjectLabel,
    this.startBlank = false,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _chat = ChatController();
  final List<({String id, String label})> _context = [];
  // The anchored subject (🔗 常驻关联资产). Mutable so 新建对话 can clear it — the
  // widget param is immutable, so we mirror it here and drive the chip/header
  // from this field instead.
  String? _anchorLabel;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _tailKey = GlobalKey();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _scrollRequest = 0;

  // §1.5.1 开场 hint — 空态脚手架(opener + 起聊 chips),仅锚定会话且无历史时
  // 显示;不落库为消息,用户点 chip / 打字即进入正常对话。
  String? _hintOpener;
  List<String> _hintStarters = const [];

  @override
  void initState() {
    super.initState();
    _anchorLabel = widget.subjectLabel;
    _chat.addListener(_onChange);
    if (widget.startBlank) {
      // 新建对话 — leave the fresh controller blank: no resume, no subject, no
      // context. (Constructed empty already; just skip resumeLast.)
    } else if (widget.boundSessionId != null) {
      _chat.loadSession(widget.boundSessionId!);
    } else if (widget.subjectType != null && widget.subjectId != null) {
      // Pending subject — peek for an existing thread, but don't create one.
      _chat.bindSubject(widget.subjectType!, widget.subjectId!);
      _loadOpeningHint(widget.subjectType!, widget.subjectId!);
    } else {
      // Plain Agent entry — resume the last active conversation (web parity),
      // so backing out and returning doesn't lose the thread.
      _chat.resumeLast();
    }
  }

  // 新建对话 — wipe everything so the new thread carries no context: the
  // controller (messages / session / bound subject / attached assets), the local
  // chip rail, and the anchored subject chip.
  void _newConversation() {
    _context.clear();
    _anchorLabel = null;
    _chat.reset(); // clears contextAssets + subject + session, then notifies
    setState(() {});
  }

  void _onChange() {
    // Restore the context chip rail after a history session loads (codex r2 —
    // was empty on reopen). Seeds once: manual attaches make _context non-empty.
    if (_context.isEmpty && _chat.contextAssets.isNotEmpty) {
      _context.addAll(
        _chat.contextAssets.map((c) => (id: c.id, label: c.label)),
      );
    }
    setState(() {});
    _scrollToEnd();
  }

  void _scrollToEnd() {
    final request = ++_scrollRequest;
    void alignTail({required bool animated}) {
      if (!mounted || request != _scrollRequest) return;
      final tailContext = _tailKey.currentContext;
      if (tailContext != null) {
        Scrollable.ensureVisible(
          tailContext,
          alignment: 1,
          duration: animated
              ? const Duration(milliseconds: 200)
              : Duration.zero,
          curve: Curves.easeOut,
        );
        return;
      }
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;
      final target = pos.maxScrollExtent
          .clamp(pos.minScrollExtent, pos.maxScrollExtent)
          .toDouble();
      if (animated) {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(target);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      alignTail(animated: true);
      Future<void>.delayed(
        const Duration(milliseconds: 80),
        () => alignTail(animated: false),
      );
      Future<void>.delayed(
        const Duration(milliseconds: 240),
        () => alignTail(animated: false),
      );
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

  // §1.5.1: L0+L1 hint 由服务端现算(零 LLM,毫秒级);失败静默 → 退回通用空态。
  Future<void> _loadOpeningHint(String type, String id) async {
    final api = ApiClient();
    try {
      final r = await api.getJson(
        '/api/sessions/opening-hint',
        query: {'subject_type': type, 'subject_id': id},
      );
      if (!mounted || r is! Map) return;
      setState(() {
        _hintOpener = r['opener'] as String?;
        _hintStarters = ((r['starters'] as List?) ?? const [])
            .whereType<String>()
            .take(3)
            .toList();
      });
    } catch (_) {
      /* hint 是增强,失败不打扰 */
    } finally {
      api.close();
    }
  }

  // 点起聊 chip = 把它作为首条用户消息发出 → 进入正常 chat 管线(§1.5.1)。
  void _sendStarter(String text) {
    if (_chat.streaming) return;
    _chat.send(text);
  }

  void _send() {
    final t = _input.text;
    if (t.trim().isEmpty || _chat.streaming) return;
    _input.clear();
    _chat.send(t);
  }

  // Context chip rail (web SessionTopicBar): subject + attached assets + the
  // 「+ 添加资产」 picker, so context can be added continuously.
  Widget _contextBar(EurekaColors eu) {
    return Container(
      height: 38,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // 「+ 添加资产」 first so it's always reachable without scrolling past
          // a long context list.
          _addChip(eu),
          // The anchored subject asset is a persistent accent chip (常驻关联资产).
          if (_anchorLabel != null)
            _ctxChip(eu, '🔗', _anchorLabel!, accent: true),
          for (final c in _context) _ctxChip(eu, '•', c.label),
        ],
      ),
    );
  }

  Widget _ctxChip(
    EurekaColors eu,
    String icon,
    String label, {
    bool accent = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent ? eu.brand.withValues(alpha: 0.12) : eu.surfaceRaised,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent ? eu.brand.withValues(alpha: 0.30) : eu.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: accent ? eu.textHi : eu.textMid,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _addChip(EurekaColors eu) {
    return GestureDetector(
      onTap: _addContext,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: eu.textLo, style: BorderStyle.solid),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 13, color: eu.textMid),
            const SizedBox(width: 3),
            Text('添加资产', style: TextStyle(color: eu.textMid, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Future<void> _addContext() async {
    final picked = await _showAssetPicker();
    if (picked == null || picked.isEmpty) return;
    final ok = await _chat.attachContexts(picked.map((a) => a.id).toList());
    if (ok && mounted) {
      setState(() {
        for (final a in picked) {
          _context.add((id: a.id, label: a.title));
        }
      });
    } else if (mounted) {
      showToast(context, '添加失败', error: true);
    }
  }

  Future<List<AssetItem>?> _showAssetPicker() {
    final eu = context.eu;
    final taken = _context.map((c) => c.id).toSet();
    return showModalBottomSheet<List<AssetItem>>(
      context: context,
      backgroundColor: eu.surfaceRaised,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => AssetPickerPanel(excludeIds: taken),
    );
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
      drawer: _SessionsDrawer(chat: _chat, onNewConversation: _newConversation),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 8, 6),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回',
                    icon: Icon(Icons.arrow_back, color: eu.textMid),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Text(
                      // Discuss threads show their subject; otherwise the
                      // session's readable title (never a bare "Agent").
                      _anchorLabel?.isNotEmpty == true
                          ? _anchorLabel!
                          : _chat.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: eu.textHi,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 新会话直接放在头部,和「历史对话」平齐 —— 不必先打开历史抽屉
                  // 再去右上角找「新对话」。复用 _newConversation(原地清空开新线程)。
                  IconButton(
                    tooltip: '新会话',
                    icon: Icon(Icons.add_comment_outlined, color: eu.textMid),
                    onPressed: _newConversation,
                  ),
                  IconButton(
                    tooltip: '历史对话',
                    icon: Icon(Icons.history, color: eu.textMid),
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                ],
              ),
            ),
            _contextBar(eu),
            Expanded(
              child: msgs.isEmpty
                  ? (_hintOpener != null
                        ? _openingHint(eu)
                        : Center(
                            child: Text(
                              '问 Agent 任何事…',
                              style: TextStyle(color: eu.textMid, fontSize: 15),
                            ),
                          ))
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      itemCount: msgs.length,
                      itemBuilder: (_, i) {
                        final child = _Bubble(
                          msgs[i],
                          onPrecipitate: (skill) =>
                              _precipitate(msgs[i], skill),
                        );
                        return i == msgs.length - 1
                            ? KeyedSubtree(key: _tailKey, child: child)
                            : child;
                      },
                    ),
            ),
            _InputBar(
              controller: _input,
              onSend: _send,
              streaming: _chat.streaming,
            ),
          ],
        ),
      ),
    );
  }

  /// §1.5.1 空态开场 hint:REKA 口吻的 opener + 2-3 个可点起聊 chip。
  Widget _openingHint(EurekaColors eu) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('✦', style: TextStyle(color: eu.brand, fontSize: 15)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _hintOpener!,
                    style: TextStyle(
                      color: eu.textHi,
                      fontSize: 15.5,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final st in _hintStarters)
                  GestureDetector(
                    onTap: () => _sendStarter(st),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: eu.brand.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: eu.brand.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        st,
                        style: TextStyle(color: eu.brand, fontSize: 13.5),
                      ),
                    ),
                  ),
              ],
            ),
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
    // Did THIS turn create cards? (web turnCreatedCards): a persisted `cards`
    // part, OR a non-query tool_result that yielded cards. If so, hide
    // 沉淀为资产 — the user already got a real asset. (Must include CardsPart, or
    // a replayed/created-card turn wrongly offers precipitate after reload.)
    final hasCards = m.parts.any(
      (p) =>
          (p is CardsPart && p.cards.isNotEmpty) ||
          (p is ToolResultPart &&
              !isQueryTool(p.name) &&
              extractCards(p.response).isNotEmpty),
    );
    final showPrecipitate =
        !m.streaming &&
        onPrecipitate != null &&
        fullText.length > 8 &&
        !hasCards;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: maxW),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var idx = 0; idx < m.parts.length; idx++)
              _part(
                context,
                m.parts[idx],
                isLast: idx == m.parts.length - 1,
                streaming: m.streaming,
              ),
            if (m.streaming && m.parts.isEmpty)
              Text(
                '分析中…',
                style: TextStyle(color: eu.textLo, fontStyle: FontStyle.italic),
              ),
            if (m.streaming &&
                m.parts.isNotEmpty &&
                (m.parts.last is ToolResultPart || m.parts.last is CardsPart))
              _workingHint(context),
            if (showPrecipitate) _PrecipitateMenu(onPick: onPrecipitate!),
            if (!m.streaming && (m.elapsedMs != null || m.tokens != null))
              _costFooter(context, m),
          ],
        ),
      ),
    );
  }

  Widget _part(
    BuildContext context,
    ChatPart p, {
    required bool isLast,
    required bool streaming,
  }) {
    final eu = context.eu;
    switch (p) {
      case TextPart(:final text):
        // Streaming tail renders raw (no markdown) + cursor so half-typed `**`
        // don't jitter; settled text gets the lightweight markdown pass.
        if (streaming && isLast) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: _StreamingText(text),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: MarkdownText(text),
        );
      case ToolCallPart(:final name):
        // Only the in-flight call (last part of a streaming msg) shows a spinner;
        // once its tool_result lands the call is no longer last → drop it
        // (the result continues the thread; a leftover chip is redundant).
        if (!(streaming && isLast)) return const SizedBox.shrink();
        return _spinnerChip(context, '${_toolLabel(name)}中…', eu.accentAmber);
      case ToolResultPart(:final name, :final response):
        final cards = extractCards(response);
        if (isQueryTool(name)) {
          // Fold query results behind a tap so mid-conversation lookups don't
          // flood the thread (§4.2.3 CollapsibleQueryResult).
          return _CollapsibleQueryResult(label: _toolLabel(name), cards: cards);
        }
        if (cards.isEmpty) {
          return _chip(
            context,
            '${_toolLabel(name)} 完成',
            eu.textLo,
            icon: Icons.check_rounded,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final c in cards) SkillCard(c, layoutOverride: 'horizontal'),
          ],
        );
      case CardsPart(:final cards):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final c in cards) SkillCard(c, layoutOverride: 'horizontal'),
          ],
        );
      case ErrorPart(:final message):
        return _chip(context, message, eu.accentRed);
    }
  }

  Widget _chip(
    BuildContext context,
    String label,
    Color color, {
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
            ],
            // Flexible + softWrap so a long message (e.g. a raw error) wraps
            // instead of overflowing the bubble horizontally.
            Flexible(
              child: Text(
                label,
                softWrap: true,
                style: TextStyle(color: color, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _spinnerChip(BuildContext context, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: color),
            ),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _workingHint(BuildContext context) {
    final eu = context.eu;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
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
          const SizedBox(width: 6),
          Text(
            '处理中…',
            style: TextStyle(
              color: eu.textLo,
              fontStyle: FontStyle.italic,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _costFooter(BuildContext context, ChatMessage m) {
    final eu = context.eu;
    final bits = <String>[];
    final ms = m.elapsedMs;
    final tk = m.tokens;
    if (ms != null && ms > 0) {
      bits.add(
        ms < 1000 ? '用时 ${ms}ms' : '用时 ${(ms / 1000).toStringAsFixed(1)}s',
      );
    }
    if (tk != null && tk > 0) {
      bits.add(
        tk < 1000 ? '$tk tokens' : '${(tk / 1000).toStringAsFixed(1)}k tokens',
      );
    }
    if (bits.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        bits.join(' · '),
        style: TextStyle(color: eu.textLo, fontSize: 10),
      ),
    );
  }

  String _toolLabel(String name) => _toolLabels[name] ?? name;
}

const _toolLabels = {
  // CREATE 一律叫「创建资产」—— 待办/事件/名片/随记 对用户都是「资产」,不暴露内部类型。
  'tool_create_asset': '创建资产',
  'tool_create_todo': '创建资产',
  'tool_create_note': '创建资产',
  'tool_create_event': '创建资产',
  'tool_create_contact': '创建资产',
  'tool_update_asset': '更新资产',
  'tool_update_event': '更新资产',
  'tool_update_contact': '更新资产',
  'tool_query_asset': '查询资产',
  'tool_query_digest': '汇总数据',
  'tool_delete_asset': '删除资产',
  'tool_query_event': '查询事件',
  'tool_get_event': '查询事件',
  'query_event': '查询事件',
  'get_event': '查询事件',
  'tool_query_contact': '查询联系人',
  'tool_get_contact': '查询联系人',
  'query_contact': '查询联系人',
  'get_contact': '查询联系人',
  'tool_create_task': '触发外部任务',
};

/// Streaming tail: raw text (no markdown) + a blinking caret, matching the web's
/// `Cursor` so half-typed `**` don't flicker mid-stream (§4.2.3).
class _StreamingText extends StatefulWidget {
  final String text;
  const _StreamingText(this.text);

  @override
  State<_StreamingText> createState() => _StreamingTextState();
}

class _StreamingTextState extends State<_StreamingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final base = TextStyle(color: eu.text, fontSize: 14, height: 1.4);
    return RichText(
      text: TextSpan(
        style: base,
        children: [
          TextSpan(text: widget.text),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: FadeTransition(
              opacity: _c,
              child: Container(
                width: 7,
                height: 15,
                margin: const EdgeInsets.only(left: 1),
                color: eu.brand,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Folds a query tool_result into a one-line "↩ 查询资产 · 找到 N 项 ▸"; tapping
/// reveals the found cards (§4.2.3 CollapsibleQueryResult).
class _CollapsibleQueryResult extends StatefulWidget {
  final String label;
  final List<Map<String, dynamic>> cards;
  const _CollapsibleQueryResult({required this.label, required this.cards});

  @override
  State<_CollapsibleQueryResult> createState() =>
      _CollapsibleQueryResultState();
}

class _CollapsibleQueryResultState extends State<_CollapsibleQueryResult> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final n = widget.cards.length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: n == 0 ? null : () => setState(() => _open = !_open),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: eu.textLo.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: eu.textLo.withValues(alpha: 0.24)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_rounded, size: 13, color: eu.textLo),
                  const SizedBox(width: 5),
                  Text(
                    '${widget.label} · 找到 $n 项',
                    style: TextStyle(color: eu.textLo, fontSize: 12),
                  ),
                  if (n > 0) ...[
                    const SizedBox(width: 4),
                    Icon(
                      _open ? Icons.expand_less : Icons.chevron_right,
                      size: 15,
                      color: eu.textLo,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_open)
            for (final c in widget.cards)
              SkillCard(c, layoutOverride: 'horizontal'),
        ],
      ),
    );
  }
}

/// 沉淀为资产 — a dropdown of the four free-text asset types; picking one calls
/// onPick(skill) and shows inline saving / done / error state.
class _PrecipitateMenu extends StatefulWidget {
  final Future<void> Function(String skill) onPick;
  const _PrecipitateMenu({required this.onPick});

  @override
  State<_PrecipitateMenu> createState() => _PrecipitateMenuState();
}

class _PrecipitateMenuState extends State<_PrecipitateMenu> {
  // idea/notes/misc merged into 随记 (notes). Precipitate offers 待办 or 随记.
  static const _types = [('todo', '✅', '待办'), ('notes', '✍️', '随记')];

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
            Text(
              '已沉淀为$_label',
              style: TextStyle(color: eu.accentGreen, fontSize: 12),
            ),
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
          for (final t in _types)
            PopupMenuItem(value: t.$1, child: Text('${t.$2} ${t.$3}')),
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
              Icon(
                _state == 'saving'
                    ? Icons.hourglass_empty
                    : Icons.bookmark_border,
                size: 13,
                color: isError ? eu.accentRed : eu.textLo,
              ),
              const SizedBox(width: 4),
              Text(
                isError ? '沉淀失败,重试' : '沉淀为资产',
                style: TextStyle(
                  color: isError ? eu.accentRed : eu.textLo,
                  fontSize: 12,
                ),
              ),
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
  final VoidCallback onNewConversation;
  const _SessionsDrawer({required this.chat, required this.onNewConversation});

  @override
  State<_SessionsDrawer> createState() => _SessionsDrawerState();
}

class _SessionsDrawerState extends State<_SessionsDrawer> {
  List<SessionInfo>? _sessions;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final ss = await widget.chat.listSessions();
      if (mounted) {
        setState(() {
          _sessions = ss;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<bool> _confirmDelete(SessionInfo s) async {
    final eu = context.eu;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: eu.surfaceRaised,
        title: Text('删除会话？', style: TextStyle(color: eu.textHi)),
        content: Text(
          '「${s.title}」将被删除，其中产生的资产会保留。',
          style: TextStyle(color: eu.textMid),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: TextStyle(color: eu.textMid)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '删除',
              style: TextStyle(
                color: eu.accentRed,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _delete(SessionInfo s) async {
    final ok = await widget.chat.deleteSession(s.id);
    if (!mounted) return;
    if (ok) {
      setState(() => _sessions?.removeWhere((x) => x.id == s.id));
    } else {
      showToast(context, '删除失败', error: true);
      _load(); // restore the row that Dismissible already swiped away
    }
  }

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
                  Text(
                    '历史对话',
                    style: TextStyle(
                      color: eu.textHi,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      widget
                          .onNewConversation(); // clears anchor + context + session
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('新对话'),
                  ),
                ],
              ),
            ),
            Expanded(child: _list(eu)),
          ],
        ),
      ),
    );
  }

  Widget _list(EurekaColors eu) {
    if (_error != null) {
      return Center(
        child: Text('加载失败', style: TextStyle(color: eu.textMid)),
      );
    }
    final ss = _sessions;
    if (ss == null) return const Center(child: CircularProgressIndicator());
    if (ss.isEmpty) {
      return Center(
        child: Text('暂无会话', style: TextStyle(color: eu.textMid)),
      );
    }
    return ListView.builder(
      itemCount: ss.length,
      itemBuilder: (_, i) {
        final s = ss[i];
        final active = s.id == widget.chat.sessionId;
        // Swipe left to delete (iOS-native), with a confirm dialog.
        return Dismissible(
          key: ValueKey(s.id),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) => _confirmDelete(s),
          onDismissed: (_) => _delete(s),
          background: Container(
            alignment: Alignment.centerRight,
            color: eu.accentRed.withValues(alpha: 0.18),
            padding: const EdgeInsets.only(right: 20),
            child: Icon(Icons.delete_outline, color: eu.accentRed),
          ),
          child: ListTile(
            title: Text(
              s.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? eu.brand : eu.textHi,
                fontSize: 14,
              ),
            ),
            subtitle: Text(
              '${s.createdAt.month}月${s.createdAt.day}日',
              style: TextStyle(color: eu.textLo, fontSize: 11),
            ),
            onTap: () async {
              await widget.chat.loadSession(s.id, title: s.title);
              if (mounted) Navigator.of(context).pop();
            },
          ),
        );
      },
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
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
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.arrow_upward, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
