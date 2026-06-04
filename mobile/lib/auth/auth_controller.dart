import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/auth_store.dart';

/// App-wide auth state: holds the session token + the signed-in email, and
/// drives the login gate in main.dart. The token is mirrored into [AuthStore]
/// so ApiClient / the SSE client attach it automatically.
class AuthController extends ChangeNotifier {
  AuthController._();
  static final AuthController instance = AuthController._();

  static const _kToken = 'eureka_token';
  static const _kEmail = 'eureka_email';

  String? _email;
  bool _loaded = false;

  String? get email => _email;
  bool get isAuthed => AuthStore.token != null;
  bool get loaded => _loaded;

  /// Read any persisted token on startup. A `--dart-define=DEV_TOKEN=...` lets a
  /// headless/dev build skip the login screen for screenshot verification.
  Future<void> load() async {
    AuthStore.onUnauthorized = _onUnauthorized;
    const devToken = String.fromEnvironment('DEV_TOKEN');
    if (devToken.isNotEmpty) {
      AuthStore.token = devToken;
      _email = 'dev@local';
    } else {
      // Never let storage init wedge the gate — time out / swallow errors and
      // proceed unauthenticated (→ login) if prefs are unavailable.
      try {
        final sp = await SharedPreferences.getInstance()
            .timeout(const Duration(seconds: 3));
        AuthStore.token = sp.getString(_kToken);
        _email = sp.getString(_kEmail);
      } catch (_) {
        AuthStore.token = null;
      }
    }
    _loaded = true;
    notifyListeners();
  }

  /// Returns null on success, or a user-facing error message.
  Future<String?> login(String email, String password) =>
      _auth('/api/auth/login', email, password);

  Future<String?> register(String email, String password) =>
      _auth('/api/auth/register', email, password);

  Future<String?> _auth(String path, String email, String password) async {
    final api = ApiClient();
    try {
      final res = await api.postJson(path, {
        'email': email.trim(),
        'password': password,
      });
      final m = (res as Map).cast<String, dynamic>();
      final token = m['token'] as String?;
      if (token == null) return '登录失败，请重试';
      AuthStore.token = token;
      _email = ((m['user'] as Map?)?['email']) as String?;
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kToken, token);
      if (_email != null) await sp.setString(_kEmail, _email!);
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return _errMsg(e);
    } catch (_) {
      return '网络错误，请检查连接';
    } finally {
      api.close();
    }
  }

  String _errMsg(ApiException e) {
    try {
      final body = jsonDecode(e.body);
      final d = body is Map ? body['detail'] : null;
      if (d is String && d.isNotEmpty) return d;
    } catch (_) {}
    return '操作失败 (${e.statusCode})';
  }

  Future<void> logout() async {
    AuthStore.token = null;
    _email = null;
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kToken);
    await sp.remove(_kEmail);
    await sp.remove('eureka:active_chat_session'); // don't resume across accounts
    notifyListeners();
  }

  void _onUnauthorized() {
    // Token expired server-side — drop it so the gate shows login.
    if (AuthStore.token == null && _email == null) return;
    AuthStore.token = null;
    _email = null;
    SharedPreferences.getInstance().then((sp) {
      sp.remove(_kToken);
      sp.remove(_kEmail);
    });
    notifyListeners();
  }
}

/// True when a dev token was injected (so verification builds skip login).
bool get hasDevToken => const String.fromEnvironment('DEV_TOKEN').isNotEmpty;
