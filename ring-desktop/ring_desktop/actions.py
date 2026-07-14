import logging
import time
from typing import List, Tuple, Union

import Quartz
from AppKit import NSPasteboard, NSPasteboardTypeString, NSScreen
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


def _scroll(direction: str) -> None:
    """在对话区(屏幕中央)发滚轮事件——不移动鼠标、不依赖焦点。方向反了把正负对调。"""
    lines = 5 if direction == "up" else -5
    fr = NSScreen.mainScreen().frame()
    ev = Quartz.CGEventCreateScrollWheelEvent(
        None, Quartz.kCGScrollEventUnitLine, 1, lines)
    Quartz.CGEventSetLocation(ev, Quartz.CGPointMake(fr.size.width / 2.0, fr.size.height / 2.0))
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, ev)


def parse_sequence(value: str) -> List[Tuple[List[Key], KeyType]]:
    """'cmd+a;backspace' -> 依次执行的组合键列表。用 ';' 分隔多步。"""
    return [parse_keyspec(c) for c in value.split(";") if c.strip()]


def _send_combo(mods: List[Key], main: KeyType) -> None:
    for m in mods:
        _controller.press(m)
    try:
        _controller.press(main)
        _controller.release(main)
    finally:
        for m in reversed(mods):
            _controller.release(m)


def _send_key(value: str) -> None:
    for i, (mods, main) in enumerate(parse_sequence(value)):
        if i:
            time.sleep(0.03)  # 组合键之间留一点间隔，给 app 反应
        _send_combo(mods, main)


def type_text(text: str) -> None:
    """把文字注入当前聚焦窗口。走剪贴板 Cmd+V 粘贴，绕开中文输入法对逐字键入的拦截，
    中英文混排都稳。粘贴后还原用户原剪贴板。"""
    pb = NSPasteboard.generalPasteboard()
    old = pb.stringForType_(NSPasteboardTypeString)
    pb.clearContents()
    pb.setString_forType_(text, NSPasteboardTypeString)
    _send_combo([Key.cmd], "v")
    time.sleep(0.2)
    if old is not None:
        pb.clearContents()
        pb.setString_forType_(old, NSPasteboardTypeString)


def dispatch(action: dict) -> None:
    """执行一个动作。M1 支持 key / text；其余类型记日志跳过。"""
    if not action:
        return
    t = action.get("type")
    if t == "key":
        _send_key(action["value"])
    elif t == "scroll":
        _scroll(action.get("value", "down"))
    elif t == "text":
        type_text(action["value"])
    else:
        log.info("action type not handled: %s", t)
