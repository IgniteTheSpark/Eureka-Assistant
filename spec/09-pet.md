# 09 · 宠物（球球 · Pet）

> 状态：**v1 已实现**（backend `0010_pet` + `/api/pet` + Flutter 球球渲染/孵化/换装;floating-ball + 多只仍后置)。游戏化层（engagement）拆成**两块可独立实现的 spec**，经 `completion_event` 货币**解耦**：
> - **[§7 任务 & 周岛](07-gamemode.md)** = daily-gen → `completion_event` → 周岛（成果物）。**待实现。**
> - **本章 §9 宠物** = 球球（形象 + 换装/背包）+ 奖励经济（掉装饰 + 里程碑），**只读消费** `completion_event`。**已实现。**
>
> 二者互不调用、可各自 ship / 拔。`completion_events` 表 + `emit_completion_event` 已随宠物一起落地(见 [§2 §3.17](02-data-model.md));岛侧只是还没消费它。
> **实现映射:** 渲染引擎 `mobile/assets/js/{pixel,mascot}.js`(基因键空间,**v2 = 7 槽位 + partSprite**);后端基因 `backend/core/pet.py`(含稀有度/解锁规则);经济 `backend/core/completion.py`;接口 `backend/api/pet.py`;Flutter `lib/render/pet_view.dart`(WebView) · `lib/render/sprite_factory.dart`(像素级预览工厂) · `lib/pet/{pet_controller,pet_cosmetics}.dart` · `lib/pages/{pet_spawn_page,pet_page}.dart` · 入口在 REKA 浮球雷达「我的岛」。
>
> **v2(Reka System 重梳,已采用):** 引擎扩到 **7 个外观槽**(加 `carrier` 承载 + `aura` 光环)、加 `partSprite`(单组件离屏渲染);收集系统加 **稀有度**(普通/稀有/史诗/传说)、**孵化保底掉落**、**里程碑门控解锁**(`check_unlocks`);换装格用 **sprite-factory** 出真实 sprite 预览(原 emoji 占位已替换)。
>
> **v4(Reka System 最新,已采用):** ① 短按菜单从径向扇形 → **毛玻璃面板**;② **统一 aura 染色**:菜单/气泡/弹窗都跟 Reka 光环色(引擎 `glowColors` ↔ Flutter `rekaGlow`);③ 我的岛 **真·跨 overlay 飞入相框**(`RekaFly` + 稳定 rect 轮询 + 900ms 兜底,永不卡死);④ 新通知 **脉冲环 + celebrate**;⑤ 时序对齐随包附的 `动画交互文档`(飞入 .62s 回弹等)。
>
> **v3(Reka System,已采用):** 「我的岛」换装板重做 —— ① **解剖式 callouts**:Reka 居中,各装备件在框边浮标签 + 虚线引线 + 锚点(替代下方 chip 行);② **徽记 = 颜色烘焙进件的命名组件**(金星/银十字/霓粉之心/天蓝水滴/赤焰闪电/蓝电闪电/青翠之叶/青环,**取消独立选色 colorbar**);③ **个人库存只展示已拥有**(去掉 locked/🔒 格,不剧透),选中格右上 **✓ 角标**;④ 引擎 +3 光环(炽火/翠绿/霜白)。

---

## 9.0 定位

- 一只代表 agent 的 **球球（mascot）** 陪着用户；记录被它接住、结晶成有类型的资产 = 在 **feed 它**。情感锚 + 奖励出口。
- **气质护栏（同 [§7.0](07-gamemode.md)，贯穿）：默认温柔** —— 无连胜 / 无愧疚 / 无进度条强迫 / 无排行榜；成长**只产外观、绝不锁功能**（核心动作永远可用）；奖励**只增不减、不付费抽、无 FOMO**。竞争元素（排行榜/攀比）依赖多用户社交，**后置**。
- **与岛解耦**：球球**不**读岛、不读任务；只订阅 `completion_event`（输入契约见 §9.1）。

---

## 9.1 输入契约：`completion_event`（来自 [§7](07-gamemode.md)）

- 球球侧消费的**唯一输入** = `completion_event`（中心货币，append-only，由 [§7.1](07-gamemode.md) 产生）。形如 `{id, user_id, domain, tier, source(task|record|opportunistic), ref, ts}`。
- 球球**只读**：每条 `completion_event` → ① 掷一次掉落得装饰（§9.3）；② 推进里程碑计数（§9.3）。**绝不回头解读语义、不写 L0**。
- **解耦保证**：即使 [§7](07-gamemode.md)（岛）未实现，只要有 `completion_event` 流，球球也能独立跑；反之岛也能没有球球独立跑。`completion_event` 是两块 spec 的**唯一缝**。
- 岛侧的 payoff ①（按 domain 长岛）**不在本章**，见 [§7.4](07-gamemode.md)。

---

## 9.2 球球本体（L2）

