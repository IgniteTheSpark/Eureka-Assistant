import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data_revision.dart';
import '../render/render_spec.dart';
import '../render/skill_card.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';

/// 新技能 — describe a thing → the design agent clarifies (if vague) then drafts
/// {name, display_name, payload_schema, render_spec} → confirm to register it.
/// Bottom sheet, mirroring the web AddSkillWizard ("想记录点什么?" + suggestion
/// chips + AI 生成).
void showAddSkill(BuildContext context) {
  final eu = context.eu;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: eu.surfaceRaised,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => const _AddSkillSheet(),
  );
}

const _suggestions = ['跑步训练记录', '读书笔记', '每天喝水量', '面试复盘'];

class _AddSkillSheet extends StatefulWidget {
  const _AddSkillSheet();

  @override
  State<_AddSkillSheet> createState() => _AddSkillSheetState();
}

class _AddSkillSheetState extends State<_AddSkillSheet> {
  final _api = ApiClient();
  final _desc = TextEditingController();
  String _stage = 'describe'; // describe | questions | preview
  bool _busy = false;
  String? _error;

  List<Map<String, dynamic>> _questions = [];
  final Map<String, TextEditingController> _answers = {};
  Map<String, dynamic>? _draft;

  // Preview-stage slot model (§4.8): editable identity + per-field slot, all
  // feeding a live SkillCard preview and the render_spec sent on confirm.
  final _pIcon = TextEditingController();
  final _pName = TextEditingController();
  String _pAccent = 'blue';
  String _pLayout = 'horizontal';
  String? _pPrimary;
  String? _pSecondary;
  final List<String> _pInfo = [];
  final Map<String, String?> _pFormats = {};
  List<String> _pFields = [];
  Map<String, dynamic> _pSample = {};

  static const _accentOptions = [
    'blue', 'purple', 'amber', 'green', 'red', 'gray', 'neutral'
  ];

  @override
  void dispose() {
    _desc.dispose();
    _pIcon.dispose();
    _pName.dispose();
    for (final c in _answers.values) {
      c.dispose();
    }
    _api.close();
    super.dispose();
  }

  Future<void> _draftRequest(List<Map<String, String>>? answers) async {
    if (_desc.text.trim().isEmpty) {
      setState(() => _error = '先描述一下你想记录什么');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{'description': _desc.text.trim()};
      if (answers != null) body['answers'] = answers;
      final res = await _api.postJson('/api/skills', body);
      final m = (res as Map).cast<String, dynamic>();
      final draft = (m['draft'] as Map?)?.cast<String, dynamic>();
      if (draft != null) {
        _initPreview(draft);
        setState(() {
          _draft = draft;
          _stage = 'preview';
          _busy = false;
        });
        return;
      }
      final qs = (m['questions'] as List?)?.whereType<Map>().toList() ?? const [];
      if (qs.isNotEmpty) {
        _questions = qs.map((e) => e.cast<String, dynamic>()).toList();
        for (final q in _questions) {
          _answers.putIfAbsent(q['key'] as String? ?? '', () => TextEditingController());
        }
        setState(() {
          _stage = 'questions';
          _busy = false;
        });
      } else {
        setState(() {
          _busy = false;
          _error = '设计失败，换个描述再试';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '请求失败：$e';
        });
      }
    }
  }

