"""
LLM configuration — Phase B Step 3.

Single place to:
- Set up provider env vars (LiteLLM picks up from env)
- Define per-role model selections (swap models for all consumers in one place)

Provider: OpenRouter (gateway). Current model: Moonshot Kimi K2.5 via OpenRouter.

Why Kimi-via-OpenRouter (not Gemini/Claude/GPT):
- Anthropic / OpenAI / Google upstream providers reject requests via OpenRouter
  from certain regions (returns generic "TOS violation" 403). Kimi (Moonshotai)
  routes through Novita and doesn't trigger the same restriction.
- Kimi K2.5 has strong Chinese support and solid function-calling, which the
  agents (Assistant + Flash Pipeline sub-skills + Design Agent) depend on.

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
    if settings.openrouter_api_key:
        os.environ.setdefault("OPENROUTER_API_KEY", settings.openrouter_api_key)
    if settings.openai_api_key:
        # OpenAI key is for Whisper ASR (audio upload path is deferred per Phase A)
        os.environ.setdefault("OPENAI_API_KEY", settings.openai_api_key)


# ── Per-role models ────────────────────────────────────────────────────────────
# Change a single string here to swap a model for every consumer. Roles are
# named by where they get used in the architecture, not by model family.
#
# Current pick: DeepSeek Chat via OpenRouter for everything.
# - China-friendly (no IP-region 403 issues that Claude/GPT/Gemini hit)
# - Strong, reliable function-calling discipline — handles the double-JSON
#   pattern in our MCP tools (create_asset takes payload as JSON string)
#   without truncation or escape errors that broke Kimi K2 in integration
# - Non-reasoning, fast (~2-5s/call), very cheap
# Past trials:
# - openrouter/google/gemini-2.5-flash: 403 TOS (provider blocked for account)
# - openrouter/anthropic/claude-3.5-haiku: 403 TOS
# - openrouter/openai/gpt-4o-mini: 403 TOS
# - openrouter/moonshotai/kimi-k2.5/k2.6: reasoning models, content truncated
# - openrouter/moonshotai/kimi-k2: tool_call args malformed JSON, ADK chokes
# Swap by changing the strings below — agent code doesn't move (clean seam).

ASSISTANT_MODEL        = LiteLlm(model="openrouter/deepseek/deepseek-chat")
FLASH_DISPATCHER_MODEL = LiteLlm(model="openrouter/deepseek/deepseek-chat")
FLASH_SKILL_MODEL      = LiteLlm(model="openrouter/deepseek/deepseek-chat")
DESIGN_AGENT_MODEL     = LiteLlm(model="openrouter/deepseek/deepseek-chat")
TASK_MODEL             = LiteLlm(model="openrouter/deepseek/deepseek-chat")   # v1.4.x — task-skill MCP router
