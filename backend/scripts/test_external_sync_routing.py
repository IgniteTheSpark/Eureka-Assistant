from __future__ import annotations

from agents.assistant import _requires_tracked_external_task


CASES = [
    ("可以帮我把小型讨论会的日程和饭局放进钉钉吗", True),
    ("把 Eureka 的代办同步到钉钉待办", True),
    ("把刚刚那段总结放到钉钉文档", True),
    ("把这个会议加到 Google Calendar", True),
    ("查我今天有哪些钉钉日程", False),
    ("看看我有哪些钉钉待办", False),
    ("把那个钉钉日程改到 4 点", False),
    ("删掉钉钉里的那个会", False),
]


def main() -> None:
    for text, expected in CASES:
        actual = _requires_tracked_external_task(text)
        assert actual is expected, f"{text!r}: expected {expected}, got {actual}"
        print(f"ok - {text}: {actual}")


if __name__ == "__main__":
    main()
