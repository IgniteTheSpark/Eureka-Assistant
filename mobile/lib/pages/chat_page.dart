import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../assets/assets.dart';
import '../chat/chat_card.dart';
import '../chat/chat_controller.dart';
import '../chat/chat_models.dart';
import '../chat/markdown_text.dart';
import '../render/render_spec.dart';
import '../render/skill_card.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';
import '../timeline/timeline.dart';

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
  const ChatPage({
    super.key,
    this.boundSessionId,
    this.subjectType,
    this.subjectId,
    this.subjectLabel,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _chat = ChatController();
  final List<({String id, String label})> _context = [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _chat.addListener(_onChange);
    if (widget.boundSessionId != null) {
      _chat.loadSession(widget.boundSessionId!);
    } else if (widget.subjectType != null && widget.subjectId != null) {
      // Pending subject — peek for an existing thread, but don't create one.
      _chat.bindSubject(widget.subjectType!, widget.subjectId!);
    } else {
      // Plain Agent entry — resume the last active conversation (web parity),
      // so backing out and returning doesn't lose the thread.
      _chat.resumeLast();
    }
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
          if (widget.subjectLabel != null)
            _ctxChip(eu, '🔗', widget.subjectLabel!, accent: true),
          for (final c in _context) _ctxChip(eu, '•', c.label),
        ],
      ),
    );
  }

  Widget _ctxChip(EurekaColors eu, String icon, String label, {bool accent = false}) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent ? eu.brand.withValues(alpha: 0.12) : eu.surfaceRaised,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent ? eu.brand.withValues(alpha: 0.30) : eu.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(color: accent ? eu.textHi : eu.textMid, fontSize: 12)),
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
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('添加失败')));
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
      builder: (_) => _AssetPicker(excludeIds: taken),
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
      drawer: _SessionsDrawer(chat: _chat),
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
                      widget.subjectLabel?.isNotEmpty == true
                          ? widget.subjectLabel!
                          : _chat.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: eu.textHi, fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
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
    // part, OR a non-query/report tool_result that yielded cards. If so, hide
    // 沉淀为资产 — the user already got a real asset. (Must include CardsPart, or
    // a replayed/created-card turn wrongly offers precipitate after reload.)
    final hasCards = m.parts.any((p) =>
        (p is CardsPart && p.cards.isNotEmpty) ||
        (p is ToolResultPart && !isQueryTool(p.name) && extractCards(p.response).isNotEmpty));
    final showPrecipitate = !m.streaming &&
        onPrecipitate != null &&
        fullText.length > 8 &&
        !hasCards &&
        !_looksLikeHtmlReport(fullText);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: maxW),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var idx = 0; idx < m.parts.length; idx++)
              _part(context, m.parts[idx],
                  isLast: idx == m.parts.length - 1, streaming: m.streaming),
            if (m.streaming && m.parts.isEmpty)
              Text('分析中…',
                  style: TextStyle(color: eu.textLo, fontStyle: FontStyle.italic)),
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

  Widget _part(BuildContext context, ChatPart p,
      {required bool isLast, required bool streaming}) {
    final eu = context.eu;
    switch (p) {
      case TextPart(:final text):
        // Salvage: deepseek sometimes dumps a report's HTML as plain text. Never
        // show raw markup in chat — fold it into a receipt (§4.2.3).
        if (_looksLikeHtmlReport(text)) {
          return _ReportReceipt(
            title: _titleFromHtml(text),
            body: _htmlToText(text),
            streaming: streaming && isLast,
          );
        }
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
        if (name == 'tool_render_report') {
          return _ReportReceipt(
            title: _titleFromResult(response),
            body: _bodyFromResult(response),
            streaming: false,
          );
        }
        final cards = extractCards(response);
        if (isQueryTool(name)) {
          // Fold query results behind a tap so mid-conversation lookups don't
          // flood the thread (§4.2.3 CollapsibleQueryResult).
          return _CollapsibleQueryResult(label: _toolLabel(name), cards: cards);
        }
        if (cards.isEmpty) {
          return _chip(context, '↩ ${_toolLabel(name)} 完成', eu.textLo);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final c in cards) SkillCard(c, layoutOverride: 'horizontal')],
        );
      case CardsPart(:final cards):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final c in cards) SkillCard(c, layoutOverride: 'horizontal')],
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
            child: CircularProgressIndicator(strokeWidth: 1.6, color: eu.textLo),
          ),
          const SizedBox(width: 6),
          Text('处理中…',
              style: TextStyle(color: eu.textLo, fontStyle: FontStyle.italic, fontSize: 13)),
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

