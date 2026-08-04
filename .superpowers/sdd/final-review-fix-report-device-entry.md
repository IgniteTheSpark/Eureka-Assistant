# Theme V2 Device Entry/Details Final Review Fix Report

## Status

All five Important final-review findings are implemented and verified. No backend, API contract, capture/ASR, or physical-device behavior was broadened.

## Findings addressed

### 1. Stale card refresh could resurrect a successfully unbound device

- Added an operation revision to `DeviceController`.
- A refresh captures the current revision and discards every deferred result after an unbind, connect, logout, disconnect event, or newer operation invalidates it.
- Refresh returns immediately while unbind is active.
- The detail page's deferred initialization refresh can no longer restore a card after the destructive route has closed.
- A harmless disconnected refresh does not erase the deferred server-sync warning.

Regression coverage proves that successful unbind, logout, disconnect, and a newer connect all win over an older refresh, including a refresh that was already inside an awaited transport call when unbind began.

### 2. Card compensation could retain only one pending request

- Replaced the single-record SharedPreferences payload with an account-scoped version-2 request map keyed by binding ID.
- Added legacy single-record decoding and automatic migration.
- Added typed `CardUnbindSyncTicket` and `CardUnbindSyncResult` values so enqueue and flush retain an immutable account/request scope.
- `write` is an upsert; `clear` removes only the exact expected request; retry handles every pending request independently.
- SharedPreferences read/modify/write is serialized globally across store instances, preventing two coordinator instances from losing each other's enqueue.
- Unknown or malformed persisted state remains fail-closed across coordinator instances.
- Every SharedPreferences boolean result is checked. Failed write prevents the server request; failed removal/rewrite retains retryable state.
- Server calls are bounded by a test-injectable timeout, defaulting to five seconds.

Coverage includes two offline unbinds, partial and complete retries, legacy migration, account isolation, same-account and cross-account races, same-ID replacement, single-store and separate-store concurrent enqueue, persistence failures, and a server call that never completes.

### 3. Pairing route dropped Theme V2 route theming

- Generalized the route wrapper to `themeV2Route<T>`, accepting an arbitrary child builder.
- `themeV2DeviceRoute` delegates to the generalized wrapper.
- The production App Shell now opens pairing through the same Theme V2 wrapper used for card and ring details.
- The wrapper preserves the existing `EurekaTheme` extension while applying Theme V2 tokens and Geist typography.

The focused navigation test now asserts Geist, `ThemeV2Tokens`, and `EurekaTheme` for pairing, card detail, and ring detail routes. Pairing scan/connect ownership and behavior were not changed.

### 4. Card server compensation blocked the destructive route

- Split card unbind into irreversible local work and durable server compensation.
- The transport awaits only hardware unbind, native cache clear, and durable enqueue before returning a pending result.
- The controller clears local device state immediately, then observes the bounded flush future only to surface the exact warning `设备已解绑，服务端同步待重试` on failure.
- The detail page captures the root `ScaffoldMessenger`, closes immediately after local success, and can show the later warning without restoring the route or connected device.
- A narrow `CardUnbindHardware` seam tests the real transport flow without physical hardware.
- Hardware failure still retains the device and keeps the detail route open; logout remains disconnect-only.

Coverage proves that a never-completing API cannot delay local completion, the durable request remains pending after timeout, the route closes after exactly one hardware unbind, and a later failure updates both controller warning state and user-visible snackbar.

### 5. Delayed ring reconnect reads could undo `forget()`

- Added narrow reconnect gateway and binding-store interfaces while preserving production singleton adapters.
- Added an operation revision to invalidate delayed `start`, `refreshMac`, and `resume` work after `forget`, `pause`, or dispose.
- A delayed binding-store read can no longer restore a forgotten MAC or trigger scan/connect.
- Added direct tests for independent battery and version gateway failures; existing partial-information behavior remains intact.
- Ring ordered unbind and its exact disconnect warning behavior are unchanged.

## TDD evidence

### Finding 1 — controller refresh ordering

- RED: `flutter test test/device_controller_test.dart`
- Observed four ordering failures: an old device was restored after unbind, logout, and disconnect, and an older SN1 refresh replaced a newer SN2 connect.
- Additional RED: a refresh already inside its transport await restored `DeviceInfo` after a successful unbind.
- GREEN: revision-guard coverage passes for every ordering case, and the detail-page deferred-refresh regression passes.

### Finding 2 — multi-request compensation

- RED: `flutter test test/device/card_unbind_sync_test.dart`
- Initial compile failures identified the missing `readAll`, `enqueue`, `flush`, ticket, result, and timeout contracts.
- Additional RED: concurrent enqueue through separate store instances retained only `binding-2`, losing `binding-1`.
- Additional RED: a failed enqueue did not propagate account-scoped unknown state to another coordinator instance.
- GREEN: the complete persistence, migration, concurrency, retry, fail-closed, and timeout suite passes.

### Finding 3 — pairing route theme

- RED: focused navigation test expected Geist on the pairing route but received `Manrope_regular`.
- GREEN: pairing, card, and ring routes all retain Theme V2 typography/tokens plus the legacy theme extension.

### Finding 4 — non-blocking compensation

- RED: focused controller/page tests initially failed to compile because the hardware seam, `unbindHardware`, and pending unbind result did not exist.
- Additional RED: after route close, the deferred warning was not initially asserted at the stable animation frame.
- Additional RED: a subsequent disconnected refresh cleared the controller's background-sync warning.
- GREEN: local completion is immediate, late warning delivery survives route pop and refresh, hardware failure remains blocking, and the transport timeout leaves durable compensation pending.

### Finding 5 — ring reconnect invalidation

