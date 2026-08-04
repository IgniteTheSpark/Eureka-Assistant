import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/auth_store.dart';

@immutable
class PendingCardUnbind {
  const PendingCardUnbind({required this.bindingId, required this.deleteData});

  final String bindingId;
  final bool deleteData;

  Map<String, dynamic> toJson() => {
    'binding_id': bindingId,
    'delete_data': deleteData,
  };

  factory PendingCardUnbind.fromJson(Map<String, dynamic> json) {
    final bindingId = json['binding_id'];
    final deleteData = json['delete_data'];
    if (bindingId is! String ||
        bindingId.trim().isEmpty ||
        deleteData is! bool) {
      throw const FormatException('invalid pending card unbind');
    }
    return PendingCardUnbind(bindingId: bindingId, deleteData: deleteData);
  }

  @override
  bool operator ==(Object other) =>
      other is PendingCardUnbind &&
      other.bindingId == bindingId &&
      other.deleteData == deleteData;

  @override
  int get hashCode => Object.hash(bindingId, deleteData);
}

abstract interface class CardUnbindSyncStore {
  Future<PendingCardUnbind?> read({String? accountScope});

  Future<void> write(PendingCardUnbind request, {String? accountScope});

  Future<void> clear({
    String? accountScope,
    PendingCardUnbind? expectedRequest,
  });
}

abstract interface class CardUnbindSyncApi {
  Future<dynamic> postJson(String path, Map<String, dynamic> body);
}

abstract interface class CardUnbindSyncPreferences {
  String? getString(String key);

  Future<bool> setString(String key, String value);

  Future<bool> remove(String key);
}

class CardUnbindSyncCoordinator {
  CardUnbindSyncCoordinator({
    required CardUnbindSyncStore store,
    required CardUnbindSyncApi api,
    String Function()? accountScope,
  }) : _store = store,
       _api = api,
       _accountScope = accountScope ?? _currentAccountScope;

  factory CardUnbindSyncCoordinator.production() {
    return CardUnbindSyncCoordinator(
      store: const SharedPreferencesCardUnbindSyncStore(),
      api: _ApiClientCardUnbindSyncApi(ApiClient()),
    );
  }

  final CardUnbindSyncStore _store;
  final CardUnbindSyncApi _api;
  final String Function() _accountScope;

  Future<bool> sync(PendingCardUnbind request) async {
    return _sync(request, accountScope: _accountScope());
  }

  Future<bool> _sync(
    PendingCardUnbind request, {
    required String accountScope,
  }) async {
    try {
      await _store.write(request, accountScope: accountScope);
      await _api.postJson('/api/cards/${request.bindingId}/unbind', {
        'delete_data': request.deleteData,
      });
      await _store.clear(accountScope: accountScope, expectedRequest: request);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> retryPending() async {
    final accountScope = _accountScope();
    try {
      final request = await _store.read(accountScope: accountScope);
      if (request == null) return true;
      return _sync(request, accountScope: accountScope);
    } catch (_) {
      return false;
    }
  }

  Future<Set<String>?> pendingBindingIds() async {
    final accountScope = _accountScope();
    try {
      final request = await _store.read(accountScope: accountScope);
      if (request == null || request.bindingId.isEmpty) return const {};
      return {request.bindingId};
    } catch (_) {
      return null;
    }
  }

  static String _currentAccountScope() => AuthStore.userId ?? 'anonymous';
}

class SharedPreferencesCardUnbindSyncStore implements CardUnbindSyncStore {
  const SharedPreferencesCardUnbindSyncStore({
    CardUnbindSyncPreferences? preferences,
  }) : _preferences = preferences;

  final CardUnbindSyncPreferences? _preferences;

  String get key => _keyForScope(null);

  @override
  Future<void> clear({
    String? accountScope,
    PendingCardUnbind? expectedRequest,
  }) async {
    final preferences = await _loadPreferences();
    final key = _keyForScope(accountScope);
    if (expectedRequest != null) {
      final raw = preferences.getString(key);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('invalid pending card unbind');
      }
      final current = PendingCardUnbind.fromJson(
        decoded.cast<String, dynamic>(),
      );
      if (current != expectedRequest) return;
    }
    final removed = await preferences.remove(key);
    if (!removed) throw StateError('pending card unbind was not cleared');
  }

  @override
  Future<PendingCardUnbind?> read({String? accountScope}) async {
    final preferences = await _loadPreferences();
    final raw = preferences.getString(_keyForScope(accountScope));
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('invalid pending card unbind');
    }
    return PendingCardUnbind.fromJson(decoded.cast<String, dynamic>());
  }

  @override
  Future<void> write(PendingCardUnbind request, {String? accountScope}) async {
    final preferences = await _loadPreferences();
    final stored = await preferences.setString(
      _keyForScope(accountScope),
      jsonEncode(request.toJson()),
    );
    if (!stored) throw StateError('pending card unbind was not persisted');
  }

  Future<CardUnbindSyncPreferences> _loadPreferences() async {
    final injected = _preferences;
    if (injected != null) return injected;
    return _SharedPreferencesAdapter(await SharedPreferences.getInstance());
  }

  String _keyForScope(String? accountScope) =>
      'eureka:pending_card_unbind:${accountScope ?? AuthStore.userId ?? 'anonymous'}';
}

class _SharedPreferencesAdapter implements CardUnbindSyncPreferences {
  const _SharedPreferencesAdapter(this._preferences);

  final SharedPreferences _preferences;

  @override
  String? getString(String key) => _preferences.getString(key);

  @override
  Future<bool> remove(String key) => _preferences.remove(key);

  @override
  Future<bool> setString(String key, String value) {
    return _preferences.setString(key, value);
  }
}

class _ApiClientCardUnbindSyncApi implements CardUnbindSyncApi {
  _ApiClientCardUnbindSyncApi(this._api);

  final ApiClient _api;

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body) {
    return _api.postJson(path, body);
  }
}
