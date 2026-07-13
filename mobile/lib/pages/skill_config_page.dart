import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../data_revision.dart';
import '../render/render_spec.dart';
import '../render/skill_card.dart' show CardPreview, renderSpecsProvider;
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/toast.dart';

/// Reusable skill render-config editor — the same controls the add-skill wizard's
/// confirm step uses: a **live card preview** + icon + 显示名 + per
/// field **主 / 副 / 信息 / 隐藏** role assignment. Composes a `render_spec` from the
/// slot model; the host reads it via the form's [GlobalKey].
class SkillConfigForm extends StatefulWidget {
  final Map<String, dynamic> renderSpec; // current spec to seed from
  final Map<String, dynamic> payloadSchema; // field keys + types + labels
  final String displayName;
  const SkillConfigForm({
    super.key,
    required this.renderSpec,
    required this.payloadSchema,
    required this.displayName,
  });

  @override
  State<SkillConfigForm> createState() => SkillConfigFormState();
}

class SkillConfigFormState extends State<SkillConfigForm> {
  final _icon = TextEditingController();
  final _name = TextEditingController();
  String _accent = 'neutral';
  String _layout = 'horizontal';
  String? _primary;
  String? _secondary;
  final List<String> _info = [];
  final Map<String, String?> _formats = {};
  List<String> _fields = [];
  Map<String, dynamic> _sample = {};

  String get displayNameText =>
      _name.text.trim().isEmpty ? widget.displayName : _name.text.trim();

  @override
  void initState() {
    super.initState();
    final rs = widget.renderSpec;
    final schema = widget.payloadSchema;
    _layout = rs['card_layout'] as String? ?? 'horizontal';
    _icon.text = rs['icon'] as String? ?? '•';
    _name.text = widget.displayName;
    _accent = 'neutral';
    _primary = rs['primary_field'] as String?;
    _secondary = rs['secondary_field'] as String?;
    final metas = ((rs['meta_fields'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    _info
      ..clear()
      ..addAll(
        metas
            .map((m) => m['field'] as String? ?? '')
            .where((s) => s.isNotEmpty),
      );
    if (_primary != null) {
      _formats[_primary!] = rs['primary_format'] as String?;
    }
    if (_secondary != null) {
      _formats[_secondary!] = rs['secondary_format'] as String?;
    }
    for (final m in metas) {
      final f = m['field'] as String?;
      if (f != null) _formats[f] = m['format'] as String?;
    }
    _fields = schema.keys
        .cast<String>()
        .where((k) => (schema[k] as Map?)?['type'] != 'uuid')
        .toList();
    _sample = {
      for (final f in _fields)
        f: _sampleFor(
          f,
          (schema[f] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
    };
  }

  @override
  void dispose() {
    _icon.dispose();
    _name.dispose();
    super.dispose();
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

  String? _labelOf(String f) {
    final meta = widget.payloadSchema[f];
    if (meta is Map) {
      final l = (meta['label'] as String?)?.trim();
      if (l != null && l.isNotEmpty && l != f) return l;
    }
    return null;
  }

  String _slotOf(String f) {
    if (f == _primary) return '主';
    if (f == _secondary) return '副';
    if (_info.contains(f)) return '信息';
    return '隐藏';
  }

  void _applySlot(String f, String slot) {
    setState(() {
      if (_primary == f) _primary = null;
      if (_secondary == f) _secondary = null;
      _info.remove(f);
      switch (slot) {
        case '主':
          _primary = f;
        case '副':
          _secondary = f;
        case '信息':
          if (_info.length < 3) _info.add(f);
      }
    });
  }

  CardData _previewCard() {
    final spec = RenderSpec(
      cardLayout: _layout,
      icon: _icon.text.isEmpty ? '•' : _icon.text,
      accentColor: _accent,
      primaryField: _primary,
      primaryFormat: _formats[_primary],
      secondaryField: _secondary,
      secondaryFormat: _formats[_secondary],
      metaFields: [for (final f in _info) MetaFieldSpec(f, _formats[f])],
    );
    return buildCard(
      payload: _sample,
      spec: spec,
      displayName: displayNameText,
    );
  }

  /// The composed render_spec to PUT. Preserves `actions` (check/edit/…) from the
  /// original — the role UI only edits presentation slots.
  Map<String, dynamic> composeRenderSpec() => {
    'card_layout': _layout,
    'icon': _icon.text.isEmpty ? '•' : _icon.text,
    'accent_color': _accent,
    if (_primary != null) 'primary_field': _primary,
    if (_primary != null && _formats[_primary] != null)
      'primary_format': _formats[_primary],
    if (_secondary != null) 'secondary_field': _secondary,
    if (_secondary != null && _formats[_secondary] != null)
      'secondary_format': _formats[_secondary],
    'meta_fields': [
      for (final f in _info)
        {'field': f, if (_formats[f] != null) 'format': _formats[f]},
    ],
    if (widget.renderSpec['actions'] != null)
      'actions': widget.renderSpec['actions'],
  };

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '预览',
          style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo),
        ),
        const SizedBox(height: 6),
        CardPreview(_previewCard()),
        const SizedBox(height: 18),
        Text(
          '图标 · 名称',
          style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 56,
              child: TextField(
                controller: _icon,
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
                controller: _name,
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                  color: eu.textHi,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                decoration: _dec(eu, '显示名称'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          '字段位置',
          style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo),
        ),
        const SizedBox(height: 4),
        Text(
          '主 = 标题 · 副 = 副标题 · 信息 = meta(≤3) · 隐藏 = 不展示',
          style: TextStyle(color: eu.textLo, fontSize: 11),
        ),
        const SizedBox(height: 10),
        for (final f in _fields) _fieldRow(eu, f),
      ],
    );
  }

  Widget _fieldRow(EurekaColors eu, String f) {
    const slots = ['主', '副', '信息', '隐藏'];
    final current = _slotOf(f);
    final label = _labelOf(f);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label ?? f,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: eu.text,
                    fontSize: 13,
                    fontWeight: label != null
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
                if (label != null)
                  Text(
                    f,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: eu.textLo,
                      fontSize: 10.5,
                      letterSpacing: 0.2,
                    ),
                  ),
              ],
            ),
          ),
          for (final s in slots) _slotChip(eu, f, s, current),
        ],
      ),
    );
  }

  Widget _slotChip(EurekaColors eu, String f, String slot, String current) {
    final sel = slot == current;
    final disabled = slot == '信息' && !sel && _info.length >= 3;
    return GestureDetector(
      onTap: disabled ? null : () => _applySlot(f, slot),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(left: 5),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: sel ? eu.brand.withValues(alpha: 0.10) : eu.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: sel ? eu.brand.withValues(alpha: 0.45) : eu.border,
          ),
        ),
        child: Text(
          slot,
          style: TextStyle(
            color: disabled
                ? eu.textLo.withValues(alpha: 0.4)
                : sel
                ? eu.textHi
                : eu.textMid,
            fontSize: 12,
            fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(EurekaColors eu, String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: eu.textLo),
    filled: true,
    fillColor: eu.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: eu.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: eu.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: eu.brand),
    ),
  );
}

