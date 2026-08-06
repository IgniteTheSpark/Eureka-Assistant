import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eureka/api/auth_store.dart';
import 'package:eureka/app_events.dart';
import 'package:eureka/auth/auth_controller.dart';
import 'package:eureka/ble_flash/ble_flash_manager.dart';
import 'package:eureka/ble_flash/ble_flash_overlay.dart';
import 'package:eureka/main.dart';
import 'package:eureka/widgets/listening_overlay.dart';

void main() {
  testWidgets('unauthenticated app shows the login gate', (tester) async {
    SharedPreferences.setMockInitialValues({});
    AuthStore.token = null;
    AuthStore.userId = null;
    await AuthController.instance.load();

    await tester.pumpWidget(const ProviderScope(child: EurekaApp()));
    await tester.pumpAndSettle();

    expect(find.text('登录你的账号'), findsOneWidget);
    expect(find.text('用百智登录'), findsNothing);
  });

  testWidgets('hardware flags do not mount legacy full-screen overlays', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    AuthStore.token = null;
    AuthStore.userId = null;
    await AuthController.instance.load();
    listeningNotifier.value = true;
    BleFlashManager.instance.isFlashing.value = true;
    addTearDown(() {
      listeningNotifier.value = false;
      BleFlashManager.instance.isFlashing.value = false;
    });

    await tester.pumpWidget(const ProviderScope(child: EurekaApp()));
    await tester.pump();

    expect(find.byType(GlobalListeningOverlay), findsNothing);
    expect(find.byType(BleFlashOverlay), findsNothing);
  });
}
