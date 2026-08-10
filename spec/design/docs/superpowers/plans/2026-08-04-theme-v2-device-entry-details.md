# Theme V2 Device Entry and Details Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Theme V2 icon-only connected-device entry, direct/dual-device routing, card and ring detail pages, and reliable device-specific unbinding that can be verified on the connected Android phone.

**Architecture:** Keep `DeviceController`, `DeviceSilentReconnect`, `RingConnection`, `RingReconnect`, and both native SDKs as the hardware owners. Add typed presentation state at the Theme V2 shell boundary, one small ring detail service for testable SDK orchestration, and one persistent card-unbind sync coordinator for the device-success/server-failure case. Card and ring pages share a Theme V2 visual scaffold but never share hardware operations.

**Tech Stack:** Flutter/Dart, `br_flutter_plugin_ble` v1.0.4, local `chiplet_ring`, SharedPreferences, FastAPI/SQLAlchemy, Flutter tests, pytest contract tests, Android ADB.

## Global Constraints

- Do not replace either hardware SDK or merge the card and ring controllers.
- Connected top-navigation states show device icons only; the visible connected label is removed while an accessible semantic label remains.
- Disconnected opens pairing; one connected device opens its detail; two connected devices open a compact anchored chooser.
- Device details contain only product-image placeholder, device name/state, basic information, and `解除绑定`.
- Card fields: name, state, SN, battery, and used/total storage.
- Ring fields: name, state, battery, MAC, firmware, and hardware version; never invent a ring SN.
- Card unbind preserves the keep-recordings and delete-recordings choices.
- Device-side card unbind success immediately clears local state even if server sync fails.
- Ring unbind order is reconnect-forget, BLE disconnect, persisted-MAC removal, and connection-state clear.
- A ring SDK disconnect failure still clears local binding and returns a visible warning; it is never swallowed silently.
- Real product images are excluded; placeholders must be replaceable and visibly illustrative.
- Ring native acceptance is Android-only because the checked-in plugin has no iOS implementation.
- Never exercise real card recording deletion without explicit user approval.

---

## File Structure

### Create

- `mobile/lib/device/card_unbind_sync.dart` — persist and retry the server half of card unbind.
- `mobile/lib/ring/ring_device_service.dart` — load ring information and enforce ordered unbind.
- `mobile/lib/theme_v2/device/theme_v2_device_detail_scaffold.dart` — shared view-only detail layout.
- `mobile/lib/theme_v2/device/theme_v2_card_device_detail_page.dart` — card detail and confirmation flow.
- `mobile/lib/theme_v2/device/theme_v2_ring_device_detail_page.dart` — ring detail and confirmation flow.
- `mobile/test/device/card_unbind_sync_test.dart`
- `mobile/test/ring/ring_device_service_test.dart`
- `mobile/test/theme_v2/device/theme_v2_device_detail_page_test.dart`

### Modify

- `mobile/lib/theme_v2/shell/device_status_summary.dart`
- `mobile/lib/theme_v2/shell/theme_v2_device_status_adapter.dart`
- `mobile/lib/theme_v2/shell/theme_v2_global_top_nav.dart`
- `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- `mobile/lib/pages/device_pairing_page.dart`
- `mobile/lib/device/device_controller.dart`
- `mobile/lib/device/device_silent_reconnect.dart`
- `mobile/lib/ring/ring_connection.dart`
- `theme_v2_service/app/domains/devices/service.py`
- Relevant controller, reconnect, shell, inbox, and golden tests.

---

### Task 1: Typed device presence and icon-only global entry

**Files:**
- Modify: `mobile/lib/theme_v2/shell/device_status_summary.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_device_status_adapter.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_global_top_nav.dart`
- Test: `mobile/test/theme_v2/shell/theme_v2_device_status_adapter_test.dart`
- Test: `mobile/test/theme_v2/shell/theme_v2_shell_test.dart`

**Interfaces:**
- Produces: `ThemeV2DevicePresence`, `ThemeV2DeviceTarget`, `DeviceStatusSummary.presence`, `DeviceStatusSummary.directTarget`.
- Consumes: card state/binding/error and ring connection state from existing controllers.

- [ ] **Step 1: Write failing summary tests**

Add exact expectations for the four presence states:

```dart
expect(disconnected.presence, ThemeV2DevicePresence.none);
expect(card.presence, ThemeV2DevicePresence.card);
expect(ring.presence, ThemeV2DevicePresence.ring);
expect(dual.presence, ThemeV2DevicePresence.both);
expect(card.directTarget, ThemeV2DeviceTarget.card);
expect(ring.directTarget, ThemeV2DeviceTarget.ring);
expect(dual.directTarget, isNull);
```

- [ ] **Step 2: Run the adapter test to prove the API is missing**

Run:

```bash
cd mobile
flutter test test/theme_v2/shell/theme_v2_device_status_adapter_test.dart
```

Expected: FAIL because the typed presence API does not exist.

- [ ] **Step 3: Implement the stable typed contract**

Use this model in `device_status_summary.dart`:

```dart
enum ThemeV2DevicePresence { none, card, ring, both }

