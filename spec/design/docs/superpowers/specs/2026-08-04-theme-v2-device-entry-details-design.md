# Theme V2 Device Entry and Details Design

> Date: 2026-08-04
> Status: Design draft for review, implementation not started
> Scope: Theme V2 global device entry, card/ring detail surfaces, device information, and unbinding semantics

## 1. Outcome

Theme V2 reuses the mature card and ring connection stacks while replacing the legacy device presentation with one consistent Theme V2 experience.

The global top navigation behaves as follows:

```text
No connected device
→ show the existing disconnected device entry
→ tap opens pairing

One connected device
→ show that device's icon only
→ tap opens that device's detail directly

Card and ring both connected
→ show a compact dual-device icon state
→ tap opens a small anchored chooser
→ choose card or ring to open its detail
```

The change does not redesign the hardware architecture, replace either SDK, or merge the card and ring connection controllers.

## 2. Source-of-Truth Boundaries

The UI uses typed device state rather than parsing display labels.

| Device | Connection source | Identity source | Information source | Unbind mechanism |
|---|---|---|---|---|
| Recording card | `DeviceController` / card BLE SDK | Bound `DeviceInfo` and server binding | Card BLE SDK and bound-device data | Device SDK unbind, native bind-cache clear, server unbind sync |
| Ring | `RingConnection` | Saved `ring_mac` | Ring SDK battery/version calls | Stop reconnect, disconnect BLE, remove saved MAC |

The shared Theme V2 shell may aggregate these states for presentation, but device operations remain delegated to the existing device-specific controllers.

## 3. Global Top Navigation

### 3.1 Visual states

Connected states do not show text such as `戒指已连接`, `录音卡已连接`, or `双设备已连接`. They use icons only so the device entry remains compact.

Required states:

- Disconnected: existing disconnected entry and pairing behavior.
- Card only: canonical recording-card icon.
- Ring only: canonical ring icon.
- Card and ring: compact combined state that clearly indicates two available devices.

The hit target remains at least `44 × 44` even when the visible icon is smaller.

### 3.2 Navigation behavior

- Disconnected opens `DevicePairingPage`.
- Card only opens the Theme V2 card detail.
- Ring only opens the Theme V2 ring detail.
- Dual connected opens an anchored popup below the device button.

The dual-device popup contains two rows:

1. Recording card icon, name, and connected state.
2. Ring icon, name, and connected state.

It is a lightweight chooser, not a device-management page. Selecting a row closes the popup and opens that detail.

## 4. Unified Detail Surface

Card and ring details share the same Theme V2 layout but retain device-specific fields and operations.

```text
Contextual app bar
→ product image area
→ device name and connected state
→ basic information section
→ destructive "解除绑定" action
```

The detail surface contains no settings, recording management, gesture configuration, debug controls, or firmware-update actions.

### 4.1 Product image area

The page reserves a stable product-image area for each device. Until real product images are supplied:

- Use a restrained device-specific placeholder illustration.
- Keep asset naming and layout stable so the placeholder can be replaced without changing page structure.
- Do not present the placeholder as a photorealistic product image.

### 4.2 Recording card fields

The card detail shows only information reliably available through the existing controller and SDK:

- Device name or nickname.
- Connection state.
- Serial number.
- Battery percentage.
- Used and total storage.

Firmware and model information are available from the SDK but are not added in this scope because the requested surface is limited to basic information.

### 4.3 Ring fields

The ring detail shows:

- Device name (`UReka 戒指` unless a future naming source is added).
- Connection state.
- Battery percentage.
- Saved MAC address.
- Firmware version.
- Hardware version when returned by the SDK.

The current ring SDK does not expose a serial number, so the UI must not invent or relabel the MAC as an SN.

## 5. Unbinding Semantics

`解除绑定` means removing the remembered relationship and returning the device to a pairable state. It must never be implemented as ordinary Bluetooth disconnection.

Both detail pages require a destructive confirmation before starting. While unbinding is in progress, the action is disabled to prevent duplicate operations.

### 5.1 Recording card

The card confirmation preserves the mature choice:

- Only unbind and keep recordings on the device.
- Unbind and delete recordings on the device.

The operation order remains:

