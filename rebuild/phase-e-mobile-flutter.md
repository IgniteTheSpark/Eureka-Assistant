# Phase E — Mobile (Flutter) + TestFlight

> 版本:v0.1 | 2026-06-02 | 状态:规划中(Phase D 的 React web app 已稳定,作为 UI 参照)
> 配套:[phase-d 前端](phase-d-frontend-design.md) · [phase-b 架构](phase-b-architecture-blueprint.md) · [runtime-flow](runtime-flow.md)

把 Eureka 从 web SPA 迁移到 **Flutter 原生 iOS app**,目标:**上 TestFlight**,且 **v0 即包含 BLE 硬件闪念(W1/W2 卡)**。后端保持 FastAPI/Python(已迁移到 MySQL),与公司栈(MySQL / Redis / Node / Flutter)对齐。

---

## 一、关键决策(已锁定)

| # | 决策点 | 选择 | 备注 |
|---|---|---|---|
| 1 | App 技术栈 | **Flutter**(对齐公司栈) | 重写 UI,不是 wrap;React `frontend/` 作参照 |
| 2 | v0 范围 | **含硬件闪念(BLE 卡)** | 最长的一根 pole,见 §五 |
| 3 | 后端 | **保留 FastAPI/Python** | 已在 MySQL 上;不改写成 Node |
| 4 | BLE/Opus 采集 | **复用现有 Swift 栈 → 包成 Flutter plugin** | 不在 Dart 里重写 BLE/Opus(关键降险) |
| 5 | 关系库 | **MySQL(已完成)** | 向量库 Postgres 待 embedding 落地后再上 |
| 6 | 鉴权 | Sign in with Apple + JWT(behind `get_current_user_id`) | 见 §四,需与公司鉴权策略对齐 |

---

## 二、现状 → 目标 差距

**已有**
- `backend/` — FastAPI + Google ADK agents + MySQL(aiomysql/pymysql),SSE chat/flash,12+ API 端点。可本地 Docker 跑通。
- `frontend/` — React/Vite web SPA(Chat / Calendar 流月年 / Library / Notifications / AssetDetail / AddSkillWizard / flash overlay)。**这是 Flutter 重写的视觉与交互参照。**
- `integrations/flash-card/` — 桌面 flash 桥(`eureka-bridge.py` / `listen-watcher.py`):监听 Mac 上的 FlashType app 输出 → POST `/api/flash`。**仅 Mac**,移动端不可用,但它定义了 capture→backend 的契约。
- FlashType Swift SPM 工程(`~/Documents/flash-type-swift-feature-main-intent-5dba85e`):`FlashTypeBluetooth.swift`(BLE)+ `OpusDecoder.swift` + `YbridOpus.xcframework`。**这是 §五 plugin 复用的源。**

**缺口(到 TestFlight)**
1. **没有任何 iOS / Flutter 工程** —— 最大块。
2. 后端只在 localhost Docker:需云部署 + HTTPS + 托管 MySQL。
3. 鉴权是 stub(`get_current_user_id()` 恒返回 `"default"`)。
4. 硬件闪念在移动端不存在(桥是 Mac-only)。
5. Apple 侧:开发者账号、App Store Connect、签名、图标、隐私声明、上传。

---

## 三、Milestones(E0–E5)

每个 milestone = 可演示 + commit + tag `phase-e/eN`。估时按 1 人计,可并行处压缩。

| M | 内容 | 估时 | 依赖 | 状态 |
|---|---|---|---|---|
| **E0** Foundations | 后端云部署(HTTPS + 托管 MySQL + secrets + CORS);Apple 开发者账号 + App Store Connect record + bundle id;鉴权 seam(JWT-ready) | ~1 wk | 公司基建 / Apple 账号 | pending |
| **E1** Flutter skeleton | Flutter 工程 + 状态管理 + 路由 + design tokens 移植(`--eu-*`→ThemeData) + Dart API client + **SSE client** + AppShell(dock + 3 面板 stub) | 1–1.5 wk | E0 后端可达 | pending |
| **E2** Port surfaces | Chat(SSE/cards/markdown/precipitate/cost footer)· Calendar(流月年 + ⚡ flash 条 + day detail + event editor)· Library(类目 + AssetDetail + AddSkillWizard)· Notifications。render_spec 卡片系统是大头 | 2–3 wk | E1 | pending |
| **E3** Native BLE flash | Swift Flutter plugin 包 BLE+Opus(复用 FlashType 栈)→ connect/stream;ASR 选型;capture→`/api/flash`;listening overlay;BLE 后台 + 权限 | 2–3 wk | E1(可与 E2 并行) | pending |
| **E4** TestFlight prep | 图标 / 启动屏 / Info.plist 权限串 / App Privacy label / 出口合规 / 签名 / 上传 | 3–5 d | E2+E3 | pending |
| **E5** Beta hardening | 崩溃上报 / 错误 + 离线态 / 反馈通道 | ongoing | E4 | pending |

