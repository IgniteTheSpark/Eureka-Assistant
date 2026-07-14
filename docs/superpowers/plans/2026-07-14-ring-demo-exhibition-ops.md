# Ring Demo Exhibition Operations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a safe current-user workspace reset to the Demo website and provide repeatable macOS setup/run tooling for exhibition staff.

**Architecture:** A feature-gated FastAPI endpoint deletes only the authenticated user's content in one transaction while preserving User, User Skills, Connected Apps, and card/ring configuration. A weakly surfaced Operator Controls panel calls the endpoint with confirmation; repository scripts standardize dependency setup and four-process startup.

**Tech Stack:** FastAPI, SQLAlchemy async, MySQL 8, React/TypeScript, shell scripts, Docker Compose.

## Global Constraints

- `POST /api/demo/reset` defaults disabled and requires both `DEMO_RESET_ENABLED=true` and a valid JWT.
- Reset only the authenticated user; never call or expose `backend/scripts/clear_data.py`.
- Preserve `users`, `user_skills`, `global_skills`, `connected_apps`, `cards`, and `card_bindings`.
- Delete workspace content atomically and return per-table counts.
- Keep the physical ring connected after a successful reset.
- Do not put API keys, passwords, or reset secrets in committed frontend code.
- Setup/run scripts support macOS only and must not erase Docker volumes.

---

## File Structure

- Modify `backend/config.py`: `demo_reset_enabled` setting.
- Modify `.env.example` and `docker-compose.yml`: explicit feature flag wiring.
- Create `backend/core/demo_reset.py`: scoped transactional deletion service.
- Create `backend/api/demo.py`: authenticated feature-gated endpoint.
- Modify `backend/main.py`: register the router.
- Create `backend/scripts/test_demo_reset.py`: two-user MySQL integration contract.
- Modify `ring-demo/src/lib/backend-client.ts`: reset method.
- Create `ring-demo/src/components/OperatorControls.tsx` and test.
- Modify `ring-demo/src/app/App.tsx` and Flash state ownership to clear UI after reset.
- Create `scripts/setup-ring-demo.sh` and `scripts/run-ring-demo.sh`.
- Modify `README.md`: exhibition setup, reset, and troubleshooting.

---

### Task 1: Feature-Gated Current-User Reset Service

**Files:**
- Modify: `backend/config.py`
- Modify: `.env.example`
- Modify: `docker-compose.yml`
- Create: `backend/core/demo_reset.py`
- Create: `backend/scripts/test_demo_reset.py`

**Interfaces:**
- Produces: `async reset_demo_workspace(db: AsyncSession, user_id: str) -> dict[str, int]`.
- Preserves configuration tables and deletes content tables in one transaction.

- [ ] **Step 1: Write the failing two-user integration test**

```python
async def test_reset_is_user_scoped():
    user_a = await seed_user("demo-a@example.com")
    user_b = await seed_user("demo-b@example.com")
    await seed_workspace(user_a)
    await seed_workspace(user_b)
    async with AsyncSessionLocal() as db:
        counts = await reset_demo_workspace(db, user_a)
        await db.commit()
    assert counts["assets"] == 1
    assert await count(Asset, user_a) == 0
    assert await count(Asset, user_b) == 1
    assert await count(UserSkill, user_a) > 0
    assert await count(ConnectedApp, user_a) == 1
```

The script must clean up its own fixture users in `finally`, and must never touch pre-existing rows.

- [ ] **Step 2: Run and verify the test fails**

Run: `docker compose exec backend python -m scripts.test_demo_reset`
Expected: FAIL because `core.demo_reset` does not exist.

- [ ] **Step 3: Add the setting and transactional service**

```python
class Settings(BaseSettings):
    demo_reset_enabled: bool = False
```

```python
async def _delete(db, model, user_id: str) -> int:
    result = await db.execute(delete(model).where(model.user_id == user_id))
    return int(result.rowcount or 0)


async def reset_demo_workspace(db, user_id: str) -> dict[str, int]:
    counts: dict[str, int] = {}
    await db.execute(
        update(Session)
        .where(Session.user_id == user_id)
        .values(event_id=None, contact_id=None, file_id=None, subject_asset_id=None)
    )
    event_ids = select(Event.id).where(Event.user_id == user_id)
    counts["event_attendees"] = _rowcount(await db.execute(
        delete(EventAttendee).where(EventAttendee.event_id.in_(event_ids))
    ))
    counts["event_files"] = _rowcount(await db.execute(
        delete(EventFile).where(EventFile.event_id.in_(event_ids))
    ))
    for model in (
        FlashRecording, Message, Task, Notification, Report, Nudge,
        CompletionEvent, RhythmProfile, AssetField, Asset, Event, Contact,
        InputTurn, Session, File, Pet,
    ):
        counts[model.__tablename__] = await _delete(db, model, user_id)
    return counts
```