enum ThemeV2DeviceTarget { pairing, card, ring }

@immutable
class DeviceStatusSummary {
  const DeviceStatusSummary({
    required this.kind,
    required this.label,
    required this.presence,
  });

  const DeviceStatusSummary.disconnected({this.label = '未连接'})
    : kind = DeviceStatusSummaryKind.disconnected,
      presence = ThemeV2DevicePresence.none;

  const DeviceStatusSummary.connected({
    required this.presence,
    this.label = '已连接',
  }) : kind = DeviceStatusSummaryKind.connected;

  const DeviceStatusSummary.attention({
    required this.presence,
    this.label = '需要处理',
  }) : kind = DeviceStatusSummaryKind.attention;

  final DeviceStatusSummaryKind kind;
  final String label;
  final ThemeV2DevicePresence presence;

  ThemeV2DeviceTarget? get directTarget => switch (presence) {
    ThemeV2DevicePresence.none => ThemeV2DeviceTarget.pairing,
    ThemeV2DevicePresence.card => ThemeV2DeviceTarget.card,
    ThemeV2DevicePresence.ring => ThemeV2DeviceTarget.ring,
    ThemeV2DevicePresence.both => null,
  };
}
```

Map card/ring/dual states to matching presence. Only surface card attention when `cardIsBound` is true so a post-unbind sync warning cannot look connected.

- [ ] **Step 4: Write failing icon-only widget tests**

For card, ring, and dual summaries assert that the visible connection label is absent, the semantic label remains, and the hit target is at least `44 × 44`. Preserve `未连接` as visible text in the disconnected state.

```dart
expect(find.text('录音卡已连接'), findsNothing);
expect(find.bySemanticsLabel('设备：录音卡已连接'), findsOneWidget);
final size = tester.getSize(find.bySemanticsLabel('设备：录音卡已连接'));
expect(size.width, greaterThanOrEqualTo(44));
expect(size.height, greaterThanOrEqualTo(44));
```

- [ ] **Step 5: Implement connected glyphs**

Render the label row only for `ThemeV2DevicePresence.none`. Connected states use a square icon control and this glyph mapping:

```dart
Widget connectedGlyph(ThemeV2DevicePresence presence, Color color) {
  return switch (presence) {
    ThemeV2DevicePresence.card =>
      Icon(Icons.contactless_outlined, size: 20, color: color),
    ThemeV2DevicePresence.ring =>
      Icon(Icons.circle_outlined, size: 20, color: color),
    ThemeV2DevicePresence.both => Stack(
      alignment: Alignment.center,
      children: [
        Transform.translate(
          offset: const Offset(-4, 3),
          child: Icon(Icons.contactless_outlined, size: 15, color: color),
        ),
        Transform.translate(
          offset: const Offset(5, -4),
          child: Icon(Icons.circle_outlined, size: 15, color: color),
        ),
      ],
    ),
    ThemeV2DevicePresence.none =>
      Icon(Icons.devices_outlined, size: 18, color: color),
  };
}
```

- [ ] **Step 6: Verify and commit**

Run:

```bash
cd mobile
flutter test test/theme_v2/shell/theme_v2_device_status_adapter_test.dart test/theme_v2/shell/theme_v2_shell_test.dart
```

Expected: PASS.

Commit:

```bash
git add mobile/lib/theme_v2/shell/device_status_summary.dart mobile/lib/theme_v2/shell/theme_v2_device_status_adapter.dart mobile/lib/theme_v2/shell/theme_v2_global_top_nav.dart mobile/test/theme_v2/shell/theme_v2_device_status_adapter_test.dart mobile/test/theme_v2/shell/theme_v2_shell_test.dart
git commit -m "feat(theme-v2): type connected device entry state"
```

---

### Task 2: Testable ring information and real unbind semantics

**Files:**
- Create: `mobile/lib/ring/ring_device_service.dart`
- Modify: `mobile/lib/ring/ring_connection.dart`
- Create: `mobile/test/ring/ring_device_service_test.dart`

**Interfaces:**
- Produces: `RingDeviceInfo`, `RingUnbindResult`, `RingDeviceGateway`, `RingBindingStore`, `RingDeviceService.loadInfo()`, `RingDeviceService.unbind()`.
- Consumes: the ring SDK, `RingReconnect.forget`, SharedPreferences `ring_mac`, and `RingConnection.markUnbound`.

- [ ] **Step 1: Write the failing ordered-unbind test**

```dart
final operations = <String>[];
final service = RingDeviceService(
  gateway: _FakeRingGateway(operations),
  bindingStore: _FakeRingBindingStore(operations, mac: 'AA:BB'),
  forgetReconnect: () => operations.add('forget'),
  markUnbound: () => operations.add('mark-unbound'),
);

