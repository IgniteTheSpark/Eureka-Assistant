import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_events.dart';
import '../api/api_client.dart';
import '../api/auth_store.dart';
import '../pet/pet_controller.dart';
import '../pet/reka_nudges.dart';
import '../pet/reka_notifications.dart';

/// App-wide auth state: holds the session token + the signed-in email, and
/// drives the login gate in main.dart. The token is mirrored into [AuthStore]
/// so ApiClient / the SSE client attach it automatically.
class AuthController extends ChangeNotifier {
  AuthController._();
  static final AuthController instance = AuthController._();

  static const _kToken = 'eureka_token';
  static const _kEmail = 'eureka_email';
  // Deep-link scheme the backend redirects to after 百智 OAuth (matches
  // EUREKA_APP_SCHEME server-side). The web-auth session intercepts it.
  static const _kBaizhiScheme = 'eureka';

  String? _email;
  bool _loaded = false;
  int _sessionEpoch = 0;

  String? get email => _email;
  bool get isAuthed => AuthStore.token != null;
  bool get loaded => _loaded;
  int get sessionEpoch => _sessionEpoch;

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
        final sp = await SharedPreferences.getInstance().timeout(
          const Duration(seconds: 3),
        );
        AuthStore.token = sp.getString(_kToken);
        _email = sp.getString(_kEmail);
        if (AuthStore.token != null) _sessionEpoch++;
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
      await _finishLogin(token, ((m['user'] as Map?)?['email']) as String?);
      return null;
    } on ApiException catch (e) {
      return _errMsg(e);
    } catch (_) {
      return '网络错误，请检查连接';
    } finally {
      api.close();
    }
  }

  /// §13.1 / B1 — log in with 百智 (100wiser) OAuth. Fetches the oauth-bridge URL
  /// from the backend, opens it in a web-auth session, and captures the backend's
  /// `eureka://auth?token=<EurekaJWT>` deep-link callback. The client only ever
  /// handles the **Eureka JWT** — 百智's real token stays server-side.
  /// Returns null on success, '' on user-cancel (silent), or an error message.
  Future<String?> loginWithBaizhi() async {
    final api = ApiClient();
    try {
      final res = await api.getJson('/api/auth/baizhi/authorize');
      final authorizeUrl = ((res as Map)['authorize_url']) as String?;
      if (authorizeUrl == null || authorizeUrl.isEmpty) return '百智登录暂不可用';

      final callback = await FlutterWebAuth2.authenticate(
        url: authorizeUrl,
        callbackUrlScheme: _kBaizhiScheme,
      );
      final params = Uri.parse(callback).queryParameters;
      final err = params['error'];
      if (err != null && err.isNotEmpty) return '百智登录失败，请重试';
      final token = params['token'];
      if (token == null || token.isEmpty) return '百智登录失败，请重试';
      await _finishLogin(
        token,
        null,
      ); // 百智 user — email comes from 百智, not stored here
      return null;
    } on ApiException catch (e) {
      return _errMsg(e);
    } catch (e) {
      // flutter_web_auth_2 throws on user-cancel — treat as a silent no-op.
      if (e.toString().toLowerCase().contains('cancel')) return '';
      return '百智登录失败，请重试';
    } finally {
      api.close();
    }
  }

  /// Commit a freshly minted Eureka session token: mirror into [AuthStore] +
  /// persist. [email] is null for 百智-OAuth users (no email/password locally).
  Future<void> _finishLogin(String token, String? email) async {
    _resetPerUserState();
    AuthStore.token = token;
    _email = email;
    _sessionEpoch++;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kToken, token);
    if (email != null) {
      await sp.setString(_kEmail, email);
    } else {
      await sp.remove(_kEmail);
    }
    notifyListeners();
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
    _sessionEpoch++;
    _resetPerUserState();
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kToken);
    await sp.remove(_kEmail);
    await sp.remove(
      'eureka:active_chat_session',
    ); // don't resume across accounts
    notifyListeners();
  }

  /// Wipe the singleton stores that hold per-account state, so signing out (or a
  /// 401) doesn't leak the previous user's REKA onto the login screen / next
  /// account. Pet reset also forces the next user's 孵化 onboarding to re-decide
  /// from a fresh /api/pet (a stale spawned snapshot would skip it).
  void _resetPerUserState() {
    AppEvents.instance.stop();
    PetController.instance.reset();
    RekaNudges.instance.reset();
    RekaNotifications.instance.clear();
  }

  void _onUnauthorized() {
    // Token expired server-side — drop it so the gate shows login.
    if (AuthStore.token == null && _email == null) return;
    AuthStore.token = null;
    _email = null;
    _sessionEpoch++;
    _resetPerUserState();
    SharedPreferences.getInstance().then((sp) {
      sp.remove(_kToken);
      sp.remove(_kEmail);
    });
    notifyListeners();
  }
}

/// True when a dev token was injected (so verification builds skip login).
bool get hasDevToken => const String.fromEnvironment('DEV_TOKEN').isNotEmpty;
