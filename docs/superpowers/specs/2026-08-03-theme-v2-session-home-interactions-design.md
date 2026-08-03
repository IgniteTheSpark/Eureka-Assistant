# Theme V2 Session 与 Today 交互修正设计

日期：2026-08-03  
状态：已确认，待实施  
范围：Theme V2 Session 输入与 turn 计数、Today 顶部全局导航、Today Asset 泡泡池物理动效

## 1. 目标

本轮修正四个已确认的交互问题：

1. 用户在 Session 发送文字后立即收起软键盘。
2. Session 页头和背景水印展示 user turn 数，而不是 user/agent 消息总数。
3. Today 首页加入现有 Theme V2 顶部全局导航。
4. Today Asset 泡泡池恢复旧版的真实重力、碰撞、拖动和倾斜反馈，同时保留 Theme V2 的视觉与 Core Record 路由。

## 2. 产品决策

### 2.1 Session turn 定义

一个 turn 由一次用户输入开始。一次录音闪念、一次文字提问都各计一个 turn；对应的 Agent 回复、工具结果、错误提示和流式中间状态不另计数。

因此，当 Session 内存在 6 条 user message 和 6 条 agent message 时，页头与背景水印都显示 `06`，而不是 `12`。失败但已经提交的 user message 仍算一次 turn。

### 2.2 首页全局导航

Today 使用与 Calendar、Library 相同的 `ThemeV2GlobalTopNav`，包含：

- UReka Logo；
- 设备连接状态与设备入口；
- Light/Dark 主题切换；
- 通知入口与未读数。

底部 `ThemeV2FloatingDock` 继续保留“今日 / 日历 / 资产”三个入口。本决策覆盖 `spec/design/theme-v2-today-handoff.md` 中“Home 不显示额外 Global Top Nav”的旧约束。

### 2.3 泡泡池技术方向

复用旧版 `mobile/lib/today/bubble_physics.dart` 中基于 Forge2D 的 `BubbleField` 物理世界，不直接嵌入旧版 `BubblePool`。Theme V2 提供自己的状态管理、绘制和 Core Record 点击行为。

选择该方案的原因：

- 保留已经验证过的 Box2D 重力、圆形碰撞、睡眠和抛掷手感；
- 不重新引入旧主题 token、旧 Dock 几何、旧 Asset API 和旧页面手势；
- Theme V2 的视觉尺寸、渐变、语义和 Asset 详情入口保持独立。

## 3. 组件设计

### 3.1 Session Composer

`SessionComposer` 在确认输入非空且当前不处于发送状态后，按以下顺序处理：

1. 规范化输入；
2. 清空文本框；
3. 对传入的 `FocusNode` 调用 `unfocus()`；
4. 调用异步 `onSend`。

键盘在网络请求开始前收起。请求失败时不自动重新获取焦点，错误仍由现有 Session 错误区展示。

### 3.2 Session turn 计数

增加一个无副作用的共享计算函数，仅统计 `messages.where((message) => message.isUser)`。

`ThemeV2SessionPage` 只计算一次 turn count，并传给：

- `SessionHeader` 的小号计数；
- `SessionTranscript` 的大号背景水印。

`SessionTranscript` 内部用于滚动、焦点定位和内容签名的 message 数量逻辑不改，因为那些逻辑描述的仍是实际渲染消息结构。

### 3.3 Today 顶部全局导航

生产 `ThemeV2AppShell` 的 Today page declaration 从 `showTopNav: false` 改为使用默认开启状态。继续复用 Shell 已构造的同一个 `ThemeV2GlobalTopNav`，不在 `ThemeV2HomePage` 内重复创建导航实例。

Top Nav 占据 Shell 的标准 56 px 布局高度；Today Panel 在剩余 viewport 中继续使用现有 10 px 顶部间距和响应式高度计算。底部 Dock、安全区和 Panel 内部布局规则保持不变。

### 3.4 Theme V2 物理泡泡池

当前静态 `_AssetBubbleField` 改为有生命周期的 Stateful Widget，并负责以下边界：

