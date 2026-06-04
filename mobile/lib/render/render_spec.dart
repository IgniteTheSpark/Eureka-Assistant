import '../api/api_client.dart';

/// Mirror of UserSkill.render_spec (subset the cards use). Ported from the web
/// lib/render-spec.ts.
class RenderSpec {
  final String cardLayout; // horizontal | stacked | inline | compact
  final String icon;
  final String accentColor; // blue|amber|green|red|purple|gray|neutral
  final String? primaryField;
  final String? primaryFormat;
  final String? secondaryField;
  final String? secondaryFormat;
  final List<MetaFieldSpec> metaFields;
  final List<String> actions;

  /// Per-field display labels from the skill's `payload_schema` (field → label).
  /// The skill author (design agent / seed) defines these, so the detail sheet
  /// labels custom fields correctly instead of guessing from the field name.
  final Map<String, String> fieldLabels;

  const RenderSpec({
    required this.cardLayout,
    required this.icon,
    required this.accentColor,
    this.primaryField,
    this.primaryFormat,
    this.secondaryField,
    this.secondaryFormat,
    this.metaFields = const [],
    this.actions = const [],
    this.fieldLabels = const {},
  });

  /// The format this skill declares for [field] (primary / secondary / meta), or
  /// null. This is the *authoritative* format source — e.g. expense declares
  /// `amount` as `currency` here, so no field-name money-guessing is needed.
  String? formatForField(String field) {
    if (field == primaryField) return primaryFormat;
    if (field == secondaryField) return secondaryFormat;
    for (final m in metaFields) {
      if (m.field == field) return m.format;
    }
    return null;
  }

  RenderSpec withFieldLabels(Map<String, String> labels) => RenderSpec(
        cardLayout: cardLayout,
        icon: icon,
        accentColor: accentColor,
        primaryField: primaryField,
        primaryFormat: primaryFormat,
        secondaryField: secondaryField,
        secondaryFormat: secondaryFormat,
        metaFields: metaFields,
        actions: actions,
        fieldLabels: labels,
      );

