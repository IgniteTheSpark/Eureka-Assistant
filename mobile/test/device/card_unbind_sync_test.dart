import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eureka/api/auth_store.dart';
import 'package:eureka/device/card_unbind_sync.dart';

void main() {
  const first = PendingCardUnbind(bindingId: 'binding-1', deleteData: false);
  const second = PendingCardUnbind(bindingId: 'binding-2', deleteData: true);

  test('sync persists before posting and retains a failed request', () async {
    final events = <String>[];
    final store = _MemoryStore(events);
    final api = _FakeApi(events)
      ..failures[first.bindingId] = StateError('offline');
    final coordinator = CardUnbindSyncCoordinator(store: store, api: api);

    expect(await coordinator.sync(first), isFalse);

    expect(await store.readAll(), {first.bindingId: first});
    expect(await coordinator.pendingBindingIds(), {first.bindingId});
    expect(events, ['write:${first.bindingId}', 'post:${first.bindingId}']);
  });

  test('two offline enqueues retain both binding requests', () async {
    final store = _MemoryStore(<String>[]);
    final api = _FakeApi(<String>[])
      ..failures[first.bindingId] = StateError('offline')
      ..failures[second.bindingId] = StateError('offline');
    final coordinator = CardUnbindSyncCoordinator(store: store, api: api);

    expect(await coordinator.sync(first), isFalse);
    expect(await coordinator.sync(second), isFalse);

    expect(await store.readAll(), {
      first.bindingId: first,
      second.bindingId: second,
    });
    expect(await coordinator.pendingBindingIds(), {
      first.bindingId,
      second.bindingId,
    });
  });

  test(
    'retry processes requests independently and clears only success',
    () async {
      final store = _MemoryStore(<String>[])
        ..values[first.bindingId] = first
        ..values[second.bindingId] = second;
      final api = _FakeApi(<String>[])
        ..failures[first.bindingId] = StateError('still offline');
      final coordinator = CardUnbindSyncCoordinator(store: store, api: api);

      expect(await coordinator.retryPending(), isFalse);

      expect(
        api.bindingIds,
        unorderedEquals([first.bindingId, second.bindingId]),
      );
      expect(await store.readAll(), {first.bindingId: first});
      expect(await coordinator.pendingBindingIds(), {first.bindingId});
    },
  );

  test('retry clears every independently successful request', () async {
    final store = _MemoryStore(<String>[])
      ..values[first.bindingId] = first
      ..values[second.bindingId] = second;
    final api = _FakeApi(<String>[]);
    final coordinator = CardUnbindSyncCoordinator(store: store, api: api);

    expect(await coordinator.retryPending(), isTrue);

    expect(
      api.bindingIds,
      unorderedEquals([first.bindingId, second.bindingId]),
    );
    expect(await store.readAll(), isEmpty);
  });

  test(
    'legacy single-record JSON is decoded and migrated to a collection',
    () async {
      SharedPreferences.setMockInitialValues({
        'eureka:pending_card_unbind:owner': jsonEncode(first.toJson()),
      });
      AuthStore.userId = 'owner';
      addTearDown(() => AuthStore.userId = null);
      final store = SharedPreferencesCardUnbindSyncStore();

      expect(await store.readAll(), {first.bindingId: first});

      final preferences = await SharedPreferences.getInstance();
      final migrated =
          jsonDecode(preferences.getString('eureka:pending_card_unbind:owner')!)
              as Map<String, dynamic>;
      expect(migrated['version'], 2);
      expect((migrated['requests'] as Map<String, dynamic>).keys, [
        first.bindingId,
      ]);
    },
  );

  test(
    'SharedPreferences store resolves the account key per operation',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesCardUnbindSyncStore();
      addTearDown(() => AuthStore.userId = null);

      AuthStore.userId = 'owner';
      await store.write(first);
      AuthStore.userId = 'other';
      expect(await store.readAll(), isEmpty);
      await store.write(second);

      AuthStore.userId = 'owner';
      expect(await store.readAll(), {first.bindingId: first});
      AuthStore.userId = 'other';
      expect(await store.readAll(), {second.bindingId: second});
    },
  );

  test('concurrent enqueues do not lose either binding request', () async {
    final preferences = _FakePreferences()..yieldBeforeSet = true;
    final store = SharedPreferencesCardUnbindSyncStore(
      preferences: preferences,
    );

    await Future.wait([store.write(first), store.write(second)]);

    expect(await store.readAll(), {
      first.bindingId: first,
      second.bindingId: second,
    });
  });

  test(
    'separate store instances serialize requests for the same account',
    () async {
      final preferences = _FakePreferences()..yieldBeforeSet = true;
      final firstStore = SharedPreferencesCardUnbindSyncStore(
        preferences: preferences,
      );
      final secondStore = SharedPreferencesCardUnbindSyncStore(
        preferences: preferences,
      );

      await Future.wait([firstStore.write(first), secondStore.write(second)]);

      expect(await firstStore.readAll(), {
        first.bindingId: first,
        second.bindingId: second,
      });
    },
  );

  test('false SharedPreferences enqueue prevents the server post', () async {
    final preferences = _FakePreferences()..setSucceeds = false;
    final store = SharedPreferencesCardUnbindSyncStore(
      preferences: preferences,
    );
    final api = _FakeApi(<String>[]);
    final coordinator = CardUnbindSyncCoordinator(
      store: store,
      api: api,
      accountScope: () => 'failed-write-account',
    );

    expect(await coordinator.sync(first), isFalse);
    expect(api.calls, isEmpty);
    expect(await coordinator.pendingBindingIds(), isNull);
    final anotherCoordinator = CardUnbindSyncCoordinator(
      store: store,
      api: api,
      accountScope: () => 'failed-write-account',
    );
    expect(await anotherCoordinator.pendingBindingIds(), isNull);
  });

  test('false SharedPreferences remove retains retryable state', () async {
    final preferences = _FakePreferences()..removeSucceeds = false;
    final store = SharedPreferencesCardUnbindSyncStore(
      preferences: preferences,
    );
    final api = _FakeApi(<String>[]);
    final coordinator = CardUnbindSyncCoordinator(store: store, api: api);
    await store.write(first);

    final ticket = await coordinator.enqueue(first);
    final result = await coordinator.flush(ticket);

    expect(result.serverSynced, isFalse);
    expect(api.calls, hasLength(1));
    expect(await store.readAll(), {first.bindingId: first});
  });

  test(
    'false SharedPreferences collection rewrite retains both requests',
    () async {
      final preferences = _FakePreferences();
      final store = SharedPreferencesCardUnbindSyncStore(
        preferences: preferences,
      );
      final api = _FakeApi(<String>[]);
      final coordinator = CardUnbindSyncCoordinator(store: store, api: api);
      await store.write(first);
      await store.write(second);
      preferences.setSucceeds = false;

      final result = await coordinator.flush(
        CardUnbindSyncTicket(request: first, accountScope: 'anonymous'),
      );

      expect(result.serverSynced, isFalse);
      expect(await store.readAll(), {
        first.bindingId: first,
        second.bindingId: second,
      });
    },
  );

  test('in-flight flush clears only its captured account scope', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesCardUnbindSyncStore();
    final api = _DeferredApi();
    final coordinator = CardUnbindSyncCoordinator(store: store, api: api);
    addTearDown(() => AuthStore.userId = null);

    AuthStore.userId = 'owner';
    final ticket = await coordinator.enqueue(first);
    final flush = coordinator.flush(ticket);
    await api.started.future;

    AuthStore.userId = 'other';
    await coordinator.enqueue(second);
    api.complete();
    expect((await flush).serverSynced, isTrue);

    AuthStore.userId = 'owner';
    expect(await store.readAll(), isEmpty);
    AuthStore.userId = 'other';
    expect(await store.readAll(), {second.bindingId: second});
  });

  test('in-flight flush preserves another same-account request', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesCardUnbindSyncStore();
    final api = _DeferredApi();
    final coordinator = CardUnbindSyncCoordinator(store: store, api: api);

    final ticket = await coordinator.enqueue(first);
    final flush = coordinator.flush(ticket);
    await api.started.future;

    await coordinator.enqueue(second);
    api.complete();
    expect((await flush).serverSynced, isTrue);
    expect(await store.readAll(), {second.bindingId: second});
  });

  test(
    'in-flight flush does not clear a newer request for the same binding',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesCardUnbindSyncStore();
      final api = _DeferredApi();
      final coordinator = CardUnbindSyncCoordinator(store: store, api: api);
      const newer = PendingCardUnbind(bindingId: 'binding-1', deleteData: true);

      final ticket = await coordinator.enqueue(first);
      final flush = coordinator.flush(ticket);
      await api.started.future;

      await coordinator.enqueue(newer);
      api.complete();
      expect((await flush).serverSynced, isTrue);
      expect(await store.readAll(), {newer.bindingId: newer});
    },
  );

  test(
    'never-completing API times out and leaves the request pending',
    () async {
      final store = _MemoryStore(<String>[]);
      final coordinator = CardUnbindSyncCoordinator(
        store: store,
        api: _NeverApi(),
        requestTimeout: const Duration(milliseconds: 10),
      );

      final ticket = await coordinator.enqueue(first);
      final result = await coordinator.flush(ticket);

      expect(result.serverSynced, isFalse);
      expect(result.message, cardUnbindSyncPendingWarning);
      expect(await store.readAll(), {first.bindingId: first});
      expect(await coordinator.pendingBindingIds(), {first.bindingId});
    },
  );
}

