# 13 · 百智平台集成（BaiZhi / 100wiser）

> **横切章 · 设计中。** 百智是 Eureka 的**硬件供应商(录音卡)+ 未来的收购方**。因此架构**主动向百智收敛**:
> **身份**(百智 OAuth 登录)· **硬件**(录音卡 SDK 直连手机)· **知识**(资产同步进百智知识库)三条都打通,目标是日后**干净地并入百智**。
>
> **收购语境下的取舍(已与产品确认):** 数据主权 / 「别把护城河喂给供应商」这类**对外部第三方**的顾虑**不适用**(终将是一家公司)。
> 但有两条**与所有权无关、仍然成立**的纪律,本章贯彻:① **单一权威存储**(同一公司内两份可写副本也会同步腐烂)→ Eureka DB 近期为权威,**单向**推百智 KB;② **用户同意/隐私**(交易闭合前仍是两个主体在搬用户个人数据;PIPL/隐私政策仍适用)→ 同步**对用户透明**(设置项),非静默。
>
> 平台基础(取自 [openapi.100wiser.com/doc](https://openapi.100wiser.com/doc)):BaseUrl `https://openapi.100wiser.com` · OAuth Bridge `https://100wiser.com/oauth-bridge` · Sign Salt `BAIZHIAPPLICATION`。

---

## 13.1 OAuth 登录（百智作 IdP）

> 现状:Eureka 自有 邮箱+密码 → HS256(§3)。新增**百智 OAuth 登录**:百智账号 = Eureka 用户身份(每个持卡用户本就有百智账号)。

**铁律:身份用百智,但 Eureka 仍签发自己的会话 token。** 登录 ≠ 把每个请求耦合到百智 token,§3 的 `get_current_user_id` / per-user 隔离**不变**。

**流程(后端实现 OAuth bridge):**
1. 后端生成 `nonce`(≥16 字节随机 hex)+ `sign = SHA256(app_id + app_secret + "BAIZHIAPPLICATION" + nonce)`(小写 hex,**签名在服务端,`app_secret` 永不到客户端**)。
2. 构造授权地址 `https://100wiser.com/oauth-bridge?app_id&nonce&sign&app_name`,app 打开(用户在百智登录态下授权)。
3. 百智回跳 `redirectUrl?token=<临时token>`(**一次性、短时效,不持久化**)。
4. 后端 `POST https://openapi.100wiser.com/api/applications/token/exchange {token}` → 拿**百智真实登录 token(JWT)**。
5. 后端**把百智身份映射到 Eureka `user_id`**(首登即 provision 基线技能,同现有注册流)→ **签发 Eureka 自己的 JWT** 作会话。
6. **百智真实 token 单独存**(per-user、服务端加密、write-only,同 Connected Apps 凭据模型)—— 仅用于代用户调百智 MCP/API(§13.2 / §13.4)。

**移动端落地(关键 —— 快速接入文档的 web 示例〔Next.js/Cookie/回调页〕不直接适用):**
- **`redirectUrl` = Eureka 后端端点**(如 `https://<api>/api/auth/baizhi/callback`),**不是 web 回调页**。后端收临时 token → 调换取 → 映射 user → 签发 Eureka JWT → **深链回 Flutter app**(`eureka://auth?token=<eureka_jwt>`,universal link / custom scheme)。
- Flutter 侧:用**系统浏览器 / `flutter_web_auth` 之类**打开授权地址,捕获深链回跳拿 **Eureka JWT**(不是百智临时 token)。`app_secret` 与百智真实 token **全程不上设备**。
- **换取端点(权威,认这条)**:`POST https://openapi.100wiser.com/api/applications/token/exchange  {"token":"<临时token>"}` → `data.token` = 真实 JWT。(快速接入文档第 7 节示例里的 `/api/baizhi/oauth/exchange` 是**笔误**,以第 8 节 / 配置表为准。)
- 环境变量:`BAIZHI_BASE_URL` / `BAIZHI_OAUTH_BASE_URL` / `BAIZHI_APP_ID` / `BAIZHI_APP_SECRET` / `BAIZHI_APP_NAME` / `BAIZHI_REDIRECT_URL`(后端 `.env.prod`,**不提交、不上客户端**)。

**待决:** 百智 OAuth 是**唯一登录**,还是与邮箱+密码并存?持卡用户必有百智账号 → 百智-primary 合理;但 web/Android/未来非持卡用户是否仍需邮箱路径,你定。

**✅ 已实现(B1):** 后端 `api/auth_baizhi.py` —— `GET /auth/baizhi/authorize`(签名拼桥 URL)+ `GET /auth/baizhi/callback`(换取真实 token → 映射 → 签发 Eureka JWT → 302 深链 `eureka://auth?token=`)。`User` 加 `baizhi_user_id`(unique,迁移 `0017`),`email`/`password_hash` 改 **nullable**(百智用户无邮箱密码);百智真实 token 入 `connected_apps`(`connector_id='baizhi'`,Fernet 加密 write-only)。Flutter `auth_controller.loginWithBaizhi()` 用 `flutter_web_auth_2` 开桥、捕获深链拿 **Eureka JWT**,登录页加「用百智登录」。
> **决策(对照成稿卡 §8):** ① **邮箱登录保留不动**,新增百智路径(并存,非唯一)。② **稳定身份**:优先 `BAIZHI_ME_URL`(可选 env,权威 me 端点);未配则**解码百智真实 token 的 JWT payload** 取首个 id 类 claim(`userId`/`user_id`/`uid`/`sub`/…)。③ 真实 token **不假设 refresh**;过期→重新走授权。
> **仍需(非 coding):** 在 `.env.prod` 填 `BAIZHI_APP_ID/SECRET/NAME` + 百智控制台建应用配 `redirectUrl`;向百智确认权威 me 端点(填 `BAIZHI_ME_URL` 即切换);iOS 重新 `pod install` 装 `flutter_web_auth_2`(ASWebAuthenticationSession,无需 Info.plist 改)。

---

## 13.2 MCP 连接器（会议 / 日历）

百智把能力以**远程 MCP Server(SSE + Bearer)** 暴露 —— 正是 Eureka 既有外部 MCP 模式([§1.7](01-agent-architecture.md),同 DingTalk 那套 streamable_http+token)。**加进 `MCP_SERVER_CATALOG`:**

| 连接器 | URL | Tools |
|---|---|---|
| `baizhi_meeting`（会议） | `https://mcp.baizhi.ai/meeting/sse` | `create_meeting` · `query_meeting` · `generate_minutes` |
| `baizhi_calendar`（日历，文档标签写「文件夹 MCP」实为日程） | `https://mcp.baizhi.ai/calendar/sse` | `create_event` · `query_events` · `delete_event` |

- **Bearer = 该用户的百智真实 token**(§13.1 存的那枚),服务端在 agent 调用时注入。
- 给 agent 直接添了**会议 + 日历**能力,扩展 Eureka 既有 event 体系。**pull 优先**:要把百智会议/日历数据带进 Eureka 当上下文,走这些**只读 tool**,不要反向灌库。

---

## 13.3 录音卡 SDK（硬件 · 直连手机）

> 确认:Eureka 用的就是百智录音卡。现状捕捉走 **macOS FlashType 桌面桥**(§3.2)。目标:**手机直连卡**,去掉 Mac 依赖 —— 这是「手机优先零摩擦捕捉」的真正解锁(也是 gamemode 里后置的「原生 BLE/离线补传」)。

- **SDK**:`brrecordsdk/RecordSDK`,Swift,`BluetoothDeviceManager`(单例 + delegate),iOS/macOS。能力:BLE 扫描/绑定/连接、BLE 同步 `.opus`、**WiFi 快传**(`192.168.1.1:32769` socket)、实时录音、**闪念录音(设备按键触发,「F」前缀 `.opus`)**、MARK 头解析。
- **接法:把 Swift SDK 封成 Flutter 插件(platform channel,iOS)** → app 内:绑定卡 → BLE/WiFi 同步取 `.opus` + 闪念事件 → **剥 MARK 头**(取真实 Opus payload)→ ASR(端上 whisper 或上传后端)→ 喂 flash 管线(`POST /api/flash`)。
- **闪念事件**(`flashMemoDidStartRecording`/`...DidReceiveAudio`/`...DidFinishRecording`)= 硬件按键触发的捕捉 = Eureka 的「闪念」入口,直接接 §1.3 flash pipeline。
- **要点**:① 让百智把 SDK 对外接口标 `public`(文档已提示);② BLE 同步/WiFi快传/删除/格式化**不并发**;③ CRC 校验失败的文件不喂 ASR;④ 绑定信息 `BindInfo` 业务层持久化、下次 `setBindInfo` 回填;⑤ 格式化清空卡片须二次确认。
- **过渡**:FlashType 桌面桥(§3.2)可保留作 dev/桌面路径;手机插件落地后,手机为主路径。
- **获取**:钉钉联系 张冲 拿 SDK。

---

## 13.4 知识库同步（资产 → 百智 KB）

> 收购语境下**做**(不再是「仅 opt-in 导出」),但守两条纪律(见章首)。

- **方向 = 单向 `Eureka DB → 百智 KB`**:Eureka DB **近期为权威存储**(捕捉/结构化/domain/技能全依赖它);百智 KB 作**下游索引/镜像**。**不做双向**(避免冲突腐烂)。长期若 Eureka 并入百智,再议谁为权威。
- **同步内容**:asset(payload + domain + 类型)+ 报告,作为 KB 条目;**异步推**(不挡捕捉,复用 `has_pending`/任务管线);create/update 触发增量同步。
- **认证**:用 §13.1 存的百智 token(或专用同步 API)。
- **用户透明(纪律②)**:一个**设置开关**(生态内可默认开,但**可见、可关**);隐私政策说明;交易闭合前按两主体数据条款处理。
- **价值**:用户的 Eureka 语料在百智其他面(会议/助手)可检索 —— 生态收敛的意义所在。

---

## 13.5 安全与待决

- **安全铁律**:`app_secret` 仅后端 `.env.prod`(永不客户端/不提交);签名在服务端;临时 token 一次性、不持久化;百智真实 token **per-user 加密、write-only、不回客户端/日志**(同 [§1.7.1](01-agent-architecture.md) Connected Apps 模型)。
- **待决**:① 百智-only 登录 vs 并存邮箱(§13.1);② KB 同步范围(全量 / 按 domain / 按类型)+ 默认开关态(§13.4);③ 端上 ASR vs 上传后端转写(§13.3);④ 收购闭合时间 → 决定何时从「单向同步」升到「百智为权威」。

---

## 13.6 落点 / 实施批次

| 批 | 内容 | 落点 |
|---|---|---|
| **B1 · OAuth 登录 ✅ 已实现** | bridge(nonce/sign)+ 回调 + token exchange + 映射→Eureka user + 签发 Eureka JWT + 存百智 token(加密) | 后端 `api/auth_baizhi.py`(+`main.py` 挂载、`config.py` `baizhi_*`、`User.baizhi_user_id` 迁移 `0017`)· Flutter `auth_controller.loginWithBaizhi` + 登录页「用百智登录」(`flutter_web_auth_2`)· 成稿卡 [`handoff-baizhi-oauth.md`](handoff-baizhi-oauth.md) |
| **B2 · MCP 连接器** | `baizhi_meeting`/`baizhi_calendar` 进 `MCP_SERVER_CATALOG`;Bearer 注入 | [§1.7](01-agent-architecture.md) `mcp_config.py` |
| **B3 · 录音卡 Flutter 插件** | Swift `BluetoothDeviceManager` → iOS platform channel;绑定/BLE+WiFi 同步/闪念事件 → 剥 MARK → flash 管线 | mobile 插件 · §3.2 |
| **B4 · KB 同步** | 单向 Eureka→百智 KB,异步增量,设置开关 | §13.4 · §2 |

> 依赖:B1 是 B2/B4 的前置(都要百智 token)。B3 独立(硬件侧),可并行。
