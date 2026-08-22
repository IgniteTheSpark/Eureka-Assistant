import 'package:eureka/pages/report_viewer_page.dart';
import 'package:eureka/api/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'private report illustrations are inlined before WebView load',
    () async {
      const html =
          '<figure id="reka-report-illustration" class="r-illustration" '
          'data-illustration-status="ready"><img '
          'src="/api/files/file-1" alt="报告插图" loading="lazy"></figure>';

      final prepared = await inlinePrivateReportImages(
        html,
        (_) async => const ApiBinaryResponse(
          bytes: [0xff, 0xd8, 0xff],
          contentType: 'image/jpeg',
        ),
      );

      expect(prepared, contains('src="data:image/jpeg;base64,/9j/"'));
      expect(prepared, isNot(contains('/api/files/file-1')));
    },
  );

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
      initialIllustrationStatus: 'pending',
      initialRevision: 1,
    );

    expect(page.enableLegacyEnhancements, isFalse);
    expect(page.enableThemeV2Actions, isTrue);
    expect(page.themeV2Palette, 'pal-ink');
    expect(page.initialIllustrationStatus, 'pending');
    expect(page.initialRevision, 1);
  });

  test('late illustration patch accepts only the renderer-owned slot', () {
    const trusted =
        '<figure id="reka-report-illustration" class="r-illustration" '
        'data-illustration-status="ready"><img src="/api/files/file-1" '
        'alt="报告插图" loading="lazy"></figure>';
    const external =
        '<figure id="reka-report-illustration" class="r-illustration" '
        'data-illustration-status="ready"><img src="https://evil.test/x" '
        'alt="报告插图" loading="lazy"></figure>';

    expect(
      extractTrustedReportIllustrationSlot('<main>$trusted</main>'),
      trusted,
    );
    expect(extractTrustedReportIllustrationSlot(external), isNull);
    expect(extractTrustedReportIllustrationSlot('$trusted$trusted'), isNull);
  });

  test('viewer chrome follows the exact report-owned palette', () {
    expect(
      reportViewerChromePalette('pal-minimal').background,
      const Color(0xFFF6F5F1),
    );
    expect(
      reportViewerChromePalette('pal-warm').background,
      const Color(0xFFF3ECE0),
    );
    expect(
      reportViewerChromePalette('pal-dashboard').background,
      const Color(0xFF0C1118),
    );
    expect(
      reportViewerChromePalette('pal-neon').background,
      const Color(0xFF06070F),
    );
    expect(
      reportViewerChromePalette('pal-ink').background,
      const Color(0xFF14130F),
    );
    expect(
      reportViewerChromePalette('pal-forest').background,
      const Color(0xFF0C1410),
    );
  });

  test('report citations open only external http links', () async {
    Uri? opened;

    expect(isExternalReportUrl('https://example.com/research'), isTrue);
    expect(isExternalReportUrl('http://example.com/research'), isTrue);
    expect(isExternalReportUrl('javascript:alert(1)'), isFalse);
    expect(isExternalReportUrl('file:///private/report'), isFalse);
    expect(
      await openExternalReportUrl(
        'https://example.com/research',
        launcher: (uri) async {
          opened = uri;
          return true;
        },
      ),
      isTrue,
    );
    expect(opened, Uri.parse('https://example.com/research'));
  });
}
