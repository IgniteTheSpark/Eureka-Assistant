# 10 · 游戏配置与 Live-Ops（Game Config）

> **横切章 · 服务 [§7 任务&周岛](07-gamemode.md) + [§9 宠物](09-pet.md)。** 状态：**Stage 1 设计中（建议先做）· Stage 2 设计中（按需后置）**。
> 解决一个具体问题：宠物 v1 把**装饰目录 / 掉落池 / 里程碑阈值**都硬编在 `backend/core/pet.py`（`SKINS/EMBLEMS/.../DROP_POOL`、`_DROP_CHANCE=0.55`），
> 岛系统还没建。本章定义一层**游戏配置**，把「能当数据的部分」从代码里收敛出来，让我们能 **update / 配置 inventory、里程碑、掉率、岛经济**，
> 并为未来的 live-ops（季节掉落、平衡调参、上下架）留出后台路径。

---

## 10.0 核心原则：代码拥有「画法」，配置拥有「元数据 + 经济 + 上下架」

**不是所有东西都能变成配置。** 装饰和岛元素**与渲染引擎强耦合**：每个装饰键（`mascot.js`）/ 岛元素（`worldgen`）只因为引擎里有它的 **sprite 画法**才渲染得出来——
后台改一行 DB **变不出一个新 sprite**。所以「后台」的真实边界是：

| 谁拥有 | 内容 | 在哪 |
|---|---|---|
| **代码（引擎）** | 每个键的 **sprite 画法**（`assets/js/mascot.js` · 未来 worldgen）；**指标计算**（`completion.py` 读 `completion_events` 算 接住数/连续天/领域数）；可用的 **槽位类型 / 指标类型**（schema 本身） | 仓库代码 + 美术 |
| **配置（数据）** | 装饰目录**元数据**、掉落池**权重**、**里程碑目录**、岛**经济参数**、全局**调参旋钮**、**上下架 / 季节 / premium** 标记 | 本章 config |

**缝 = 稳定字符串键**：config 用键引用代码里已存在的 sprite / 指标；一个**校验器**在 build/启动时强制二者同步（config 引用了没有 sprite 的键 → fail；引用了引擎不会算的指标 → fail）。这条铁律保证「配置自由」不会变成「线上裂图」。

**装饰的「可配置度」分两档（关键细分）：**
- **参数化槽（`skin` 体色 / `emblem_color` 徽色 / `aura` 光环）= 一个颜色值** → **完全可在后台新增/改**：加一条 `{id, name, color}` 即多一个体色/光环，引擎按值上色、**无需新 sprite**。屏二「身色」整列（极光/葡萄/珊瑚/蜜金…）+「光环」(金辉/青辉/虹彩…)就属此档。
- **形状槽（`emblem` 徽记 / `head` 头部 / `item` 双手 / `carrier` 承载）= 一段画法** → 后台能改**元数据/上下架/掉率/稀有度/由哪个里程碑解锁**，但**新增一个形状（如新「探险帽」「云朵」）仍需工程 + 美术加 sprite**。屏一里程碑奖的「探险帽 / 皇冠」就属此档。

换句话说：**规则（里程碑阈值 + 奖什么）100% 可后台改；颜色类装饰可后台新增；形状类装饰可后台运营但新增要美术。**

---

## 10.1 进 config 的五样东西

1. **装饰目录（cosmetic catalog）** —— 在代码键宇宙之上的元数据。每键：
   `{id, slot(skin|emblem|emblem_color|head|item|carrier|aura), name(中文), rarity(normal|rare|epic|legendary), drop_weight, premium(0/1), enabled(0/1), season?}`。
   （v2 已落地的 `RARITY`〔每键稀有度〕+ `TIERS`〔四级颜色〕在 `core/pet.py`，Flutter `pet_cosmetics.dart` 镜像 → 应与目录合并到一处真相。）
   （`id` 必须在引擎键空间内；`name/色板` 现在散在 Flutter `pet_cosmetics.dart`，应与目录合并到一处真相。）
