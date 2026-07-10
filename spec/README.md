# UReka Spec Library

> **入口文件 / 文档地图。**
> 本目录同时存放长期产品真值、设计 brief、coding handoff、历史原型与实现计划。读文档前先看本页，避免拿过期 handoff 当长期 spec。

---

## 0. 阅读原则

### 0.1 真值优先级

当文档之间冲突时，按以下顺序判断：

1. **当前代码实现**：`mobile/` + `backend/`
2. **分章长期 spec**：`00-14` + `99`
3. **当前 handoff / design brief**：`handoffs/` / `design/`
4. **历史计划 / 原型记录**：`archive/` / old prototype docs
5. **`SPEC.md`**：历史整合快照，只作全文检索参考，**不是当前真值**

### 0.2 文件状态标签

| 状态 | 含义 |
|---|---|
| **Canonical** | 长期真值，应该被持续维护 |
| **Active Brief** | 当前要交给 design/coding agent 的设计或实现卡 |
| **Reference** | 有参考价值，但不是最终真值 |
| **Historical** | 历史快照 / 旧方案 / 已被新文档取代 |
| **Debug-only** | 工程调试或实验文档，不进入产品规范 |

### 0.3 不要再做的事

- 不要把新的需求直接塞进 `SPEC.md`。
- 不要在根层继续堆 handoff、design brief、临时原型 README。
- 不要让同一个主题同时有 3 份“看起来都像真值”的文档。
- 新需求若是长期规则，进 `00-14`；若是给 agent 执行，写 `handoffs/handoff-*`；若是设计方向，写 `design/design-*`。

---

## 1. Canonical · 长期真值章节

这些是 UReka 当前产品和工程的主规格。

| # | 文档 | 状态 | 内容 |
|---|---|---|---|
| 00 | [00-product-overview.md](00-product-overview.md) | Canonical | 产品定义、人群、核心概念、术语 |
| 01 | [01-agent-architecture.md](01-agent-architecture.md) | Canonical | Agent 编排、Flash/Chat/Task、MCP、LLM、prompt 约束 |
| 02 | [02-data-model.md](02-data-model.md) | Canonical | 数据模型、assets、skills、events、notifications、pet 等 |
| 03 | [03-api-reference.md](03-api-reference.md) | Canonical | API 请求/响应、FlashResponse、timeline、reports、pet 等 |
| 04 | [04-frontend.md](04-frontend.md) | Canonical | Flutter 前端架构、主页面、交互、DayRender、今日页等 |
| 05 | [05-design-system.md](05-design-system.md) | Canonical | 现有 design tokens、颜色、字体、组件视觉契约 |
| 06 | [06-synthesis-report.md](06-synthesis-report.md) | Canonical | 报告/合成引擎、report genre、AI imagery、report actions |
| 07 | [07-gamemode.md](07-gamemode.md) | Canonical | 任务 & 周岛，游戏化任务层 |
| 08 | [08-domain-system.md](08-domain-system.md) | Canonical | 8 个生活领域、domain 存储、展示、总结、任务环 |
| 09 | [09-pet.md](09-pet.md) | Canonical | Reka 宠物、换装、掉落、里程碑、浮动球 |
| 10 | [10-game-config.md](10-game-config.md) | Canonical | 游戏配置、Live-Ops、装饰/掉落/里程碑配置边界 |
| 11 | [11-admin.md](11-admin.md) | Canonical | 管理后台 / Live-Ops console |
| 12 | [12-business-model.md](12-business-model.md) | Canonical | 商业模式、token 成本、Free/Pro、用量日志 |
| 13 | [13-baizhi-integration.md](13-baizhi-integration.md) | Canonical | 百智 OAuth、硬件、录音卡 SDK、ASR 集成 |
| 14 | [14-proactive-reka.md](14-proactive-reka.md) | Canonical | 主动 REKA、Type A/B、offer、通知、晨报、节律 |
| 99 | [99-prompts-appendix.md](99-prompts-appendix.md) | Canonical | Prompt / seed / agent 行为附录 |

---

## 2. Active Briefs · 当前可交付给 Agent 的文档

这些文档是当前比较新的设计 / 实现任务卡。它们不替代长期 spec，但可以直接给 design/coding agent。

### 2.1 Design Briefs