Delete `Task` before `Asset`, joins before `Event/Contact/File`, and `FlashRecording` before `InputTurn/Session/File`. Execute the service inside the endpoint's `async with db.begin()` so exceptions roll back all statements.

Wire `DEMO_RESET_ENABLED=${DEMO_RESET_ENABLED:-false}` into Docker Compose and document it in `.env.example` as exhibition-only.

- [ ] **Step 4: Verify isolation, preservation, and rollback**

Run: `docker compose exec backend python -m scripts.test_demo_reset`
Expected: PASS for current-user deletion, second-user preservation, User/UserSkill/ConnectedApp/CardBinding preservation, counts, and forced-error rollback.

- [ ] **Step 5: Commit**

```bash
git add backend/config.py backend/core/demo_reset.py backend/scripts/test_demo_reset.py .env.example docker-compose.yml
git commit -m "feat(backend): add scoped demo workspace reset"
```

### Task 2: Authenticated Reset Endpoint

**Files:**
- Create: `backend/api/demo.py`
- Modify: `backend/main.py`
- Modify: `backend/scripts/test_demo_reset.py`

**Interfaces:**
- Produces: `POST /api/demo/reset -> {ok: true, deleted: Record<string, number>}`.
- Returns 404 when disabled and 401 without a valid Bearer token.

- [ ] **Step 1: Add failing endpoint assertions**

```python
disabled = client.post("/api/demo/reset", headers=auth_headers(token))
assert disabled.status_code == 404

settings.demo_reset_enabled = True
unauthorized = client.post("/api/demo/reset")
assert unauthorized.status_code == 401

response = client.post("/api/demo/reset", headers=auth_headers(token))
assert response.status_code == 200
assert response.json()["ok"] is True
```

- [ ] **Step 2: Run and verify failure**

Run: `docker compose exec backend python -m scripts.test_demo_reset`
Expected: FAIL because `/api/demo/reset` is not registered.

- [ ] **Step 3: Implement and register the endpoint**

```python
router = APIRouter()


@router.post("/demo/reset")
async def reset_demo(user_id: str = Depends(get_current_user_id)):
    if not settings.demo_reset_enabled:
        raise HTTPException(status_code=404, detail="not found")
    async with AsyncSessionLocal() as db:
        async with db.begin():
            deleted = await reset_demo_workspace(db, user_id)
    return {"ok": True, "deleted": deleted}
```

Register `api.demo.router` in `backend/main.py` under prefix `/api`.

- [ ] **Step 4: Run reset and Flash regression checks**

