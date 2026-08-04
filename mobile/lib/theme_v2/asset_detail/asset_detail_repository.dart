import '../../api/api_client.dart';
import '../../timeline/timeline.dart';
import 'asset_detail_model.dart';
import 'asset_entity_ref.dart';

abstract interface class AssetDetailRepository {
  Future<AssetDetailModel> load(AssetEntityRef ref);

  Future<AssetDetailModel> save(
    AssetDetailModel current,
    Map<String, dynamic> valuesPatch,
  );

  Future<void> delete(AssetEntityRef ref);
}

class ApiAssetDetailRepository implements AssetDetailRepository {
  ApiAssetDetailRepository(this.api, {this.coreRecordsOnly = false});

  final ApiClient api;
  final bool coreRecordsOnly;

  @override
  Future<AssetDetailModel> load(AssetEntityRef ref) async {
    if (coreRecordsOnly) return _loadCoreRecord(ref);
    try {
      final response = await api.getJson(_canonicalPath(ref));
      return AssetDetailModel.fromJson(
        (response as Map).cast<String, dynamic>(),
      );
    } on ApiException catch (error) {
      if (error.statusCode != 404 || ref.kind == AssetEntityKind.contact) {
        rethrow;
      }
      return _loadCoreRecord(ref);
    }
  }

  Future<AssetDetailModel> _loadCoreRecord(AssetEntityRef ref) async {
    return switch (ref.kind) {
      AssetEntityKind.event => _eventDetail(
        ref,
        (await api.getJson('/api/events/${ref.id}') as Map)
            .cast<String, dynamic>(),
      ),
      AssetEntityKind.asset => _assetDetail(
        ref,
        (await api.getJson('/api/assets/${ref.id}') as Map)
            .cast<String, dynamic>(),
      ),
      AssetEntityKind.contact => throw StateError(
        'core contact details are unavailable',
      ),
    };
  }

  AssetDetailModel _eventDetail(
    AssetEntityRef ref,
    Map<String, dynamic> event,
  ) {
    final fields = <AssetDetailField>[
      _field('title', '标题', order: 0, required: true),
      _field('start_at', '开始', order: 1),
      _field('end_at', '结束', order: 2),
      _field('location', '地点', order: 3),
      _field('attendees', '参与人', order: 4),
      _field('description', '备注', order: 5, long: true),
    ];
    return _coreDetail(
      ref: ref,
      version: _version(event),
      skill: const AssetDetailSkill(
        id: null,
        machineName: 'event',
        displayName: '事件',
        icon: '📅',
      ),
      fields: fields,
      values: {
        for (final field in fields)
          field.id: field.id == 'attendees'
              ? _coreEventAttendees(event[field.id])
              : event[field.id],
      },
      primaryFieldId: 'title',
      secondaryFieldIds: const [
        'start_at',
        'end_at',
        'location',
        'attendees',
        'description',
      ],
      source: _coreSource(event),
    );
  }