- RED: `flutter test test/ring/ring_reconnect_test.dart` failed to compile because injectable gateway/store contracts did not exist.
- GREEN: delayed `resume` and `refreshMac` reads cannot scan or connect after `forget`.
- Additional battery/version throwing-gateway tests passed with the existing partial-info production behavior.

## Final verification

- `dart format` over all 13 changed Dart files — 13 files formatted; final pass clean.
- `flutter test test/device_controller_test.dart test/device/card_unbind_sync_test.dart test/device_silent_reconnect_test.dart test/ring/ring_device_service_test.dart test/ring/ring_reconnect_test.dart test/theme_v2/shell test/theme_v2/device` — **82 tests passed**.
- `flutter analyze` over the same 13 changed Dart files — **No issues found**.
- `git diff --check` — clean for the whole working tree and for the intended change set.

Flutter emitted existing dependency-update and BLE plugin Swift Package Manager notices. Theme V2 shell tests also logged expected mocked localhost 400 responses; all tests completed successfully.

## Backend and safety

- No backend files changed. The prior isolated Docker device contract result remains **12/12 passed** and is unchanged by this mobile-only review fix.
- No ADB, physical card/ring, recording deletion, native destructive action, or real account unbind was performed.
- Physical-device acceptance caveats from the original implementation remain unchanged.

## Commit scope

The intended commit contains only:

- `.superpowers/sdd/final-review-fix-report-device-entry.md`
- `mobile/lib/device/card_unbind_sync.dart`
- `mobile/lib/device/device_controller.dart`
- `mobile/lib/ring/ring_reconnect.dart`
- `mobile/lib/theme_v2/device/theme_v2_card_device_detail_page.dart`
- `mobile/lib/theme_v2/device/theme_v2_device_route.dart`
- `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- `mobile/test/device/card_unbind_sync_test.dart`
- `mobile/test/device_controller_test.dart`
- `mobile/test/device_silent_reconnect_test.dart`
- `mobile/test/ring/ring_device_service_test.dart`
- `mobile/test/ring/ring_reconnect_test.dart`
- `mobile/test/theme_v2/device/theme_v2_device_detail_page_test.dart`
- `mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart`

The pre-existing modified `spec/design/redesignureka.pen` and unrelated untracked design specification/plan documents are preserved and excluded from staging.

## Concerns

No functional blocker was found in the review-fix scope. The branch remains available for the controller's whole-branch merge/push workflow; this task does not merge, push, or clean up the workspace.

---

## Second Final Re-review Fix Addendum

### Findings addressed

1. **Stable card compensation warning ordering**
   - The pending card-unbind server-sync warning now has dedicated controller state instead of relying only on the ordinary `error` slot.
   - A successful disconnected `refreshBoundDevice()` may clear a transient refresh error, but it cannot clear the pending compensation warning.
   - A genuine new device-entry, scan, connect, unbind, or logout operation clears the warning so it is not immortal.
   - The regression now uses the real ordering: background sync fails first, the warning is asserted, then a disconnected refresh runs and the same warning remains while the controller stays null/idle.

2. **In-flight ring connect invalidation**
   - Ring reconnect now tracks an active connect attempt and prevents a second scan/retry round while that attempt is unresolved.
   - Each connect captures the reconnect operation revision. If `forget`, `pause`, dispose, or a newer reconnect operation invalidates a connect before it completes, a stale successful connection is actively disconnected.
   - Stale cleanup leaves `_connected` false and resumes reconnect work only if the current, non-paused operation still has a saved MAC.
   - The gateway seam now includes `disconnect`, backed by the existing Chiplet Ring SDK disconnect call.
   - Normal reconnect success remains connected without cleanup disconnect or an immediate duplicate scan.

### RED evidence

- Command: `flutter test test/device_controller_test.dart test/ring/ring_reconnect_test.dart`
- Stable warning regression failed with expected `设备已解绑，服务端同步待重试` but actual `null` after the later disconnected refresh.
- Deferred connect → `forget` regression failed with expected one cleanup disconnect but actual zero.
- Normal reconnect regression failed with expected one scan start but actual two, proving the in-flight connect immediately restarted scanning.
- Result before production changes: **14 passed, 3 failed**.

### GREEN evidence

- Focused controller/reconnect rerun: `flutter test test/device_controller_test.dart test/ring/ring_reconnect_test.dart` — **17 tests passed**.
- Requested covering command: `flutter test test/device_controller_test.dart test/ring/ring_reconnect_test.dart test/ring/ring_device_service_test.dart test/theme_v2/device/theme_v2_device_detail_page_test.dart` — **40 tests passed**.
- Broader focused device-entry rerun (required because both edited controllers are shared): `flutter test test/device_controller_test.dart test/device/card_unbind_sync_test.dart test/device_silent_reconnect_test.dart test/ring/ring_device_service_test.dart test/ring/ring_reconnect_test.dart test/theme_v2/shell test/theme_v2/device` — **85 tests passed**.
- Focused analysis: `flutter analyze lib/device/device_controller.dart lib/ring/ring_reconnect.dart test/device_controller_test.dart test/ring/ring_reconnect_test.dart` — **No issues found**.
- `dart format` covered both production files and both changed test files.
- `git diff --check` passed for both the complete working tree and the five-file fix scope.
- No backend files or contracts changed; the prior isolated Docker device result remains **12/12 passed**.
- No physical-device, ADB, recording deletion, or real unbind action was performed.

### Second-fix commit scope

- `.superpowers/sdd/final-review-fix-report-device-entry.md`
- `mobile/lib/device/device_controller.dart`
- `mobile/lib/ring/ring_reconnect.dart`
- `mobile/test/device_controller_test.dart`
- `mobile/test/ring/ring_reconnect_test.dart`

The modified Pen file and unrelated untracked design plans/specifications remain excluded.
