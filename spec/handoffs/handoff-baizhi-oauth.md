# Handoff · B1 百智 OAuth 登录（coding agent 即用接入卡）

> **✅ 已实现(2026-06-09)。** 后端 `api/auth_baizhi.py`(挂载 `main.py`,配置 `config.py` `baizhi_*`,模型 `User.baizhi_user_id` + email/password 改 nullable,迁移 `0017_baizhi_user_id`,百智 token 入 `connected_apps` provider=`baizhi` 加密)+ Flutter `auth_controller.loginWithBaizhi()`(`flutter_web_auth_2`)+ 登录页「用百智登录」。已验证:签名/桥 URL、JWT 取 id、用户映射 + 基线技能 + token 加解密 + Eureka JWT 签发(in-container 跑通,唯独真实百智网络换取需真凭据)。**剩余=开发者手动**:`.env` 填凭据 + 百智控制台建应用、iOS `pod install`、向百智确认 me 端点(见 §8)。

> 给**实现 session**的成稿契约。依据 [§13.1](../13-baizhi-integration.md) + 百智快速接入文档。
> **本卡只描述 WHAT/契约 + 参考片段;实际代码由 coding agent 写在 `backend/` + `mobile/`(spec session 不碰这两个目录)。**
> 关键纠偏(对比快速接入文档):① 文档是 **web** 示例(Next.js/Cookie/回调页),Eureka 是 **Flutter + FastAPI** → `redirectUrl` = **后端端点 + 深链回 app**,不是 web 回调页;② 换取端点认 **`/api/applications/token/exchange`**(文档第 7 节的 `/api/baizhi/oauth/exchange` 是笔误)。

---

## 0. 前置(开发者手动,非 coding)
- 百智控制台创建应用 → 拿 `app_id` / `app_secret` / `app_name`;配置 `redirectUrl` = **后端回调** `https://<api-host>/api/auth/baizhi/callback`。
- 写入后端 `.env.prod`(**不提交、不上客户端**):
  ```bash
  BAIZHI_BASE_URL=https://openapi.100wiser.com
  BAIZHI_OAUTH_BASE_URL=https://100wiser.com
  BAIZHI_APP_ID=<app_id>
  BAIZHI_APP_SECRET=<app_secret>
  BAIZHI_APP_NAME=<app_name>
  BAIZHI_REDIRECT_URL=https://<api-host>/api/auth/baizhi/callback
  EUREKA_APP_SCHEME=eureka     # 深链回 app 的 scheme / universal link
  ```

## 1. 流程(移动端,后端中介)
```
Flutter                         FastAPI 后端                         百智
  │  GET /api/auth/baizhi/authorize │                                   │
  │ ───────────────────────────────►│ 生成 nonce+sign,拼授权 URL        │
  │ ◄──────────── {authorize_url} ──│                                   │
  │ 系统浏览器打开 authorize_url ───────────────────────────────────────►│ 用户在百智登录态授权
  │                                 │ ◄── 回跳 redirectUrl?token=<临时> ──│
  │                                 │ POST token/exchange ──────────────►│
  │                                 │ ◄────────── {data.token=<真实JWT>} │
  │                                 │ 映射→Eureka user_id(首登 provision)│
  │                                 │ 签发 Eureka JWT;存百智真实token(加密)│
  │ ◄── 302 eureka://auth?token=<EurekaJWT> ──────────────────────────  │
  │ 捕获深链 → 存 Eureka JWT → 进 app                                    │
```
**铁律**:`app_secret` 与百智真实 token **全程只在后端**;客户端只拿 **Eureka JWT**(沿用现有 §3 鉴权,每请求不变)。

## 2. 后端端点(FastAPI · 新增 `api/auth_baizhi.py` 之类)

### `GET /api/auth/baizhi/authorize` → `{authorize_url}`(免 token)
- 生成 `nonce`(≥16B 随机 hex)、`sign`、拼 URL。返回给 app(或直接 302)。
```python
import hashlib, secrets, os
def _baizhi_sign(nonce: str) -> str:
    raw = f"{os.environ['BAIZHI_APP_ID']}{os.environ['BAIZHI_APP_SECRET']}BAIZHIAPPLICATION{nonce}"
    return hashlib.sha256(raw.encode()).hexdigest()      # 小写 hex
def baizhi_authorize_url() -> str:
    nonce = secrets.token_hex(16)
    from urllib.parse import urlencode
    q = urlencode({"app_id": os.environ["BAIZHI_APP_ID"], "nonce": nonce,
                   "sign": _baizhi_sign(nonce), "app_name": os.environ["BAIZHI_APP_NAME"]})
    return f"{os.environ['BAIZHI_OAUTH_BASE_URL']}/oauth-bridge?{q}"
```
> nonce 无需服务端存(签名自含);如要更严可把 nonce 短存做一次性校验(可选)。