await service.unbind();

expect(operations, [
  'forget',
  'disconnect',
  'clear-mac',
  'mark-unbound',
]);
```

Also test that `loadInfo()` maps `{fw: '1.2', hw: 'A3'}` and tolerates null battery/version values.
Add a disconnect-failure case and assert `clear-mac` and `mark-unbound` still
run, while the returned result contains the visible warning.

- [ ] **Step 2: Run the test to prove the service is absent**

Run:

```bash
cd mobile
flutter test test/ring/ring_device_service_test.dart
```

Expected: FAIL because `ring_device_service.dart` does not exist.

- [ ] **Step 3: Implement the narrow service**

Use these public interfaces:

```dart
@immutable
class RingDeviceInfo {
  const RingDeviceInfo({
    required this.mac,
    this.batteryPct,
    this.firmwareVersion,
    this.hardwareVersion,
  });

  final String? mac;
  final int? batteryPct;
  final String? firmwareVersion;
  final String? hardwareVersion;
}

abstract interface class RingDeviceGateway {
  Future<int?> getBattery();
  Future<Map?> getVersion();
  Future<void> disconnect();
}

abstract interface class RingBindingStore {
  Future<String?> readMac();
  Future<void> clearMac();
}

class RingDeviceService {
  RingDeviceService({
    required this.gateway,
    required this.bindingStore,
    required this.forgetReconnect,
    required this.markUnbound,
  });

  factory RingDeviceService.production();

  final RingDeviceGateway gateway;
  final RingBindingStore bindingStore;
  final VoidCallback forgetReconnect;
  final VoidCallback markUnbound;

  Future<RingDeviceInfo> loadInfo();
  Future<RingUnbindResult> unbind();
}
```

Define the explicit result:

```dart
@immutable
class RingUnbindResult {
  const RingUnbindResult({this.warning});

