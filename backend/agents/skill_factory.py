"""
Sub-skill agent factory — Phase B v1.4.x.

Builds ADK LlmAgents from the skills/ directory + shared MCPToolset.

Adding a new skill:
1. Drop `skills/flash-<name>-skill/SKILL.md` — it's auto-discovered at boot
2. Add UserSkill row (via db/seed.py or design-agent flow) so the asset has
   payload_schema + render_spec
3. Add a row to flash-dispatcher/SKILL.md's intent table so the dispatcher
   knows the type exists

No factory code changes needed — `SKILL_FOLDER_MAP` is computed from the
filesystem at import time.
"""
from pathlib import Path

from google.adk.agents import LlmAgent

from agents.mcp_toolset import get_mcp_toolset
from core.llm import FLASH_SKILL_MODEL, FLASH_DISPATCHER_MODEL


SKILLS_DIR = Path(__file__).parent.parent / "skills"

# Folders we never want to dispatch to even if they live in skills/.
# `flash-dispatcher` is the dispatcher itself, not a sub-skill.
_NON_SKILL_FOLDERS = {"flash-dispatcher"}


def _discover_skill_folders() -> dict[str, str]:
    """
    Scan skills/ for folders matching `flash-<machine_name>-skill/` that
    contain a SKILL.md, return {machine_name → folder_name}.

    Naming convention: `flash-<machine_name>-skill`
      - `flash-todo-skill`    → machine_name="todo"
      - `flash-expense-skill` → machine_name="expense"

    Folders not matching this pattern (e.g. flash-dispatcher) are skipped.
    """
    out: dict[str, str] = {}
    if not SKILLS_DIR.exists():
        return out
    for folder in SKILLS_DIR.iterdir():
        if not folder.is_dir():
            continue
        if folder.name in _NON_SKILL_FOLDERS:
            continue
        if not (folder / "SKILL.md").exists():
            continue
        name = folder.name
        if not (name.startswith("flash-") and name.endswith("-skill")):
            continue
        machine_name = name[len("flash-"):-len("-skill")]
        out[machine_name] = name
    return out


# Snapshot at import time. Restart backend to pick up newly-added skill folders.
SKILL_FOLDER_MAP: dict[str, str] = _discover_skill_folders()


def _load_prompt(folder: str) -> str:
    """Load skills/<folder>/SKILL.md as a string."""
    path = SKILLS_DIR / folder / "SKILL.md"
    if not path.exists():
        raise FileNotFoundError(f"no SKILL.md at {path}")
    return path.read_text(encoding="utf-8")


def make_skill_agent(skill_name: str) -> LlmAgent:
    """
    Create an ephemeral LlmAgent for a flash-pipeline sub-skill.
    Each call returns a fresh agent (cheap — they are stateless one-shots).
    """
    folder = SKILL_FOLDER_MAP.get(skill_name)
    if not folder:
        raise ValueError(
            f"unknown skill: {skill_name!r}. "
            f"Discovered: {sorted(SKILL_FOLDER_MAP)}. "
            f"To add: drop skills/flash-{skill_name}-skill/SKILL.md and restart."
        )
    prompt = _load_prompt(folder)
    return LlmAgent(
        name=f"{skill_name}_skill",
        model=FLASH_SKILL_MODEL,
        instruction=prompt,
        tools=[get_mcp_toolset()],
    )


