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