/* ── report salvage / HTML-to-text (§4.2.3 ReportReceiptCard) ───────────────── */

final _htmlReportLead = RegExp(r'^\s*(```html|<!doctype|<html|<style)', caseSensitive: false);

/// True when an agent text part is actually a report's HTML dumped as text — we
/// never render raw markup in chat, so this routes to a [_ReportReceipt].
bool _looksLikeHtmlReport(String t) {
  if (t.isEmpty) return false;
  return _htmlReportLead.hasMatch(t) || t.toLowerCase().contains('<style');
}

final _tagRe = RegExp(r'<[^>]+>');
final _spacesRe = RegExp(r'[ \t]{2,}');
final _blanksRe = RegExp(r'\n{3,}');

/// Flatten report HTML to readable text (no WebView dependency). Strips
/// style/script, turns block tags into line breaks, decodes common entities.
String _htmlToText(String html) {
  var s = html
      .replaceAll(RegExp(r'```html', caseSensitive: false), '')
      .replaceAll('```', '')
      .replaceAll(RegExp(r'<style[^>]*>.*?</style>', caseSensitive: false, dotAll: true), '')
      .replaceAll(RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false, dotAll: true), '')
      .replaceAll(
          RegExp(r'</(p|div|h[1-6]|li|tr|table|section|header|footer|ul|ol)>',
              caseSensitive: false),
          '\n')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(_tagRe, '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
  return s.replaceAll(_spacesRe, ' ').replaceAll(_blanksRe, '\n\n').trim();
}

String _titleFromHtml(String html) {
  final m = RegExp(r'<title>(.*?)</title>', caseSensitive: false, dotAll: true).firstMatch(html) ??
      RegExp(r'<h1[^>]*>(.*?)</h1>', caseSensitive: false, dotAll: true).firstMatch(html);
  final t = m == null ? '' : _htmlToText(m.group(1)!).trim();
  return t.isEmpty ? '整理报告' : t;
}

String _titleFromResult(Map<String, dynamic> r) {
  final sc = r['structuredContent'];
  final t = r['title'] ?? (sc is Map ? sc['title'] : null);
  return (t is String && t.trim().isNotEmpty) ? t.trim() : '整理报告';
}

String _bodyFromResult(Map<String, dynamic> r) {
  dynamic html = r['html'] ?? r['report_html'];
  final sc = r['structuredContent'];
  if (html == null && sc is Map) html = sc['html'] ?? sc['report_html'];
  if (html == null) {
    final content = r['content'];
    if (content is List && content.isNotEmpty && content.first is Map) {
      final txt = (content.first as Map)['text'];
      if (txt is String) html = txt;
    }
  }
  if (html is String && html.trim().isNotEmpty) {
    return html.contains('<') ? _htmlToText(html) : html.trim();
  }
  return '报告已生成。';
}

/// Streaming tail: raw text (no markdown) + a blinking caret, matching the web's
/// `Cursor` so half-typed `**` don't flicker mid-stream (§4.2.3).
class _StreamingText extends StatefulWidget {
  final String text;
  const _StreamingText(this.text);

  @override
  State<_StreamingText> createState() => _StreamingTextState();
}

class _StreamingTextState extends State<_StreamingText> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true);

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
      text: TextSpan(style: base, children: [
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
      ]),
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
  State<_CollapsibleQueryResult> createState() => _CollapsibleQueryResultState();
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
                  Text('↩ ${widget.label} · 找到 $n 项',
                      style: TextStyle(color: eu.textLo, fontSize: 12)),
                  if (n > 0) ...[
                    const SizedBox(width: 4),
                    Icon(_open ? Icons.expand_less : Icons.chevron_right,
                        size: 15, color: eu.textLo),
                  ],
                ],
              ),
            ),
          ),
          if (_open)
            for (final c in widget.cards) SkillCard(c, layoutOverride: 'horizontal'),
        ],
      ),
    );
  }
}

