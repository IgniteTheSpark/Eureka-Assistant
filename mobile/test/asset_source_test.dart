import 'package:eureka/render/asset_detail_sheet.dart';
import 'package:eureka/render/render_spec.dart';
import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('manual assets identify Quick Create as their source', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAssetDetail(
                context,
                data: const CardData(
                  layout: 'horizontal',
                  icon: '📋',
                  accentColor: 'blue',
                  title: '手动创建待办',
                  subtitle: '',
                  metaFields: [],
                ),
                payload: const {'title': '手动创建待办', 'content': '从快创建立'},
                cardType: 'todo',
              ),
              child: const Text('打开详情'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();

    expect(find.text('来自「快创」'), findsOneWidget);
  });
}
