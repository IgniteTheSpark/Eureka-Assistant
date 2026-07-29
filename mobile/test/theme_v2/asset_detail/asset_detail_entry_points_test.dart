import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all production asset details use the canonical Theme V2 launcher', () {
    const forbidden = [
      'showAssetDetail(',
      'showThemeV2AssetDetail(',
      'render/asset_detail_sheet.dart',
    ];
    final violations = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final pattern in forbidden) {
        if (source.contains(pattern)) {
          violations.add('${entity.path}: $pattern');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('every known detail entry point imports the canonical launcher', () {
    const entryPoints = [
      'lib/app_events.dart',
      'lib/pages/calendar_page.dart',
      'lib/pages/notifications_page.dart',
      'lib/render/skill_card.dart',
      'lib/today/bubble_pool.dart',
      'lib/today/next_action.dart',
      'lib/theme_v2/library/theme_v2_library_page.dart',
      'lib/theme_v2/library/asset/asset_list_page.dart',
    ];
    final missing = <String>[];
    for (final path in entryPoints) {
      if (!File(path).readAsStringSync().contains('open_asset_detail.dart')) {
        missing.add(path);
      }
    }
    expect(missing, isEmpty, reason: missing.join('\n'));
  });
}