- **第一期只 1 只**；数据**按"可多只"留位**（后续可拥有多只 + 选一只展示），UI 先显 1。
- **无 EXP / 等级 / 升级**（已弃用）。成长 = **横向收集换装**：**背包（inventory）= 装饰物**，换装改外形。
- **装饰物来源 = ① 任务完成随机掉 + ② 里程碑解锁 + ③ 孵化保底掉**（见 §9.3），每件带**稀有度**(普通/稀有/史诗/传说)。护栏：只增不减、不付费抽、无 FOMO。
  - **里程碑 = 40 条配置驱动(`core/milestones.py` 单一来源)**:每条 = 一个指标越过阈值 → 解锁**指定**装饰。指标:`capture/streak/domains/skins/emblems/heads/items/carriers/auras/total`(全部从 pet 的 `milestones`+`unlocked` JSON 算,无新追踪)。**加法**:35 条的奖品**也在随机掉落池里**(里程碑 = 保底拿到的路径),只有 **5 件 endgame 专属**(gold/bubble 身色 · crown · ring 承载 · rainbow)从掉落池**排除**(只能靠里程碑)。`pet.check_unlocks` 读配置发放;每次完成事件**最多发 4 件**(`_MAX_UNLOCKS_PER_EVENT`,老用户一次达成很多时按涓流发、不刷屏)。
  - **追踪面 = `GET /api/pet/milestones`**(§3):列全部 40 条 + 该用户进度(每条带 `label`/`metric`/`threshold`/`reward_slot`/`reward_key`/`tier`/`exclusive`/`current`/`achieved`/`reward_owned`)+ `summary{achieved,total}`。这是「简单 backend 去 track 所有里程碑」。
  - **前端(✅ `pet_page.dart` + `PetController.milestones`)**:里程碑**收敛进换装页**(`_WardrobePage`)——板上只留一张**成就·里程碑 summary 卡**(🏆 + `N/40` + 进度条,点开 `showWardrobe(tab:_kMilestoneTab)`);换装页 slot tabs 末尾加 **🏆 里程碑 tab** → **5 列 compact grid**:每格**只画奖品 sprite + 进度环**(`SpritePreview`,达成绿环 + ✓ 角标),点格弹 **bottom sheet** 看**任务(`label`)+ 进度 + 奖品名 + 稀有度 + 专属**(详情挪进弹层,grid 极简)。读 `GET /api/pet/milestones`(40 条),数据随 `PetController.refresh()`(连同 `GET /api/pet`)一起拉,完成事件后 `dataRevision` 自动刷新。可编辑的 admin 网页(§10/§11)另议。
- **状态动画**（闲逛 / 听〔长按〕/ 思考〔处理中〕/ 庆祝〔闭环〕/ 夜里睡）**保留为纯表现**，不挂等级。✅ 引擎(`mascot.js`)已支持 idle/listen/celebrate/sleep + 自动眨眼 + 庆祝彩带;v1 详情页用 idle + 轻点庆祝。
- **球球详情(✅ 已实现 `pet_page.dart`)**:hero 渲染 + 改名 + 里程碑三连(接住数/连续天/领域 n/8)+ **换装背包**(按槽位分区,已解锁可选、未解锁灰显带锁、点锁提示"多记录就有机会")。**premium 装饰 = 干净付费面**(只卖外观,后置)。
- **孵化接管(✅ 已实现 `pet_spawn_page.dart`)**:首次进入(`!spawned`)走一次全屏 蛋→轻点唤醒→孵化→起名→自我介绍 流程,完成后替换为详情页。
- **掉落庆祝(✅ 已实现)**:任意写后 `dataRevision` 触发 `pet_controller` 重拉 `GET /api/pet`,与上次快照 diff 出新解锁的装饰 → 顶部 toast「🎁 球球带回了新装饰 · X」+ 通知 +1。**两档揭示**:日常随机掉走**非侵入 toast**(后台静默到货,不打断当前操作);**孵化保底掉**走**揭示弹窗**(用户主动点孵化,期待庆祝时刻 —— 见 §9.3 `reka_drop_reveal.dart`)。`showRekaDropReveal` 也可复用于任意掉落(`showDropRevealGlobal`),v1 仅孵化触发。
- **全局浮动球球(✅ 已实现 `pet/floating_mascot.dart`)**:挂在**根 overlay**(`main.dart`)、浮在**所有页面**最上层(通过 `navigatorKey` 导航);**可随意拖、记忆位置**(`SharedPreferences` 存分数坐标,跨分辨率稳)。**自抑制**:在「它自己就是 REKA」的页面(孵化接管 / 详情)用引用计数 `mascotSuppressed` 隐藏浮动球。

- **手势(✅ 已实现 · 设计稿对齐 · 折中)**:
  - **短按 → 功能菜单(✅ v4 `pet/reka_radial.dart`)**:不再是散开的径向扇形,而是**一块毛玻璃面板**装下全部项,在 Reka 上/下方居中弹出(同气泡定位);**面板 + 项按 Reka 当前 aura 染色**(`rekaGlow` → 毛玻璃底/边框/外发光)。**快创 · 洞察 · 通知(带角标) · 我的岛**(未孵化则 → 孵化接管)。面板 .28s 淡入缩放,项内 28ms 错峰 `scale .55→1`。
    - **任务暂从菜单移除(2026-06)**:等岛屿任务([§7](07-gamemode.md))spec 落地再加回(`_Item('tasks', …)` + `_onPick` 的 'tasks' 分支已留注释待恢复)。
    - **总结 → 洞察(改名,2026-06)**:菜单项「总结」太死板,改为「洞察」(图标换 `auto_awesome_outlined` ✦,呼应升华);内部 key 仍 `summarize`。全链路文案同步(`reka_chat` 气泡 + `report_*` 页)。
    - **标签下划线 = 假象,已修**:面板项 Text 此前**没包 `Material`** → Flutter 给 overlay 里无 Material 祖先的文字渲染**黄色双下划线**(用户看到的「黄色下划线」其实是这个 artifact,非设计)。修法:整个面板 `return Material(type: MaterialType.transparency, child: Stack(...))`,下划线消失。
  - **长按 → 续上次对话**:直接 push `ChatPage`(复用其「resume last conversation」)。**不做独立底部会话面板**(设计稿的 74% session 面板按折中略去)。

