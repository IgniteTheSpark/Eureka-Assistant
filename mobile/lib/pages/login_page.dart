import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/auth_controller.dart';
import '../config.dart';
import 'ring_debug_page.dart';
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
  static final _uppercasePattern = RegExp(r'[A-Z]');
  static final _lowercasePattern = RegExp(r'[a-z]');
  static final _digitPattern = RegExp(r'[0-9]');
  static final _safeSymbolPattern = RegExp(r'[!@#$%^&*._+=?-]');
  static final _allowedPasswordPattern = RegExp(
    r'^[A-Za-z0-9!@#$%^&*._+=?-]*$',
  );

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirmation = TextEditingController();
  final _verificationCode = TextEditingController();
  bool _register = false; // false = login, true = register
  bool _forgotPassword = false; // password-reset mode
  bool _busy = false;
  bool _codeBusy = false;
  int _codeCooldown = 0;
  String? _error;
  String? _notice;
  String _termsUrl = '';
  String _privacyUrl = '';
  String _termsVersion = '';
  bool _termsAccepted = false;
  Timer? _codeTimer;

  String get _passwordValue => _password.text;
  bool get _passwordLengthValid =>
      _passwordValue.length >= 8 && _passwordValue.length <= 128;
  bool get _passwordHasUppercase => _uppercasePattern.hasMatch(_passwordValue);
  bool get _passwordHasLowercase => _lowercasePattern.hasMatch(_passwordValue);
  bool get _passwordHasDigit => _digitPattern.hasMatch(_passwordValue);
  bool get _passwordHasSafeSymbol =>
      _safeSymbolPattern.hasMatch(_passwordValue);
  bool get _passwordCharactersValid =>
      _allowedPasswordPattern.hasMatch(_passwordValue);
  bool get _passwordPolicyValid =>
      _passwordLengthValid &&
      _passwordHasUppercase &&
      _passwordHasLowercase &&
      _passwordHasDigit &&
      _passwordHasSafeSymbol &&
      _passwordCharactersValid;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordConfirmation.dispose();
    _verificationCode.dispose();
    _codeTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadAuthConfig();
  }

  Future<void> _loadAuthConfig() async {
    final config = await AuthController.instance.loadAuthConfig();
    if (!mounted) return;
    setState(() {
      _termsUrl = config['terms_url'] ?? '';
      _privacyUrl = config['privacy_url'] ?? '';
      _termsVersion = config['terms_version'] ?? '';
    });
  }

  Future<void> _openLegalUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https') return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _requestVerificationCode() async {
    if (_codeBusy || _codeCooldown > 0) return;
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = '请先输入邮箱');
      return;
    }
    setState(() {
      _codeBusy = true;
      _error = null;
      _notice = null;
    });
    final error = await AuthController.instance.requestVerificationCode(
      email,
      _forgotPassword ? 'password_reset' : 'register',
    );
    if (!mounted) return;
    setState(() {
      _codeBusy = false;
      _error = error;
      _notice = error == null ? '验证码已发送' : null;
    });
    if (error == null) _startCodeCooldown();
  }

  void _startCodeCooldown() {
    _codeTimer?.cancel();
    setState(() => _codeCooldown = 60);
    _codeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_codeCooldown <= 1) {
        timer.cancel();
        setState(() => _codeCooldown = 0);
        return;
      }
      setState(() => _codeCooldown--);
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final email = _email.text.trim();
    final pw = _password.text;
    final code = _verificationCode.text.trim();
    final needsCode = _register || _forgotPassword;
    if (email.isEmpty || pw.isEmpty || (needsCode && code.isEmpty)) {
      setState(() {
        _error = needsCode ? '请输入邮箱、验证码和密码' : '请输入邮箱和密码';
      });
      return;
    }
    if (needsCode && !_passwordPolicyValid) {
      setState(() => _error = '密码未满足下方全部要求');
      return;
    }
    if (needsCode && pw != _passwordConfirmation.text) {
      setState(() => _error = '两次输入的密码不一致');
      return;
    }
    if (_register && (!_termsAccepted || _termsVersion.isEmpty)) {
      setState(() => _error = '请先阅读并同意服务条款和隐私政策');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    final auth = AuthController.instance;
    final String? err;
    if (_register) {
      err = await auth.register(
        email,
        code,
        pw,
        termsVersion: _termsVersion,
        termsAccepted: _termsAccepted,
      );
    } else if (_forgotPassword) {
      err = await auth.resetPassword(email, code, pw);
    } else {
      err = await auth.login(email, pw);
    }
    if (!mounted) return;
    if (_forgotPassword && err == null) {
      _codeTimer?.cancel();
      setState(() {
        _busy = false;
        _forgotPassword = false;
        _register = false;
        _codeCooldown = 0;
        _error = null;
        _notice = '密码已重置，请使用新密码登录';
        _email.clear();
        _verificationCode.clear();
        _password.clear();
        _passwordConfirmation.clear();
      });
      return;
    }
    setState(() {
      _busy = false;
      _error = err; // null = success → gate rebuilds away from here
    });
  }

  void _switchMode(bool register) {
    setState(() {
      _register = register;
      _forgotPassword = false;
      _error = null;
      _notice = null;
    });
  }

  void _enterForgotMode() {
    setState(() {
      _forgotPassword = true;
      _register = false;
      _error = null;
      _notice = null;
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
                Text(
                  _forgotPassword
                      ? '忘记密码？'
                      : _register
                      ? '创建账号'
                      : '登录你的账号',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: eu.textMid, fontSize: 15),
                ),
                const SizedBox(height: 28),
                _field(eu, _email, '邮箱', TextInputType.emailAddress, false),
                if (_register || _forgotPassword) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _field(
                          eu,
                          _verificationCode,
                          '验证码',
                          TextInputType.number,
                          false,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: (_busy || _codeBusy || _codeCooldown > 0)
                            ? null
                            : _requestVerificationCode,
                        child: _codeBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _codeCooldown > 0
                                    ? '${_codeCooldown.toString()}秒后重试'
                                    : '获取验证码',
                              ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                _field(
                  eu,
                  _password,
                  _forgotPassword ? '新密码' : '密码',
                  TextInputType.visiblePassword,
                  true,
                  onChanged: (_) => setState(() {}),
                  onSubmit: (_) => _submit(),
                ),
                if (!_register && !_forgotPassword) ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: eu.brand,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                      onPressed: _busy ? null : _enterForgotMode,
                      child: const Text('忘记密码？'),
                    ),
                  ),
                ],
                if (_register || _forgotPassword) ...[
                  const SizedBox(height: 12),
                  _field(
                    eu,
                    _passwordConfirmation,
                    _forgotPassword ? '确认新密码' : '确认密码',
                    TextInputType.visiblePassword,
                    true,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '密码要求',
                          style: TextStyle(color: eu.textLo, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        _passwordRule(eu, '8–128 位', _passwordLengthValid),
                        _passwordRule(eu, '包含大写字母 A–Z', _passwordHasUppercase),
                        _passwordRule(eu, '包含小写字母 a–z', _passwordHasLowercase),
                        _passwordRule(eu, '包含数字 0–9', _passwordHasDigit),
                        _passwordRule(
                          eu,
                          '包含安全符号 ! @ # \$ % ^ & * . _ + = ? -',
                          _passwordHasSafeSymbol,
                        ),
                        _passwordRule(
                          eu,
                          '只允许 ASCII 字母、数字和上述安全符号',
                          _passwordCharactersValid,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _passwordPolicyValid ? '密码强度：符合要求' : '密码强度：未完成',
                          style: TextStyle(
                            color: _passwordPolicyValid ? eu.brand : eu.textLo,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_register) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 28,
                        height: 32,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Transform.scale(
                            scale: 0.86,
                            child: Checkbox(
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              value: _termsAccepted,
                              onChanged: _busy
                                  ? null
                                  : (value) => setState(
                                      () => _termsAccepted = value ?? false,
                                    ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          runSpacing: -4,
                          children: [
                            const Text(
                              '我已阅读并同意',
                              style: TextStyle(fontSize: 12, height: 1.1),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                textStyle: const TextStyle(
                                  fontSize: 12,
                                  height: 1.1,
                                ),
                              ),
                              onPressed: _termsUrl.isEmpty
                                  ? null
                                  : () => _openLegalUrl(_termsUrl),
                              child: const Text('服务条款'),
                            ),
                            const Text(
                              '和',
                              style: TextStyle(fontSize: 12, height: 1.1),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                textStyle: const TextStyle(
                                  fontSize: 12,
                                  height: 1.1,
                                ),
                              ),
                              onPressed: _privacyUrl.isEmpty
                                  ? null
                                  : () => _openLegalUrl(_privacyUrl),
                              child: const Text('隐私政策'),
                            ),
                          ],
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
                if (_notice != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _notice!,
                    style: TextStyle(color: eu.brand, fontSize: 13),
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
                      gradient: LinearGradient(
                        colors: [eu.brand, eu.accentPurple],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: _busy
                          ? null
                          : [
                              BoxShadow(
                                color: eu.brand.withValues(alpha: 0.4),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
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
                            _forgotPassword
                                ? '重置密码'
                                : _register
                                ? '注册并进入'
                                : '登录',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _busy
                      ? null
                      : () {
                          if (_forgotPassword) {
                            _switchMode(false);
                          } else {
                            _switchMode(!_register);
                          }
                        },
                  behavior: HitTestBehavior.opaque,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: _forgotPassword
                              ? ''
                              : _register
                              ? '已有账号？'
                              : '还没有账号？',
                          style: TextStyle(color: eu.textMid, fontSize: 13),
                        ),
                        TextSpan(
                          text: _forgotPassword
                              ? '返回登录'
                              : _register
                              ? '去登录'
                              : '去注册',
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
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmit,
  }) {
    return TextField(
      controller: c,
      keyboardType: type,
      obscureText: obscure,
      onChanged: onChanged,
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

  Widget _passwordRule(EurekaColors eu, String label, bool valid) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(
            valid ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 15,
            color: valid ? eu.brand : eu.textLo,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: valid ? eu.brand : eu.textLo,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
