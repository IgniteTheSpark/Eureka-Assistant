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

## 本地 Ring Demo：四进程启动

Ring Demo 需要同时运行 MySQL、Backend、Ring Desktop 和 Demo Web。先完成
仓库根目录 `.env` 配置和上面的 Ring Desktop 安装，然后从仓库根目录分别在
终端中启动。

**终端 1 — MySQL 和 Backend：**

```bash
docker compose up -d db
docker compose run --rm backend alembic upgrade head
docker compose run --rm backend python -m db.seed
docker compose up -d backend
```

**终端 2 — Ring Desktop：**

```bash
cd ring-desktop
source .venv/bin/activate
python -m ring_desktop.app
```

**终端 3 — Demo Web：**

```bash
cd ring-demo
npm install
npm run dev
```

macOS 首次启动 Ring Desktop 时，允许终端使用蓝牙；再到“系统设置 → 隐私与
安全性 → 辅助功能”中启用启动 Ring Desktop 的终端 App。如果之前拒绝过蓝牙，
也在“蓝牙”隐私列表中启用该终端。修改权限后重启 Ring Desktop。

浏览器打开 `http://localhost:5173`。使用本地 Backend 中已有的 UReka 邮箱和
密码登录，或点击 **Create account** 创建账号（密码至少 6 位）。如需验证数据
打通，请在现有 UReka 客户端使用同一账号，确认能看到 Demo 创建的 Flash 资产。

### 真戒指冒烟检查

以下检查必须连接真实戒指，自动化测试不能代替：

1. 停止可能占用戒指连接的手机 App，在 Demo Web 中扫描并连接 `BCL…` 戒指。
2. 进入 Flash，双击开始录音，再双击停止；确认 transcript 只出现在 Flash。
3. 确认 `/api/flash` 返回真实资产，Demo Web 显示资产卡片；再用相同账号打开
   现有 UReka 客户端，确认能看到这些资产。
4. 返回首页并进入 Vibe；依次聚焦 Codex 和钉钉，确认各自配置的手势映射生效。
5. 启动 ASR 后在转写完成前切换 Flash/Vibe，确认旧转写不会进入新模式。
6. 关闭 Demo Web 标签页，确认 Ring Desktop 恢复 standalone 路由；如果浏览器
   没有成功发送 release，lease 会在 10 秒内兜底过期。

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