/// Per-skill config editor screen — opened from a skill's category page. Loads
/// the skill's current render_spec + payload_schema, hosts a [SkillConfigForm],
/// and PATCHes `/api/skills/{id}` on save (then refreshes the card registry so
/// every card re-renders with the new icon / color / field layout).
class SkillConfigPage extends ConsumerStatefulWidget {
  final String skillName;
  final String userSkillId;
  final String label;
  const SkillConfigPage({
    super.key,
    required this.skillName,
    required this.userSkillId,
    required this.label,
  });

  @override
  ConsumerState<SkillConfigPage> createState() => _SkillConfigPageState();
}

class _SkillConfigPageState extends ConsumerState<SkillConfigPage> {
  final _api = ApiClient();
  final _formKey = GlobalKey<SkillConfigFormState>();
  Map<String, dynamic>? _skill;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await _api.getJson('/api/skills');
      final skills = (res is Map ? res['skills'] : null) as List? ?? const [];
      final s = skills.whereType<Map>().firstWhere(
        (e) => e['name'] == widget.skillName,
        orElse: () => const {},
      );
      if (mounted) {
        setState(() {
          _skill = s.isEmpty ? null : s.cast<String, dynamic>();
          _loading = false;
          if (_skill == null) _error = '技能不存在';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '加载失败：$e';
        });
      }
    }
  }

  Future<void> _save() async {
    final fs = _formKey.currentState;
    if (fs == null || _busy) return;
    setState(() => _busy = true);
    try {
      await _api.patchJson('/api/skills/${widget.userSkillId}', {
        'render_spec': fs.composeRenderSpec(),
        'display_name': fs.displayNameText,
      });
      ref.invalidate(
        renderSpecsProvider,
      ); // cards re-render with the new config
      bumpData();
      if (mounted) {
        showToast(context, '已保存');
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '保存失败：$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Scaffold(
      backgroundColor: eu.bg,
      appBar: AppBar(
        backgroundColor: eu.bg,
        foregroundColor: eu.textHi,
        elevation: 0,
        title: Text(
          '卡片配置 · ${widget.label}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_skill != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        '保存',
                        style: TextStyle(
                          color: eu.brand,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const USkeletonList(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
              count: 6,
              cardHeight: 76,
              leading: false,
            )
          : _skill == null
          ? Center(
              child: Text(
                _error ?? '技能不存在',
                style: TextStyle(color: eu.textMid),
              ),
            )
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkillConfigForm(
                      key: _formKey,
                      renderSpec:
                          (_skill!['render_spec'] as Map?)
                              ?.cast<String, dynamic>() ??
                          const {},
                      payloadSchema:
                          (_skill!['payload_schema'] as Map?)
                              ?.cast<String, dynamic>() ??
                          const {},
                      displayName:
                          _skill!['display_name'] as String? ?? widget.label,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(color: eu.accentRed, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
