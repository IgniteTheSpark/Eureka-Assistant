import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data_revision.dart';
import '../pages/chat_page.dart';
import '../pages/session_detail_page.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';
import 'render_spec.dart';
import 'skill_card.dart' show accentOf;

/// Asset detail sheet — the Flutter mirror of the web AssetDetailDrawer: hero +
/// 编辑/删除 actions + 来源 (source session) + payload fields. Opened by tapping
/// any [SkillCard].
void showAssetDetail(
  BuildContext context, {
  required CardData data,
  required Map<String, dynamic> payload,
  required String cardType,
  String? assetId,
  String? sessionId,
  RenderSpec? spec,
}) {
  final eu = context.eu;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: eu.surfaceRaised,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _AssetDetail(
      data: data,
      payload: payload,
      cardType: cardType,
      assetId: assetId,
      sessionId: sessionId,
      spec: spec,
    ),
  );
}

class _AssetDetail extends StatefulWidget {
  final CardData data;
  final Map<String, dynamic> payload;
  final String cardType;
  final String? assetId;
  final String? sessionId;
  final RenderSpec? spec;
  const _AssetDetail({
    required this.data,
    required this.payload,
    required this.cardType,
    required this.assetId,
    required this.sessionId,
    this.spec,
  });

  @override
  State<_AssetDetail> createState() => _AssetDetailState();
}

class _AssetDetailState extends State<_AssetDetail> {
  final _api = ApiClient();
  bool _confirmDel = false;
  bool _busy = false;

  CardData get data => widget.data;
  Map<String, dynamic> get payload => widget.payload;
  String get cardType => widget.cardType;

