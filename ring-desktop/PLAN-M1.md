# Ring-desktop M1 Implementation Plan

> Historical implementation plan. The project now lives at
> `Eureka-Assistant/ring-desktop/`; absolute paths below have been updated for
> the monorepo layout, but completed task instructions are retained for context.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 一个常驻 Mac 的 demo：戒指经 BLE 直连，触控手势按「当前聚焦 app」路由成按键注入；菜单栏显示状态，配置窗按 app 配手势。

**Architecture:** 主进程 = `rumps` 菜单栏 + 后台线程跑 `bleak`（监听手势）+ 按 `NSWorkspace` 前台 bundle id 查 `config.json` → `pynput` 注入按键。配置窗 = 独立 `pywebview` 子进程（菜单栏"打开配置"拉起），读写同一个 `config.json`，避免双主线程冲突。

**Tech Stack:** Python 3.9+；bleak(BLE)、pyobjc/AppKit(前台 app)、pynput(注入)、rumps(菜单栏)、pywebview(配置窗)、pytest(测试)。

---

## 文件结构

```
Ring-desktop/
├── SPEC.md
├── PLAN-M1.md                 # 本文件
├── README.md                  # 运行说明（Task 0）
├── requirements.txt           # 依赖（Task 0）
├── config.example.json        # 默认配置样例（Task 0）
├── ring_desktop/
│   ├── __init__.py
│   ├── gestures.py            # 报文解析（Task 1，纯函数，TDD）
│   ├── config.py              # per-app 配置读写/查找（Task 2，TDD）
│   ├── actions.py             # keyspec 解析 + pynput 注入（Task 3，TDD）
│   ├── frontmost.py           # NSWorkspace 前台 app（Task 4）
│   ├── ble.py                 # bleak 连接/订阅/解析/重连（Task 5）
│   ├── app.py                 # 主程序：菜单栏 + 串联（Task 6）
│   └── config_window.py       # pywebview 配置窗子进程（Task 7）
└── tests/
    ├── test_gestures.py
    ├── test_config.py
    └── test_actions.py
```

**统一数据形状（全计划复用）：**
- 手势码：`0 longPress / 1 single / 2 double / 3 triple / 4 up / 5 down / 6 left / 7 right`
- 手势名：`GESTURE_NAMES[code] -> "single"` 等
- 配置：`{ "default": {<gestureName>: <action>}, "<bundleId>": {<gestureName>: <action>} }`
- 动作 action：`{"type": "key", "value": "ctrl+u"}`（M1 只实现 `key`；`text` 顺手带上；`media/voice/script` 留空待 M2/M3）

---

## Task 0: 项目脚手架

**Files:**
- Create: `ring_desktop/__init__.py`, `requirements.txt`, `config.example.json`, `README.md`, `tests/__init__.py`

- [ ] **Step 1: 建目录与空包**

```bash
cd /path/to/Eureka-Assistant/ring-desktop
mkdir -p ring_desktop tests
touch ring_desktop/__init__.py tests/__init__.py
```

- [ ] **Step 2: 写 `requirements.txt`**

```
bleak>=0.21
pyobjc-framework-Cocoa>=10
pynput>=1.7
rumps>=0.4
pywebview>=5
pytest>=8
```

- [ ] **Step 3: 写 `config.example.json`**

```json
{
  "default": {
    "triple":    { "type": "key", "value": "enter" },
    "longPress": { "type": "key", "value": "ctrl+u" }
  },
  "com.anthropic.claudefordesktop": {
    "triple":    { "type": "key", "value": "enter" },
    "longPress": { "type": "key", "value": "ctrl+u" },
    "left":      { "type": "key", "value": "esc" },
    "up":        { "type": "key", "value": "up" },
    "down":      { "type": "key", "value": "down" },
    "right":     { "type": "key", "value": "shift+tab" }
  },
  "com.alibaba.DingTalkMac": {
    "triple":    { "type": "key", "value": "enter" },
    "up":        { "type": "key", "value": "up" },
    "down":      { "type": "key", "value": "down" }
  }
}
```

