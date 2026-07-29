import 'package:flutter/foundation.dart';

import '../../../assets/assets.dart';
import '../../../render/render_spec.dart';
import '../../asset/asset_card_display.dart';

enum AssetRecordKind { todo, note, event, contact, custom }

enum TodoAssetFilter { all, today, completed, unscheduled }

typedef AssetRecordCard = AssetCardViewData;

@immutable
class AssetRecordField {
  const AssetRecordField({
    required this.id,
    required this.label,
    required this.value,
    this.type = 'string',
    this.required = false,
    this.long = false,
  });

  final String id;
  final String label;
  final dynamic value;
  final String type;
  final bool required;
  final bool long;
}

@immutable
class AssetSource {
  const AssetSource({required this.label, this.sessionId});

  final String label;
  final String? sessionId;
}

@immutable
class AssetRecordViewModel {
  const AssetRecordViewModel({
    required this.id,
    required this.containerId,
    required this.kind,
    required this.card,
    required this.fields,
    required this.payload,
    required this.createdAt,
    DateTime? effectiveAt,
    this.source,
    this.dueAt,
    this.completed = false,
    this.userSkillId,
    this.sessionId,
    this.domain,
    this.payloadSchema = const {},
    this.renderSpec = const {},
  }) : effectiveAt = effectiveAt ?? createdAt;

  final String id;
  final String containerId;
  final AssetRecordKind kind;
  final AssetRecordCard card;
  final List<AssetRecordField> fields;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime effectiveAt;
  final AssetSource? source;
  final DateTime? dueAt;
  final bool completed;
  final String? userSkillId;
  final String? sessionId;
  final String? domain;
  final Map<String, dynamic> payloadSchema;
  final Map<String, dynamic> renderSpec;

  AssetRecordViewModel copyWith({
    AssetRecordCard? card,
    List<AssetRecordField>? fields,
    Map<String, dynamic>? payload,
    DateTime? dueAt,
    bool clearDueAt = false,
    bool? completed,
    AssetSource? source,
  }) {
    return AssetRecordViewModel(
      id: id,
      containerId: containerId,
      kind: kind,
      card: card ?? this.card,
      fields: List.unmodifiable(fields ?? this.fields),
      payload: Map.unmodifiable(payload ?? this.payload),
      createdAt: createdAt,
      effectiveAt: effectiveAt,
      source: source ?? this.source,
      dueAt: clearDueAt ? null : (dueAt ?? this.dueAt),
      completed: completed ?? this.completed,
      userSkillId: userSkillId,
      sessionId: sessionId,
      domain: domain,
      payloadSchema: payloadSchema,
      renderSpec: renderSpec,
    );
  }
}

class AssetRecordAdapter {
  const AssetRecordAdapter._();

  static AssetRecordViewModel asset({
    required AssetItem asset,
    required String skillLabel,
    required RenderSpec spec,
    Map<String, dynamic> renderSpec = const {},
    Map<String, dynamic> payloadSchema = const {},
  }) {
    final kind = switch (asset.skillName) {
      'todo' => AssetRecordKind.todo,
      'notes' || 'note' => AssetRecordKind.note,
      _ => AssetRecordKind.custom,
    };
    final display = _displayFromSpec(
      renderSpec: renderSpec,
      spec: spec,
      payload: asset.payload,
    );
    return AssetRecordViewModel(
      id: asset.id,
      containerId: asset.skillName,
      kind: kind,
      card: AssetCardViewData.fromPayload(
        payload: asset.payload,
        display: display,
        spec: spec,
        skillLabel: skillLabel,
        timeLabel: _clockLabel(asset.effectiveAt),
      ),
      fields: _fieldsFromSpec(asset.payload, spec, payloadSchema),
      payload: Map.unmodifiable(asset.payload),
      createdAt: asset.createdAt,
      effectiveAt: asset.effectiveAt,
      source: _assetSource(asset),
      dueAt: kind == AssetRecordKind.todo ? _todoDueAt(asset.payload) : null,
      completed: kind == AssetRecordKind.todo
          ? todoPayloadIsDone(asset.payload)
          : false,
      userSkillId: asset.userSkillId,
      sessionId: asset.sessionId,
      domain: asset.domain,
      payloadSchema: Map.unmodifiable(payloadSchema),
      renderSpec: Map.unmodifiable(renderSpec),
    );
  }

