# Handoff · 首次登录 onboarding（孵化即引导）

> **状态(2026-06):前端四项 ✅ 已实现并验证**(`pages/pet_spawn_page.dart` 重写 + `main.dart` `_PostAuthGate` 三级 gating + `morning_briefing.py` `thin` 信号)。**唯一未做 = 后端「即时建技能」**(下表第 5 行),按设计优雅降级:onboarding 现为「孵化 + 引导首捕 + 卡片 + 进 app」,等 §1.8 即时建技能就绪再补「我还帮你建了个 XX 本子」那一拍。design 的破壳动画/现身呈现仍可在编码 v1(`_CrackPainter` + celebrate)基础上精修。
>
> 给 **coding agent + design** 的实施范围。**全新用户第一屏 = 孵化,不是晨报。** 孵化即 onboarding —— 在 ~30 秒交付产品 aha:**你随口说一句乱的,REKA 当场替你整理成卡片(连建技能都替你办)。**
> 规则真值见 [§9.2.2](09-pet.md)(onboarding 流程 + 两条孵化改动)· [§9.3](09-pet.md)(`starter_drop` 首孵不揭示)· [§14.6](14-proactive-reka.md)(晨报三级 gating)· [§1.8](01-agent-architecture.md)(design-agent 即时建技能依赖)。
> **改自已实现**:`pet_spawn_page.dart` 现为「轻点即瞬间破壳 + `starter_drop` 揭示弹窗」—— 两点都要改。

---

## 这条弧线（实现目标）

```
全屏蛋 →【点击越点越碎】→ 迸开 → REKA 现身 →(起名/默认 Reka)
  → 「我帮你记着生活里的小事。来,随口说件今天的?」
  → 首次捕捉(语音/打字,任意语言、任意乱)
  →【魔法时刻】REKA 当场结构化成卡片;若不属已有技能 → 自动建技能 + 「我还帮你建了个『XX』本子」
  → 「你记的都在这儿 →」(瞥一眼资产库)→ 进 app
```

## 实施范围

| 面 | 做什么 | 验收 |
|---|---|---|
| **✅ 前端 · 渐进破壳(改瞬间破壳)** | `pet_spawn_page.dart`:点击**不是一下出 REKA**,而是**越点越碎** —— 每次点击给蛋**加裂纹 + 轻微抖动 + 触觉**,蛋逐步崩裂,**最后一下迸开**出 REKA。约 3–5 下(次数/节奏 = design) | ✅ `_CrackPainter` 累积裂纹 + `_shake` 抖动 + `HapticFeedback`(轻×3、末击 heavy);4 下末击才 `spawn()`;进度点提示 |
| **✅ 前端 · 出生不摊组件(改 `starter_drop` 揭示)** | 首孵**不弹** `reka_drop_reveal`「孵化掉落 · 稀有度 · 收下」卡;REKA 现身只呈现一只**完整的、戴帽子+徽记的 REKA**(starter 件静默装好=它的样子)。**`starter_drop` 照发照装备,只是首孵不揭示**;reveal 弹窗保留给后续掉落 | ✅ `_Step.born` 直接现身完整 REKA(celebrate),不再 `showRekaDropReveal`;旧 reveal 步骤/稀有度 chip 已删;后续掉落仍走 reveal |
| **🟡 前端 · 引导首捕 + 魔法时刻** | 孵化后 REKA 邀请首次捕捉(语音/打字)→ 跑捕捉管线 → **当场展示结构化卡片**;命中新类型且自动建了技能 → 显「我还帮你建了个『XX』本子」→ 「你记的都在这儿」瞥资产库 → 进 app | ✅ 打字首捕 → `sendFlash(source:'typed')` → 当场 `SkillCard` → 「你记的都在资产库」→ 进 app。**首捕是普通「记录」不是「闪念」**(打字 ≠ 闪念,后端按 modality 分容器:typed→`manual`「记录」/voice→`flash`「闪念」)。语音=硬件,不在软件 onboarding。🟡「建了 XX 本子」那一拍待后端即时建技能(优雅降级:暂不显) |
| **✅ 前端 · 首屏 gating(改 §14.6)** | 三级优先:① `!spawned` → 孵化 onboarding(不弹晨报);② 已孵化+中午前当天首开+**有内容** → 晨报;③ 已孵化但数据太薄 → **跳过晨报**直接进 app | ✅ `_PostAuthGate` 等宠物加载后 `!spawned`→孵化;`maybeShowMorningBriefing` 加 spawned 守卫 + 后端 `thin` 跳过;验:新用户 thin=true |
| **🟡 后端/agent · 即时建技能** | 捕捉命中**不属已有技能**的内容 → design-agent([§1.8](01-agent-architecture.md))建技能 + 归类。两个杠杆:**B 一键升级**(用户拍板,已做)/ **A 静默自动建**(onboarding 魔法时刻,待做) | ✅ **B**(`POST /api/skills/promote`):随记带 `suggest_skill` → 卡片显「✨ 长期记成『XX』本子?」chip,点一下 design-agent 当场建技能 + 把这条**重抽进新本子** + 删原随记(失败则改挂)。验:`宝宝5点起床6点睡觉`→建「宝宝作息」`wake_time/sleep_start`。⏳ **A** 静默自动建(onboarding 内)待做 |
| **🎨 design** | ① **渐进破壳动画**(裂纹分级、抖动、末击迸裂、点数节奏)② **孵化现身呈现**(REKA 整体、暖、有羁绊感,**不**摊组件)③ onboarding 整体情绪/节奏 | 破壳让人想点;现身让人「这是我的伙伴」;全程短、暖、不像填表 |

