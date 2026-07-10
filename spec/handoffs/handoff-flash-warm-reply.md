# Handoff · Flash Reply Agent（替换「已记录 N 项内容」）

> 给 coding agent。目标：闪念完成后，用户看到的不是机械的「已记录 N 项内容」，而是 REKA 理解了用户刚刚记录的内容后，自己生成的一句短、温暖、具体的回应。
> **真值**：[§1 Step3 Flash 完成反馈](../01-agent-architecture.md) · [§3.1 FlashResponse](../03-api-reference.md) · [§99 回复风格](../99-prompts-appendix.md)。

---

## 0. 现状问题

当前 `backend/agents/flash_pipeline.py::_build_summary` 基本是：

```python
summary = f"已记录 {ok_count} 项内容。"
```

这让闪念体验像系统状态码。用户输入明明是「早上吃包子花了8」「下午要开一个会」「昨天下午跑了5km」，REKA 却只回一句「已记录 1 项内容」，没有听懂感，也没有正反馈。

---

## 1. 产品目标

Flash 结构化卡片负责展示事实；`summary` 负责让用户感觉：**REKA 听懂了我刚刚说的这件事，并替我收好了。**

这里不要做模板拼接，不要按 asset type 写死句式。用户记录的内容非常杂：消费、待办、跑步、宝宝打针、想法、名片、自定义技能都可能出现。固定规则会很快变僵硬。

正确方向：结构化完成后，用一个专门的 **Flash Reply Agent** 读取：

- 用户原始输入 `source_text`
- 已产出的 cards / derived_assets
- pending confirmation / suggest_skill 等状态
- 必要的时间字段（period / occurred_at / date）

然后由 agent 自己生成一句自然回复。

---

## 2. 输出边界

Flash Reply Agent 不是聊天 agent，不做长对话，只做一句完成反馈。

要求：

- **一到两句，优先一句**；通常 12-50 个中文字符。
- **理解内容**：回应要和用户刚记录的事有关，而不是只报数量。
- **有温度但克制**：温和、轻、有陪伴感；不鸡汤、不夸张、不卖萌。
- **忠于卡片**：只能基于原话和已产出的卡，不编事实。
- **不暴露内部**：不出现 asset_id、tool name、JSON、字段名、prompt、规则、模型判断。
- **不影响创建**：reply 生成失败不能让 flash 失败。

坏例子：

- `已记录 1 项内容。`
- `已记录 3 项内容。`
- `我判断这是 expense，已经创建 asset。`
- `太棒啦！！！你今天真的超级自律！！！`

可接受风格示例（不是模板，只是风格标尺）：

- `包子这笔 8 块我帮你记好了，放在今天上午。`
- `下午的会我先帮你记着了，还没具体到几点。`
- `这次 5km 跑步也收好啦，归到昨天下午。`
- `都记好啦：早饭、咖啡两笔账，还有下午的会。`

---

## 3. 推荐架构

### 3.1 新增 Flash Reply Agent

文件建议：

- `backend/agents/flash_reply.py`（新增）
- `backend/agents/flash_pipeline.py`（调用）

新增一个轻量函数：

```python
async def generate_flash_summary(
    source_text: str,
    cards: list[dict],
    derived_assets: list[dict],
    pending: list[dict] | None = None,
    suggest_skill: str | None = None,
    user_id: str = "default",
) -> str:
    ...
```

它内部调用现有 LLM provider / ADK / LiteLLM 路径，使用一个专门 prompt，返回一条中文短句。

### 3.2 调用位置

结构化 pipeline 顺序保持：

```text
dispatcher → sub-skills 并行创建 → Python 聚合 cards/derived_assets → Flash Reply Agent → FlashResponse.summary
```

也就是说，reply agent **只读结果，不参与创建**。它不能重新路由、不能调 create/update/delete 工具。

`_aggregate` 当前大概返回：

```python
reply = _build_reply(qa_results)
cards = [_make_card(r, render_specs) for r in asset_results]
summary = _build_summary(asset_results, has_reply=bool(reply))
```

改成：

```python
reply = _build_reply(qa_results)
cards = [_make_card(r, render_specs) for r in asset_results]
derived_assets = ...
summary = await generate_flash_summary(...) if cards else fallback
```

如果有 QA reply，`reply` 仍然放 QA 答案；记录确认仍放 `summary`。不要混用。

### 3.3 超时与 fallback

