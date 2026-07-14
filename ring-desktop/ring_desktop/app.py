import asyncio
import logging
import os
import subprocess
import sys
import threading
from dataclasses import dataclass
from typing import Callable, Optional

import rumps
from AppKit import NSApplicationActivateIgnoringOtherApps, NSRunningApplication
from pynput import keyboard

from . import audio, asr
from .ble import RingBLE
from .gestures import GESTURE_NAMES
from .config import load_config, resolve_action, resolve_vibration
from .control_api import VibrationControlServer
from .demo_session import CaptureContext, DemoMode, DemoSessionController
from .frontmost import frontmost_bundle_id
from .actions import dispatch, type_text
from .recorder import Recorder
from .vibration import VibrationType

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("ring_desktop.app")

CONFIG_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "config.json")
CONFIG_HOTKEY = "<ctrl>+<alt>+r"
VIBE_BUNDLES = frozenset({"com.openai.codex", "com.alibaba.DingTalkMac"})


@dataclass(frozen=True)
class VoiceCaptureContext:
    demo: CaptureContext
    source_bundle: Optional[str]


def status_icon(status: str, recording: bool) -> str:
    if recording:
        return "🎙"
    return "🟢" if status == "connected" else "⚪️"


def resolve_demo_action(
    mode: str,
    bundle: Optional[str],
    gesture: str,
    config: dict,
):
    if mode == DemoMode.IDLE.value:
        return None
    if mode == DemoMode.FLASH.value:
        return {"type": "voice"} if gesture == "double" else None
    if mode == DemoMode.VIBE.value:
        if bundle not in VIBE_BUNDLES:
            return None
        return resolve_action(config, bundle, gesture)
    return resolve_action(config, bundle, gesture)


def _action_label(action: object) -> Optional[str]:
    if not isinstance(action, dict):
        return None
    action_type = action.get("type")
    value = action.get("value")
    if action_type == "voice":
        return "Voice"
    if action_type == "scroll" and isinstance(value, str):
        return f"Scroll {value}"
    if action_type == "key" and isinstance(value, str):
        return value.replace("+", " + ").title()
    return str(value) if value is not None else None


def serialize_mapping(config: dict, bundle: Optional[str]) -> dict:
    merged = dict(config.get("default", {}))
    merged.update(config.get(bundle or "", {}))
    mapping = {}
    for gesture, action in merged.items():
        if gesture == "vibration":
            continue
        label = _action_label(action)
        if label is not None:
            mapping[gesture] = label
    return mapping


def _capture_event_data(context: CaptureContext) -> dict:
    return {
        "sessionId": context.session_id,
        "generation": context.generation,
        "mode": context.mode.value,
    }


