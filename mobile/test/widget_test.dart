import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eureka/api/auth_store.dart';
import 'package:eureka/auth/auth_controller.dart';
import 'package:eureka/main.dart';

void main() {
  testWidgets('unauthenticated app shows the login gate', (tester) async {
    SharedPreferences.setMockInitialValues({});
    AuthStore.token = null;
    AuthStore.userId = null;
    await AuthController.instance.load();

    await tester.pumpWidget(const ProviderScope(child: EurekaApp()));
    await tester.pumpAndSettle();

    expect(find.text('登录你的账号'), findsOneWidget);
    expect(find.text('用百智登录'), findsOneWidget);
  });
}