def make_dispatcher_agent(custom_skills_hint: str = "") -> LlmAgent:
    """
    Create the Flash Pipeline dispatcher LlmAgent.
    Outputs intent list JSON; no tools (pure classification).

    `custom_skills_hint` (May audit): when the user has registered custom
    skills via AddSkillWizard (跑步记录 / 宝宝养育记录 / …), append a
    block teaching the dispatcher to emit `type=<machine_name>` for any
    keyword hit, rather than dumping content into misc. Empty string when
    user has no custom skills (back-compat: prompt is exactly as it was).
    """
    prompt = _load_prompt("flash-dispatcher")
    if custom_skills_hint:
        prompt += (
            "\n\n---\n\n"
            "## 用户自定义 skill(关键!优先匹配,胜过 misc/notes)\n\n"
            "用户在 AddSkillWizard 里注册了下面这些 skill。**如果 user_text "
            "里出现任何 skill 的关键名词,就把 intent type 设成那个 "
            "skill 的 machine_name**(而不是 misc/notes/idea)。\n\n"
            + custom_skills_hint
            + "\n\n判断:\n"
            "- 「跑了 5 公里」→ type=\"running\" (字典里有 跑步记录)\n"
            "- 「宝宝喝奶」→ type=\"babycare\" (字典里有 宝宝养育记录)\n"
            "- 字典里**没有**任何匹配 → 才回退 misc / notes\n\n"
            "示例输出:\n"
            "```json\n"
            "{\"intents\": [{\"type\": \"running\", \"source_text\": \"跑了 5 公里 步频 6\"}]}\n"
            "```\n"
        )
    return LlmAgent(
        name="flash_dispatcher",
        model=FLASH_DISPATCHER_MODEL,
        instruction=prompt,
        tools=[],
    )


def make_custom_skill_agent(
    skill_name: str,
    display_name: str,
    payload_schema: dict,
    render_spec: dict,
) -> LlmAgent:
    """
    Generic flash sub-skill for user-registered custom skills. The user
    registered the skill via AddSkillWizard but didn't drop a SKILL.md, so
    we build the prompt at call time from the schema + render hints.

    The agent's only job: extract fields from `source_text`, then call
    tool_create_asset(user_skill_name=<machine_name>, payload=<JSON>,
    session_id=..., source_input_turn_id=...).
    """
    # Compact field doc for the prompt.
    fields: list[str] = []
    if isinstance(payload_schema, dict):
        for fname, fmeta in payload_schema.items():
            if not isinstance(fmeta, dict):
                continue
            ftype = fmeta.get("type", "string")
            req = "(必填)" if fmeta.get("required") else "(可选)"
            desc = fmeta.get("description", "")
            unit_bits: list[str] = []
            if fname == render_spec.get("primary_field") and render_spec.get("primary_unit"):
                unit_bits.append(f"单位:{render_spec['primary_unit']}")
            if fname == render_spec.get("secondary_field") and render_spec.get("secondary_unit"):
                unit_bits.append(f"单位:{render_spec['secondary_unit']}")
            extras = (" " + " ".join(unit_bits)) if unit_bits else ""
            fields.append(f"- `{fname}` ({ftype}{req}): {desc}{extras}")
    fields_text = "\n".join(fields) if fields else "(无 schema)"

    instruction = (
        f"你是 Eureka 的「{display_name}」记录 skill。从 source_text 里抽取字段,"
        f"然后调用 tool_create_asset 把这条记录写进数据库。\n\n"
        f"## 输入\n"
        f"- source_text: 用户原话(对应这一条记录的片段)\n"
        f"- user_text: 完整原话(背景)\n"
        f"- session_id / source_input_turn_id: 工具调用要带的值\n\n"
        f"## payload 字段\n"
        f"{fields_text}\n\n"
        f"## 流程\n"
        f"1. 从 source_text 抽 payload(只放出现的字段;未提到的字段就别加)\n"
        f"2. 时间/日期字段统一 ISO8601 +08:00(参考 prompt 里给的「今天」)\n"
        f"3. 调用 tool_create_asset:\n"
        f"     user_skill_name=\"{skill_name}\"\n"
        f"     payload=JSON 字符串\n"
        f"     session_id=<上面给的>\n"
        f"     source_input_turn_id=<上面给的>\n"
        f"4. 工具返回后,**只输出**(不要别的话):\n"
        f"```json\n"
        f"{{\"ok\": true, \"asset_id\": \"<返回的 id>\", \"user_skill_name\": \"{skill_name}\", \"payload\": <你写的 payload>}}\n"
        f"```\n"
        f"如果工具失败:`{{\"ok\": false, \"error\": \"<原因>\"}}`\n"
    )

    return LlmAgent(
        name=f"{skill_name}_custom_skill",
        model=FLASH_SKILL_MODEL,
        instruction=instruction,
        tools=[get_mcp_toolset()],
    )