class RingApp(rumps.App):
    def __init__(self):
        super().__init__("Ring", title="⚪️", quit_button=None)
        self.status = "starting"
        self.last = "-"
        self._state_lock = threading.RLock()
        self._frontmost = None          # 主线程缓存的前台 app（BLE 线程读它，别自己调 AppKit）
        self._mapping = {}
        self._demo = DemoSessionController()
        self._capture_context = None
        self._finalizing_recording = False
        self._pending_capture = None
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
            on_tick=self._on_recorder_tick,
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
                demo_controller=self._demo,
                demo_events=self._demo.events,
                get_demo_state=self._demo_state_snapshot,
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
        self._demo.events.publish(
            "connection.changed", self._ble.connection_state()
        )

    def _on_gesture(self, code: int):
        # 本回调在 BLE 后台线程执行：绝不在这里碰 AppKit（前台 app 用主线程缓存的 self._frontmost）。
        name = GESTURE_NAMES.get(code, str(code))
        with self._state_lock:
            bundle = self._frontmost
        context = self._demo.capture_context()
        action = resolve_demo_action(
            context.mode.value,
            bundle,
            name,
            load_config(CONFIG_PATH),
        )
        log.info("gesture=%s app=%s action=%s", name, bundle, action)
        if action and action.get("type") == "voice":
            if self._rec.recording:         # 第二次双击 = 立即停（断流仍作兜底）
                def stop_recording():
                    self._finalize_recording(self._rec.stop)
                    self.last = f"{name}->🎙停"

                if self._demo.run_if_current(context, stop_recording):
                    log.info("voice recording stopped (double-tap)")
                else:
                    self.last = f"{name}->-"
            else:
                def start_recording():
                    self._rec.start()
                    self.last = (
                        f"{name}->🎙录音"
                        if self._rec.recording
                        else f"{name}->(冷却忽略)"
                    )
                    if self._rec.recording:
                        self._capture_context = VoiceCaptureContext(context, bundle)
                        self._demo.events.publish(
                            "recording.started", _capture_event_data(context)
                        )

                if self._run_if_capture_current(context, bundle, start_recording):
                    if self._rec.recording:
                        log.info("voice recording started")
                else:
                    self.last = f"{name}->-"
        elif action:
            def dispatch_action():
                self.last = f"{name}->{action.get('value')}"
                try:
                    dispatch(action)
                except Exception as e:
                    log.warning("dispatch failed: %s", e)

            if not self._run_if_capture_current(context, bundle, dispatch_action):
                self.last = f"{name}->-"
        else:
            self.last = f"{name}->-"

    def _on_recorder_tick(self):
        self._finalize_recording(self._rec.tick)

    def _finalize_recording(self, finalize):
        was_recording = self._rec.recording
        self._finalizing_recording = True
        try:
            finalize()
        finally:
            self._finalizing_recording = False
        if was_recording and not self._rec.recording:
            context = self._capture_context
            if context is not None:
                self._demo.events.publish(
                    "recording.stopped", _capture_event_data(context.demo)
                )
        pending_capture = getattr(self, "_pending_capture", None)
        self._pending_capture = None
        if pending_capture is not None:
            self._start_transcription(*pending_capture)

    def _on_capture(self, adpcm: bytes):
        log.info("captured %d adpcm bytes -> decode+ASR", len(adpcm))
        context = self._capture_context
        if context is None:
            log.warning("discarding capture without recording context")
            return
        if getattr(self, "_finalizing_recording", False):
            self._pending_capture = (adpcm, context)
            return
        self._start_transcription(adpcm, context)

    def _start_transcription(self, adpcm: bytes, context: VoiceCaptureContext):
        self._demo.events.publish("asr.started", _capture_event_data(context.demo))
        threading.Thread(
            target=self._transcribe_inject,
            args=(adpcm, context),
            daemon=True,
        ).start()

    def _run_if_capture_current(
        self,
        context: CaptureContext,
        source_bundle: Optional[str],
        callback: Callable[[], None],
    ) -> bool:
        performed = False

        def authorize_bundle_and_run():
            nonlocal performed
            if context.mode is DemoMode.VIBE:
                with self._state_lock:
                    if (
                        self._frontmost not in VIBE_BUNDLES
                        or self._frontmost != source_bundle
                    ):
                        return
                    callback()
                    performed = True
                return
            callback()
            performed = True

        authorized = self._demo.run_if_current(context, authorize_bundle_and_run)
        return authorized and performed

    def _transcribe_inject(self, adpcm: bytes, context: VoiceCaptureContext):
        try:
            wav = audio.write_wav_temp(audio.decode_adpcm(adpcm))
            text = asr.transcribe(wav)
            log.info("voice text: %s", text)
            if not text:
                return

            def deliver_text():
                self.last = f"🎙{text[:14]}"
                if context.demo.mode is DemoMode.FLASH:
                    self._demo.events.publish(
                        "transcript.ready",
                        {**_capture_event_data(context.demo), "text": text},
                    )
                elif context.demo.mode in {DemoMode.VIBE, DemoMode.STANDALONE}:
                    type_text(text)

            if not self._run_if_capture_current(
                context.demo,
                context.source_bundle,
                deliver_text,
            ):
                log.info(
                    "discarding stale or app-switched transcript generation=%s",
                    context.demo.generation,
                )
        except Exception as e:
            log.warning("voice transcribe/inject failed: %r", e)
            self._run_if_capture_current(
                context.demo,
                context.source_bundle,
                lambda: setattr(self, "last", "voice->失败"),
            )

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
            self._demo.tick()
            if self._open_config_requested.is_set():
                self._open_config_requested.clear()
                self.open_config(None)
            bundle = frontmost_bundle_id()   # AppKit 调用留在主线程
            with self._state_lock:
                bundle_changed = bundle != self._frontmost
            if bundle_changed:
                config = load_config(CONFIG_PATH)
                mapping = serialize_mapping(config, bundle)
                with self._state_lock:
                    self._frontmost = bundle
                    self._mapping = mapping
                self._demo.events.publish(
                    "active_app.changed", {"activeApp": bundle}
                )
                self._demo.events.publish(
                    "mapping.changed",
                    {"mapping": mapping},
                )
            self.title = status_icon(self.status, self._rec.recording)
            self.menu["打开配置…"].title = f"打开配置…  ({self.status}·{self.last})"
        except Exception as e:
            log.warning("refresh error: %s", e)

    def _demo_state_snapshot(self):
        with self._state_lock:
            return {
                "activeApp": self._frontmost,
                "mapping": dict(self._mapping),
            }

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
