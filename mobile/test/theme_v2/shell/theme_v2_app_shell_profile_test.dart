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

  testWidgets('logo opens the full account page', (tester) async {
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

    // The wordmark is the account entry point; no separate profile button exists.
    expect(find.bySemanticsLabel('UReka logo'), findsOneWidget);
    expect(find.bySemanticsLabel('个人中心'), findsNothing);

    await tester.tap(find.bySemanticsLabel('UReka logo'));
    await tester.pumpAndSettle();

    expect(find.text('账户'), findsNWidgets(2));
    expect(find.text('修改密码'), findsOneWidget);
    expect(find.text('导出数据'), findsOneWidget);
    expect(find.text('停用账户'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
  });

  testWidgets('account page shows the persisted account email', (tester) async {
    SharedPreferences.setMockInitialValues({
      'eureka_token': 'test-token',
      'eureka_email': 'm6ui@test.com',
      'eureka_user_id': 'user-1',
      'eureka_onboarding_status': 'skipped',
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

    await tester.tap(find.bySemanticsLabel('UReka logo'));
    await tester.pumpAndSettle();
    expect(find.text('m6ui@test.com'), findsOneWidget);
  });
}
