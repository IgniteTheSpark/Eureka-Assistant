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
}