  final String? warning;
  bool get hasWarning => warning != null;
}
```

`loadInfo()` reads MAC first and catches battery/version failures independently.
`unbind()` calls `forgetReconnect()` before disconnect, captures any disconnect
failure, then always clears `ring_mac` and calls `markUnbound()`. It returns a
result with `warning: '本地绑定已解除，蓝牙断开可能未完成'` when disconnect failed;
it must not silently discard the exception.

Add this explicit transition to `RingConnection`:

```dart
void markUnbound() {
  if (conn == RingConnState.disconnected) return;
  conn = RingConnState.disconnected;
  notifyListeners();
}
```

- [ ] **Step 4: Verify and commit**

Run:

```bash
cd mobile
flutter test test/ring/ring_device_service_test.dart
```

Expected: PASS.

Commit:

```bash
git add mobile/lib/ring/ring_device_service.dart mobile/lib/ring/ring_connection.dart mobile/test/ring/ring_device_service_test.dart
git commit -m "feat(ring): preserve real unbind semantics"
```

---

### Task 3: Card local-unbind outcome and persistent server compensation

**Files:**
- Create: `mobile/lib/device/card_unbind_sync.dart`
- Modify: `mobile/lib/device/device_controller.dart`
- Modify: `mobile/lib/device/device_silent_reconnect.dart`
- Modify: `theme_v2_service/app/domains/devices/service.py`
- Create: `mobile/test/device/card_unbind_sync_test.dart`
- Modify: `mobile/test/device_controller_test.dart`
- Modify: `mobile/test/device_silent_reconnect_test.dart`
- Modify: `theme_v2_service/tests/contract/test_device_api.py`

**Interfaces:**
- Produces: `PendingCardUnbind`, `CardUnbindSyncCoordinator.sync`, `retryPending`, `pendingBindingIds`, and `DeviceUnbindResult`.
- Consumes: `ApiClient.postJson`, account-scoped SharedPreferences, the real card SDK unbind/clear calls, and the existing backend endpoint.

- [ ] **Step 1: Write failing persistence and retry tests**

Use in-memory API/store fakes and assert:

```dart
const request = PendingCardUnbind(
  bindingId: 'binding-1',
  deleteData: false,
);
api.fail = true;
expect(await coordinator.sync(request), isFalse);
expect(await store.read(), request);
expect(await coordinator.pendingBindingIds(), {'binding-1'});

api.fail = false;
expect(await coordinator.retryPending(), isTrue);
expect(await store.read(), isNull);
```

Record the fake calls and prove `write` happens before `post`. The retry test must use only the API/store seam and contain no BLE call.

- [ ] **Step 2: Run the test to prove the coordinator is absent**

Run:

```bash
cd mobile
flutter test test/device/card_unbind_sync_test.dart
```

Expected: FAIL because the coordinator does not exist.

- [ ] **Step 3: Implement the account-scoped coordinator**

Define:

```dart
@immutable
class PendingCardUnbind {
  const PendingCardUnbind({
    required this.bindingId,
    required this.deleteData,
  });

  final String bindingId;
  final bool deleteData;
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
  });

  factory CardUnbindSyncCoordinator.production();

  Future<bool> sync(PendingCardUnbind request);
  Future<bool> retryPending();
  Future<Set<String>> pendingBindingIds();
}
```

The production SharedPreferences key is resolved at operation time:

```dart
String get key =>
    'eureka:pending_card_unbind:${AuthStore.userId ?? 'anonymous'}';
```

Persist `{binding_id, delete_data}` before posting. Clear only after a 2xx response.

- [ ] **Step 4: Write failing controller outcome tests**

Configure `MockDeviceTransport` to return:

```dart
const DeviceUnbindResult(
  serverSynced: false,
  message: '设备已解绑，服务端同步待重试',
)
```

Then assert:

```dart
final result = await controller.unbind(deleteData: false);
expect(result?.serverSynced, isFalse);
expect(controller.device, isNull);
expect(controller.state, DeviceConnState.idle);
expect(controller.errorMessage, '设备已解绑，服务端同步待重试');
```

Add a hardware-failure fake that throws `DeviceOperationException` and assert the bound device remains present with `DeviceConnState.error`.

- [ ] **Step 5: Implement the typed unbind result through the controller**

Change the transport contract to:

```dart
@immutable
class DeviceUnbindResult {
  const DeviceUnbindResult({
    required this.serverSynced,
    this.message,
  });

  const DeviceUnbindResult.complete()
    : serverSynced = true,
      message = null;

