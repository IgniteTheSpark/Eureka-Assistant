import 'package:shared_preferences/shared_preferences.dart';

import 'package:eureka/api/auth_store.dart';
import 'package:eureka/auth/auth_controller.dart';
import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:eureka/theme_v2/shell/device_status_summary.dart';
import 'package:eureka/theme_v2/shell/theme_v2_app_shell.dart';
import 'package:eureka/theme_v2/shell/theme_v2_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.token = null;
    AuthStore.userId = null;
  });

  testWidgets('profile button opens account sheet with logout entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: ThemeV2AppShell(
          showStartupOverlays: false,
          deviceStatus: const DeviceStatusSummary.disconnected(),
          pages: const [
            ThemeV2PageScaffold(body: Text('today')),
            ThemeV2PageScaffold(body: Text('calendar')),
            ThemeV2PageScaffold(body: Text('library')),
          ],
        ),
      ),
    );

    // Top nav exposes the profile action.
    expect(find.bySemanticsLabel('个人中心'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('个人中心'));
    await tester.pumpAndSettle();

    // Account sheet shows the account label + logout entry.
    expect(find.text('Eureka 账号'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);

    // Dismiss the sheet without triggering the platform-heavy logout path.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('退出登录'), findsNothing);
  });

  testWidgets('tapping 退出登录 dismisses the account sheet', (tester) async {
    // Seed a logged-in session so the sheet shows the real account email.
    SharedPreferences.setMockInitialValues({
      'eureka_token': 'test-token',
      'eureka_email': 'm6ui@test.com',
      'eureka_user_id': 'user-1',
    });
    AuthStore.token = 'test-token';
    AuthStore.userId = 'user-1';
    await AuthController.instance.load();
    expect(AuthController.instance.isAuthed, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: ThemeV2AppShell(
          showStartupOverlays: false,
          deviceStatus: const DeviceStatusSummary.disconnected(),
          pages: const [
            ThemeV2PageScaffold(body: Text('today')),
            ThemeV2PageScaffold(body: Text('calendar')),
            ThemeV2PageScaffold(body: Text('library')),
          ],
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('个人中心'));
    await tester.pumpAndSettle();
    expect(find.text('m6ui@test.com'), findsOneWidget);

    // The onTap pops the sheet synchronously, then fires the platform-heavy
    // logout() cleanup chain (BLE teardown etc.). That chain needs real device
    // platform channels + the google_fonts HTTP fetch, neither available in a
    // widget test, so the widget contract under test is limited to: tapping
    // 退出登录 dismisses the account sheet. (Session clearing itself is
    // AuthController's own responsibility, covered by real-device QA.)
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    expect(find.text('退出登录'), findsNothing);
    expect(find.text('m6ui@test.com'), findsNothing);
  });
}