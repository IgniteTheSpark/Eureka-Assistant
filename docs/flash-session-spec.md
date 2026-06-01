# Flash Session — 交互设计规范

_最后更新：2026-05-21（补充时间流展示规则 §四）_

---

## 一、概念定位

Flash Session（今日闪念）是一个**对话式知识捕获界面**，不是简单的表单录入。

用户向 Session 输入任何文字，Agent 都会：
1. 理解意图（捕获 / 查询 / 闲聊均可）
2. 执行相应操作（提取并存储资产，或查询已有数据）
3. **用自然语言给出回复**，并在回复下方附上操作结果的卡片

> **核心原则：每一轮用户输入，必须有 Agent 的文字回复。**

---

## 二、对话模型

### 消息结构

```
用户气泡（右，蓝色渐变）
Agent 气泡（左，✦ 头像）
  └── 文字回复（必须有）
  └── 资产卡片（有则显示，无则不显示）
```

### 不区分输入类型

Flash Session 的输入框**不做任何前端路由区分**（不看 `?`、不看关键词），所有输入统一交给后端 Agent 判断。

| 输入示例 | Agent 行为 | 回复示例 |
|---------|-----------|---------|
| 帮我创建明天早上8点起床的代办 | 创建 todo 资产 | "好的，已为你创建了明天早上8点的起床提醒 ✅" |
| 昨天早上吃麦当劳花了15块 | 创建 expense 资产 | "记录完成，昨天的麦当劳消费 ¥15 已入账 💰" |
| 今天我有几个代办 | 查询 todo | "今天你有 3 个待办：……" |
| 为什么要记录闪念 | 闲聊 / 反思 | 正常对话回复，不创建资产 |

---

## 三、后端架构要求

### 统一入口

Flash Session 的所有输入通过 **统一对话接口** 处理，后端 root_agent 负责路由：

```
用户输入
    ↓
root_agent（意图识别 + 路由）
    ├── 捕获意图 → flash_note agent → 创建资产 → 返回自然语言摘要 + cards
    └── 查询意图 → query_agent → 查询数据 → 返回自然语言答案
```

### 关键约束

1. **root_agent 不得输出路由通知**  
   错误示例：`"用户想查看待办事项，已转给查询助手"`  
   正确做法：静默路由，由子 Agent 直接返回最终回复

2. **资产归属 session**  
   Flash Session 内触发的资产创建，`session_id` 必须绑定当前的 `daily` session（不能落到 `agent_chat` session 里）

3. **每次调用必须有文字回复**  
   无论是创建资产还是查询，最终响应的 `answer` / `summary` 字段不能为空

### 接口调用

前端调用 `POST /api/query`，传入：
```json
{
  "question": "<用户输入原文>",
  "session_id": "<当前 daily session 的 UUID>"
}
```

`session_id` 传入后，后端在调用 flash_note agent 创建资产时，将此 ID 注入 `session_id` 参数，确保资产归属正确的 daily session。

---

## 四、时间流展示规则（StreamPage）

### 哪些闪念出现在首页时间流

| 来源 | 是否出现在时间流 |
|------|----------------|
| FAB 输入框 / 语音按钮（首次录入） | ✅ 显示 |
| FlashSessionPage 内的追问输入框 | ❌ 不显示 |

**实现方式**：

- FlashSessionPage 的 `send()` 调用 `POST /api/flash` 时，始终在 body 中传入 `"is_followup": true`
- 后端 `flash.py` 将 `is_followup: true` 存入 flash 资产的 `payload`
- `StreamPage.tsx` 的 `buildTimeline()` 过滤掉 `payload.is_followup === true` 的 flash 资产

> **设计理由**：时间流展示用户主动的"闪念录入"动作，而 session 内的追问属于对话的延伸，不是独立的信息录入点。大量追问出现在时间流会增加噪音，干扰核心信息的回顾。

---

## 五、前端实现规范

### FlashSessionPage 对话流

1. 用户发送 → 立即显示用户气泡 + "处理中…" Agent 气泡
2. 后端返回 → 替换 "处理中…" 为真实回复（文字 + 可选 cards）
3. 自动滚到底部

### 历史重建

页面打开时，从 DB 加载当日 daily session 的资产，重建对话历史：
- 每个 `flash` 类型资产 → **用户气泡**（`payload.content`）
- 配套的 `agent_summary` + 派生资产 → **Agent 气泡**

### 不做的事

- ❌ 不在前端判断输入类型（无 `?` 路由逻辑）
- ❌ 不展示 TurnCard / 翻页导航
- ❌ 不单独维护 Q&A 气泡区域

---

## 五、待解决的设计问题

- [ ] 语音输入（🎙）进入 Flash Session 后，transcript 如何在对话中展示？
- [ ] 多个资产同时创建时（如一句话含待办 + 记账），cards 如何排列？
- [ ] Flash Session 内创建的资产，是否要支持点击卡片进入详情？
