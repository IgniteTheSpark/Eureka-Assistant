# Eureka 本地环境装机 + Step 1 验证(给新 Claude session 用)

> 目的:让一台全新 Mac 能跑起 Eureka 后端,完成 Phase C Step 1(数据库 schema)的验证。
> 范围:**只装 Docker(必装)+ Python 3.12(可选)**。backend 全在容器里跑,本机不需要 Postgres 或更多依赖。
> 上下文:Phase C 重建 Step 1 代码已落地,见 `Eureka-BrandNew/backend/db/`。

---

## 起点假设(已经在机器上探过的状态)

| 项 | 状态 |
|---|---|
| 架构 | macOS Apple Silicon(arm64),macOS 14.6.1+ |
| Homebrew | ✅ 已装于 `/opt/homebrew` |
| Xcode CLT | ✅ 已装(`/Library/Developer/CommandLineTools`) |
| 系统 Python | 3.9.6(stock) |
| Docker | ❌ 未装 |
| Python 3.12 | ❌ 未装(可选) |
| 项目路径 | `/Users/admin/workwork/eureka-staff/bizcard/Eureka-BrandNew` |

---

## Step A — 装 Docker Desktop(必做)

```bash
brew install --cask docker
```

~700MB 下载 + ~10 分钟。装完 `/Applications/Docker.app` 出现。

**启动 Docker daemon**(GUI app,需要用户手动一次,或用 open 命令):
```bash
open -a Docker
```
菜单栏出现鲸鱼图标后等它从「starting」变成可用,首次启动约 30-60 秒。

**验证**:
```bash
docker --version          # 期望:Docker version 24.x 之类
docker compose version    # 期望:Docker Compose version v2.x
docker run --rm hello-world
# 期望:"Hello from Docker!" 一大段问候
```

若 `Cannot connect to the Docker daemon`:Docker Desktop 没启动,重跑 `open -a Docker` 等 30 秒。

---

## Step B — 可选:装 Python 3.12

**本次验证不需要**。只有以后想本机不走容器直接跑 backend(`uvicorn main:app --reload`)才装。

```bash
brew install python@3.12
brew link python@3.12 --force
python3.12 --version
```

---

## Step C — Phase C Step 1 验证(数据层)

确认 Docker daemon 运行后:

```bash
cd /Users/admin/workwork/eureka-staff/bizcard/Eureka-BrandNew

# ── ① 清旧 volume(防之前残留)
docker compose down -v

# ── ② 起 db
docker compose up db -d

# ── ③ 等 db healthy(10-15 秒)
docker compose ps
# 期望:db 状态 "Up X seconds (healthy)"
# 若还是 "starting":再等 5 秒重跑 docker compose ps

# ── ④ Migration
docker compose run --rm backend alembic upgrade head
# 期望:
#   INFO  [alembic.runtime.migration] Running upgrade  -> 0001, initial schema — Phase B rebuild (post design integration)
# 然后无 ERROR

# ── ⑤ Seed
docker compose run --rm backend python -m db.seed
# 期望(顺序可能不同):
#   + global_skill: todo
#   + global_skill: event
#   + global_skill: idea
#   + global_skill: contact
#   + global_skill: expense
#   + global_skill: qa
#   + user_skill: todo
#   + user_skill: event
#   + user_skill: idea
#   + user_skill: contact
#   + user_skill: expense
#   + user_skill: qa
#   Seed complete.

# ── ⑥ 9 张表都建好了?
docker compose exec db psql -U eureka -d eureka -c "\dt"
# 期望(顺序可能不同):
#   alembic_version
#   asset_fields
#   assets
#   contacts
#   files
#   global_skills
#   input_turns
#   messages
#   sessions
#   user_skills
# 共 10 行(alembic_version + 9 业务表)

# ── ⑦ 6 个 GlobalSkill?
docker compose exec db psql -U eureka -d eureka -c "SELECT name FROM global_skills ORDER BY id;"
# 期望 6 行:todo / event / idea / contact / expense / qa

# ── ⑧ 6 个 UserSkill + render_spec?
docker compose exec db psql -U eureka -d eureka -c "SELECT display_name, render_spec IS NOT NULL AS has_render FROM user_skills ORDER BY created_at;"
# 期望 6 行,前 5 个 has_render=t,qa 那行 has_render=f
```

## ⑨ 通过的判定

以上 8 步全部按期望输出 = Phase C Step 1 数据层验证**通过**。可以回主 session 报告:
- "装机完成 + Step 1 通过",贴 ⑥ ⑦ ⑧ 三个 psql 输出(~20 行)即可

## 常见踩坑

| 现象 | 原因 / 解法 |
|---|---|
| `Cannot connect to the Docker daemon` | Docker Desktop 没启动 → `open -a Docker` 等 30 秒 |
| `permission denied` 装 cask | 用 admin 账号跑;cask 装 Docker.app 要写 `/Applications` |
| `ANTHROPIC_API_KEY` warning | 不影响 migration/seed;无视,或设个假值 `export ANTHROPIC_API_KEY=anything` |
| `port 5432 already in use` | 本机另有 postgres 占用 → `brew services stop postgresql` 或改 docker-compose.yml 改端口 |
| `pgvector` 扩展报错 | 镜像 `pgvector/pgvector:pg16` 自带 vector,正常不应报错;真报错的话联系主 session 看 schema |
| `psql` 连不上 | db 还没 healthy,`docker compose ps` 看状态,等 healthy 再试 |
| `relation "global_skills" does not exist` 在 ⑤ 步 | ④ migration 没跑或没跑通,回去重跑 ④ |

## 用法约定

- 需要 sudo 密码或 GUI 操作(Docker Desktop 启动)的环节,**告诉用户来做**;不要自己尝试输入密码
- 其它命令直接跑,关键输出贴出来确认
- 全过完报告「装机成功 + Step 1 验证通过/失败」+ ⑥⑦⑧ 输出

主 session 同时在并行推 Step 2(MCP server 实现),跟装机解耦不冲突。