  Future<void> _confirm() async {
    final d = _draft;
    if (d == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.postJson('/api/skills/confirm', {
        'name': d['name'],
        'display_name':
            _pName.text.trim().isEmpty ? d['display_name'] : _pName.text.trim(),
        'payload_schema': d['payload_schema'],
        'render_spec': _composeRenderSpec(),
      });
      bumpData();
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '创建失败：$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: ✨ tile + 新技能 · AI 设计 + close
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [eu.brand.withValues(alpha: 0.22), eu.accentPurple.withValues(alpha: 0.10)],
                        ),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: eu.brand.withValues(alpha: 0.32)),
                      ),
                      child: const Text('✨', style: TextStyle(fontSize: 18)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('新技能 · AI 设计',
                              style: euMono(fontSize: 10, letterSpacing: 1, color: eu.textLo)),
                          Text(_stageTitle(),
                              style: TextStyle(
                                  color: eu.textHi, fontSize: 18, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).maybePop(),
                      behavior: HitTestBehavior.opaque,
                      child: Icon(Icons.close, size: 20, color: eu.textMid),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_stage == 'describe') ..._describe(eu),
                if (_stage == 'questions') ..._questionsStage(eu),
                if (_stage == 'preview') ..._preview(eu),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: eu.accentRed, fontSize: 13)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _stageTitle() => switch (_stage) {
        'questions' => '再补充几点',
        'preview' => '确认技能',
        _ => '想记录点什么？',
      };

  List<Widget> _describe(EurekaColors eu) => [
        TextField(
          controller: _desc,
          minLines: 2,
          maxLines: 4,
          autofocus: true,
          style: TextStyle(color: eu.textHi, fontSize: 14, height: 1.4),
          decoration: _dec(eu, '用一句话描述你想记录的东西，例如「记录每次跑步的距离、配速和感受」…'),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in _suggestions)
              GestureDetector(
                onTap: () => setState(() => _desc.text = s),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: eu.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: eu.border),
                  ),
                  child: Text(s, style: TextStyle(color: eu.textMid, fontSize: 13)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text('AI 会自动设计字段、图标和卡片样式',
            style: TextStyle(color: eu.textLo, fontSize: 12)),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
              child: Text('取消', style: TextStyle(color: eu.textMid)),
            ),
            const SizedBox(width: 8),
            _gradientBtn(eu, _busy ? '设计中…' : '✨ AI 生成', _busy ? null : () => _draftRequest(null)),
          ],
        ),
      ];

  List<Widget> _questionsStage(EurekaColors eu) => [
        for (final q in _questions) ...[
          Text(q['prompt'] as String? ?? '', style: TextStyle(color: eu.textHi, fontSize: 14)),
          const SizedBox(height: 6),
          if ((q['options'] as List?)?.isNotEmpty ?? false)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final o in (q['options'] as List).whereType<String>())
                  GestureDetector(
                    onTap: () => setState(
                        () => _answers[q['key'] as String? ?? '']?.text = o),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: _answers[q['key']]?.text == o
                            ? eu.brand.withValues(alpha: 0.16)
                            : eu.surface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: _answers[q['key']]?.text == o ? eu.brand : eu.border),
                      ),
                      child: Text(o,
                          style: TextStyle(
                              color: _answers[q['key']]?.text == o ? eu.textHi : eu.textMid,
                              fontSize: 13)),
                    ),
                  ),
              ],
            )
          else
            TextField(
              controller: _answers[q['key'] as String? ?? ''],
              style: TextStyle(color: eu.textHi, fontSize: 14),
              decoration: _dec(eu, q['placeholder'] as String? ?? '可留空'),
            ),
          const SizedBox(height: 14),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _gradientBtn(eu, _busy ? '设计中…' : '✨ 生成技能', _busy ? null : () {
              final answers = _answers.entries
                  .map((e) => {'key': e.key, 'value': e.value.text.trim()})
                  .toList();
              _draftRequest(answers);
            }),
          ],
        ),
      ];

  /// Seed the slot model from the draft render_spec + payload_schema.
  void _initPreview(Map<String, dynamic> draft) {
    final rs = (draft['render_spec'] as Map?)?.cast<String, dynamic>() ?? const {};
    final schema = (draft['payload_schema'] as Map?)?.cast<String, dynamic>() ?? const {};
    _pLayout = rs['card_layout'] as String? ?? 'horizontal';
    _pIcon.text = rs['icon'] as String? ?? '•';
    _pName.text = draft['display_name'] as String? ?? draft['name'] as String? ?? '新技能';
    _pAccent = rs['accent_color'] as String? ?? 'blue';
    _pPrimary = rs['primary_field'] as String?;
    _pSecondary = rs['secondary_field'] as String?;
    final metas = ((rs['meta_fields'] as List?) ?? const []).whereType<Map>().toList();
    _pInfo
      ..clear()
      ..addAll(metas.map((m) => m['field'] as String? ?? '').where((s) => s.isNotEmpty));
    _pFormats.clear();
    if (_pPrimary != null) _pFormats[_pPrimary!] = rs['primary_format'] as String?;
    if (_pSecondary != null) _pFormats[_pSecondary!] = rs['secondary_format'] as String?;
    for (final m in metas) {
      final f = m['field'] as String?;
      if (f != null) _pFormats[f] = m['format'] as String?;
    }
    _pFields = schema.keys.where((k) => (schema[k] as Map?)?['type'] != 'uuid').toList();
    final sp = (draft['sample_payload'] as Map?)?.cast<String, dynamic>();
    _pSample = sp ??
        {
          for (final f in _pFields)
            f: _sampleFor(f, (schema[f] as Map?)?.cast<String, dynamic>() ?? const {}),
        };
  }

  dynamic _sampleFor(String field, Map<String, dynamic> spec) {
    final en = spec['enum'];
    if (en is List && en.isNotEmpty) return en.first;
    return switch (spec['type']) {
      'number' => 42,
      'datetime' || 'date' => DateTime.now().toIso8601String(),
      'boolean' => true,
      _ => '示例',
    };
  }

  String _slotOf(String f) {
    if (f == _pPrimary) return '主';
    if (f == _pSecondary) return '副';
    if (_pInfo.contains(f)) return '信息';
    return '隐藏';
  }

  // applySlotPick: primary/secondary are unique (re-assigning demotes the old
  // holder to 隐藏); 信息 caps at 3.
  void _applySlot(String f, String slot) {
    setState(() {
      if (_pPrimary == f) _pPrimary = null;
      if (_pSecondary == f) _pSecondary = null;
      _pInfo.remove(f);
      switch (slot) {
        case '主':
          _pPrimary = f;
        case '副':
          _pSecondary = f;
        case '信息':
          if (_pInfo.length < 3) _pInfo.add(f);
      }
    });
  }

  CardData _previewCard() {
    final spec = RenderSpec(
      cardLayout: _pLayout,
      icon: _pIcon.text.isEmpty ? '•' : _pIcon.text,
      accentColor: _pAccent,
      primaryField: _pPrimary,
      primaryFormat: _pFormats[_pPrimary],
      secondaryField: _pSecondary,
      secondaryFormat: _pFormats[_pSecondary],
      metaFields: [for (final f in _pInfo) MetaFieldSpec(f, _pFormats[f])],
    );
    return buildCard(
      payload: _pSample,
      spec: spec,
      displayName: _pName.text.isEmpty ? '新技能' : _pName.text,
    );
  }

  Map<String, dynamic> _composeRenderSpec() => {
        'card_layout': _pLayout,
        'icon': _pIcon.text.isEmpty ? '•' : _pIcon.text,
        'accent_color': _pAccent,
        if (_pPrimary != null) 'primary_field': _pPrimary,
        if (_pPrimary != null && _pFormats[_pPrimary] != null)
          'primary_format': _pFormats[_pPrimary],
        if (_pSecondary != null) 'secondary_field': _pSecondary,
        if (_pSecondary != null && _pFormats[_pSecondary] != null)
          'secondary_format': _pFormats[_pSecondary],
        'meta_fields': [
          for (final f in _pInfo)
            {'field': f, if (_pFormats[f] != null) 'format': _pFormats[f]},
        ],
      };

  List<Widget> _preview(EurekaColors eu) {
    return [
      // Live card preview — rebuilt from the slot model on every edit.
      Text('预览', style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo)),
      const SizedBox(height: 6),
      CardPreview(_previewCard()),
      const SizedBox(height: 16),
      // Identity: icon (≤2 chars) + display name.
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: TextField(
              controller: _pIcon,
              maxLength: 2,
              textAlign: TextAlign.center,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 20),
              decoration: _dec(eu, '✨').copyWith(counterText: ''),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _pName,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: eu.textHi, fontSize: 15, fontWeight: FontWeight.w600),
              decoration: _dec(eu, '技能名称'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Text('颜色', style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo)),
      const SizedBox(height: 8),
      Row(
        children: [
          for (final c in _accentOptions) _accentDot(eu, c),
        ],
      ),
      const SizedBox(height: 16),
      Text('字段', style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo)),
      const SizedBox(height: 8),
      for (final f in _pFields) _fieldRow(eu, f),
      const SizedBox(height: 20),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _busy ? null : () => setState(() => _stage = 'describe'),
            child: Text('重新描述', style: TextStyle(color: eu.textMid)),
          ),
          const SizedBox(width: 8),
          _gradientBtn(eu, _busy ? '创建中…' : '创建技能', _busy ? null : _confirm),
        ],
      ),
    ];
  }

  Widget _accentDot(EurekaColors eu, String name) {
    final color = accentOf(name, eu).fg;
    final sel = _pAccent == name;
    return GestureDetector(
      onTap: () => setState(() => _pAccent = name),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 30,
        height: 30,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          shape: BoxShape.circle,
          border: Border.all(color: sel ? color : eu.border, width: sel ? 2 : 1),
        ),
        child: Center(
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        ),
      ),
    );
  }

  Widget _fieldRow(EurekaColors eu, String f) {
    const slots = ['主', '副', '信息', '隐藏'];
    final current = _slotOf(f);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(f,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: eu.text, fontSize: 13)),
          ),
          for (final s in slots) _slotChip(eu, f, s, current),
        ],
      ),
    );
  }

  Widget _slotChip(EurekaColors eu, String f, String slot, String current) {
    final sel = slot == current;
    // 信息 disabled once 3 are taken (unless this field already holds it).
    final disabled = slot == '信息' && !sel && _pInfo.length >= 3;
    return GestureDetector(
      onTap: disabled ? null : () => _applySlot(f, slot),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(left: 5),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: sel ? eu.brand.withValues(alpha: 0.16) : eu.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: sel ? eu.brand : eu.border),
        ),
        child: Text(slot,
            style: TextStyle(
                color: disabled
                    ? eu.textLo.withValues(alpha: 0.4)
                    : sel
                        ? eu.textHi
                        : eu.textMid,
                fontSize: 12,
                fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
      ),
    );
  }

  InputDecoration _dec(EurekaColors eu, String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: eu.textLo, height: 1.4),
        filled: true,
        fillColor: eu.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: eu.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: eu.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: eu.brand)),
      );

  Widget _gradientBtn(EurekaColors eu, String label, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [eu.brand, eu.accentPurple]),
            borderRadius: BorderRadius.circular(12),
            boxShadow: onTap == null
                ? null
                : [BoxShadow(color: eu.brand.withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 4))],
          ),
          child: Opacity(
            opacity: onTap == null ? 0.6 : 1,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(label,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ),
      );
}