  factory RenderSpec.fromJson(Map<String, dynamic> j) => RenderSpec(
        cardLayout: j['card_layout'] as String? ?? 'horizontal',
        icon: j['icon'] as String? ?? '•',
        accentColor: j['accent_color'] as String? ?? 'gray',
        primaryField: j['primary_field'] as String?,
        primaryFormat: j['primary_format'] as String?,
        secondaryField: j['secondary_field'] as String?,
        secondaryFormat: j['secondary_format'] as String?,
        metaFields: ((j['meta_fields'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => MetaFieldSpec(
                m['field'] as String? ?? '', m['format'] as String?))
            .toList(),
        actions:
            ((j['actions'] as List?) ?? const []).whereType<String>().toList(),
      );
}

class MetaFieldSpec {
  final String field;
  final String? format;
  const MetaFieldSpec(this.field, this.format);
}

/// Normalized card props the SkillCard renders (from a payload + spec).
class CardData {
  final String layout;
  final String icon;
  final String accentColor;
  final String title;
  final String subtitle;
  final List<({String value, String? format})> metaFields;
  final bool? checkDone;

  const CardData({
    required this.layout,
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.subtitle,
    required this.metaFields,
    this.checkDone,
  });

  CardData copyWith({String? layout, bool? checkDone}) => CardData(
        layout: layout ?? this.layout,
        icon: icon,
        accentColor: accentColor,
        title: title,
        subtitle: subtitle,
        metaFields: metaFields,
        checkDone: checkDone ?? this.checkDone,
      );
}

/// Build CardData from a payload + render_spec (mirrors web buildCard).
CardData buildCard({
  required Map<String, dynamic> payload,
  required RenderSpec? spec,
  required String displayName,
}) {
  if (spec == null) {
    return CardData(
      layout: 'horizontal',
      icon: '•',
      accentColor: 'gray',
      title: displayName,
      subtitle: '',
      metaFields: const [],
    );
  }
  final primary =
      spec.primaryField != null ? applyFormat(payload[spec.primaryField], spec.primaryFormat) : '';
  final secondary = spec.secondaryField != null
      ? applyFormat(payload[spec.secondaryField], spec.secondaryFormat)
      : '';
  final meta = <({String value, String? format})>[];
  for (final mf in spec.metaFields) {
    final v = applyFormat(payload[mf.field], mf.format);
    if (v.isNotEmpty) meta.add((value: v, format: mf.format));
  }
  // Checkable skills (todo) always carry a bool checkDone so the card shows a
  // toggleable checkbox even before a status is set.
  bool? checkDone;
  if (spec.actions.contains('check')) {
    checkDone = payload['status'] == 'done' || payload['done'] == true;
  }
  return CardData(
    layout: spec.cardLayout,
    icon: spec.icon,
    accentColor: spec.accentColor,
    title: primary.isNotEmpty ? primary : displayName,
    subtitle: secondary,
    metaFields: meta,
    checkDone: checkDone,
  );
}

/// Synthesize a spec for first-class entities (event/contact/task) that have no
/// UserSkill render_spec.
RenderSpec synthesizeSpec(String cardType) {
  switch (cardType) {
    case 'event':
      return const RenderSpec(
        cardLayout: 'horizontal',
        icon: '📅',
        accentColor: 'purple',
        primaryField: 'title',
        secondaryField: 'start_at',
        secondaryFormat: 'absolute_date',
        metaFields: [MetaFieldSpec('location', 'text')],
      );
    case 'contact':
      return const RenderSpec(
        cardLayout: 'horizontal',
        icon: '👤',
        accentColor: 'neutral',
        primaryField: 'name',
        secondaryField: 'company',
        metaFields: [MetaFieldSpec('title', 'text'), MetaFieldSpec('phone', 'text')],
      );
    case 'task':
      return const RenderSpec(
        cardLayout: 'horizontal',
        icon: '⏳',
        accentColor: 'purple',
        primaryField: 'title',
        secondaryField: 'external_system',
        metaFields: [MetaFieldSpec('status', 'badge')],
      );
    default:
      return const RenderSpec(
          cardLayout: 'horizontal', icon: '🗂', accentColor: 'gray', primaryField: 'content');
  }
}

Future<Map<String, RenderSpec>> fetchRenderSpecs(ApiClient api) async {
  final res = await api.getJson('/api/skills');
  final skills = (res is Map ? res['skills'] : null) as List? ?? const [];
  final out = <String, RenderSpec>{};
  for (final s in skills.whereType<Map>()) {
    final name = s['name'] as String?;
    final rs = s['render_spec'];
    if (name != null && rs is Map) {
      out[name] = RenderSpec.fromJson(rs.cast<String, dynamic>())
          .withFieldLabels(_fieldLabelsFrom(s['payload_schema']));
    }
  }
  return out;
}

/// A readable one-line title for an asset payload — the **general** rule used
/// anywhere we need to label an asset (picker, lists, …). Resolution order:
///   1. the skill's `render_spec.primary_field` (then secondary) — so a custom
///      skill whose content lives in e.g. `book` / `distance` shows that, not a
///      machine name;
///   2. common text fields (content/title/name/…);
///   3. the first non-empty string field in the payload;
///   4. `fallback` (pass the skill **display_name**, never the machine_name).
String readableTitle(Map<String, dynamic> payload, RenderSpec? spec, {String fallback = '资产'}) {
  String? pick(String? key) {
    if (key == null) return null;
    final v = payload[key];
    if (v == null) return null;
    final s = '$v'.trim();
    return s.isEmpty ? null : s;
  }

  final byField = pick(spec?.primaryField) ?? pick(spec?.secondaryField);
  if (byField != null) return byField;
  for (final k in const [
    'content', 'title', 'name', 'book', 'text', 'summary', 'description', 'note'
  ]) {
    final v = pick(k);
    if (v != null) return v;
  }
  for (final v in payload.values) {
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return fallback;
}

/// Build field → label from a skill's payload_schema. Prefers a concise `label`;
/// no label → no entry (the detail sheet falls back to a universal map / the
/// field name). Never invents money/quantity semantics.
Map<String, String> _fieldLabelsFrom(dynamic payloadSchema) {
  final out = <String, String>{};
  if (payloadSchema is Map) {
    payloadSchema.forEach((field, meta) {
      if (field is String && meta is Map) {
        final label = (meta['label'] as String?)?.trim();
        if (label != null && label.isNotEmpty) out[field] = label;
      }
    });
  }
  return out;
}

/* ── value formatting (mirrors web format.ts) ──────────────────────────────── */

final _isoDt = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}');
final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');
bool _looksIso(String v) => _isoDt.hasMatch(v) || _isoDate.hasMatch(v);

String applyFormat(dynamic value, String? format) {
  if (value == null || value == '') return '';
  final s = value.toString();
  if (format == null) return _looksIso(s) ? _fmtDate(s, false) : s;
  switch (format) {
    case 'relative_date':
      return _looksIso(s) ? _fmtDate(s, true) : s;
    case 'absolute_date':
      return _looksIso(s) ? _fmtDate(s, false) : s;
    case 'time':
      return _looksIso(s) ? _fmtTime(s) : s;
    case 'currency':
      return '¥$s';
    case 'duration':
      return _fmtDuration(s);
    case 'badge':
    case 'text':
      return s;
    default:
      if (format.startsWith('truncate_')) {
        final n = int.tryParse(format.substring('truncate_'.length)) ?? 40;
        return s.length > n ? '${s.substring(0, n)}…' : s;
      }
      return s;
  }
}

String _fmtDate(String raw, bool deadlineSuffix) {
  final d = DateTime.tryParse(raw.replaceAll('Z', '+00:00'))?.toLocal();
  if (d == null) return raw;
  final hasTime = d.hour != 0 || d.minute != 0;
  if (hasTime) {
    return '${d.month}月${d.day}日 ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
  return deadlineSuffix ? '${d.month}月${d.day}日截止' : '${d.month}月${d.day}日';
}

String _fmtTime(String raw) {
  final d = DateTime.tryParse(raw.replaceAll('Z', '+00:00'))?.toLocal();
  if (d == null) return raw;
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String _fmtDuration(String raw) {
  final n = int.tryParse(raw);
  if (n != null) return _minutes(n);
  final m = RegExp(r'^(?:(\d+)h)?(?:(\d+)m)?$').firstMatch(raw);
  if (m != null) {
    final h = int.tryParse(m.group(1) ?? '0') ?? 0;
    final mm = int.tryParse(m.group(2) ?? '0') ?? 0;
    return _minutes(h * 60 + mm);
  }
  return raw;
}

String _minutes(int total) {
  if (total <= 0) return '0 分钟';
  final h = total ~/ 60;
  final m = total % 60;
  if (h == 0) return '$m 分钟';
  if (m == 0) return '$h 小时';
  return '$h 小时 $m 分钟';
}