- [ ] **Step 4: 写 `README.md`**

```markdown
# Ring-desktop
戒指 → Mac 输入设备（M1：手势→按键）。详见 SPEC.md / PLAN-M1.md。

## 安装
    python3 -m venv .venv && source .venv/bin/activate
    pip install -r requirements.txt
    cp config.example.json config.json

## 运行（在你自己的终端里跑——要蓝牙+辅助功能权限）
    python -m ring_desktop.app
首次：系统设置→隐私与安全性→蓝牙 & 辅助功能，给终端打勾。

## 测试
    pytest -q
```

- [ ] **Step 5: 建并激活 venv、装依赖**

Run:
```bash
cd /path/to/Eureka-Assistant/ring-desktop
python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt
cp config.example.json config.json
```
Expected: 依赖装好（bleak 用预编译轮子；若 pyobjc 报编译器错，先 `pip install --upgrade pip` 再重试）。

- [ ] **Step 6: Commit**

```bash
git init 2>/dev/null; git add -A && git commit -m "chore: scaffold ring-desktop M1"
```

---

## Task 1: `gestures.py` — 报文解析（TDD）

**Files:**
- Create: `ring_desktop/gestures.py`
- Test: `tests/test_gestures.py`

- [ ] **Step 1: 写失败测试**

```python
# tests/test_gestures.py
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
```

- [ ] **Step 2: 跑测试确认失败**

Run: `pytest tests/test_gestures.py -q`
Expected: FAIL（`ModuleNotFoundError: ring_desktop.gestures`）

- [ ] **Step 3: 写实现**

```python
# ring_desktop/gestures.py
from typing import Optional

GESTURE_NAMES = {
    0: "longPress", 1: "single", 2: "double", 3: "triple",
    4: "up", 5: "down", 6: "left", 7: "right",
}

_GESTURE_PREFIX = bytes([0x00, 0x09, 0x61, 0x00])  # 手势帧固定头

def parse_gesture(data: bytes) -> Optional[int]:
    """戒指 notify 报文 -> 手势码 0..7；非手势(心跳/音频/未知)返回 None。

    手势帧：5 字节，前缀 00 09 61 00，末字节为手势码。
    心跳   00 2a 12 00 29 / 音频(len=110, 00 09 71 ...) 都不匹配。
    """
    if len(data) == 5 and data[:4] == _GESTURE_PREFIX:
        code = data[4]
        if code in GESTURE_NAMES:
            return code
    return None
```

- [ ] **Step 4: 跑测试确认通过**

Run: `pytest tests/test_gestures.py -q`
Expected: PASS（8 passed）

- [ ] **Step 5: Commit**

```bash
git add ring_desktop/gestures.py tests/test_gestures.py && git commit -m "feat: parse ring gesture frames"
```

---

## Task 2: `config.py` — per-app 配置（TDD）

**Files:**
- Create: `ring_desktop/config.py`
- Test: `tests/test_config.py`

- [ ] **Step 1: 写失败测试**

