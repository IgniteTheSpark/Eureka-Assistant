import 'package:eureka/assets/assets.dart';
import 'package:eureka/theme_v2/library/asset/asset_detail_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('asset detail presentation', () {
    for (final kind in const [
      'todo',
      'notes',
      'event',
      'contact',
      'tennis_match',
      'unknown_custom_skill',
    ]) {
      test('$kind always starts in the bottom sheet', () {
        expect(
          initialAssetDetailPresentation(kind),
          AssetDetailPresentationKind.bottomSheet,
        );
      });
    }

    test('presentation is not inferred from the skill name', () {
      expect(
        initialAssetDetailPresentation('todo'),
        initialAssetDetailPresentation('unknown_custom_skill'),
      );
    });
  });

  group('AssetItem effective time', () {
    test('parses authoritative effective_at separately from created_at', () {
      final item = AssetItem.fromJson({
        'id': 'a1',
        'user_skill_id': 'skill-1',
        'user_skill_name': 'tennis_match',
        'payload': {'played_on': '2026-07-02'},
        'effective_at': '2026-07-02T00:00:00+08:00',
        'created_at': '2026-07-28T09:00:00+08:00',
        'occurred_at': '2026-07-02T00:00:00+08:00',
        'period': '上午',
      });

      expect(item.userSkillId, 'skill-1');
      expect(item.effectiveAt.day, 2);
      expect(item.createdAt.day, 28);
      expect(item.occurredAt?.day, 2);
      expect(item.period, '上午');
    });

    test('compatibility fallback is occurred_at then created_at', () {
      final occurred = AssetItem.fromJson({
        'created_at': '2026-07-28T09:00:00+08:00',
        'occurred_at': '2026-07-03T14:30:00+08:00',
      });
      final created = AssetItem.fromJson({
        'created_at': '2026-07-28T09:00:00+08:00',
      });

      expect(occurred.effectiveAt.day, 3);
      expect(created.effectiveAt.day, 28);
    });

    test('accepts the legacy structured-query skill_name key', () {
      final item = AssetItem.fromJson({
        'skill_name': 'legacy_custom',
        'created_at': '2026-07-28T09:00:00+08:00',
      });

      expect(item.skillName, 'legacy_custom');
    });
  });
}
