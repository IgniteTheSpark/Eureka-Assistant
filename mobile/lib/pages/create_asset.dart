import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data_revision.dart';
import '../render/skill_card.dart' show accentOf;
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';

/// Serialize a picked wall-clock [DateTime] as Beijing time (+08:00) — matching
/// the backend's `_LOCAL_TZ` and the agent's ISO convention. `dateOnly` fields
/// emit a bare `YYYY-MM-DD` (no time, no offset) so there is zero timezone
/// ambiguity. Fixes the "picked 6.4 → saved as 6.5" off-by-one that came from
/// `DateTime.toIso8601String()` on a local value (it drops the offset, so the
/// backend re-read it as UTC and shifted the day).
String isoBeijing(DateTime d, {bool dateOnly = false}) {
  String two(int n) => n.toString().padLeft(2, '0');
  final date = '${d.year}-${two(d.month)}-${two(d.day)}';
  if (dateOnly) return date;
  return '${date}T${two(d.hour)}:${two(d.minute)}:00+08:00';
}

/// A creatable skill (name + display + icon/accent + payload_schema), from
/// GET /api/skills. Drives the 快创 menu tiles + the schema-driven form.
class SkillDef {
  final String name;
  final String displayName;
  final String icon;
  final String accentColor;
  final Map<String, dynamic> schema;
  const SkillDef(this.name, this.displayName, this.icon, this.accentColor, this.schema);
}

Future<List<SkillDef>> fetchSkillDefs(ApiClient api) async {
  final res = await api.getJson('/api/skills');
  final skills = (res is Map ? res['skills'] : null) as List? ?? const [];
  final out = <SkillDef>[];
  for (final s in skills.whereType<Map>()) {
    final name = s['name'] as String?;
    if (name == null || name == 'qa' || name == 'external_ref') continue;
    final rs = (s['render_spec'] as Map?)?.cast<String, dynamic>() ?? const {};
    out.add(SkillDef(
      name,
      s['display_name'] as String? ?? name,
      rs['icon'] as String? ?? '•',
      rs['accent_color'] as String? ?? 'gray',
      (s['payload_schema'] as Map?)?.cast<String, dynamic>() ?? const {},
    ));
  }
  return out;
}

/// 快创 — bottom sheet of creatable types (事件 + every skill). Tapping a tile
/// pushes that type's create form. Mirrors the web CreateAssetMenu.
void showCreateMenu(BuildContext context) {
  final eu = context.eu;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: eu.surfaceRaised,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => const _CreateMenu(),
  );
}

class _CreateMenu extends StatefulWidget {
  const _CreateMenu();
  @override
  State<_CreateMenu> createState() => _CreateMenuState();
}

