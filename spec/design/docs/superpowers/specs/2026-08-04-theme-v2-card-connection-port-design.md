# Theme V2 卡片连接成熟流程复刻设计

> 日期：2026-08-04
> 状态：已完成交互确认，等待书面规格审核
> 范围：录音卡扫描、绑定和恢复流程，卡片与戒指产品图，以及 Theme V2 设备选择、配对和详情呈现

## 1. 目标

Theme V2 以 `bizcard-flutter` 中已经过产品和真机验证的录音卡连接实现为参考，完整复刻其行为，而不是只借鉴视觉。

复刻后的体验必须满足：

- 第一层设备选择只有“录音卡”和“戒指”两个类别。
- 用户不需要预先判断 W1 或 W2；型号由扫描结果自动识别。
- 录音卡连接遵循成熟版的权限检查、扫描、绑定预检、绑定参数复用、BLE 连接、服务端绑定和失败回滚顺序。
- Theme V2 继续使用自己的认证和 `/api/cards/*` 接口，不依赖另一个 App 的网络层或状态管理库。
- 卡片使用 `bizcard-flutter` 中的 W1/W2 产品图；戒指使用用户提供的 `5.png`。
- 不改动硬件录音、音频传输、ASR、Capture 或 Agent 流程。

## 2. 参考实现与复刻边界

### 2.1 录音卡参考实现

行为来源以以下文件为准：

- `bizcard-flutter/lib/feature/device/searchv2/connect/device_searchv2_connect_vm.dart`
- `bizcard-flutter/lib/feature/device/searchv2/device_searchv2_flow.dart`
- `bizcard-flutter/lib/feature/device/searchv2/connect/dialog/dsc_device_sheet.dart`
- `bizcard-flutter/lib/feature/device/searchv2/connect/widget/dsc_guide_carousel.dart`
- `bizcard-flutter/lib/func/ble/ble_manager.dart`
- `bizcard-flutter/lib/feature/device/info/device_info_vm.dart`
- `bizcard-flutter/lib/feature/device/info/dialog/di_unbind_dialog.dart`

### 2.2 复刻原则

复刻的是状态机、调用顺序、恢复行为和用户交互，不直接跨仓库导入 Dart 文件。

以下内容不能直接搬运：

- `signals_flutter` ViewModel 结构。
- `MeetingApiService` 和旧版 V4 接口模型。
- `go_router` 页面栈实现。
- 旧项目的颜色、文字、埋点和国际化基础设施。
- 服务端优先的旧解绑顺序。

Theme V2 保持当前硬件所有权边界：

| 能力 | 所有者 |
|---|---|
| 卡片 BLE SDK 调用 | 卡片 BLE gateway |
| 卡片绑定业务状态机 | 新的卡片连接 workflow |
| Theme V2 页面状态与入口 | `DeviceController` |
| 卡片绑定记录 | Theme V2 `/api/cards/*` |
| 静默重连 | `DeviceSilentReconnect` |
| 戒指连接 | 现有戒指 SDK、`RingConnection`、`RingReconnect` |

## 3. 组件设计

### 3.1 `CardConnectionWorkflow`

新增一个只负责录音卡连接业务顺序的 workflow。它不持有 Flutter `BuildContext`，也不直接展示 Toast、Dialog 或页面。

内部状态至少区分：

```text
idle
→ preparing
→ scanning
→ deviceFound
→ preflighting
→ bleConnecting
→ serverBinding（仅新绑定或重新绑定）
→ connected
```

异常进入可恢复错误状态；退出配对页面或开始新的连接任务会取消旧任务，旧任务不得覆盖新状态。

### 3.2 `CardBleGateway`

封装 `br_flutter_plugin_ble`，向 workflow 暴露：

- 初始化 SDK。
- 检查和申请权限。
- 读取蓝牙状态。
- 订阅蓝牙状态变化。
- 开始和停止绑定扫描。
- 订阅发现设备。
- 连接设备。
- 硬件解绑并选择是否删除录音。
- 刷新或清理原生绑定缓存。
- 读取已连接设备、电量和存储。