| 文档 | 状态 | 用途 |
|---|---|---|
| [design-system-revamp.md](design/design-system-revamp.md) | Active Brief | 下一轮全 app design system revamp 总 brief。先做 Global Shell + Asset Surface System，再做 Today/Calendar/Library |
| [design-habit-streak.md](design/design-habit-streak.md) | Active Brief | 习惯 / streak 系统设计讨论稿 |
| [handoff-today-home-design.md](handoffs/handoff-today-home-design.md) | Active Brief | 今日页作为 app home 的设计 handoff |
| [redesign-home-B.md](design/redesign-home-B.md) | Reference / Hifi Truth | 今日首页 B「潮汐」hifi 视觉/交互真值收录；由 `handoff-today-home-design.md` 引用 |
| [handoff-calendar-design.md](handoffs/handoff-calendar-design.md) | Reference | 日历 / 今日页早期设计 brief；部分已被今日 home 新模型取代 |

### 2.2 Coding Handoffs

| 文档 | 状态 | 用途 |
|---|---|---|
| [handoff-period-time-fix.md](handoffs/handoff-period-time-fix.md) | Active Brief | 模糊时段不造假钟点；todo/custom skill 承接 `period/occurred_at` |
| [handoff-flash-warm-reply.md](handoffs/handoff-flash-warm-reply.md) | Active Brief | Flash Reply Agent：替换「已记录 N 项内容」 |
| [handoff-uiux-design-system-revamp.md](handoffs/handoff-uiux-design-system-revamp.md) | Active Brief | Quiet Warm Minimalism UIUX revamp：tokens、surface、Library tile、Dynamic Edit、Agent/Skill patterns |
| [handoff-reka-emote-notif.md](handoffs/handoff-reka-emote-notif.md) | Active Brief | Reka emote、统一气泡容器、通知持久化 |
| [handoff-reka-companion.md](handoffs/handoff-reka-companion.md) | Reference | 主动 REKA / report→todo / companion 层实现卡 |
| [handoff-report-prompts-v2.md](handoffs/handoff-report-prompts-v2.md) | Reference | 报告 prompt 升级成稿 |
| [handoff-quiz.md](handoffs/handoff-quiz.md) | Reference | quiz / flashcard genre 实现卡 |
| [handoff-onboarding.md](handoffs/handoff-onboarding.md) | Reference | 首次登录孵化 onboarding |
| [handoff-baizhi-oauth.md](handoffs/handoff-baizhi-oauth.md) | Reference | 百智 OAuth 登录接入 |
| [handoff-today-page.md](handoffs/handoff-today-page.md) | Historical / Reference | 日历流/月/DayDetail 时段分组 + 闪念移出流；today-page 部分已被新 home brief 取代 |

---

## 3. Historical / Prototype · 历史与原型资料

这些文件可能仍有参考价值，但不要把它们当最终真值。

| 文档 | 状态 | 说明 |
|---|---|---|
| [SPEC.md](SPEC.md) | Historical | 2026-06-04 整合快照，已显著落后；只作全文检索 |
| [prototype-today-page.md](archive/prototype-today-page.md) | Historical | 用户今日页 hifi 原型 README 逐字保存 |
| [plan-today-page-landing.md](archive/plan-today-page-landing.md) | Historical | 今日页 landing 旧实现计划 |
| [handoff-today-landing.md](handoffs/handoff-today-landing.md) | Historical | 今日页旧 landing 实现 handoff |
| [eurekamind-phase0-embedded-thought-mode.md](archive/eurekamind-phase0-embedded-thought-mode.md) | Historical / External | EurekaMind embedded thought-mode/PA-mode 相关接入方案；不属于 UReka 主 spec |

---

## 4. Subfolders

| 目录 | 状态 | 说明 |
|---|---|---|
| [handoffs/](handoffs/) | Active / Reference / Historical | 所有给 coding/design agent 的执行卡，按 README 状态判断是否当前可用 |
| [design/](design/) | Active / Reference | design system brief、视觉方向、设计真值收录 |
| [design/today-home/](design/today-home/) | Historical / Reference | 今日页 HTML 原型、support.js、方向板；视觉参考，不是长期逻辑真值 |
| [archive/](archive/) | Historical | 旧计划、旧原型、外部历史方案；只作溯源 |
| [chiple-ring-spec/](chiple-ring-spec/) | Reference | Chiple/Ring 相关子规格、计划、状态 |

---

## 5. 按角色阅读

