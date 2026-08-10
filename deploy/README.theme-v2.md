# Theme V2 production deployment

This is the production path for the Flutter app's default Theme V2 runtime. It
runs one API process, one background worker, MySQL 8, a one-shot Alembic
migration service, and Caddy HTTPS on a single cloud VM.

The older `deploy/docker-compose.prod.yml` still targets `backend/`; do not use
it for a Theme V2 release.

## 1. Prepare the VM and DNS

Recommended beta starting point: Ubuntu 22.04 or 24.04, 4 vCPU, 8 GB RAM, and
80-100 GB SSD. Give the VM a stable public IP and point an API subdomain at it.

Allow inbound 80 and 443. Restrict SSH to trusted source addresses. Do not open
3306, 8000, or 8100: only Caddy publishes a host port.

Install Git, Docker Engine, the Docker Compose plugin, `curl`, `gzip`, and
`sha256sum`. Clone the repository onto the VM.

## 2. Create production configuration

```bash
cp deploy/.env.theme-v2.prod.example deploy/.env.theme-v2.prod
chmod 600 deploy/.env.theme-v2.prod
```

Before the first deploy, replace every `replace-with-*` value and set the real
`DOMAIN`, `ACME_EMAIL`, and `REPORT_PUBLIC_BASE_URL`. Generate secrets without
putting them in shell history:

```bash
openssl rand -hex 32
openssl rand -base64 36
```

The password embedded in `THEME_V2_DATABASE_URL` must match
`THEME_V2_DB_PASSWORD`; URL-encode any reserved characters. Enable capture,
chat, planner, report generation, and web search only after setting each
feature's model and API key. `/ready` rejects enabled providers with incomplete
configuration.

The example uses Aliyun Debian/PyPI mirrors for a mainland VM. Change
`DEBIAN_MIRROR` and `PIP_INDEX_URL` to the official sources when deploying in a
region with reliable international package access.

Keep the real env file on the VM or in a secret manager. It is gitignored and
must never be pasted into logs, screenshots, tickets, or chat.

## 3. Deploy

From the repository root:

```bash
deploy/theme-v2-deploy.sh deploy
```

The script refuses a dirty checkout, tags the application image with the Git
SHA, validates Compose, builds the production image, waits for MySQL, applies
Alembic migrations, starts API/Worker/Caddy, and polls the public `/ready`
endpoint. Successful and previous image tags are stored in the gitignored
`deploy/.theme-v2-state/` directory.

Useful commands:

```bash
deploy/theme-v2-deploy.sh status
deploy/theme-v2-deploy.sh logs
curl -fsS https://api.example.com/health
curl -fsS https://api.example.com/ready
```

`/health` proves the API process is running. `/ready` also checks runtime
configuration, fonts, and MySQL, so deployment monitoring should use `/ready`.
Prometheus `/metrics` is intentionally not exposed through public Caddy.

## 4. Roll back application containers

```bash
deploy/theme-v2-deploy.sh rollback
# Or select a known local image explicitly:
deploy/theme-v2-deploy.sh rollback <git-sha-tag>
```

Rollback changes API and Worker images only. It never reverses database
migrations. Production migrations therefore need to remain backward-compatible
with the previous application image. Take a backup before any destructive or
large schema/data migration.

## 5. Back up both durable data stores

Theme V2 stores user records in MySQL and generated report/media files in the
`media_data` volume. Both must be backed up:

```bash
deploy/theme-v2-backup.sh
```

The script creates a timestamped MySQL dump, a compressed media archive, and
SHA-256 checksums with owner-only permissions. Copy each completed directory to
encrypted storage outside the VM. Schedule the script daily, define retention
at the remote backup destination, and run a restore drill before launch and
quarterly afterward.

## 6. Monitoring and routine operations

- Poll `https://<DOMAIN>/ready` every minute from outside the VM.
- Alert on API 5xx, readiness failures, worker exits, disk above 75%, memory
  pressure, and MySQL volume growth.
- Docker logs rotate at 20 MB with five files per container.
- Configure provider-side spending limits for every model/API key.
- Take a VM snapshot before the first real-user release, but do not treat a
  snapshot as the only database backup.

## 7. Build the mobile release against production

The API URL is compiled into the Flutter application:

```bash
cd mobile
flutter build apk --release --dart-define=API_BASE=https://api.example.com
```

Use the same `API_BASE` for the signed iOS/Android release and smoke-test login,
capture, chat streaming, report generation, media links, notifications, and a
device reconnect against production before distributing the build.