Android 与 iOS 的 SDK 初始化、权限和扫描差异只能存在于 gateway 内。

### 3.3 `CardBindingGateway`

适配 Theme V2 服务端接口：

- `POST /api/cards/binding-info`
- `POST /api/cards/bindings`
- `GET /api/cards/bindings`
- `POST /api/cards/{binding_id}/unbind`

它把接口结果转换为明确的绑定状态，不把原始 JSON 判断散落在 UI 或 workflow 中。

### 3.4 `DeviceController`

`DeviceController` 继续作为 Theme V2 UI 使用的统一门面，负责：

- 暴露扫描结果、连接状态、已连接设备和错误。
- 把页面操作转发给 workflow。
- 把 workflow 的细分状态折叠为现有 Theme V2 展示状态。
- 与 `DeviceSilentReconnect` 协调手动配对期间的暂停和恢复。

`DeviceController` 不再自行拼接绑定预检、BLE 连接和服务端绑定步骤。

### 3.5 `CardModelResolver`

型号解析只读取设备广播名称或服务端保存的原始 `card_name`：

- 明确包含 W1 标识时解析为 W1。
- 明确包含 W2 标识时解析为 W2。
- 无法识别时解析为 unknown，并使用 W2 作为视觉降级，不改变连接逻辑。

显示昵称与原始型号字段必须分离。不能因为 `card_nick` 是“UReka 录音卡”而丢失 W1/W2 型号。

## 4. 产品图片

### 4.1 录音卡

从 `bizcard-flutter/assets/images/` 复用：

- `img_device_connect_guide_1_1.png`：W1 开机/未连接状态。
- `img_device_connect_guide_1_2.png`：W1 蓝牙连接状态。
- `img_device_connect_guide_2_1.png`：W2 开机/未连接状态。
- `img_device_connect_guide_2_2.png`：W2 蓝牙连接状态。

素材复制进 Theme V2 自己的资源目录，不建立运行时跨仓库依赖。

### 4.2 戒指

戒指使用：

`/Users/admin/硬件相关/录音戒指概念图/5.png`

它覆盖：

- 设备类别选择页。
- 戒指搜索连接页。
- 戒指设备详情页。

顶部全局导航继续使用简洁戒指图标。

应用内使用一份仅裁去透明留白的副本，以保证不同尺寸下的可视面积；不得修改戒指本体、颜色、材质或视角，原始文件保持不变。

## 5. 用户交互

### 5.1 第一层设备选择

页面只有两个入口：

1. 录音卡。
2. 戒指。

录音卡入口使用 W1 与 W2 并置或轻微叠放的组合示意图，表达这是一个设备类别，不要求用户选择型号。戒指入口使用指定戒指图片。

### 5.2 录音卡扫描引导

选择录音卡后立即准备 SDK 并开始扫描。

页面保留成熟版的两步自动轮播结构：

1. 开启设备：组合展示 W1 `_1` 与 W2 `_1` 图片。
2. 开始蓝牙配对：组合展示 W1 `_2` 与 W2 `_2` 图片。

顶部展示当前搜索状态。蓝牙关闭、权限缺失或扫描失败时，不能继续显示无限搜索动画。

### 5.3 发现设备面板

扫描发现一个或多个设备后显示确认面板：

- 扫描结果按 SN 去重。
- 已出现的设备保持首次发现顺序，新设备追加在末尾。
- 同一 SN 的名称、MAC 或 BLE identifier 更新时更新原位置，不重排。
- 每行展示自动识别出的 W1/W2 图片、设备名称和 SN。
- 面板打开期间新发现设备可以增量加入。
- 连接期间禁止再次点击其他设备。
- 连接成功后关闭面板并进入录音卡详情。
- 用户关闭发现面板时结束当前配对流程；再次进入时重新扫描。

### 5.4 戒指配对

戒指继续使用现有扫描、发现、连接与保存 `ring_mac` 的流程。页面和发现面板使用指定戒指图片，不把卡片 workflow 应用于戒指。

### 5.5 设备详情

