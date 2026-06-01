# Workspace — 设计规范

_最后更新：2026-05-21_

---

## 一、核心设计哲学：Skill 即产品功能

系统以 **Skill 为扩展单元**，让产品、Agent、前端三方解耦：

- **定义 Skill**：写 `SKILL.md`，声明触发条件 + payload schema + queryable fields
- **Agent 运行**：用户输入 → Dispatcher 匹配 Skill → 执行 → 输出结构化 Asset + 字段索引
- **后端存储**：`assets` 表统一存储，`asset_fields` 表存可查询字段索引，不感知业务语义
- **前端展示**：新 Skill → 新 `asset_type` → Workspace 新入口 + 新渲染模板

> **新增一个产品功能，只需：定义 SKILL.md → 注册 Dispatcher → 加前端模板。后端不变。**

---

## 二、三张核心数据表

系统有三张独立的核心表，职责不混用：

| 表 | 职责 | 特点 |
|---|---|---|
| `assets` | 所有结构化内容产物 | `user_skill_id` 关联 Skill，`session_id` 关联 Session |
| `asset_fields` | 可查询字段倒排索引 | 三列分型：`value_text` / `value_number` / `value_date` |
| `contacts` | 联系人，独立生命周期 | 固定 schema，不走 asset/skill 体系 |

> **Contact 不是 Asset**：联系人有独立表结构（name / phone / company / title / email / notes[]），其 Skill 逻辑直接操作 `contacts` 表，不产出 Asset，不写 `asset_fields`。

---

## 三、Asset 类型体系

`asset_type` 存在 `payload.asset_type` 中，由对应的 Skill 输出。

### 内置 Asset 类型

| asset_type | 说明 | 图标 | 典型来源 |
|---|---|---|---|
| `todo` | 待办事项，含认领状态和 due_date | ✅ | 对话 / 手动 |
| `idea` | 想法记录 | 💡 | 对话 / 手动 |
| `note` | 笔记或摘要，`note_type` 区分子类型 | 📄 | 对话 / 手动 |
| `misc` | 兜底杂项：闲聊、无法归类、Skill 兜底产出 | 📎 | 对话（兜底）/ 手动 |
| `expense` | 记账，含金额 / 商家 / 类别 / 日期 | 💰 | 对话 / 手动 |

> **`contact` 不在此列**：联系人是独立实体，走独立的 Contact Skill 体系（见§六）。  
> **`flash` 不在此列**：Flash 在架构上是 File（原始录入容器），前端将其隐藏；派生出的结构化内容才是 Asset。

### `note_type` 子类型
`meeting_summary` / `conversation_note` / `manual`

### Todo 认领状态
| status | 含义 |
|---|---|
| `pending_confirmation` | AI 生成，待用户认领（不进主 Todo 列表） |
| `pending` | 用户认领，待完成 |
| `dismissed` | 用户忽略 |
| `done` | 已完成 |

---

## 四、Session 作为唯一溯源锚点

**所有 Asset 都通过 Session 溯源，Session 是唯一的追踪锚点。**

```
用户直接对话（Flash / Ask Agent）
  └── 创建 Session
        ↓ Agent 处理
        输出 Asset（note / todo / expense…）
          └── source: session_id + input_id
```

**不存在 `source_type = "file_analysis"` 的概念**。文件解析场景（上传文件 → 点击解析）也在以该 File 为 context 的 Session 中进行，产出 Asset 的溯源仍然是 Session。

| 溯源字段 | 含义 | 用途 |
|---|---|---|
| `session_id` | 哪个 Session 产出了这条 Asset | 跳转到 Session 页面 |
| `input_id` | Session 内哪一轮用户输入触发了这条 Asset | 在 Session 页内定位到具体对话轮次 |
| `source_type = "manual"` | 用户直接在 App 内创建，无 AI 来源 | 不展示来源 |

---

## 五、Skill 声明规范（payload_schema + queryable_fields）

### 5.1 index_type 枚举

