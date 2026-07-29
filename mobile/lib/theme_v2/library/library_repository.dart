import 'dart:io';

import 'package:http/http.dart' as http;

import '../../api/api_client.dart';
import '../../assets/assets.dart';
import '../../render/render_spec.dart';
import '../asset/asset_card_display.dart';
import 'library_models.dart';

abstract interface class LibraryRepository {
  Future<LibraryOverview> loadOverview();
}

class ApiLibraryRepository implements LibraryRepository {
  ApiLibraryRepository(this.api);

  final ApiClient api;

  @override
  Future<LibraryOverview> loadOverview() async {
    final sources = await Future.wait([
      _capture(
        'assets',
        () => api.getJson('/api/assets', query: const {'limit': 50}),
      ),
      _capture('skills', () => api.getJson('/api/skills')),
      _capture('events', () => api.getJson('/api/events')),
      _capture('contacts', () => api.getJson('/api/contacts')),
      _capture('counts', () => api.getJson('/api/assets/counts')),
    ]);
    final failures = [
      for (final source in sources)
        if (source.failure != null) source.failure!,
    ];
    if (failures.length == sources.length) {
      throw LibraryLoadFailure(
        '资产库暂时无法加载',
        isOffline: failures.every((failure) => failure.isOffline),
      );
    }

    final assets = _assets(sources[0].value);
    final skills = _skills(sources[1].value);
    final events = _rows(sources[2].value, 'events');
    final contacts = _rows(sources[3].value, 'contacts');
    final serverCounts = _counts(sources[4].value);
    final counts = sources[4].failure == null
        ? serverCounts
        : _countsFromAssets(assets);

    return LibraryOverview(
      systemContainers: _systemContainers(
        skills: skills,
        counts: counts,
        events: events,
        contacts: contacts,
      ),
      customContainers: _customContainers(skills, counts),
      recentAssets: _recentAssets(assets, skills),
      totalAssetCount: counts.values.fold(0, (sum, count) => sum + count),
      failedSources: failures,
    );
  }

  Future<_CapturedSource> _capture(
    String source,
    Future<dynamic> Function() request,
  ) async {
    try {
      return _CapturedSource(value: await request());
    } catch (error) {
      return _CapturedSource(
        failure: LibrarySourceFailure(
          source: source,
          isOffline: _isOfflineError(error),
        ),
      );
    }
  }

