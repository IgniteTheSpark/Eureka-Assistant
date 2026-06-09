import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../auth/auth_controller.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';

/// Email + password login / register gate. On success the auth gate in main.dart
/// rebuilds into the app shell.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false; // false = login, true = register
  bool _busy = false;
  bool _busyBaizhi = false; // §13.1 百智 OAuth in flight
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final email = _email.text.trim();
    final pw = _password.text;
    if (email.isEmpty || pw.isEmpty) {
      setState(() => _error = '请输入邮箱和密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = AuthController.instance;
    final err = _register ? await auth.register(email, pw) : await auth.login(email, pw);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err; // null = success → gate rebuilds away from here
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
      // null = success (gate rebuilds away); '' = user cancelled (stay silent);
      // else show the message.
      if (err != null && err.isNotEmpty) _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
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
                // Full brand lockup (gradient mark + wordmark). White variant on
                // dark backgrounds, gradient variant on light.
                SvgPicture.asset(
                  eu.brightness == Brightness.dark
                      ? 'assets/logo/eureka_lockup_white.svg'
                      : 'assets/logo/eureka_lockup.svg',
                  height: 92,
                ),
                const SizedBox(height: 10),
                Text(_register ? '创建账号' : '登录你的账号',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: eu.textMid, fontSize: 15)),
                const SizedBox(height: 28),
                _field(eu, _email, '邮箱', TextInputType.emailAddress, false),
                const SizedBox(height: 12),
                _field(eu, _password, '密码', TextInputType.visiblePassword, true,
                    onSubmit: (_) => _submit()),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: eu.accentRed, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: _busy ? null : _submit,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [eu.brand, eu.accentPurple]),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: _busy
                          ? null
                          : [
                              BoxShadow(
                                  color: eu.brand.withValues(alpha: 0.4),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6))
                            ],
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_register ? '注册并进入' : '登录',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 18),
                // 「或」divider.
                Row(children: [
                  Expanded(child: Divider(color: eu.border, height: 1)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('或', style: TextStyle(color: eu.textLo, fontSize: 12)),
                  ),
                  Expanded(child: Divider(color: eu.border, height: 1)),
                ]),
                const SizedBox(height: 18),
                // §13.1 用百智登录 (OAuth) — 持卡用户已有百智账号。
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
                            child: CircularProgressIndicator(strokeWidth: 2, color: eu.brand))
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.badge_outlined, size: 18, color: eu.textHi),
                            const SizedBox(width: 8),
                            Text('用百智登录',
                                style: TextStyle(
                                    color: eu.textHi, fontSize: 15, fontWeight: FontWeight.w600)),
                          ]),
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _busy
                      ? null
                      : () => setState(() {
                            _register = !_register;
                            _error = null;
                          }),
                  behavior: HitTestBehavior.opaque,
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: _register ? '已有账号？' : '还没有账号？',
                          style: TextStyle(color: eu.textMid, fontSize: 13)),
                      TextSpan(
                          text: _register ? '去登录' : '去注册',
                          style: TextStyle(
                              color: eu.brand, fontSize: 13, fontWeight: FontWeight.w700)),
                    ]),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(EurekaColors eu, TextEditingController c, String hint,
      TextInputType type, bool obscure,
      {ValueChanged<String>? onSubmit}) {
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: eu.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: eu.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: eu.brand)),
      ),
    );
  }
}