- 卡片详情依据真实型号展示 W1 或 W2 图片。
- 未知卡片型号使用 W2 图片作为视觉降级。
- 戒指详情展示指定戒指图片。
- 详情保留 Theme V2 的连接状态、基本信息和解除绑定操作。
- 全局顶部导航只显示紧凑图标，不显示产品大图或已连接文字。

## 6. 录音卡扫描状态机

### 6.1 开始扫描

```text
暂停静默重连
→ 记录用户仍希望扫描
→ 初始化原生 BLE SDK
→ 检查平台权限
→ 检查蓝牙状态
→ 订阅蓝牙与发现设备事件
→ 开始绑定扫描
```

Android 先检查权限，必要时由原生 SDK 申请。iOS 先初始化 SDK，再确认蓝牙为 `poweredOn`。

保留成熟版的 iOS 续扫兼容逻辑：扫描调用完成但用户仍在扫描页、未开始连接且未发现目标时，可以按插件验证过的短间隔继续扫描。该逻辑不能在 Android 重复触发。

### 6.2 蓝牙状态变化

- `poweredOff`：停止底层扫描，但保留用户扫描意图并显示“请开启蓝牙”。
- `poweredOn`：若页面仍在、仍有扫描意图且没有连接任务，自动重新开始扫描。
- `unauthorized`：停止扫描并显示权限错误，不循环申请权限。

### 6.3 生命周期

- 页面离开时停止扫描、取消订阅和轮播计时器。
- 切换到戒指时停止卡片扫描。
- 开始连接时停止卡片扫描，避免 SDK 竞争。
- 连接失败且允许重试时恢复扫描。

## 7. 录音卡绑定状态机

### 7.1 连接前预检

用户选择设备后：

1. 锁定连接任务，忽略重复点击。
2. 使用 SN 请求 `/api/cards/binding-info`。
3. 根据返回状态决定下一步。

| 服务端状态 | 行为 |
|---|---|
| `bound_by_other` | 在 BLE 连接前终止并提示设备已被其他账号绑定 |
| `bound_by_me` | 复用当前绑定的 app UUID 和 device UUID |
| `previously_bound_by_me` | 复用最近历史绑定的连接参数，BLE 成功后重新激活服务端绑定 |
| `never_bound_by_me` | 生成新的 app UUID，BLE 成功后创建服务端绑定 |

### 7.2 BLE 连接

向 SDK 传入：

- 扫描结果中的 SN。
- card MAC。
- iOS BLE identifier（存在时）。
- 预检得到或新生成的 app UUID。
- 已绑定或历史绑定的 device UUID（存在时）。

SDK 返回值用于解析真实 SN、设备名称、device UUID、app UUID 和 card MAC。字段解析需要兼容插件现存的大小写与别名。

### 7.3 服务端绑定

- `bound_by_me`：BLE 成功即视为连接成功，使用 `current_binding` 构造设备信息，不重复 POST 绑定。
- `previously_bound_by_me`：BLE 成功后 POST `/api/cards/bindings`，重新激活绑定。
- `never_bound_by_me`：BLE 成功后 POST `/api/cards/bindings`，创建绑定。

服务端绑定成功后，用返回的规范绑定数据刷新原生绑定缓存，再进入 connected。

### 7.4 服务端绑定失败回滚

如果 BLE 已成功但服务端绑定失败：

```text
硬件 unbind(deleteAudio: false)
→ 清除本次临时连接态
→ 保留设备中的录音
→ 显示服务端绑定失败
→ 恢复扫描
```

回滚不得调用删除录音选项。回滚失败可以记录诊断信息，但不能把本次连接显示为成功。

## 8. 错误映射与恢复

需要保留成熟版的可理解错误：

| 场景 | 用户结果 |
|---|---|
| 蓝牙权限缺失 | 提示开启蓝牙权限，可重新触发权限流程 |
| 蓝牙未开启 | 提示开启蓝牙，开启后自动续扫 |
| 设备地址无效 | 提示重新扫描 |
| 被其他账号绑定 | 明确提示不可绑定，不调用 BLE connect |
| BLE 连接失败 | 显示连接失败并恢复扫描 |
| 登录过期 | 提示重新登录，不进行硬件绑定 |
| 服务端绑定失败 | 保留录音地硬件回滚并恢复扫描 |
| 页面已退出或旧任务返回 | 忽略旧结果，不覆盖当前页面状态 |

