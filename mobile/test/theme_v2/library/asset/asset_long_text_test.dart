import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/library/asset/asset_long_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('half state omits expansion affordance for short text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(AssetLongText(text: '这是一段短随记。', expanded: false, onExpand: () {})),
    );

    expect(find.byKey(const ValueKey('asset-long-text-half')), findsOneWidget);
    expect(find.text('查看全部'), findsNothing);
    expect(find.byKey(const ValueKey('asset-long-text-fade')), findsNothing);
  });

  testWidgets('half state caps long content at 120 and offers expansion', (
    tester,
  ) async {
    var expanded = false;
    await tester.pumpWidget(
      _host(
        AssetLongText(
          text: List.filled(20, '这是需要完整展开的长文本内容。').join(),
          expanded: false,
          onExpand: () => expanded = true,
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('asset-long-text-half'))).height,
      120,
    );
    expect(find.byKey(const ValueKey('asset-long-text-fade')), findsOneWidget);
    await tester.tap(find.text('查看全部'));
    expect(expanded, isTrue);
  });

  testWidgets('full state uses a selectable local scroll region', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 960);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        AssetLongText(
          text: List.generate(80, (index) => '第 $index 行内容').join('\n'),
          expanded: true,
          onExpand: () {},
        ),
      ),
    );

    final region = find.byKey(const ValueKey('asset-long-text-full'));
    expect(region, findsOneWidget);
    expect(
      find.descendant(of: region, matching: find.byType(SelectableText)),
      findsOneWidget,
    );
    expect(tester.getSize(region).height, 480);
    expect(
      find.descendant(of: region, matching: find.byType(SingleChildScrollView)),
      findsOneWidget,
    );
  });
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
