# Handoff · Reka emote + 对话气泡容器 + 通知持久化 — 给 coding + design

> 三块一起,因为是同一套「Reka 的表达层」:**① emote 表情**(头顶 pop + 通知图标)· **② 统一对话气泡容器**(菜单/peek/chat/nudge 共用)· **③ 通知持久化**(dismiss 后还找得到)。
> **真值**：[§9.2 emote 叠层](09-pet.md) · [§9.2.0 Reka 气泡容器](09-pet.md) · [§14.7 nudge 展示+持久化](14-proactive-reka.md) · [§2 §3.14 notifications](02-data-model.md) · [§9.2 通知收敛](09-pet.md)。
> **资产已 vendor**：`mobile/assets/emotes/`（`pixel-balloon/` 30 白气球 + `pixel-flat/` 30 透明符号 + `KENNEY-LICENSE.txt`，**CC0 商用免费**，credit Kenney 可选）。

---

## A. Reka 情绪 emote 叠层

**球球头顶冒一个 emote 气泡(播一拍淡出)+ 同一套符号当通知/nudge 图标。** 30 符号:idea💡 cash💰 ? ! Z(sleep) ★ ♥ ♪ 笑脸 dots…

**state / event → emote 映射:**

| 触发 | emote |
|---|---|
| idle / 夜里 | `sleep` Z |
| listen（长按/捕捉中） | `dots3` / `music` |
| celebrate / acted / 完成 | `faceHappy` / `stars` / `hearts` / `laugh` |
| Type B 整理灵感（灵感） | `idea` 💡 |
| Type B 记账分析 | `cash` 💰 |
| Type A 节律缺口 | `dots3`（或按域：记账 `cash`、健康 `heart`） |
| 到点提醒（事件/待办） | `exclamation` ❗ |
| flash_done / task_done | `faceHappy` / `stars` |
| task_failed | `drop`（轻，别用哭脸） |

> **gentle-only 铁律**：**永不用** `faceAngry` / `faceSad` / `heartBroken` / `anger`（违背 §14.8「邀请非命令、不愧疚」，Reka 不摆臭脸）。

**验收**：Type B 整理灵感的 nudge 图标 = 💡、记账 = 💰、提醒 = ❗、完成 = 笑脸/星；球球该睡时头顶 Z；任何场景都不出现负面脸。

---

## B. Reka 统一对话气泡容器（§9.2.0）

**Reka 说的话都装进同一种容器 = 带尾巴、尾巴指向球球的对话气泡**（菜单 / peek / 快创 / 洞察结果 / nudge 全用它）。取代旧「纯矩形毛玻璃面板」。

- **形 = Kenney 对话气泡轮廓**（圆角 + 尾巴）。**别拉伸 sprite**：
  - **大 / 多变容器**（菜单、chat、洞察结果）→ **重画成可缩放 shape**（`CustomPainter`：圆角矩形 + 尾巴 path）**或** 9-slice（`Image.centerSlice`，角/尾固定、边中拉伸）。
  - **小瞬时气泡**（peek / emote pop）→ 直接用原像素 sprite 也行。
- **皮色按日夜主题（+ aura）染色**：Kenney 白图用 `BlendMode.srcIn` 可染任意色 —— **深色主题染浅、浅色主题染深 / surface 色**（白气泡**别**原样上浅色主题、会糊）。沿用 v4 aura 染色（跟 `rekaGlow`）。
- **芯**：保留毛玻璃（`backdrop blur`）+ 主题 / aura 半透底。
- **尾巴**：corner-aware，锚在靠近浮球的一角、指向球。
- **里面**：emote 符号（A）作图标。

**验收**：菜单 / peek / chat / nudge 都是带尾气泡、尾巴指球；**深色 + 浅色主题**下气泡对比都清晰（不糊）；菜单和 peek 尺寸不同但都不拉伸变形。

> **分层护栏**：Reka 的气泡可萌，**数据界面（今日页 / 日历 / 库）仍走高级**（§4.5.0 三铁律）。别因像素气泡把整屏拖成卡通玩具感。

---

## C. 通知持久化（修「重进就没了」）

**现状 bug**：`notifications` / `nudges` 服务端**已持久**，但 mobile feed 是**内存单例**、开 app 只 `GET /api/nudges/pending`（仅恢复未处理）→ dismiss 过的、历史的重进就空。

**改：**
1. **feed 开 app 从 `GET /api/notifications` 拉历史**（含已读 / 已 dismiss），不只 pending nudge。
2. **dismiss（知道了）≠ 删除**：只置 `read=1` / `nudges.status=dismissed`，通知行**留 feed**（灰一点），「整理灵感 / 该记账」明天还能翻出来做。
3. **保留窗口 = 14 天**（取代旧「仅留 100 条」）；过窗再 prune。`notifications.type` 加 `nudge`。
4. feed = 「Reka 建议过 + 完成过的事」近 14 天历史；nudge 行点击重开 peek、completion 行点击进对应 asset/session。

**验收**：收到「该记账」nudge → 知道了 → 杀 app 重进 → **feed 里仍能看到它**（灰、可点回）；14 天后才消失；feed 重进不空。

---

## 分工

- **后端（coding）**：`notifications.type` 加 `nudge`（若未加）；**14 天保留窗 prune**（取代 100 条上限）；确认 `GET /api/notifications` 返回历史（含 read）。
- **前端（coding）**：feed 开 app 拉 `/api/notifications` 历史 + 合并内存；dismiss 只置 read 不删；emote 叠层（球头顶 pop + 通知/nudge 图标按映射，`BlendMode.srcIn` 染色）；**气泡容器**（9-slice 或 CustomPainter 重画 + 主题/aura 染色 + 毛玻璃芯 + corner-aware 尾巴）；pubspec 注册 `assets/emotes/`。
- **🎨 design**：7 个气球外形**选 1** + 尾巴/圆角的像素质感；emote↔域 的细映射（rhythm_gap 按域）；各容器（菜单 vs peek vs chat）尺寸/留白；日夜两套气泡染色取值（`/design-review` 精修）。

## 别做
- 不用负面脸 emote（怒/哭/碎心）。
- 不拉伸气泡 sprite（用 9-slice / 重画）。
- 不把白气泡原样上浅色主题（要按主题染色）。
- 不为了像素气泡牺牲数据界面的高级感（分层）。

## 读这些
[§9.2 emote + 通知收敛](09-pet.md) · [§9.2.0 气泡容器](09-pet.md) · [§14.7 nudge 展示 + 持久化](14-proactive-reka.md) · [§14.4 Type A](14-proactive-reka.md) · [§2 §3.14 notifications](02-data-model.md) · [§14.8 护栏](14-proactive-reka.md)。
