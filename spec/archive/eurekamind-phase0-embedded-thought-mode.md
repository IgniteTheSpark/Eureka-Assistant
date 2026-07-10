# EurekaMind Phase 0：嵌入式闪念模式接入方案

## 1. 核心决策

Phase 0 **不是后端合并，也不是数据合并**。

当前 EurekaMind 保持“会议产品”的主体能力不变；UReka 作为一个独立的“闪念 / 资产 / 日历”模式嵌入到同一个 App 里。两边只共享账号身份，不共享数据库、不共享 agent、不共享业务表。

对用户侧统一品牌为 **EurekaMind / eureka**。嵌入后的体验里不再把 UReka 表达成另一个独立产品。

选择这个方案的原因是：当前 EurekaMind 后端和 UReka 后端很可能不是同一语言 / 同一运行时。Phase 0 如果尝试把 UReka 的 flash dispatcher、资产模型、MCP tools、agent 编排整体 copy 进会议后端，实际会从“接入”变成“重写”，风险和周期都不可控。

## 2. 目标

- 让现有 EurekaMind 用户能在同一个 App 内使用 UReka 的核心闪念能力。
- 用 UReka 的 flash capture 和 typed assets 替换当前 EurekaMind 较弱的 memo / 闪念能力。
- 将会议首页的日历入口跳转到 UReka 日历。
- 保持会议录音、会议详情、会议总结、会议提醒、会议名片、会议 agent 稳定不动。
- 建立账号桥，让两套系统识别同一个逻辑用户。
- 为后续逐步拆墙预留接口：会议 todo 同步、会议只读桥、联系人关联、统一首页。

## 3. 非目标

- 不合并 EurekaMind 会议后端和 UReka 后端。
- 不合并数据库。
- 不合并会议 agent 和 UReka agent。
- 不迁移现有会议提醒到 UReka todo assets。
- 不替换 EurekaMind 现有 business-card / contact 体系。
- 不把会议首页改成统一 today 首页。
- 不在 EurekaMind 内展示 UReka 独立登录页。
- 不继续保留当前 EurekaMind 旧 memo generated-assets 弹层作为主入口。

## 4. 当前代码事实

### 4.1 EurekaMind Flutter

仓库：`/Users/admin/workwork/eureka-staff/bizcard-flutter`

- 技术栈：Flutter、go_router、signals、Dio、Slang i18n。
- 当前首页是会议列表首页。
- `HomePage` 当前包含：
  - ask bar：进入当前会议 / general agent
  - calendar icon：通过 `WebviewConfig.h5Calendar` 打开 H5 日历
  - 旧闪念 / memo banner：进入 `FlashRoute`
  - 底部胶囊：录会议 / 问 agent / 上传音频
- `AskAgentArgs` 已支持 `general`、`contact`、`meeting`、`reminder`、`memo` 五种 scenario。
- 会议详情里的 Ask Eureka 使用 `AskAgentArgs.meeting(dataId: meetingId)`，已经支持基于某场会议的上下文对话。
- 当前旧闪念使用 `/api/app/memo/v1/*`，点击 memo 详情后进入 `AskAgentPage` 的 `memo` scenario。
- 会议提醒使用现有 meeting / card reminder APIs，编辑页仍走 H5 reminder 页面。

### 4.2 UReka Flutter

仓库：`/Users/admin/workwork/eureka-staff/Eureka-Assistant/mobile`

- 技术栈：Flutter、独立 `MaterialApp`、Riverpod、singleton controllers、`http` ApiClient。
- 主 shell 是 `AppShell`。
- 一级页面包括：
  - 今日
  - 日历
  - 资产库
- 闪念 capture 是 `showFlashSheet(context)` bottom sheet，不是一个常驻 tab。
- Auth 由 `AuthStore.token/userId` 持有，`AuthController` 持久化：
  - `eureka_token`
  - `eureka_user_id`
  - `eureka_email`
- API base URL 通过编译参数 `API_BASE` 注入，默认 `http://localhost:8000`。

