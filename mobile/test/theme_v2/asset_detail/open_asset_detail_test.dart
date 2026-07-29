import 'package:eureka/theme_v2/asset_detail/asset_detail_model.dart';
import 'package:eureka/theme_v2/asset_detail/asset_detail_repository.dart';
import 'package:eureka/theme_v2/asset_detail/asset_entity_ref.dart';
import 'package:eureka/theme_v2/asset_detail/open_asset_detail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'launcher loads once and expansion preserves the same detail state',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(411, 960);
      addTearDown(tester.view.reset);
      final repository = _FakeRepository(_model);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => openAssetDetail(
                  context,
                  const AssetEntityRef(
                    kind: AssetEntityKind.asset,
                    id: 'asset-1',
                  ),
                  repository: repository,
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(repository.loads, 1);
      expect(find.text('宝贝饮食'), findsWidgets);
      expect(
        find.byKey(const ValueKey('theme-v2-asset-sheet')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('asset-detail-expand')));
      await tester.pumpAndSettle();
      expect(repository.loads, 1);
      expect(
        find.byKey(const ValueKey('theme-v2-asset-full-page')),
        findsOneWidget,
      );
    },
  );
}

class _FakeRepository implements AssetDetailRepository {
  _FakeRepository(this.model);

  final AssetDetailModel model;
  int loads = 0;

  @override
  Future<AssetDetailModel> load(AssetEntityRef ref) async {
    loads++;
    return model;
  }

  @override
  Future<AssetDetailModel> save(
    AssetDetailModel current,
    Map<String, dynamic> valuesPatch,
  ) async => current;

  @override
  Future<void> delete(AssetEntityRef ref) async {}
}

final _model = AssetDetailModel.fromJson({
  'entity': {'kind': 'asset', 'id': 'asset-1', 'version': 'version-1'},
  'skill': {
    'id': 'skill-1',
    'machine_name': 'baby_meal',
    'display_name': '宝贝饮食',
    'icon': '🍼',
  },
  'fields': [
    {
      'id': 'meal',
      'label': '饮食',
      'type': 'string',
      'required': true,
      'long': false,
      'order': 0,
    },
  ],
  'values': {'meal': '小米粥'},
  'display': {'primary_field_id': 'meal', 'secondary_field_ids': <String>[]},
  'source': {
    'kind': 'manual',
    'label': '手动创建',
    'session_id': null,
    'input_turn_id': null,
  },
  'capabilities': {'editable': true, 'deletable': true},
});
