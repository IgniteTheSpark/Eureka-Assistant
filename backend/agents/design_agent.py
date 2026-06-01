"""
Design Agent — Phase B Step 4 (decision Q1 #4 + Phase A §8).

Takes a user's natural-language description of a new skill they want to track
(e.g. "我想记录跑步训练") and produces a draft:
  { name, display_name, payload_schema, render_spec, sample_payload }

Used by POST /api/skills (Step 5). The frontend's AddSkillWizard streams the
draft into a live preview the user can tweak before committing.

Structured output via Gemini's response_schema (decision Q1 #4) — eliminates
JSON-parsing defensive code and reduces retries.

The render_spec produced here must conform to the receivable enum vocabulary
(7 accent_colors × 4 card_layouts × bounded format/action sets) so the
SkillCard renderer (Phase D §九) can render it without surprise.
"""
import json
import uuid

from google.adk.agents import LlmAgent
from google.adk.runners import Runner
from google.adk.sessions import InMemorySessionService
from google.genai.types import Content, Part

from core.llm import DESIGN_AGENT_MODEL


_session_service = InMemorySessionService()
APP_NAME = "eureka-design-agent"


DESIGN_INSTRUCTION = """
你是 Eureka 的「skill 设计助手」。用户描述一种想记录的东西,你产出一份
能直接装入 Eureka 系统的 skill 定义。

## 必须返回单个 JSON 对象,字段固定如下:

{
  "name":         "string",   // skill machine name,小写英文,不超过 30 字符,例 "running"
  "display_name": "string",   // 中文显示名,例 "跑步训练"
  "payload_schema": {         // 字段定义,3-6 个字段最合适
    "<field>": {
      "type":        "string|number|datetime|date|boolean",
      "required":    true|false,
      "description": "字段含义"
    }
  },
  "render_spec": {
    "card_layout":      "horizontal|stacked|inline|compact",
    "icon":             "string (1 个 emoji)",
    "accent_color":     "blue|amber|green|red|purple|gray|neutral",
    "primary_field":    "string (payload 字段名)",
    "secondary_field":  "string (payload 字段名,可省)",
    "secondary_format": "text|relative_date|absolute_date|time|currency|duration|badge|truncate_40",
    "meta_fields":      [{"field": "string", "format": "可省"}],
    "actions":          ["check"|"edit"|"delete"|"open"]
  },
  "sample_payload": {        // 示范数据一条,用于前端实时预览 card 的样子
    "<field>": <value>
  }
}

## 设计规则

- 字段尽量精简:3-6 个就够,多了用户填不动。优先「真正想记录的」,而不是「能记录的」。
- accent_color 必须从 7 个槽里选(都是有语义的):
    blue(默认/中性) · amber(提醒/注意) · green(正向/数字) · red(紧急)
    · purple(事件/日程) · gray(次要) · neutral(无强语义)
- icon 用 1 个 emoji,跟主题贴近(跑步 🏃、读书 📖、睡眠 😴、健身 💪、习惯 ⭕)
- card_layout 默认 horizontal;内容字段多/长用 stacked;时间流密集场景用 inline
- primary_field 必填,选最能一眼识别这条记录的字段(跑步 → 距离;读书 → 书名)
- secondary_format 不确定就 "text",日期/时间字段用 "relative_date" 或 "absolute_date"
- **字段覆盖(关键!别让用户记的东西在卡片上消失)**:payload 里每个有意义的
    字段都要能在卡片上看到 —— 要么是 primary_field / secondary_field,要么进
    meta_fields。尤其是自由文本字段(note / 备注 / 感想 / 描述 / 心情),用户
    随手记的内容常常落在这里;如果它没进 render_spec,卡片就只剩干巴巴的标题,
    用户会以为内容丢了。这类字段优先放 secondary_field(长文本能截断显示)或
    meta_fields。空字段不会显示,所以全放进去不会让卡片变脏。
- 不要发明 enum 外的值

## 字段类型 + 单位的处理(关键!)

卡片的显示规则非常简单:**`<字段的原始值>`** —— 没有前缀标签,没有
单位后缀。不要在 render_spec 里发明 `field_units` / `primary_label`
/ `primary_unit` 之类的 key,它们已被废弃。

那单位怎么办?**把单位塞进字段值里,或者用 string 字段让用户自由填写**:

- 跑步: `distance` 用 string,值像「5 km」「10 公里」。AI 不要自作主张
        生成 number + 单独的 unit 字段。
- 读书: `pages_read` 可以是 number(读到 123 页 → 用户能理解;不需要
        单位也清楚是页数),或 string「123 页」。两种都行。
- 喝水: `amount` 用 string,值像「500 毫升」。
- 宝宝生活: `amount` 一定是 string,值像「150 毫升」「300 克」「5 小时」
        (一个 skill 多种活动,单位会变,所以单位必须跟着值走)。

**判断标准**:这个字段在所有 asset 里都同一个单位吗?
- 是 → number 字段也行,值是裸数字
- 否 → 一定是 string,让用户连同单位一起写

## actions: "check" 的纪律

**只有真正状态化的 skill 才用 "check"**:todo(完成/未完成)、习惯打卡(打 / 没打)、
review(看了 / 没看)。这类 skill 的 payload 必有 status 或 done 字段。

**不要给** measurement / record / log 类型的 skill 加 "check" —— 跑步记录、读书、
喝水、记账,这些是「记下来一条」,不是「待办做完了」。强加 "check" 会让卡片
长出一个无意义的勾选框。

判断标准:你打算这条记录被「点击 ✓ 标记完成」吗?
- 是 → actions 里加 "check",payload 加 status: "todo" | "done"
- 否 → actions 别加 "check"(默认 ["edit", "delete"] 即可)
"""


