import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eureka/api/auth_store.dart';
import 'package:eureka/auth/auth_controller.dart';
import 'package:eureka/pages/login_page.dart';
import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';

http.Client _stubBackend({int registerStatus = 200}) {
  Map<String, dynamic> _json(Object body) =>
      jsonDecode(body as String) as Map<String, dynamic>;
  http.Response _ok([Map<String, dynamic>? extra]) => http.Response(
        jsonEncode({'ok': true, ...?extra}),
        200,
        headers: {'content-type': 'application/json'},
      );
  return MockClient((request) async {
    final path = request.url.path;
    if (path == '/api/auth/config') {
      return http.Response(
        jsonEncode({
          'terms_url': 'https://example.com/terms',
          'privacy_url': 'https://example.com/privacy',
          'terms_version': '2026-08-v1',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path == '/api/auth/verification-codes') {
      final purpose = _json(request.body)['purpose'];
      return _ok({
        'resend_delay_seconds': 60,
        'expires_in_seconds': 600,
        'purpose': purpose,
      });
    }
    if (path == '/api/auth/password-reset') {
      return _ok();
    }
    if (path == '/api/auth/register') {
      if (registerStatus != 200) {
        return http.Response(
          jsonEncode({'detail': '服务条款已更新，请阅读并同意最新版本后重试'}),
          registerStatus,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'ok': true,
          'token': 'token-1',
          'user': {
            'id': 'u1',
            'email': 'alice@example.com',
            'onboarding_status': 'pending',
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return _ok();
  });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.token = null;
    AuthStore.userId = null;
    AuthController.clientOverride = _stubBackend;
  });

  tearDown(() {
    AuthController.clientOverride = null;
  });

  Future<void> _openForgetPassword(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: const LoginPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('登录你的账号'), findsOneWidget);
    await tester.tap(find.text('忘记密码？'));
    await tester.pumpAndSettle();
  }

  testWidgets('forgot password flow reaches reset UI with all fields', (
    tester,
  ) async {
    await _openForgetPassword(tester);

    expect(find.text('忘记密码？'), findsOneWidget);
    expect(find.text('重置密码'), findsOneWidget);
    expect(find.text('获取验证码'), findsOneWidget);
    expect(find.text('返回登录'), findsOneWidget);
    expect(find.text('密码要求'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(4));
  });

  testWidgets(
    'forgot password flow: email -> reset code -> new password + confirm -> back to login',
    (tester) async {
      await _openForgetPassword(tester);

      await tester.enterText(find.byType(TextField).at(0), 'alice@example.com');
      await tester.tap(find.text('获取验证码'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('验证码已发送'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(1), '123456');
      await tester.enterText(find.byType(TextField).at(2), 'Newpass456!');
      await tester.enterText(find.byType(TextField).at(3), 'Newpass456!');

      await tester.ensureVisible(find.text('重置密码'));
      await tester.tap(find.text('重置密码'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('登录你的账号'), findsOneWidget);
      expect(find.text('密码已重置，请使用新密码登录'), findsOneWidget);
      expect(find.text('登录'), findsOneWidget);
      expect(find.text('重置密码'), findsNothing);
    },
  );

  testWidgets(
    'forgot password blocks empty fields, weak password, and mismatch locally',
    (tester) async {
      await _openForgetPassword(tester);

      await tester.ensureVisible(find.text('重置密码'));
      await tester.tap(find.text('重置密码'));
      await tester.pump();
      expect(find.text('请输入邮箱、验证码和密码'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'alice@example.com');
      await tester.enterText(find.byType(TextField).at(1), '123456');
      await tester.enterText(find.byType(TextField).at(2), 'weakpass1');
      await tester.enterText(find.byType(TextField).at(3), 'weakpass1');
      await tester.ensureVisible(find.text('重置密码'));
      await tester.tap(find.text('重置密码'));
      await tester.pump();
      expect(find.text('密码未满足下方全部要求'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(2), 'Newpass456!');
      await tester.enterText(find.byType(TextField).at(3), 'Mismatch456!');
      await tester.ensureVisible(find.text('重置密码'));
      await tester.tap(find.text('重置密码'));
      await tester.pump();
      expect(find.text('两次输入的密码不一致'), findsOneWidget);
    },
  );

  testWidgets('register surfaces server-authoritative stale-terms rejection', (
    tester,
  ) async {
    AuthController.clientOverride = () => _stubBackend(registerStatus: 409);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildEurekaTheme(EurekaColors.light),
        home: const LoginPage(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('还没有账号？去注册'));
    await tester.pumpAndSettle();
    expect(find.text('创建账号'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'alice@example.com');
    await tester.tap(find.text('获取验证码'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.byType(TextField).at(1), '123456');
    await tester.enterText(find.byType(TextField).at(2), 'Secret123!');
    await tester.enterText(find.byType(TextField).at(3), 'Secret123!');
    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    await tester.ensureVisible(find.text('注册并进入'));
    await tester.tap(find.text('注册并进入'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('服务条款已更新，请阅读并同意最新版本后重试'), findsOneWidget);
  });
}
