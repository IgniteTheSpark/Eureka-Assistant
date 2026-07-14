# Ring Demo 设计

日期：2026-07-14  
状态：待评审

## 1. 背景

Eureka Assistant 已经包含三块可复用能力：

- `backend/`：FastAPI、Flash Pipeline、Skills、JWT 用户体系和 MySQL 数据库。
- `ring-desktop/`：macOS BLE 连接、戒指音频、ASR、手势、前台 App 识别和震动。
- `mobile/`：现有 UReka 产品客户端和资产渲染规则，可作为数据语义参考，但不直接承载本次桌面网页 Demo。

本次新增一个独立的 `ring-demo/` Web 应用，用于展示戒指产品，并在同事的 Mac 上通过本地服务完成真实 Flash 和 Vibe 演示。

## 2. 目标

- 提供一个大尺寸产品 Banner 首页。
- 在首页 Banner 下提供 Flash Mode 和 Vibe Mode 两个大型 Demo 入口。
- Flash Mode 跑通“戒指语音 → ASR → Agent/Skills → 真实资产”的闭环。
- Vibe Mode 跑通“戒指语音/手势 → Codex 或钉钉”的真实桌面交互。
- Flash 和 Vibe 严格互斥，避免 Vibe 输入进入 Flash Pipeline。
- 复用当前 Backend、MySQL、Session、Assets、Contacts、Events 和 Skills，不建立 Demo 专用数据库。
- 支持同事 clone 仓库、配置本地 API Key 后在 macOS 上启动。
- 首版只使用简单、稳定的页面过渡和状态动画，优先保证全链路可运行。

## 3. 非目标

- 不支持 Windows。
- 不部署远端 Backend 或数据库。
- 不演示 Claude。
- 不在 Demo 中实现通用手势编辑器。
- 不展示失败震动或以失败场景作为演示内容。
- 不承诺长按手势、区域感知、健康能力或所有 App 通用。
- 不在首版完成安装包签名、自动更新或生产级隐私方案。
- 不把某一种资产卡片作为 Flash Demo 的核心卖点。

## 4. 总体架构

```text
Ring
  ↓ BLE / audio / gestures
Ring Desktop (127.0.0.1:17863)
  ├─ Flash: SSE transcript/status → ring-demo
  └─ Vibe: frontmost app mapping → Codex / DingTalk

ring-demo (React + TypeScript + Vite)
  ├─ local Ring Desktop control API
  └─ POST /api/flash → existing Backend

Backend (localhost:8000)
  └─ existing MySQL 8 volume
       ├─ sessions / input_turns / messages
       ├─ assets / asset_fields
       ├─ contacts
       └─ events
```

### 4.1 组件职责

#### `ring-demo/`

- 产品 Banner、Demo 入口和两个 Mode 页面。
- 管理本机 JWT 登录状态。
- 连接 Ring Desktop 本地 API 和 SSE 事件流。
- 在 Flash Mode 收到最终 transcript 后调用现有 `POST /api/flash`。
- 渲染同步返回的 `reply`、`summary`、`cards` 和 `derived_assets`。
- 不直接访问数据库，不持有 LLM/ASR API Key。

#### `ring-desktop/`

- 继续作为 BLE、录音、ASR、手势和前台 App 映射的唯一所有者。
- 新增 Demo Session、Mode、Generation 和事件发布能力。
- Flash Mode 只发布 transcript，不直接依赖 Eureka Backend 或 JWT。
- Vibe Mode 只把动作交给当前前台 Codex/钉钉。

#### `backend/`

- 保持 `POST /api/flash` 为唯一 Flash 文本处理入口。
- 保持现有 JWT 用户隔离。
- 保持当前 Flash Session、Input Turn、消息和资产落库语义。
- 首版不新增 Demo 专用表和 Demo 专用资产接口。

## 5. 数据与资产库

Demo 使用真实 UReka 数据链路，不生成只存在于浏览器内的假资产：

1. 用户第一次使用 Demo 时，通过现有 `/api/auth/register` 或 `/api/auth/login` 登录。
2. 注册继续调用现有 `provision_user_skills`，为该用户配置基础 Skills。
3. Flash transcript 以 `source: "voice"` 调用 `/api/flash`。
4. Backend 获取或创建当天的 Flash Session。
5. Backend 创建 Input Turn 和用户消息，运行 Flash Pipeline。
6. 各 Skill 按当前实现写入 Assets、Contacts、Events 等正式表。
7. Demo 渲染接口返回值；同一结果也可以在原 UReka 资产库中查询到。

后续增加更多 Skills 时，主要改动在现有 Backend Skill 注册、Dispatcher 和 Render Spec，不改变 Demo 的主流程。无法归类或尚无专属渲染的内容使用“随记”兜底。

## 6. 页面结构

### 6.1 首页 `/`

首页由两部分组成：

