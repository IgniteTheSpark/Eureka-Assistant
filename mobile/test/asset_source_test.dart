import 'package:eureka/theme_v2/asset_detail/asset_detail_model.dart';
import 'package:eureka/theme_v2/asset_detail/asset_detail_repository.dart';
import 'package:eureka/theme_v2/asset_detail/asset_entity_ref.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/library/asset/asset_detail_presentation.dart';
import 'package:eureka/theme_v2/library/asset/asset_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('manual assets identify their canonical non-clickable source', (
    tester,
  ) async {
    final model = AssetDetailModel.fromJson(_manualEnvelope());
    final controller = AssetDetailController(
      repository: _SourceRepository(model),
      ref: model.ref,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: Scaffold(body: ThemeV2AssetDetailSurface(controller)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('手动创建'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });
}

class _SourceRepository implements AssetDetailRepository {
  const _SourceRepository(this.model);

  final AssetDetailModel model;

  @override
  Future<AssetDetailModel> load(AssetEntityRef ref) async => model;

  @override
  Future<AssetDetailModel> save(
    AssetDetailModel current,
    Map<String, dynamic> valuesPatch,
  ) async => current;

  @override
  Future<void> delete(AssetEntityRef ref) async {}
}

Map<String, dynamic> _manualEnvelope() => {
  'entity': {'kind': 'asset', 'id': 'asset-1', 'version': 'version-1'},
  'skill': {
    'id': 'skill-1',
    'machine_name': 'todo',
    'display_name': '待办',
    'icon': '📋',
  },
  'fields': [
    {
      'id': 'title',
      'label': '标题',
      'type': 'string',
      'required': true,
      'long': false,
      'order': 0,
    },
  ],
  'values': {'title': '手动创建待办'},
  'display': {'primary_field_id': 'title', 'secondary_field_ids': <String>[]},
  'source': {
    'kind': 'manual',
    'label': '手动创建',
    'session_id': null,
    'input_turn_id': null,
  },
  'capabilities': {'editable': true, 'deletable': true},
};