/// Compact report receipt — opens the full report in a sheet instead of dumping
/// HTML into the thread (§4.2.3 ReportReceiptCard → ReportSheet).
class _ReportReceipt extends StatelessWidget {
  final String title;
  final String body;
  final bool streaming;
  const _ReportReceipt({required this.title, required this.body, required this.streaming});

  void _open(BuildContext context) {
    final eu = context.eu;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: eu.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _ReportSheet(title: title, body: body),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        onTap: streaming ? null : () => _open(context),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: eu.brand.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: eu.brand.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: eu.brand.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: eu.brand.withValues(alpha: 0.30)),
                ),
                child: const Text('📄', style: TextStyle(fontSize: 15)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(streaming ? '整理报告中…' : title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: eu.textHi, fontSize: 13.5, fontWeight: FontWeight.w600)),
                    Text(streaming ? '约 15-30 秒' : '点击查看报告',
                        style: TextStyle(color: eu.textMid, fontSize: 11.5)),
                  ],
                ),
              ),
              if (streaming)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.8, color: eu.brand),
                )
              else
                Icon(Icons.chevron_right, size: 18, color: eu.textLo),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportSheet extends StatelessWidget {
  final String title;
  final String body;
  const _ReportSheet({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  const Text('📄', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: eu.textHi, fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: eu.textMid),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Text(body, style: TextStyle(color: eu.text, fontSize: 14, height: 1.55)),
              ),
            ),
          ],
        ),
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
        content: Text('「${s.title}」将被删除，其中产生的资产会保留。',
            style: TextStyle(color: eu.textMid)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: TextStyle(color: eu.textMid)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('删除',
                style: TextStyle(color: eu.accentRed, fontWeight: FontWeight.w600)),
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
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('删除失败')));
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
            Expanded(child: _list(eu)),
          ],
        ),
      ),
    );
  }

  Widget _list(EurekaColors eu) {
    if (_error != null) {
      return Center(child: Text('加载失败', style: TextStyle(color: eu.textMid)));
    }
    final ss = _sessions;
    if (ss == null) return const Center(child: CircularProgressIndicator());
    if (ss.isEmpty) {
      return Center(child: Text('暂无会话', style: TextStyle(color: eu.textMid)));
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
            title: Text(s.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: active ? eu.brand : eu.textHi, fontSize: 14)),
            subtitle: Text('${s.createdAt.month}月${s.createdAt.day}日',
                style: TextStyle(color: eu.textLo, fontSize: 11)),
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

/// Bottom-sheet asset picker for attaching context to a chat (web AssetPickerSheet).
class _AssetPicker extends StatefulWidget {
  final Set<String> excludeIds;
  const _AssetPicker({required this.excludeIds});

  @override
  State<_AssetPicker> createState() => _AssetPickerState();
}

class _PickerData {
  final List<AssetItem> assets;
  final Map<String, SkillMeta> skills; // skillName → icon/label(display_name)
  final Map<String, RenderSpec> specs; // skillName → render_spec
  _PickerData(this.assets, this.skills, this.specs);
}

class _AssetPickerState extends State<_AssetPicker> {
  final _api = ApiClient();
  late final Future<_PickerData> _future = _load();
  String _filter = '__all__'; // '__all__' or a skillName
  final Set<String> _selected = {}; // multi-select
  // Resolved title per asset id (so the confirm result carries readable labels).
  final Map<String, AssetItem> _byId = {};

  Future<_PickerData> _load() async {
    final r = await Future.wait([
      fetchAssets(_api),
      fetchSkills(_api),
      fetchRenderSpecs(_api),
    ]);
    return _PickerData(
      r[0] as List<AssetItem>,
      r[1] as Map<String, SkillMeta>,
      r[2] as Map<String, RenderSpec>,
    );
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    // Fixed height in the 1/2–2/3 screen range — does NOT shrink with item count.
    final h = MediaQuery.of(context).size.height * 0.62;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: h,
        child: FutureBuilder<_PickerData>(
          future: _future,
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snap.data;
            final all = (data?.assets ?? const <AssetItem>[])
                .where((a) => !widget.excludeIds.contains(a.id))
                .toList();
            final present = <String>[];
            for (final a in all) {
              if (!present.contains(a.skillName)) present.add(a.skillName);
            }
            String labelOf(String s) => data?.skills[s]?.label ?? s;
            final shown = _filter == '__all__'
                ? all
                : all.where((a) => a.skillName == _filter).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('添加资产',
                      style: TextStyle(color: eu.textHi, fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                if (present.length > 1)
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        _filterChip(eu, '全部', '__all__'),
                        for (final s in present) _filterChip(eu, labelOf(s), s),
                      ],
                    ),
                  ),
                Expanded(
                  child: shown.isEmpty
                      ? Center(child: Text('没有可添加的资产', style: TextStyle(color: eu.textMid)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                          itemCount: shown.length,
                          itemBuilder: (_, i) {
                            final a = shown[i];
                            final title = readableTitle(
                              a.payload,
                              data?.specs[a.skillName],
                              fallback: labelOf(a.skillName),
                            );
                            _byId[a.id] = a.copyWithTitle(title);
                            final icon = data?.skills[a.skillName]?.icon ?? '•';
                            final checked = _selected.contains(a.id);
                            return ListTile(
                              leading: Text(icon, style: const TextStyle(fontSize: 18)),
                              title: Text(title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: eu.textHi, fontSize: 14)),
                              subtitle: Text(labelOf(a.skillName),
                                  style: TextStyle(color: eu.textLo, fontSize: 11)),
                              trailing: Icon(
                                checked ? Icons.check_circle : Icons.radio_button_unchecked,
                                color: checked ? eu.brand : eu.textLo,
                                size: 22,
                              ),
                              onTap: () => setState(() {
                                if (checked) {
                                  _selected.remove(a.id);
                                } else {
                                  _selected.add(a.id);
                                }
                              }),
                            );
                          },
                        ),
                ),
                if (_selected.isNotEmpty) _selectedRow(eu),
                _confirmBar(eu),
              ],
            );
          },
        ),
      ),
    );
  }

  // Selected assets as removable chips — so the user can deselect without
  // hunting for the row in the list.
  Widget _selectedRow(EurekaColors eu) {
    return Container(
      height: 44,
      decoration: BoxDecoration(border: Border(top: BorderSide(color: eu.border))),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final id in _selected)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() => _selected.remove(id)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: eu.brand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: eu.brand.withValues(alpha: 0.30)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 120),
                        child: Text(_byId[id]?.title ?? '资产',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: eu.textHi, fontSize: 12)),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.close, size: 13, color: eu.textMid),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _confirmBar(EurekaColors eu) {
    final n = _selected.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: eu.border))),
      child: Row(
        children: [
          Expanded(
            child: Text(n == 0 ? '未选择' : '已选 $n 项',
                style: TextStyle(color: n == 0 ? eu.textLo : eu.textMid, fontSize: 13)),
          ),
          GestureDetector(
            onTap: n == 0
                ? null
                : () => Navigator.of(context).pop(
                      [for (final id in _selected) _byId[id]!],
                    ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              decoration: BoxDecoration(
                color: n == 0 ? eu.surface : eu.brand,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(n == 0 ? '添加' : '添加 $n 项',
                  style: TextStyle(
                      color: n == 0 ? eu.textLo : Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(EurekaColors eu, String label, String value) {
    final active = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: active ? eu.brand.withValues(alpha: 0.18) : eu.surfaceRaised,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: active ? eu.brand.withValues(alpha: 0.45) : eu.border),
          ),
          child: Text(label,
              style: TextStyle(
                  color: active ? eu.textHi : eu.textMid,
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500)),
        ),
      ),
    );
  }
}
