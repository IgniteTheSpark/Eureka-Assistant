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
3. **未备案域名的 80/443 被阿里云拦截**(按 Host/SNI 拦,App 的 API 调用同样命中)→ 备案前走 **8443 非标端口**:
   - `.env.prod` 设 `DOMAIN=api.example.com:8443` + `CADDYFILE=Caddyfile.cn-8443`;
   - 证书用 **DNS-01**(不需要 80 可达):RAM 子账号只授 `AliyunDNSFullAccess`,然后
     `Ali_Key=.. Ali_Secret=.. acme.sh --issue --dns dns_ali -d api.example.com --server letsencrypt`,
     `--install-cert` 到 `deploy/certs/{fullchain,key}.pem`,`--reloadcmd "docker restart eureka-prod-caddy-1"`
     (acme.sh cron 自动续期);
   - App 构建:`flutter build ipa --dart-define=API_BASE=https://api.example.com:8443`;
   - **备案通过后**:`DOMAIN` 去掉 `:8443`、`CADDYFILE` 删掉(回默认 Caddyfile),`up -d` 即切回标准 443
     自动 HTTPS,App 发版换 URL。
   - 安全组放行:80 / 443 / 8443。