  bool get _deletable => widget.assetId != null;
  // Events/contacts PUT flat fields; assets PUT a payload_patch — the editor
  // branches on cardType.
  bool get _editable => widget.assetId != null;

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  String _deletePath() {
    final id = widget.assetId;
    switch (cardType) {
      case 'event':
        return '/api/events/$id';
      case 'contact':
        return '/api/contacts/$id';
      default:
        return '/api/assets/$id';
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _api.deleteJson(_deletePath());
      bumpData();
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _confirmDel = false;
        });
      }
    }
  }

  void _openSource() {
    final sid = widget.sessionId;
    if (sid == null || sid.isEmpty) return;
    Navigator.of(context).maybePop();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SessionDetailPage(sessionId: sid, title: '来源会话'),
    ));
  }

  String _subjectType() {
    switch (cardType) {
      case 'event':
        return 'event';
      case 'contact':
        return 'contact';
      default:
        return 'asset';
    }
  }

  // 讨论 — open a chat bound to this asset. The session is bound *lazily*: we
  // pass the subject to ChatPage and let it peek/create only on first send, so
  // tapping 讨论 and backing out never leaves an empty session.
  void _discuss() {
    final id = widget.assetId;
    if (id == null) return;
    Navigator.of(context).maybePop();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatPage(
        subjectType: _subjectType(),
        subjectId: id,
        subjectLabel: data.title,
      ),
    ));
  }

  Future<void> _edit() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: context.eu.surfaceRaised,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _EditAssetSheet(
        assetId: widget.assetId!,
        payload: payload,
        cardType: cardType,
        spec: widget.spec,
      ),
    );
    if (changed == true && mounted) {
      bumpData();
      Navigator.of(context).maybePop(); // close detail; list refreshes via revision
    }
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final a = accentOf(data.accentColor, eu);
    final fields = <Widget>[];
    for (final e in payload.entries) {
      if (_skip(e.key, e.value)) continue;
      if (cardType == 'contact' &&
          (e.key == 'name' || e.key == 'company' || e.key == 'title')) {
        continue;
      }
      fields.add(_field(eu, e.key, e.value));
    }

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(cardType.toUpperCase(),
                      style: euMono(fontSize: 10.5, letterSpacing: 1.6, color: eu.textLo)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    behavior: HitTestBehavior.opaque,
                    child: Icon(Icons.close, size: 20, color: eu.textMid),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [a.bg, Colors.transparent]),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: a.edge),
                ),
                child: Text(data.icon, style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(height: 14),
              Text(data.title,
                  style: TextStyle(
                      color: eu.textHi, fontSize: 22, height: 1.25, fontWeight: FontWeight.w700)),
              if (data.subtitle.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(data.subtitle, style: TextStyle(color: eu.textMid, fontSize: 14)),
              ],
              if (widget.assetId != null) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    _actionBtn(eu, Icons.auto_awesome, '讨论', eu.brand, _busy ? null : _discuss),
                    const SizedBox(width: 8),
                    if (_editable) ...[
                      _actionBtn(eu, Icons.edit_outlined, '编辑', eu.textMid, _busy ? null : _edit),
                      const SizedBox(width: 8),
                    ],
                    if (_deletable)
                      _actionBtn(
                        eu,
                        Icons.delete_outline,
                        _confirmDel ? '确认删除' : '删除',
                        eu.accentRed,
                        _busy
                            ? null
                            : () => _confirmDel ? _delete() : setState(() => _confirmDel = true),
                        filled: _confirmDel,
                      ),
                  ],
                ),
              ],
              _sourceSection(eu),
              if (fields.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(height: 1, color: eu.rule),
                const SizedBox(height: 14),
                ...fields,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionBtn(
      EurekaColors eu, IconData icon, String label, Color color, VoidCallback? onTap,
      {bool filled = false}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: filled ? color.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: filled ? color.withValues(alpha: 0.4) : eu.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(color: color, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _sourceSection(EurekaColors eu) {
    final hasSession = widget.sessionId != null && widget.sessionId!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('来源 · SOURCE',
              style: euMono(fontSize: 9.5, letterSpacing: 1.6, color: eu.textLo)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: hasSession ? _openSource : null,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: hasSession ? eu.accentBlue.withValues(alpha: 0.10) : eu.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: hasSession ? eu.accentBlue.withValues(alpha: 0.28) : eu.border),
              ),
              child: Row(
                children: [
                  Text(hasSession ? '⚡' : '✎', style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hasSession ? '由对话/闪念创建 · 点开看原始记录' : '手动创建',
                      style: TextStyle(
                          color: hasSession ? eu.textHi : eu.textMid, fontSize: 13),
                    ),
                  ),
                  if (hasSession) Icon(Icons.history, size: 15, color: eu.textMid),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(EurekaColors eu, String key, dynamic value) {
    // Label: the skill's own field label wins; else a universal fallback.
    final label = widget.spec?.fieldLabels[key] ?? _label(key, cardType);
    if (value is List) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final it in value)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: eu.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: eu.border),
                    ),
                    child: Text(_listEntry(it), style: TextStyle(color: eu.text, fontSize: 13)),
                  ),
              ],
            ),
          ],
        ),
      );
    }
    // Format: the skill's render_spec is authoritative (expense declares
    // `amount` as currency there); else value-based inference (no money guess).
    final shown = applyFormat(value, widget.spec?.formatForField(key) ?? _inferFormat(key, value));
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo)),
          const SizedBox(height: 4),
          Text(shown.isEmpty ? '$value' : shown,
              style: TextStyle(color: eu.text, fontSize: 14, height: 1.4)),
        ],
      ),
    );
  }

  String _listEntry(dynamic it) {
    if (it == null) return '—';
    if (it is String || it is num) return '$it';
    if (it is Map) {
      final name = it['name'] ?? it['title'] ?? it['display_name'];
      final role = it['role'];
      if (name != null && role != null) return '$name ($role)';
      if (name != null) return '$name';
    }
    return '$it';
  }
}

/// Generic asset editor — edit visible payload string/number fields and PUT a
/// payload_patch. Covers asset-skill cards (todo/notes/idea/expense/…); entity
/// types (event/contact) keep web's dedicated forms (not yet ported).
class _EditAssetSheet extends StatefulWidget {
  final String assetId;
  final Map<String, dynamic> payload;
  final String cardType;
  final RenderSpec? spec;
  const _EditAssetSheet({
    required this.assetId,
    required this.payload,
    required this.cardType,
    this.spec,
  });

  @override
  State<_EditAssetSheet> createState() => _EditAssetSheetState();
}

