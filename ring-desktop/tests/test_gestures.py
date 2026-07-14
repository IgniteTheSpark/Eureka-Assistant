from ring_desktop.gestures import parse_gesture, GESTURE_NAMES


def test_single_click():
    assert parse_gesture(bytes.fromhex("0009610001")) == 1


def test_double_click():
    assert parse_gesture(bytes.fromhex("0009610002")) == 2


def test_right_swipe():
    assert parse_gesture(bytes.fromhex("0009610007")) == 7


def test_long_press():
    assert parse_gesture(bytes.fromhex("0009610000")) == 0


def test_heartbeat_is_not_gesture():
    # 00 2a 12 00 29 —— 每 30s 的心跳
    assert parse_gesture(bytes.fromhex("002a120029")) is None


def test_audio_frame_is_not_gesture():
    # len=110 的音频帧 00 09 71 ...
    assert parse_gesture(bytes.fromhex("000971086400" + "00" * 104)) is None


def test_unknown_code_is_none():
    assert parse_gesture(bytes.fromhex("0009610099")) is None


def test_names_cover_0_to_7():
    assert GESTURE_NAMES[0] == "longPress" and GESTURE_NAMES[7] == "right"
