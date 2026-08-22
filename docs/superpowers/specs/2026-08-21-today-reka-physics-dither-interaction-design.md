# Today Reka、资产物理与 Dither 交互修复设计

日期：2026-08-21

## 背景

当前 Theme V2 首页与根页面共享同一个 dither Reka。真机验证后出现四个相互关联的问题：

1. 日历 Flow 中的“回到今天”悬浮按钮与 Dock 上方的小 Reka 使用同一底部中央空间，按钮会被遮挡。
2. 首页拖动 Reka 时，视觉位置缓慢追赶手指，松手后才突然到达最终位置。
3. Reka 生成的新资产在动画阶段不属于资产物理场，只有到达底部、完成动画后才成为可碰撞的资产球。
4. 首页资产球移动时，dither 对速度变化的反馈太弱，周围扩散不明显。

本设计采用“统一交互与物理接管”方案：保留现有视觉语言和物理引擎，修正所有权与阶段边界，不引入新的首页场景体系。

## 目标

- 首页 Reka 在拖动阶段逐帧跟手，手指、命中区域和视觉中心始终一致。
- 260ms 的 Reka 位移动画只服务于首页与 Dock 之间的形态切换。
- Dock 上方 Reka 不挤压主页面内容，但会为同区域的悬浮操作提供明确避让边界。
- 新资产进入资产 chamber 后立即由 `BubbleField` 接管，下降途中即可与已有资产球发生碰撞。
- 资产球移动越快，周围 dither 扩散越明显；静止后恢复当前安静状态。
- 遵守系统“减少动态效果”，不增加持续动画或额外物理运动。

## 非目标

- 不重做首页信息架构、Dock 或 Reka 造型。
- 不把 Reka 本身加入 Forge2D 物理世界。
- 不改变资产、闪念或语音服务的数据模型。
- 不调整无 Dock 页面或 Bottom Sheet 的 Reka 展示规则。

## 设计

### 1. Reka 拖拽与形态切换分离

`ShellDitheredReka` 继续作为唯一真实渲染器。位置策略分为两类：

- `today + dragging/settling`：视觉中心直接读取 `TodayRekaMotionController.rekaCenter`，不使用隐式位置补间。拖动必须逐帧跟手；松手后的惯性仍由 motion controller 驱动。
- `today <-> dock`：仅 mode 变化时执行 260ms 的位置和缩放 handoff。

首页场景仍负责首页命中和手势识别，Shell 负责唯一视觉渲染。测试必须覆盖真实 Shell 组合，而不只覆盖独立的 `TodayRekaScene`，防止命中层与视觉层再次失配。

### 2. Dock Reka 避让区

Dock Reka 保持 overlay，不改变页面正文的 bottom clearance，也不在 Dock 中新增占位。

`ShellDitheredReka`/Dock chrome 提供一个共享的 bottom overlay exclusion extent，表示 Dock Reka 实际可见区域及最小间距。日历 Flow 的“回到今天”属于底部悬浮操作，出现时将 bottom offset 增加该 exclusion extent，放在 Reka 上方。

这样正文布局不被挤开，但两个可操作悬浮层不会重叠，点击区域也不会互相截获。

### 3. 新资产的物理接管边界

生成动画仍保留 charge、emit、handoff、recover 四个阶段，但渲染所有权在资产球首次完整进入 asset chamber 时切换：

1. `TodayOutputOverlay` 从 Reka 出发，把资产球移动到 asset chamber 的入口边界。
2. 到达边界时发送包含 chamber-local center 和下降速度的 `TodayAssetHandoff`。
3. `TodayOutputCoordinator` 在 handoff 后允许该资产进入 stable asset 集合。
4. Overlay 在 handoff 后不再绘制该资产球，避免双重渲染。
5. `ThemeV2AssetBubbleField` 使用 handoff center/velocity 创建真实 Forge2D body；从该帧开始，重力、球体碰撞和边界碰撞全部生效。
6. Reka 的 recover 动画和后续队列可以继续，不再决定资产物理接管时机。

接管位置按球半径夹紧在 chamber 内，避免初始 body 与顶边重叠。快速下落 body 保持 continuous collision，防止穿透已有小球。

### 4. 速度驱动的 dither 扩散

现有 dither source 的 `energy` 只对压力强度做很小的增益，且很快被 clamp，肉眼差异不足。

资产区域将把速度映射为独立的视觉 spread：

- 静止或休眠球保持现有半径和低能量。
- 移动球根据线速度增加有限的外围 feather/spread，不改变真实物理半径和命中区域。
- 被用户拖动的球使用最大但受限的 spread。
- spread 平滑受限，避免高速生成球造成大面积闪烁。
- reduce-motion 模式固定为静态扩散。

Shader 与 Canvas fallback 使用同一压力函数语义，确保真机 GPU 渲染和测试/降级路径一致。

## 状态与数据流

```text
手指拖动 -> TodayRekaScene gesture -> TodayRekaMotionController
          -> ShellDitheredReka 直接定位 -> 视觉逐帧跟手

新资产 -> OutputOverlay(charge/emit)
       -> 到达 asset chamber 边界
       -> TodayAssetHandoff(center, velocity)
       -> Coordinator 暴露资产 + Overlay 停止绘制
       -> BubbleField 创建 body
       -> 下坠、碰撞、速度驱动 dither spread
```

## 错误与降级

- 若 handoff 数据缺失，资产仍按 BubbleField 的确定性默认 spawn 位置创建，不丢失资产。
- 若动画被系统 reduce-motion 禁用，资产直接在 chamber 内创建静态布局，不播放下坠。
- 页面失活、应用进入后台或资产被删除时，沿用现有取消、清理和 spawn-state pruning。
- Dock Reka handoff 期间继续禁用交互，避免导航动画中误触。

## 测试与验收

先增加会失败的回归测试，再修改实现：

1. Shell 组合测试：拖动 90px 后，视觉中心在同一帧与 controller/命中中心一致；松手不出现补间追赶。
2. 日历布局测试：“回到今天”矩形与 Dock Reka 的可见区域、72px 交互区域均不相交，并可点击。
3. Output/physics 测试：资产在 asset chamber 顶部完成 handoff；handoff 后 Overlay 不再绘制资产，BubbleField 已包含带下降速度的 body。
4. 碰撞测试：新资产在到达 floor 前与路径中的已有资产球发生碰撞并改变至少一个 body 的速度/轨迹。
5. Dither 测试：移动球的视觉 spread 明显大于静止球；物理半径和命中尺寸不变；fallback 与 shader source 参数一致。
6. Reduce-motion、生命周期、导航 handoff 和现有 Theme V2 全量测试保持通过。
7. Flutter analyzer 通过，并在已连接 Android 真机安装验证四项行为。

## 风险控制

- 物理接管只移动“所有权边界”，不引入第二套物理引擎。
- Dock exclusion 使用共享常量/几何方法，避免日历写死与 Reka 尺寸不一致的 magic number。
- dither spread 有最大值，并继续受 24 个 source 上限约束。
- 保留现有资产 ID 去重与 spawn state 只消费一次的规则，避免重复 body。