## 5. 产品形态

### 5.1 会议模式

会议模式保持当前 EurekaMind 体验：

- 当前会议首页不改。
- 当前会议列表不改。
- 当前会议详情不改。
- 当前会议总结和 transcript 不改。
- 当前会议 reminder tab 不改。
- 当前 business-card / contact 体系不改。
- 当前 meeting / general agent 不改。

会议模式只改两个入口：

- 当前旧闪念 / memo 入口改成进入嵌入式闪念模式。
- 当前日历 icon 改成进入嵌入式闪念模式里的 UReka 日历页。

### 5.2 闪念模式

闪念模式是嵌入后的 UReka 体验：

- 使用 UReka 后端、UReka DB、UReka agent、UReka flash pipeline、UReka assets、UReka calendar。
- 视觉和文案上统一为 EurekaMind / eureka 品牌。
- 不展示 UReka 独立登录页。
- 用户感知应该是“EurekaMind 的闪念模式”，不是“跳到了另一个产品”。

闪念模式一级导航：

- 今日
- 日历
- 资产库

闪念 capture 作为模式内动作存在。会议首页旧闪念入口点击后的默认行为可以二选一：

- 进入闪念模式后立即打开 flash capture sheet。
- 进入闪念模式 Today 页，并在页面上提供显著的闪念动作。

产品偏好：旧闪念入口应该让用户感觉是在“开始 / 查看闪念”，而不是简单打开另一个 App。

## 6. 导航与入口

### 6.1 旧闪念入口

当前：

- `HomeFlashReviewBanner` 通过 `MemoApiService` 读取旧 memo count。
- 点击后进入 `FlashRoute`，展示旧 memo list。
- 点击 memo item 后进入 `AskAgentPage` 的 memo scenario。

Phase 0 目标：

- 保留首页入口位置。
- count 数据源改成 UReka thought / flash count（如果 UReka 提供）。
- 如果 UReka 暂时没有 count 接口，则展示静态入口，不展示数量。
- 点击后进入嵌入式闪念模式。
- 旧 `FlashRoute` 不再从主路径可达。

建议文案：

- 标题：`闪念`
- 有数量时：`你有 N 条闪念`
- 无数量时：`记录想法、待办、联系人和日程`

### 6.2 日历 icon

当前：

- 会议首页 top bar 的日历 icon 打开 `WebviewConfig.h5Calendar`。

Phase 0 目标：

- 日历 icon 进入嵌入式闪念模式，并默认选中 `Calendar` 页。
- Phase 0 中，UReka 日历不展示会议 reminder，除非这些 reminder 本身是在 UReka 内创建的。
- 这是 Phase 0 的预期限制，不视为 bug。

### 6.3 资产库

资产库不作为会议首页顶部的一个小 icon 放在日历旁边。

资产库是闪念模式内的一级页面。会议模式首页不继续堆叠 UReka 专属入口，避免会议首页变成杂项入口集合。

## 7. 账号桥

Phase 0 必须有一个后端 token bridge。

### 7.1 必要接口语义

EurekaMind App 已有会议产品登录态。客户端通过当前登录态请求一个 UReka session：

```http
POST /api/app/ureka/v1/token/exchange
Authorization: Bearer <eurekamind-token>
```

返回：

```json
{
  "ok": true,
  "ureka_token": "<jwt>",
  "ureka_user_id": "<id>",
  "email": "optional@example.com"
}
```

接口路径可以调整，但语义不变：

- 输入：当前 EurekaMind 已登录用户。
- 输出：同一个逻辑用户对应的 UReka JWT 和 UReka user id。
- 如果 UReka 侧用户不存在，由后端负责 provision。

### 7.2 客户端行为

首次进入闪念模式时：

1. 检查本地是否已有可用 UReka auth state。
2. 如果缺失或过期，调用 token exchange。
3. 将返回的 token / user id 注入 UReka `AuthStore`。
4. 进入嵌入式 `AppShell`。

嵌入模式下禁用 UReka LoginPage。

### 7.3 登出

