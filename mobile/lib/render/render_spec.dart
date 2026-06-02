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
  });

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
  bool? checkDone;
  if (spec.actions.contains('check') &&
      (payload.containsKey('status') || payload.containsKey('done'))) {
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
      out[name] = RenderSpec.fromJson(rs.cast<String, dynamic>());
    }
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
