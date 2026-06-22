# §8 领域（Domain）系统

> **横切章 · Layer A 已实现（2026-06）· Layer B（§8.4 日环/岛）待 §7。** `domain` = 8 个固定「生活领域」标签,横跨**数据 / agent / 展示 / 游戏化任务 / 总结查询**五层。
>
> **实现分两层:** **Layer A =「标注 + 展示 + 读」(自包含,已落地)** —— `backend/core/domains.py`(8 域常量 + `normalize_domain` + `prior_for_skill`)、迁移 `0009_domain`
> (`assets.domain` / `user_skills.domain` / `global_skills.domain` + `idx_assets_domain`)、create 工具 `domain` 参 + 服务端回落(域→技能 prior→基线 prior→「生活」兜底,**永不 null**,§8.2)、`/api/assets?domain=` 与 `tool_query_*` 的 domain 过滤、
> Flutter `theme/domains.dart`(`DomainChip` + 8 色/图标)、卡片/详情 chip、详情与新建表单的 domain 选择器、report-dispatcher 抽 `domain?` + pipeline 按域过滤 + report-intake 技能/领域消歧。
> **Layer B =「§8.4 每日任务日环 / 岛领域区 / completion_events」**,强依赖 §7 游戏化基建(daily_plans/completion_events/islands 都还没建),**随 §7 一起做**。
> **自定义技能不打 skill 级 domain(产品决策,非后置):** design agent 不参与领域判定、AddSkillWizard 无域选择器 —— 自定义技能每条记录**只按内容**识别 domain(create 工具 `domain` 参);仅基线技能(记账/随记/名片)带固定 prior。**agent 没给也不会 null** —— 服务端「生活」兜底(每条 asset 永不 null,§8.2)。
> **report 资产选择器「按领域」筛选面 = 已实现**(`report_asset_picker_page.dart`:类型 tab 下多一条领域 chip 条 + 行内 domain chip)。
>
> 因为它是 spec 里少数真正跨章的抽象、且属较新较重的改动,**本章作为 domain 的唯一真相收口**;
> 其余章节（§1 / §2 / §3 / §4 / §6 / §7）只保留各自的落点与指回本章的指针(索引见 [§8.6](#86-各章落点索引收口))。
> 取代早期的 **behavior（动作）轴**(更直观、更适合「生活之岛」的晒法,§7.4)。

---

## 8.0 是什么 / 为什么单列

- **8 个有界生活领域** ∈ `{工作, 学习, 健康, 运动, 社交, 娱乐, 生活, 灵感}`(列可空,但**每条新 asset 必落其一、永不 null** —— §8.2;`null` 仅历史遗留)。
- **一个横切标签,让「无限」收敛到「有界」**:用户自定义技能可无限,但
  - 岛只画 **8 个区**(美术成本有界,§7.4);
  - 总结/查询只多 **8 个过滤面**(维度有界,§8.5)。
- **「灵感」= 随记 / 突发灵感的家**,接 [§6 合成引擎](06-synthesis-report.md)升华。
- **关键:domain 按「内容 / 主题」打,不按「动作」固定挂技能。** 同一个「待办」,"交报告"=工作、"买菜"=生活。

---

## 8.1 真相链：domain 存在哪

| 落点 | 列 / 字段 | 角色 |
|---|---|---|
| `user_skills.domain`（[§2 §3.2](02-data-model.md)） | String(20) nullable | **默认 prior**(只作种子,**不是固定值**)。**仅基线技能**有稳定值(记账→生活、随记→灵感、名片→社交,`core.domains.SKILL_DOMAIN_PRIOR`);**用户自定义技能 prior 恒 null** —— 不在建技能时打 domain,完全靠每条记录按内容识别(产品决策 2026-06)。 |
| `assets.domain`（[§2 §3.6](02-data-model.md)） | String(20)（列可空，**新写入永不 null**） | **每条记录的唯一真相**。创建时 agent 按内容打、服务端「生活」兜底(§8.2)、manual 可改。 |
| `daily_plans` 任务项的 `domain`（[§7](07-gamemode.md) / §8.4） | 8 选 1 | 任务的领域(daily-gen 按内容 + 技能 prior 打)。 |
| `completion_events.domain`（[§2 §3.17](02-data-model.md)） | 8 选 1 | **继承**:`source=task` 取任务 domain;`source=record` 取该 `assets.domain`;`source=opportunistic` 取 `assets.domain` 或固定值(contact=社交)。 |
| `weekly_islands.snapshot`（[§7.9](07-gamemode.md)） | `domain → {count, tier 分布}` | 岛的领域聚合(周快照)。 |

**真相链:** `skill.domain(prior / 默认) → asset.domain & task.domain(按内容定稿,可被用户改) → completion_event.domain(继承)`。

**不存 domain 列的两类:** `contact` 恒「社交」(定义即社交,机会型创建直接以社交记一次);`event` v1 **不存**列(其领域由引用它的 daily 任务按内容带,§8.4)。

---

## 8.2 怎么赋值

> **✅ 每条 asset 永不留空 domain(产品决策 2026-06,改了)。** `create_asset` 服务端按链解析、**最后一定落到一个域**:
> **① `domain`(agent 按内容)→ ② `user_skills.domain`(技能 prior)→ ③ `prior_for_skill`(基线 prior:记账→生活 / 随记→灵感 / 名片→社交)→ ④ 「生活」兜底**(`mcp_server/tools.py`,`normalize_domain(domain) or normalize_domain(user_skill.domain) or prior_for_skill(name) or "生活"`)。
> agent 提示三处(chat `assistant.py`、flash dispatcher `SKILL.md`、MCP 工具 docstring `server.py`)都已改成 **「每条都打 / REQUIRED / 拿不准落生活 / 绝不留空」**(原「模糊则省略」已废)。
> 效果:**流 / 月的领域 tag 全程一致**,不再有「无领域」卡片。**例外**:`qa` / `task` 无 asset、不打;`event` 无 domain 列(§8.1);`contact` 恒社交。**历史(决策前)数据**的 `assets.domain` 仍可能 null。

- **agent 自动(主路径)**:落 asset 时按**内容**判定 domain(技能 `domain` prior 作默认;`contact` 固定社交;`随记` 默认灵感)→ 写 `assets.domain`。create 工具有 **`domain` 参**(省略则服务端按上面链回落,**永不 null**)。**两条实现路径(✅ 已实现)**:
  - **chat(`assistant.py`)**:agent 每次 create 直接带 `domain=`(prompt §「领域」)。
  - **flash(`flash_pipeline.py`)**:**dispatcher 在 intent 上多产一个 `domain`**(按内容,8 选 1,SKILL.md「领域」节);pipeline 在 sub-skill 建好 asset 后用 `_apply_domain()` 把该 domain **覆盖**到 `assets.domain`(覆盖技能 prior)。即闪念路径的 domain 由 dispatcher 统一判、pipeline 落,而非每个 sub-skill 各判 —— 更稳、绕开 sub-skill tool-call 抖动。详见 [§1](01-agent-architecture.md) / [§7.10](07-gamemode.md)。
- **manual 表单选择器**:asset-backed 的新建 / 编辑表单带 domain 选择器(8 选 1,预填 agent 猜测或技能 prior,可清空),见 [§4.4.3a](04-frontend.md)。
  **已实现**:新建表单 `create_asset.dart._domainSelector`(默认「按技能默认」)、详情 `asset_detail_sheet.dart._pickDomain`(chip 可点改 / 清除 → `PUT /api/assets/{id}`)。
- **prior 的来源(产品决策 2026-06,改了)**:**只有基线技能**(记账/随记/名片)在代码里带固定 prior(`core.domains.SKILL_DOMAIN_PRIOR`)。
  **用户自定义技能不打 skill 级 domain** —— design agent 不参与领域判定、AddSkillWizard 无域选择器;自定义技能的每条记录**完全靠 agent 按内容识别**(create 工具的 `domain` 参)。注:这是说 **skill 级 prior 仍可 null**;但**每条 asset 的实际 domain 永不 null**(agent 没给 → 服务端「生活」兜底,见本节顶部)。
  理由:domain 本就「按内容/主题」打(§8.0),给自定义技能钉死一个 skill 级领域既易错又多余。
- **agent / 服务端创建永不 null**(「生活」兜底,§8.2 顶)。`null` 仅来自两处:① **历史(2026-06 决策前)遗留**;② 用户在详情**手动清空**领域([§4.4.3a](04-frontend.md))。`null` = 不归域、不长岛、卡片不显 chip。

---

## 8.3 展示（让 domain 在 UI 露出来）

> 既然每条记录都带了 domain,就该看得见。这是一个轻量、贯穿列表/详情的视觉增量。

- **卡片 domain chip**:`SkillCard` / 事件卡 / timeline 条目的 meta 区,一个**小色点 + 2 字领域名**(空间紧时退化为纯色点)。`domain==null` → **不显示**(不占位)。**(2026-06 颜色收敛:这颗域点 = 卡片唯一的颜色 —— 卡片 / 库容器本体单色 + emoji,per-skill `accent_color` 已退役,见 [§5.1](05-design-system.md)。)**
- **详情 chip**:`AssetDetailDrawer` 的 hero 副标题旁一个 domain chip,**可点 → 进编辑改**领域。
- **8 领域 · 起始配色 + 图标**(复用 [§5](05-design-system.md) 的 8 个 accent 槽;**终版图标走单独 design doc**,emoji 仅占位):

  | 领域 | accent 槽 | 占位图标 |
  |---|---|---|
  | 工作 | blue | 💼 |
  | 学习 | purple | 📚 |
  | 健康 | green | 🩺 |
  | 运动 | cyan | 🏃 |
  | 社交 | amber | 🤝 |
  | 娱乐 | red | 🎮 |
  | 生活 | neutral | 🏠 |
  | 灵感 | gray | 💡 |

- **按领域浏览(后置)**:资产库 /「最近」可加一条 **domain 过滤条**(8 chip),或在「我的岛」按领域聚合看。**v1 至少把 chip 显示出来**;过滤条 P2。
- **视觉权重**:副标题级,不抢主字段焦点;复用 §5 chip / 单选样式。

---

## 8.4 domain → 每日任务派生（任务体系：从 per-skill 预算 → per-domain 日环）

> 重写任务**配额与计数口径**。§7.3 仍管 daily-gen **如何生成具体任务**(基底 + 触发、`completion_predicate`);**配额 / 计数以本节为准**(旧 §7.3.1 的 per-skill 7/3/1 **折叠进**此模型)。

- **每个活跃 domain 一个「日环」,容量 ≤2**:daily-gen 每天为每个**活跃领域**(用户有技能 / 近期活动的领域,不是全 8 个)派生**至多 2 条** grounded 任务。
- **完成 = 领域分桶,机会型也计**:某领域的日环由**任意一次该领域的合格活动**填充,每次发一条 `completion_event`(`source` 三态,§7.9)——
  - ① 完成一条派生任务(`source=task`),**或**
  - ② 直接录入一条该领域的**结构化记录**(记账 / 跑步 / 读书 / 自定义习惯 / 勾 todo / 事件赴约,`source=record`),**或**
  - ③ 机会型一级实体创建(contact / external,`source=opportunistic`)。

  > **例**:完成 1 个生活类代办 + 录入 1 笔生活类记账 = 填满生活日环 2 格 = 当天生活领域 **+2**(岛 +2 个生活元素)。
- **日上限 = 反刷阀**:**每领域 ≤2/天**计入岛 —— 录 100 笔记账 ≠ 100 元素,**封顶 2**。这取代旧 per-skill 预算成为节流器,也是「贫瘠↔丰满」诚实信号的守门(§7.4)。
- **随记 / 灵感例外**:**裸随记不计**(守住「闪念不都长岛」,§7.1)—— 灵感日环**只由「升华一篇」任务**填(攒够 N 条 → synthesis,接 [§6](06-synthesis-report.md))。
- **机会型一级实体**:`contact`(社交)/ `external_ref`(按内容)**创建即计一次**(§7.3.2),同样吃 2/天上限。
- **高难 = domain 级周任务**:每周为活跃领域抽象**一条高难「领域级」任务** = 把本周该领域的记录**升华成一篇**([§6](06-synthesis-report.md) 报告 artifact)+ 岛上栽一个**稀有地标**(§7.4)。**一领域 / 周 ≤1 条高难**。
- **岛增长**:日环每填 1 格 → 该领域 **+1 元素**(§7.4 合并 / 升级照旧);周高难完成 → **稀有地标**。
- **「活跃领域」判定**:有该领域技能 prior,或近 N 天有该领域记录。daily-gen 只为活跃领域派生,避免给 8 个领域都塞任务。具体 N、每领域 2 是否随重要领域上浮 = **调参,后定**。

---

## 8.5 domain 维度的总结与查询

有了 domain,读侧多了一层维度。核心取舍:**重聚合进「总结能力」,轻查询留 chat,捕捉永不掺和。**

### 8.5.1 多一层「按领域」的读

用户会说「帮我总结一下最近**所有娱乐**事项」「看看我最近**工作**的整体情况」。落点分轻重:

- **轻量事实查询**(计数 / 列表,如「我这月娱乐花了多少」):`tool_query_asset` / `tool_query_digest` 加一个 `domain` 过滤参(§1 / §3);**chat QA 直接短答**。`GET /api/assets?domain=` 已支持(§3.4)。
- **重的总结 / 趋势 / 升华**:走**总结能力**([§6 合成引擎](06-synthesis-report.md))——
  - `report-dispatcher` 的抽取多产一个 `domain?`(§6.2 的 `{genre, time_range?, asset_types?, domain?, source_asset_ids?, brief}`);
  - 资产选择器加一个**「按领域」筛选面**(与现有类型 tab 并列,§6.8)。

### 8.5.2 命名冲突消解（技能名 vs 领域名）

**冲突**:用户有个技能叫「工作记录」,全局 domain 又叫「工作」。"总结我最近**工作**的情况" 指哪个?

- **消解规则**(写进 `report-intake` / `report-dispatcher` 的 SKILL.md):一个词若**同时**命中「某技能 `machine_name`/`display_name`」**和**「某 domain」→ **不猜,澄清一句**:

  > 「你是指『工作记录』这个技能(只这一类记录),还是『工作』这个**生活领域**(涵盖所有工作相关:工作记录 + 相关待办 + 相关事件…)?」

- **默认倾向**:无修饰的领域词(工作 / 娱乐 / 健康…)**优先解读为 domain**(更贴合「整体情况」的语感);带技能限定语(「我的**工作记录**」「那个记录技能」)解读为技能。**最终仍以澄清为准**。
- 这正是把这层读放进总结能力的理由 → §8.5.3。

### 8.5.3 边界：这层读放在「总结能力」，不进 chat / flash

- **flash** = 捕捉,fire-and-forget,**绝不**做聚合 / 澄清(那会破坏「录了就走」)。
- **chat** = 短问答 + 单条 CRUD;遇到「总结一个领域 / 复盘趋势」→ 走既有 **REPORT-REDIRECT**(§1):一句指路「去『报告』点 ✨总结」。chat 只保留**轻量 domain 过滤的事实查询**(短答)。
- **report**(§6)= 唯一有**引导对话 + 澄清 + 选资产**的地方 → 天然容得下「按领域选 + 技能/领域消歧」。把这层 CRUD 收在这里,**边界自洽**:重聚合都进向导,chat / flash 不长出聚合面。

> 一句话:**按领域「总结」= 报告能力;按领域「查一下」= chat 轻查询;捕捉永远不掺和。**

---

## 8.6 各章落点索引（收口）

| 章 | domain 落点 | 真相 |
|---|---|---|
| §1 agent | process sub-skill 创建时打 domain · daily-gen 任务 domain · design agent 产 prior · `tool_query_*` 加 `domain` 参 | 本章 §8.2 / §8.4 / §8.5 |
| §2 数据 | `user_skills.domain`(§3.2) · `assets.domain`+索引(§3.6) · `completion_events.domain`(§3.17) | 语义见本章 §8.1 |
| §3 API | `/api/assets` 的 `domain` 参 + 序列化 · `/api/daily-plan`·`/api/island` 的 domain · `report-dispatcher` 抽取 | 本章 §8.3 / §8.5 |
| §4 前端 | 表单 domain 选择器(§4.4.3a) · 卡片 / 详情 domain chip(本章 §8.3) | 本章 §8.3 |
| §6 报告 | dispatcher 抽 `domain?` · 选择器按领域筛选 · 技能/领域消歧 | 本章 §8.5 |
| §7 任务&周岛 | 任务日环 / 岛领域区 / completion_events(计数口径见 §8.4) · §7.7 → 本章 | 本章 §8.4 |
| §9 宠物 | 只读消费 completion_events(domain 随货币带入掉落/里程碑) | 本章 §8.1 |

---

## 8.7 v1 范围与后置

- **Layer A 已实现(2026-06):** `assets.domain` 列(+ 基线技能 prior + `idx_assets_domain`,迁移 0009)、agent 自动打域(create 工具 `domain` 参 + 服务端回落)、
  新建/详情表单 domain 选择器、**卡片 + 详情 domain chip 展示**、`/api/assets?domain=` + `tool_query_asset/digest` domain 过滤、chat 轻量 domain 查询、
  report-dispatcher 抽 `domain?` + pipeline 按域过滤 + intake 技能/领域消歧、**report 资产选择器「按领域」筛选面**(`report_asset_picker_page.dart`)。
  实测:agent 按内容打域(待办「交季度汇报邮件」→工作)、`?domain=工作` 过滤、chat「娱乐花了多少」→ domain 查询,均通过。
- **自定义技能不打 skill 级 domain(产品决策,非后置):** 仅基线技能(记账/随记/名片)带固定 prior;自定义技能每条记录只按内容识别。design agent / AddSkillWizard 不涉域。
- **Layer B 待 §7:** daily「日环」计数口径(§8.4)、岛领域区、`completion_events.domain` —— 依赖 §7 游戏化基建,随其一起做。
- **更后置:** 按 domain 浏览过滤条(资产库 / 最近)、domain 配色 / 图标终版(design doc)、月 / 年领域回看、「领域广度」里程碑细化、每领域日环容量随重要领域上浮的调参。
