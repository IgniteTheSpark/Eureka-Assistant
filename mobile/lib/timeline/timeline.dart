import '../api/api_client.dart';

/// Icon + label + accent for a skill / derived kind.
class SkillMeta {
  final String icon;
  final String label;
  final String accentColor; // blue|amber|green|red|purple|gray|neutral
  /// Present for registered user skills (`/api/skills` row id) — enables the
  /// category-detail delete control. Null for built-in / first-class kinds.
  final String? userSkillId;

  /// Active-set flag: enabled skills show in the library grid + the agent
  /// routes to them. Disabled ones live only in the 技能管理页.
  final bool enabled;
  const SkillMeta(this.icon, this.label,
      [this.accentColor = 'gray', this.userSkillId, this.enabled = true]);
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

  // Event-only: end time / all-day flag / location — needed by the day view's
  // hour grid. Null/false for non-events.
  final DateTime? endAt;
  final bool allDay;
  final String? location;
  final String? eventId;
  final String? contactId;

  /// Raw payload (asset / contact) — lets the day view render a full SkillCard.
  final Map<String, dynamic> payload;

  /// For flash (input_turn) captures: {skill_name|"event"|"contact": count}.
  final Map<String, int> derived;

  /// §4.5.0a 落段:user 只说了模糊时段时填(凌晨/上午/中午/下午/晚上),否则 ''。
  final String period;

  /// True when the user stated a clock time (asset.occurred_at set → effectiveAt
  /// is that precise moment). Events with a start time count via `kind`.
  final bool hasClockTime;

  TimelineItem({
    required this.kind,
    required this.id,
    required this.effectiveAt,
    required this.title,
    required this.subtitle,
    required this.skillName,
    required this.sessionId,
    required this.derived,
    this.endAt,
    this.allDay = false,
    this.location,
    this.eventId,
    this.contactId,
    this.payload = const {},
    this.period = '',
    this.hasClockTime = false,
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
      endAt: DateTime.tryParse(j['end_at'] as String? ?? '')?.toLocal(),
      allDay: j['all_day'] == true || j['all_day'] == 1,
      location: j['location'] as String?,
      eventId: j['event_id'] as String?,
      contactId: j['contact_id'] as String?,
      payload: (j['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
      derived: {
        for (final e in rawDerived.entries)
          if (e.value is num) e.key: (e.value as num).toInt(),
      },
      period: j['period'] as String? ?? '',
      hasClockTime: j['has_clock_time'] == true,
    );
  }
}

const _builtin = <String, SkillMeta>{
  'todo': SkillMeta('✅', '待办', 'blue'),
  'event': SkillMeta('📅', '日程', 'purple'),
  'contact': SkillMeta('👤', '名片', 'neutral'),
  'notes': SkillMeta('✍️', '随记', 'amber'),   // 随记 (idea/misc merged in)
  'idea': SkillMeta('✍️', '随记', 'amber'),    // legacy fallback → 随记
  'misc': SkillMeta('✍️', '随记', 'amber'),    // legacy fallback → 随记
  'expense': SkillMeta('💰', '记账', 'green'),
  'external_ref': SkillMeta('🔗', '外部', 'purple'),
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
      // The 文件 entity was removed from the app — never surface file captures.
      .where((it) => it.kind != 'file')
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
      rs?['accent_color'] as String? ?? 'gray',
      s['user_skill_id'] as String?,
      (s['enabled'] as int? ?? 1) != 0,
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
