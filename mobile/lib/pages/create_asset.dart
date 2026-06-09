import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data_revision.dart';
import '../render/asset_detail_sheet.dart' show AssetEditPage, MdEditor;
import '../render/render_spec.dart' show RenderSpec;
import '../render/skill_card.dart' show accentOf;
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';

/// Build the field-rendering RenderSpec for a skill from its payload_schema
/// (schemaFields / types / long / required / labels). Lets 快创 reuse the same
/// [AssetEditPage] as 编辑 — create is edit with empty data. (The card preview
/// resolves its own full spec via the provider; this only drives the inputs.)
RenderSpec renderSpecForSkill(SkillDef s) => RenderSpec(
      cardLayout: 'horizontal',
      icon: s.icon,
      accentColor: s.accentColor,
    ).withSchema(s.schema);

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
void showCreateMenu(BuildContext context, {DateTime? presetDate}) {
  final eu = context.eu;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: eu.surfaceRaised,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _CreateMenu(presetDate: presetDate),
  );
}

class _CreateMenu extends StatefulWidget {
  /// When created from an empty calendar day, new date/time fields default to it.
  final DateTime? presetDate;
  const _CreateMenu({this.presetDate});
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
                    _tile(eu, '📅', '事件', 'purple',
                        () => _open(EventForm(presetDate: widget.presetDate))),
                  ];
                  for (final s in snap.data ?? const <SkillDef>[]) {
                    // contact is a 真身 entity → its dedicated form (socials /
                    // email / notes). Every other asset skill uses the SAME
                    // AssetEditPage as 编辑 (create = edit with empty data).
                    final onTap = s.name == 'contact'
                        ? () => _open(const ContactForm())
                        : () => _open(AssetEditPage(
                              payload: const {},
                              cardType: s.name,
                              title: '',
                              spec: renderSpecForSkill(s),
                              displayName: s.displayName,
                              presetDate: widget.presetDate,
                            ));
                    tiles.add(_tile(eu, s.icon, s.displayName, s.accentColor, onTap));
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

/* ── Event create form ────────────────────────────────────────────────────── */

class EventForm extends StatefulWidget {
  final DateTime? presetDate; // empty-day create → default the event to that day (09:00)
  final String? eventId; // non-null = EDIT mode (PUT instead of POST)
  final Map<String, dynamic>? existing; // event record to prefill in edit mode
  const EventForm({super.key, this.presetDate, this.eventId, this.existing});
  @override
  State<EventForm> createState() => _EventFormState();
}

class _EventFormState extends State<EventForm> {
  final _api = ApiClient();
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _desc = TextEditingController();
  late DateTime _start;
  // An event needs a time span: either an end_at after start, or all_day=1.
  late DateTime _end;
  bool _allDay = false;
  bool _busy = false;
  String? _error;
  bool get _isEdit => widget.eventId != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _title.text = '${e['title'] ?? ''}';
      _location.text = '${e['location'] ?? ''}';
      _desc.text = '${e['description'] ?? ''}';
      _allDay = e['all_day'] == 1 || e['all_day'] == true || e['all_day'] == '1';
      _start = _parseDt(e['start_at']) ?? _defaultStart();
      _end = _parseDt(e['end_at']) ?? _start.add(const Duration(hours: 1));
    } else {
      _start = _defaultStart();
      _end = _start.add(const Duration(hours: 1));
    }
  }

  DateTime _defaultStart() => widget.presetDate != null
      ? DateTime(widget.presetDate!.year, widget.presetDate!.month, widget.presetDate!.day, 9)
      : _roundToHour(DateTime.now().add(const Duration(hours: 1)));
  static DateTime? _parseDt(dynamic v) =>
      (v is String && v.isNotEmpty) ? DateTime.tryParse(v.replaceAll('Z', '+00:00'))?.toLocal() : null;
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
      final body = {
        'title': _title.text.trim(),
        'start_at': isoBeijing(_start, dateOnly: _allDay),
        if (!_allDay) 'end_at': isoBeijing(_end),
        'all_day': _allDay ? 1 : 0,
        'location': _location.text.trim(),
        'description': _desc.text.trim(),
      };
      if (_isEdit) {
        await _api.putJson('/api/events/${widget.eventId}', body);
      } else {
        await _api.postJson('/api/events', body);
      }
      bumpData();
      if (mounted) {
        Navigator.of(context).maybePop(_isEdit
            ? true
            : <String, dynamic>{
                'user_skill_name': 'event',
                'display_name': '事件',
                'icon': '📅',
                'payload': {'title': _title.text.trim()},
              });
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
        title: Text(_isEdit ? '📅 编辑事件' : '📅 事件',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
            // 描述 supports markdown (same editor as the asset editor) — events
            // often carry agendas / notes that want structure, not a flat field.
            MdEditor(label: '描述', controller: _desc),
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

/// 名片 supported social platforms — a FIXED set (user picks from here, never
/// free-form). key = stored platform key (synced with backend
/// core/contacts_meta.py / spec §4.5.3a); label = 中文/品牌名; emoji = leading mark.
/// Order: China-first.
const List<({String key, String label, String emoji})> kSocialPlatforms = [
  (key: 'wechat', label: '微信', emoji: '💬'),
  (key: 'xiaohongshu', label: '小红书', emoji: '📕'),
  (key: 'x', label: 'X', emoji: '𝕏'),
  (key: 'telegram', label: 'Telegram', emoji: '✈️'),
  (key: 'linkedin', label: 'LinkedIn', emoji: '💼'),
  (key: 'instagram', label: 'Instagram', emoji: '📷'),
];

({String key, String label, String emoji}) _socialMeta(String key) =>
    kSocialPlatforms.firstWhere((p) => p.key == key,
        orElse: () => (key: key, label: key, emoji: '🔗'));

/// Dedicated contact editor (and creator). EDIT mode when [contactId] is set
/// (PUT /api/contacts/{id}); otherwise POST /api/contacts. The contacts table
/// is the 真身 for contact data — this never routes through /api/assets.
class ContactForm extends StatefulWidget {
  final String? contactId; // non-null = EDIT mode
  final Map<String, dynamic>? existing; // contact record to prefill
  const ContactForm({super.key, this.contactId, this.existing});
  @override
  State<ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<ContactForm> {
  final _api = ApiClient();
  final _name = TextEditingController();
  final _company = TextEditingController();
  final _title = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _notes = TextEditingController(); // one annotation per line (→ md)
  // socials: platform key → handle controller, only for platforms currently shown
  // (insertion-ordered). Picked from kSocialPlatforms, never free-form.
  final Map<String, TextEditingController> _socials = {};
  bool _busy = false;
  String? _error;
  bool get _isEdit => widget.contactId != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = '${e['name'] ?? ''}';
      _company.text = '${e['company'] ?? ''}';
      _title.text = '${e['title'] ?? ''}';
      _phone.text = '${e['phone'] ?? ''}';
      _email.text = '${e['email'] ?? ''}';
      final n = e['notes'];
      if (n is List) {
        _notes.text = n.map((x) => '$x').join('\n');
      } else if (n is String) {
        _notes.text = n;
      }
      final s = e['socials'];
      if (s is Map) {
        // preserve kSocialPlatforms order for a stable layout
        for (final p in kSocialPlatforms) {
          final h = s[p.key];
          if (h != null && '$h'.trim().isNotEmpty) {
            _socials[p.key] = TextEditingController(text: '$h'.trim());
          }
        }
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _company, _title, _phone, _email, _notes, ..._socials.values]) {
      c.dispose();
    }
    _api.close();
    super.dispose();
  }

  /// Show the platforms not yet added → tap to add a row (focus it). This is the
  /// "select from supported list" gate — no free-form platforms.
  Future<void> _addSocial() async {
    final remaining = kSocialPlatforms.where((p) => !_socials.containsKey(p.key)).toList();
    if (remaining.isEmpty) return;
    final eu = context.eu;
    final key = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: eu.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('添加社交媒体',
                    style: euMono(fontSize: 11, letterSpacing: 1.2, color: eu.textLo)),
              ),
            ),
            for (final p in remaining)
              ListTile(
                leading: Text(p.emoji, style: const TextStyle(fontSize: 20)),
                title: Text(p.label, style: TextStyle(color: eu.textHi, fontWeight: FontWeight.w600)),
                onTap: () => Navigator.of(ctx).pop(p.key),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (key != null && mounted) {
      setState(() => _socials[key] = TextEditingController());
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '请填写姓名');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final notes =
        _notes.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final socials = <String, String>{};
    _socials.forEach((k, c) {
      final h = c.text.trim();
      if (h.isNotEmpty) socials[k] = h;
    });
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'company': _company.text.trim(),
      'title': _title.text.trim(),
      'phone': _phone.text.trim(),
      'email': _email.text.trim(),
      'notes': notes,
      'socials': socials, // full replace; supported-only enforced by backend
    };
    try {
      if (_isEdit) {
        await _api.putJson('/api/contacts/${widget.contactId}', body);
      } else {
        await _api.postJson('/api/contacts', body);
      }
      bumpData();
      if (mounted) {
        Navigator.of(context).maybePop(_isEdit
            ? true
            : <String, dynamic>{
                'user_skill_name': 'contact',
                'display_name': '联系人',
                'icon': '👤',
                'payload': {'name': _name.text.trim()},
              });
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
    Widget field(String label, TextEditingController c,
            {String hint = '可选', TextInputType? kb, int min = 1, int max = 1}) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo)),
            const SizedBox(height: 6),
            TextField(
              controller: c,
              style: TextStyle(color: eu.textHi),
              decoration: dec(hint),
              keyboardType: kb,
              minLines: min,
              maxLines: max,
            ),
            const SizedBox(height: 14),
          ],
        );
    Widget socialRow(String key) {
      final m = _socialMeta(key);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Text(m.emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            SizedBox(
              width: 72,
              child: Text(m.label,
                  style: TextStyle(color: eu.textHi, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: TextField(
                controller: _socials[key],
                style: TextStyle(color: eu.textHi),
                decoration: dec('账号 / 链接'),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 18, color: eu.textLo),
              onPressed: () {
                final c = _socials.remove(key);
                setState(() {});
                WidgetsBinding.instance.addPostFrameCallback((_) => c?.dispose());
              },
            ),
          ],
        ),
      );
    }

    final remainingSocials =
        kSocialPlatforms.where((p) => !_socials.containsKey(p.key)).toList();
    return Scaffold(
      backgroundColor: eu.bg,
      appBar: AppBar(
        backgroundColor: eu.bg,
        foregroundColor: eu.textHi,
        elevation: 0,
        title: Text(_isEdit ? '👤 编辑联系人' : '👤 联系人',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            field('姓名 *', _name, hint: '联系人姓名'),
            field('公司', _company),
            field('职位', _title),
            field('电话', _phone, kb: TextInputType.phone),
            field('邮箱', _email, kb: TextInputType.emailAddress),
            // 社交媒体 — pick from the supported list, store the handle only
            Text('社交媒体', style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.textLo)),
            const SizedBox(height: 8),
            for (final key in _socials.keys.toList()) socialRow(key),
            if (remainingSocials.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addSocial,
                  icon: Icon(Icons.add, size: 18, color: eu.brand),
                  label: Text('添加社交媒体', style: TextStyle(color: eu.brand, fontSize: 13)),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: const Size(0, 36)),
                ),
              ),
            const SizedBox(height: 14),
            field('备注', _notes, hint: '在哪相遇 / 怎么认识…一行一条', min: 3, max: 6),
            const SizedBox(height: 4),
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