### Product / Founder

优先读：

1. [00-product-overview.md](00-product-overview.md)
2. [design-system-revamp.md](design/design-system-revamp.md)
3. [04-frontend.md](04-frontend.md)
4. [14-proactive-reka.md](14-proactive-reka.md)
5. [12-business-model.md](12-business-model.md)

### Design Agent

优先读：

1. [design-system-revamp.md](design/design-system-revamp.md)
2. [05-design-system.md](05-design-system.md)
3. [04-frontend.md](04-frontend.md)
4. [handoff-today-home-design.md](handoffs/handoff-today-home-design.md)
5. [handoff-reka-emote-notif.md](handoffs/handoff-reka-emote-notif.md)

不要从 `archive/prototype-today-page.md` 或 `design/today-home/` 直接开始设计；那些是参考，不是当前系统 brief。

### Coding Agent

优先读：

1. 任务对应的 `handoff-*`
2. 相关长期 spec 章节
3. 当前代码

近期可执行：

- [handoff-period-time-fix.md](handoffs/handoff-period-time-fix.md)
- [handoff-flash-warm-reply.md](handoffs/handoff-flash-warm-reply.md)
- [handoff-reka-emote-notif.md](handoffs/handoff-reka-emote-notif.md)

### Backend / AI

优先读：

1. [01-agent-architecture.md](01-agent-architecture.md)
2. [02-data-model.md](02-data-model.md)
3. [03-api-reference.md](03-api-reference.md)
4. [99-prompts-appendix.md](99-prompts-appendix.md)
5. [06-synthesis-report.md](06-synthesis-report.md)

### Flutter / Frontend

优先读：

1. [04-frontend.md](04-frontend.md)
2. [05-design-system.md](05-design-system.md)
3. [03-api-reference.md](03-api-reference.md)
4. [08-domain-system.md](08-domain-system.md)
5. [09-pet.md](09-pet.md)

---

## 6. 文档维护规则

### 6.1 新需求放哪里

| 需求类型 | 放置位置 |
|---|---|
| 长期产品/架构规则 | 对应 `00-14` 章节 |
| Agent prompt / seed 变化 | `99-prompts-appendix.md` + 对应章节 |
| 给 coding agent 的执行卡 | `handoffs/handoff-<topic>.md` |
| 给 design agent 的设计 brief | `design/design-<topic>.md` 或 `handoffs/handoff-<topic>-design.md` |
| 用户原型逐字保存 | `archive/prototype-<topic>.md` 或 `design/<topic>/README*.md` |
| 已完成但有历史价值的实现计划 | `archive/`，并在本 README 标为 Historical |

### 6.2 命名规则

```text
00-14-*.md                  长期章节，留在 spec/ 根层
99-prompts-appendix.md      prompt 附录，留在 spec/ 根层
handoffs/handoff-*.md       agent 执行卡
design/design-*.md          设计方向 / design system / conceptual design
design/<topic>/             设计原型包 / HTML bundle
archive/prototype-*.md      用户原型原文保存
archive/plan-*.md           实施计划，完成后归档
```

### 6.3 更新规则

- 写新 handoff 时，必须在本 README 的 Active Briefs 区补一行。
- 一个 handoff 完成后，改成本 README 里的 Reference / Historical。
- 如果新文档取代旧文档，在旧文档顶部加 superseded 指向。
- 不要删除历史文档，除非确认没有引用且用户明确要求清理。
- 物理移动文件时，必须同步修复所有相对链接，并跑一次 markdown link check。

---

## 7. 已完成的整理

当前目录已完成物理分层：

```text
spec/
  00-14, 99, README, SPEC.md     # 长期 spec / 索引 / 历史全文快照
  handoffs/                      # agent 执行卡
  design/                        # 设计 brief / hifi 真值 / 原型包
  archive/                       # 旧计划 / 旧原型 / 外部历史方案
  chiple-ring-spec/              # 硬件子规格
```

已加顶部 historical / superseded 标注：

- `handoffs/handoff-today-landing.md`
- `handoffs/handoff-today-page.md`
- `archive/prototype-today-page.md`
- `archive/plan-today-page-landing.md`

仍可继续精修：

- `handoffs/handoff-calendar-design.md` 中的旧 today-page 部分
- 未来可把 `SPEC.md` 拆成纯归档，或生成一个自动 concat 脚本，避免手工同步。
