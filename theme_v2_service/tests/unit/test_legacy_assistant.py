from app.domains.sessions.legacy_assistant import (
    LegacyChatContext,
    build_legacy_assistant_instruction,
)


def _context() -> LegacyChatContext:
    return LegacyChatContext(
        session_id="session-1",
        input_turn_id="turn-1",
        session_type="flash",
        now_local="2026-08-05T15:30:00+08:00",
        records_json='{"session_assets": [], "enabled_skills": []}',
    )


def test_legacy_instruction_preserves_in_scope_chat_behavior_contracts():
    prompt = build_legacy_assistant_instruction(_context())

    for marker in (
        "CREATE / QUERY / UPDATE / DELETE",
        "tool_create_contact",
        "刚才那个",
        "把刚才的回答存成随记",
        "普通问答不创建记录",
        "追问后补字段必须 UPDATE",
        "外部 MCP",
        "不可使用",
        "session-1",
        "turn-1",
        "2026-08-05T15:30:00+08:00",
    ):
        assert marker in prompt


def test_flash_session_type_changes_context_not_chat_pipeline():
    prompt = build_legacy_assistant_instruction(_context())

    assert "session_type=flash" in prompt
    assert "仍然使用统一 Chat pipeline" in prompt
    assert "不得创建 CaptureRecording" in prompt
    assert "不得增加闪念计数" in prompt