  final bool serverSynced;
  final String? message;
}

abstract class DeviceTransport {
  Future<DeviceUnbindResult> unbind(
    DeviceInfo device, {
    required bool deleteData,
  });
}
```

After the SDK unbind and native cache clear succeed, call the coordinator. Return `complete` on server success or the pending-sync result above on failure. Do not throw after local hardware success.

Change `DeviceController.unbind` to `Future<DeviceUnbindResult?>`. Any returned result clears `device`/`discovered`, sets `idle`, and retains only a pending-sync warning in `error`. A thrown hardware error keeps the device and sets `error` state.

- [ ] **Step 6: Write failing reconnect-filter tests**

Inject a fake sync coordinator into `DeviceSilentReconnect` and cover:

```dart
sync.pendingIds = {'binding-1'};
sync.retrySucceeds = false;
await reconnect.tryReconnect(sessionKey: 1);
expect(ble.startScanCalls, 0);
expect(ble.connectCalls, 0);
```

Add a second case where retry succeeds, pending IDs clear, and the active server binding is allowed to drive reconnect.

- [ ] **Step 7: Integrate compensation before reconnect**

At the start of `tryReconnect`, call `retryPending()`. In `_loadBindings`, exclude rows whose `binding_id` remains in `pendingBindingIds()`. This blocks a stale server binding without repeating the hardware unbind.

- [ ] **Step 8: Make backend unbind replay idempotent**

Extend the contract test:

```python
replayed = await client.post(
    f"/api/cards/{binding['binding_id']}/unbind",
    headers=headers,
    json={"delete_data": False},
)
assert replayed.status_code == 200
assert replayed.json()["binding"]["bind_status"] == "unbound"
```

In `service.unbind_card`, query by `binding_id` and `user_id` without requiring `bound`. Mutate timestamps/status only when currently bound; return an already-unbound owner record unchanged. Foreign users and unknown IDs remain 404.

- [ ] **Step 9: Run mobile and backend tests**

Run:

```bash
cd mobile
flutter test test/device/card_unbind_sync_test.dart test/device_controller_test.dart test/device_silent_reconnect_test.dart
cd ../theme_v2_service
pytest tests/contract/test_device_api.py -q
```

Expected: all tests PASS.

- [ ] **Step 10: Commit the reliability slice**

```bash
git add mobile/lib/device/card_unbind_sync.dart mobile/lib/device/device_controller.dart mobile/lib/device/device_silent_reconnect.dart mobile/test/device/card_unbind_sync_test.dart mobile/test/device_controller_test.dart mobile/test/device_silent_reconnect_test.dart theme_v2_service/app/domains/devices/service.py theme_v2_service/tests/contract/test_device_api.py
git commit -m "fix(device): preserve local unbind across sync failures"
```

---

### Task 4: Theme V2 card and ring detail surfaces

**Files:**
- Create: `mobile/lib/theme_v2/device/theme_v2_device_detail_scaffold.dart`
- Create: `mobile/lib/theme_v2/device/theme_v2_card_device_detail_page.dart`
- Create: `mobile/lib/theme_v2/device/theme_v2_ring_device_detail_page.dart`
- Create: `mobile/test/theme_v2/device/theme_v2_device_detail_page_test.dart`

**Interfaces:**
- Consumes: `DeviceController`, `DeviceUnbindResult`, `DeviceSilentReconnect.stop`, `RingDeviceService`, and `RingConnection`.
- Produces: the two production detail routes and a shared view-only scaffold.

- [ ] **Step 1: Write failing field-rendering tests**

Mount a card page with this fake device:

```dart
const DeviceInfo(
  id: 'card-1',
  bindingId: 'binding-1',
  name: 'UReka 录音卡',
  serial: 'SN-001',
  cardDeviceUuid: 'device-uuid',
  cardAppUuid: 'app-uuid',
  cardMac: 'AA:BB',
  batteryPct: 86,
  storageUsedGb: 3.5,
  storageTotalGb: 64,
)
```

Assert `SN-001`, `86%`, `3.5GB / 64GB`, `已连接`, and `解除绑定` appear. Assert device settings, firmware update, and recording management are absent.

Mount the ring page with MAC `CC:DD`, battery `72`, firmware `1.2.3`, and hardware `A3`. Assert those values appear and no `SN` label exists.

- [ ] **Step 2: Run the test to prove the pages are absent**

Run:

```bash
cd mobile
flutter test test/theme_v2/device/theme_v2_device_detail_page_test.dart
```

Expected: FAIL because the Theme V2 device pages do not exist.

- [ ] **Step 3: Implement the shared view-only scaffold**

Use this contract:

```dart
class ThemeV2DeviceDetailScaffold extends StatelessWidget {
  const ThemeV2DeviceDetailScaffold({
    super.key,
    required this.title,
    required this.deviceName,
    required this.connected,
    required this.hero,
    required this.information,
    required this.unbinding,
    required this.onUnbind,
  });

