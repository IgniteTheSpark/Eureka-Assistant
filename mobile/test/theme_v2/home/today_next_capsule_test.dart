import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/home/today_next_capsule.dart';
import 'package:eureka/today/today_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('countdown rounds a positive partial minute up', () {
    expect(
      todayCountdownLabel(
        DateTime(2026, 8, 14, 14, 30),
        DateTime(2026, 8, 14, 14, 29, 40),
      ),
      '1 分钟后',
    );
    expect(
      todayCountdownLabel(
        DateTime(2026, 8, 14, 15, 50),
        DateTime(2026, 8, 14, 14, 29, 40),
      ),
      '1 小时 21 分钟后',
    );
  });

  test('next group excludes the displayed minute and groups equal minutes', () {
    final now = DateTime(2026, 8, 14, 14, 30);
    final group = todayNextGroup([
      _item('current', '当前事项', DateTime(2026, 8, 14, 14, 30, 40)),
      _item('next-a', '下一项', DateTime(2026, 8, 14, 15)),
      _item('next-b', '同分钟事项', DateTime(2026, 8, 14, 15, 0, 40)),
      _item('later', '更晚事项', DateTime(2026, 8, 14, 16)),
      _item('untimed', '无时间待办', DateTime(2026, 8, 14, 17), timed: false),
    ], now);

    expect(group.map((item) => item.id), ['next-a', 'next-b']);
  });

  test('next group filters unsupported kinds and sorts event before todo', () {
    final now = DateTime(2026, 8, 14, 9);
    final at = DateTime(2026, 8, 14, 10, 30);
    final group = todayNextGroup([
      _item('todo', '提交方案', at, kind: 'todo'),
      _item('note', '会议笔记', at, kind: 'note'),
      _item('event', '周会', at, kind: 'event'),
    ], now);

    expect(group.map((item) => item.id), ['event', 'todo']);
    expect(todayNextSummary(group), '周会、提交方案');
  });

  testWidgets('capsule advances at the exact minute and opens Agenda', (
    tester,
  ) async {
    final clock = ValueNotifier(DateTime(2026, 8, 14, 14, 29, 40));
    addTearDown(clock.dispose);
    var opened = 0;
    await tester.pumpWidget(
      _host(
        TodayNextCapsule(
          items: [
            _item('first', '产品方向同步', DateTime(2026, 8, 14, 14, 30)),
            _item('second', '下一项', DateTime(2026, 8, 14, 16)),
          ],
          now: clock.value,
          clock: clock,
          onOpenAgenda: () => opened++,
        ),
      ),
    );

    expect(find.text('产品方向同步'), findsOneWidget);
    expect(find.text('1 分钟后'), findsOneWidget);
    expect(find.text('进行中'), findsNothing);

    clock.value = DateTime(2026, 8, 14, 14, 30);
    await tester.pump();
    expect(find.text('产品方向同步'), findsNothing);
    expect(find.text('下一项'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('today-next-schedule')));
    expect(opened, 1);
  });

  testWidgets('same-minute banner is right aligned and summarizes two titles', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 14, 10);
    final at = DateTime(2026, 8, 14, 14);
    await tester.pumpWidget(
      _host(
        TodayNextCapsule(
          items: [
            _item('a-todo', '提交方案', at, kind: 'todo'),
            _item('event', '周会', at, kind: 'event'),
            _item('z-todo', '客户沟通', at, kind: 'todo'),
          ],
          now: now,
          onOpenAgenda: () {},
        ),
      ),
    );

    expect(find.text('14:00 · 3 项'), findsOneWidget);
    expect(find.text('周会、提交方案 +1'), findsOneWidget);
    final title = tester.widget<Text>(find.text('周会、提交方案 +1'));
    expect(title.textAlign, TextAlign.right);
  });

  testWidgets('empty capsule keeps its target and opens Agenda', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      _host(
        TodayNextCapsule(
          items: const [],
          now: DateTime(2026, 8, 14, 10),
          onOpenAgenda: () => opened++,
        ),
      ),
    );

    expect(find.text('今天暂无安排'), findsOneWidget);
    expect(find.byKey(const ValueKey('today-next-schedule')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('today-next-schedule'))).height,
      greaterThanOrEqualTo(44),
    );
    await tester.tap(find.byKey(const ValueKey('today-next-schedule')));
    expect(opened, 1);
  });
}

ChainItem _item(
  String id,
  String title,
  DateTime at, {
  String kind = 'event',
  bool timed = true,
}) => ChainItem(kind: kind, id: id, title: title, at: at, timed: timed);

Widget _host(Widget child) => MaterialApp(
  theme: buildThemeV2Theme(Brightness.light),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topRight,
      child: SizedBox(width: 220, height: 80, child: child),
    ),
  ),
);