```python
# tests/test_config.py
import json
from ring_desktop.config import load_config, save_config, resolve_action

def test_resolve_app_specific():
    cfg = {
        "default": {"triple": {"type": "key", "value": "enter"}},
        "com.x": {"triple": {"type": "key", "value": "cmd+enter"}},
    }
    assert resolve_action(cfg, "com.x", "triple")["value"] == "cmd+enter"

def test_resolve_falls_back_to_default():
    cfg = {
        "default": {"longPress": {"type": "key", "value": "ctrl+u"}},
        "com.x": {"triple": {"type": "key", "value": "enter"}},
    }
    assert resolve_action(cfg, "com.x", "longPress")["value"] == "ctrl+u"

def test_resolve_unknown_app_uses_default():
    cfg = {"default": {"single": {"type": "key", "value": "space"}}}
    assert resolve_action(cfg, "com.unknown", "single")["value"] == "space"

def test_resolve_missing_returns_none():
    assert resolve_action({}, "com.x", "single") is None

def test_save_load_roundtrip(tmp_path):
    p = tmp_path / "config.json"
    cfg = {"default": {"triple": {"type": "key", "value": "enter"}}}
    save_config(str(p), cfg)
    assert load_config(str(p)) == cfg

def test_load_missing_file_returns_empty(tmp_path):
    assert load_config(str(tmp_path / "nope.json")) == {"default": {}}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `pytest tests/test_config.py -q`
Expected: FAIL（`ModuleNotFoundError`）

- [ ] **Step 3: 写实现**

```python
# ring_desktop/config.py
import json
import os
from typing import Optional

def load_config(path: str) -> dict:
    """读配置；文件不存在则返回 {"default": {}}。"""
    if not os.path.exists(path):
        return {"default": {}}
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def save_config(path: str, cfg: dict) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)

def resolve_action(cfg: dict, bundle_id: Optional[str], gesture_name: str) -> Optional[dict]:
    """先查该 app 的档；该手势没配则回落到 default；都没有返回 None。"""
    app_profile = cfg.get(bundle_id or "", {})
    if gesture_name in app_profile:
        return app_profile[gesture_name]
    return cfg.get("default", {}).get(gesture_name)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `pytest tests/test_config.py -q`
Expected: PASS（6 passed）

- [ ] **Step 5: Commit**

```bash
git add ring_desktop/config.py tests/test_config.py && git commit -m "feat: per-app config load/save/resolve"
```

---

## Task 3: `actions.py` — keyspec 解析 + 注入（TDD 解析部分）

**Files:**
- Create: `ring_desktop/actions.py`
- Test: `tests/test_actions.py`

- [ ] **Step 1: 写失败测试（只测纯解析，不触发真实按键）**

```python
# tests/test_actions.py
from pynput.keyboard import Key
from ring_desktop.actions import parse_keyspec

def test_plain_special_key():
    assert parse_keyspec("enter") == ([], Key.enter)

def test_char_key():
    assert parse_keyspec("a") == ([], "a")

def test_ctrl_combo_char():
    assert parse_keyspec("ctrl+u") == ([Key.ctrl], "u")

def test_shift_plus_special():
    assert parse_keyspec("shift+tab") == ([Key.shift], Key.tab)

def test_cmd_combo():
    assert parse_keyspec("cmd+enter") == ([Key.cmd], Key.enter)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `pytest tests/test_actions.py -q`
Expected: FAIL（`ImportError: cannot import name 'parse_keyspec'`）

- [ ] **Step 3: 写实现**

```python
# ring_desktop/actions.py
import logging
from typing import List, Tuple, Union
from pynput.keyboard import Controller, Key

log = logging.getLogger("ring_desktop.actions")

_SPECIALS = {
    "enter": Key.enter, "esc": Key.esc, "escape": Key.esc, "tab": Key.tab,
    "space": Key.space, "backspace": Key.backspace, "delete": Key.delete,
    "up": Key.up, "down": Key.down, "left": Key.left, "right": Key.right,
}
_MODIFIERS = {"cmd": Key.cmd, "ctrl": Key.ctrl, "alt": Key.alt, "shift": Key.shift}

KeyType = Union[str, Key]

def parse_keyspec(spec: str) -> Tuple[List[Key], KeyType]:
    """'ctrl+u' -> ([Key.ctrl], 'u'); 'enter' -> ([], Key.enter)。"""
    parts = [p.strip().lower() for p in spec.split("+") if p.strip()]
    *mods, main = parts
    mod_keys = [_MODIFIERS[m] for m in mods]
    main_key: KeyType = _SPECIALS.get(main, main)  # 单字符保持为 str
    return mod_keys, main_key