- **功能在气泡里解析(✅ `pet/reka_chat.dart`,雷达项 → `RekaChat(intent:…)`)**:
  - **快创(✅,设计稿样式)** = 气泡里 **2 列 tile grid** 列出**全部**类型(事件 + `/api/skills` 每个技能,带**域色 icon chip** + sub〔一笔花销/要做的事…〕),kicker「快创 · 选个类型」→ 点 tile → **居中编辑弹窗**(`EventForm`/`ContactForm`/**`AssetEditPage`(create 模式,与编辑同款,见 [§4.4.3](04-frontend.md))** 经 `showDialog` `barrierDismissible:false` 居中呈现,**非底部 sheet**,存后 `maybePop(result)`)→ **回执气泡**(「记账 · ¥38 · 已闭环 ✓」,REKA celebrate 头像)+ **通知 +1**。`AssetEditPage` CREATE pop 的回执 map(`{user_skill_name, display_name, icon, payload}`)正是 `_onCreated` 要的格式 —— 快创/编辑同一组件、不再各画一套。
  - **洞察·升华(✅,设计稿样式)** = entry 卡:kicker「洞察 · 升华一段」+ **一句话输入行**(无内联按钮)+ **输入框下方的「+ 手动选择资产」context 行**(像 session 关联 context:`+ 手动选择资产` pill + 已选 chips〔可点 × 取消〕)+ **快捷 pills** + **底部全宽「✨ 生成洞察」提交按钮**。生成(`POST /api/reports/generate` SSE,**REKA 状态气泡 celebrate 小动画**)→ **结果气泡**(《标题》 + 「查看报告」CTA → viewer)+ 通知 +1。气泡卡右上角有**关闭 X**(`.bub-close`)。
    - **布局(✅ 改 2026-06,对齐 session 手感)**:**提交按钮从输入框旁移到卡片最下面**(全宽「生成洞察」);**「手动选择资产」从最底部移到输入框正下方**(context 行)。
    - **手动选择 = 对描述的「定向补充」,不是替代查询(✅ 修 2026-06)**:选完资产**回到同一张 entry 卡**,已选展示在 context 行(可点 × 取消;`· 会结合你上面的描述一起洞察` 提示)。用户**可继续敲描述 / 点 pill**,再按底部「生成洞察」**一起提交** —— `_generate(wish, source_asset_ids)` 把**描述(→ dispatcher 定体裁/标题/brief)+ 选中 ids(→ 取数)**一并发后端;空描述+有选 = 按选中的生成。**旧 bug**:一选完就 `_replaceSynth` 成「生成洞察/重选」、把描述丢了 → 只按那几条洞察。已删 `_K.assets`/`_assetsBubble`。
    - **资产选择器统一**:session「关联 context」与洞察「手动选择」**共用同一个 `widgets/asset_picker.dart` 的 `AssetPickerPanel`**(类型 tab + 列表〔emoji+标题+副标题+右侧 check_circle〕+ 底部已选 chips〔可删〕+ 确认条),**只是宿主不同**:session 挂**底部 sheet**、洞察挂**居中弹窗**(传 `confirmVerb/unit/tint/initialSelected/excludeIds`)。删掉了各自的 `_AssetPicker`(chat) / `_AssetPickerModal`(reka),交互/展示一致。
      - **拉全量,不止最近 50**:`fetchAssets(limit:500)` —— 否则记录多时(如 100+ 记账)旧类型(随记/读书/…)会被挤出 fetch、tab 和列表里都看不到。类型 tab 由实际有资产的 skill 动态生成。
      - **可随时关闭**:面板顶部有 ✕(pop null,两个宿主通用);洞察居中弹窗 `barrierDismissible:true`(点 scrim 也关)。修了之前洞察选择器「不选就关不掉」。
    - **单卡状态机,不堆叠(✅ 修 2026-06,`_synthBase` + `_replaceSynth`)**:洞察**不是会增长的聊天流**,而是一张**就地替换内容**的卡:`entry`(输入/pills/手动选择)→ 提交/选资产 → `generating`(「正在撰写《范围》…」,输入行被替换掉、生成期无入口)→ `result`(《标题》+「查看报告」+「再洞察一篇」)/ `insufficient·error`(提示 +「换个范围 / 再试一次」,回 entry 并预填上次 wish)。**「再洞察一篇 / 换个范围」= 唯一的再生成入口**,回到同一张 entry 卡(`_synthBase` 之后整段 `removeRange` 重建)。**根因(旧 bug)**:每次生成都 `_add` 到气泡流尾 → 输入行被不断顶上去看不见、且可无限堆叠生成;改为 replace-in-place 后输入永远可达、一次只有一张卡。
    - **generating 状态气泡布局(✅ 修 2026-06)**:`generating` 用**平静的 `idle` 宠物**(不是 `celebrate` —— 它的粒子会溢出小气泡)+ **三点 typing 动画**(`_TypingDots`,自带 repeat 控制器,正弦错峰)传达「在写」;头像缩到 34、间距/留白对齐,整体更平衡。`receipt`(已闭环 ✓)仍用 `celebrate`。
    - **外部入口汇流(✅ 闭环,修 2026-06)**:全局 `rekaFunctionRequest`(`ValueNotifier<String?>`,`floating_mascot.dart`)+ 便捷 `openRekaInsight()` —— 任意页面(如**报告列表的「✨ 洞察·升华」CTA**)可触发,挂根 overlay 的浮球**就地开同一个 `RekaChat(intent:'summarize')` 气泡**(锚定真·浮球;`_menuOpen`/`suppressed` 守卫)。**不再为洞察单开全屏页**(`ReportCreatePage` 废)——雷达菜单与报告 CTA 共用一条 REKA 流。
  - **通知(✅)** = 气泡**通知面板**(`_K.notifPanel`,列表 icon+标题+meta;打开即全部已读)。
  - **任务** = §7 待实现 → 「即将上线」toast 占位。
  - **进/出我的岛 = 「飞入 / 飞出相框」(✅,对齐设计稿;我的岛现为 dock tab,非 push 路由)**:
    - **飞入(✅ 真·跨 overlay,2026-06 修复)**:进板**不先隐藏浮球** —— 等路由动画结束(雷达推入 `PetPage` 时首帧 rect 带滑入偏移)→ 量 `_petKey`(未变换槽)的真实相框 rect → `RekaFly.flyInto`:**球从当前屏幕位置飞进相框**(620ms 回弹),**落地瞬间**才 `mascotSuppressed++`、hero 原地接管(`_heroCtl.value=1`,不二次滑入)+ celebrate;1.2s 兜底 `arrive(false)` 走 board-owned 降级(`_heroCtl.forward` 从框下升入),永不「球停半路 + 空相框」;快速进出由 dispose 的 `RekaFly.cancel()` 兜住。**历史教训:早期「真机不动画」的根因是顺序反了** —— 先 suppress 再飞,而浮球的飞行分支只在未隐藏时渲染,一帧都画不出;外加路由滑入期测到偏移 rect。修复 = 「先飞 → 落地 → 再藏」+ 等路由结束再测。**路由 pop 也飞出**:`PetPage` 包 `PopScope`,pop 时量 rect → `flyOut`(与 tab 路径对称)。
    - **飞出(overlay-resident 浮球,可靠)**:`AppShell._go` 检测到离开 tab 2 时,**趁 board 仍在布局**同步量出 hero 当前屏上 rect(`PetBoardState.measureHeroRect` 读 `_petKey`;滚出视口/未布局 → null 则跳过飞行,浮球直接回家),经 `RekaFly.flyOut(rect)` 通知**根 overlay 常驻的浮球**:浮球从该 rect **飞回 home 落点**并缩回球尺寸(`_fly` 620ms,`easeInOutCubic`,位置 lerp + scale `heroW/66→1`)。浮球**独立于 tab 生命周期**(IndexedStack 切走会 unmount board,但浮球在根 overlay 不受影响),且**飞出渲染无视 suppressed**(board hero 已 unmount,无双影)→ 退出也**永远有可见过渡**,而非瞬回。落定后 `outFrom=null`,浮球恢复常态。
    - 两端 rect 均在**点击 dock 当帧同步取得**(无 route 过渡,故无早期飞入那种测距时序坑)。
    - **关键:抑制的 notify 必须 post-frame(✅ 已修)**:我的岛是 `IndexedStack` 的 **tab**,故 `PetBoard.initState/dispose` 跑在 **shell 的 build/unmount 帧内**。直接在其中 `mascotSuppressed.value++` / `releaseMascotSuppress()`(及 `_pet.refresh()`)会在 build 中通知浮球的 `ValueListenableBuilder`/`AnimatedBuilder` → 抛 `setState() during build` / `markNeedsBuild when tree was locked`(满屏异常 + 把入场/飞出动画冲垮)。改为 **`addPostFrameCallback` 延后**(initState 里 refresh+suppress+`_heroCtl.forward`;dispose 里 release)→ notify 落在已 settle 的树上,异常消失、两段动画恢复。(浮球早先是 push 路由时这不犯 —— 路由 push 的 build 不在 shell 同一帧。)
  - **精灵 fx 不被裁(✅ v4 #3/#4)**:浮球与 hero 的 PetView 用 `OverflowBox` 放大渲染框(球 132、hero 230×210),让引擎的 **celebrate 彩纸 / listen 光环**溢出到框外(不被 66/156 的 WebView 盒裁掉);视觉本体尺寸不变(canvas 居中),命中区仍 66。相关 Stack 设 `Clip.none`。
  - **浮球抑制的真机坑(✅ 关键修复)**:不能靠「`suppressed>0 → SizedBox`」移除浮球 —— iOS 的 **WKWebView platform view 被移除后会留残影**(浮球明明该隐藏却还在,孵化页/我的岛都见过)。改为**保持浮球挂载、suppressed 时把它定位到屏幕外**(`left:-10000` + `IgnorePointer`),iOS 按位置可靠合成、不留残影,且返回时无重载闪烁。释放统一用 `releaseMascotSuppress()`(clamp 不为负,防计数泄漏)。
  - **气泡定位(✅ 设计稿 positionBubbles)**:REKA 在下半屏 → 气泡**向上展开**(bottom 锚 + bottomLeft/Right 缩放原点);在上半屏 → **向下展开**(top 锚)——避免球在顶部时气泡被挤扁;键盘弹起时浮在键盘上方。气泡卡右上角有**关闭 X**。
  - **统一光晕色(✅ v4)**:REKA 打开的所有表面 —— **菜单面板 / 气泡会话卡 / 资产选择弹窗** —— 都按 Reka 当前 aura 色(`Mascot.glowColors` ↔ Flutter `rekaGlow`)做毛玻璃底 + 边框 + 外发光,换光环时一起跟色。(快创编辑表单是真实 `Scaffold`,保留其自身样式。)
  - **REKA 反馈动效(✅ v4)**:菜单/气泡打开期间浮球 PetView 切 `listen`(头微侧 + 听的环),关闭回 `idle`;**新通知到达**:角标弹出 + **浮球外圈脉冲环扩散 2 次(1s)** + celebrate(`_pulse` + `_ballCelebrate`,仅未读数增加时触发)。
  - **动画时序基准**:v4 `动画交互文档` 是所有动画时长/缓动的单一真相 —— 飞入(board-owned)`.64s easeOutBack`、飞出 `.62s easeInOutCubic`、菜单 `.28s`+28ms 错峰、气泡 .2/.24s、弹窗 .24s、长按 ~480ms、celebrate(快创1900/洞察1700/通知1300/默认1500)。实现按此对齐(`prefers-reduced-motion` 降级后置)。
  - **overlay 层级(✅ 已修,设计稿 doctrine)**:雷达/气泡 = 非模态(轻 scrim、点别处关闭);**居中编辑/资产选择弹窗 = 模态,`barrierDismissible:false` 点 scrim 不关、只 X/取消** —— 期间**气泡卡 + 浮动球都隐藏**(`_modal` 守卫 + `mascotSuppressed++`),关闭后气泡复现(显示回执 / 已选资产)。绝不让 REKA 内容常驻在模态之上。

- **通知收敛到 REKA(`pet/reka_notifications.dart`)**:单一通知 feed(`RekaNotifications` 单例,ChangeNotifier)。喂入:快创回执、掉装饰、报告生成、以及 `AppEvents` 的服务端通知(flash/task done、reminder)。REKA **角标显示未读数**(`floating_mascot` 上 AnimatedBuilder),雷达「通知」项打开面板;**已移除 header `NotificationsBell`**。无独立红点系统。
  - **可点击跳转**:`RekaNote` 带 `type` + `link`(`AppEvents._handle` / 报告生成处透传);通知面板每行 `tappable` → 标已读 + 关菜单 + `openNotificationTarget(type, link)` 路由:`report_done`→拉 `/api/reports/{id}` 开 `ReportViewerPage`;`flash_done`→`SessionDetailPage`;`reminder`(`reminder:evt|todo:<id>:<thr>`)→`CalendarPage`;未知类型 no-op。toast 与面板**共用**这个路由。可点的行带 `chevron_right`。

- **引擎运行时注册(✅)**:`mascot.js` 已加 `Mascot.register(kind,id,def)` + `partKeys(kind)`(后期不改 core 加装饰),与设计稿对齐(整份 `mascot.js` 已与设计稿同步,含 "Reka" 命名)。

- **命名 = 默认 "Reka"、≤8 字(✅)**:backend `api/pet.py` + Flutter 默认改为 Reka;改名/起名 cap 8。

- **孵化「首次捕捉」引导(✅)**:egg→hatch→命名→intro→**首次捕捉**(「记下第一条」引导文案)→ 完成进入。(真实「等第一条 completion 再庆祝」后置;v1 是引导文案 + 进入后由 REKA 接住。)蛋+文案块**垂直居中**(`Center`+`SingleChildScrollView`,键盘弹起可滚不溢出);孵化接管页也由 off-screen 抑制保证**不出现浮球**。

- **闪念不在 REKA 菜单**:正式上线**无软件语音**(语音=硬件录音卡触发);`FlashSheet` 仅留硬件 / dev 路径(`START_OVERLAY=flash`)。软件侧快速捕捉走快创或对话。

---

## 9.2.1 组件库与渲染管线（资产即代码 · 部件即数据）

> 把设计稿「伴生智械 · 部件库」的核心方法论落到 Reka 引擎上：**一只 Reka 不是一张画好的图,而是引擎从各槽位各挑一件「白模部件」、在同一坐标空间里按固定层序叠出来的**。美术只供**灰度白模 + 锚点**,代码做**调色 / 拼装 / 稀有度 / 掉落**(资产即代码)。这让「加一件装饰」= 加一条数据,不改引擎、不出新图。

### 槽位与组装层序（`mascot.js compose()` 单一真相）

7 个外观槽,**后→前**画(后画的盖前画的):

| # | 槽位（engine key） | 说明 | 锚点来源 |
|---|---|---|---|
| 0 | `shadow` | 地面投影（有承载时收窄）| 引擎内置,非装饰 |
| 1 | `carrier` | 承载物 · 坐落在身体**下方**(先画,Reka 底缘压住其上沿)| `CARRIERS[k].{s,ox,oy}` |
| 2 | `head` | 头部件(先于身体画 → 身体顶缘压住头件下沿,自然「戴上」)| `HEADS[k].{s,ox,oy}` |
| 3 | `skin`(+ 五官)| 身体本体 = 身色调色板 + 眼/脸特征 | `buildBody()` + `placeFeatures()` |
| 4 | `emblem`(+ `emblem_color`)| 胸口徽记,**独立顶层**(不烘进身体,保证居中)| `EMBLEMS[k]` + 烘焙色 |
| 5 | `leftItem` / `rightItem` | 手 + 手持物(物相对手锚点偏移 `lx/ly`、`rx/ry`)| `HAND` + `ITEMS[k]` |
| 6 | `aura` | 光环 = canvas 的 **CSS 辉光滤镜**(`glowFilter`/`glowColors`),**不是绘制层** | `auraGlow` 颜色 |

- **徽记的颜色是「烘焙进件」的命名组件**(`kEmblemComponents`:形×色×名×稀有度,一形可多配色)—— 不是「形 + 独立调色条」。换徽记 = 同时设 `emblem`+`emblem_color`(`equipAll`)。
- **光环只在「活体」路径可见**(WebView 的 CSS filter);静态 PNG 预览不含辉光 → Flutter 侧补 `boxShadow`(见下「渲染管线」)。

### 部件注册与扩展（不改 core 加装饰）

- 引擎暴露 `Mascot.register(kind, id, def)` + `Mascot.partKeys(kind)`(`kind ∈ skin|emblem|head|item|carrier`)。**加一件新装饰**的完整步骤:
  1. **白模 + 锚点**:给该 `kind` 加一条 `def`(灰度像素网格 `s` + 偏移 `ox/oy`,或手持的 `lx/ly`/`rx/ry`),`register()` 进表 —— **不动引擎其余代码**。
  2. **稀有度**(独立数据层,见下)给它定级。
  3. **掉落 / 里程碑**:把键加进 `DROP_POOL`(随机掉),或在 `core/milestones.py` 加一条里程碑(指定它为某条件的奖励)。
  4. **Flutter 镜像**:在 `pet_cosmetics.dart` 补名/emoji(+ 徽记还需 `kEmblemComponents` 一条)。
- 整份 `mascot.js` 已与设计稿同步(含 "Reka" 命名 + `register/partKeys`),**后续加件不必碰引擎 core**。

### 稀有度 / 掉落是「独立数据层」,不是部件属性

- **稀有度不挂在白模几何上** —— 它住在单独的表:后端 `core/pet.py RARITY`(真相)↔ Flutter `pet_cosmetics.dart _rarity`(离线 UI 镜像),按 `slot+key` 查。**同一个白模可被重新定级而不改美术**。
- **掉落池**(`DROP_POOL`,排除 freebie 与专属键)、**里程碑配置**(`core/milestones.py`,40 条)同样是覆盖在同一组部件键上的**独立数据层**。平衡性调参(掉率/阈值/奖励映射)= 改数据,不改部件,不改渲染。详见 [§10 游戏配置层](10-game-config.md)。

### 渲染管线（一套引擎,两条 Flutter 路径）

`mobile/assets/js/{mascot.js,pixel.js}` 是**唯一引擎真相**(web `frontend/` 仅参考镜像)。Flutter 用**同一份引擎**走两条路:

1. **活体 `PetView`(WebView)** —— 完整动画 Reka:idle/listen/celebrate/sleep + 自动眨眼 + 庆祝彩纸 + **CSS 光环辉光**。用于 hero、浮动球、孵化页、**掉落揭示弹窗**(`reka_drop_reveal.dart`)。
2. **sprite-factory(`lib/render/sprite_factory.dart`)** —— **单个隐藏 1×1 WebView** 载入同一引擎,`Mascot.sprite()/partSprite()` → `canvas.toDataURL()` → `Image.memory`,**按 opts 缓存**。用于换装背包的几十个静态预览格(避免一屏几十个 WebView)。**代价**:纯 CSS 效果(光环辉光)不烘进 PNG → 光环槽预览在 Flutter 侧补 `boxShadow`。
   - 每槽预览策略:身色/头部/手持/徽记 = 全身 `sprite()`(徽记用 sky 体色凸显);**承载** = `partSprite('carrier')` 单画底座(全身渲染下底座只是细缝);**光环** = 全身 + Flutter `boxShadow`。

**未来选项(后置):** 设计稿提的「**共享 part JSON + Flutter `CustomPainter`**」纯 Dart 渲染 —— 让 Flutter 不依赖 WebView、原生绘制部件。**当前不做**:WebView 引擎是单一真相,美术改动同时流向 web 参考 + mobile 而无需维护一份 Dart 移植;落地 `CustomPainter` 需把部件白模导出为共享 JSON 并保证两套渲染像素一致,作为性能/去 WebView 化的后续路径记录在案。

---

## 9.3 奖励经济：掉装饰 + 里程碑

- **`completion_event` 被消费**：每条 → ② **掷一次随机掉落**得装饰（`roll_drop`,~55%,只增不减、无付费抽）；③ 推进相关**里程碑**计数 → ④ **里程碑门控解锁**(`check_unlocks`,条件达成即发对应装饰)。（payoff ① 长岛在 [§7.4](07-gamemode.md)，不在本章。）
- **稀有度(v2,§9.5 `RARITY`/`TIERS`)**:每件装饰一个等级 **普通 / 稀有 / 史诗 / 传说** → 换装格底色+角标、已装备 chip 角标按等级着色。
- **两条解锁路径**:
  - **随机掉落**(`DROP_POOL`,排除 freebie 与 lock-gated 键)—— 日常小惊喜。
  - **里程碑解锁**(`core/milestones.py`,**40 条**,真实计数即时发奖):指标 `capture/streak/domains/skins/emblems/heads/items/carriers/auras/total` 越阈值 → 解锁指定装饰。**加法**:5 件 endgame 专属(crown / bubble·gold 身色 / ring 承载 / rainbow)从掉落池排除,其余 35 条奖品也可随机掉(里程碑 = 保底路径),保证目录**可收齐**。每事件最多发 4 件(涓流)。
- **孵化保底掉落(v2,`starter_drop`)**:孵化时**必给**一件头部/手持(普通|稀有)并直接装备 —— Reka 出生即穿戴,首掉即礼物。孵化 reveal 步骤弹出**揭示弹窗**(✅ `reka_drop_reveal.dart` `showRekaDropReveal`,对齐设计稿 `hatchReveal`):稀有度染色卡 + **活体 `PetView` 大图**(穿着该件的全身 Reka,celebrate 一下)+ 「孵化掉落 · 稀有度」+ 元信息;因后端已装备故 CTA = 单个「收下」。孵化页底层同时留稀有度 chip 作常驻摘要。
- **freebie**:`carrier:none` 与 `aura:none/soft` 永久可用,不掉落、不门控。
- **里程碑** = 累计型成就（累计捕捉数 / 连续记录天数 / 领域广度〔点亮了几个生活领域〕/ 已集齐身色数…）达阈值 → 解锁装饰 / 徽章。
- **各里程碑阈值、掉落池、掉率、稀有度权重 = collector 调参**（v2 已搭真实骨架 + 5 条门控规则；精确数值后续可调）。
- **配置化:** 装饰目录 / 掉落池 / 里程碑目录 / 掉率阈值 / 稀有度都应收敛进**游戏配置层 [§10](10-game-config.md)**（现散在 `core/pet.py` 键空间 + Flutter 名色/稀有度镜像 → §10 Stage 1 收口 + 校验器；非工程改平衡的后台 = §10 Stage 2）。

---

## 9.4 球球在「我的岛」板块的呈现

「我的岛」tab（engagement 板块）的 shell 由 [§7.6](07-gamemode.md) 定义（它同时托管岛 / 任务 / 历史）；**本章填其中两块**：

```
我的岛（engagement 板块，shell 见 §7.6）
 ├ 球球(当前装扮, hero)        ← §9：点进 换装 / 背包(inventory)
 ├ 当前周岛 / 每日任务 / 历史周岛   （属 §7）
 └ 成就 · 里程碑(已解锁装饰/徽章)  ← §9
```

- **球球（hero）**：当前装扮 → 点进 **换装 / 背包**。
- **成就 · 里程碑**：已解锁的装饰 / 徽章。
- 浮动球球也可作为进入「我的岛」的情感化入口（可选）。

**✅ v1+v2 已实现(`pages/pet_page.dart` `PetBoard`,对齐设计稿 `Reka System`)**:
- **Hero pod(v3 解剖式 callouts)**:名字(可改) + sub(`身色 · 徽记组件名`) + **居中 Reka**(`_HeroCallouts`,300 高 pod);**6 个装备件在框边浮玻璃标签**(头部/左手/承载 在左,徽记/右手/光环 在右),每个标签 = 类别小字 + 值 + 稀有度角标,经**虚线引线 + 锚点**(`CustomPainter` dashed polyline:标签内缘→肘→Reka 上的锚点 dot)连到对应部位;标签宽用 GlobalKey 实测后画线。pet 居中 156×132(=scale6 canvas,锚点分数精确落点)。hero **弹入动画**(进板时);点 hero = celebrate。**不画额外地面 Container**(引擎已含投影)。**取代了 v2 的下方 chip 行**。
- **换装 = 全屏二级页(✅ 已改,`_WardrobePage` / `showWardrobe`)**:不再内嵌在板上,也**不用 bottom sheet**(弹层高度会随 tab 切换抖动 + 弹层小图与外部 hero 双 REKA,体验差)。hero 上有个 **`👕 换装` 入口** → push 一个**全屏页**:**把主视图带进来** —— 顶部就是**同一套解剖式 callouts hero**(`_HeroCallouts`,`entrance` 恒为 1、无飞入),全屏里**只有这一个 REKA**(不再有第二个小预览);下面 **slot tabs**(身色/徽记/头部/左手/右手/**承载/光环**,共 7 槽 + 末尾 **🏆 里程碑**,§9.5)→ 切槽 → **4 列背包 grid**:每格**真实 sprite 预览**(sprite-factory PNG)+ 名称 + **稀有度底色/角标**;选中 = **brand 描边 + 右上 ✓ 角标**;点格当场换装(`PATCH`,全屏 hero + 板上 hero 都实时更新,二者听同一 `PetController`)。**sprite-factory host 移到 app 根**(`main.dart` 1×1 隐藏,**全局常驻**)—— 全屏页盖住板时板的 host 会 offstage 不可靠,故提到根层,板里程碑图标 + 换装格 + 各处 sprite 预览都用同一 singleton。板身只剩 **hero(含换装入口)+ 周岛占位 + 成就·里程碑 summary 卡**(🏆 `N/40` + 进度条,点开 → 换装页 🏆 里程碑 tab;**40 条不再铺在板上**)。**v3 个人库存:只展示已拥有的件**(`unlocked` + freebie;**去掉 locked/🔒/未发现格,不剧透**)。**徽记 = 颜色烘焙进件的命名组件**(`kEmblemComponents`,形×色×名×稀有度;一形可多配色变体如赤焰/蓝电),点件同时设 `emblem`+`emblem_color`(`equipAll`),**已删除徽色 colorbar**。**每槽预览策略**:身色/头部/手持/徽记 = 全身 `sprite()`(徽记用 sky 体色凸显色彩);**承载** = `partSprite('carrier')` 单画底座(全身渲染下底座只是细缝、认不出);**光环** = 全身 + Flutter 补 boxShadow(CSS 辉光不入 PNG)。槽列上方有**稀有度图例**。
- **里程碑(收敛到换装页 🏆 tab)= 5 列 compact grid**:每格**只画奖品 sprite + 进度环**(`partSprite` 真实组件 · 达成绿环 + ✓ 角标,**不写文字**),**点格弹 bottom sheet** 看任务(`label`)+ 进度条 + 奖品名 + 稀有度 + 专属;板上另留一张 **summary 卡**(🏆 `N/40` + 进度条 → 点开此 tab)。**读 `GET /api/pet/milestones`(40 条 + 进度)渲染**(不再硬编码、不再长列表),由真实计数驱动。
- **✅ 像素级预览已落地**(原 emoji 占位的 deferred 项):`lib/render/sprite_factory.dart` = **单个隐藏 1×1 WebView**,载入引擎后 `Mascot.sprite()/partSprite()` → `canvas.toDataURL()` 回传 Flutter,`Image.memory` 显示并按 opts 缓存。避免一屏几十个 WebView。

---

## 9.5 数据模型（pet 表 · 已实现）

> 完整列定义见 [§2 §3.17](02-data-model.md)；HTTP 接口见 [§3.15 ③](03-api-reference.md)。`completion_events` 见 [§2 §3.17 ①](02-data-model.md)。

**v1 收敛为单表 `pets`（每用户 1 行）+ JSON 列**,设计稿的 `mascot` + `mascot_inventory` + `milestones` + `cosmetic_catalog` 四件事都装进它:

- **`pets`(L2,无 exp)**:`{id, user_id(uniq), seed, name, skin, emblem, emblem_color, equipped(JSON), unlocked(JSON), milestones(JSON), spawned(0=蛋/1=已孵化), created_at}`。
  - **7 个可换槽位**:`skin`(体色,10) · `emblem`(徽记) · `head`(头饰,6) · `leftItem`/`rightItem`(双手道具,9) · **`carrier`(承载,5)** · **`aura`(光环,8:none/soft + 6)**。`eyes`/`mouth` 由状态驱动、不存。`equipped` = `{head,leftItem,rightItem,carrier,aura}`(skin/emblem/emblem_color 是顶层列)。**承载/光环住进 `equipped` JSON → 无需迁移**;v2 前的旧宠物读时回填 `carrier='none'`/`aura='soft'`。
  - **徽记(v3)**:存储仍是 `emblem`(形) + `emblem_color`(色)两列,但**前端把它们视为「颜色烘焙进件的命名组件」**(`pet_cosmetics.kEmblemComponents`:形×色→名×稀有度);换装一次设两列(`equipAll`),**无独立选色**。一个形可挂多个配色组件(赤焰/蓝电闪电)。
  - **`unlocked`(= 背包/inventory)**:`{skin:[],emblem:[],head:[],item:[],carrier:[],aura:[]}`(item 池双手共用;`carrier` 默认含 `none`、`aura` 默认含 `none/soft` 这两个 freebie)。**只增不减**。
  - **`milestones`(= 累计计数)**:`{capture_count, streak_days, last_event_date, domains:[]}`。**累计型、绝不因断更回退**(连续天:相邻日 +1、断档归 1、同日不变)。
- **装饰目录 + 掉落池 + 稀有度 + 解锁规则 = 代码内键空间**,非 DB:`backend/core/pet.py`(`SKINS/EMBLEMS/EMBLEM_COLORS/HEADS/ITEMS/CARRIERS/AURAS/RARITY/TIERS/FREE/EXCLUSIVE_KEYS/DROP_POOL`)+ **`core/milestones.py`(40 条里程碑配置)**与渲染引擎 `assets/js/mascot.js` 一一对应;Flutter `pet_cosmetics.dart` 镜像名色 + 稀有度 + 解锁文案。**其元数据/数值应收敛进 [§10 游戏配置](10-game-config.md)**(键空间〔= sprite 画法〕留代码,目录/掉率/稀有度/上下架进 config + 校验器)。
- **多只留位**:靠 `seed` + 未来加 `active` 列;v1 UI 只显 1 只。
- **种子皮肤**:`seed = user_id`,`seeded_skin(seed)=SKINS[sha256(seed)%10]` —— 蛋阶段就定好体色,孵化保留。

---

## 9.6 API（pet 端点 · 已实现,详见 [§3.15 ③](03-api-reference.md)）

收敛为单实体 `/api/pet`(原 `/api/mascot` + `/api/cosmetics` + `/api/milestones` 合一):

- `GET /api/pet` —— 球球状态;**缺失则懒建一颗未孵化的蛋**(skin 按 user_id 种子定),客户端据此显示蛋 / 孵化接管页。返回 `{spawned, name, seed, skin, emblem, emblem_color, equipped(含 carrier/aura), unlocked(含 carrier/aura), milestones}`,**无 exp/level**;旧宠物缺 carrier/aura 时序列化层回填默认。
- `POST /api/pet/spawn {name}` —— 孵化:保留种子皮肤、随机起 starter 徽记、写 starter 背包(体色+徽记+freebie)、**`starter_drop` 保底发一件头部/手持并装备**、置 `spawned=1`;**幂等**(已孵化只更新 name)。
- `PATCH /api/pet {name?, equip?}` —— 改名 / 换装;`equip={slot:value}`,`slot ∈ skin/emblem/emblem_color/head/leftItem/rightItem/**carrier**/**aura**`,`value` 须在 `unlocked` 内(或 `none`;`aura` 额外放行 freebie `soft`;`emblem_color` 不门控)。
- **里程碑门控解锁**无单独端点 —— `emit_completion_event` 内 `bump_milestones` 后调 `check_unlocks`,达成条件即写入 `unlocked`,客户端经 `GET /api/pet` diff 出新装饰并 toast。
- **里程碑**不单设端点 —— 累计计数随 `GET /api/pet` 的 `milestones` 返回。
- **装饰目录**不设端点 —— 是代码内键空间(见 §9.5);前端 `pet_cosmetics.dart` 给键空间配中文名/色板。
- 后置:`POST /api/pet/active`(多只切换)。

---

## 9.7 盈利与护栏（pet 切面）

- **premium 装饰 / 形态 = 干净付费面**（只卖外观）；只增不减、无 FOMO、不付费抽。
- 全产品计量与定价模型见 [§12 商业模式](12-business-model.md)（pending）；护栏原则见 [§7.11](07-gamemode.md)。

---

## 9.8 v1 范围与后置

- **✅ v1+v2 已实现:** 1 只球球(单表 `pets`,无 exp)、孵化接管(蛋→起名→介绍→**孵化掉落 reveal**)、背包换装(**7 槽位** + 体色/徽色 + 承载 + 光环)、**稀有度四级**(普通/稀有/史诗/传说)、**随机掉落**(`roll_drop` ~55% 只增不减)+ **里程碑门控解锁**(`check_unlocks` 5 条规则)+ **孵化保底掉落**(`starter_drop`)、掉落庆祝 toast、**全局浮动可拖球球(短按雷达 / 长按续对话 / 记忆位置)**、**sprite-factory 像素级换装预览**、WebView 复用设计引擎渲染(`partSprite` 单组件)。
- **⏳ 后置:** 「我的岛」完整板块(承 [§7.6](07-gamemode.md),需岛先落地;浮动球雷达届时加「生成今日任务 / 周岛」)、多只宠物切换、premium 付费装饰、换装美术深度、collector 调参(里程碑阈值 / 掉率 / 掉落池 / 稀有度权重 / 每领域封顶)、E-ink 硬件表情。
- **掉率/阈值/稀有度现值(可调):** 掉落 `_DROP_CHANCE=0.55`、全解锁后不再掉;5 条门控规则(100 捕捉 / 14 连续 / 8 领域 / 8 身色)+ 每件装饰一个 `tier`。数值都在 `core/pet.py`,collector 后期单点调 → **收敛进 [§10 游戏配置](10-game-config.md)**(Stage 1 集中 + 校验器;Stage 2 后台不发版调)。