  static AssetRecordViewModel custom({
    required AssetItem asset,
    required String skillLabel,
    required Map<String, dynamic> renderSpec,
    required Map<String, dynamic> payloadSchema,
  }) {
    final spec = RenderSpec.fromJson(renderSpec).withSchema(payloadSchema);
    return AssetRecordAdapter.asset(
      asset: asset,
      skillLabel: skillLabel,
      spec: spec,
      renderSpec: renderSpec,
      payloadSchema: payloadSchema,
    );
  }

  static AssetRecordViewModel event({required Map<String, dynamic> entity}) {
    final title = _string(entity['title'], fallback: '未命名事件');
    final summary = eventCardSummary(entity);
    final createdAt =
        _date(entity['created_at']) ??
        _date(entity['start_at']) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return AssetRecordViewModel(
      id: _string(entity['event_id'] ?? entity['id']),
      containerId: 'event',
      kind: AssetRecordKind.event,
      card: AssetCardViewData(
        mark: '▣',
        skillLabel: '事件',
        primaryValue: title,
        secondaryValues: [if (summary.isNotEmpty) summary],
        timeLabel: _clockLabel(_date(entity['start_at'])),
      ),
      fields: _entityFields(entity, const [
        ('title', '标题'),
        ('start_at', '开始'),
        ('end_at', '结束'),
        ('location', '地点'),
        ('attendees', '参与人'),
        ('notes', '备注'),
      ]),
      payload: Map.unmodifiable(entity),
      createdAt: createdAt,
      effectiveAt: _date(entity['start_at']) ?? createdAt,
      source: _entitySource(entity),
      domain: entity['domain']?.toString(),
    );
  }