Flash 是高频入口，不能被 reply agent 拖慢太多。

建议：

- reply agent timeout：800-1500ms。
- 超时 / 报错 / 空字符串 → fallback。
- fallback 不能回到「已记录 N 项内容」，用：
  - 单条：`我帮你记好了。`
  - 多条：`这些我都帮你记好了。`
  - pending contact：保留确认提示。

这样即使 LLM 失败，体验也不机械。

---

## 4. Prompt 设计

新增 prompt 常量，例如 `FLASH_REPLY_INSTRUCTION`：

```text
你是 UReka 里的 Reka。用户刚刚随口记录了一段内容，系统已经把它整理成结构化卡片。

你的任务：基于用户原话和已生成的卡片，回复一句自然、温暖、具体的确认。

要求：
- 中文。
- 只输出一句，最多两句。
- 要让用户感觉你听懂了他刚刚说的内容。
- 可以轻轻点出关键内容、时间、数量或行动，但不要像报表。
- 只能使用用户原话和卡片里已有的信息，不要编造。
- 不要出现 asset_id、tool name、JSON、字段名、内部判断。
- 不要说「已记录 N 项内容」。
- 不要夸张鼓励、不要连续感叹号、不要卖萌。
- 如果有多个卡片，可以自然概括其中最重要的 2-3 个。
- 如果有需要确认的联系人或信息，可以温和提醒。

输入会包含：
source_text: 用户原话
cards: 已生成的用户可见卡片摘要
pending: 需要确认的事项
suggest_skill: 可选的技能建议

只返回最终给用户看的那句话。
```

传给 agent 的 cards 要先做瘦身，避免把完整 payload / 内部 id 塞进去。

推荐输入形状：

```json
{
  "source_text": "早上吃包子花了8",
  "cards": [
    {
      "type": "expense",
      "title": "¥8",
      "subtitle": "包子",
      "display_time": "今天上午，没具体时间",
      "domain": "生活"
    }
  ],
  "pending": [],
  "suggest_skill": null
}
```

不要传：

- asset_id
- event_id
- source_input_turn_id
- raw tool result
- 大段 JSON payload

---

## 5. 前端 fallback

文件：

- `mobile/lib/flash/flash_sheet.dart`
- `mobile/lib/pages/pet_spawn_page.dart`

当前 fallback 可能有：

```dart
'已记录 ${cards.length} 项内容。'
```

改成：

```dart
cards.length == 1 ? '我帮你记好了。' : '这些我都帮你记好了。'
```

后端 `summary` 有值时仍以后端为准。

---

## 6. 测试 / 验收

### 6.1 Backend tests

不要求字面完全一致，因为这是 agent 生成。测**边界和语义**：

1. 不返回机械模板：
   - 输入：任意成功 card
   - 断言：不包含 `已记录 1 项内容` / `已记录 N 项内容`

2. 不暴露内部：
   - 断言：不包含 `asset_id` / `tool_create` / `{` / `}` / `payload` / `JSON`

3. 具体内容相关：
   - `早上吃包子花了8`：回复应包含 `包子` 或 `8` 之一，最好包含时间感 `上午`
   - `下午要开一个会`：回复应包含 `会` 或 `下午`
   - `昨天下午跑了5km`：回复应包含 `5km` 或 `跑步`

4. 多条记录：
   - `早饭8块，咖啡22，下午要开会`
   - 回复不能只报数量，应至少点到一个具体项。

5. 超时 fallback：
   - mock reply agent timeout
   - FlashResponse 仍 ok，cards 不丢，summary = `我帮你记好了。` 或 `这些我都帮你记好了。`

### 6.2 App 手测

输入：

- `早上吃包子花了8`
- `下午要开一个会`
- `昨天下午跑了5km`
- `早饭8块，咖啡22，下午要开会`

验收：

- 回复句有针对性，不是统一模板。
- 不出现工具名 / JSON / ID。
- 卡片数量和原来一致。
- reply agent 出错时，仍然看到卡片和温和 fallback。

---

## 7. 不要做

- 不要用固定模板拼句子作为主路径。
- 不要让 sub-skill 自己输出最终回复。
- 不要让 reply agent 调任何写工具。
- 不要让 reply agent 影响资产创建成功。
- 不要为了生成一句话传完整内部 JSON。
- 不要把 `reply` 和 `summary` 混用：QA 答案走 `reply`，记录确认走 `summary`。