- 将 `PoolAsset` 映射为 Forge2D 圆形动态刚体；
- 使用当前 Theme V2 视觉直径作为碰撞直径；
- 构建泡泡区域自身的顶、底、左、右四面静态边界；
- 默认使用向下重力；
- 订阅加速度计，将真机倾斜映射为固定强度的屏幕空间重力；
- 使用单一 Ticker 推进物理世界并触发重绘；
- 泡泡全部休眠时停止 Ticker；
- 首页不可见、App 进入后台或 Widget dispose 时停止 Ticker 并取消传感器订阅；
- 数据增加时从上方加入新泡泡，数据删除时移除对应刚体；
- 点击泡泡打开对应 Core Record Asset；
- 拖动泡泡时使用旧版的 velocity-chase 行为，释放后保留速度形成自然抛掷。

`BubbleField` 的 Dock 障碍改为可选。旧版 Today 继续传入 Dock collider，Theme V2 的泡泡区域本身位于 Panel 内且不与底部 Dock 重叠，因此不传 Dock collider。

Theme V2 不恢复旧版的背景横滑换页、长按类型筛选或旧详情 Sheet。

## 4. Motion 与无障碍

- 泡泡使用 Forge2D restitution、friction、linear damping 和 angular damping，参数以旧版为基线。
- 物理世界只在至少一个刚体醒着时逐帧运行。
- 有意义的设备倾斜才唤醒刚体，过滤传感器微抖动。
- `MediaQuery.disableAnimations` 为 true 时不启动持续物理 Ticker 或加速度计，泡泡使用稳定的静态落位。
- 泡泡保留当前“打开资产”的 button semantics 和至少 44 px 的可操作范围。
- 顶部导航继续使用现有设备、主题和通知语义标签。

## 5. 数据与导航边界

- 泡泡数据继续来自 `TodayData.pool`，真实总数继续来自 `poolTrueCount`。
- 不增加新的后端接口、缓存或数据库字段。
- 不改 Asset 业务目的地：Theme V2 泡泡始终通过 `AssetEntityKind.asset` 和 `coreRecordsOnly: true` 打开详情。
- 不改 Calendar、Library、通知或设备连接的数据模型。
- 不把完整旧 `BubblePool` 引入 Theme V2，也不恢复旧版横向 Home 层级。

## 6. 错误与降级

- Session 发送失败：键盘保持收起，现有错误状态继续显示。
- 加速度计不可用或流报错：保留默认向下重力，泡泡碰撞与拖动仍可用。
- 泡泡池为空：保持当前安静空态，不创建物理世界或传感器订阅。
- 物理区域尺寸为零或发生旋转：下一帧按新尺寸安全重建世界。
- Asset 数据刷新：保留未变化泡泡的世界状态，增删差量同步。

## 7. 测试与验收

### 7.1 自动化测试

- Widget test：有效发送后 `FocusNode.hasFocus == false`。
- Unit/widget test：6 条 user message + 6 条 agent message 时，Header 和 watermark 均显示 `06`。
- Widget test：Agent 流式更新不改变 turn count；新增 user message 才增加。
- Shell test：Today 页面显示 `ThemeV2GlobalTopNav`，设备与通知入口可点击；Floating Dock 仍存在。
- Physics unit test：无 Dock collider 的世界受向下重力运动且保持在边界内。
- Physics unit test：两个圆形刚体发生碰撞后不穿透。
- Widget test：Reduce Motion 下泡泡池不启动持续物理动画。
- Widget test：点击 Theme V2 物理泡泡仍打开对应 Core Record Asset。

### 7.2 真机验收

1. 在 8 月 3 日闪念 Session 输入并发送文字，确认键盘立即收起。
2. 确认 6 个 user turn 的页头和背景水印都显示 `06`。
3. 返回 Today，确认顶部可见设备状态、主题切换和通知入口，底部 Dock 仍正常。
4. 观察泡泡自然下落和互相碰撞；倾斜手机时重力方向随之改变。
5. 拖动并抛出泡泡，确认其继续运动、发生碰撞并最终休眠。
6. 点击泡泡，确认打开正确 Asset 且无旧 API 404。

## 8. 非目标

- 不修改 Session 后端问答协议。
- 不改变 turn 的持久化结构，仅改变客户端展示计数。
- 不恢复旧版 Today 的 Reka Offer 横滑层、Dashboard 或长按类型面板。
- 不调整 Theme V2 总体导航信息架构。
- 不修改 Forge2D 依赖版本或引入新的动画/物理依赖。
