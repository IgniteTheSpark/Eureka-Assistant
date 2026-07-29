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
    final response = await api.getJson(_canonicalPath(ref));
    return AssetDetailModel.fromJson((response as Map).cast<String, dynamic>());
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
