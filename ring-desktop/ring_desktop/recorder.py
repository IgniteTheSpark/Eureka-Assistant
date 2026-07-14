import time
from typing import Callable

# 录音状态机：
#  - 第一次双击 start()；第二次双击 stop()（立即收尾）——这是主停法。
#  - 断流兜底：音频帧停了超过 gap 秒也收尾（万一第二次双击的手势事件丢了）。
#  - 冷却：收尾后 cooldown 秒内忽略 start()，避免"自动收尾后紧接着的双击又开一段新录音"。


class Recorder:
    def __init__(self, on_capture: Callable[[bytes], None],
                 gap: float = 1.5, max_dur: float = 30.0, cooldown: float = 1.0,
                 now: Callable[[], float] = time.time):
        self._on_capture = on_capture
        self.gap = gap
        self.max_dur = max_dur
        self.cooldown = cooldown
        self._now = now
        self.recording = False
        self.buf = bytearray()
        self.t0 = 0.0
        self.last = 0.0
        self._last_stop = -1e9

    def start(self) -> None:
        if self._now() - self._last_stop < self.cooldown:
            return  # 刚停过，忽略，避免双击停录被当成新录音
        self.recording = True
        self.buf = bytearray()
        self.t0 = self.last = self._now()

    def stop(self) -> None:
        """第二次双击=立即停。"""
        if self.recording:
            self._finalize()

    def feed(self, payload: bytes) -> None:
        if not self.recording:
            return
        self.buf += payload
        self.last = self._now()

    def tick(self) -> None:
        """周期调用：断流或超时兜底收尾。"""
        if not self.recording:
            return
        now = self._now()
        if self.buf and now - self.last > self.gap:
            self._finalize()
        elif now - self.t0 > self.max_dur:
            self._finalize()

    def _finalize(self) -> None:
        self.recording = False
        self._last_stop = self._now()
        data = bytes(self.buf)
        self.buf = bytearray()
        if data:
            self._on_capture(data)