class _MemoryStore implements CardUnbindSyncStore {
  _MemoryStore(this.events);

  final List<String> events;
  final Map<String, PendingCardUnbind> values = {};

  @override
  Future<void> clear({
    String? accountScope,
    required PendingCardUnbind expectedRequest,
  }) async {
    if (values[expectedRequest.bindingId] != expectedRequest) return;
    events.add('clear:${expectedRequest.bindingId}');
    values.remove(expectedRequest.bindingId);
  }

  @override
  Future<Map<String, PendingCardUnbind>> readAll({
    String? accountScope,
  }) async => Map.unmodifiable(values);

  @override
  Future<void> write(PendingCardUnbind request, {String? accountScope}) async {
    events.add('write:${request.bindingId}');
    values[request.bindingId] = request;
  }
}

class _FakeApi implements CardUnbindSyncApi {
  _FakeApi(this.events);

  final List<String> events;
  final List<({String path, Map<String, dynamic> body})> calls = [];
  final Map<String, Object> failures = {};

  Iterable<String> get bindingIds =>
      calls.map((call) => call.path.split('/').elementAt(3));

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body) async {
    final bindingId = path.split('/').elementAt(3);
    events.add('post:$bindingId');
    calls.add((path: path, body: body));
    final failure = failures[bindingId];
    if (failure != null) throw failure;
    return {'ok': true};
  }
}

class _DeferredApi implements CardUnbindSyncApi {
  final started = Completer<void>();
  final _response = Completer<dynamic>();

  void complete() => _response.complete({'ok': true});

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body) {
    if (!started.isCompleted) started.complete();
    return _response.future;
  }
}

class _NeverApi implements CardUnbindSyncApi {
  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body) =>
      Completer<dynamic>().future;
}

class _FakePreferences implements CardUnbindSyncPreferences {
  final Map<String, String> values = {};
  bool setSucceeds = true;
  bool removeSucceeds = true;
  bool yieldBeforeSet = false;

  @override
  String? getString(String key) => values[key];

  @override
  Future<bool> remove(String key) async {
    if (removeSucceeds) values.remove(key);
    return removeSucceeds;
  }

  @override
  Future<bool> setString(String key, String value) async {
    if (yieldBeforeSet) await Future<void>.delayed(Duration.zero);
    if (setSucceeds) values[key] = value;
    return setSucceeds;
  }
}
