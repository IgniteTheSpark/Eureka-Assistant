import asyncio

import pytest

from ring_desktop import ble as ble_module
from ring_desktop.ble import RingBLE, WRITE_CHAR, device_priority


class FakeClient:
    def __init__(self, connected=True):
        self.is_connected = connected
        self.writes = []

    async def write_gatt_char(self, characteristic, data, response):
        self.writes.append((characteristic, data, response))


def make_ble():
    return RingBLE(on_gesture=lambda _code: None)


def test_vibrate_writes_official_frame_with_response():
    ble = make_ble()
    client = FakeClient()
    ble._client = client

    asyncio.run(ble.vibrate("continuous"))

    assert client.writes == [
        (WRITE_CHAR, bytes.fromhex("00 00 83 04 02 00"), True)
    ]


def test_vibrate_rejects_disconnected_ring():
    ble = make_ble()
    ble._client = FakeClient(connected=False)

    with pytest.raises(RuntimeError, match="Ring is not connected"):
        asyncio.run(ble.vibrate("strong"))


def test_device_priority_prefers_bravechip_names_before_rssi():
    assert device_priority("BCL60392D5", -70) > device_priority("iPhone", -30)
    assert device_priority("Chiplet Ring", -80) > device_priority("Keyboard", -20)


def test_compatible_devices_filters_and_sorts_ring_names():
    found = [
        {"name": "Keyboard", "address": "keyboard", "rssi": -20},
        {"name": "BCL-weak", "address": "weak", "rssi": -80},
        {"name": "Chiplet Ring", "address": "strong", "rssi": -40},
    ]

    assert ble_module.compatible_devices(found) == [
        {"name": "Chiplet Ring", "address": "strong", "rssi": -40},
        {"name": "BCL-weak", "address": "weak", "rssi": -80},
    ]


def test_selecting_device_updates_manual_connection_state():
    ble = make_ble()

    ble.select_device("ring-id", "BCL60392D5")

    assert ble.connection_state() == {
        "status": "connecting",
        "connected": False,
        "device": {"name": "BCL60392D5", "address": "ring-id"},
        "devices": [],
        "lastError": None,
    }


def test_clearing_device_stops_reusing_old_address():
    ble = make_ble()
    ble.select_device("old-id", "BCL60392D5")

    ble.clear_device()

    assert ble.address is None
    assert ble.connection_state()["status"] == "disconnected"


def test_unknown_notification_is_logged_for_protocol_diagnosis(caplog):
    ble = make_ble()

    with caplog.at_level("INFO", logger="ring_desktop.ble"):
        ble._notify(None, bytearray.fromhex("00 09 61 00 08"))

    assert "unhandled notify: 00 09 61 00 08" in caplog.text
