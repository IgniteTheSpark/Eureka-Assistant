# Ring-desktop 设计 spec

把勇芯智能戒指（BraveChip ChipletRing）做成 **Mac 输入设备**：触控手势 + 语音，按「当前聚焦的 app」路由成动作。本仓库是一个 **desktop app**，既是戒指的**连接管理**，也是**配置中台**。

本期目标：**Python demo**，先把"连接 + 按 app 配手势 + 注入"闭环跑通（含语音听写），后续逐步迭代/产品化。

> 本目录现已并入 Eureka Assistant。戒指手机端接入位于 `../mobile/`；
> Mac 端仍保持独立运行，不依赖手机。

---

## 1. 已验证的事实（2026-06-25 实测，可行性已坐实）

| 项 | 结论 |
|---|---|
| 硬件手势 | 8 个全支持：`0长按 1单击 2双击 3三击 4上滑 5下滑 6左滑 7右滑`（UReka 调试页实测）|
| Mac 直连 | **无需官方 SDK**，`bleak` 直连即可收到手势；连接稳（实测 3 分钟零掉线，**不用做保活**）|
| 手势报文 | 特征 `bae80011-4f05-4503-8e65-3af1f7329d1f`，5 字节 `00 09 61 00 <code>`，末字节=手势码 |
| 心跳 | `00 2a 12 00 29`，每 30s 一次（疑似电量/状态），**忽略** |
| 音频 | 双击后自动涌出 `00 09 71 08 64 00 <seq> …`（len=110，ADPCM）——**我们没发任何命令，光双击就来了** |

含义：手势通道**明文**；AES 只用于"app→戒指"的命令（`CMDUtils`，会话密钥握手得到），我们只"收"不"发"，第一期不碰。

---

## 2. 核心心智模型：app 是「路由器」，动作落到聚焦软件

```
戒指(BLE notify) ──► Ring-desktop 后台
                       │  ① 解析报文：手势码 / 音频帧 / 心跳
                       │  ② 查"当前最前台 app 的 bundle id"(NSWorkspace)
                       │  ③ 按【该 app 的配置档】把这个手势/语音翻译成动作
                       └─► ④ 把按键 / 媒体键 / 文字 注入给【当前聚焦的软件】
```

- **语音**：双击起录 → 转写 → **文字直接打进当前聚焦软件**（如 Claude 的输入框）。app 自己不留存文字，是个透明的"听写引擎"。
- **触控按 app 区分**：macOS `NSWorkspace.frontmostApplication.bundleIdentifier` 实时给出前台 app；同一手势在不同 app 触发不同动作。
- "语音"本身就是一种可绑定的**动作类型**，所以"双击=语音听写"可以只在某些 app 启用。

---

## 3. 架构与组件（Python）

| 模块 | 文件 | 职责 | 依赖 |
|---|---|---|---|
| BLE 代理 | `ble.py` | 扫描/连接戒指、订阅 `bae80011`、掉线重连兜底 | `bleak`（已验证）|
| 报文解析 | `gestures.py` | `00 09 61 00 <code>`→手势码；区分音频`09 71`/心跳`2a 12` | — |
| 前台监听 | `frontmost.py` | 当前最前台 app 的 bundle id | `pyobjc`(AppKit `NSWorkspace`) |
| 动作派发 | `actions.py` | key / media / text / script / voice 注入聚焦窗口 | `pynput` 或 Quartz `CGEvent` |
| ASR | `asr.py` | 复用 UReka 后端同步 ASR（见 §6）| `httpx` |
| 音频(M2) | `audio.py` | 累积 ADPCM→解码 PCM→WAV(8k mono) | — |
| 配置 | `config.py` | per-app `手势→动作` JSON 读写 | — |
| 主程序 | `app.py` | 串联事件循环 | — |
| 菜单栏 | `menubar.py` | 常驻状态灯：连接/电量、快速连断、"打开配置" | `rumps` |
| 配置窗 | `ui/` | 连接管理 + per-app 配置 + 实时手势指示（按需弹出）| `pywebview`（HTML 前端）|

UI 形态（demo，已定）：**`rumps` 菜单栏常驻**——状态灯(连接/电量)、快速连/断、"打开配置"；**`pywebview` 配置窗**(从菜单栏按需弹出)三块——**连接**(扫描/电量/状态)、**配置**(选 app→给每个手势配动作)、**实时测试**(显示最近手势码)。

---

## 4. 配置数据模型

手势 key：`longPress(0) single(1) double(2) triple(3) up(4) down(5) left(6) right(7)`。
动作 `type`：`key`（组合键）/ `media`（系统媒体键）/ `text`（打固定文字）/ `script`（shell/AppleScript）/ `voice`（语音听写）。

```jsonc
{
  "default": {                                   // 未配置的 app 走这个
    "triple":     { "type": "key", "value": "enter" },
    "longPress":  { "type": "key", "value": "ctrl+u" }
  },
  "com.anthropic.claudefordesktop": {            // Claude 桌面端（含 Claude Code）
    "double":     { "type": "voice" },           // 双击 = 语音听写 → 打进输入框
    "triple":     { "type": "key",  "value": "enter" },        // 提交
    "longPress":  { "type": "key",  "value": "ctrl+u" },       // 清空输入框
    "left":       { "type": "key",  "value": "esc" },          // 打断
    "up":         { "type": "key",  "value": "up" },
    "down":       { "type": "key",  "value": "down" },
    "right":      { "type": "key",  "value": "shift+tab" }     // 切模式
  },
  "com.alibaba.DingTalkMac": {                   // 钉钉
    "double":     { "type": "voice" },           // 双击 = 语音 → 输入框
    "triple":     { "type": "key", "value": "enter" },         // 发送
    "up":         { "type": "key", "value": "up" },
    "down":       { "type": "key", "value": "down" }
  }
}
```