### `GET /api/auth/baizhi/callback?token=<临时>`(= 控制台 redirectUrl,免 token)
1. 读 query `token`(临时、一次性、**不持久化**)。缺失 → 深链回错误态。
2. **换取真实 token**:`POST {BAIZHI_BASE_URL}/api/applications/token/exchange  {"token": <临时>}` → `data.token`。失败(非 `code==0` / 网络)→ 深链回错误态。
3. **取百智身份 → 映射 Eureka user_id**:用真实 token 调一个百智「当前用户」接口拿稳定 user 标识(文档第 9 节「后续请求带 Bearer」;具体 me 端点向百智确认)。以 `baizhi_user_id` 查 Eureka 用户:
   - 命中 → 该 `user_id`;未命中 → **新建 Eureka 用户 + provision 基线技能**(复用现有 register 路径,见 §3 / `provisioning`)。**新增映射列**(下)。
4. **签发 Eureka JWT**:复用现有 HS256 签发(`sub=user_id`, `exp=jwt_expire_hours`,同 §3 login)。**不要**把百智 token 当会话 token。
5. **存百智真实 token**:per-user、**服务端加密、write-only、绝不回客户端/日志**(复用 Connected Apps 凭据模型,§1.7.1)。供 B2/B4 调百智用。
6. **深链回 app**:`302 → {EUREKA_APP_SCHEME}://auth?token=<EurekaJWT>`(或 universal link)。

## 3. 数据模型增量(§2)
- `users` 加 `baizhi_user_id`(String, nullable, **unique**, indexed)—— 百智身份 ↔ Eureka 用户映射。
- 百智真实 token 入**现有加密凭据表**(Connected Apps,§1.7.1)`{user_id, provider='baizhi', secret(enc), updated_at}`;**不**新开明文列。

## 4. Flutter 侧(`mobile/`)
- 登录页加「**用百智登录**」:`GET /api/auth/baizhi/authorize` → 拿 `authorize_url` → 用 `flutter_web_auth_2`(或系统浏览器 + app_links 深链)打开,`callbackUrlScheme: 'eureka'`。
- 捕获回跳 `eureka://auth?token=<EurekaJWT>` → 存进现有 token 存储(同邮箱登录后那套)→ 进 app。错误态(`?error=`)→ 提示重试。
- 之后所有请求照旧带 `Authorization: Bearer <EurekaJWT>`(§3 不变)。

## 5. 错误处理(必做,文档第 10 节 + Eureka)
- 缺临时 token / 换取失败 / 百智接口异常 / 真实 token 过期 → 都**深链回明确错误态**,app 提示「百智登录失败,请重试」,**绝不**白屏/静默。
- 临时 token **只用一次、不持久化**;真实 token 过期 → 重新走授权(或刷新,若百智支持)。

## 6. 安全清单
- [ ] `app_secret` 仅后端 env,**不提交、不上客户端**;签名在后端算。
- [ ] 临时 token 不落库、用后即弃;地址栏/深链参数用后清理。
- [ ] 百智真实 token per-user **加密存、write-only**,GET/日志**永不**出现。
- [ ] 客户端只持 **Eureka JWT**;§3 `get_current_user_id` / per-user 隔离不变。
- [ ] `redirectUrl` 与控制台一致;深链 scheme 在 iOS Info.plist / universal link 注册。

## 7. 验收
- 点「用百智登录」→ 浏览器授权 → 回 app 已登录;新百智用户首登自动建号 + 基线技能;再次登录命中同一 Eureka 用户。
- 抓包确认:客户端**只**见 Eureka JWT;`app_secret`/百智 token 不出现在任何客户端响应。
- 换取端点用对(`/api/applications/token/exchange`);错误路径都有提示。

## 8. 待向百智/你确认（实现已就绪,以下为可调项）
- **me 端点**:已做 fallback —— 未配 `BAIZHI_ME_URL` 时**解码真实 token JWT payload** 取首个 id claim(`userId`/`user_id`/`uid`/`sub`/`id`/`accountId`/`account`)。向百智拿到权威 me 端点后,把它填进 `BAIZHI_ME_URL` env 即自动切换(无需改码)。
- **真实 token 有效期 / refresh**:未假设 refresh;过期 → 客户端 401 → 重新走授权。若百智支持 refresh,后续在 callback/凭据层补。
- **百智-only vs 并存邮箱**:✅ 已选**并存** —— 邮箱登录路径**未动**,新增「用百智登录」。日后若要百智-only,隐藏邮箱表单即可(后端两条路径都在)。