class _CreateMenuState extends State<_CreateMenu> {
  final _api = ApiClient();
  late final Future<List<SkillDef>> _future = fetchSkillDefs(_api);

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  void _open(Widget form) {
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => form));
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('创建',
                  style: TextStyle(color: eu.textHi, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              FutureBuilder<List<SkillDef>>(
                future: _future,
                builder: (ctx, snap) {
                  final tiles = <Widget>[
                    _tile(eu, '📅', '事件', 'purple', () => _open(const EventForm())),
                  ];
                  for (final s in snap.data ?? const <SkillDef>[]) {
                    tiles.add(_tile(eu, s.icon, s.displayName, s.accentColor,
                        () => _open(SkillCreateForm(skill: s))));
                  }
                  return Wrap(spacing: 10, runSpacing: 10, children: tiles);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(EurekaColors eu, String icon, String label, String accent, VoidCallback onTap) {
    final a = accentOf(accent, eu);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: (MediaQuery.of(context).size.width.clamp(0, 460) - 32 - 10) / 2,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: a.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: a.edge),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: eu.textHi, fontSize: 14, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }
}

/* ── Schema-driven skill create form ──────────────────────────────────────── */

class _Field {
  final String name;
  final String type; // string | number | datetime | date | array
  final bool required;
  final List<String>? enumValues;
  final dynamic defaultValue;
  const _Field(this.name, this.type, this.required, this.enumValues, this.defaultValue);
}

const _fieldLabels = <String, String>{
  'content': '内容', 'title': '标题', 'amount': '金额', 'category': '分类',
  'currency': '币种', 'merchant': '商家', 'description': '描述', 'due_date': '截止时间',
  'status': '状态', 'name': '名称', 'phone': '电话', 'company': '公司', 'date': '日期',
  'at': '时间', 'location': '地点', 'note': '备注', 'notes': '备注',
};
String _label(String k) => _fieldLabels[k] ?? k;

List<_Field> _parseSchema(Map<String, dynamic> schema) {
  final out = <_Field>[];
  schema.forEach((name, defRaw) {
    if (defRaw is! Map) return;
    final def = defRaw.cast<String, dynamic>();
    final type = (def['type'] as String?) ?? 'string';
    if (type == 'uuid') return; // system field
    out.add(_Field(
      name,
      type,
      def['required'] == true,
      (def['enum'] as List?)?.whereType<String>().toList(),
      def['default'],
    ));
  });
  out.sort((a, b) {
    if (a.required != b.required) return a.required ? -1 : 1;
    return a.name.compareTo(b.name);
  });
  return out;
}

class SkillCreateForm extends StatefulWidget {
  final SkillDef skill;
  const SkillCreateForm({super.key, required this.skill});

  @override
  State<SkillCreateForm> createState() => _SkillCreateFormState();
}

class _SkillCreateFormState extends State<SkillCreateForm> {
  final _api = ApiClient();
  late final List<_Field> _fields = _parseSchema(widget.skill.schema);
  final Map<String, dynamic> _values = {};
  final Map<String, TextEditingController> _ctrls = {};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final f in _fields) {
      if (f.defaultValue != null) _values[f.name] = f.defaultValue;
      if (f.type == 'string' || f.type == 'number' || f.type == 'array') {
        _ctrls[f.name] = TextEditingController(text: f.defaultValue?.toString() ?? '');
      }
    }
  }

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
    // Collect text values
    _ctrls.forEach((k, c) {
      if (c.text.trim().isNotEmpty) _values[k] = c.text.trim();
    });
    // Validate required
    for (final f in _fields) {
      if (f.required && (_values[f.name] == null || '${_values[f.name]}'.isEmpty)) {
        setState(() => _error = '请填写「${_label(f.name)}」');
        return;
      }
    }
    final payload = <String, dynamic>{};
    for (final f in _fields) {
      var v = _values[f.name];
      if (v == null || '$v'.isEmpty) continue;
      if (f.type == 'number') v = num.tryParse('$v') ?? v;
      if (f.type == 'array' && v is String) v = v.split(',').map((s) => s.trim()).toList();
      // datetime/date pickers hold a DateTime — serialize as Beijing time so
      // jsonEncode doesn't choke AND the day doesn't drift (see [isoBeijing]).
      if (v is DateTime) v = isoBeijing(v, dateOnly: f.type == 'date');
      payload[f.name] = v;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.skill.name == 'contact') {
        await _api.postJson('/api/contacts', payload);
      } else {
        await _api.postJson('/api/assets', {
          'user_skill_name': widget.skill.name,
          'payload': payload,
        });
      }
      bumpData();
      if (mounted) Navigator.of(context).maybePop();
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
        title: Text('${widget.skill.icon} ${widget.skill.displayName}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            for (final f in _fields) ...[
              _fieldInput(eu, f),
              const SizedBox(height: 14),
            ],
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: eu.accentRed, fontSize: 13)),
              const SizedBox(height: 12),
            ],
            _saveButton(eu),
          ],
        ),
      ),
    );
  }

  Widget _fieldInput(EurekaColors eu, _Field f) {
    final label = '${_label(f.name)}${f.required ? ' *' : ''}';
    final cap = Text(label, style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo));
    if (f.enumValues != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cap,
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _values[f.name] as String? ?? f.enumValues!.first,
            dropdownColor: eu.surfaceRaised,
            decoration: _dec(eu),
            items: [
              for (final v in f.enumValues!)
                DropdownMenuItem(value: v, child: Text(v, style: TextStyle(color: eu.textHi))),
            ],
            onChanged: (v) => _values[f.name] = v,
          ),
        ],
      );
    }
    if (f.type == 'datetime' || f.type == 'date') {
      final picked = _values[f.name] as DateTime?;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cap,
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => _pickDateTime(f),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: eu.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: eu.border),
              ),
              child: Text(
                picked == null
                    ? '选择${f.type == 'date' ? '日期' : '时间'}'
                    : _fmt(picked, f.type == 'datetime'),
                style: TextStyle(color: picked == null ? eu.textLo : eu.textHi, fontSize: 14),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cap,
        const SizedBox(height: 6),
        TextField(
          controller: _ctrls[f.name],
          keyboardType: f.type == 'number' ? TextInputType.number : TextInputType.text,
          style: TextStyle(color: eu.textHi, fontSize: 14),
          decoration: _dec(eu),
        ),
      ],
    );
  }

  Future<void> _pickDateTime(_Field f) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: (_values[f.name] as DateTime?) ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 3),
    );
    if (d == null) return;
    var result = d;
    if (f.type == 'datetime' && mounted) {
      final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
      if (t != null) result = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    }
    setState(() => _values[f.name] = result);
  }

  String _fmt(DateTime d, bool withTime) => withTime
      ? '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  InputDecoration _dec(EurekaColors eu) => InputDecoration(
        isDense: true,
        filled: true,
        fillColor: eu.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: eu.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: eu.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: eu.brand)),
      );

  Widget _saveButton(EurekaColors eu) => GestureDetector(
        onTap: _busy ? null : _save,
        behavior: HitTestBehavior.opaque,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(color: eu.brand, borderRadius: BorderRadius.circular(12)),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('保存',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      );
}

