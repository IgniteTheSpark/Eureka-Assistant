"""
LLM configuration — Phase B Step 3.

Single place to:
- Set up provider env vars (LiteLLM picks up from env)
- Define per-role model selections (swap models for all consumers in one place)

Provider: DeepSeek direct API (api.deepseek.com). Model: DeepSeek-V3 (deepseek-chat).

Why DeepSeek-direct (not OpenRouter):
- China-hosted (api.deepseek.com) → reliable 国内 inbound. OpenRouter (openrouter.ai)
  is unreliable/blocked from inside China, which matters for the deployed backend.
- OpenAI-compatible, native litellm `deepseek/` provider (tool calling supported).
- Strong Chinese support + reliable function-calling — handles the double-JSON
  pattern in our MCP tools (create_asset takes payload as a JSON string) without
  truncation/escape errors.

To swap models or providers later, just change the model strings below — agent
code doesn't move. (decision Q1 #1 / Phase A 「干净接缝」)

Replaces the previous `agents/model_config.py` (deleted in Step 6 cleanup).
"""
import os

from google.adk.models.lite_llm import LiteLlm

from config import settings


def configure_llm_env() -> None:
    """
    Populate environment variables LiteLLM looks for. Idempotent.
    Called once at app startup from main.py.
    """
    if settings.deepseek_api_key:
        # Primary text LLM — litellm reads DEEPSEEK_API_KEY for the `deepseek/` provider.
        os.environ.setdefault("DEEPSEEK_API_KEY", settings.deepseek_api_key)
    if settings.openrouter_api_key:
        # Legacy gateway — kept only as the §6.6.2 gemini image fallback key.
        os.environ.setdefault("OPENROUTER_API_KEY", settings.openrouter_api_key)
    if settings.openai_api_key:
        # OpenAI key is for Whisper ASR (audio upload path is deferred per Phase A)
        os.environ.setdefault("OPENAI_API_KEY", settings.openai_api_key)


# ── Per-role models ────────────────────────────────────────────────────────────
# Change a single string here to swap a model for every consumer. Roles are
# named by where they get used in the architecture, not by model family.
#
# Current pick: DeepSeek-V3 (deepseek-chat) via the DeepSeek DIRECT API for all roles.
# - China-hosted (api.deepseek.com) → reliable 国内 inbound (OpenRouter is blocked/
#   flaky from inside China; this is the deployed backend's path).
# - Strong, reliable function-calling discipline — handles the double-JSON pattern
#   in our MCP tools (create_asset takes payload as JSON string) without truncation
#   or escape errors that broke Kimi K2 in integration.
# - Non-reasoning, fast (~2-5s/call), very cheap.
# Past trials (all via OpenRouter, now retired):
# - openrouter/deepseek/deepseek-chat: worked, but OpenRouter is unreliable 国内
# - openrouter/google·anthropic·openai/*: 403 TOS (providers blocked for account)
# - openrouter/moonshotai/kimi-k2.5/k2.6: reasoning models, content truncated
# - openrouter/moonshotai/kimi-k2: tool_call args malformed JSON, ADK chokes
# Swap by changing the model string below — agent code doesn't move (clean seam).
#
# Key-driven selection: DeepSeek-direct when DEEPSEEK_API_KEY is set (prod + any
# dev that has the key), else fall back to the same model via OpenRouter so a dev
# box without the DeepSeek key keeps working. Prod can't silently fall back — the
# prod compose hard-requires DEEPSEEK_API_KEY.
_TEXT_MODEL = "deepseek/deepseek-chat" if settings.deepseek_api_key else "openrouter/deepseek/deepseek-chat"

ASSISTANT_MODEL        = LiteLlm(model=_TEXT_MODEL)
FLASH_DISPATCHER_MODEL = LiteLlm(model=_TEXT_MODEL)
FLASH_SKILL_MODEL      = LiteLlm(model=_TEXT_MODEL)
DESIGN_AGENT_MODEL     = LiteLlm(model=_TEXT_MODEL)
TASK_MODEL             = LiteLlm(model=_TEXT_MODEL)   # v1.4.x — task-skill MCP router