错误恢复不能启动第二个并行连接任务，也不能与静默重连同时占用 BLE SDK。

## 9. 解绑边界

连接流程以 `bizcard-flutter` 为参考实现完整复刻；解绑继续保留 Theme V2 当前更可靠的顺序：

```text
停止静默重连
→ 硬件解绑（保留或删除录音）
→ 清理原生绑定缓存和本地连接态
→ 异步同步 Theme V2 服务端
```

硬件解绑成功而服务端同步失败时，本地不得恢复为已连接；只重试服务端同步。此次工作不能退回旧项目“服务端成功后才执行硬件解绑”的实现。

## 10. 自动化测试

### 10.1 Workflow 单元测试

使用记录调用顺序的 fake gateway 覆盖：

1. 新设备完整连接和服务端创建绑定。
2. 当前账号已绑定时复用参数，BLE 成功后不重复 POST。
3. 历史绑定时复用参数并重新激活绑定。
4. 他人绑定时不调用 BLE connect。
5. 服务端绑定失败时调用 `unbind(deleteAudio: false)` 并恢复扫描。
6. 回滚失败时仍不进入 connected。
7. 重复点击只产生一个连接任务。
8. 页面退出或 revision 变化后忽略旧异步结果。
9. 蓝牙关闭后保留扫描意图，恢复后续扫。
10. Android 与 iOS 权限和初始化顺序。

### 10.2 扫描和型号测试

1. 按 SN 去重。
2. 同一 SN 更新原位置且不重排。
3. 新设备追加在首次发现顺序末尾。
4. W1 广播名称映射 W1 图片。
5. W2 广播名称映射 W2 图片。
6. 未知型号使用 W2 视觉降级。
7. 原始型号字段不被显示昵称覆盖。

### 10.3 Widget 测试

1. 第一层只有“录音卡”和“戒指”。
2. 录音卡入口显示 W1+W2 组合示意。
3. 两步配对引导分别显示两型号的对应图片。
4. 发现面板显示多台设备并能增量更新。
5. 连接期间控件不可重复触发。
6. 卡片详情显示正确型号图片。
7. 戒指选择、搜索和详情均显示指定图片。
8. 顶部导航仍使用小图标。

### 10.4 服务端契约

现有 `/api/cards/*` 契约继续覆盖：

- 从未绑定。
- 当前账号已绑定。
- 当前账号历史绑定。
- 被其他账号绑定。
- 同账号重新绑定更新或重新激活。
- 幂等解绑。

若实现不需要修改服务端响应结构，不新增服务端架构。

## 11. 真机验收

Android 真机至少完成：

1. 第一层仅看到录音卡和戒指两个类别。
2. 录音卡入口和扫描页展示 W1+W2 组合图。
3. 扫描列表为现场可用的 W1/W2 显示正确图片和 SN；若现场只有一种型号，另一种由自动化测试验证。
4. 连接一张真实录音卡并进入正确型号详情。
5. 录音、音频同步、ASR 和 Capture 流程不受影响。
6. 强制停止 App 后重启，已绑定卡通过原有静默重连恢复。
7. 模拟或触发服务端绑定失败，确认硬件回滚时不删除录音且重新扫描。
8. 戒指选择、扫描和详情使用指定戒指图片。
9. 连接戒指后，原有硬件触发与音频流程仍可用。

iOS 至少完成自动化顺序测试；有可用真机时再验证 SDK 初始化、蓝牙状态和续扫行为。

## 12. 非目标

- 不把 `bizcard-flutter` 作为运行时依赖。
- 不合并卡片和戒指的 SDK 或控制器。
- 不修改硬件录音、音频上传、ASR、Agent 或 Report。
- 不增加卡片固件升级、录音模式或 USB 设置。
- 不重写 Theme V2 服务端认证和卡片数据模型。
- 不改变全局顶部导航的紧凑图标设计。
- 不在未明确授权时执行“解绑并删除录音”的真机操作。