# Response schema — passed to ADK LlmAgent for guaranteed structured output.
# Gemini's response_schema enforces this at decode time.
RESPONSE_SCHEMA = {
    "type": "object",
    "required": ["name", "display_name", "payload_schema", "render_spec", "sample_payload"],
    "properties": {
        "name":         {"type": "string"},
        "display_name": {"type": "string"},
        "payload_schema": {"type": "object"},
        "render_spec": {
            "type": "object",
            "required": ["card_layout", "icon", "accent_color", "primary_field"],
            "properties": {
                "card_layout": {
                    "type": "string",
                    "enum": ["horizontal", "stacked", "inline", "compact"],
                },
                "icon": {"type": "string"},
                "accent_color": {
                    "type": "string",
                    "enum": ["blue", "amber", "green", "red", "purple", "gray", "neutral"],
                },
                "primary_field":    {"type": "string"},
                "secondary_field":  {"type": "string"},
                "secondary_format": {"type": "string"},
                "meta_fields":      {"type": "array"},
                "field_units":      {"type": "object"},
                "actions":          {"type": "array"},
            },
        },
        "sample_payload": {"type": "object"},
    },
}


def make_design_agent() -> LlmAgent:
    """
    Create the design LlmAgent. Stateless — called per /api/skills request.

    NOTE on ADK structured-output API:
    ADK 1.0 LlmAgent should accept output_schema (or response_schema, name may
    differ across versions). If the keyword is wrong at integration time,
    Step 5 will catch it; we may fall back to prompt + JSON-parsing + 1 retry
    if structured output isn't available.
    """
    return LlmAgent(
        name="design_agent",
        model=DESIGN_AGENT_MODEL,
        instruction=DESIGN_INSTRUCTION,
        # output_schema enforces RESPONSE_SCHEMA at generation time when supported.
        # Keyword name may need adjustment for the installed ADK version.
        output_schema=RESPONSE_SCHEMA,
        tools=[],
    )


async def design_skill(description: str, user_id: str = "default") -> dict:
    """
    One-shot design call.
    Returns the parsed draft dict ({name, display_name, payload_schema, render_spec, sample_payload}).

    Raises if the LLM returns non-JSON (shouldn't happen with response_schema,
    but caller should handle JSONDecodeError defensively in Step 5).
    """
    agent = make_design_agent()
    sid = str(uuid.uuid4())
    await _session_service.create_session(
        app_name=APP_NAME, user_id=user_id, session_id=sid,
    )
    runner = Runner(agent=agent, app_name=APP_NAME, session_service=_session_service)
    msg = Content(role="user", parts=[Part(text=description)])

    final_text = ""
    async for event in runner.run_async(
        user_id=user_id, session_id=sid, new_message=msg,
    ):
        if event.is_final_response() and event.content and event.content.parts:
            final_text = event.content.parts[0].text or ""

    return json.loads(final_text)


# ── Clarifier — guided card flow before generation ────────────────────────────
#
# Conversational wizard: when the user's description is too vague to design a
# good skill from ("宝宝喂养记录"), ask 1-3 targeted questions first instead of
# guessing. Returns either {ready: true} (description was concrete enough) or
# {questions: [...]} for the frontend to render as a card flow.

