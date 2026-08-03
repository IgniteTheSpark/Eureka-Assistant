import pytest

from app.domains.capture.chat import (
    LiteLLMFlashChatProvider,
    PermanentFlashChatError,
    build_flash_chat_messages,
)


def test_flash_chat_prompt_keeps_context_and_question_untrusted():
    messages = build_flash_chat_messages(
        session_date="2026-08-03",
        context='{"assets":[{"type":"todo","title":"提交评审稿"}]}',
        history=[
            {"role": "user", "text": "上一问"},
            {"role": "agent", "text": "上一答"},
        ],
        question="今天有什么待办？",
    )

    assert "answer questions" in messages[0]["content"].lower()
    assert "must not create, update, or delete" in messages[0]["content"]
    assert "BEGIN_UNTRUSTED_SESSION_CONTEXT" in messages[1]["content"]
    assert "提交评审稿" in messages[1]["content"]
    assert "上一问" in messages[2]["content"]
    assert "BEGIN_UNTRUSTED_USER_QUESTION" in messages[3]["content"]
    assert "今天有什么待办？" in messages[3]["content"]


async def test_flash_chat_provider_returns_a_real_answer():
    calls = []

    async def completion(**kwargs):
        calls.append(kwargs)
        return {"choices": [{"message": {"content": "今天有一项待办：提交评审稿。"}}]}

    provider = LiteLLMFlashChatProvider(
        model="test-model",
        api_key="test-key",
        timeout_seconds=3,
        completion=completion,
    )
    reply = await provider.answer(
        session_date="2026-08-03",
        context="{}",
        history=[],
        question="今天有什么待办？",
    )

    assert reply == "今天有一项待办：提交评审稿。"
    assert calls[0]["model"] == "test-model"
    assert calls[0]["api_key"] == "test-key"


async def test_flash_chat_provider_rejects_empty_response():
    async def completion(**_):
        return {"choices": [{"message": {"content": "  "}}]}

    provider = LiteLLMFlashChatProvider(
        model="test-model",
        api_key=None,
        timeout_seconds=3,
        completion=completion,
    )

    with pytest.raises(PermanentFlashChatError, match="empty"):
        await provider.answer(
            session_date="2026-08-03",
            context="{}",
            history=[],
            question="今天有什么待办？",
        )
