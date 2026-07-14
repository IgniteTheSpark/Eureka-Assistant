import asyncio
import logging
import os
import subprocess
import sys
import threading

import rumps
from AppKit import NSApplicationActivateIgnoringOtherApps, NSRunningApplication
from pynput import keyboard

from . import audio, asr
from .ble import RingBLE
from .gestures import GESTURE_NAMES
from .config import load_config, resolve_action, resolve_vibration
from .control_api import VibrationControlServer
from .frontmost import frontmost_bundle_id
from .actions import dispatch, type_text
from .recorder import Recorder
from .vibration import VibrationType

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("ring_desktop.app")

CONFIG_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "config.json")
CONFIG_HOTKEY = "<ctrl>+<alt>+r"


def status_icon(status: str, recording: bool) -> str:
    if recording:
        return "🎙"
    return "🟢" if status == "connected" else "⚪️"


class RingApp(rumps.App):
    def __init__(self):
        super().__init__("Ring", title="⚪️", quit_button=None)
        self.status = "starting"
        self.last = "-"
        self._frontmost = None          # 主线程缓存的前台 app（BLE 线程读它，别自己调 AppKit）
        self._config_process = None
        self._open_config_requested = threading.Event()
        vibration_menu = rumps.MenuItem("测试震动")
        vibration_menu.add(
            rumps.MenuItem(
                "强力震动",
                callback=lambda _: self._request_vibration(VibrationType.STRONG),
            )
        )
        vibration_menu.add(
            rumps.MenuItem(
                "持续震动",
                callback=lambda _: self._request_vibration(VibrationType.CONTINUOUS),
            )
        )
        vibration_menu.add(
            rumps.MenuItem(
                "渐变震动",
                callback=lambda _: self._request_vibration(VibrationType.GRADIENT),
            )
        )
        self.menu = ["打开配置…", vibration_menu, "退出"]
        self._rec = Recorder(on_capture=self._on_capture, gap=1.5)  # 1.5s 静默才收尾，避免说话停顿被截断
        self._ble = RingBLE(
            on_gesture=self._on_gesture,
            on_audio=self._rec.feed,
            on_tick=self._rec.tick,
            on_status=self._on_status,
        )
        threading.Thread(target=self._run_ble, daemon=True).start()
        self._control_server = None
        try:
            self._control_server = VibrationControlServer(
                self._request_vibration,
                request_event=self._request_vibration_event,
                get_connection=self._ble.connection_state,
                request_scan=self._ble.request_scan,
                request_connect=self._ble.request_connect,
                request_disconnect=self._ble.request_disconnect,
            ).start()
        except OSError as error:
            log.warning("local control API unavailable: %s", error)
        self._hotkeys = None
        try:
            self._hotkeys = keyboard.GlobalHotKeys({
                CONFIG_HOTKEY: self._open_config_requested.set,
            })
            self._hotkeys.start()
        except Exception as error:
            log.warning("global config hotkey unavailable: %s", error)
        rumps.Timer(self._refresh, 0.5).start()

    def _run_ble(self):
        asyncio.run(self._ble.run())

    def _on_status(self, s: str):
        self.status = s

    def _on_gesture(self, code: int):
        # 本回调在 BLE 后台线程执行：绝不在这里碰 AppKit（前台 app 用主线程缓存的 self._frontmost）。
        name = GESTURE_NAMES.get(code, str(code))
        bundle = self._frontmost
        action = resolve_action(load_config(CONFIG_PATH), bundle, name)
        log.info("gesture=%s app=%s action=%s", name, bundle, action)
        if action and action.get("type") == "voice":
            if self._rec.recording:         # 第二次双击 = 立即停（断流仍作兜底）
                self._rec.stop()
                self.last = f"{name}->🎙停"
                log.info("voice recording stopped (double-tap)")
            else:
                self._rec.start()
                self.last = f"{name}->🎙录音" if self._rec.recording else f"{name}->(冷却忽略)"
                if self._rec.recording:
                    log.info("voice recording started")
        elif action:
            self.last = f"{name}->{action.get('value')}"
            try:
                dispatch(action)
            except Exception as e:
                log.warning("dispatch failed: %s", e)
        else:
            self.last = f"{name}->-"

    def _on_capture(self, adpcm: bytes):
        log.info("captured %d adpcm bytes -> decode+ASR", len(adpcm))
        threading.Thread(target=self._transcribe_inject, args=(adpcm,), daemon=True).start()

    def _transcribe_inject(self, adpcm: bytes):
        try:
            wav = audio.write_wav_temp(audio.decode_adpcm(adpcm))
            text = asr.transcribe(wav)
            log.info("voice text: %s", text)
            self.last = f"🎙{text[:14]}"
            if text:
                type_text(text)
        except Exception as e:
            log.warning("voice transcribe/inject failed: %r", e)
            self.last = "voice->失败"

    def _request_vibration(self, vibration_type: VibrationType) -> bool:
        accepted = self._ble.request_vibration(vibration_type)
        if accepted:
            self.last = f"震动->{vibration_type.value}"
        else:
            self.last = "震动->未连接"
        return accepted

    def _request_vibration_event(self, bundle_id: str, event_name: str):
        vibration_type = resolve_vibration(
            load_config(CONFIG_PATH), bundle_id, event_name
        )
        if vibration_type is None:
            self.last = f"{event_name}->关闭"
            log.info("vibration event ignored: app=%s event=%s", bundle_id, event_name)
            return None
        log.info(
            "vibration event: app=%s event=%s type=%s",
            bundle_id,
            event_name,
            vibration_type.value,
        )
        return self._request_vibration(vibration_type)

    def _refresh(self, _):
        try:
            if self._open_config_requested.is_set():
                self._open_config_requested.clear()
                self.open_config(None)
            self._frontmost = frontmost_bundle_id()   # AppKit 调用留在主线程
            self.title = status_icon(self.status, self._rec.recording)
            self.menu["打开配置…"].title = f"打开配置…  ({self.status}·{self.last})"
        except Exception as e:
            log.warning("refresh error: %s", e)

    @rumps.clicked("打开配置…")
    def open_config(self, _):
        if self._config_process is not None and self._config_process.poll() is None:
            running = NSRunningApplication.runningApplicationWithProcessIdentifier_(
                self._config_process.pid
            )
            if running is not None:
                running.activateWithOptions_(NSApplicationActivateIgnoringOtherApps)
            return
        self._config_process = subprocess.Popen(
            [sys.executable, "-m", "ring_desktop.config_window"]
        )

    @rumps.clicked("退出")
    def quit_app(self, _):
        if self._hotkeys is not None:
            self._hotkeys.stop()
        if self._control_server is not None:
            self._control_server.stop()
        self._ble.stop()
        rumps.quit_application()


def main():
    RingApp().run()


if __name__ == "__main__":
    main()