CLARIFIER_INSTRUCTION = """
你是 Eureka 的 skill 引导助手。用户描述了一个想记录的东西,但有时候描述太
笼统,你要决定是否追问几个关键问题,把记录意图问清楚。

输入:用户的描述。
输出:**只输出 JSON**,从以下两种里选一种。

A) 描述已经够清楚(字段隐含、目的明确)→ 不需要追问:
{"ready": true}

B) 描述太笼统(只给类目,没说要记什么字段/目的)→ 追问:
{
  "questions": [
    {
      "key":         "<英文短标识,如 'purpose' / 'fields' / 'unit'>",
      "prompt":      "<中文问题>",
      "type":        "choice" | "text",
      "options":     ["选项1","选项2","..."],   // type=choice 时必填,2-4 项
      "placeholder": "<示例提示>"               // type=text 时可选
    }
  ]
}

## 判断「够清楚」的标准

- 含动作 + 数值(「跑步训练」「读书 100 页」「记账 50 块」)→ ready=true
- 已经隐含了核心字段(「跑步训练」隐含 距离/时长/配速)→ ready=true
- 只给类目名,没有任何字段提示(「宝宝喂养记录」「看书」「健身」)→ 追问
- 抽象 / 模糊(「灵感」「日记」「随便记记」)→ 追问

## 出问题的纪律

- **最多 3 个问题**,1-2 个最好;不要把 schema 设计全甩给用户
- 优先问:**记录目的 + 关键字段 + 时间维度**
- choice 给 2-4 个常见场景,涵盖大部分用户的需求
- text 留给开放回答(还想记哪些细节)
- 问的目的是缩小范围,不是 RPC 一个完整 schema —— 后面 design 阶段 LLM 还会扩展

## 示例

**输入:** `我想记录跑步训练`
**输出:** `{"ready": true}`

**输入:** `宝宝喂养记录`
**输出:**
{
  "questions": [
    {"key":"purpose","prompt":"主要想追踪什么?","type":"choice","options":["频率(几次)","量(毫升/克)","时间分布","综合"]},
    {"key":"fields","prompt":"每次记录还想填哪些信息?","type":"text","placeholder":"如:奶/水/辅食、份量..."}
  ]
}

**输入:** `看书`
**输出:**
{
  "questions": [
    {"key":"unit","prompt":"按什么粒度记?","type":"choice","options":["每天总时长","每本书的进度","每次阅读片段"]},
    {"key":"meta","prompt":"还想顺手记什么?","type":"text","placeholder":"如:书名、感想、引文..."}
  ]
}

**输入:** `健身打卡`
**输出:**
{
  "questions": [
    {"key":"focus","prompt":"主要想追踪哪一面?","type":"choice","options":["训练动作 + 组数","时长 + 强度","只是打卡完成"]}
  ]
}
"""

CLARIFIER_SCHEMA = {
    "type": "object",
    "properties": {
        "ready": {"type": "boolean"},
        "questions": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["key", "prompt", "type"],
                "properties": {
                    "key":         {"type": "string"},
                    "prompt":      {"type": "string"},
                    "type":        {"type": "string", "enum": ["choice", "text"]},
                    "options":     {"type": "array", "items": {"type": "string"}},
                    "placeholder": {"type": "string"},
                },
            },
        },
    },
}


def make_clarifier_agent() -> LlmAgent:
    """Conversational stage of the skill wizard — emits questions or `ready`."""
    return LlmAgent(
        name="skill_clarifier",
        model=DESIGN_AGENT_MODEL,
        instruction=CLARIFIER_INSTRUCTION,
        output_schema=CLARIFIER_SCHEMA,
        tools=[],
    )


async def clarify_skill(description: str, user_id: str = "default") -> dict:
    """
    Returns either {"ready": true} or {"questions": [...]}.

    Caller: api/skills.draft_skill — when ready, falls through to design_skill;
    when questions, frontend collects answers and POSTs back with them folded
    into the description for the design pass.
    """
    agent = make_clarifier_agent()
    sid = str(uuid.uuid4())
    await _session_service.create_session(
        app_name=APP_NAME, user_id=user_id, session_id=sid,
    )
    runner = Runner(agent=agent, app_name=APP_NAME, session_service=_session_service)
    msg = Content(role="user", parts=[Part(text=description)])
    final_text = ""
    async for event in runner.run_async(
        user_id=user_id, session_id=sid, new_message=msg,
    ):
        if event.is_final_response() and event.content and event.content.parts:
            final_text = event.content.parts[0].text or ""
    try:
        parsed = json.loads(final_text)
    except (json.JSONDecodeError, ValueError):
        # Conservative fallback: if the clarifier returns something we can't
        # parse, treat as ready and let the design pass do its best.
        return {"ready": True}
    if not isinstance(parsed, dict):
        return {"ready": True}
    return parsed
