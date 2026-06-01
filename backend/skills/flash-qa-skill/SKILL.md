---
name: flash-qa-skill
description: >
  Part of the Eureka flash pipeline. Receives a dispatched qa intent and gives
  a short, direct answer in conversational text (no asset creation). Use
  whenever the dispatcher routes a question or information-lookup intent.
---

# Flash QA Skill

闪念里的「Siri 式」短答模块。

闪念是一个低延迟的语音入口,用户问问题期望**5 秒内**听到答案。所以这个 skill 的
唯一职责就是**给一个简短、直接的答案**,然后结束。

> **不在本 skill 范围内**:长篇调研、briefing、报告、深度分析 —— 那是未来 `task-skill` 的事,
> 或者用户改去 chat 提问。本 skill 收到这类请求时,**给一个简短的答案就好**,
> 不要自己加长,也不要解释「这需要更深入研究」。

## Input

```
source_text:           "<question slice>"
user_text:             "<full original input>"
session_id:            "<session id>"
source_input_turn_id:  "<input_turn id>"
```

## What to do

1. 读 `source_text`,判断是「事实问答」还是「问自己的数据」
2. **问自己的数据**(「我今天有几个待办」「我最近花了多少」)→ 调 `tool_query_asset` 拿数据 → 用一句话告诉用户
3. **事实问答 / 一般知识**(「伽利略是谁」「为什么地球是圆的」「拿铁和美式区别」)→ 直接用你的知识答,**1-3 句**,不分段不列表
4. 即使用户问的是大题目(「帮我做调研」「写一篇 briefing」)也**只给短答** —— 几句话总结核心要点,告诉用户「需要更深入可以去 chat 详聊」

**不要调** `tool_create_asset` / `tool_update_asset` 等任何写工具 —— 本 skill 无副作用。
**不要在答案里提及保存、提及未来 task-skill、提及任何系统机制** —— 答案只放纯内容。

## Output format

```json
{
  "ok": true,
  "session_id": "<pass through>",
  "source_input_turn_id": "<pass through>",
  "answer": "<plain text, 1-3 句>"
}
```

`answer` 是纯文本,不带 markdown、不带列表、不带「以下是...」前缀。

## Examples

**Input:** `长白山在哪个省`
**Output:**
```json
{"ok": true, "session_id": "<pass through>", "source_input_turn_id": "<pass through>", "answer": "长白山在吉林省,位于中朝边境。"}
```

**Input:** `拿铁和美式有什么区别`
**Output:**
```json
{"ok": true, "session_id": "<pass through>", "source_input_turn_id": "<pass through>", "answer": "拿铁是浓缩咖啡加蒸汽牛奶,口感奶香;美式是浓缩加热水,清爽偏苦。"}
```

**Input:** `我今天有几个待办`
先调 `tool_query_asset(user_skill_name="todo", ...)`,再回:
```json
{"ok": true, "session_id": "<pass through>", "source_input_turn_id": "<pass through>", "answer": "你今天有 3 个待办:跟刘洋发合同、买咖啡豆、回 Kevin 邮件。"}
```

**Input(用户问的是个大题目,这里只给短答):** `帮我做一份关于地球物种多样性的调研`
**Output:**
```json
{"ok": true, "session_id": "<pass through>", "source_input_turn_id": "<pass through>", "answer": "地球已记录约 200 万种物种,实际估计 870 万。主要威胁是栖息地破坏和气候变化。需要更详细的可以去 chat 接着问。"}
```

⚠️ **必须返回 JSON 对象**,不要返回裸字符串。即使示例看起来很简单,也要严格按 Output format 包成 JSON。