class _EditAssetSheetState extends State<_EditAssetSheet> {
  final _api = ApiClient();
  late final Map<String, TextEditingController> _ctrls = {
    for (final e in widget.payload.entries)
      if (!_skip(e.key, e.value) && e.value is! List && e.value is! Map)
        e.key: TextEditingController(text: '${e.value}'),
  };
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _api.close();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final patch = <String, dynamic>{};
    _ctrls.forEach((k, c) {
      final orig = '${widget.payload[k]}';
      if (c.text != orig) patch[k] = c.text;
    });
    try {
      if (patch.isNotEmpty) {
        switch (widget.cardType) {
          case 'event':
            await _api.putJson('/api/events/${widget.assetId}', patch);
          case 'contact':
            await _api.putJson('/api/contacts/${widget.assetId}', patch);
          default:
            await _api.putJson('/api/assets/${widget.assetId}', {'payload_patch': patch});
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('编辑',
                  style: TextStyle(color: eu.textHi, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              for (final e in _ctrls.entries) ...[
                Text(widget.spec?.fieldLabels[e.key] ?? _label(e.key, widget.cardType),
                    style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo)),
                const SizedBox(height: 4),
                TextField(
                  controller: e.value,
                  style: TextStyle(color: eu.textHi, fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: eu.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: eu.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: eu.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: eu.brand),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: _busy ? null : _save,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: eu.brand,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('保存',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ── field labels / skip / format (ported from web AssetDetailDrawer) ──────── */

const _fieldLabels = <String, String>{
  'title': '标题', 'subtitle': '摘要', 'content': '内容', 'note': '备注', 'notes': '备注',
  'description': '描述', 'summary': '摘要', 'body': '正文', 'markdown': '正文',
  'due_date': '截止时间', 'date': '日期', 'time': '时间', 'start_at': '开始', 'end_at': '结束',
  'amount': '金额', 'price': '价格', 'currency': '币种', 'category': '分类',
  'location': '地点', 'distance': '距离', 'duration': '时长', 'pace': '配速', 'mood': '心情',
  'name': '名称', 'company': '公司', 'phone': '电话', 'email': '邮箱',
  'reps': '次数', 'weight': '重量', 'pages_read': '阅读页数',
};

String _label(String key, String cardType) {
  // `amount`/`price` are money only for the expense skill. Elsewhere (e.g. a
  // custom water-intake skill whose volume field is named `amount`) treat them
  // as a generic quantity, not 金额.
  if (key == 'amount') return cardType == 'expense' ? '金额' : '数量';
  if (key == 'price') return cardType == 'expense' ? '价格' : '数量';
  return _fieldLabels[key] ?? key;
}

const _skipKeys = <String>{
  'ok', 'contact_action', 'when', 'card_type', 'kind', 'skill_name',
  'user_skill_name', 'user_id', 'all_day', 'status', 'task_id', 'external_id',
  'external_url', 'external_system', 'external_type', 'event_id', 'asset_id',
  'id', 'contact_id', 'file_id', 'source_input_turn_id', 'session_id',
  'sync_source', 'sync_external_id', 'recurrence_rule', 'updated_at',
  'user_skill_id', 'logId', 'trace_id',
  'icon', 'accent_color', 'accentColor', 'actions', 'card_layout', 'layout',
  'cardType', 'checkDone', 'primary_field', 'primary_format', 'secondary_field',
  'secondary_format', 'meta_fields', 'metaFields', 'timeline_position',
  'calendar_render', 'created_at',
};

bool _skip(String key, dynamic value) {
  if (_skipKeys.contains(key)) return true;
  if (value == null) return true;
  if (value is String && value.isEmpty) return true;
  if (value is List && value.isEmpty) return true;
  if (value is Map && value.isEmpty) return true;
  return false;
}

final _isoDt = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}');

// Value-based fallback format inference — only for fields the skill's render_spec
// doesn't already format. Strictly date heuristics (universally safe); never
// money — currency comes from a skill's own render_spec (expense), not field name.
String? _inferFormat(String key, dynamic value) {
  if (value is! String) return null;
  if (key == 'due_date') return 'relative_date';
  if (key.endsWith('_date') || key.endsWith('_at')) return 'absolute_date';
  if (key == 'date' || key == 'time') return 'absolute_date';
  if (_isoDt.hasMatch(value)) return 'absolute_date';
  return null;
}
