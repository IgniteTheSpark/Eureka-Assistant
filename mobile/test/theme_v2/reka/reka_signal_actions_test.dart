import 'dart:async';

import 'package:eureka/theme_v2/asset_detail/asset_detail_model.dart';
import 'package:eureka/theme_v2/asset_detail/asset_detail_repository.dart';
import 'package:eureka/theme_v2/asset_detail/asset_entity_ref.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/reka/reka_signal_actions.dart';
import 'package:eureka/theme_v2/reka/reka_signal_repository.dart';
import 'package:eureka/today/today_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'overdue target opens canonical todo detail with snooze context',
    (tester) async {
      final reka = _FakeRekaRepository();
      final asset = _FakeAssetRepository(
        AssetDetailModel.fromJson(_todoEnvelope()),
      );
      final item = TodayRekaItem(
        id: 'overdue-1',
        type: 'overdue',
        title: '提交方案已逾期',
        body: '需要处理',
        link: '',
        createdAt: DateTime(2026, 8, 14, 10),
        naturalKey: 'overdue:todo-1:2026-08-14T01:00:00Z',
        targetType: 'asset',
        targetId: 'todo-1',
        actions: ['open', 'snooze', 'dismiss'],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildThemeV2Theme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => unawaited(
                  openRekaSignalTarget(
                    context,
                    item,
                    repository: reka,
                    assetRepository: asset,
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('asset-detail-overdue-reminder')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('overdue-snooze-15')));
      await tester.pumpAndSettle();
      expect(reka.snoozedSignalId, 'overdue-1');
      expect(reka.snoozedUntil, isNotNull);
    },
  );
}

class _FakeRekaRepository implements RekaSignalRepository {
  String? snoozedSignalId;
  DateTime? snoozedUntil;

  @override
  Future<void> completeTodo(String assetId) async {}

  @override
  Future<void> dismiss(String signalId) async {}

  @override
  Future<RekaSignalBatch> load({String timezoneName = 'Asia/Shanghai'}) {
    throw UnimplementedError();
  }

  @override
  Future<void> snooze(String signalId, DateTime remindAgainAt) async {
    snoozedSignalId = signalId;
    snoozedUntil = remindAgainAt;
  }
}

class _FakeAssetRepository implements AssetDetailRepository {
  const _FakeAssetRepository(this.model);

  final AssetDetailModel model;

  @override
  Future<void> delete(AssetEntityRef ref) async {}

  @override
  Future<AssetDetailModel> load(AssetEntityRef ref) async => model;

  @override
  Future<AssetDetailModel> save(
    AssetDetailModel current,
    Map<String, dynamic> valuesPatch,
  ) async => current;
}

Map<String, dynamic> _todoEnvelope() => {
  'entity': {'kind': 'asset', 'id': 'todo-1', 'version': 'version-1'},
  'skill': {
    'id': 'skill-todo',
    'machine_name': 'todo',
    'display_name': '待办',
    'icon': '☑',
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
  'values': {
    'title': '提交方案',
    'due_date': '2026-08-14T09:00:00+08:00',
    'status': 'pending',
  },
  'display': {'primary_field_id': 'title', 'secondary_field_ids': <String>[]},
  'source': {'kind': 'manual', 'label': '手动创建'},
  'capabilities': {'editable': true, 'deletable': true},
};
