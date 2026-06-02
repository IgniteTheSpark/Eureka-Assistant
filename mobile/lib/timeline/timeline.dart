import '../api/api_client.dart';

/// Icon + label for a skill / derived kind.
class SkillMeta {
  final String icon;
  final String label;
  const SkillMeta(this.icon, this.label);
}

/// One unified timeline entry (asset / event / contact / input_turn / file),
/// matching the backend /api/timeline shape.
class TimelineItem {
  final String kind;
  final String id;
  final DateTime effectiveAt; // local time
  final String title;
  final String subtitle;
  final String? skillName;
  final String? sessionId;

  /// For flash (input_turn) captures: {skill_name|"event"|"contact": count}.
  final Map<String, int> derived;

  TimelineItem({
    required this.kind,
    required this.id,
    required this.effectiveAt,
    required this.title,
    required this.subtitle,
    required this.skillName,
    required this.sessionId,
    required this.derived,
  });

  factory TimelineItem.fromJson(Map<String, dynamic> j) {
    final ea = DateTime.tryParse(j['effective_at'] as String? ?? '')?.toLocal() ??
        DateTime.now();
    final rawDerived = (j['derived'] as Map?)?.cast<String, dynamic>() ?? const {};
    return TimelineItem(
      kind: j['kind'] as String? ?? 'asset',
      id: j['id'] as String? ?? '',
      effectiveAt: ea,
      title: j['title'] as String? ?? '',
      subtitle: j['subtitle'] as String? ?? '',
      skillName: j['skill_name'] as String?,
      sessionId: j['session_id'] as String?,
      derived: {
        for (final e in rawDerived.entries)
          if (e.value is num) e.key: (e.value as num).toInt(),
      },
    );
  }
}

const _builtin = <String, SkillMeta>{
  'todo': SkillMeta('✅', '待办'),
  'event': SkillMeta('📅', '日程'),
  'contact': SkillMeta('👤', '名片'),
  'idea': SkillMeta('💡', '想法'),
  'notes': SkillMeta('📝', '笔记'),
  'expense': SkillMeta('💰', '记账'),
  'misc': SkillMeta('🗂', '其它'),
  'external_ref': SkillMeta('🔗', '外部'),
};

/// Resolve a skill / derived key to its icon + label. Custom skills live only
/// in the registry, so look there first (mirrors the web derivedMeta fix).
SkillMeta resolveMeta(String key, Map<String, SkillMeta> registry) {
  if (key == 'event') return _builtin['event']!;
  return registry[key] ?? _builtin[key] ?? SkillMeta('•', key);
}

Future<List<TimelineItem>> fetchTimeline(ApiClient api) async {
  final res = await api.getJson('/api/timeline');
  final items = (res is Map ? res['items'] : null) as List? ?? const [];
  return items
      .whereType<Map>()
      .map((e) => TimelineItem.fromJson(e.cast<String, dynamic>()))
      .toList();
}

/// name → {icon, label} from /api/skills (render_spec.icon + display_name).
Future<Map<String, SkillMeta>> fetchSkills(ApiClient api) async {
  final res = await api.getJson('/api/skills');
  final skills = (res is Map ? res['skills'] : null) as List? ?? const [];
  final out = <String, SkillMeta>{};
  for (final s in skills.whereType<Map>()) {
    final name = s['name'] as String?;
    if (name == null) continue;
    final rs = (s['render_spec'] as Map?)?.cast<String, dynamic>();
    out[name] = SkillMeta(
      rs?['icon'] as String? ?? '•',
      s['display_name'] as String? ?? name,
    );
  }
  return out;
}

/// Group items into day buckets, newest day first; items within a day ascend.
List<MapEntry<DateTime, List<TimelineItem>>> groupByDay(List<TimelineItem> items) {
  final byDay = <DateTime, List<TimelineItem>>{};
  for (final it in items) {
    final d = DateTime(it.effectiveAt.year, it.effectiveAt.month, it.effectiveAt.day);
    byDay.putIfAbsent(d, () => []).add(it);
  }
  final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final d in days)
      MapEntry(d, byDay[d]!..sort((a, b) => a.effectiveAt.compareTo(b.effectiveAt))),
  ];
}