  final String title;
  final String deviceName;
  final bool connected;
  final Widget hero;
  final List<ThemeV2DeviceInfoRow> information;
  final bool unbinding;
  final VoidCallback? onUnbind;
}
```

Use Theme V2 tokens, a contextual back app bar, a stable `180px` hero region, independent information rows, and a bottom critical `解除绑定` action disabled while busy.

- [ ] **Step 4: Implement card detail and confirmation**

Use injectable defaults:

```dart
class ThemeV2CardDeviceDetailPage extends StatefulWidget {
  const ThemeV2CardDeviceDetailPage({
    super.key,
    this.controller,
    this.stopSilentReconnect,
    this.refreshOnLoad = true,
  });

  final DeviceController? controller;
  final Future<void> Function()? stopSilentReconnect;
  final bool refreshOnLoad;
}
```

The confirmation returns `bool? deleteData`: null cancels, false keeps recordings, true deletes recordings. After confirmation:

```dart
await stopSilentReconnect();
final result = await controller.unbind(deleteData: deleteData);
if (result == null || !context.mounted) return;
if (!result.serverSynced && result.message != null) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(result.message!)),
  );
}
Navigator.of(context).pop();
```

If hardware unbind fails, keep the detail open and show `controller.errorMessage`.

- [ ] **Step 5: Implement ring detail and confirmation**

Accept an injectable `RingDeviceService` and connection `Listenable`. Load fields through `loadInfo()`, render missing values as `--`, confirm `解除绑定`, await `service.unbind()`, and pop only after local binding clear.

Use `RingArt(size: 132)` as the honest temporary ring illustration. Use a Theme V2 card-shaped illustration with `Icons.contactless_outlined` for the recorder; keep both hero slots asset-replaceable.

- [ ] **Step 6: Add interaction tests**

For card: tap `解除绑定`, assert both `仅解除绑定，保留录音` and `解除绑定并删除录音`, choose keep, and assert stop-reconnect precedes `deleteData == false`.

For ring: confirm unbind and assert one service call. Add a null-field result and assert each missing value renders `--` without an exception. Add a warning result and assert the page closes after showing `本地绑定已解除，蓝牙断开可能未完成` through the route-level `ScaffoldMessenger`.

- [ ] **Step 7: Verify and commit**

Run:

```bash
cd mobile
flutter test test/theme_v2/device/theme_v2_device_detail_page_test.dart
```

Expected: PASS.

Commit:

```bash
git add mobile/lib/theme_v2/device mobile/test/theme_v2/device/theme_v2_device_detail_page_test.dart
git commit -m "feat(theme-v2): add hardware detail surfaces"
```

---

### Task 5: Direct routing, dual-device chooser, and pairing handoff

**Files:**
- Modify: `mobile/lib/theme_v2/shell/theme_v2_global_top_nav.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- Modify: `mobile/lib/pages/device_pairing_page.dart`
- Modify: `mobile/test/theme_v2/shell/theme_v2_shell_test.dart`
- Modify: `mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart`
- Modify: `mobile/test/theme_v2/shell/theme_v2_device_status_adapter_test.dart`
- Modify: `mobile/test/theme_v2/calendar/theme_v2_calendar_golden_test.dart`
- Modify: `mobile/test/theme_v2/library/theme_v2_library_golden_test.dart`
- Modify: `mobile/test/theme_v2/inbox/reka_inbox_page_test.dart`

