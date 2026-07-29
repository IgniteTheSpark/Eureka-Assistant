import 'package:eureka/render/render_spec.dart';
import 'package:eureka/theme_v2/asset/asset_card_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CardDisplayConfig', () {
    test('prefers canonical card_display and normalizes secondary order', () {
      final config = CardDisplayConfig.fromRenderSpec({
        'primary_field': 'legacy_title',
        'secondary_field': 'legacy_subtitle',
        'card_display': {
          'primary_field_id': 'opponent',
          'secondary_field_ids': [
            'score',
            'venue',
            'score',
            'opponent',
            '',
            'result',
            'ignored',
          ],
        },
      });

      expect(config.primaryFieldId, 'opponent');
      expect(config.secondaryFieldIds, ['score', 'venue', 'result']);
    });

    test('projects legacy secondary and meta fields into one order', () {
      final config = CardDisplayConfig.fromRenderSpec({
        'primary_field': 'title',
        'secondary_field': 'summary',
        'meta_fields': [
          {'field': 'date'},
          {'field': 'location'},
          {'field': 'date'},
        ],
      });

      expect(config.primaryFieldId, 'title');
      expect(config.secondaryFieldIds, ['summary', 'date', 'location']);
    });

    test(
      'writes canonical and legacy projections without dropping other keys',
      () {
        final config = CardDisplayConfig(
          primaryFieldId: 'opponent',
          secondaryFieldIds: ['score', 'venue', 'result'],
        );

        final output = config.applyToRenderSpec({
          'icon': '🎾',
          'actions': ['edit'],
          'primary_field': 'old',
          'primary_format': 'old_format',
          'secondary_field': 'score',
          'secondary_format': 'badge',
          'meta_fields': [
            {'field': 'venue', 'format': 'text'},
            {'field': 'result', 'format': 'badge'},
          ],
        });

        expect(output['card_display'], {
          'primary_field_id': 'opponent',
          'secondary_field_ids': ['score', 'venue', 'result'],
        });
        expect(output['primary_field'], 'opponent');
        expect(output.containsKey('primary_format'), isFalse);
        expect(output['secondary_field'], 'score');
        expect(output['secondary_format'], 'badge');
        expect(output['meta_fields'], [
          {'field': 'venue', 'format': 'text'},
          {'field': 'result', 'format': 'badge'},
        ]);
        expect(output['icon'], '🎾');
        expect(output['actions'], ['edit']);
      },
    );
  });

  group('AssetCardViewData', () {
    test('projects formatted primary and three nonblank secondary values', () {
      const spec = RenderSpec(
        cardLayout: 'horizontal',
        icon: '🎾',
        accentColor: 'neutral',
        primaryField: 'opponent',
        secondaryField: 'played_at',
        secondaryFormat: 'absolute_date',
        metaFields: [
          MetaFieldSpec('score', null),
          MetaFieldSpec('venue', null),
        ],
      );

      final data = AssetCardViewData.fromPayload(
        payload: const {
          'opponent': 'Kevin',
          'played_at': '2026-07-02',
          'score': '4–1',
          'venue': '深云体育公园',
        },
        display: CardDisplayConfig(
          primaryFieldId: 'opponent',
          secondaryFieldIds: ['played_at', 'score', 'venue'],
        ),
        spec: spec,
        skillLabel: '网球对局',
        timeLabel: '21:34',
      );

      expect(data.mark, '🎾');
      expect(data.primaryValue, 'Kevin');
      expect(data.secondaryValues, ['7月2日', '4–1', '深云体育公园']);
      expect(data.timeLabel, '21:34');
    });

    test('skips blanks and falls back to skill label for primary', () {
      final data = AssetCardViewData.fromPayload(
        payload: const {'title': ' ', 'status': null, 'location': '会议室'},
        display: CardDisplayConfig(
          primaryFieldId: 'title',
          secondaryFieldIds: ['status', 'location'],
        ),
        spec: null,
        skillLabel: '事件',
        timeLabel: ' ',
      );

      expect(data.mark, '•');
      expect(data.primaryValue, '事件');
      expect(data.secondaryValues, ['会议室']);
      expect(data.timeLabel, isNull);
    });
  });
}