Run: `docker compose exec backend python -m scripts.test_demo_reset`
Expected: PASS.
Run: `docker compose exec backend python -m scripts.test_flash_text_terminal_status`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/api/demo.py backend/main.py backend/scripts/test_demo_reset.py
git commit -m "feat(backend): expose authenticated demo reset"
```

### Task 3: Demo Website Operator Controls

**Files:**
- Modify: `ring-demo/src/lib/backend-client.ts`
- Create: `ring-demo/src/components/OperatorControls.tsx`
- Create: `ring-demo/src/components/OperatorControls.test.tsx`
- Modify: `ring-demo/src/app/App.tsx`
- Modify: `ring-demo/src/state/demo-store.tsx`
- Modify: `ring-demo/src/styles.css`

**Interfaces:**
- `BackendClient.resetDemo() -> Promise<{ok: true; deleted: Record<string, number>}>`.
- `DemoStore.resetLocalExperience()` clears transcript/results/errors but retains Ring connection and Demo Session.

- [ ] **Step 1: Write failing confirmation/reset tests**

```tsx
it("requires confirmation before resetting the current demo account", async () => {
  render(<OperatorControls />);
  await user.click(screen.getByRole("button", { name: /operator controls/i }));
  await user.click(screen.getByRole("button", { name: /reset demo data/i }));
  expect(backend.resetDemo).not.toHaveBeenCalled();
  await user.click(screen.getByRole("button", { name: /confirm reset/i }));
  expect(backend.resetDemo).toHaveBeenCalledTimes(1);
  expect(demo.resetLocalExperience).toHaveBeenCalledTimes(1);
});
```

- [ ] **Step 2: Run and verify failure**

Run: `cd ring-demo && npm test -- --run src/components/OperatorControls.test.tsx`
Expected: FAIL because Operator Controls are missing.

- [ ] **Step 3: Implement the reset client and weakly surfaced panel**

```ts
resetDemo() {
  return this.authorizedRequest<DemoResetResponse>("/api/demo/reset", {
    method: "POST",
  });
}
```

The panel must show the logged-in email, require an explicit second click, disable controls while pending, display returned total deletion count, retain all UI state on failure, and call `resetLocalExperience()` only after HTTP success. Mount it in the shared App shell so it is reachable from Home, Flash, and Vibe without becoming a primary CTA.

- [ ] **Step 4: Verify all Web checks**

Run: `cd ring-demo && npm test -- --run && npm run typecheck && npm run build`
Expected: PASS, including success, cancel, 404-disabled, 401-login redirect, and server-error preservation.

- [ ] **Step 5: Commit**

```bash
git add ring-demo/src
git commit -m "feat(demo): add exhibition reset controls"
```

### Task 4: macOS Setup and Run Scripts

**Files:**
- Create: `scripts/setup-ring-demo.sh`
- Create: `scripts/run-ring-demo.sh`
- Modify: `README.md`

**Interfaces:**
- `scripts/setup-ring-demo.sh`: checks prerequisites, creates local env/config/venv, installs dependencies, migrates/seeds Backend.
- `scripts/run-ring-demo.sh`: starts Docker services and Vite, then runs Ring Desktop in the foreground with cleanup traps.

- [ ] **Step 1: Implement non-destructive setup checks**

```bash
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
for cmd in docker node npm python3; do
  command -v "$cmd" >/dev/null || { echo "Missing prerequisite: $cmd" >&2; exit 1; }
done
if [[ ! -f "$ROOT/.env" ]]; then
  cp "$ROOT/.env.example" "$ROOT/.env"
  echo "Created .env. Add DEEPSEEK_API_KEY and set DEMO_RESET_ENABLED=true, then rerun."
  exit 2
fi
python3 -m venv "$ROOT/ring-desktop/.venv"
"$ROOT/ring-desktop/.venv/bin/pip" install -r "$ROOT/ring-desktop/requirements.txt"
[[ -f "$ROOT/ring-desktop/config.json" ]] || cp "$ROOT/ring-desktop/config.example.json" "$ROOT/ring-desktop/config.json"
npm --prefix "$ROOT/ring-demo" install
docker compose -f "$ROOT/docker-compose.yml" up -d db
docker compose -f "$ROOT/docker-compose.yml" run --rm backend alembic upgrade head
docker compose -f "$ROOT/docker-compose.yml" run --rm backend python -m db.seed
```

- [ ] **Step 2: Implement the foreground runner with cleanup**

```bash
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
docker compose -f "$ROOT/docker-compose.yml" up -d db backend
npm --prefix "$ROOT/ring-demo" run dev -- --host 127.0.0.1 &
WEB_PID=$!
cleanup() { kill "$WEB_PID" 2>/dev/null || true; }
trap cleanup EXIT INT TERM
cd "$ROOT/ring-desktop"
exec .venv/bin/python -m ring_desktop.app
```

- [ ] **Step 3: Lint scripts and document exhibition flow**

Run: `zsh -n scripts/setup-ring-demo.sh scripts/run-ring-demo.sh`
Expected: exit 0.
Document setup, `DEMO_RESET_ENABLED=true`, first-time permissions, opening `http://localhost:5173`, Demo account login, Operator Reset, and troubleshooting for ports 8000/5173/17863.

- [ ] **Step 4: Run the full exhibition verification**

Run: `cd ring-desktop && pytest -q`
Run: `cd ring-demo && npm test -- --run && npm run typecheck && npm run build`
Run: `docker compose exec backend python -m scripts.test_demo_reset`
Run: `zsh -n scripts/setup-ring-demo.sh scripts/run-ring-demo.sh`
Expected: all exit 0.

Perform one real-account cycle: create Flash assets, open the same account in UReka, confirm shared data, use Operator Reset, confirm UReka content is empty, confirm Skills/Connected Apps/account persist, and immediately create a new Flash asset without reconnecting the ring.

- [ ] **Step 5: Commit**

```bash
git add scripts/setup-ring-demo.sh scripts/run-ring-demo.sh README.md
git commit -m "docs(demo): add exhibition setup and run flow"
```