2. **掉落池（drop pool）** —— `{chance(现 0.55), pool:[cosmetic_id…] 或按 slot/rarity 加权, per_tier 修正(简单/中等/高难掉率不同), 全解锁后行为, pity 规则?}`。
3. **里程碑目录（milestones）** —— **最干净、最该后台化的配置项**。每条：
   `{key, metric(capture_count|streak_days|domain_breadth|domain_count:<domain>|domain_total:<domain>), threshold, label, reward_cosmetic_id, repeatable?}`。
   指标由引擎算，目录只定义「哪条指标到几算达成、给什么奖」。
   **现状（v2）**：门控规则 **已在服务端** `core/pet.py` `LOCK_RULES`（累计 100→皇冠、连续 14→泡泡糖身色、点亮 8 领域→蜜金身色+光环座、集齐 8 身色→虹彩光环），`check_unlocks` 在每次 completion 后判定即时发奖；客户端里程碑卡（`pet_page.dart`）镜像这 4 条做进度展示。**仍应上移到 config**（现是代码常量）→ 才能后台改阈值/换奖励/增删条目而不发版。
4. **岛经济（island，[§7](07-gamemode.md)，待建即按此建）** —— `{domain→element_family 映射, 升级阈值(小→中→大 各需几个), tier→landmark 映射, 满载视觉占比}`。
5. **全局调参旋钮（tuning knobs）** —— 收口所有「后定」数值：`per_domain_daily_cap(现 2)`、`active_domain_window`、daily-gen 触发阈值（攒 10 灵感 / 150 页…，§7.3）、freemium 额度（§7.11）。

> 这些正是散落在 §7/§8/§9 里标了「调参,后定」的全部数值 —— 本章是它们的**单一收口点**。

### 10.1.1 对照那两屏：什么能后台改、改它影响什么

| 屏上的东西 | 归属 | 后台能否 manually update | 备注 |
|---|---|---|---|
| 里程碑「连续 5 天 → 探险帽」的**阈值 5、奖励=探险帽、文案** | 里程碑目录（§10.1.3） | ✅ **完全可改**（改 5→7、换奖励、加/删整条） | 指标 `streak_days` 由引擎算,目录只挂阈值+奖 |
| 「累计 100 条 → 皇冠」「点亮 8 领域 → 蜜金」「连续 14 天 → 泡泡糖」 | 同上 | ✅ 完全可改 | `capture_count` / `domain_breadth` / `streak_days` |
| 进度 `1/5`、`1/100`、进度条 | 引擎算的**实时计数** | ⛔ 不是配置（是用户真实数据） | 后台改阈值后进度分母随之变 |
| 身色「蜜金 / 泡泡糖 / 极光…」的**名字、是否上架、由哪个里程碑解锁、掉率** | 装饰目录 + 掉落池（§10.1.1/2） | ✅ 可改 | 体色是**参数化**(颜色值)→ 甚至可后台**新增**一个体色 |
| 一个**全新形状**装饰（如新「探险帽」造型） | 形状 sprite | ⛔ 需工程 + 美术加 `mascot.js` 画法 | 后台只能运营已有形状,不能凭空造形状 |
| 锁图标 🔒 / 灰显（未解锁态） | 引擎按 `unlocked` 渲染 | ⛔ 表现层,不配置 | 解锁与否由用户进度 + 里程碑目录决定 |

**一句话回答「这些规则不能后台改吗」：能 —— 里程碑规则(阈值/奖励/增删)和体色/徽色这类颜色装饰,后台都能 manually update;只有"画一个新形状"绕不开美术。** 这正是 §10 要建的东西;而屏上这些**目前还在客户端 catalog**(§9.4),所以"现在还改不了" —— 把它们上移到服务端 config（§10.2 Stage 1）+ 加后台（Stage 2）后就能改。

---

## 10.2 分两阶段交付

### Stage 1 —— 仓库内配置 + 校验器（**建议现在做**，本质是集中现有硬编码）

- **一处真相**：把 `core/pet.py` 的目录/掉率、Flutter 的中文名/色板、各处「后定」数值，收敛到**一个服务端权威 config**（建议 in-repo 的 `backend/config/game/*.json|py`，**版本受控、可 code review、schema 校验**）。
- **校验器**：build/启动时跑 `validate_game_config()` —— ① 每个 cosmetic `id` 在引擎键空间内；② 每个 milestone `metric` 是引擎会算的；③ 掉落池只引用 enabled 的键；④ 数值在合法区间。**任一不过 → 启动失败**（防线上裂图 / 引用空键）。
- **加载**：进程启动读入内存（或带 TTL 的热读）；`GET /api/pet`、掉落、里程碑都从它派生，**不再读散落常量**。
- 产出：从此**改平衡 = 改一个 config + 小 PR**，不动引擎代码;数据/经济与画法彻底分层。**无 DB、无 admin UI。**

