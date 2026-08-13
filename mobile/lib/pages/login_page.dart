import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../auth/auth_controller.dart';
import '../config.dart';
import 'ring_debug_page.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';

enum _AuthMode { login, register, forgot }

/// Email + password login / register / password-reset gate (§4 / §5.5).
/// Registration now requires a 6-digit email verification code.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const bool _showBaizhiLogin = bool.fromEnvironment(
    'SHOW_BAIZHI_LOGIN',
    defaultValue: false,
  );

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _code = TextEditingController();
  _AuthMode _mode = _AuthMode.login;
  bool _busy = false;
  bool _busyBaizhi = false; // §13.1 百智 OAuth in flight
  bool _requestingCode = false;
  int _cooldown = 0; // resend countdown (seconds)
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _code.dispose();
    super.dispose();
  }

  String? _validateInputs() {
    final email = _email.text.trim();
    final pw = _password.text;
    if (_mode == _AuthMode.forgot) {
      if (email.isEmpty) return '请输入邮箱';
      if (pw.isEmpty) return '请输入新密码';
      if (pw.length < 8) return '密码至少 8 位';
      if (_code.text.isEmpty) return '请输入验证码';
      return null;
    }
    if (email.isEmpty || pw.isEmpty) return '请输入邮箱和密码';
    if (_mode == _AuthMode.register) {
      if (pw.length < 8) return '密码至少 8 位';
      if (_confirm.text != pw) return '两次输入的密码不一致';
      if (_code.text.isEmpty) return '请先获取并输入验证码';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final validationError = _validateInputs();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = AuthController.instance;
    final email = _email.text.trim();
    final pw = _password.text;
    String? err;
    switch (_mode) {
      case _AuthMode.login:
        err = await auth.login(email, pw);
      case _AuthMode.register:
        err = await auth.register(email, _code.text.trim(), pw);
      case _AuthMode.forgot:
        err = await auth.resetPassword(email, _code.text.trim(), pw);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err; // null = success → gate rebuilds away from here
    });
    if (err == null && _mode == _AuthMode.forgot) {
      _switchMode(_AuthMode.login);
    }
  }

  Future<void> _requestCode() async {
    if (_busy || _requestingCode || _cooldown > 0) return;
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = '请输入邮箱');
      return;
    }
    setState(() {
      _requestingCode = true;
      _error = null;
    });
    final purpose = _mode == _AuthMode.register ? 'register' : 'password_reset';
    final err = await AuthController.instance.requestVerificationCode(
      email,
      purpose,
    );
    if (!mounted) return;
    setState(() {
      _requestingCode = false;
      _error = err;
      if (err == null) _cooldown = 60;
    });
    if (err == null) {
      _startCooldown();
    }
  }

  void _startCooldown() {
    Future.doWhile(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _cooldown = _cooldown > 0 ? _cooldown - 1 : 0);
      return _cooldown > 0;
    });
  }

  void _switchMode(_AuthMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
      _code.clear();
    });
  }

  /// §13.1 — 用百智登录 (OAuth). Backend mediates; we only get the Eureka JWT back.
  Future<void> _submitBaizhi() async {
    if (_busy || _busyBaizhi) return;
    setState(() {
      _busyBaizhi = true;
      _error = null;
    });
    final err = await AuthController.instance.loginWithBaizhi();
    if (!mounted) return;
    setState(() {
      _busyBaizhi = false;
      if (err != null && err.isNotEmpty) _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final title = switch (_mode) {
      _AuthMode.login => '登录你的账号',
      _AuthMode.register => '创建账号',
      _AuthMode.forgot => '重置密码',
    };
    final submitLabel = switch (_mode) {
      _AuthMode.login => '登录',
      _AuthMode.register => '注册并进入',
      _AuthMode.forgot => '重置密码',
    };
    return Scaffold(
      backgroundColor: eu.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SvgPicture.asset(
                  eu.brightness == Brightness.dark
                      ? 'assets/logo/eureka_lockup_white.svg'
                      : 'assets/logo/eureka_lockup.svg',
                  height: 92,
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: eu.textMid, fontSize: 15),
                ),
                const SizedBox(height: 28),
                _field(eu, _email, '邮箱', TextInputType.emailAddress, false),
                const SizedBox(height: 12),
                _field(
                  eu,
                  _password,
                  _mode == _AuthMode.forgot ? '新密码（至少 8 位）' : '密码',
                  TextInputType.visiblePassword,
                  true,
                  onSubmit: (_) => _submit(),
                ),
                if (_mode == _AuthMode.register) ...[
                  const SizedBox(height: 12),
                  _field(eu, _confirm, '确认密码', TextInputType.visiblePassword, true),
                ],
                if (_mode != _AuthMode.login) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          eu,
                          _code,
                          '6 位验证码',
                          TextInputType.number,
                          false,
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 50,
                        child: TextButton(
                          onPressed: (_requestingCode || _cooldown > 0)
                              ? null
                              : _requestCode,
                          style: TextButton.styleFrom(
                            backgroundColor: eu.surfaceRaised,
                            foregroundColor: eu.brand,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: eu.border),
                            ),
                          ),
                          child: Text(
                            _requestingCode
                                ? '发送中…'
                                : _cooldown > 0
                                    ? '${_cooldown}s'
                                    : '获取验证码',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: eu.accentRed, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: _busy ? null : _submit,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: eu.brand,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: _busy
                          ? null
                          : [
                              BoxShadow(
                                color: eu.brand.withValues(alpha: 0.16),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            submitLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_mode == _AuthMode.login)
                  Center(
                    child: TextButton(
                      onPressed: () => _switchMode(_AuthMode.forgot),
                      child: Text(
                        '忘记密码？',
                        style: TextStyle(color: eu.textMid, fontSize: 13),
                      ),
                    ),
                  ),
                if (_showBaizhiLogin && _mode == _AuthMode.login) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: Divider(color: eu.border, height: 1)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '或',
                          style: TextStyle(color: eu.textLo, fontSize: 12),
                        ),
                      ),
                      Expanded(child: Divider(color: eu.border, height: 1)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  GestureDetector(
                    onTap: (_busy || _busyBaizhi) ? null : _submitBaizhi,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: eu.surfaceRaised,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: eu.border),
                      ),
                      child: _busyBaizhi
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: eu.brand,
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.badge_outlined,
                                  size: 18,
                                  color: eu.textHi,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '用百智登录',
                                  style: TextStyle(
                                    color: eu.textHi,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (_mode != _AuthMode.login)
                  Center(
                    child: TextButton(
                      onPressed: () => _switchMode(_AuthMode.login),
                      child: Text(
                        '返回登录',
                        style: TextStyle(color: eu.textMid, fontSize: 13),
                      ),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: _busy
                        ? null
                        : () => _switchMode(_AuthMode.register),
                    behavior: HitTestBehavior.opaque,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '还没有账号？',
                            style: TextStyle(color: eu.textMid, fontSize: 13),
                          ),
                          TextSpan(
                            text: '去注册',
                            style: TextStyle(
                              color: eu.brand,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (AppConfig.showRingDebug) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RingDebugPage()),
                    ),
                    icon: const Icon(Icons.bluetooth_audio_outlined, size: 18),
                    label: const Text('[Debug] Ring 调试（免登录）'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    EurekaColors eu,
    TextEditingController c,
    String hint,
    TextInputType type,
    bool obscure, {
    ValueChanged<String>? onSubmit,
  }) {
    return TextField(
      controller: c,
      keyboardType: type,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: obscure ? TextInputAction.go : TextInputAction.next,
      onSubmitted: onSubmit,
      style: TextStyle(color: eu.textHi, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: eu.textLo),
        filled: true,
        fillColor: eu.surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: eu.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: eu.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: eu.brand),
        ),
      ),
    );
  }
}
