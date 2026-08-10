import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/pages/notifications_page.dart';
import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('notification rows use a meaningful icon for every known type', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final notifications = <Map<String, dynamic>>[
      _notification('flash_done', '闪念已整理'),
      _notification('report_available', '发现一份可生成的报告'),
      _notification('report_plan_ready', '报告方案已准备好'),
      _notification('report_done', '报告已生成'),
      _notification('report_failed', '报告生成失败'),
      _notification('reminder', '日程即将开始'),
      _notification('task_done', '代办已完成'),
      _notification('task_failed', '代办处理失败'),
      _notification('nudge', 'Reka 提醒'),
      _notification('unknown', '普通通知'),
    ];
    final api = ApiClient(
      baseUrl: 'https://notifications.test',
      enableLogging: false,
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(jsonEncode({'notifications': notifications, 'unread': 0})),
          200,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: NotificationsPage(api: api),
      ),
    );
    await tester.pumpAndSettle();

    for (final icon in <IconData>[
      Icons.bolt_rounded,
      Icons.auto_awesome_outlined,
      Icons.fact_check_outlined,
      Icons.insert_chart_outlined_rounded,
      Icons.error_outline_rounded,
      Icons.notifications_active_outlined,
      Icons.check_circle_outline_rounded,
      Icons.warning_amber_rounded,
      Icons.lightbulb_outline_rounded,
      Icons.notifications_none_outlined,
    ]) {
      expect(find.byIcon(icon), findsOneWidget, reason: icon.toString());
    }
    expect(find.text('•'), findsNothing);
  });
}

Map<String, dynamic> _notification(String type, String title) => {
  'id': type,
  'type': type,
  'title': title,
  'body': '$title 的说明',
  'link': '',
  'read': true,
  'created_at': '2026-08-09T08:00:00Z',
};
