import asyncio
import logging
import threading
from typing import Callable, Optional

from bleak import BleakScanner, BleakClient

from .gestures import parse_gesture
from .vibration import VibrationType, build_immediate_frame

log = logging.getLogger("ring_desktop.ble")

KEY_CHAR = "bae80011-4f05-4503-8e65-3af1f7329d1f"  # 实测手势+音频 notify 特征
WRITE_CHAR = "bae80010-4f05-4503-8e65-3af1f7329d1f"
_AUDIO_PREFIX = bytes([0x00, 0x09, 0x71])           # 音频帧前缀
_AUDIO_HEADER = 10                                  # 音频帧前导字节数，其后为 ADPCM 负载


def device_priority(name: Optional[str], rssi: Optional[int]):
    normalized = (name or "").lower()
    bravechip_name = normalized.startswith(("bcl", "chiplet", "ring"))
    return int(bravechip_name), rssi if rssi is not None else -999


def compatible_devices(devices):
    """Return only likely BraveChip rings, strongest signal first."""
    rings = []
    for device in devices:
        name = (device.get("name") or "").lower()
        if name.startswith(("bcl", "chiplet", "ring")):
            rings.append(device)
    return sorted(rings, key=lambda item: item.get("rssi", -999), reverse=True)


class RingBLE:
    """连戒指、订阅通知：手势 -> on_gesture(code)，音频负载 -> on_audio(payload)。
    on_tick 在连接循环里被周期调用（给录音断流检测用）。掉线自动重连。"""

    def __init__(self, on_gesture: Callable[[int], None],
                 on_status: Optional[Callable[[str], None]] = None,
                 on_audio: Optional[Callable[[bytes], None]] = None,
                 on_tick: Optional[Callable[[], None]] = None,
                 address: Optional[str] = None):
        self.on_gesture = on_gesture
        self.on_status = on_status or (lambda s: None)
        self.on_audio = on_audio or (lambda b: None)
        self.on_tick = on_tick or (lambda: None)
        self.address = address
        self.device_name = None
        self._stop = False
        self._loop = None
        self._client = None
        self._target_event = None
        self._state_lock = threading.RLock()
        self._status = "connecting" if address else "disconnected"
        self._devices = []
        self._last_error = None

    def _set_status(self, status: str, error: Optional[str] = None):
        with self._state_lock:
            self._status = status
            self._last_error = error
        self.on_status(status)

    def connection_state(self) -> dict:
        with self._state_lock:
            device = None
            if self.address:
                device = {"name": self.device_name or "Unknown ring", "address": self.address}
            return {
                "status": self._status,
                "connected": self._status == "connected",
                "device": device,
                "devices": [dict(item) for item in self._devices],
                "lastError": self._last_error,
            }

    def _wake_connection_loop(self):
        loop = self._loop
        event = self._target_event
        if loop is not None and loop.is_running() and event is not None:
            loop.call_soon_threadsafe(event.set)

    def select_device(self, address: str, name: str) -> bool:
        if not address or not name:
            return False
        old_address = self.address
        with self._state_lock:
            self.address = address
            self.device_name = name
            self._status = "connecting"
            self._last_error = None
        client = self._client
        loop = self._loop
        if (
            old_address != address
            and client is not None
            and client.is_connected
            and loop is not None
            and loop.is_running()
        ):
            asyncio.run_coroutine_threadsafe(client.disconnect(), loop)
        self.on_status("connecting")
        self._wake_connection_loop()
        return True

    def clear_device(self) -> bool:
        with self._state_lock:
            self.address = None
            self.device_name = None
            self._status = "disconnected"
            self._last_error = None
        client = self._client
        loop = self._loop
        if client is not None and client.is_connected and loop is not None and loop.is_running():
            asyncio.run_coroutine_threadsafe(client.disconnect(), loop)
        self.on_status("disconnected")
        self._wake_connection_loop()
        return True

    async def scan(self):
        connected = self.is_connected
        if not connected:
            self._set_status("scanning")
        try:
            found = await BleakScanner.discover(timeout=8.0, return_adv=True)
            devices = []
            for dev, adv in found.values():
                devices.append({
                    "name": adv.local_name or dev.name or "Unknown",
                    "address": dev.address,
                    "rssi": adv.rssi,
                })
            devices = compatible_devices(devices)
            with self._state_lock:
                self._devices = devices
            if connected:
                self._set_status("connected")
            else:
                self._set_status("ready" if devices else "not found")
            return devices
        except Exception as error:
            self._set_status("error", str(error))
            return []

    def request_scan(self) -> bool:
        loop = self._loop
        if loop is None or not loop.is_running():
            return False
        asyncio.run_coroutine_threadsafe(self.scan(), loop)
        return True

    def request_connect(self, address: str, name: str) -> bool:
        return self.select_device(address, name)

    def request_disconnect(self) -> bool:
        return self.clear_device()

    def _notify(self, _sender, data: bytearray):
        b = bytes(data)
        code = parse_gesture(b)
        if code is not None:
            log.info("gesture %s", code)
            self.on_gesture(code)
            return
        if b[:3] == _AUDIO_PREFIX:
            self.on_audio(b[_AUDIO_HEADER:])
            return
        if b[:4] == bytes((0x00, 0x00, 0x83, 0x04)):
            log.info("vibration acknowledged: %s", b.hex(" "))
            return
        log.info("unhandled notify: %s", b.hex(" "))

    async def vibrate(self, vibration_type: VibrationType = VibrationType.CONTINUOUS):
        client = self._client
        if client is None or not client.is_connected:
            raise RuntimeError("Ring is not connected")
        frame = build_immediate_frame(vibration_type)
        await client.write_gatt_char(WRITE_CHAR, frame, response=True)
        log.info("vibration sent: type=%s frame=%s", vibration_type, frame.hex(" "))

    @property
    def is_connected(self) -> bool:
        client = self._client
        return client is not None and client.is_connected

    def request_vibration(self, vibration_type: VibrationType = VibrationType.CONTINUOUS) -> bool:
        """Thread-safe entry point for menu/API callers outside the BLE loop."""
        loop = self._loop
        if loop is None or not loop.is_running() or not self.is_connected:
            return False
        future = asyncio.run_coroutine_threadsafe(
            self.vibrate(vibration_type), loop
        )

        def log_result(done):
            try:
                done.result()
            except Exception as error:
                log.warning("vibration failed: %s", error)

        future.add_done_callback(log_result)
        return True

    async def run_once(self) -> None:
        self._loop = asyncio.get_running_loop()
        addr = self.address
        if not addr:
            return
        self._set_status("connecting")
        async with BleakClient(addr) as client:
            self._client = client
            try:
                characteristics = {
                    characteristic.uuid.lower()
                    for service in client.services
                    for characteristic in service.characteristics
                }
                if KEY_CHAR not in characteristics or WRITE_CHAR not in characteristics:
                    raise RuntimeError("Connected BLE device is not a BraveChip ring")
                self._set_status("connected")
                await client.start_notify(KEY_CHAR, self._notify)
                while client.is_connected and not self._stop:
                    self.on_tick()
                    await asyncio.sleep(0.2)
            finally:
                self._client = None
        if self.address == addr:
            self._set_status("disconnected")

    async def run(self) -> None:
        self._loop = asyncio.get_running_loop()
        self._target_event = asyncio.Event()
        while not self._stop:
            if not self.address:
                self._set_status("disconnected")
                self._target_event.clear()
                if not self.address:
                    await self._target_event.wait()
                continue
            attempted_address = self.address
            try:
                await self.run_once()
            except Exception as e:
                log.warning("ble error: %s", e)
                if self.address == attempted_address:
                    with self._state_lock:
                        self.address = None
                    self._set_status("error", str(e))
            if self._stop:
                break
            if self.address:
                await asyncio.sleep(2.0)

    def stop(self):
        self._stop = True
        self._wake_connection_loop()
