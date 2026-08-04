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
}

class _MemoryStore implements CardUnbindSyncStore {
  _MemoryStore(this.events);

  final List<String> events;
  PendingCardUnbind? value;

  @override
  Future<void> clear() async {
    events.add('clear');
    value = null;
  }

  @override
  Future<PendingCardUnbind?> read() async => value;

  @override
  Future<void> write(PendingCardUnbind request) async {
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