---

## 依赖 / 顺序

- **gating + 渐进破壳 + 不摊组件**:纯前端,可先上(不依赖后端)。
- **魔法时刻的"建本子"那一拍**依赖**即时建技能**(后端/agent)。**优雅降级**:依赖未就绪 → 先上「孵化 + 引导首捕 + 卡片 + 进 app」,等即时建技能就绪再补「建了 XX 本子」。**所以 onboarding 不被这条卡死。**

## Out of scope（别做）

- **不让用户"创建技能"**(填技能表单)= 反 onboarding,违背零配置命题 —— 技能由 agent 自动建并**展示**,不是布置作业。
- ~~硬件配对 onboarding(随 §13 录音卡 SDK 落地再做)~~ → **✅ 已加(2026-06,jigong 录音卡 SDK 落地后)**:**孵化/起名后第一件事 = 连卡提示**(`_Step.pairPrompt`),并据此**分叉首捕方式**:
  - **有卡** → [连接录音卡] → `DevicePairingPage` 绑成 → `_Step.hardwareWait`:「按一下录音卡,说件今天的」,靠 `BleFlashManager.isFlashing`(与 ASR 无关,只表示卡录到音频)确认捕捉到 → 「✓ 接住了,整理好在资产库」;整理出卡异步走 ASR,onboarding **不等它**。
  - **没卡 / 没绑成** → [我还没有卡,用打字] → `_Step.invite`:打字首捕 → `sendFlash` → 当场出 `SkillCard`(同步)。
  - 始终给逃生口(连卡可跳过、硬件等待有「先进去看看」),**配对/录音绝不是进门门槛**。
- 多步教程 / 功能巡览墙(就一条首捕 + 一次魔法 + 可选连卡,别堆教程)。

## 读这些

[§9.2.2](09-pet.md)(onboarding 流程,真值)· §9.2/§9.3(孵化 + `starter_drop`)· [§14.6](14-proactive-reka.md)(晨报 gating)· [§1.8](01-agent-architecture.md)(design-agent 建技能)· §1.3/§1.5(捕捉管线)。

## 分工

- **前端(coding agent)**:`pet_spawn_page.dart` 渐进破壳 + 抑制首孵揭示 + 引导首捕 + 魔法时刻 + 首屏三级 gating。
- **后端/agent(coding agent)**:捕捉路径即时建技能 + 回传(若尚未就绪 → 优雅降级,不阻塞)。
- **🎨 design(设计流程)**:破壳动画 + 孵化现身呈现 + onboarding 情绪节奏(`/design-shotgun`→`/design-html`/Flutter 动效规格)。

## 护栏(承全局)

- **零配置**:不让用户配置/学习;agent 替他办、并演示。
- **不摊 plumbing**:出生时 REKA 是**角色**,不是 loadout —— 收集/稀有度/换装等用户自己逛到再发现。
- **短 + 暖 + 不困住**:一条首捕、一次魔法、可滑走。
