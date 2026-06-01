# Third-party MCP credentials

这个文件夹放第三方 MCP 服务的密钥文件。整个文件夹被 `.gitignore` 忽略,**绝
不会被 commit**。

## 期望的文件结构

```
mcp-credentials/
├── README.md                          ← (本文件,在 git 里)
├── .gitignore                         ← (在 git 里)
├── google-calendar-creds.json         ← Google Cloud OAuth client 凭据
├── google-calendar-token.json         ← 一次性 OAuth 完成后自动生成的 token
└── (dingtalk 不需要文件,credentials 走 .env)
```

## Google Calendar 配置流程

### Step 1: Google Cloud Console

1. 打开 https://console.cloud.google.com/
2. 新建项目(或选已有项目)
3. 左侧菜单 → **APIs & Services** → **Library** → 搜索「Google Calendar API」→ Enable
4. 左侧菜单 → **APIs & Services** → **OAuth consent screen**:
   - User Type:**External**(个人 Gmail 也用 External)
   - App name: `Eureka`(随意)
   - User support email: 填你自己
   - **Test users**: 添加你自己的 Gmail —— 否则会卡在 "App not verified"
   - 保存
5. 左侧菜单 → **APIs & Services** → **Credentials** → **Create Credentials** → **OAuth client ID**:
   - Application type: **Desktop app**
   - Name: `Eureka MCP`
   - 创建后,点击右侧 **DOWNLOAD JSON**
6. 把下载的 JSON 重命名成 `google-calendar-creds.json` 放到这个文件夹里

### Step 2: 一次性 OAuth 授权(在宿主机跑,需要浏览器)

容器里没法弹浏览器,所以这一步在宿主机做。需要 Node.js(`node --version` 应该 ≥ 18)。

```bash
cd /Users/admin/workwork/eureka-staff/bizcard/Eureka-BrandNew
export GOOGLE_OAUTH_CREDENTIALS="$(pwd)/mcp-credentials/google-calendar-creds.json"
export GOOGLE_CALENDAR_MCP_TOKEN_PATH="$(pwd)/mcp-credentials/google-calendar-token.json"
npx -y @cocal/google-calendar-mcp auth
```

执行后会自动打开浏览器走 OAuth,授权后回到终端会看到 "Authentication successful"。
`google-calendar-token.json` 会自动生成在 mcp-credentials/ 里。

> 如果浏览器不自动打开,把终端里的 `https://accounts.google.com/o/oauth2/...` URL 复制到浏览器手动打开。

### Step 3: 启用

在项目根目录 `.env`(没有就建)加:

```
EUREKA_MCP_ENABLED=fake_external,google_calendar
```

重启 backend:

```
docker compose restart backend
```

## Dingtalk 配置流程

### Step 1: 钉钉开放平台

1. 打开 https://open.dingtalk.com/
2. 用你的钉钉账号登录(选「企业内部开发」如果是公司钉钉,或个人版均可)
3. 顶部 **应用开发** → **企业内部应用** → **创建应用**:
   - 类型:H5 微应用 或 小程序皆可,我们只用它的 AppKey
   - 名字:`Eureka MCP`
4. 创建后,在「凭证与基础信息」页面拿到:
   - **AppKey** → 即 `DINGTALK_Client_ID`
   - **AppSecret** → 即 `DINGTALK_Client_Secret`

### Step 2: 配置权限

应用详情页 → **权限管理** → 申请这些权限(按你需要哪些功能):
- 日历能力:`Calendar.events.read` / `Calendar.events.write` → 日历 CRUD 必备
- 机器人能力:`Robot.Message.Send` → 发消息必备
- (可选)通讯录读权限,如果想让 agent 查同事

### Step 3:(可选)群机器人

如果要让 task-skill 能往钉钉群里发消息:
1. 进想发消息的钉钉群 → 群设置 → 智能群助手 → **添加机器人** → **自定义**
2. 安全设置:勾「加签」或「关键词」
3. 创建后拿到 **Webhook URL**,里面有个 `access_token=xxx` —— 这是 `ROBOT_ACCESS_TOKEN`
4. 机器人 ID(`ROBOT_CODE`)在机器人详情页

### Step 4: 启用

`.env`:

```
EUREKA_MCP_ENABLED=fake_external,google_calendar,dingtalk
DINGTALK_Client_ID=your_app_key_here
DINGTALK_Client_Secret=your_app_secret_here
# 可选:
ROBOT_CODE=your_robot_code
ROBOT_ACCESS_TOKEN=your_webhook_token
ACTIVE_PROFILES=dingtalk-calendar,dingtalk-robot-send-message
```

重启:

```
docker compose restart backend
```

## 验证

启用后任一 MCP:

```
# Flash 触发
curl -s -X POST http://localhost:8000/api/flash \
  -H "Content-Type: application/json" \
  -d '{"text":"明天下午三点跟客户开会，帮我同步到我的 Google Calendar","source":"voice"}'

# 然后看 task 状态(8 秒后应该 done)
curl -s "http://localhost:8000/api/tasks?status=done" | python3 -m json.tool
```

应该看到一个 task 状态 done,result_asset_payload.external_url 指向真实的
Google Calendar 事件链接(`https://calendar.google.com/event?eid=...`)。

## 排错

| 现象 | 可能原因 |
|---|---|
| task status=failed, error 提到 "OAuth" | google-calendar-token.json 不在或过期 → 重跑 Step 2 |
| task status=failed, error 提到 "401 / 403" | Dingtalk AppKey/Secret 错,或没勾权限 |
| docker logs 里有 "EUREKA_MCP_ENABLED: unknown MCP" | 名字拼错;只能用 catalog 里的:`fake_external` / `google_calendar` / `dingtalk` |
| `npx` 在容器里报 "command not found" | Dockerfile 里 node.js 没装上,重新 `docker compose build backend` |
| Google OAuth 卡在 "App not verified" | OAuth consent screen 里没加你自己作为 test user |
