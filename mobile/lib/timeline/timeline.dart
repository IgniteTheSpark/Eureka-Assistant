import '../api/api_client.dart';
import '../render/render_spec.dart';

const todoAssetIcon = '📋';
const eventAssetIcon = '📅';
const contactAssetIcon = '👤';
const notesAssetIcon = '✍️';

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
  const SkillMeta(
    this.icon,
    this.label, [
    this.accentColor = 'gray',
    this.userSkillId,
    this.enabled = true,
  ]);
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

  /// True only when the user actually scheduled this item. Unlike
  /// [effectiveAt], this never becomes true merely because the backend uses the
  /// capture time as a sorting fallback for an otherwise time-less todo.
  final bool hasScheduledTime;

  /// §8 生活领域(工作/学习/健康/运动/社交/娱乐/生活/灵感),否则 ''。流/月卡片的领域 tag。
  final String domain;

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
    this.hasScheduledTime = false,
    this.domain = '',
  });

  factory TimelineItem.fromJson(Map<String, dynamic> j) {
    final kind = j['kind'] as String? ?? 'asset';
    final ea =
        DateTime.tryParse(j['effective_at'] as String? ?? '')?.toLocal() ??
        DateTime.now();
    final rawDerived =
        (j['derived'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rawPayload =
        (j['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    final payload = kind == 'event'
        ? <String, dynamic>{
            'event_id': j['event_id'],
            'title': j['title'],
            'start_at': j['start_at'] ?? j['effective_at'],
            'end_at': j['end_at'],
            'all_day': j['all_day'],
            'location': j['location'],
            'description': j['description'],
            'attendees': j['attendees'],
            ...rawPayload,
          }
        : rawPayload;
    return TimelineItem(
      kind: kind,
      id: j['id'] as String? ?? '',
      effectiveAt: ea,
      title: j['title'] as String? ?? '',
      subtitle: kind == 'event'
          ? eventCardSummary(payload)
          : j['subtitle'] as String? ?? '',
      skillName: j['skill_name'] as String?,
      sessionId: j['session_id'] as String?,
      endAt: DateTime.tryParse(j['end_at'] as String? ?? '')?.toLocal(),
      allDay: j['all_day'] == true || j['all_day'] == 1,
      location: j['location'] as String?,
      eventId: j['event_id'] as String?,
      contactId: j['contact_id'] as String?,
      payload: payload,
      derived: {
        for (final e in rawDerived.entries)
          if (e.value is num) e.key: (e.value as num).toInt(),
      },
      period: j['period'] as String? ?? '',
      hasClockTime: j['has_clock_time'] == true,
      hasScheduledTime: j['has_scheduled_time'] == true,
      domain: j['domain'] as String? ?? '',
    );
  }
}

const _builtin = <String, SkillMeta>{
  'todo': SkillMeta(todoAssetIcon, '待办', 'blue'),
  'event': SkillMeta(eventAssetIcon, '日程', 'purple'),
  'contact': SkillMeta(contactAssetIcon, '名片', 'neutral'),
  'notes': SkillMeta(notesAssetIcon, '随记', 'amber'),
  'expense': SkillMeta('💳', '记账', 'green'),
  'external_ref': SkillMeta('🔗', '外部', 'purple'),
};

/// Built-in glyphs the client pins regardless of the server's render_spec — the
/// seed mirrors these, but the client owns the canonical look. 待办 must read as
/// "to-do" (📋), not "done" (✅). Custom user skills are unaffected.
const _pinnedIcons = <String, String>{'todo': todoAssetIcon};

String _canonicalSkillKey(String key) => switch (key.trim().toLowerCase()) {
  'calendar' => 'event',
  'note' || 'idea' || 'misc' => 'notes',
  final normalized => normalized,
};

/// Resolve a skill / derived key to its icon + label. Custom skills live only
/// in the registry, so look there first (mirrors the web derivedMeta fix).
SkillMeta resolveMeta(String key, Map<String, SkillMeta> registry) {
  final normalized = key.trim().toLowerCase();
  final registered = registry[normalized] ?? registry[key];
  final canonical = _canonicalSkillKey(normalized);
  final m = registered ?? _builtin[canonical] ?? SkillMeta('•', key);
  final pin = _pinnedIcons[canonical];
  return pin == null
      ? m
      : SkillMeta(pin, m.label, m.accentColor, m.userSkillId, m.enabled);
}

/// Resolve the canonical identity for an Asset-like timeline entry.
///
/// Flash/input-turn rows are a separate presentation and should keep their
/// lightning icon instead of passing through this resolver.
SkillMeta resolveTimelineItemMeta(
  TimelineItem item,
  Map<String, SkillMeta> registry,
) {
  if (item.kind == 'event') return resolveMeta('event', registry);
  if (item.kind == 'contact') return resolveMeta('contact', registry);
  final skillName = item.skillName?.trim();
  if (skillName != null && skillName.isNotEmpty) {
    return resolveMeta(skillName, registry);
  }
  return const SkillMeta('•', '记录');
}

Future<List<TimelineItem>> fetchTimeline(
  ApiClient api, {
  bool coreRecordsOnly = false,
}) async {
  if (coreRecordsOnly) return _fetchCoreRecordTimeline(api);
  try {
    final res = await api.getJson('/api/timeline');
    final items = (res is Map ? res['items'] : null) as List? ?? const [];
    return items
        .whereType<Map>()
        .map((e) => TimelineItem.fromJson(e.cast<String, dynamic>()))
        // The 文件 entity was removed from the app — never surface file captures.
        .where((it) => it.kind != 'file')
        .toList();
  } on ApiException catch (error) {
    if (error.statusCode != 404) rethrow;
    return _fetchCoreRecordTimeline(api);
  }
}

Future<List<TimelineItem>> _fetchCoreRecordTimeline(ApiClient api) async {
  final responses = await Future.wait([
    api.getJson('/api/user-skills'),
    api.getJson('/api/assets', query: const {'limit': 100}),
    api.getJson('/api/events', query: const {'limit': 100}),
    api.getJson('/api/flash/recordings', query: const {'limit': 200}),
  ]);
  final skillsById = <String, ({String name, String domain})>{};
  for (final raw in _coreList(responses[0], 'skills').whereType<Map>()) {
    final skill = raw.cast<String, dynamic>();
    final id = skill['id']?.toString();
    final name = skill['machine_name']?.toString();
    if (id == null || name == null || name.isEmpty) continue;
    skillsById[id] = (name: name, domain: skill['domain']?.toString() ?? '');
  }

  final items = <TimelineItem>[];
  for (final raw in _coreList(responses[2], 'events').whereType<Map>()) {
    final event = raw.cast<String, dynamic>();
    if (event['status'] == 'cancelled') continue;
    final start = DateTime.tryParse(
      event['start_at']?.toString() ?? '',
    )?.toLocal();
    if (start == null) continue;
    final id = event['id']?.toString() ?? '';
    items.add(
      TimelineItem(
        kind: 'event',
        id: id,
        effectiveAt: start,
        title: _coreTitle(event, '事件'),
        subtitle: '',
        skillName: null,
        sessionId: null,
        derived: const {},
        endAt: DateTime.tryParse(event['end_at']?.toString() ?? '')?.toLocal(),
        allDay: event['all_day'] == true,
        location: event['location']?.toString(),
        eventId: id,
        payload: event,
      ),
    );
  }

  for (final raw in _coreList(responses[1], 'assets').whereType<Map>()) {
    final asset = raw.cast<String, dynamic>();
    final skill = skillsById[asset['user_skill_id']?.toString()];
    if (skill == null) continue;
    final payload =
        (asset['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    final due = payload['due_date']?.toString();
    final explicit = _firstCoreDate([
      asset['effective_at'],
      payload['occurred_at'],
    ]);
    final semantic = switch (skill.name) {
      'todo' => _firstCoreDate([due]),
      'expense' => _firstCoreDate([payload['at'], payload['date']]),
      _ => null,
    };
    final effective =
        explicit ?? semantic ?? _firstCoreDate([asset['created_at']]);
    if (effective == null) continue;
    final hasExplicitClock = explicit != null;
    items.add(
      TimelineItem(
        kind: 'asset',
        id: asset['id']?.toString() ?? '',
        effectiveAt: effective,
        title: _coreTitle(payload, skill.name),
        subtitle:
            payload['note']?.toString() ??
            payload['description']?.toString() ??
            '',
        skillName: skill.name,
        sessionId: null,
        derived: const {},
        payload: payload,
        period: payload['period']?.toString() ?? '',
        hasClockTime: hasExplicitClock || due?.contains('T') == true,
        hasScheduledTime:
            skill.name == 'todo' &&
            (hasExplicitClock || due?.contains('T') == true),
        domain: skill.domain,
      ),
    );
  }

  for (final raw in _coreList(responses[3], 'recordings').whereType<Map>()) {
    final recording = raw.cast<String, dynamic>();
    final effective = _firstCoreDate([
      recording['captured_at'],
      recording['created_at'],
    ]);
    if (effective == null) continue;
    final title = recording['title']?.toString().trim() ?? '';
    items.add(
      TimelineItem(
        kind: 'input_turn',
        id: recording['id']?.toString() ?? '',
        effectiveAt: effective,
        title: title.isEmpty ? '闪念' : title,
        subtitle: '',
        skillName: null,
        sessionId: recording['session_date']?.toString(),
        derived: const {},
        payload: {
          'process_status': recording['process_status'],
          'session_date': recording['session_date'],
        },
      ),
    );
  }
  items.sort((a, b) => a.effectiveAt.compareTo(b.effectiveAt));
  return items;
}

DateTime? _firstCoreDate(Iterable<dynamic> values) {
  for (final value in values) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) continue;
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed != null) return parsed;
  }
  return null;
}

List _coreList(dynamic response, String key) => switch (response) {
  List value => value,
  Map value => value[key] as List? ?? const [],
  _ => const [],
};

String _coreTitle(Map<String, dynamic> value, String fallback) {
  final candidate =
      value['title'] ?? value['content'] ?? value['name'] ?? value['amount'];
  final title = candidate?.toString().trim() ?? '';
  return title.isEmpty ? fallback : title;
}

/// name → {icon, label} from /api/skills (render_spec.icon + display_name).
Future<Map<String, SkillMeta>> fetchSkills(
  ApiClient api, {
  bool coreRecordsOnly = false,
}) async {
  dynamic res;
  if (coreRecordsOnly) {
    res = await api.getJson('/api/user-skills');
  } else {
    try {
      res = await api.getJson('/api/skills');
    } on ApiException catch (error) {
      if (error.statusCode != 404) rethrow;
      res = await api.getJson('/api/user-skills');
    }
  }
  final skills = switch (res) {
    List value => value,
    Map value => value['skills'] as List? ?? const [],
    _ => const [],
  };
  final out = <String, SkillMeta>{};
  for (final s in skills.whereType<Map>()) {
    final name = (s['name'] ?? s['machine_name']) as String?;
    if (name == null) continue;
    final rs = (s['render_spec'] as Map?)?.cast<String, dynamic>();
    final coreSpec = coreRecordsOnly
        ? coreRecordRenderSpec(name, s['schema'])
        : null;
    out[name] = SkillMeta(
      // Pin built-in glyphs (待办 → 📋) even for surfaces that read the meta map
      // directly (e.g. 资产库 container tiles), not just via resolveMeta.
      _pinnedIcons[name] ?? (rs?['icon'] as String? ?? coreSpec?.icon ?? '•'),
      s['display_name'] as String? ?? name,
      rs?['accent_color'] as String? ?? coreSpec?.accentColor ?? 'gray',
      (s['user_skill_id'] ?? s['id']) as String?,
      (s['enabled'] as int? ?? 1) != 0,
    );
  }
  return out;
}

/// Group items into day buckets, newest day first; items within a day ascend.
List<MapEntry<DateTime, List<TimelineItem>>> groupByDay(
  List<TimelineItem> items,
) {
  final byDay = <DateTime, List<TimelineItem>>{};
  for (final it in items) {
    final d = DateTime(
      it.effectiveAt.year,
      it.effectiveAt.month,
      it.effectiveAt.day,
    );
    byDay.putIfAbsent(d, () => []).add(it);
  }
  final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final d in days)
      MapEntry(
        d,
        byDay[d]!..sort((a, b) => a.effectiveAt.compareTo(b.effectiveAt)),
      ),
  ];
}