> 单击(1)默认不绑（戒指触摸面日常易误触，重要动作用三击/长按这种"刻意"手势）。以上 binding 都可在 UI 里改——上面只是初始档。Claude/钉钉的具体动作，搭起来后你在 app 里调最快。

配置 UI 体验：**"聚焦你想配置的 app → 点'添加当前 app'"**，自动抓 bundle id，免手填。

---

## 5. 报文解析（Phase 1 只需手势）

```
gesture   : len 5,  前缀 00 09 61 00, code = bytes[4]   ∈ 0..7      → 派发
audio(M2) : len 110, 前缀 00 09 71 08 64 00, 后跟 seq + ADPCM 负载   → 累积
heartbeat : 00 2a 12 00 29, 每 30s                                  → 忽略
其它      : 记日志、忽略
```

---

## 6. 语音 / ASR 复用方案（M2）

UReka 的 ASR **不是端上调腾讯 SDK，而是打后端**（`lib/api/tencent_asr_s3_client.dart`）：

- 端点：`POST {TENCENT_ASR_BASE}/api/platform/speech/asr`，默认 base `https://pre.card.biz`
- 请求：`multipart/form-data`，字段 `audio`=音频文件、`speaker_diarization=false`
- 返回：`{ "code":0, "data":{ "text": "...", "segments":[...] } }`
- **无鉴权头**（Dart 客户端只发 Accept/Content-Type）

Python 复刻（`asr.py`，约 15 行）：
```
def recognize(wav_path) -> str:
    r = httpx.post(f"{BASE}/api/platform/speech/asr",
                   files={"audio": open(wav_path,"rb")},
                   data={"speaker_diarization":"false"}, timeout=30)
    return r.json()["data"]["text"]
```

语音闭环：双击起录 → 累积 `09 71` 帧 → **解码 ADPCM→PCM** → 包 WAV(8kHz 单声道) → 上面 POST → text → 注入聚焦 app。

⚠️ **M2 待验证**：(a) Mac 收的是 **raw ADPCM**（UReka 端是 SDK 内部已解码的 PCM），需自己实现 ADPCM 解码；(b) 停录方式——再次双击是否停流（硬件 toggle）待测，否则需发停流命令（涉及 AES）；(c) `pre.card.biz` 在 Mac 网络下可用性/是否限 IP。

---

## 7. 权限与运行形态

- **蓝牙**：CLI/进程需蓝牙权限。demo 从**用户终端**跑（权限挂终端，spike 已验证 OK）；无头进程会被 SIGABRT。
- **辅助功能(Accessibility)**：注入按键需要；首次在 系统设置→隐私与安全性→辅助功能 给终端/app 打勾。
- demo：`python -m ring_desktop`（终端）。后续 `py2app/pyinstaller` 打包成 `.app`，权限挂到 app 自身。

---

## 8. 分期

- **M1（本期 demo）**：BLE 连接 + per-app 手势配置 UI + 注入；先配 **Claude 桌面端 + 钉钉**。手势→按键闭环可用。
- **M2**：语音听写（ADPCM 解码 + 复用后端 ASR + 注入）。
- **M3**：打包 `.app`、电量/状态、更多 app、视情况 Swift 原生化。

---

## 9. 目录结构（建议）

```
Ring-desktop/
├── SPEC.md                  # 本文件
├── README.md
├── requirements.txt         # bleak, pyobjc, pynput, httpx, pywebview, (rumps)
├── config.example.json
└── ring_desktop/
    ├── __init__.py
    ├── ble.py               # bleak 连接/订阅/重连
    ├── gestures.py          # 报文解析 + 手势码
    ├── frontmost.py         # NSWorkspace 前台 app
    ├── actions.py           # key/media/text/script/voice 注入
    ├── config.py            # per-app 配置读写
    ├── asr.py               # 复用 UReka 后端 ASR (M2)
    ├── audio.py             # ADPCM→PCM→WAV (M2)
    ├── menubar.py           # rumps 菜单栏常驻(状态/快捷/打开配置)
    ├── app.py               # 主程序 / 事件循环
    └── ui/                  # pywebview 配置窗前端 (html/js)
```

---

## 10. 测试策略

- **单测**：报文解析（喂字节序列→期望手势码 / 正确忽略心跳与音频）；配置加载/校验；ASR 响应解析。
- **手动验证**：注入——焦点放记事本，触发手势看是否出对应按键；前台检测——切 app 看 bundle id 是否变；ASR——拿一个现成 WAV POST `pre.card.biz` 验证连通与返回。
- **真机联调**：戒指连上 → Claude 桌面端里三击=Enter、长按=Ctrl+U；钉钉里同样手势走钉钉档。

---

## 11. 开放问题 / 风险

1. **ADPCM 解码**（M2）：Mac 收 raw ADPCM，需实现解码（参考 UReka `AdPcmTool` / 标准 IMA-ADPCM），跑通才有语音。
2. **停录**：再次双击能否停音频流待测；不能则需发 AES 停流命令。
3. **后端 ASR 可用性**：`pre.card.biz` 是否对 Mac 网络开放/限流/限 IP；必要时换自建或直连腾讯。
4. **媒体键注入**：Apple Music 类需要系统媒体键（`NX_KEYTYPE_*`），`pynput` 不直接支持，可能要 Quartz 事件——本期 Claude/钉钉用不到，M3 再说。
5. **误触**：单击默认不绑；重要动作用刻意手势。后续可加"长按确认"等防护。
6. **打包权限**：`.app` 化后蓝牙/辅助功能 TCC 需重新授权。
