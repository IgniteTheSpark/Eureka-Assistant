import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eureka/api/auth_store.dart';
import 'package:eureka/device/card_unbind_sync.dart';

void main() {
  test('sync persists before posting and retains a failed request', () async {
    final events = <String>[];
    final store = _MemoryStore(events);
    final api = _FakeApi(events)..fail = true;
    final coordinator = CardUnbindSyncCoordinator(store: store, api: api);
    const request = PendingCardUnbind(
      bindingId: 'binding-1',
      deleteData: false,
    );

    expect(await coordinator.sync(request), isFalse);

    expect(await store.read(), request);
    expect(await coordinator.pendingBindingIds(), {'binding-1'});
    expect(events, ['write', 'post']);
    expect(api.calls, hasLength(1));
    expect(api.calls.single.path, '/api/cards/binding-1/unbind');
    expect(api.calls.single.body, {'delete_data': false});
  });

  test(
    'retryPending posts the stored request without a BLE operation',
    () async {
      final events = <String>[];
      final store = _MemoryStore(events);
      final api = _FakeApi(events)..fail = true;
      final coordinator = CardUnbindSyncCoordinator(store: store, api: api);
      const request = PendingCardUnbind(
        bindingId: 'binding-1',
        deleteData: false,
      );

      expect(await coordinator.sync(request), isFalse);
      api.fail = false;
      events.clear();

      expect(await coordinator.retryPending(), isTrue);

      expect(await store.read(), isNull);
      expect(await coordinator.pendingBindingIds(), isEmpty);
      expect(events, ['write', 'post', 'clear']);
      expect(api.calls, hasLength(2));
    },
  );

  test(
    'SharedPreferences store resolves the account key per operation',
    () async {
      SharedPreferences.setMockInitialValues({});
      const store = SharedPreferencesCardUnbindSyncStore();
      const ownerRequest = PendingCardUnbind(
        bindingId: 'binding-owner',
        deleteData: false,
      );
      const otherRequest = PendingCardUnbind(
        bindingId: 'binding-other',
        deleteData: true,
      );
      addTearDown(() => AuthStore.userId = null);

      AuthStore.userId = 'owner';
      await store.write(ownerRequest);
      AuthStore.userId = 'other';
      expect(await store.read(), isNull);
      await store.write(otherRequest);

      AuthStore.userId = 'owner';
      expect(await store.read(), ownerRequest);
      AuthStore.userId = 'other';
      expect(await store.read(), otherRequest);
    },
  );

  test('false SharedPreferences write prevents the server post', () async {
    final events = <String>[];
    final preferences = _FakePreferences()..setSucceeds = false;
    final store = SharedPreferencesCardUnbindSyncStore(
      preferences: preferences,
    );
    final api = _FakeApi(events);
    final coordinator = CardUnbindSyncCoordinator(store: store, api: api);

    expect(
      await coordinator.sync(
        const PendingCardUnbind(bindingId: 'binding-1', deleteData: false),
      ),
      isFalse,
    );
    expect(api.calls, isEmpty);
  });

  test('false SharedPreferences clear retains retryable state', () async {
    final events = <String>[];
    final preferences = _FakePreferences()..removeSucceeds = false;
    final store = SharedPreferencesCardUnbindSyncStore(
      preferences: preferences,
    );
    final api = _FakeApi(events);
    final coordinator = CardUnbindSyncCoordinator(store: store, api: api);
    const request = PendingCardUnbind(
      bindingId: 'binding-1',
      deleteData: false,
    );

    expect(await coordinator.sync(request), isFalse);
    expect(api.calls, hasLength(1));
    expect(await store.read(), request);
  });

  test('in-flight sync clears only its captured account scope', () async {
    SharedPreferences.setMockInitialValues({});
    const store = SharedPreferencesCardUnbindSyncStore();
    final api = _DeferredApi();
    final coordinator = CardUnbindSyncCoordinator(store: store, api: api);
    const ownerRequest = PendingCardUnbind(
      bindingId: 'binding-owner',
      deleteData: false,
    );
    const otherRequest = PendingCardUnbind(
      bindingId: 'binding-other',
      deleteData: true,
    );
    addTearDown(() => AuthStore.userId = null);

    AuthStore.userId = 'owner';
    final sync = coordinator.sync(ownerRequest);
    await api.started.future;

    AuthStore.userId = 'other';
    await store.write(otherRequest);
    api.complete();
    expect(await sync, isTrue);

    AuthStore.userId = 'owner';
    expect(await store.read(), isNull);
    AuthStore.userId = 'other';
    expect(await store.read(), otherRequest);
  });

  test('in-flight sync does not clear a newer same-account request', () async {
    SharedPreferences.setMockInitialValues({});
    const store = SharedPreferencesCardUnbindSyncStore();
    final api = _DeferredApi();
    final coordinator = CardUnbindSyncCoordinator(store: store, api: api);
    const originalRequest = PendingCardUnbind(
      bindingId: 'binding-original',
      deleteData: false,
    );
    const newerRequest = PendingCardUnbind(
      bindingId: 'binding-newer',
      deleteData: true,
    );
    addTearDown(() => AuthStore.userId = null);

    AuthStore.userId = 'owner';
    final sync = coordinator.sync(originalRequest);
    await api.started.future;

    await store.write(newerRequest);
    api.complete();
    expect(await sync, isTrue);
    expect(await store.read(), newerRequest);
  });
}

class _MemoryStore implements CardUnbindSyncStore {
  _MemoryStore(this.events);

  final List<String> events;
  PendingCardUnbind? value;

  @override
  Future<void> clear({
    String? accountScope,
    PendingCardUnbind? expectedRequest,
  }) async {
    if (expectedRequest != null && value != expectedRequest) return;
    events.add('clear');
    value = null;
  }

  @override
  Future<PendingCardUnbind?> read({String? accountScope}) async => value;

  @override
  Future<void> write(PendingCardUnbind request, {String? accountScope}) async {
    events.add('write');
    value = request;
  }
}

class _FakeApi implements CardUnbindSyncApi {
  _FakeApi(this.events);

  final List<String> events;
  final List<({String path, Map<String, dynamic> body})> calls = [];
  bool fail = false;

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body) async {
    events.add('post');
    calls.add((path: path, body: body));
    if (fail) throw StateError('offline');
    return {'ok': true};
  }
}

class _DeferredApi implements CardUnbindSyncApi {
  final started = Completer<void>();
  final _response = Completer<dynamic>();

  void complete() => _response.complete({'ok': true});

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body) {
    started.complete();
    return _response.future;
  }
}

class _FakePreferences implements CardUnbindSyncPreferences {
  String? value;
  bool setSucceeds = true;
  bool removeSucceeds = true;

  @override
  String? getString(String key) => value;

  @override
  Future<bool> remove(String key) async {
    if (removeSucceeds) value = null;
    return removeSucceeds;
  }

  @override
  Future<bool> setString(String key, String value) async {
    if (setSucceeds) this.value = value;
    return setSucceeds;
  }
}
