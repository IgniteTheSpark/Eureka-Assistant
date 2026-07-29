import 'package:eureka/theme_v2/asset_detail/markdown_field_editor.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Markdown field preserves raw syntax across Edit and Preview', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeV2Theme(Brightness.light),
        home: Scaffold(
          body: MarkdownFieldEditor(label: '备注', controller: controller),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('markdown-editor-input')),
      '# 标题\n\n- 第一项',
    );
    await tester.tap(find.text('预览'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('markdown-editor-preview')),
      findsOneWidget,
    );
    expect(find.text('标题', findRichText: true), findsOneWidget);
    expect(find.text('第一项', findRichText: true), findsOneWidget);

    await tester.tap(find.text('编辑'));
    await tester.pump();
    expect(controller.text, '# 标题\n\n- 第一项');
    final input = tester.widget<TextField>(
      find.byKey(const ValueKey('markdown-editor-input')),
    );
    expect(input.minLines, 9);
    expect(input.maxLines, isNull);
  });
}
