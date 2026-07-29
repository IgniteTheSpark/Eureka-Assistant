import 'package:eureka/theme_v2/asset_detail/asset_text_value.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'short text keeps natural height and has no expansion affordance',
    (tester) async {
      await tester.pumpWidget(
        _host(
          AssetTextValue(
            text: '这是一段短备注。',
            markdown: false,
            full: false,
            onExpand: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final natural = find.byKey(const ValueKey('asset-text-natural'));
      expect(natural, findsOneWidget);
      expect(tester.getSize(natural).height, lessThan(120));
      expect(find.text('展开全文'), findsNothing);
    },
  );

  testWidgets(
    'overflowing plain text offers expansion only after real layout',
    (tester) async {
      var expanded = false;
      await tester.pumpWidget(
        _host(
          AssetTextValue(
            text: List.filled(24, '这是会在实际宽度下超过六行的纯文本内容。').join(),
            markdown: false,
            full: false,
            onExpand: () => expanded = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('asset-text-collapsed')),
        findsOneWidget,
      );
      expect(find.text('展开全文'), findsOneWidget);
      await tester.tap(find.text('展开全文'));
      expect(expanded, isTrue);
    },
  );

  testWidgets('overflowing Markdown renders grammar and offers expansion', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AssetTextValue(
          text:
              '# 标题\n\n- 第一项\n- 第二项\n\n> 引用\n\n'
              '${List.filled(18, '继续补充完整观察。').join()}',
          markdown: true,
          full: false,
          onExpand: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('标题', findRichText: true), findsOneWidget);
    expect(find.text('第一项', findRichText: true), findsOneWidget);
    expect(find.text('展开全文'), findsOneWidget);
  });

  testWidgets(
    'full short value stays natural while long value gets local scroll',
    (tester) async {
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              AssetTextValue(
                text: '完整但很短。',
                markdown: true,
                full: true,
                onExpand: () {},
              ),
              AssetTextValue(
                text: [
                  for (var index = 0; index < 80; index++) '第 $index 行内容',
                  '最后一句唯一内容',
                ].join('\n'),
                markdown: true,
                full: true,
                onExpand: () {},
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('asset-text-natural')), findsOneWidget);
      final region = find.byKey(const ValueKey('asset-text-full-scroll'));
      expect(region, findsOneWidget);
      expect(tester.getSize(region).height, 480);
      expect(
        find.descendant(
          of: region,
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('最后一句唯一内容', findRichText: true),
        findsOneWidget,
      );
    },
  );
}

Widget _host(Widget child) => MaterialApp(
  theme: buildThemeV2Theme(Brightness.light),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(width: 371, child: child),
    ),
  ),
);
