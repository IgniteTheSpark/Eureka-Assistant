# Deploy — Eureka backend on a cloud VM (Phase E0)

Stands up the FastAPI backend + MySQL behind Caddy (automatic HTTPS) on a single
VM, so the iOS app can reach the API over `https://`. Auth is email+password with
per-user data isolation — set a strong `JWT_SECRET` in `.env.prod` (the token
signing key; changing it later logs everyone out).

> Stack: Docker Compose · MySQL 8 · FastAPI (uvicorn) · Caddy 2 (Let's Encrypt).

## 0. Prerequisites
- A VM (AWS EC2 / GCP CE / Aliyun ECS), Ubuntu 22.04+ recommended, 2 vCPU / 2-4 GB RAM.
- A domain you control. Create a DNS **A record** → the VM's public IP
  (e.g. `api.yourdomain.com`). TLS won't issue until DNS resolves.
- Security group / firewall: allow inbound **80** and **443**. Do NOT open 3306.

## 1. Install Docker on the VM
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"   # re-login after this
```

## 2. Get the code + secrets
```bash
git clone <this-repo> eureka && cd eureka
cp deploy/.env.prod.example deploy/.env.prod
# Edit deploy/.env.prod: DOMAIN, ACME_EMAIL, MySQL passwords, OPENROUTER_API_KEY,
# JWT_SECRET (openssl rand -hex 32), and CONNECTED_APPS_KEY (REQUIRED in prod —
# python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())").
# Optional: IMAGE_API_KEY (Doubao report images), BAIZHI_* (百智 login, after go-live).
# DATABASE_URL's password MUST match MYSQL_PASSWORD.
nano deploy/.env.prod
```
(Optional) put MCP credential files in `./mcp-credentials/` if you use Google
Calendar / DingTalk MCPs — the backend mounts that dir read-only.

## 3. Bring it up (build + start)
```bash
docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml up -d --build
```
Caddy fetches a TLS cert on first boot (needs DNS + ports 80/443 reachable).

## 4. Migrate + seed the database (first deploy only)
```bash
docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml \
  exec backend alembic upgrade head
docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml \
  exec backend python -m db.seed
```

## 5. Verify
```bash
curl -s https://api.yourdomain.com/health      # → {"status":"ok",...}
```
Point the app's API base URL at `https://api.yourdomain.com`.

## Operations
- **Logs:** `docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml logs -f backend`
- **Update to new code:** `git pull` then re-run step 3 (rebuilds the backend image), then step 4's `alembic upgrade head` if there are new migrations.
- **DB backup:** `docker compose ... exec db mysqldump -ueureka -p"$MYSQL_PASSWORD" eureka > backup.sql`
- **Restart:** `docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml restart backend`

## Notes / hardening (post-beta)
- Move secrets out of a plaintext `.env.prod` into a secrets manager.
- Per-user OpenRouter rate-limit / quota + an OpenRouter spend cap (all agent
  traffic runs on the one server key).
- Move the auth token to device Keychain (`flutter_secure_storage`) — beta uses
  `shared_preferences`.
- Consider an off-VM managed MySQL once data matters; add automated DB backups.

---

## 附录 · 中国大陆部署(阿里云 ECS,备案前)— 2026-06 实战记录

大陆机房的三个坑及解法(均已落进本目录配置):

1. **Docker Hub 被墙** → `/etc/docker/daemon.json` 配镜像加速:
   `{"registry-mirrors": ["https://docker.m.daocloud.io", "https://docker.1ms.run"]}` 后 `systemctl restart docker`。
2. **跨境 PyPI 龟速**(实测 pip 层卡 30+ 分钟)→ Dockerfile 已带 `ARG PIP_INDEX_URL`,
   本 compose 默认传阿里云镜像源;本地构建不受影响。
3. **未备案域名 + TLS 被拦截**(2026-06 抓包实测,结论比预想更严):
   - 阿里云对未备案域名 `api.ureka.chat` 的 **HTTP** 返回 **403**(按 Host 拦);
   - 大陆骨干网对这台 ECS 的 **TLS 流量做 RST 注入** —— 带 SNI=域名必断,连
     **8443 非标端口、甚至无 SNI 的裸 IP TLS 也「先通后断」**(ClientHello 到达后被
     伪造 RST 打断,概率性,做 App 不可用)。**→ 原计划的 8443 + DNS-01 HTTPS 方案
     在用户网络下实测 0/6 不通,已放弃。**
   - **备案前唯一可靠通道:裸 IP + 明文 HTTP(`http://39.96.55.118`,实测 6/6 稳定 200,
     完整注册/登录链路通过)。** 配置即 `Caddyfile.cn-8443` 里保留的 `:80` 站点。
   - App 端:`--dart-define=API_BASE=http://39.96.55.118`,并在 `ios/Runner/Info.plist`
     加 **仅放行该 IP** 的 ATS 明文例外(`NSExceptionDomains` → `39.96.55.118`)。
     代价是明文传输,仅限备案前内测;App Store 正式提审走备案后的 HTTPS。
   - 证书/`acme.sh` DNS-01/`8443` 那套**备案后**才有意义:届时 `DOMAIN` 指回
     `api.ureka.chat`(去端口)、`CADDYFILE` 删掉回默认 Caddyfile,`up -d` 切回标准
     443 自动 HTTPS;同时删掉 App 的 ATS 例外、`API_BASE` 换 `https://api.ureka.chat`。
   - 安全组放行:80 / 443 / 8443(后两者备案后用)。