_controller = Controller()

def _send_key(spec: str) -> None:
    mods, main = parse_keyspec(spec)
    for m in mods:
        _controller.press(m)
    try:
        _controller.press(main)
        _controller.release(main)
    finally:
        for m in reversed(mods):
            _controller.release(m)

def dispatch(action: dict) -> None:
    """执行一个动作。M1 支持 key / text；其余类型记日志跳过。"""
    if not action:
        return
    t = action.get("type")
    if t == "key":
        _send_key(action["value"])
    elif t == "text":
        _controller.type(action["value"])
    else:
        log.info("action type not implemented in M1: %s", t)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `pytest tests/test_actions.py -q`
Expected: PASS（5 passed）

- [ ] **Step 5: 手动验证注入（需辅助功能权限）**

Run（焦点放到"备忘录"后，回终端执行）:
```bash
python -c "import time; from ring_desktop.actions import dispatch; time.sleep(3); dispatch({'type':'text','value':'ring ok'}); dispatch({'type':'key','value':'enter'})"
```
Expected: 3 秒内把焦点切到备忘录；备忘录里出现 `ring ok` 并换行。首次会要"辅助功能"授权。

- [ ] **Step 6: Commit**

```bash
git add ring_desktop/actions.py tests/test_actions.py && git commit -m "feat: keyspec parse + pynput inject"
```

---

## Task 4: `frontmost.py` — 当前前台 app

**Files:**
- Create: `ring_desktop/frontmost.py`

- [ ] **Step 1: 写实现**

```python
# ring_desktop/frontmost.py
from typing import Optional, List, Dict
from AppKit import NSWorkspace

def frontmost_bundle_id() -> Optional[str]:
    """当前最前台 app 的 bundle id，如 'com.anthropic.claudefordesktop'。"""
    app = NSWorkspace.sharedWorkspace().frontmostApplication()
    return str(app.bundleIdentifier()) if app else None

def running_apps() -> List[Dict[str, str]]:
    """活跃(常规)运行中的 app 列表，供配置窗挑选。"""
    out = []
    for a in NSWorkspace.sharedWorkspace().runningApplications():
        if a.activationPolicy() == 0 and a.bundleIdentifier():  # 0 = regular
            out.append({"name": str(a.localizedName()), "bundle": str(a.bundleIdentifier())})
    # 去重 + 按名排序
    seen, uniq = set(), []
    for x in sorted(out, key=lambda d: d["name"].lower()):
        if x["bundle"] not in seen:
            seen.add(x["bundle"]); uniq.append(x)
    return uniq
```

- [ ] **Step 2: 手动验证**

Run（先把焦点切到 Claude，再迅速回终端按回车执行——或直接看终端自己的 bundle）:
```bash
python -c "from ring_desktop.frontmost import frontmost_bundle_id, running_apps; print(frontmost_bundle_id()); print(len(running_apps()), 'apps')"
```
Expected: 打印某个 bundle id（如终端自身），以及运行中的 app 数量 > 0。

- [ ] **Step 3: Commit**

```bash
git add ring_desktop/frontmost.py && git commit -m "feat: frontmost + running apps via NSWorkspace"
```

---

## Task 5: `ble.py` — 戒指 BLE 监听（改写自已验证的 spike）

**Files:**
- Create: `ring_desktop/ble.py`
- 参考: `/Users/admin/claude/ring-mac-spike/ring_spike.py`（已验证能连、能收手势）

- [ ] **Step 1: 写实现**

