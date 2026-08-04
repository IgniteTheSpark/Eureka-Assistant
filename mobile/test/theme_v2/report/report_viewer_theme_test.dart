import 'package:eureka/pages/report_viewer_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Theme V2 viewer leaves report-owned palette CSS untouched', () {
    const html =
        '<html><head><title>Report</title></head><body>Body</body></html>';

    final themed = applyThemeV2ReportViewerTheme(html, palette: 'pal-warm');

    expect(themed, html);
  });

  test('Theme V2 action capability is independent from legacy rerender', () {
    const page = ReportViewerPage(
      title: '报告',
      html: '<html></html>',
      reportId: 'report-1',
      enableLegacyEnhancements: false,
      enableThemeV2Actions: true,
      themeV2Palette: 'pal-ink',
    );

    expect(page.enableLegacyEnhancements, isFalse);
    expect(page.enableThemeV2Actions, isTrue);
    expect(page.themeV2Palette, 'pal-ink');
  });
}