### Stage 2 —— DB 后端 + 受保护 admin API + 极简内部后台（**设计好，按需后置**）

- **触发条件**：出现真实 live-ops 需求（季节掉落、频繁平衡、非工程同学要改、A/B、紧急上下架）才建。**没有这些需求前不建**（避免造没人用的后台）。
- **形态**：`game_config` 表（**版本化行** + 生效时间 + 作者 + 可回滚）覆盖 Stage 1 的文件默认值；`/api/admin/game-config`（见 §10.3）做 CRUD；一个**极简内部 admin 页**（不是给终端用户）。
- 仍受 §10.0 铁律约束：只能在**代码键宇宙 + schema**内编辑 —— admin 能调权重/阈值/上下架/起季节，但**新增一个真装饰仍需工程 + 美术加 sprite**。
- 好处：平衡与季节运营**不发版**;改动有审计、有版本、可回滚。

---

## 10.3 admin API + 安全（Stage 2）

- 端点（全部 **admin-only**，独立于普通用户鉴权）：
  - `GET /api/admin/game-config` —— 读当前生效配置 + 版本。
  - `PUT /api/admin/game-config` —— 提交新版本（先过 `validate_game_config()`，过了才生效，留历史）。
  - `POST /api/admin/game-config/rollback {version}` —— 回滚。
- **安全铁律**：① admin 面**绝不**对终端用户暴露（独立 admin 鉴权 + 角色门控）；② 每次变更**审计**（谁、何时、改了什么、可回滚）；③ 写入必过校验器（不让裂图配置上线）；④ 配置里**不含任何密钥/凭据**（凭据走 [§Connected Apps] 的 write-only 加密通道，与本章无关）。

---

## 10.4 与现状的差距（落地指引）

- **宠物（已实现）**：`core/pet.py` 的 `SKINS/EMBLEMS/EMBLEM_COLORS/HEADS/ITEMS/DROP_POOL` + `_DROP_CHANCE=0.55` + Flutter `pet_cosmetics.dart` 的名/色 → **收敛成 §10.1 的目录 + 掉落池 config**（键空间不变，只把元数据/数值搬进 config + 加校验器）。里程碑从「纯累计展示」→ **目录化**（§10.1.3）。
- **岛（未建）**：直接按 §10.1.4 的 config 建（domain→element、升级阈值、landmark），不要再硬编。
- **校验器是关键交付物**：它让 config 与引擎键空间/指标**强一致**，是 Stage 1 的核心价值，不只是「把常量挪个地方」。

---

## 10.5 v1 范围与后置

> **触发已明确（产品意图 2026-06）**:用户要求「里程碑规则 + 装饰目录能后台 manually update」(对照屏一/屏二)。这就是 Stage 2 的 live-ops 触发条件 → **里程碑目录 + 装饰目录的后台编辑纳入计划**;但有**硬性前置顺序**:必须先 Stage 1（把这些从客户端 catalog 上移到服务端 config），后台才有得可编辑。

- **Stage 1（前置必做）**：游戏 config 单一真相（cosmetics 目录 + 掉落池 + **里程碑目录** + 全局旋钮）+ `validate_game_config()` 校验器 + 宠物现有键空间收敛进来。**重点:屏一/屏二的里程碑阈值-奖励映射、体色目录,从客户端 catalog（§9.4）搬到服务端 config。**
- **Stage 2（紧随，按上面触发做）**：`game_config` 表 + 版本化 + `/api/admin/game-config` + 内部 admin UI + 审计/回滚。**首个 admin 面 = 里程碑目录 + 装饰目录编辑**（改阈值/换奖励/增删里程碑、改名/上下架/掉率/新增体色）。
- **岛配置**：随 [§7](07-gamemode.md) 岛实现时按本章 schema 落。
- **后台改不了的（说清边界）**：新增**形状**装饰 sprite（需工程 + 美术）、引擎指标种类（需加计算）—— admin 只在「代码已提供的键空间 + 指标种类」内编辑。
- **不在本章**：通用应用配置（env / feature flag / `EUREKA_MCP_ENABLED` 等）属运维配置，与游戏内容配置分开管理。
