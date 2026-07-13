#!/usr/bin/env python3
from pathlib import Path


SKILL = Path(__file__).resolve().parents[1] / "skills" / "flash-event-skill" / "SKILL.md"


def section(text: str, start: str, end: str) -> str:
    start_at = text.index(start)
    end_at = text.index(end, start_at)
    return text[start_at:end_at]


def branch(step_3b: str, label: str) -> str:
    prefix = f"| **{label} 命中**"
    return next(line for line in step_3b.splitlines() if line.startswith(prefix))


def main() -> None:
    text = SKILL.read_text()
    step_3b = section(text, "**Step 3b", "### Update")
    zero_match = branch(step_3b, "0")
    one_match = branch(step_3b, "1")
    many_matches = branch(step_3b, "2+")

    forbidden_conflicts = (
        "不查 contacts",
        "不查询 contacts",
        "永不查询 contacts",
        "不要尝试匹配 contact",
        "不要传 contact_id",
        "不做智能匹配",
        "重复 add 没关系",
        "重复 attendee(同一个名字出现多次)不去重",
    )
    for conflict in forbidden_conflicts:
        assert conflict not in text, f"legacy attendee guidance remains: {conflict}"

    assert "tool_query_contact" in step_3b
    assert "不创建 contact" in step_3b

    assert 'name="<原文里的称呼>"' in zero_match
    assert "contact_id" not in zero_match

    assert 'name=contacts[0]["name"]' in one_match
    assert 'contact_id=contacts[0]["contact_id"]' in one_match

    assert 'name="<原文里的称呼>"' in many_matches
    assert "contact_id=" not in many_matches
    assert "contacts[0]" in many_matches and "第一条" in many_matches
    assert "不得" in many_matches or "不使用" in many_matches

    dedupe_at = step_3b.index("完全重复")
    assert dedupe_at < step_3b.index("tool_query_contact")
    assert dedupe_at < step_3b.index("tool_add_event_attendee")

    examples = section(text, "## Examples", "## Notes")
    kevin_example = section(
        examples,
        "**输入:** `周五晚上7点跟Kevin、Kevin和刘洋老师一起吃饭`",
        "**输入:** `明天早上 9 点站会`",
    )
    assert kevin_example.count('tool_query_contact(name_query="Kevin")') == 1
    assert kevin_example.count('tool_add_event_attendee(event_id, name="Kevin"') == 1

    print("ok - flash event attendee safety contract")


if __name__ == "__main__":
    main()