```python
# ring_desktop/ble.py
import asyncio
import logging
from typing import Callable, Optional
from bleak import BleakScanner, BleakClient
from .gestures import parse_gesture

log = logging.getLogger("ring_desktop.ble")

KEY_CHAR = "bae80011-4f05-4503-8e65-3af1f7329d1f"  # 实测手势/数据 notify 特征

class RingBLE:
    """连戒指、订阅手势通知，每来一个手势码回调 on_gesture(code)。掉线自动重连。"""

    def __init__(self, on_gesture: Callable[[int], None],
                 on_status: Optional[Callable[[str], None]] = None,
                 address: Optional[str] = None):
        self.on_gesture = on_gesture
        self.on_status = on_status or (lambda s: None)
        self.address = address          # 已知 CoreBluetooth UUID 时直连
        self._stop = False

    def _notify(self, _sender, data: bytearray):
        code = parse_gesture(bytes(data))
        if code is not None:
            log.info("gesture %s", code)
            self.on_gesture(code)

    async def _pick_address(self) -> Optional[str]:
        if self.address:
            return self.address
        self.on_status("scanning")
        found = await BleakScanner.discover(timeout=8.0, return_adv=True)
        # 选含手势特征所在服务的设备：先按 RSSI 取最强、名字非空者
        items = sorted(found.values(), key=lambda x: -(x[1].rssi or -999))
        for dev, adv in items:
            name = adv.local_name or dev.name or ""
            if name:  # 戒指广播带名字；最强信号优先（贴近 Mac）
                return dev.address
        return items[0][0].address if items else None

    async def run_once(self) -> None:
        addr = await self._pick_address()
        if not addr:
            self.on_status("not found")
            return
        self.on_status("connecting")
        async with BleakClient(addr) as client:
            self.address = addr
            self.on_status("connected")
            await client.start_notify(KEY_CHAR, self._notify)
            while client.is_connected and not self._stop:
                await asyncio.sleep(0.5)
        self.on_status("disconnected")

    async def run(self) -> None:
        """常驻：断了就重连，直到 stop()。"""
        while not self._stop:
            try:
                await self.run_once()
            except Exception as e:
                log.warning("ble error: %s", e)
            if self._stop:
                break
            await asyncio.sleep(2.0)

    def stop(self):
        self._stop = True
```

- [ ] **Step 2: 手动验证（戒指必须先从手机释放：`adb shell am force-stop com.eureka.mindapp`）**

Run（在你终端，戒指唤醒、贴近 Mac）:
```bash
python -c "import asyncio,logging; logging.basicConfig(level=logging.INFO); from ring_desktop.ble import RingBLE; r=RingBLE(on_gesture=lambda c: print('GOT',c), on_status=lambda s: print('status',s)); asyncio.run(r.run_once())"
```
Expected: 打印 `status scanning → connecting → connected`，做手势时打印 `GOT 1`/`GOT 3` 等。Ctrl+C 退出。

- [ ] **Step 3: Commit**

```bash
git add ring_desktop/ble.py && git commit -m "feat: ring BLE listener with reconnect"
```

---

## Task 6: `app.py` — 主程序（菜单栏 + 串联）

**Files:**
- Create: `ring_desktop/app.py`

**接线**：bleak 在后台线程跑（自带 asyncio loop）→ 收到手势码 → 转手势名 → 查前台 bundle → `resolve_action` → `dispatch`；菜单栏每 0.5s 刷新状态/最近手势；"打开配置"拉起子进程。

- [ ] **Step 1: 写实现**

