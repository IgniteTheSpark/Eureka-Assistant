import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_events.dart';
import '../api/api_client.dart';
import '../api/auth_store.dart';
import '../ble_flash/ble_flash_manager.dart';
import '../ble_flash/flash_file_workflow.dart';
import '../device/device_controller.dart';
import '../device/device_silent_reconnect.dart';
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
  static const _kUserId = 'eureka_user_id';
  // Deep-link scheme the backend redirects to after 百智 OAuth (matches
  // EUREKA_APP_SCHEME server-side). The web-auth session intercepts it.
  static const _kBaizhiScheme = 'eureka';

  String? _email;
  String? _userId;
  bool _loaded = false;
  int _sessionEpoch = 0;

  String? get email => _email;
  String? get userId => _userId;
  bool get isAuthed => AuthStore.token != null && _userId != null;
  bool get loaded => _loaded;
  int get sessionEpoch => _sessionEpoch;

  /// Read any persisted token on startup. A `--dart-define=DEV_TOKEN=...` lets a
  /// headless/dev build skip the login screen for screenshot verification.
  Future<void> load() async {
    AuthStore.onUnauthorized = _onUnauthorized;
    const devToken = String.fromEnvironment('DEV_TOKEN');
    if (devToken.isNotEmpty) {
      AuthStore.token = devToken;
      AuthStore.userId = 'dev';
      _userId = 'dev';
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
        _userId = sp.getString(_kUserId);
        AuthStore.userId = _userId;
        if (AuthStore.token != null && _userId == null) {
          await _restoreCurrentUser();
        }
        if (isAuthed) _sessionEpoch++;
      } catch (_) {
        _clearAuthMemory();
      }
    }
    _loaded = true;
    notifyListeners();
    _tryReconnectAfterAuth();
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
      final user = (m['user'] as Map?)?.cast<String, dynamic>();
      final ok = await _finishLogin(
        token,
        userId: user?['id']?.toString(),
        email: user?['email'] as String?,
      );
      if (!ok) return '登录失败，请重试';
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
      final ok = await _finishLogin(token, userId: null, email: null);
      if (!ok) return '百智登录失败，请重试';
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
  /// persist. [email] can be null for 百智-OAuth users.
  Future<bool> _finishLogin(
    String token, {
    required String? userId,
    required String? email,
  }) async {
    await _resetPerUserState();
    AuthStore.token = token;
    var resolvedUserId = _clean(userId);
    var resolvedEmail = email;
    if (resolvedUserId == null) {
      final me = await _fetchCurrentUser();
      resolvedUserId = _clean(me?['id']);
      resolvedEmail ??= me?['email'] as String?;
    }
    if (resolvedUserId == null) {
      _clearAuthMemory();
      return false;
    }
    _userId = resolvedUserId;
    _email = resolvedEmail;
    AuthStore.userId = resolvedUserId;
    _sessionEpoch++;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kToken, token);
    await sp.setString(_kUserId, resolvedUserId);
    if (resolvedEmail != null) {
      await sp.setString(_kEmail, resolvedEmail);
    } else {
      await sp.remove(_kEmail);
    }
    notifyListeners();
    _tryReconnectAfterAuth();
    return true;
  }

  void _tryReconnectAfterAuth() {
    if (!isAuthed) return;
    unawaited(
      DeviceSilentReconnect.instance.tryReconnect(sessionKey: _sessionEpoch),
    );
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
    _clearAuthMemory();
    _sessionEpoch++;
    await _resetPerUserState();
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kToken);
    await sp.remove(_kEmail);
    await sp.remove(_kUserId);
    await sp.remove(
      'eureka:active_chat_session',
    ); // don't resume across accounts
    notifyListeners();
  }

  /// Wipe the singleton stores that hold per-account state, so signing out (or a
  /// 401) doesn't leak the previous user's REKA onto the login screen / next
  /// account. Pet reset also forces the next user's 孵化 onboarding to re-decide
  /// from a fresh /api/pet (a stale spawned snapshot would skip it).
  Future<void> _resetPerUserState() async {
    AppEvents.instance.stop();
    FlashFileWorkflow.instance.stop();
    await DeviceSilentReconnect.instance.stop();
    await BleFlashManager.instance.stop();
    await DeviceController.instance.disconnectForLogout();
    PetController.instance.reset();
    RekaNudges.instance.reset();
    RekaNotifications.instance.clear();
  }

  void _onUnauthorized() {
    // Token expired server-side — drop it so the gate shows login.
    if (AuthStore.token == null && _email == null && _userId == null) return;
    _clearAuthMemory();
    _sessionEpoch++;
    unawaited(_resetPerUserState());
    SharedPreferences.getInstance().then((sp) {
      sp.remove(_kToken);
      sp.remove(_kEmail);
      sp.remove(_kUserId);
    });
    notifyListeners();
  }

  Future<void> _restoreCurrentUser() async {
    final me = await _fetchCurrentUser();
    final id = _clean(me?['id']);
    if (id == null) {
      _clearAuthMemory();
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_kToken);
      await sp.remove(_kEmail);
      await sp.remove(_kUserId);
      return;
    }
    _userId = id;
    _email = me?['email'] as String? ?? _email;
    AuthStore.userId = id;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kUserId, id);
    if (_email != null) await sp.setString(_kEmail, _email!);
  }

  Future<Map<String, dynamic>?> _fetchCurrentUser() async {
    final api = ApiClient();
    try {
      final res = await api.getJson('/api/auth/me');
      final user = (res as Map)['user'];
      return user is Map ? user.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    } finally {
      api.close();
    }
  }

  void _clearAuthMemory() {
    AuthStore.token = null;
    AuthStore.userId = null;
    _email = null;
    _userId = null;
  }

  String? _clean(Object? value) {
    final s = value?.toString().trim();
    return s == null || s.isEmpty ? null : s;
  }
}

/// True when a dev token was injected (so verification builds skip login).
bool get hasDevToken => const String.fromEnvironment('DEV_TOKEN').isNotEmpty;
