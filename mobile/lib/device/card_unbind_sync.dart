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
    return PendingCardUnbind(
      bindingId: json['binding_id']?.toString() ?? '',
      deleteData: json['delete_data'] == true,
    );
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
  Future<PendingCardUnbind?> read();

  Future<void> write(PendingCardUnbind request);

  Future<void> clear();
}

abstract interface class CardUnbindSyncApi {
  Future<dynamic> postJson(String path, Map<String, dynamic> body);
}

class CardUnbindSyncCoordinator {
  CardUnbindSyncCoordinator({
    required CardUnbindSyncStore store,
    required CardUnbindSyncApi api,
  }) : _store = store,
       _api = api;

  factory CardUnbindSyncCoordinator.production() {
    return CardUnbindSyncCoordinator(
      store: const SharedPreferencesCardUnbindSyncStore(),
      api: _ApiClientCardUnbindSyncApi(ApiClient()),
    );
  }

  final CardUnbindSyncStore _store;
  final CardUnbindSyncApi _api;

  Future<bool> sync(PendingCardUnbind request) async {
    try {
      await _store.write(request);
      await _api.postJson('/api/cards/${request.bindingId}/unbind', {
        'delete_data': request.deleteData,
      });
      await _store.clear();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> retryPending() async {
    try {
      final request = await _store.read();
      if (request == null) return true;
      return sync(request);
    } catch (_) {
      return false;
    }
  }

  Future<Set<String>> pendingBindingIds() async {
    try {
      final request = await _store.read();
      if (request == null || request.bindingId.isEmpty) return const {};
      return {request.bindingId};
    } catch (_) {
      return const {};
    }
  }
}

class SharedPreferencesCardUnbindSyncStore implements CardUnbindSyncStore {
  const SharedPreferencesCardUnbindSyncStore();

  String get key =>
      'eureka:pending_card_unbind:${AuthStore.userId ?? 'anonymous'}';

  @override
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(key);
  }

  @override
  Future<PendingCardUnbind?> read() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(key);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return PendingCardUnbind.fromJson(decoded.cast<String, dynamic>());
  }

  @override
  Future<void> write(PendingCardUnbind request) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(key, jsonEncode(request.toJson()));
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