```text
Stop any in-flight silent reconnect
→ send card SDK unbind command with deleteAudio choice
→ clear native binding cache
→ immediately clear local connected state
→ synchronize /api/cards/{bindingId}/unbind
→ return to the pairing state
```

The server `delete_data` value records the user's selection, while actual device recording deletion is controlled by the SDK's `deleteAudio` option.

#### Partial-success rule

If device-side unbinding succeeds but server synchronization fails:

- The card remains locally unbound and the detail closes.
- The UI must not restore or continue showing a connected card.
- Show a clear non-blocking message that server synchronization failed and needs retry.
- Prevent silent reconnect from reviving the stale binding in the same app session.
- Keep enough binding identity to retry only the server synchronization without sending the hardware unbind command again.

This is an implementation reliability fix around the existing architecture, not a new device subsystem.

### 5.2 Ring

The current ring SDK has no unbind API. The proven legacy sequence is mandatory:

```text
RingReconnect.forget()
→ stop scan/retry activity and clear in-memory MAC
→ disconnect the ring BLE connection
→ remove ring_mac from SharedPreferences
→ clear the Theme V2 connected state
→ return to pairing
```

If the SDK disconnect call fails, local unbinding still completes: reconnect
activity remains stopped, `ring_mac` is removed, and connected presentation is
cleared. The UI then reports that local binding was removed but Bluetooth
disconnect may not have completed; the error must not be swallowed silently.

Removing only `ring_mac` or calling only `disconnect()` is incorrect because the reconnect singleton can reconnect the ring from its in-memory MAC.

The ring has no server-side binding endpoint in the current architecture.

## 6. State and Error Handling

- Information loading is independent per field; one unavailable SDK value displays `--` and does not fail the whole page.
- A disconnected device detail may briefly update to disconnected state while an operation completes, then return to the previous screen.
- Unbind confirmation is not dismissed as success until the device-specific local unbind step succeeds.
- A complete local unbind always removes the top-nav connected state immediately.
- Ordinary logout remains a disconnect-only operation and must never trigger unbind.
- Pairing and unbinding pause conflicting scan/reconnect work before touching the BLE stack.

## 7. Platform Boundary

The checked-in `chiplet_ring` package currently contains Android native implementation only. Ring detail and unbind acceptance testing therefore targets the connected Android device. This change does not claim or add iOS ring support.

The recording-card plugin supports the existing Android and iOS bridges; implementation keeps both paths intact.

## 8. Test and Acceptance Coverage

### 8.1 Automated behavior

1. Disconnected device entry opens pairing.
2. Card-only state opens card detail directly.
3. Ring-only state opens ring detail directly.
4. Dual-device state opens the chooser and routes each row correctly.
5. Connected top-nav states render no status text.
6. Card detail renders basic information and both unbind choices.
7. Successful card unbind clears local state and synchronizes the server.
8. Device-side card unbind plus server-sync failure still clears the connected UI and exposes retryable synchronization state.
9. Card logout disconnects without unbinding.
10. Ring detail renders battery, MAC, firmware, and hardware values without an invented SN.
11. Ring unbind calls `forget` before disconnect and persisted-MAC removal.
12. Ring unbind cannot be undone by the auto-reconnect loop.
13. Missing battery, storage, or version values render as unavailable without crashing.
14. A ring SDK disconnect failure still clears local binding and produces a visible warning.

### 8.2 Android device acceptance

1. Connect only the card, open detail from the top navigation, and verify live information.
2. Unbind the card while keeping recordings, then confirm it appears in pairing and does not silently reconnect.
3. Rebind and verify the delete-recordings confirmation path without executing destructive deletion unless explicitly approved for the test device.
4. Connect only the ring, verify its information, unbind it, and confirm it advertises for pairing again.
5. Connect both devices, verify the compact chooser and both detail destinations.
6. Force-close and relaunch after each unbind to confirm neither device returns as connected from stale local state.

## 9. Non-goals

- Replacing the card or ring SDK.
- Combining both hardware stacks into one controller.
- Changing recording capture, ASR, or hardware-trigger pipelines.
- Adding device settings or firmware-update controls.
- Adding server-side ring binding.
- Creating iOS ring support.
- Final product photography; supplied images will replace placeholders later.
