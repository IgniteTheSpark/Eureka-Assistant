import 'package:flutter_test/flutter_test.dart';
import 'package:eureka/today/today_data.dart';
import 'package:eureka/today/today_summary.dart';

void main() {
  PoolAsset a(String id, String type, String title, DateTime at,
          [Map<String, dynamic>? p]) =>
      PoolAsset(
          id: id,
          type: type,
          domain: '生活',
          title: title,
          payload: p ?? const {},
          createdAt: at);

  final pool = [
    a('e1', 'expense', '麦当劳', DateTime(2026, 6, 22, 12, 30), {'amount': 45}),
    a('e2', 'expense', '瑞幸', DateTime(2026, 6, 22, 15, 20), {'amount': 88}),
    a('r1', 'running', '晨跑3km', DateTime(2026, 6, 22, 7, 0)),
    a('r2', 'running', '夜跑5km', DateTime(2026, 6, 22, 20, 0)),
  ];

  group('summaryFor', () {
    test('记账 specialized: sum + max + count', () {
      final s = summaryFor('expense', pool);
      expect(s.metric, '¥133');
      expect(s.sub, '最大 ¥88 · 共 2 笔');
    });

    test('custom/other type: latest one, no aggregation', () {
      final s = summaryFor('running', pool);
      expect(s.title, '夜跑5km'); // latest by createdAt (20:00)
      expect(s.metric, '');
    });

    test('全部: count + latest preview', () {
      final s = summaryFor('all', pool);
      expect(s.metric, '共 4 条');
      expect(s.sub, '最新:夜跑5km');
    });

    test('empty', () {
      expect(summaryFor('expense', const []).metric, '');
    });
  });
}