**Interfaces:**
- Consumes: typed device targets and both new detail pages.
- Produces: `ThemeV2GlobalTopNav.onDeviceSelected` plus production pairing/card/ring routing.

- [ ] **Step 1: Write failing direct and dual routing tests**

Capture target selection:

```dart
final selected = <ThemeV2DeviceTarget>[];
ThemeV2GlobalTopNav(
  deviceStatus: summary,
  onDeviceSelected: selected.add,
  onNotificationsPressed: () {},
)
```

Assert card-only emits `.card`, ring-only emits `.ring`, and disconnected emits `.pairing`. For dual presence, the first tap emits nothing and opens a popup containing `UReka 录音卡` and `UReka 戒指`; tapping either row emits the matching target.

- [ ] **Step 2: Run shell tests to prove the route API is absent**

Run:

```bash
cd mobile
flutter test test/theme_v2/shell/theme_v2_shell_test.dart test/theme_v2/shell/theme_v2_navigation_state_test.dart
```

Expected: FAIL because `onDeviceSelected` and the dual chooser do not exist.

- [ ] **Step 3: Implement the chooser inside the button context**

Replace `VoidCallback onDevicePressed` with:

```dart
final ValueChanged<ThemeV2DeviceTarget> onDeviceSelected;
```

For a direct target, emit immediately. For dual presence, obtain the button's `RenderBox`, convert its rectangle to global coordinates, and use `showMenu<ThemeV2DeviceTarget>` anchored below the button. Provide two `PopupMenuItem` rows with canonical icon, device name, and `已连接` secondary text. Emit only a non-null selection.

- [ ] **Step 4: Route production shell selections**

Rename the shell test seam to `ValueChanged<ThemeV2DeviceTarget>? onDeviceSelected` and implement:

```dart
void _openDevice(BuildContext context, ThemeV2DeviceTarget target) {
  final callback = widget.onDeviceSelected;
  if (callback != null) {
    callback(target);
    return;
  }
  final page = switch (target) {
    ThemeV2DeviceTarget.pairing => const DevicePairingPage(),
    ThemeV2DeviceTarget.card => const ThemeV2CardDeviceDetailPage(),
    ThemeV2DeviceTarget.ring => const ThemeV2RingDeviceDetailPage(),
  };
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => page),
  );
}
```

Update every existing top-nav test/golden constructor to accept and ignore the target when not under test.

- [ ] **Step 5: Route successful pairing to the new details**

In `device_pairing_page.dart`, change only the post-connect destinations:

```dart
MaterialPageRoute<void>(
  builder: (_) => const ThemeV2CardDeviceDetailPage(),
)
```

and:

```dart
MaterialPageRoute<void>(
  builder: (_) => const ThemeV2RingDeviceDetailPage(),
)
```

Do not change scanning, BLE connection, saved MAC, or server binding logic.

- [ ] **Step 6: Run affected Theme V2 tests**

Run:

```bash
cd mobile
flutter test test/theme_v2/shell test/theme_v2/device test/theme_v2/inbox/reka_inbox_page_test.dart test/theme_v2/calendar/theme_v2_calendar_golden_test.dart test/theme_v2/library/theme_v2_library_golden_test.dart
```

Expected: PASS with no unintended golden changes.

- [ ] **Step 7: Commit the routing slice**

```bash
git add mobile/lib/theme_v2/shell/theme_v2_global_top_nav.dart mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/lib/pages/device_pairing_page.dart mobile/test/theme_v2/shell mobile/test/theme_v2/inbox/reka_inbox_page_test.dart mobile/test/theme_v2/calendar/theme_v2_calendar_golden_test.dart mobile/test/theme_v2/library/theme_v2_library_golden_test.dart
git commit -m "feat(theme-v2): route connected hardware details"
```

