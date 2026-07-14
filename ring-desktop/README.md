# Ring-desktop

戒指 → Mac 输入与触觉通知设备：按当前聚焦 app 路由触控手势、
语音转写，并通过戒指马达反馈任务完成等桌面事件。
详见 [SPEC.md](SPEC.md) / [PLAN-M1.md](PLAN-M1.md)。

## 安装

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp config.example.json config.json
```

## 运行（在你自己的终端里跑——要蓝牙 + 辅助功能权限）

```bash
python -m ring_desktop.app
```

首次：系统设置 → 隐私与安全性 → 蓝牙 & 辅助功能，给你的终端 App 打勾。
跑之前先释放戒指（别让手机抢）：`adb shell am force-stop com.eureka.mindapp`。

启动后打开配置页，在“戒指连接”中点击 `扫描`，选择名称以 `BCL`、
`Chiplet` 或 `Ring` 开头的设备，再点击 `连接`。菜单栏只显示一个状态图标：
绿色表示已连接，白色表示未连接，录音时显示麦克风。菜单栏图标不可见时，
按 `Control+Option+R` 打开或切回配置窗口。

## 震动通知

菜单栏 → `测试震动` 可以触发强力、持续、渐变三种模式。

Ring-desktop 常驻且戒指已连接时，Claude Hook、Shell、快捷指令等可调用：

```bash
python -m ring_desktop.notify --type continuous
```

可选类型：`strong`、`continuous`、`gradient`。本地 API 只监听
`127.0.0.1:17863`：

```bash
curl -X POST http://127.0.0.1:17863/vibrate \
  -H 'Content-Type: application/json' \
  -d '{"type":"continuous"}'
```

配置窗口中，每个 app 可分别配置三类事件：`任务完成`、`需要确认`、
`执行失败`。每类事件都能选择关闭、强力、持续或渐变震动。

Codex 桌面端的 bundle id 是 `com.openai.codex`。通过 Codex 的 `notify`
回调运行 `ring_desktop.codex_notify` 后，任务完成会调用事件 API；现有的
Computer Use `turn-ended` 通知也会继续转发。当前 Codex legacy notify 实际
会发送任务完成事件，另外两类映射已预留给后续支持相应 payload 的 hook。

## 测试

```bash
pytest -q
```