用户从 EurekaMind 登出时：

- 清理 EurekaMind 当前登录态。
- 清理嵌入式 UReka auth state。
- 停止已启动的 UReka SSE / listening / background managers。

## 8. 后端和 API 边界

### 8.1 服务边界

Phase 0 使用两个独立后端。

EurekaMind 会议后端负责：

- 会议上传
- 会议列表 / 详情
- transcript
- summary
- meeting reminders
- business cards
- meeting / general agent

UReka 后端负责：

- flash pipeline
- assets
- timeline / calendar
- UReka chat agent
- UReka contacts
- UReka connected apps

### 8.2 客户端 API 配置

不要复用 `bizcard-flutter` 里现有的 `ApiPath.eureka` 作为 UReka 后端地址。

新增独立 UReka API base 配置，例如：

```dart
UREKA_API_BASE=https://...
```

嵌入式 UReka `ApiClient` 直接请求该 base。

## 9. 设计和命名适配

### 9.1 命名

用户可见 UI 不再把 UReka 表达为独立产品。

允许使用：

- EurekaMind
- eureka
- 闪念
- 资产库
- 日历

Phase 0 嵌入体验中避免出现：

- UReka
- UReka Assistant
- 作为独立产品人格出现的 Reka / 球球表达

### 9.2 视觉适配

UReka 当前有自己的 palette、字体、floating dock、global header、mascot、onboarding。

Phase 0 需要一轮设计适配：

- 将 UReka wordmark 替换成 EurekaMind / eureka 命名。
- 颜色尽量贴近 EurekaMind 当前 App 视觉体系。
- 顶部 chrome 和导航密度贴近会议版。
- 避免让闪念模式看起来像另一个安装在 App 里的产品。
- 保留 UReka 的信息架构和数据流，不在 Phase 0 重做产品结构。

### 9.3 默认隐藏能力

除非另行确认，嵌入式上线默认隐藏或禁用：

- UReka 独立登录 / 注册页
- pet onboarding
- 强制全局 floating mascot
- ring / debug-only 页面
- 与会议模式设备流冲突的 UReka device pairing

这些能力后续可以按产品方向逐步恢复。

## 10. 数据边界

### 10.1 会议提醒

Phase 0 不把会议提醒合并进 UReka todos。

结果：

- 会议详情 reminder tab 继续展示现有会议提醒。
- UReka 日历不展示会议提醒，除非这些提醒在 UReka 内被创建。
- 这是预期行为。

### 10.2 联系人

Phase 0 不合并联系人。

结果：

- 会议 / business-card 联系人继续在 EurekaMind 会议后端。
- UReka contacts 继续在 UReka 后端。
- 用户可能在两个模式里看到“联系人类”记录。
- UI 不应承诺“联系人已经全局统一”。

### 10.3 Agent

Phase 0 不合并 agent。

结果：

- 会议模式 agent 继续回答和操作会议 / 名片 / reminder 上下文。
- 闪念模式 agent 继续回答和操作 UReka assets / calendar / contacts。
- 跨模式提问延后到后续阶段。

## 11. 实施轮廓

### 11.1 嵌入式 UReka Shell

需要创建一个可以挂进 `bizcard-flutter` 的 UReka embedded entry，不能直接运行 UReka 的 standalone `main.dart`。

建议形态：

```dart
class UrekaEmbeddedShell extends StatelessWidget {
  const UrekaEmbeddedShell({
    required this.initialTab,
    this.openFlashOnEnter = false,
  });
}
```

输入：

- `initialTab`：today / calendar / assets
- `openFlashOnEnter`：首帧后是否自动打开 `showFlashSheet`

职责：

- 提供 UReka 所需 theme / ProviderScope。
- 确保 UReka auth 已注入。
- 渲染 UReka `AppShell` 或适配后的等价 shell。
- 尽量避免嵌套 `MaterialApp`；除非没有更稳的替代方案。

### 11.2 Token Bridge Client

在 `bizcard-flutter` 侧新增一个小 client：