---

### Task 6: Full regression and Android acceptance

**Files:**
- Modify only files required by failures directly caused by Tasks 1–5.
- Keep generated screenshots and build outputs out of git unless the user requests them.

**Interfaces:**
- Consumes: the completed entry, detail, and unbind flows.
- Produces: formatted, analyzed, regression-tested code and Android acceptance evidence.

- [ ] **Step 1: Format changed Dart surfaces**

Run:

```bash
cd mobile
dart format lib/device/card_unbind_sync.dart lib/device/device_controller.dart lib/device/device_silent_reconnect.dart lib/ring/ring_connection.dart lib/ring/ring_device_service.dart lib/pages/device_pairing_page.dart lib/theme_v2/device lib/theme_v2/shell test/device test/ring test/theme_v2/device test/theme_v2/shell
```

Expected: formatting completes successfully.

- [ ] **Step 2: Run focused static analysis**

Run:

```bash
cd mobile
flutter analyze lib/device/card_unbind_sync.dart lib/device/device_controller.dart lib/device/device_silent_reconnect.dart lib/ring/ring_connection.dart lib/ring/ring_device_service.dart lib/pages/device_pairing_page.dart lib/theme_v2/device lib/theme_v2/shell test/device test/ring test/theme_v2/device test/theme_v2/shell
```

Expected: `No issues found!`.

- [ ] **Step 3: Run the relevant automated suite**

Run:

```bash
cd mobile
flutter test test/device_controller_test.dart test/device_silent_reconnect_test.dart test/device/card_unbind_sync_test.dart test/ring/ring_device_service_test.dart test/theme_v2/shell test/theme_v2/device test/theme_v2/inbox/reka_inbox_page_test.dart
cd ../theme_v2_service
pytest tests/contract/test_device_api.py -q
```

Expected: all Flutter and pytest tests PASS.

- [ ] **Step 4: Build and launch on the connected Android phone**

Run:

```bash
cd mobile
flutter devices
flutter build apk --debug
flutter run -d RFCY71B21YK
```

Expected: the app starts using this branch's isolated Theme V2 backend configuration.

- [ ] **Step 5: Verify entry and information without destructive actions**

1. Card only: top bar shows one icon without text and opens card detail directly.
2. Verify live card name, state, SN, battery, and storage.
3. Cancel card unbind and confirm connection remains intact.
4. Ring only: top bar opens ring detail and shows battery, MAC, firmware, and hardware.
5. Both: compact chooser routes to each correct detail.
6. Light/dark: entry and detail surfaces remain readable.

- [ ] **Step 6: Verify safe real unbind paths**

1. Ring: confirm unbind, force-stop/relaunch, verify no reconnect, and verify it is discoverable for pairing.
2. Re-pair ring and verify normal connection.
3. Card: choose `仅解除绑定，保留录音`, force-stop/relaunch, verify no reconnect, and verify it appears in pairing.
4. Do not choose `解除绑定并删除录音` without fresh explicit approval.

- [ ] **Step 7: Inspect the final diff**

Run:

```bash
git status --short
git diff --check
git diff --stat
```

Expected: no whitespace errors, generated build outputs are unstaged, and `spec/design/redesignureka.pen` plus unrelated user documents remain untouched.

Do not push or merge into `main` unless the user separately requests it.

---

## Self-Review Result

- Spec coverage: entry states, direct/dual routing, both field sets, card/ring unbind semantics, server partial success, placeholders, accessibility, Android boundary, and device acceptance all map to tasks.
- Placeholder scan: no implementation step relies on unspecified error handling or unnamed tests.
- Type consistency: `ThemeV2DeviceTarget`, `RingDeviceInfo`, `PendingCardUnbind`, and `DeviceUnbindResult` use the same names and signatures throughout.
- Architecture check: existing SDK/controller ownership stays intact; new classes are narrow adapters or compensation state.
- Safety check: real recording deletion remains blocked without explicit approval.
- Workspace check: `spec/design/redesignureka.pen` and existing unrelated untracked documents remain outside implementation commits.