1. 大尺寸 Hero/Banner：戒指产品视觉、产品定位和简短说明；首版允许使用高质量占位视觉。
2. 两个大型 Demo Block：Flash Mode 和 Vibe Mode，各包含一句介绍和明确入口。

首页不是 Step-by-step 教程，不放操作步骤条。戒指 BLE 连接在 Mode 页面处理；从 Mode 返回首页时保持物理连接，但 Ring Desktop 进入 Demo `idle`。

### 6.2 Flash 页面 `/flash`

页面包含：

- 返回首页。
- 戒指连接控制和实时连接状态。
- 当前模式标识。
- 一个统一的 Flash 体验画布。
- 当前 transcript、Agent 处理状态和本轮生成结果。
- 可选的本次 Session 最近结果区域，不承担完整资产库功能。

进入页面时激活 `flash`；离开页面、浏览器返回或关闭时释放/闲置当前 Demo Mode。

### 6.3 Vibe 页面 `/vibe`

页面包含：

- 返回首页。
- 戒指连接控制和实时连接状态。
- Codex、钉钉两种支持能力的简短说明。
- 当前识别到的前台 App。
- 当前生效的动作映射。
- 当前 Ring Desktop 是否已准备好接管语音和手势。

用户自行打开并操作真实 Codex 或钉钉。网页不控制 App 内部状态，也不判断消息是否发送或任务是否成功。

进入页面时激活 `vibe`；离开时进入 Demo `idle`。

## 7. Mode 与路由隔离

### 7.1 内部状态

Ring Desktop 增加以下内部模式：

- `standalone`：没有活跃 Demo Session，保持当前桌面端行为。
- `idle`：Demo Session 存在，但用户位于首页。
- `flash`：语音只交给 Demo Web。
- `vibe`：语音和手势只交给前台 Codex/钉钉。

用户界面只展示 Flash 和 Vibe；`standalone`、`idle` 是底层状态。

### 7.2 Demo Session Lease

- Web 打开时创建随机 `sessionId` 并向 Ring Desktop 注册。
- Web 定期发送 heartbeat。
- Ring Desktop 保存 Session lease；超时后自动退出 Demo Session并恢复 `standalone`。
- 页面关闭、浏览器崩溃或网络中断不会让戒指永久停留在 Flash Mode。

### 7.3 Generation

- 每次 Mode 或 Demo Session 改变时递增 `generation`。
- 录音开始时记录 `sessionId + mode + generation`。
- ASR 完成后再次校验三者。
- 校验失败的旧结果直接丢弃，不进入任何下游。

如果 transcript 已经由 Web 正式提交到 `/api/flash`，之后切换页面不取消已开始的 Backend 请求。资产允许在后台完成，但不得突然覆盖 Vibe 页面；返回 Flash 页面后可以重新获取或显示本地保留的结果。

## 8. Ring Desktop 本地 API

在现有 `127.0.0.1:17863` Control API 上扩展：

```text
GET  /connection
POST /connection/scan
POST /connection/connect
POST /connection/disconnect

GET  /demo/status
POST /demo/session
POST /demo/heartbeat
POST /demo/mode
POST /demo/release
GET  /demo/events        # SSE
```

建议请求字段：

```json
{
  "sessionId": "browser-generated-uuid",
  "mode": "idle | flash | vibe"
}
```

`GET /demo/status` 返回连接、模式、Generation、录音/ASR 状态、当前前台 App 和当前映射的可序列化快照。

SSE 事件至少包含：

- `connection.changed`
- `mode.changed`
- `recording.started`
- `recording.stopped`
- `asr.started`
- `transcript.ready`
- `active_app.changed`
- `mapping.changed`

Control API 继续只监听 `127.0.0.1`，并为本地 Demo Origin 添加必要的 CORS 响应头。

## 9. Flash 交互状态

Flash 页面是一个持续变化的画布，不显示线性 Stepper。内部状态如下：

```text
disconnected
  → ready
  → listening
  → transcribing
  → processing
  → revealed
  → ready
```

### 9.1 Ready

- 显示戒指已连接和一个安静的待机视觉。
- 不放大“双击”动作，也不把动作说明做成页面中心。

### 9.2 Listening

- 第一次双击开始录音。
- 页面通过 Ring Desktop 事件进入 Listening。
- 使用简单的呼吸、波形或光晕效果表达正在接收声音。

### 9.3 Transcribing

- 第二次双击停止录音。
- Ring Desktop 解码并执行 ASR。
- 页面保持连续的中间态，不使用阻塞式弹窗。

### 9.4 Processing

- Web 收到 `transcript.ready`，校验 Session/Generation 后调用 `/api/flash`。
- 页面显示 transcript 和统一的 Agent 处理视觉。
- `/api/flash` 当前为同步接口，首版不伪造具体 Skill 的实时进度。

### 9.5 Revealed