  static AssetRecordViewModel contact({required Map<String, dynamic> entity}) {
    final name = _string(entity['name'], fallback: '未命名联系人');
    final company = _string(entity['company']);
    final title = _string(entity['title']);
    return AssetRecordViewModel(
      id: _string(entity['contact_id'] ?? entity['id']),
      containerId: 'contact',
      kind: AssetRecordKind.contact,
      card: AssetCardViewData(
        mark: '♙',
        skillLabel: '联系人',
        primaryValue: name,
        secondaryValues: [
          if (company.isNotEmpty) company,
          if (title.isNotEmpty) title,
        ],
      ),
      fields: _entityFields(entity, const [
        ('name', '姓名'),
        ('company', '公司'),
        ('title', '职位'),
        ('phone', '电话'),
        ('email', '邮箱'),
        ('social', '社交账号'),
        ('notes', '备注'),
      ]),
      payload: Map.unmodifiable(entity),
      createdAt:
          _date(entity['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      effectiveAt: _date(entity['effective_at']) ?? _date(entity['created_at']),
      source: _entitySource(entity),
      domain: entity['domain']?.toString(),
    );
  }

  static CardDisplayConfig _displayFromSpec({
    required Map<String, dynamic> renderSpec,
    required RenderSpec spec,
    required Map<String, dynamic> payload,
  }) {
    try {
      return CardDisplayConfig.fromRenderSpec(renderSpec);
    } on FormatException {
      final primary =
          spec.primaryField ??
          spec.schemaFields.firstOrNull ??
          payload.keys.firstOrNull ??
          'title';
      return CardDisplayConfig(
        primaryFieldId: primary,
        secondaryFieldIds: [
          ?spec.secondaryField,
          for (final meta in spec.metaFields) meta.field,
        ],
      );
    }
  }

  static List<AssetRecordField> _fieldsFromSpec(
    Map<String, dynamic> payload,
    RenderSpec spec,
    Map<String, dynamic> payloadSchema,
  ) {
    final ids = <String>[
      ...spec.schemaFields,
      for (final key in payload.keys)
        if (!spec.schemaFields.contains(key)) key,
    ];
    return List.unmodifiable([
      for (final id in ids)
        if (id != 'id' && id != 'uuid')
          AssetRecordField(
            id: id,
            label: spec.fieldLabels[id] ?? id,
            value: payload[id],
            type:
                spec.fieldTypes[id] ??
                ((payloadSchema[id] as Map?)?['type']?.toString() ?? 'string'),
            required: spec.requiredFields.contains(id),
            long:
                spec.longFields.contains(id) ||
                ((payloadSchema[id] as Map?)?['long'] == true),
          ),
    ]);
  }

  static List<AssetRecordField> _entityFields(
    Map<String, dynamic> entity,
    List<(String, String)> definitions,
  ) {
    return List.unmodifiable([
      for (final definition in definitions)
        if (entity.containsKey(definition.$1))
          AssetRecordField(
            id: definition.$1,
            label: definition.$2,
            value: entity[definition.$1],
            long: definition.$1 == 'notes',
          ),
    ]);
  }

  static AssetSource? _assetSource(AssetItem asset) {
    final session = asset.sessionId?.trim() ?? '';
    if (session.isNotEmpty) {
      return AssetSource(label: '来自会话', sessionId: session);
    }
    return null;
  }

  static AssetSource? _entitySource(Map<String, dynamic> entity) {
    final session = entity['session_id']?.toString().trim() ?? '';
    if (session.isNotEmpty) {
      return AssetSource(label: '来自会话', sessionId: session);
    }
    final source = entity['source']?.toString().trim() ?? '';
    return source.isEmpty ? null : AssetSource(label: source);
  }
}

bool matchesTodoFilter(
  AssetRecordViewModel record,
  TodoAssetFilter filter,
  DateTime today,
) {
  if (record.kind != AssetRecordKind.todo) return false;
  return switch (filter) {
    TodoAssetFilter.all => true,
    TodoAssetFilter.today =>
      !record.completed &&
          record.dueAt != null &&
          _sameDate(record.dueAt!, today),
    TodoAssetFilter.completed => record.completed,
    TodoAssetFilter.unscheduled => !record.completed && record.dueAt == null,
  };
}

List<AssetRecordViewModel> sortTodoRecords(
  Iterable<AssetRecordViewModel> records,
) {
  final sorted = List<AssetRecordViewModel>.of(records);
  sorted.sort((a, b) {
    final aDue = a.dueAt;
    final bDue = b.dueAt;
    if (aDue == null && bDue != null) return 1;
    if (aDue != null && bDue == null) return -1;
    if (aDue != null && bDue != null) {
      final dueOrder = aDue.compareTo(bDue);
      if (dueOrder != 0) return dueOrder;
    }
    final createdOrder = b.createdAt.compareTo(a.createdAt);
    return createdOrder != 0 ? createdOrder : b.id.compareTo(a.id);
  });
  return List.unmodifiable(sorted);
}

DateTime? _todoDueAt(Map<String, dynamic> payload) {
  for (final key in const ['due_at', 'scheduled_at', 'due_date', 'date']) {
    final value = _date(payload[key]);
    if (value != null) return value;
  }
  return null;
}

DateTime? _date(dynamic value) {
  if (value is DateTime) return value;
  final raw = value?.toString().trim() ?? '';
  return raw.isEmpty ? null : DateTime.tryParse(raw);
}

String? _clockLabel(DateTime? value) {
  if (value == null) return null;
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

String _string(dynamic value, {String fallback = ''}) {
  final normalized = value?.toString().trim() ?? '';
  return normalized.isEmpty ? fallback : normalized;
}

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
