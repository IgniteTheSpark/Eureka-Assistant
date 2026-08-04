import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/auth_store.dart';

const cardUnbindSyncPendingWarning = '设备已解绑，服务端同步待重试';

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

@immutable
class CardUnbindSyncTicket {
  const CardUnbindSyncTicket({
    required this.request,
    required this.accountScope,
  });

  final PendingCardUnbind request;
  final String accountScope;
}

@immutable
class CardUnbindSyncResult {
  const CardUnbindSyncResult.synced(this.bindingId)
    : serverSynced = true,
      message = null;

  const CardUnbindSyncResult.pending(this.bindingId)
    : serverSynced = false,
      message = cardUnbindSyncPendingWarning;

  final String bindingId;
  final bool serverSynced;
  final String? message;
}

abstract interface class CardUnbindSyncStore {
  Future<Map<String, PendingCardUnbind>> readAll({String? accountScope});

  Future<void> write(PendingCardUnbind request, {String? accountScope});

  Future<void> clear({
    String? accountScope,
    required PendingCardUnbind expectedRequest,
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
  static final Set<String> _unknownAccountScopes = {};

  CardUnbindSyncCoordinator({
    required CardUnbindSyncStore store,
    required CardUnbindSyncApi api,
    String Function()? accountScope,
    this.requestTimeout = const Duration(seconds: 5),
  }) : assert(requestTimeout > Duration.zero),
       _store = store,
       _api = api,
       _accountScope = accountScope ?? _currentAccountScope;

  factory CardUnbindSyncCoordinator.production() {
    return CardUnbindSyncCoordinator(
      store: SharedPreferencesCardUnbindSyncStore(),
      api: _ApiClientCardUnbindSyncApi(ApiClient()),
    );
  }

  final CardUnbindSyncStore _store;
  final CardUnbindSyncApi _api;
  final String Function() _accountScope;
  final Duration requestTimeout;

  Future<CardUnbindSyncTicket> enqueue(PendingCardUnbind request) async {
    final accountScope = _accountScope();
    try {
      await _store.write(request, accountScope: accountScope);
      return CardUnbindSyncTicket(request: request, accountScope: accountScope);
    } catch (_) {
      _unknownAccountScopes.add(accountScope);
      rethrow;
    }
  }

  Future<CardUnbindSyncResult> flush(CardUnbindSyncTicket ticket) async {
    final request = ticket.request;
    try {
      await _api
          .postJson('/api/cards/${request.bindingId}/unbind', {
            'delete_data': request.deleteData,
          })
          .timeout(requestTimeout);
      await _store.clear(
        accountScope: ticket.accountScope,
        expectedRequest: request,
      );
      return CardUnbindSyncResult.synced(request.bindingId);
    } catch (_) {
      return CardUnbindSyncResult.pending(request.bindingId);
    }
  }

  /// Backward-compatible blocking helper for legacy callers. The wait is always
  /// bounded by [requestTimeout]; new unbind flows use [enqueue] then [flush].
  Future<bool> sync(PendingCardUnbind request) async {
    try {
      final ticket = await enqueue(request);
      return (await flush(ticket)).serverSynced;
    } catch (_) {
      return false;
    }
  }

  Future<bool> retryPending() async {
    final accountScope = _accountScope();
    if (_unknownAccountScopes.contains(accountScope)) return false;
    try {
      final requests = await _store.readAll(accountScope: accountScope);
      if (requests.isEmpty) return true;
      final results = await Future.wait([
        for (final request in requests.values)
          flush(
            CardUnbindSyncTicket(request: request, accountScope: accountScope),
          ),
      ]);
      return results.every((result) => result.serverSynced);
    } catch (_) {
      _unknownAccountScopes.add(accountScope);
      return false;
    }
  }

  Future<Set<String>?> pendingBindingIds() async {
    final accountScope = _accountScope();
    if (_unknownAccountScopes.contains(accountScope)) return null;
    try {
      final requests = await _store.readAll(accountScope: accountScope);
      return requests.keys.toSet();
    } catch (_) {
      _unknownAccountScopes.add(accountScope);
      return null;
    }
  }

  static String _currentAccountScope() => AuthStore.userId ?? 'anonymous';
}

class SharedPreferencesCardUnbindSyncStore implements CardUnbindSyncStore {
  SharedPreferencesCardUnbindSyncStore({CardUnbindSyncPreferences? preferences})
    : _preferences = preferences;

  static const _formatVersion = 2;
  static Future<void> _operationTail = Future<void>.value();

  final CardUnbindSyncPreferences? _preferences;

  String get key => _keyForScope(null);

  @override
  Future<void> clear({
    String? accountScope,
    required PendingCardUnbind expectedRequest,
  }) {
    return _serialized(() async {
      final preferences = await _loadPreferences();
      final key = _keyForScope(accountScope);
      final raw = preferences.getString(key);
      if (raw == null) return;
      final decoded = _decode(raw);
      if (decoded.requests[expectedRequest.bindingId] != expectedRequest) {
        return;
      }

      decoded.requests.remove(expectedRequest.bindingId);
      if (decoded.requests.isEmpty) {
        final removed = await preferences.remove(key);
        if (!removed) {
          throw StateError('pending card unbind was not cleared');
        }
        return;
      }
      await _persist(preferences, key, decoded.requests);
    });
  }

  @override
  Future<Map<String, PendingCardUnbind>> readAll({String? accountScope}) {
    return _serialized(() async {
      final preferences = await _loadPreferences();
      final key = _keyForScope(accountScope);
      final raw = preferences.getString(key);
      if (raw == null) return const <String, PendingCardUnbind>{};
      final decoded = _decode(raw);
      if (decoded.legacy) {
        await _persist(preferences, key, decoded.requests);
      }
      return Map<String, PendingCardUnbind>.unmodifiable(decoded.requests);
    });
  }

  @override
  Future<void> write(PendingCardUnbind request, {String? accountScope}) {
    return _serialized(() async {
      final preferences = await _loadPreferences();
      final key = _keyForScope(accountScope);
      final raw = preferences.getString(key);
      final requests = raw == null
          ? <String, PendingCardUnbind>{}
          : _decode(raw).requests;
      requests[request.bindingId] = request;
      await _persist(preferences, key, requests);
    });
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<void> _persist(
    CardUnbindSyncPreferences preferences,
    String key,
    Map<String, PendingCardUnbind> requests,
  ) async {
    final stored = await preferences.setString(
      key,
      jsonEncode({
        'version': _formatVersion,
        'requests': {
          for (final entry in requests.entries) entry.key: entry.value.toJson(),
        },
      }),
    );
    if (!stored) throw StateError('pending card unbind was not persisted');
  }

  ({Map<String, PendingCardUnbind> requests, bool legacy}) _decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('invalid pending card unbind collection');
    }
    final root = Map<String, dynamic>.from(decoded);
    if (root.containsKey('binding_id')) {
      final request = PendingCardUnbind.fromJson(root);
      return (requests: {request.bindingId: request}, legacy: true);
    }
    if (root['version'] != _formatVersion || root['requests'] is! Map) {
      throw const FormatException('invalid pending card unbind collection');
    }

    final requests = <String, PendingCardUnbind>{};
    for (final entry in (root['requests'] as Map).entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('invalid pending card unbind collection');
      }
      final request = PendingCardUnbind.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
      if (request.bindingId != entry.key) {
        throw const FormatException('invalid pending card unbind collection');
      }
      requests[request.bindingId] = request;
    }
    return (requests: requests, legacy: false);
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