  Future<AssetDetailModel> _assetDetail(
    AssetEntityRef ref,
    Map<String, dynamic> asset,
  ) async {
    final skillId = asset['user_skill_id']?.toString() ?? '';
    final skill = (await api.getJson('/api/user-skills/$skillId') as Map)
        .cast<String, dynamic>();
    final payload =
        (asset['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rawSchema =
        (skill['schema'] as Map?)?.cast<String, dynamic>() ?? const {};
    final schema =
        (rawSchema['properties'] as Map?)?.cast<String, dynamic>() ?? rawSchema;
    final isSchemaEnvelope = rawSchema['properties'] is Map;
    final hasDeclaredFields = schema.keys.any(
      (id) => !_coreMetadataFields.contains(id),
    );
    final isClosedSchema =
        hasDeclaredFields &&
        (isSchemaEnvelope ? rawSchema['additionalProperties'] == false : true);
    final requiredFields = (rawSchema['required'] as List? ?? const [])
        .map((value) => value.toString())
        .toSet();
    final machineName = skill['machine_name']?.toString() ?? 'asset';
    final fieldIds = machineName == 'todo'
        ? const <String>{'title', 'due_date', 'content', 'status'}
        : <String>{
            ...schema.keys.where((id) => !_coreMetadataFields.contains(id)),
            if (!isClosedSchema)
              ...payload.keys.where((id) => !_coreMetadataFields.contains(id)),
          };
    final fields = <AssetDetailField>[];
    var order = 0;
    for (final id in fieldIds) {
      final rawMetadata = schema[id];
      final metadata = rawMetadata is Map
          ? rawMetadata.cast<String, dynamic>()
          : null;
      fields.add(
        _field(
          id,
          _coreFieldLabel(machineName, id, metadata?['label']),
          type: metadata?['type']?.toString() ?? 'string',
          required:
              metadata?['required'] == true || requiredFields.contains(id),
          long:
              metadata?['long'] == true ||
              const {'content', 'description', 'notes', 'remark'}.contains(id),
          order: order++,
        ),
      );
    }
    final primary = const ['title', 'content', 'name'].firstWhere(
      (id) => _hasCoreValue(payload[id]),
      orElse: () {
        for (final field in fields) {
          if (_hasCoreValue(payload[field.id])) return field.id;
        }
        return fields.isEmpty ? 'content' : fields.first.id;
      },
    );
    final values = <String, dynamic>{
      for (final id in fieldIds)
        if (payload.containsKey(id)) id: payload[id],
    };
    if (machineName == 'todo' &&
        !_hasCoreValue(values['due_date']) &&
        _hasCoreValue(payload['occurred_at'])) {
      values['due_date'] = payload['occurred_at'];
    }
    return _coreDetail(
      ref: ref,
      version: _version(asset),
      skill: AssetDetailSkill(
        id: skillId.isEmpty ? null : skillId,
        machineName: machineName,
        displayName: skill['display_name']?.toString() ?? '资产',
        icon: _coreAssetIcon(machineName),
      ),
      fields: fields,
      values: values,
      primaryFieldId: primary,
      secondaryFieldIds: [
        for (final field in fields)
          if (field.id != primary) field.id,
      ],
      source: _coreSource(asset),
    );
  }

  @override
  Future<AssetDetailModel> save(
    AssetDetailModel current,
    Map<String, dynamic> valuesPatch,
  ) async {
    if (coreRecordsOnly) {
      switch (current.ref.kind) {
        case AssetEntityKind.asset:
          final latest =
              (await api.getJson('/api/assets/${current.ref.id}') as Map)
                  .cast<String, dynamic>();
          final payload = {
            ...(latest['payload'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{},
            ...valuesPatch,
          };
          final response = await api.patchJson(
            '/api/assets/${current.ref.id}',
            {'payload': payload},
          );
          return _assetDetail(
            current.ref,
            (response as Map).cast<String, dynamic>(),
          );
        case AssetEntityKind.event:
          final response = await api.patchJson(
            '/api/events/${current.ref.id}',
            valuesPatch,
          );
          return _eventDetail(
            current.ref,
            (response as Map).cast<String, dynamic>(),
          );
        case AssetEntityKind.contact:
          throw StateError('core contact updates are unavailable');
      }
    }
    final response = await api.putJson(_canonicalPath(current.ref), {
      'expected_version': current.version,
      'values_patch': valuesPatch,
    });
    return AssetDetailModel.fromJson((response as Map).cast<String, dynamic>());
  }

  @override
  Future<void> delete(AssetEntityRef ref) => api.deleteJson(switch (ref.kind) {
    AssetEntityKind.asset => '/api/assets/${ref.id}',
    AssetEntityKind.event => '/api/events/${ref.id}',
    AssetEntityKind.contact => '/api/contacts/${ref.id}',
  });

  String _canonicalPath(AssetEntityRef ref) =>
      '/api/asset-details/${ref.pathSegment}/${ref.id}';
}

AssetDetailModel _coreDetail({
  required AssetEntityRef ref,
  required String version,
  required AssetDetailSkill skill,
  required List<AssetDetailField> fields,
  required Map<String, dynamic> values,
  required String primaryFieldId,
  required List<String> secondaryFieldIds,
  AssetDetailSource source = const AssetDetailSource(
    kind: AssetDetailSourceKind.manual,
    label: '手动创建',
    sessionId: null,
    inputTurnId: null,
    reportId: null,
  ),
}) => AssetDetailModel(
  ref: ref,
  version: version,
  skill: skill,
  fields: List.unmodifiable(fields),
  values: Map.unmodifiable(values),
  display: AssetDetailDisplay(
    primaryFieldId: primaryFieldId,
    secondaryFieldIds: List.unmodifiable(secondaryFieldIds),
  ),
  source: source,
  capabilities: const AssetDetailCapabilities(editable: true, deletable: true),
);

AssetDetailField _field(
  String id,
  String label, {
  String type = 'string',
  bool required = false,
  bool long = false,
  required int order,
}) => AssetDetailField(
  id: id,
  label: label,
  type: type,
  required: required,
  long: long,
  order: order,
);

String _version(Map<String, dynamic> value) =>
    value['updated_at']?.toString() ??
    value['created_at']?.toString() ??
    'core-record';

String _fieldLabel(String id) => switch (id) {
  'title' => '标题',
  'content' => '内容',
  'name' => '名称',
  'due_date' => '截止时间',
  'status' => '状态',
  'description' => '描述',
  'notes' || 'remark' => '备注',
  _ => id,
};

String _coreFieldLabel(String machineName, String id, dynamic declaredLabel) {
  final label = declaredLabel?.toString().trim() ?? '';
  if (label.isNotEmpty) return label;
  if (machineName == 'expense') {
    return switch (id) {
      'amount' => '金额',
      'currency' => '币种',
      'category' => '类别',
      'merchant' => '商户',
      'date' => '日期',
      'description' => '描述',
      _ => _fieldLabel(id),
    };
  }
  return switch (id) {
    'tags' => '标签',
    'phone' => '电话',
    'company' => '公司',
    'email' => '邮箱',
    _ => _fieldLabel(id),
  };
}

bool _hasCoreValue(dynamic value) =>
    value != null && (value is! String || value.trim().isNotEmpty);

const _coreMetadataFields = {'period', 'occurred_at', 'domain'};

String _coreAssetIcon(String machineName) =>
    resolveMeta(machineName, const <String, SkillMeta>{}).icon;

List<Map<String, dynamic>> _coreEventAttendees(dynamic raw) => [
  for (final attendee in raw is List ? raw.whereType<Map>() : const <Map>[])
    attendee.cast<String, dynamic>(),
];

AssetDetailSource _coreSource(Map<String, dynamic> record) {
  final recordingId = record['source_recording_id']?.toString().trim() ?? '';
  final inputTurnId = record['source_input_turn_id']?.toString().trim() ?? '';
  if (recordingId.isNotEmpty) {
    final createdAt = DateTime.tryParse(
      record['created_at']?.toString() ?? '',
    )?.toLocal();
    final dateLabel = createdAt == null
        ? '闪念'
        : '${createdAt.month}月${createdAt.day}日闪念';
    return AssetDetailSource(
      kind: AssetDetailSourceKind.flash,
      label: '来自 $dateLabel',
      sessionId: recordingId,
      inputTurnId: inputTurnId.isEmpty ? null : inputTurnId,
      reportId: null,
    );
  }

  final reportId = record['source_report_id']?.toString().trim() ?? '';
  final actionId = record['source_report_action_id']?.toString().trim() ?? '';
  final reportTitle = record['source_report_title']?.toString().trim() ?? '';
  if (reportId.isNotEmpty || actionId.isNotEmpty || reportTitle.isNotEmpty) {
    final displayTitle = reportTitle.isEmpty ? '报告' : reportTitle;
    return AssetDetailSource(
      kind: AssetDetailSourceKind.report,
      label: '来自报告《$displayTitle》',
      sessionId: null,
      inputTurnId: null,
      reportId: reportId.isEmpty ? null : reportId,
    );
  }

  return const AssetDetailSource(
    kind: AssetDetailSourceKind.manual,
    label: '手动创建',
    sessionId: null,
    inputTurnId: null,
    reportId: null,
  );
}