| index_type | 写入列 | 说明 |
|---|---|---|
| `number` | `value_number` (Numeric) | 数值，支持范围查询 |
| `date` | `value_date` (timestamptz) | 日期/时间，支持范围查询。纯 `YYYY-MM-DD` 自动补 `T00:00:00Z` |
| `text` | `value_text` (text) | 字符串，支持模糊匹配 |

> 旧数据中出现的 `"numeric"` / `"enum"` / `"datetime"` 均已对齐为标准三值。后端 `_cast_field` 同时兼容别名。

### 5.2 已注册 Skill 完整定义

#### expense（记账）
```json
payload_schema: {
  "asset_type": "expense",
  "fields": {
    "amount":      { "type": "number",  "required": true },
    "merchant":    { "type": "string" },
    "category":    { "type": "string" },
    "date":        { "type": "date"   },
    "description": { "type": "string" }
  }
}
queryable_fields: [
  { "field": "amount",   "index_type": "number" },
  { "field": "merchant", "index_type": "text"   },
  { "field": "category", "index_type": "text"   },
  { "field": "date",     "index_type": "date"   }
]
```

#### todo（待办）
```json
payload_schema: {
  "asset_type": "todo",
  "fields": {
    "content":  { "type": "string", "required": true },
    "status":   { "type": "string", "enum": ["pending_confirmation","pending","done","dismissed"] },
    "due_date": { "type": "date" }
  }
}
queryable_fields: [
  { "field": "due_date", "index_type": "date" },
  { "field": "status",   "index_type": "text" }
]
```

#### idea（想法）
```json
payload_schema: {
  "asset_type": "idea",
  "fields": {
    "content": { "type": "string", "required": true },
    "date":    { "type": "date" }
  }
}
queryable_fields: [
  { "field": "content", "index_type": "text" },
  { "field": "date",    "index_type": "date" }
]
```

#### note（笔记）
```json
payload_schema: {
  "asset_type": "note",
  "fields": {
    "content":   { "type": "string", "required": true },
    "note_type": { "type": "string", "enum": ["meeting_summary","conversation_note","manual"] },
    "date":      { "type": "date" }
  }
}
queryable_fields: [
  { "field": "content",   "index_type": "text" },
  { "field": "note_type", "index_type": "text" },
  { "field": "date",      "index_type": "date" }
]
```

#### misc（杂项兜底）
```json
payload_schema: {
  "asset_type": "misc",
  "fields": {
    "content": { "type": "string" }
  }
}
queryable_fields: [
  { "field": "content", "index_type": "text" }
]
```

### 5.3 asset_fields 表结构
```
asset_fields
  asset_id     UUID  (FK → assets, CASCADE DELETE)
  user_id      varchar(50)
  field_name   varchar(100)
  value_text   text        -- index_type: text
  value_number numeric     -- index_type: number
  value_date   timestamptz -- index_type: date
```
已建索引：`(user_id, field_name, value_number)` / `value_text` / `value_date`。

### 5.4 写入时机
Agent 通过 Skill 创建 Asset 时，**同时**写两张表：
1. `assets.payload` — 完整 JSON，用于展示
2. `asset_fields` — 按 `queryable_fields` 声明的字段，分型写入

编辑（`PUT /api/assets/{id}`）时，清空旧 `asset_fields` 行后重建（见§七）。

**MCP 查询走 `asset_fields` 表，不解析 payload**，避免 LLM 做 payload 遍历导致的 token 爆炸问题。

---

## 六、Contact Skill（独立体系）

Contact 的 Skill 逻辑**完全独立**，不产出 Asset，不写 `asset_fields`。

```
Contact Skill
  └── 操作对象：contacts 表（固定 schema）
        name / phone / company / title / email / notes[]
  └── 行为：新增联系人 / 更新字段 / 追加 notes
  └── 查询：直接按任意字段查 contacts 表（不走 asset_fields）
  └── 多候选时：返回 pending_confirmation，等用户确认
```

#### Contact 可查询字段（直接查 contacts 表）
| 字段 | 类型 |
|---|---|
| `name` | text |
| `phone` | text |
| `company` | text |
| `title` | text |
| `email` | text |

`user_skills.queryable_fields` 对 contact 仅作 Agent prompt 参考（声明 Agent 可用哪些条件检索），实际查询走 `contacts` 表而非 `asset_fields`。