```python
# ring_desktop/app.py
import asyncio
import logging
import os
import subprocess
import sys
import threading

import rumps

from .ble import RingBLE
from .gestures import GESTURE_NAMES
from .config import load_config, resolve_action
from .frontmost import frontmost_bundle_id
from .actions import dispatch

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("ring_desktop.app")

CONFIG_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "config.json")

class RingApp(rumps.App):
    def __init__(self):
        super().__init__("●Ring", quit_button=None)
        self.status = "starting"
        self.last = "-"
        self.menu = ["打开配置…", "退出"]
        self._ble = RingBLE(on_gesture=self._on_gesture, on_status=self._on_status)
        threading.Thread(target=self._run_ble, daemon=True).start()
        rumps.Timer(self._refresh, 0.5).start()

    def _run_ble(self):
        asyncio.run(self._ble.run())

    def _on_status(self, s: str):
        self.status = s

    def _on_gesture(self, code: int):
        name = GESTURE_NAMES.get(code, str(code))
        bundle = frontmost_bundle_id()
        cfg = load_config(CONFIG_PATH)          # 每次重读，配置窗改了即时生效
        action = resolve_action(cfg, bundle, name)
        self.last = f"{name}→{action.get('value') if action else '—'}"
        log.info("gesture=%s app=%s action=%s", name, bundle, action)
        if action:
            try:
                dispatch(action)
            except Exception as e:
                log.warning("dispatch failed: %s", e)

    def _refresh(self, _):
        dot = "🟢" if self.status == "connected" else "⚪️"
        self.title = f"{dot}Ring"
        self.menu["打开配置…"].title = f"打开配置…  ({self.status} · {self.last})"

    @rumps.clicked("打开配置…")
    def open_config(self, _):
        subprocess.Popen([sys.executable, "-m", "ring_desktop.config_window"])

    @rumps.clicked("退出")
    def quit_app(self, _):
        self._ble.stop()
        rumps.quit_application()

def main():
    RingApp().run()

if __name__ == "__main__":
    main()
```

- [ ] **Step 2: 手动验证（端到端）**

Run（戒指已释放并唤醒；先 `cp config.example.json config.json`）:
```bash
python -m ring_desktop.app
```
Expected:
- 菜单栏出现 `⚪️Ring`，连上后变 `🟢Ring`；
- 焦点切到 **Claude 桌面端**，戒指**三击** → Claude 输入框回车（提交）；**长按** → 清空输入框（Ctrl+U）；
- 点菜单 `打开配置…` 不报错（Task 7 完成后会弹窗）。

- [ ] **Step 3: Commit**

```bash
git add ring_desktop/app.py && git commit -m "feat: menubar app wiring ble->frontmost->config->inject"
```

---

## Task 7: `config_window.py` — pywebview 配置窗（独立子进程）

**Files:**
- Create: `ring_desktop/config_window.py`

**职责**：弹一个窗，展示 default + 各 app 的「手势→按键」，可改、可"添加运行中的 app"，保存写回 `config.json`。

- [ ] **Step 1: 写实现**

