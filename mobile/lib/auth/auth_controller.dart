import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_events.dart';
import '../api/api_client.dart';
import '../api/auth_store.dart';
import '../ble_flash/ble_flash_manager.dart';
import '../ble_flash/flash_file_workflow.dart';
import '../chat/recent_session.dart';
import '../device/device_controller.dart';
import '../device/device_silent_reconnect.dart';
import '../pet/pet_controller.dart';
import '../pet/reka_nudges.dart';
import '../pet/reka_notifications.dart';
import '../ring/ring_capture_service.dart';

/// App-wide auth state: holds the session token + the signed-in email, and
/// drives the login gate in main.dart. The token is mirrored into [AuthStore]
/// so ApiClient / the SSE client attach it automatically.
class AuthController extends ChangeNotifier {
  AuthController._();
  static final AuthController instance = AuthController._();

  static const _kToken = 'eureka_token';
  static const _kEmail = 'eureka_email';
  static const _kUserId = 'eureka_user_id';
  static const _kOnboardingStatus = 'eureka_onboarding_status';

  String? _email;
  String? _userId;
  String? _onboardingStatus;
  bool _loaded = false;
  int _sessionEpoch = 0;

  String? get email => _email;
  String? get userId => _userId;
  String? get onboardingStatus => _onboardingStatus;
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
        _onboardingStatus = sp.getString(_kOnboardingStatus);
        AuthStore.userId = _userId;
        // Restore the user when identity or onboarding status is missing
        // (covers sessions minted before onboarding-status persistence).
        if (AuthStore.token != null &&
            (_userId == null || _onboardingStatus == null)) {
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
  Future<String?> login(String email, String password) async {
    final api = ApiClient();
    try {
      final res = await api.postJson('/api/auth/login', {
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
        onboardingStatus: user?['onboarding_status'] as String?,
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

  /// Request a 6-digit verification code for `register` or `password_reset`.
  /// Returns null on success or a user-facing error message.
  Future<String?> requestVerificationCode(String email, String purpose) async {
    final api = ApiClient();
    try {
      await api.postJson('/api/auth/verification-codes', {
        'email': email.trim(),
        'purpose': purpose,
      });
      return null;
    } on ApiException catch (e) {
      return _errMsg(e);
    } catch (_) {
      return '网络错误，请检查连接';
    } finally {
      api.close();
    }
  }

  /// Register with an email verification code (§5.5). Terms acceptance is
  /// required server-side.
  Future<String?> register(
    String email,
    String verificationCode,
    String password, {
    required String termsVersion,
    required bool termsAccepted,
  }) async {
    final api = ApiClient();
    try {
      final res = await api.postJson('/api/auth/register', {
        'email': email.trim(),
        'verification_code': verificationCode,
        'password': password,
        'terms_version': termsVersion,
        'terms_accepted': termsAccepted,
      });
      final m = (res as Map).cast<String, dynamic>();
      final token = m['token'] as String?;
      if (token == null) return '注册失败，请重试';
      final user = (m['user'] as Map?)?.cast<String, dynamic>();
      final ok = await _finishLogin(
        token,
        userId: user?['id']?.toString(),
        email: user?['email'] as String?,
        onboardingStatus: user?['onboarding_status'] as String?,
      );
      if (!ok) return '注册失败，请重试';
      return null;
    } on ApiException catch (e) {
      return _errMsg(e);
    } catch (_) {
      return '网络错误，请检查连接';
    } finally {
      api.close();
    }
  }

  Future<Map<String, String>> loadAuthConfig() async {
    final api = ApiClient();
    try {
      final response = await api.getJson('/api/auth/config');
      final data = (response as Map).cast<String, dynamic>();
      return {
        'terms_url': data['terms_url'] as String? ?? '',
        'privacy_url': data['privacy_url'] as String? ?? '',
        'terms_version': data['terms_version'] as String? ?? '',
      };
    } catch (_) {
      return const {};
    } finally {
      api.close();
    }
  }

  /// Verify a password-reset code and replace the password (§5.5).
  Future<String?> resetPassword(
    String email,
    String verificationCode,
    String newPassword,
  ) async {
    final api = ApiClient();
    try {
      await api.postJson('/api/auth/password-reset', {
        'email': email.trim(),
        'verification_code': verificationCode,
        'new_password': newPassword,
      });
      return null;
    } on ApiException catch (e) {
      return _errMsg(e);
    } catch (_) {
      return '网络错误，请检查连接';
    } finally {
      api.close();
    }
  }

  /// Change the authenticated user's password (§8.3), then require a fresh
  /// login because the backend revokes the current session.
  Future<String?> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final api = ApiClient();
    try {
      await api.patchJson('/api/account/password', {
        'current_password': currentPassword,
        'new_password': newPassword,
      });
      await logout();
      return null;
    } on ApiException catch (e) {
      return _errMsg(e);
    } catch (_) {
      return '网络错误，请检查连接';
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
    String? onboardingStatus,
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
    _onboardingStatus = onboardingStatus;
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
    if (onboardingStatus != null) {
      await sp.setString(_kOnboardingStatus, onboardingStatus);
    }
    notifyListeners();
    _tryReconnectAfterAuth();
    return true;
  }

  /// Update the durable onboarding status after skip/complete; the gate reads
  /// this to route pending users into onboarding.
  Future<void> updateOnboardingStatus(String status) async {
    _onboardingStatus = status;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kOnboardingStatus, status);
    notifyListeners();
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
    await _resetPerUserState();
    _clearAuthMemory();
    _sessionEpoch++;
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kToken);
    await sp.remove(_kEmail);
    await sp.remove(_kUserId);
    await sp.remove(_kOnboardingStatus);
    await sp.remove(
      'eureka:active_chat_session',
    ); // don't resume across accounts
    await sp.remove(recentSessionIdKey);
    await sp.remove(recentSessionTypeKey);
    notifyListeners();
  }

  /// Wipe the singleton stores that hold per-account state, so signing out (or a
  /// 401) doesn't leak the previous user's REKA onto the login screen / next
  /// account. Pet reset also forces the next user's 孵化 onboarding to re-decide
  /// from a fresh /api/pet (a stale spawned snapshot would skip it).
  Future<void> _resetPerUserState() async {
    AppEvents.instance.stop();
    FlashFileWorkflow.instance.stop();
    // Each cleanup is best-effort: on Web the native BLE/ring plugins throw
    // MissingPluginException, which must not block logout or auth reset.
    await _guard(() => stopRingCapture());
    await _guard(() => DeviceSilentReconnect.instance.stop());
    await _guard(() => BleFlashManager.instance.stop());
    await _guard(() => DeviceController.instance.disconnectForLogout());
    PetController.instance.reset();
    RekaNudges.instance.reset();
    RekaNotifications.instance.clear();
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Best-effort cleanup: swallow platform errors.
    }
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
      sp.remove(_kOnboardingStatus);
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
      await sp.remove(_kOnboardingStatus);
      return;
    }
    _userId = id;
    _email = me?['email'] as String? ?? _email;
    _onboardingStatus =
        me?['onboarding_status'] as String? ?? _onboardingStatus;
    AuthStore.userId = id;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kUserId, id);
    if (_email != null) await sp.setString(_kEmail, _email!);
    if (_onboardingStatus != null) {
      await sp.setString(_kOnboardingStatus, _onboardingStatus!);
    }
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
    _onboardingStatus = null;
  }

  String? _clean(Object? value) {
    final s = value?.toString().trim();
    return s == null || s.isEmpty ? null : s;
  }
}

/// True when a dev token was injected (so verification builds skip login).
bool get hasDevToken => const String.fromEnvironment('DEV_TOKEN').isNotEmpty;