- 调用 token exchange。
- 存储 UReka token / user id。
- 进入闪念模式时注入 UReka auth。
- 登出时清理。

### 11.3 替换首页旧闪念入口

调整 `HomeFlashReviewBanner`：

- count 来源：优先 UReka；不可用则静态展示。
- 点击：进入 `UrekaEmbeddedShell(initialTab: today, openFlashOnEnter: true)`。

不再把旧 memo list 作为默认目标。

### 11.4 替换日历 icon 目标

调整首页 calendar icon：

- 目标：`UrekaEmbeddedShell(initialTab: calendar)`。
- Phase 0 主路径不再进入 H5 calendar。

### 11.5 移除旧闪念主路径可达性

旧 flash route 可以暂时留在代码里，但不再从主导航或首页入口进入。

后续 cleanup 可删除：

- 旧 `feature/flash`
- 首页旧 memo list 相关依赖
- 如果不再需要，删除旧 memo scenario 入口

## 12. 验收标准

Phase 0 成功标准：

- 当前会议首页正常加载，主行为不变。
- 当前会议详情正常加载，主行为不变。
- 当前会议 agent 仍可从首页和会议详情进入。
- 首页旧闪念入口进入嵌入式闪念模式。
- 首页旧闪念入口不再进入旧 memo list。
- 首页日历 icon 进入嵌入式 UReka calendar。
- 闪念模式可使用 exchanged token 请求 UReka 后端。
- EurekaMind 登出时，两边 auth state 都被清理。
- 嵌入体验里不出现 UReka 作为独立产品的用户可见命名。

## 13. 风险

### 13.1 嵌套 Flutter App 风险

UReka 当前是独立 App，包含自己的 `MaterialApp`、auth gate、global overlays、mascot 和 singleton managers。

缓解：

- 抽出 embedded shell，不直接嵌套完整 standalone `EurekaApp`。
- 嵌入模式下禁用 standalone login 和 onboarding。

### 13.2 设计割裂

UReka 当前视觉语言可能看起来像另一个 App。

缓解：

- Phase 0 包含设计适配 pass。
- 优先处理命名、top chrome、颜色、导航密度。

### 13.3 数据预期割裂

用户可能以为 UReka 日历会显示会议提醒。

缓解：

- Phase 0 不把该日历描述成“全部任务”。
- Phase 1 再做 meeting todo sync。

### 13.4 Token Bridge 依赖

没有 token exchange，嵌入体验无法做到无感登录。

缓解：

- 将 token bridge 视为 Phase 0 唯一强制后端依赖。

## 14. 后续拆墙路线

### Phase 1：Todo Sync Bridge

将会议 reminders 同步到 UReka todo assets。

推荐由会议后端负责：

- meeting backend 主动调用 UReka sync API
- 或 meeting backend 发事件，UReka 消费

必要映射：

- `source_type = meeting`
- `source_meeting_id`
- `source_reminder_id`
- title
- due date / time
- done state
- 可选 related contacts

### Phase 2：Agent Read Bridges

增加只读桥：

- UReka agent 可以读取会议 summary / transcript。
- 会议 agent 可以读取 UReka assets。

使用 HTTP tool API，不做同进程 tool import。

### Phase 3：联系人关联

不要立即物理合并联系人表。

先基于以下字段做候选关联：

- email
- phone
- name + company

之后再决定 business-card contact 是成为 canonical contact profile，还是作为 linked profile 保留。

### Phase 4：统一 Today / Home

只有在 todo bridge 和 read bridge 成立后，再考虑统一首页。

统一首页可以混排：

- meetings
- flash captures
- todos
- calendar events
- assets

## 15. 待确认后端契约

实施前需要确认：

1. UReka dev / staging / prod API base URLs。
2. token exchange endpoint 路径和响应结构。
3. UReka 后端是否能根据 EurekaMind user id / email 自动 provision 用户。
4. 可选：UReka 是否提供首页闪念入口 count 接口。

如果第 4 项暂时没有，Phase 0 可以用静态闪念入口上线。