```python
# ring_desktop/config_window.py
import json
import os
import webview
from .config import load_config, save_config
from .frontmost import running_apps

CONFIG_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "config.json")
GESTURES = ["longPress", "single", "double", "triple", "up", "down", "left", "right"]
KEY_CHOICES = ["", "enter", "esc", "tab", "shift+tab", "up", "down", "left", "right",
               "ctrl+u", "cmd+a", "cmd+enter", "space", "backspace"]

class Api:
    def get_state(self):
        return {"config": load_config(CONFIG_PATH), "running": running_apps(),
                "gestures": GESTURES, "keys": KEY_CHOICES}

    def save(self, config_json):
        cfg = json.loads(config_json)
        save_config(CONFIG_PATH, cfg)
        return True

HTML = """
<!doctype html><html><head><meta charset="utf-8"><style>
body{font:14px -apple-system;margin:16px;color:#222}
h3{margin:18px 0 6px} select{margin:2px} .app{border:1px solid #ddd;border-radius:8px;padding:10px;margin:8px 0}
.row{display:flex;gap:8px;align-items:center;margin:3px 0} .row label{width:90px}
button{padding:6px 12px;border-radius:6px;border:1px solid #aaa;background:#f6f6f6;cursor:pointer}
</style></head><body>
<h2>Ring 配置</h2>
<div id="apps"></div>
<h3>添加 app</h3><select id="add"></select><button onclick="addApp()">添加</button>
<p><button onclick="save()">保存</button> <span id="msg"></span></p>
<script>
let S=null;
async function load(){ S=await window.pywebview.api.get_state(); render(); }
function render(){
  const apps=document.getElementById('apps'); apps.innerHTML='';
  for(const b of Object.keys(S.config)){ apps.appendChild(card(b, S.config[b])); }
  const add=document.getElementById('add'); add.innerHTML='';
  for(const a of S.running){ const o=document.createElement('option');
    o.value=a.bundle; o.text=a.name+' ('+a.bundle+')'; add.appendChild(o); }
}
function card(bundle, prof){
  const d=document.createElement('div'); d.className='app';
  d.innerHTML='<b>'+bundle+'</b>';
  for(const g of S.gestures){
    const cur=(prof[g]&&prof[g].value)||'';
    const opts=S.keys.map(k=>'<option '+(k===cur?'selected':'')+' value="'+k+'">'+(k||'（不绑）')+'</option>').join('');
    const row=document.createElement('div'); row.className='row';
    row.innerHTML='<label>'+g+'</label><select data-b="'+bundle+'" data-g="'+g+'">'+opts+'</select>';
    d.appendChild(row);
  }
  return d;
}
function collect(){
  const cfg={}; document.querySelectorAll('select[data-g]').forEach(s=>{
    const b=s.dataset.b,g=s.dataset.g; cfg[b]=cfg[b]||{};
    if(s.value) cfg[b][g]={type:'key',value:s.value};
  }); return cfg;
}
function addApp(){ const b=document.getElementById('add').value;
  if(!S.config[b]) S.config[b]={}; render(); }
async function save(){ const merged=collect();
  if(!merged.default) merged.default=S.config.default||{};
  await window.pywebview.api.save(JSON.stringify(merged));
  document.getElementById('msg').innerText='已保存 ✓'; }
window.addEventListener('pywebviewready', load);
</script></body></html>
"""

def main():
    webview.create_window("Ring 配置", html=HTML, js_api=Api(), width=560, height=720)
    webview.start()

if __name__ == "__main__":
    main()
```

- [ ] **Step 2: 手动验证**

Run:
```bash
python -m ring_desktop.config_window
```
Expected: 弹窗，列出 default / Claude / 钉钉 三块，每个手势一个下拉；"添加 app" 下拉里有运行中的 app；改一个绑定→点保存→`config.json` 更新；关窗。再 `cat config.json` 看是否写入。

- [ ] **Step 3: 端到端联调**

Run: `python -m ring_desktop.app` → 菜单栏"打开配置…" → 改 Claude 的"单击"为某键 → 保存关窗 → 戒指单击 → 立即生效（app 每次手势重读 config）。

- [ ] **Step 4: Commit**

```bash
git add ring_desktop/config_window.py && git commit -m "feat: pywebview per-app config window"
```

---

## 自检（写完计划后对照 spec）

- **覆盖**：连接(Task5) / 解析(Task1) / 前台识别(Task4) / per-app 配置(Task2,7) / 注入(Task3) / 菜单栏+串联(Task6) ✓。语音/ASR/打包属 M2/M3，本计划不含（spec §8 已分期）。
- **占位**：无 TBD；每个代码步骤给了完整代码。
- **类型一致**：手势名 `GESTURE_NAMES`(Task1) 贯穿 config(Task2)/app(Task6)/配置窗(Task7)；action 形状 `{"type","value"}` 一致；`resolve_action(cfg,bundle,name)` 签名一致；BLE `KEY_CHAR=bae80011`。
- **已知偏差**：配置窗用独立子进程（非同进程嵌入），规避 rumps/pywebview 双主线程冲突——已在架构说明。

## 风险/前置
- 跑前需 **`adb shell am force-stop com.eureka.mindapp`** 释放戒指（否则被手机抢）。
- 权限：终端的**蓝牙** + **辅助功能**（首次弹窗授权）。
- `bleak` 设备选择是"最强信号且有名字"——若环境里别的强信号设备干扰，Task5 可改成记下戒指地址后用 `address=` 直连（`run_once` 已支持）。
