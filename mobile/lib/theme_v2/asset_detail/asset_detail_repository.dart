import '../../api/api_client.dart';
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
  ApiAssetDetailRepository(this.api);

  final ApiClient api;

  @override
  Future<AssetDetailModel> load(AssetEntityRef ref) async {
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
      _field('description', '备注', order: 4, long: true),
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
      values: event,
      primaryFieldId: 'title',
      secondaryFieldIds: const [
        'start_at',
        'end_at',
        'location',
        'description',
      ],
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
    final schema =
        (skill['schema'] as Map?)?.cast<String, dynamic>() ?? const {};
    final fieldIds = <String>{...schema.keys, ...payload.keys};
    final fields = <AssetDetailField>[];
    var order = 0;
    for (final id in fieldIds) {
      final metadata = (schema[id] as Map?)?.cast<String, dynamic>();
      fields.add(
        _field(
          id,
          metadata?['label']?.toString() ?? _fieldLabel(id),
          type: metadata?['type']?.toString() ?? 'string',
          required: metadata?['required'] == true,
          long:
              metadata?['long'] == true ||
              const {'content', 'description', 'notes', 'remark'}.contains(id),
          order: order++,
        ),
      );
    }
    final primary = const ['title', 'content', 'name'].firstWhere(
      payload.containsKey,
      orElse: () => fields.isEmpty ? 'content' : fields.first.id,
    );
    return _coreDetail(
      ref: ref,
      version: _version(asset),
      skill: AssetDetailSkill(
        id: skillId.isEmpty ? null : skillId,
        machineName: skill['machine_name']?.toString() ?? 'asset',
        displayName: skill['display_name']?.toString() ?? '资产',
        icon: '•',
      ),
      fields: fields,
      values: payload,
      primaryFieldId: primary,
      secondaryFieldIds: [
        for (final field in fields)
          if (field.id != primary) field.id,
      ],
    );
  }

  @override
  Future<AssetDetailModel> save(
    AssetDetailModel current,
    Map<String, dynamic> valuesPatch,
  ) async {
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
  source: const AssetDetailSource(
    kind: AssetDetailSourceKind.manual,
    label: '手动创建',
    sessionId: null,
    inputTurnId: null,
  ),
  capabilities: const AssetDetailCapabilities(editable: false, deletable: true),
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