- 展示 `reply/summary` 和一个或多个 Cards。
- 对已支持类型使用专属渲染；其他类型使用通用 Asset Card。
- 无法归类时以“随记”呈现。
- 一句话产生多项内容时，卡片以短暂错峰动画出现。

## 10. Vibe 交互

Vibe Mode 不要求用户在网页中选择终端。Ring Desktop 根据 macOS 前台 Bundle ID 自动选择：

- Codex：`com.openai.codex`
- 钉钉：`com.alibaba.DingTalkMac`

首版预设映射沿用当前配置：

- 双击：语音录入/结束。
- 三击：Enter。
- 上/下：按对应 App 的现有滚动或按键映射。

不使用当前戒指未稳定上报的长按。Codex 已有的任务完成正向震动可以继续工作；失败震动不在 Demo 页面和演示脚本中呈现。

当其他 App 位于前台时，页面显示“打开 Codex 或钉钉以启用映射”，不把动作误发给 Flash。

## 11. 视觉与动效边界

首版优先使用 React + CSS 完成简单效果：

- 首页 Banner 的轻微入场和背景层次。
- 两个 Demo Block 的 hover、focus 和进入过渡。
- Mode 页的淡入/淡出。
- Flash Listening 呼吸/波形、Processing 循环和 Cards stagger。
- Vibe 当前 App 状态的平滑切换。

首版不引入复杂 3D 戒指、重型 Shader 或长时间编排动画。视觉结构应为后续升级保留空间。

## 12. 登录与本地配置

- Demo 复用现有 email/password JWT 接口，不增加免鉴权 Backend 路径。
- 主演示页面不长期显示登录 UI。
- 首次使用或 Token 失效时进入轻量本地 Setup/Login 覆盖层。
- JWT 只保存在本机浏览器存储中。
- DeepSeek、OpenRouter 等 Key 继续只配置在仓库根目录 `.env`，不得进入 `ring-demo` 或浏览器 Bundle。
- 新同事可以注册本机 Demo 用户；用户注册时自动 provision 基础 Skills。

最终 README 应提供：环境检查、`.env` 配置、数据库 migration/seed、Ring Desktop 权限和启动顺序。后续实现一个仓库级 Demo 启动脚本，减少手动启动多个进程的成本。

## 13. 异常处理

- Backend 离线：Flash 页面保持可恢复状态，提示本地服务未启动，不触发 Vibe 路由。
- Ring Desktop 离线：Mode 页面显示本地 Ring 服务未运行，并提供启动说明。
- 戒指断开：保留当前页面和已生成资产，连接组件进入可重连状态。
- ASR 空结果：回到 Ready，使用低干扰提示，不创建资产。
- `/api/flash` 失败：不触发失败震动；保留 transcript 并允许重新提交。
- SSE 断开：自动重连并通过 `/demo/status` 恢复快照。
- JWT 失效：进入 Setup/Login 覆盖层，成功后恢复当前页面。
- 不受支持的前台 App：Vibe 不执行映射，只更新状态提示。

## 14. 验证

### 14.1 自动测试

- Ring Desktop：Mode 状态机、Session lease、Generation 丢弃、Flash/Vibe 路由、SSE 事件和原 standalone 行为回归。
- Demo Web：路由、JWT、Ring API client、Flash 状态 reducer、通用 Card fallback 和 Mode 释放。
- Backend：复用现有 Flash/API 测试，并增加 Demo 请求契约覆盖（`source=voice`、cards/derived_assets）。
- 无硬件模拟：可以向 Demo Event 层注入连接、录音、ASR 和前台 App 事件，跑通 UI。

### 14.2 Mac 真机检查

1. 启动 MySQL、Backend、Ring Desktop 和 Demo Web。
2. 在 Flash 页面扫描并连接真实戒指。
3. 双击开始、双击结束，确认 transcript 只进入 Flash。
4. 确认 `/api/flash` 返回并在页面展示结果。
5. 确认资产同时出现在现有 UReka 资产库/日历/联系人数据中。
6. 返回首页并进入 Vibe。
7. 打开 Codex，验证语音、Enter 和滚动映射。
8. 打开钉钉，验证对应映射。
9. 在录音或 ASR 中途切换/返回，确认旧结果不会进入错误模式。
10. 关闭浏览器，确认 lease 超时后 Ring Desktop 恢复 standalone。

## 15. 首版交付顺序

1. 建立 `ring-demo/` React/TypeScript/Vite 工程和页面路由。
2. 完成首页 Banner、两个 Demo Block 和简单页面过渡。
3. 扩展 Ring Desktop Demo Session、Mode、Generation、状态 API 和 SSE。
4. 完成共享戒指连接组件。
5. 跑通 Flash 录音、ASR、JWT、`/api/flash` 和通用资产展示。
6. 跑通 Vibe 的 Codex/钉钉前台识别和映射状态。
7. 增加模拟测试、全链路测试和真实戒指验证。
8. 补充同事本地 Setup/Run 文档与启动脚本。