  List<AssetItem> _assets(dynamic response) {
    final rows = (response is Map ? response['assets'] : null) as List? ?? [];
    return rows
        .whereType<Map>()
        .map((row) => AssetItem.fromJson(row.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Map<String, _SkillDefinition> _skills(dynamic response) {
    final rows = (response is Map ? response['skills'] : null) as List? ?? [];
    final result = <String, _SkillDefinition>{};
    for (final raw in rows.whereType<Map>()) {
      final row = raw.cast<String, dynamic>();
      final name = row['name']?.toString().trim() ?? '';
      if (name.isEmpty || !_enabled(row['enabled'])) continue;
      final renderMap =
          (row['render_spec'] as Map?)?.cast<String, dynamic>() ?? const {};
      var spec = RenderSpec.fromJson(
        renderMap,
      ).withSchema(row['payload_schema']);
      if (name == 'todo') spec = normalizeTodoSpec(spec);
      result[name] = _SkillDefinition(
        name: name,
        label: row['display_name']?.toString().trim().isNotEmpty == true
            ? row['display_name'].toString().trim()
            : name,
        userSkillId: row['user_skill_id']?.toString() ?? row['id']?.toString(),
        renderMap: renderMap,
        spec: spec,
      );
    }
    return result;
  }

  List<Map<String, dynamic>> _rows(dynamic response, String key) {
    final rows = (response is Map ? response[key] : null) as List? ?? [];
    return rows
        .whereType<Map>()
        .map((row) => row.cast<String, dynamic>())
        .toList(growable: false);
  }

  Map<String, int> _counts(dynamic response) {
    final raw = (response is Map ? response['counts'] : null) as Map? ?? {};
    return {
      for (final entry in raw.entries)
        if (entry.value is num)
          entry.key.toString(): (entry.value as num).toInt(),
    };
  }

  Map<String, int> _countsFromAssets(List<AssetItem> assets) {
    final result = <String, int>{};
    for (final asset in assets) {
      result.update(asset.skillName, (count) => count + 1, ifAbsent: () => 1);
    }
    return result;
  }

  List<LibraryContainerSummary> _systemContainers({
    required Map<String, _SkillDefinition> skills,
    required Map<String, int> counts,
    required List<Map<String, dynamic>> events,
    required List<Map<String, dynamic>> contacts,
  }) => [
    _systemContainer(
      id: 'todo',
      label: '待办',
      fallbackMark: '☑',
      type: LibraryContainerType.todo,
      skill: skills['todo'],
      count: counts['todo'] ?? 0,
    ),
    _systemContainer(
      id: 'notes',
      label: '随记',
      fallbackMark: '✎',
      type: LibraryContainerType.notes,
      skill: skills['notes'],
      count: counts['notes'] ?? 0,
    ),
    _systemContainer(
      id: 'event',
      label: '事件',
      fallbackMark: '▣',
      type: LibraryContainerType.event,
      skill: skills['event'],
      count: counts['event'] ?? events.length,
    ),
    _systemContainer(
      id: 'contact',
      label: '联系人',
      fallbackMark: '♙',
      type: LibraryContainerType.contact,
      skill: skills['contact'],
      count: counts['contact'] ?? contacts.length,
    ),
  ];

  LibraryContainerSummary _systemContainer({
    required String id,
    required String label,
    required String fallbackMark,
    required LibraryContainerType type,
    required _SkillDefinition? skill,
    required int count,
  }) => LibraryContainerSummary(
    id: id,
    label: skill?.label ?? label,
    mark: _mark(skill, fallbackMark),
    type: type,
    totalCount: count,
    isSystem: true,
    userSkillId: skill?.userSkillId,
  );

  List<LibraryContainerSummary> _customContainers(
    Map<String, _SkillDefinition> skills,
    Map<String, int> counts,
  ) {
    const hidden = {'todo', 'notes', 'event', 'contact', 'external_ref', 'qa'};
    return [
      for (final skill in skills.values)
        if (!hidden.contains(skill.name))
          LibraryContainerSummary(
            id: skill.name,
            label: skill.label,
            mark: _mark(skill, '•'),
            type: LibraryContainerType.custom,
            totalCount: counts[skill.name] ?? 0,
            isSystem: false,
            userSkillId: skill.userSkillId,
          ),
    ];
  }

  List<LibraryRecentAsset> _recentAssets(
    List<AssetItem> assets,
    Map<String, _SkillDefinition> skills,
  ) {
    final sorted = List<AssetItem>.of(assets)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [
      for (final asset in sorted.take(50))
        _recentAsset(asset, skills[asset.skillName]),
    ];
  }

  LibraryRecentAsset _recentAsset(AssetItem asset, _SkillDefinition? skill) {
    final label = skill?.label ?? asset.skillName;
    final spec = skill?.spec ?? synthesizeSpec(asset.skillName);
    final display = _displayConfig(skill?.renderMap, spec, asset.payload);
    final card = AssetCardViewData.fromPayload(
      payload: asset.payload,
      display: display,
      spec: spec,
      skillLabel: label,
    );
    return LibraryRecentAsset(
      id: asset.id,
      skillName: asset.skillName,
      skillLabel: label,
      mark: card.mark,
      primaryValue: card.primaryValue,
      createdAt: asset.createdAt,
      detailCard: {
        'asset_id': asset.id,
        'user_skill_id': asset.userSkillId ?? skill?.userSkillId,
        'user_skill_name': asset.skillName,
        'payload': asset.payload,
        'session_id': asset.sessionId,
        'domain': asset.domain,
      },
    );
  }

  CardDisplayConfig _displayConfig(
    Map<String, dynamic>? renderMap,
    RenderSpec spec,
    Map<String, dynamic> payload,
  ) {
    if (renderMap != null) {
      try {
        return CardDisplayConfig.fromRenderSpec(renderMap);
      } on FormatException {
        // A legacy render spec falls through to its resolved primary field.
      }
    }
    final primary =
        spec.primaryField ??
        payload.keys.cast<String?>().firstWhere(
          (key) => key != null && key.trim().isNotEmpty,
          orElse: () => null,
        ) ??
        'content';
    return CardDisplayConfig(primaryFieldId: primary);
  }

  String _mark(_SkillDefinition? skill, String fallback) {
    final value = skill?.spec.icon.trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  bool _enabled(dynamic value) =>
      value == null || value == true || value == 1 || value == '1';

  bool _isOfflineError(Object error) =>
      error is SocketException ||
      error is http.ClientException ||
      (error is ApiException && error.statusCode == 503);
}

class _CapturedSource {
  const _CapturedSource({this.value, this.failure});

  final dynamic value;
  final LibrarySourceFailure? failure;
}

class _SkillDefinition {
  const _SkillDefinition({
    required this.name,
    required this.label,
    required this.userSkillId,
    required this.renderMap,
    required this.spec,
  });

  final String name;
  final String label;
  final String? userSkillId;
  final Map<String, dynamic> renderMap;
  final RenderSpec spec;
}
