import 'dart:async';

import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_tokens.dart';
import 'package:eureka/theme_v2/inbox/reka_inbox_controller.dart';
import 'package:eureka/theme_v2/inbox/reka_inbox_page.dart';
import 'package:eureka/theme_v2/shell/device_status_summary.dart';
import 'package:eureka/theme_v2/shell/theme_v2_app_shell.dart';
import 'package:eureka/theme_v2/shell/theme_v2_global_top_nav.dart';
import 'package:eureka/theme_v2/shell/theme_v2_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('loading empty error and retry are explicit structural states', (
    tester,
  ) async {
    final repository = _PageRepository()..fail = true;
    final loadGate = Completer<void>();
    repository.loadGate = loadGate.future;
    final controller = RekaInboxController(repository: repository);
    await _pump(tester, RekaInboxPage(controller: controller, autoLoad: false));

    unawaited(controller.load());
    await tester.pump();
    expect(find.text('正在接收 REKA 信号'), findsOneWidget);

    loadGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('暂时无法加载 Inbox'), findsOneWidget);
    expect(find.bySemanticsLabel('重试 Inbox'), findsOneWidget);

    repository.fail = false;
    await tester.tap(find.bySemanticsLabel('重试 Inbox'));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法加载 Inbox'), findsNothing);
    expect(find.text('提醒 one'), findsOneWidget);
  });

  testWidgets('ready page exposes data-backed unread and outcome actions', (
    tester,
  ) async {
    final repository = _PageRepository();
    final controller = RekaInboxController(repository: repository);
    await controller.load();
    await _pump(tester, RekaInboxPage(controller: controller, autoLoad: false));

    expect(find.text('REKA Inbox'), findsOneWidget);
    expect(find.text('2 条未读'), findsOneWidget);
    expect(find.bySemanticsLabel('标记 提醒 one 为已读'), findsOneWidget);
    expect(find.bySemanticsLabel('执行 提醒 one'), findsOneWidget);
    expect(find.bySemanticsLabel('忽略 提醒 two'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('标记 提醒 one 为已读'));
    await tester.pumpAndSettle();
    expect(controller.itemById('one')?.status, 'seen');
    expect(find.text('1 条未读'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('忽略 提醒 two'));
    await tester.pumpAndSettle();
    expect(controller.itemById('two')?.status, 'dismissed');
    expect(find.text('全部已读'), findsWidgets);
  });

  testWidgets('double tap execute launches the downstream action once', (
    tester,
  ) async {
    final repository = _ControlledPageRepository();
    final controller = RekaInboxController(repository: repository);
    await controller.load();
    var actions = 0;
    await _pump(
      tester,
      RekaInboxPage(
        controller: controller,
        autoLoad: false,
        onAct: (_) => actions++,
      ),
    );

    final execute = find.bySemanticsLabel('执行 提醒 one');
    await tester.tap(execute);
    await tester.tap(execute);
    await tester.pump();
    expect(repository.outcomeCalls, 1);

    repository.outcomeGate.complete();
    await tester.pumpAndSettle();
    expect(actions, 1);
  });

  testWidgets('partial empty data keeps retry reachable', (tester) async {
    final controller = RekaInboxController(
      repository: _PartialEmptyRepository(),
    );
    await controller.load();
    await _pump(tester, RekaInboxPage(controller: controller, autoLoad: false));

    expect(find.text('部分 Inbox 暂不可用'), findsOneWidget);
    expect(find.bySemanticsLabel('重试 Inbox'), findsOneWidget);
    expect(find.text('Inbox 已清空'), findsNothing);
  });

  testWidgets('all actions have 44px targets and 360 width does not overflow', (
    tester,
  ) async {
    final controller = RekaInboxController(repository: _PageRepository());
    await controller.load();
    await _pump(
      tester,
      RekaInboxPage(controller: controller, autoLoad: false),
      size: const Size(360, 800),
    );

    for (final label in [
      '返回',
      '标记全部已读',
      '标记 提醒 one 为已读',
      '执行 提醒 one',
      '忽略 提醒 one',
    ]) {
      final target = find.bySemanticsLabel(label);
      expect(target, findsOneWidget, reason: label);
      final size = tester.getSize(target);
      expect(size.width, greaterThanOrEqualTo(44), reason: label);
      expect(size.height, greaterThanOrEqualTo(44), reason: label);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('top nav badge count and label come from controller data', (
    tester,
  ) async {
    await _pump(
      tester,
      ThemeV2GlobalTopNav(
        deviceStatus: const DeviceStatusSummary.disconnected(),
        unreadNotificationCount: 3,
        onDeviceSelected: (_) {},
        onNotificationsPressed: () {},
      ),
    );

    expect(find.text('3'), findsOneWidget);
    final semantics = tester.getSemantics(find.bySemanticsLabel('通知，3 条未读'));
    expect(semantics.flagsCollection.isButton, isTrue);
  });

  testWidgets('Theme V2 shell bell opens the shared inbox route', (
    tester,
  ) async {
    final controller = RekaInboxController(repository: _PageRepository());
    await controller.load(includeOffers: false);
    await _pump(
      tester,
      ThemeV2AppShell(
        inboxController: controller,
        showStartupOverlays: false,
        pages: const [
          ThemeV2PageScaffold(body: _Body()),
          ThemeV2PageScaffold(body: _Body()),
          ThemeV2PageScaffold(body: _Body()),
        ],
      ),
    );

    await tester.tap(find.bySemanticsLabel('通知，2 条未读'));
    await tester.pumpAndSettle();

    expect(find.byType(RekaInboxPage), findsOneWidget);
    final routeTheme = Theme.of(tester.element(find.byType(RekaInboxPage)));
    expect(routeTheme.extension<ThemeV2Tokens>(), isNotNull);
  });

  testWidgets('Inbox route follows ambient light and dark theme changes', (
    tester,
  ) async {
    final controller = RekaInboxController(repository: _PageRepository());
    await controller.load(includeOffers: false);
    final brightness = ValueNotifier(Brightness.light);
    addTearDown(brightness.dispose);
    await _pump(
      tester,
      ValueListenableBuilder<Brightness>(
        valueListenable: brightness,
        builder: (context, value, _) => MaterialApp(
          theme: ThemeData(brightness: value),
          home: ThemeV2AppShell(
            inboxController: controller,
            showStartupOverlays: false,
            pages: const [
              ThemeV2PageScaffold(body: _Body()),
              ThemeV2PageScaffold(body: _Body()),
              ThemeV2PageScaffold(body: _Body()),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('通知，2 条未读'));
    await tester.pumpAndSettle();
    var routeTheme = Theme.of(tester.element(find.text('REKA Inbox')));
    expect(routeTheme.brightness, Brightness.light);
    expect(
      routeTheme.extension<ThemeV2Tokens>()?.background,
      ThemeV2Tokens.light.background,
    );

    brightness.value = Brightness.dark;
    await tester.pumpAndSettle();
    routeTheme = Theme.of(tester.element(find.text('REKA Inbox')));
    expect(routeTheme.brightness, Brightness.dark);
    expect(
      routeTheme.extension<ThemeV2Tokens>()?.background,
      ThemeV2Tokens.dark.background,
    );
  });
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _PageRepository implements RekaInboxRepository {
  bool fail = false;
  Future<void>? loadGate;
  final outcomes = <(String, String)>[];

  @override
  Future<List<Map<String, dynamic>>> loadPending() async {
    await loadGate;
    if (fail) throw StateError('offline');
    return [_pageRow('one', 'pending'), _pageRow('two', 'delivered')];
  }

  @override
  Future<List<Map<String, dynamic>>> loadRecent() async {
    await loadGate;
    if (fail) throw StateError('offline');
    return [_pageRow('done', 'acted')];
  }

  @override
  Future<List<Map<String, dynamic>>> loadOffers() async {
    await loadGate;
    if (fail) throw StateError('offline');
    return const [];
  }

  @override
  Future<void> outcome(String id, String status) async {
    outcomes.add((id, status));
  }
}

class _PartialEmptyRepository implements RekaInboxRepository {
  @override
  Future<List<Map<String, dynamic>>> loadPending() async => const [];

  @override
  Future<List<Map<String, dynamic>>> loadRecent() async {
    throw StateError('recent unavailable');
  }

  @override
  Future<List<Map<String, dynamic>>> loadOffers() async => const [];

  @override
  Future<void> outcome(String id, String status) async {}
}

class _ControlledPageRepository extends _PageRepository {
  final outcomeGate = Completer<void>();
  var outcomeCalls = 0;

  @override
  Future<void> outcome(String id, String status) {
    outcomeCalls++;
    return outcomeGate.future;
  }
}

Map<String, dynamic> _pageRow(String id, String status) => {
  'id': id,
  'type': 'nudge',
  'kind': 'overdue',
  'text': '提醒 $id',
  'body': '这是 $id 的详细说明',
  'ref': 'todo:$id',
  'cta': 'view',
  'status': status,
  'created_at': '2026-07-28T02:00:00Z',
};

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(411, 960),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: buildThemeV2Theme(Brightness.light),
      home: Scaffold(body: SafeArea(child: child)),
    ),
  );
}
