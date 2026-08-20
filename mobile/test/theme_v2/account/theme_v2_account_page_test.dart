import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eureka/api/auth_store.dart';
import 'package:eureka/auth/auth_controller.dart';
import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:eureka/theme_v2/account/theme_v2_account_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.token = null;
    AuthStore.userId = null;
  });

  testWidgets('deactivation entry uses 停用账户 wording without erasure claim', (
    tester,
  ) async {
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
        home: const ThemeV2AccountPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('停用账户'), findsOneWidget);
    expect(find.textContaining('永久删除'), findsNothing);

    await tester.tap(find.text('停用账户'));
    await tester.pumpAndSettle();

    expect(find.textContaining('登录权限会立即撤销'), findsOneWidget);
    expect(find.textContaining('业务数据会保留'), findsOneWidget);
    expect(find.textContaining('不提供自助恢复'), findsOneWidget);
    expect(find.textContaining('永久删除'), findsNothing);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.textContaining('登录权限会立即撤销'), findsNothing);
  });
}