**粗估:~7–11 周** 到含硬件闪念的 v0。E3(BLE/Opus)是进度风险,plugin 复用是控险关键。

---

## 四、后端部署 + 鉴权(E0)

**部署**(FastAPI 不变)
- 云主机 / 容器,**HTTPS/TLS**(Apple ATS 拒绝明文 HTTP)。
- 托管 / 公司 MySQL(`DATABASE_URL` 切过去;`alembic upgrade head` + seed)。
- secrets 上服务端(`OPENROUTER_API_KEY` 等)。CORS 收敛到 app origin。
- 健康检查 `/health` 已有。
- 开放决策:部署目标(k8s / PaaS / 云 VM)—— 取决于公司基建。

**鉴权**
- 当前:`backend/core/auth.py` `get_current_user_id()` 恒返回 `settings.user_id`。这是设计好的单一 seam。
- v0:Sign in with Apple(Apple 友好)→ 后端校验 identity token → JWT;`get_current_user_id` 读 `Authorization: Bearer`,无 token 时 dev 回退 `"default"`。
- 开放决策:公司是否有集中鉴权(Node 服务)?若有,FastAPI 应对接而非自建 Apple 登录。
- 若有账号体系,Apple 要求提供**账号删除**入口。

---

## 五、硬件闪念 plugin 策略(E3,最关键)

W1/W2 卡通过 BLE 流式 **Opus** 音频;现有 Mac FlashType 已把这套(BLE 协议 + Opus 解码)用 Swift 跑通。

**策略:把这套 Swift 采集栈封成 Flutter iOS plugin,不在 Dart 重写。**
- 复用 `FlashTypeBluetooth.swift`(扫描 / 连接 / 订阅特征 / 读流)+ `OpusDecoder.swift` + `YbridOpus.xcframework`。
- 暴露 `MethodChannel`(connect / disconnect / 状态)+ `EventChannel`(音频帧 / 转写片段 / 连接事件)给 Dart。
- Dart 侧:listening overlay + 把结果 POST 到 `/api/flash`(契约同桌面桥)。

**ASR 选型(开放决策)**:桌面桥用 `FLASH_TYPE_ASR_COMMAND`。移动端选 on-device(Apple Speech / Whisper.cpp)还是云。影响延迟 / 隐私 / 成本。

**iOS 细节**:CoreBluetooth 后台模式、`NSBluetoothAlwaysUsageDescription`、`NSMicrophoneUsageDescription`、断连重连、低电量。

---

## 六、Apple / TestFlight 清单(E4)

- Apple Developer Program 会员($99/yr,**先办**,审批有时延)。
- App Store Connect:app record + bundle id;签名证书 + provisioning(Xcode 自动签名或 fastlane)。
- 图标全尺寸、启动屏、version/build 号。
- `Info.plist`:麦克风 / 蓝牙 usage 串;App Privacy「营养标签」;出口合规(加密)问答。
- 构建 + 上传(Xcode / Transporter / fastlane)。
- TestFlight:内部测试者即时;外部测试者需一次 Beta App Review。

---

## 七、开放决策(需用户/公司确认才能执行)

1. **后端部署目标**:公司基建是什么(k8s / 某 PaaS / 云厂商)?有没有现成 CI/CD?
2. **鉴权**:自建 Apple 登录于 FastAPI,还是对接公司既有(Node)鉴权服务?
3. **ASR**:on-device 还是云?用哪个?
4. **Flutter 约定**:状态管理(Riverpod / Bloc / 公司模板)、最低 iOS 版本、是否单仓库还是独立 repo。
5. **`frontend-next`**(Next.js)去留:留作参照还是删,避免双源。

---

## 八、v0 明确 out-of-scope

- Android(先 iOS / TestFlight)。
- 多租户后台 / 管理端。
- Redis(公司栈有,但 v0 未用到,按需再上)。
- 向量库 / 语义检索(待 embedding)。
- 离线优先 / 本地缓存深度优化。
- 推送通知(可 E5+)。

---

## 九、风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| BLE/Opus 在 Flutter 落地 | E3 进度最大不确定 | 复用 Swift 栈封 plugin(§五),不重写 |
| render_spec 卡片系统重写量 | E2 体量大 | 先 chat + 一种卡片打通管线,再铺开 |
| 鉴权与公司栈重复 | 返工 | E0 先定 §七.2 |
| 部署基建不明 | E0 阻塞 | 先定 §七.1;后端本身 deploy-ready |
| App Review(蓝牙/麦克风权限说明、隐私标签) | 上架延迟 | E4 提前备齐权限串 + 隐私标签 |

---

## 十、即时下一步

1. 提交当前 React 基线(markdown 渲染 + ⚡ flash 时间线 + 时区修复 + 自定义技能 chip),让参照系干净。
2. 修掉 2 个 pre-existing `tsc` 错误(SkillCard `CheckTile` / CategoryList),保证 web 参照可 build。
3. 定 §七 的开放决策(尤其部署目标 + 鉴权策略),即可开跑 E0。