---

## 七、Workspace 结构

### 页面层级

```
Workspace（一级）
  ├── 系统区（System Sections）
  │     👤 联系人  ›  → 联系人列表
  │     📁 文件    ›  → 文件列表（占位）
  │     ⚡ 闪念    ›  → 闪念列表（按日期分组）
  │
  ├── ── ASSETS 分隔线 ──
  │
  └── 资产区（按 asset_type 分桶）
        ✅ 待办  ›  → todo 列表（pending_confirmation 单独分组）
        💡 想法  ›  → idea 列表
        📄 笔记  ›  → note 列表
        💰 消费  ›  → expense 列表
        📎 杂项  ›  → misc 列表
        [新类型] ›  → 自动出现，通用模板 fallback
```

### Asset 详情页（AssetDetailPage）
每个资产行点击 → push 到 `p-asset-detail`。

#### 编辑双写逻辑
```
PUT /api/assets/{id}  body: { payload_patch: { field: value } }

1. Merge payload_patch into assets.payload → UPDATE assets
2. DELETE FROM asset_fields WHERE asset_id = ?
3. SELECT user_skills.queryable_fields WHERE id = asset.user_skill_id
4. 按 queryable_fields 声明逐字段 re-INSERT asset_fields（分型写入）
```

#### 溯源
详情页顶部显示「⚡ 查看来源 →」按钮（当 `session_id` 存在时），点击跳转 FlashSessionPage。

---

## 八、Skill-to-Feature 完整注册流程

新增一个 Asset 类型功能的完整步骤（Contact 类型除外，走§六）：

```
Step 1 — 后端：写 skills/<name>/SKILL.md
  - 触发条件描述（dispatcher 用于匹配 intent）
  - payload schema 声明（字段名 + 类型 + 是否必填）
  - queryable_fields 声明（字段名 + index_type: number/date/text）

Step 2 — 后端：在 global_skills 表注册新 Skill
         在 user_skills 表写入 payload_schema + queryable_fields
         （可用 scripts/fix_skills.py 模式扩展）

Step 3 — 后端：在 flash-dispatcher/SKILL.md 注册新 intent 类型名

Step 4 — 后端：在 flash_pipeline.py 的 skill_map 中加入路由

Step 5 — 前端：在 WorkspacePage 的 ASSET_META 中加入
         { icon, label, color, bg }

Step 6（可选）— 前端：为该类型写专用二级渲染模板
         默认 fallback 到通用模板
```

**DB 无改动（assets + asset_fields 表结构不变）。**

---

## 九、当前实现状态

| 功能 | 状态 | 说明 |
|---|---|---|
| `assets` + `asset_fields` 表 | ✅ | 含三列分型索引和完整 index |
| `user_skills` 全量 Skill 定义 | ✅ | expense/todo/idea/note/misc/contact 均已注册 |
| `index_type` 统一规范 | ✅ | 仅 number/date/text；`_cast_field` 兼容旧别名 |
| Workspace 一级页（类型分桶） | ✅ | WorkspacePage |
| 系统区：联系人 / 文件 / 闪念 | ✅ | 联系人和闪念有数据；文件占位 |
| 二级列表（单类型） | ✅ | AssetListView / ContactsListView / FlashListView |
| Todo 待认领分组 | ✅ | pending_confirmation 单独区块 |
| Asset 详情页 + 编辑 | ✅ | AssetDetailPage，各类型表单 |
| 编辑双写（payload + asset_fields） | ✅ | PUT /api/assets/{id} |
| Asset 溯源（来源 badge + 跳转 Session） | ✅ | SourceBadge 可点击；详情页「查看来源」按钮 |
| MCP query 走 asset_fields | ✅（后端） | 待全链路验证 |
| 溯源 input_id 定位 | ⏳ | 跳转到 Session 内具体轮次 |
| 二级列表手动创建 | ⏳ | — |
| 二级列表删除 | ⏳ | — |
| SKILL.md 标准化模板 | ⏳ | 现有 skill 文件需按新规范迁移 |
