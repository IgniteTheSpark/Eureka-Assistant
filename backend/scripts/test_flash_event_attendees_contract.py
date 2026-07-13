#!/usr/bin/env python3
from pathlib import Path


SKILL = Path(__file__).resolve().parents[1] / "skills" / "flash-event-skill" / "SKILL.md"


def main() -> None:
    text = SKILL.read_text()
    assert "tool_query_contact" in text
    assert "0 命中" in text and "1 命中" in text and "2+ 命中" in text
    assert "不创建 contact" in text
    assert "完全重复" in text and "去重" in text
    print("ok - flash event attendee safety contract")


if __name__ == "__main__":
    main()