/* ── Event create form ────────────────────────────────────────────────────── */

class EventForm extends StatefulWidget {
  const EventForm({super.key});
  @override
  State<EventForm> createState() => _EventFormState();
}

class _EventFormState extends State<EventForm> {
  final _api = ApiClient();
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _desc = TextEditingController();
  DateTime _start = _roundToHour(DateTime.now().add(const Duration(hours: 1)));
  // An event needs a time span: either an end_at after start, or all_day=1.
  // The backend rejects a lone start (it would be a todo, not an event) — so
  // the form defaults to a 1h span and offers an 全天 toggle.
  late DateTime _end = _start.add(const Duration(hours: 1));
  bool _allDay = false;
  bool _busy = false;
  String? _error;

  static DateTime _roundToHour(DateTime d) => DateTime(d.year, d.month, d.day, d.hour);

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _desc.dispose();
    _api.close();
    super.dispose();
  }

  Future<void> _pick({required bool isStart}) async {
    final base = isStart ? _start : _end;
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(base.year - 2),
      lastDate: DateTime(base.year + 3),
    );
    if (d == null || !mounted) return;
    var picked = DateTime(d.year, d.month, d.day);
    if (!_allDay) {
      final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
      picked = DateTime(d.year, d.month, d.day, t?.hour ?? 0, t?.minute ?? 0);
    }
    setState(() {
      if (isStart) {
        _start = picked;
        // Keep end >= start (preserve the existing duration when possible).
        if (!_end.isAfter(_start)) _end = _start.add(const Duration(hours: 1));
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_title.text.trim().isEmpty) {
      setState(() => _error = '请填写标题');
      return;
    }
    if (!_allDay && !_end.isAfter(_start)) {
      setState(() => _error = '结束时间要晚于开始时间');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.postJson('/api/events', {
        'title': _title.text.trim(),
        'start_at': isoBeijing(_start, dateOnly: _allDay),
        if (!_allDay) 'end_at': isoBeijing(_end),
        'all_day': _allDay ? 1 : 0,
        'location': _location.text.trim(),
        'description': _desc.text.trim(),
      });
      bumpData();
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '保存失败：$e';
        });
      }
    }
  }

  String _fmt(DateTime d) => _allDay
      ? '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Widget _timeBox(EurekaColors eu, String text, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: eu.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: eu.border),
          ),
          child: Text(text, style: TextStyle(color: eu.textHi, fontSize: 14)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    InputDecoration dec(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: eu.textLo),
          isDense: true,
          filled: true,
          fillColor: eu.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: eu.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: eu.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: eu.brand)),
        );
    return Scaffold(
      backgroundColor: eu.bg,
      appBar: AppBar(
        backgroundColor: eu.bg,
        foregroundColor: eu.textHi,
        elevation: 0,
        title: const Text('📅 事件', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text('标题 *', style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo)),
            const SizedBox(height: 6),
            TextField(controller: _title, style: TextStyle(color: eu.textHi), decoration: dec('事件标题')),
            const SizedBox(height: 14),
            Row(
              children: [
                Text('全天', style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo)),
                const Spacer(),
                Switch(
                  value: _allDay,
                  activeThumbColor: eu.brand,
                  onChanged: (v) => setState(() => _allDay = v),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('开始时间', style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo)),
            const SizedBox(height: 6),
            _timeBox(eu, _fmt(_start), () => _pick(isStart: true)),
            if (!_allDay) ...[
              const SizedBox(height: 14),
              Text('结束时间', style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo)),
              const SizedBox(height: 6),
              _timeBox(eu, _fmt(_end), () => _pick(isStart: false)),
            ],
            const SizedBox(height: 14),
            Text('地点', style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo)),
            const SizedBox(height: 6),
            TextField(controller: _location, style: TextStyle(color: eu.textHi), decoration: dec('可选')),
            const SizedBox(height: 14),
            Text('描述', style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo)),
            const SizedBox(height: 6),
            TextField(
              controller: _desc,
              style: TextStyle(color: eu.textHi),
              decoration: dec('可选'),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 18),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: eu.accentRed, fontSize: 13)),
              const SizedBox(height: 12),
            ],
            GestureDetector(
              onTap: _busy ? null : _save,
              behavior: HitTestBehavior.opaque,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(color: eu.brand, borderRadius: BorderRadius.circular(12)),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('保存',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
