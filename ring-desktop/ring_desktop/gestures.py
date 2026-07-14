from typing import Optional

GESTURE_NAMES = {
    0: "longPress", 1: "single", 2: "double", 3: "triple",
    4: "up", 5: "down", 6: "left", 7: "right",
}

_GESTURE_PREFIX = bytes([0x00, 0x09, 0x61, 0x00])  # 手势帧固定头


def parse_gesture(data: bytes) -> Optional[int]:
    """戒指 notify 报文 -> 手势码 0..7；非手势(心跳/音频/未知)返回 None。

    手势帧：5 字节，前缀 00 09 61 00，末字节为手势码。
    心跳 00 2a 12 00 29 / 音频(len=110, 00 09 71 ...) 都不匹配。
    """
    if len(data) == 5 and data[:4] == _GESTURE_PREFIX:
        code = data[4]
        if code in GESTURE_NAMES:
            return code
    return None
