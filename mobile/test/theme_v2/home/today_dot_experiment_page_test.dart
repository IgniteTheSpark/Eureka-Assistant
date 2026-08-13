import 'package:eureka/theme_v2/home/today_dot_matrix_scene.dart';
import 'package:eureka/theme_v2/home/today_reka_quick_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('scene exposes a quiet living Reka with a 64 px hotspot', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _Host(child: TodayDotMatrixScene(refreshEmphasis: 0, onRekaTap: () {})),
    );

    final reka = find.bySemanticsLabel('Reka 快捷操作');
    expect(reka, findsOneWidget);
    expect(tester.getSize(reka).width, greaterThanOrEqualTo(64));
    expect(tester.getSize(reka).height, greaterThanOrEqualTo(64));
    expect(find.text('今天很安静，我在这里。'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);

    semantics.dispose();
  });

  testWidgets('quick actions invoke only the selected callback', (
    tester,
  ) async {
    final counts = <TodayRekaAction, int>{
      for (final action in TodayRekaAction.values) action: 0,
    };

    for (final selected in TodayRekaAction.values) {
      await tester.pumpWidget(
        _Host(
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTodayRekaQuickActions(
                context,
                anchor: const Rect.fromLTWH(32, 420, 64, 64),
                onCreateAsset: () => counts[TodayRekaAction.createAsset] =
                    counts[TodayRekaAction.createAsset]! + 1,
                onCreateReport: () => counts[TodayRekaAction.createReport] =
                    counts[TodayRekaAction.createReport]! + 1,
                onStartChat: () => counts[TodayRekaAction.startChat] =
                    counts[TodayRekaAction.startChat]! + 1,
              ),
              child: const Text('打开菜单'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开菜单'));
      await tester.pumpAndSettle();
      expect(find.text('创建资产'), findsOneWidget);
      expect(find.text('创建报告'), findsOneWidget);
      expect(find.text('开始新聊天'), findsOneWidget);

      await tester.tap(find.text(selected.label));
      await tester.pumpAndSettle();

      for (final action in TodayRekaAction.values) {
        expect(counts[action], action == selected ? 1 : 0);
      }
      counts[selected] = 0;
    }
  });
}

class _Host extends StatelessWidget {
  const _Host({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(411, 860),
          devicePixelRatio: 1,
          disableAnimations: true,
          textScaler: TextScaler.noScaling,
        ),
        child: Scaffold(body: child),
      ),
    );
  }
}
