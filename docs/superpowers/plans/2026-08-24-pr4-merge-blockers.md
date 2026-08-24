# PR #4 Merge Blockers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make PR #4 safe to merge by fixing the authentication transaction/concurrency gaps, reducing onboarding to curated record types and curated field selection, hardening onboarding idempotency, validating production JWT configuration, and regenerating the Flutter lockfile.

**Architecture:** Keep `UserAccount.onboarding_status` and `UserSkill` as the durable backend truth. Authentication mutations use row locks and transaction boundaries that make verification-code consumption atomic with the protected business mutation, while invalid-code counters and login attempts are persisted independently. Onboarding accepts only catalog identifiers and field keys, derives all schema metadata server-side, and binds every confirmation idempotency key to a canonical request fingerprint. Flutter owns only transient page state and retry-key reuse.

**Tech Stack:** FastAPI, Pydantic v2, SQLAlchemy async, MySQL 8, Alembic, pytest/httpx, Flutter/Dart, SharedPreferences removal, `package:uuid`.

## Global Constraints

- Work only in `/Users/admin/workwork/eureka-staff/Eureka-Assistant/.worktrees/pr4-merge-blockers` on `codex/pr4-merge-blockers`.
- Preserve all PR #4 commits by building on `589ae76334f59fdbca3fe4e40c038b6602776afe`; do not rewrite existing migrations.
- Follow strict RED → GREEN → REFACTOR for every behavior change. Run the named failing test before editing production code.
- Use only focused test files and changed-file analysis during implementation. A repository-wide suite requires a separate explanation, estimate, and user confirmation.
- Onboarding copy says “记录类型”, never “技能”. The backend may continue storing `UserSkill` internally.
- Onboarding permits exactly the four catalog categories `running`, `drinking_water`, `baby_feeding`, and `dancing`; fields are a non-empty subset of that category's curated fields.
- Do not implement export streaming, accessibility enhancements, migration-history cleanup, or personal-center record-type management in this branch.
- Do not commit generated Flutter state such as `.dart_tool/`, `.flutter-plugins-dependencies`, or `pubspec_overrides.yaml`; only `mobile/pubspec.lock` is expected from dependency resolution.

---

### Task 1: Make verification challenges newest-only and business-transaction atomic

**Files:**

- Modify: `theme_v2_service/app/auth/challenges.py`
- Modify: `theme_v2_service/app/auth/api.py`
- Test: `theme_v2_service/tests/unit/test_email_challenges.py`
- Test: `theme_v2_service/tests/contract/test_auth_api.py`

**Step 1: Write failing challenge-lifecycle tests**

Add these cases to `test_email_challenges.py`:

```python
async def test_issuing_new_challenge_invalidates_older_unconsumed_code(session):
    first, first_code = await issue_challenge(
        session,
        email="newest@example.com",
        purpose=CHALLENGE_REGISTER,
        request_ip="1.2.3.4",
    )
    first.sent_at = _now() - timedelta(seconds=120)
    scope_type, scope_hash = _bucket_key("email-cooldown", "newest@example.com")
    await session.execute(
        update(EmailRateLimitBucket)
        .where(
            EmailRateLimitBucket.scope_type == scope_type,
            EmailRateLimitBucket.scope_hash == scope_hash,
        )
        .values(last_request_at=first.sent_at)
    )
    second, second_code = await issue_challenge(
        session,
        email="newest@example.com",
        purpose=CHALLENGE_REGISTER,
        request_ip="1.2.3.4",
    )
    assert first.consumed_at is not None
    found = await find_active_challenge(
        session,
        email="newest@example.com",
        purpose=CHALLENGE_REGISTER,
    )
    assert found.id == second.id
    with pytest.raises(ChallengeConsumedError):
        await verify_code(session, challenge=first, code=first_code)
    assert await verify_code(session, challenge=second, code=second_code)

async def test_invalid_code_counter_survives_caller_rollback(session):
    challenge, _ = await issue_challenge(
        session,
        email="failure@example.com",
        purpose=CHALLENGE_REGISTER,
        request_ip="1.2.3.4",
    )
    await session.commit()
    with pytest.raises(ChallengeInvalidError):
        await verify_code(session, challenge=challenge, code="000000")
    await session.rollback()
    async with AsyncSessionFactory() as fresh:
        assert (await fresh.get(EmailVerificationChallenge, challenge.id)).failed_attempts == 1
```

Add two contract fault-injection cases to `test_auth_api.py`. The first obtains
a registration code through the existing fake sender, monkeypatches
`app.auth.api.ensure_capture_skills` to raise `RuntimeError("baseline failed")`,
posts the otherwise-valid registration body, then uses `AsyncSessionFactory`
to assert both that no `UserAccount` exists and that the newest register
challenge still has `consumed_at is None`. The second registers a user, obtains
a password-reset code, monkeypatches `app.auth.api.hash_password` to raise
`RuntimeError("hash failed")`, posts the reset, and asserts the newest reset
challenge remains unconsumed and the original password still logs in.

**Step 2: Run RED tests**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test \
  python -m pytest -q \
  tests/unit/test_email_challenges.py \
  tests/contract/test_auth_api.py \
  -k 'invalidates_older or rolls_back_code_consumption or invalid_code_counter'
```

Expected: the old challenge remains unconsumed, or the endpoint consumes the challenge before the injected business failure.

**Step 3: Implement newest-only challenge issuance**

In `issue_challenge`, after rate-limit reservation and before adding the new row, consume every older unconsumed row of the same email and purpose. The same email bucket already serializes issuance; keep the invalidation in the request transaction so a delivery failure rolls it back:

```python
await session.execute(
    update(EmailVerificationChallenge)
    .where(
        EmailVerificationChallenge.email == email,
        EmailVerificationChallenge.purpose == purpose,
        EmailVerificationChallenge.consumed_at.is_(None),
    )
    .values(consumed_at=now)
)
```

Keep the `find_active_challenge` query's `.with_for_update()` and successful
`verify_code` as flush-only. Preserve the existing invalid-code behavior that
commits the locked counter row before raising. Both verification endpoints must
continue to call `verify_code` before making any business writes, so that this
failure-only commit cannot accidentally commit account changes. Add a contract
assertion for that ordering and clarify it in the function docstring. Do not
open a second session while the caller owns the challenge row lock; that would
self-block on MySQL.

**Step 4: Remove premature success commits**

Delete the success-path `await session.commit()` after `verify_code` in both `/register` and `/password-reset`. Challenge consumption, account creation/baseline skills, and password reset must commit together through `get_session`.

**Step 5: Run GREEN tests and adjacent auth tests**

Run the two full focused files:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test \
  python -m pytest -q \
  tests/unit/test_email_challenges.py \
  tests/contract/test_auth_api.py
```

Expected: all pass.

**Step 6: Commit**

```bash
git add theme_v2_service/app/auth/challenges.py \
  theme_v2_service/app/auth/api.py \
  theme_v2_service/tests/unit/test_email_challenges.py \
  theme_v2_service/tests/contract/test_auth_api.py
git commit -m "fix: make verification consumption atomic"
```

---

### Task 2: Serialize password mutations and bound login/PBKDF work

**Files:**

- Modify: `theme_v2_service/app/auth/security.py`
- Modify: `theme_v2_service/app/auth/challenges.py`
- Modify: `theme_v2_service/app/auth/api.py`
- Modify: `theme_v2_service/app/account/api.py`
- Modify: `theme_v2_service/app/account/deletion.py`
- Modify: `theme_v2_service/app/config.py`
- Test: `theme_v2_service/tests/contract/test_auth_api.py`
- Test: `theme_v2_service/tests/contract/test_account_api.py`
- Test: `theme_v2_service/tests/unit/test_auth.py`

**Step 1: Write failing input, timing-boundary, rate-limit, and concurrency tests**

Add contract tests covering:

```python
@pytest.mark.parametrize("path,body", [
    ("/api/auth/login", {"email": "x" * 321, "password": "Secret123!"}),
    ("/api/auth/register", {
        "email": "person@example.com",
        "verification_code": "12345",
        "password": "Secret123!",
        "terms_version": "2026-08-v1",
        "terms_accepted": True,
    }),
    ("/api/auth/password-reset", {
        "email": "person@example.com",
        "verification_code": "123456",
        "new_password": "X" * 129,
    }),
])
async def test_auth_request_limits_are_rejected_before_handler(client, path, body):
    assert (await client.post(path, json=body)).status_code == 422

async def test_login_rate_limit_counts_failed_attempts(client, monkeypatch):
    monkeypatch.setenv("LOGIN_ATTEMPTS_PER_EMAIL_15_MIN", "2")
    get_settings.cache_clear()
    await client.post("/api/auth/login", json={
        "email": "limited@example.com", "password": "Wrong123!"
    })
    await client.post("/api/auth/login", json={
        "email": "limited@example.com", "password": "Wrong123!"
    })
    third = await client.post("/api/auth/login", json={
        "email": "limited@example.com", "password": "Wrong123!"
    })
    assert third.status_code == 429
    assert third.headers["retry-after"]

async def test_unknown_and_deleted_login_use_dummy_verification(client, monkeypatch):
    calls = []
    monkeypatch.setattr(auth_api, "verify_password_async", recording_verify)
    await client.post("/api/auth/login", json={
        "email": "unknown@example.com", "password": "Wrong123!"
    })
    await client.post("/api/auth/login", json={
        "email": "deleted@example.com", "password": "Wrong123!"
    })
    assert len(calls) == 2
    assert all(stored.startswith("pbkdf2_sha256$") for _, stored in calls)
```

Add real two-session races for password reset and account password change. Each test starts both transactions from the same original `auth_version`, coordinates them with events, and asserts either serialization or one stale attempt rejection; no two replacement tokens with the same final version may remain valid.

Add a soft-delete/password-change race in `test_account_api.py` and assert a deleted account cannot regain a password or valid session.

**Step 2: Run RED tests**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test \
  python -m pytest -q \
  tests/contract/test_auth_api.py \
  tests/contract/test_account_api.py \
  tests/unit/test_auth.py \
  -k 'request_limits or login_rate_limit or dummy or concurrent or race'
```

Expected: oversized inputs reach handlers, login attempts are unlimited, password hashes run synchronously, and concurrent mutations lose an `auth_version` increment.

**Step 3: Add bounded async password helpers**

Keep the synchronous primitives for unit compatibility but add one process-wide limiter and async wrappers in `security.py`:

```python
_password_work_slots = asyncio.Semaphore(8)

async def hash_password_async(password: str) -> str:
    async with _password_work_slots:
        return await asyncio.to_thread(hash_password, password)

async def verify_password_async(password: str, stored: str) -> bool:
    async with _password_work_slots:
        return await asyncio.to_thread(verify_password, password, stored)

_DUMMY_PASSWORD_HASH = hash_password("dummy-account-password-never-used")
```

Generate the dummy hash once as a source constant so an unknown account does the same PBKDF operation without per-request random hashing.

**Step 4: Add atomic login-attempt reservation**

Expose a `reserve_login_attempt` helper that uses the existing MySQL bucket primitive for two fixed 900-second scopes:

```python
async def reserve_login_attempt(*, email: str, request_ip: str | None) -> int:
    async with AsyncSessionFactory.begin() as limiter_session:
        now = _now()
        email_ok = await _reserve_bucket(
            limiter_session,
            key=_bucket_key("login-email-15m", email),
            window_seconds=900,
            limit=settings.login_attempts_per_email_15_min,
            now=now,
        )
        ip_ok = request_ip is None or await _reserve_bucket(
            limiter_session,
            key=_bucket_key("login-ip-15m", request_ip),
            window_seconds=900,
            limit=settings.login_attempts_per_ip_15_min,
            now=now,
        )
        if not email_ok or not ip_ok:
            raise LoginRateLimitError(retry_after_seconds=900)
```

Call it before loading the user or verifying the password. Return HTTP 429 with `Retry-After`.

Add settings with safe defaults:

```python
login_attempts_per_email_15_min: int = Field(default=10, ge=1)
login_attempts_per_ip_15_min: int = Field(default=50, ge=1)
```

**Step 5: Lock account rows and use async password work**

For password reset, password change, and soft delete, load the row with a locking `SELECT` before checking or mutating it:

```python
user = await session.scalar(
    select(UserAccount)
    .where(UserAccount.id == user_id)
    .with_for_update()
)
```

Use `verify_password_async` and `hash_password_async`, and keep `auth_version += 1` inside the locked transaction. Password reset must lock the account before consuming the challenge so concurrent reset attempts serialize consistently. Deleted accounts remain uniformly rejected.

**Step 6: Enforce Pydantic request bounds**

Use constrained fields on all public auth/account schemas:

```python
email: str = Field(min_length=3, max_length=320)
password: str = Field(min_length=1, max_length=128)
verification_code: str = Field(pattern=r"^\d{6}$")
new_password: str = Field(min_length=8, max_length=128)
```

Do not weaken the existing password complexity validator.

**Step 7: Run GREEN tests**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test \
  python -m pytest -q \
  tests/contract/test_auth_api.py \
  tests/contract/test_account_api.py \
  tests/unit/test_auth.py \
  tests/unit/test_email_challenges.py
```

Expected: all pass, including repeated two-session race cases.

**Step 8: Commit**

```bash
git add theme_v2_service/app/auth/security.py \
  theme_v2_service/app/auth/challenges.py \
  theme_v2_service/app/auth/api.py \
  theme_v2_service/app/account/api.py \
  theme_v2_service/app/account/deletion.py \
  theme_v2_service/app/config.py \
  theme_v2_service/tests/contract/test_auth_api.py \
  theme_v2_service/tests/contract/test_account_api.py \
  theme_v2_service/tests/unit/test_auth.py
git commit -m "fix: serialize account credentials and limit login work"
```

---

### Task 3: Enforce preset-only onboarding and payload-bound idempotency

**Files:**

- Modify: `theme_v2_service/app/domains/onboarding/api.py`
- Modify: `theme_v2_service/app/domains/onboarding/service.py`
- Modify: `theme_v2_service/app/domains/onboarding/catalog.py`
- Create: `theme_v2_service/migrations/versions/0032_onboarding_request_fingerprint.py`
- Modify: `theme_v2_service/tests/contract/test_onboarding_api.py`
- Modify: `theme_v2_service/tests/unit/test_onboarding_service.py`
- Modify: `theme_v2_service/tests/integration/test_migrations.py`

**Step 1: Write failing preset-contract and preview tests**

Replace custom-category tests with:

```python
async def test_skill_creation_accepts_only_curated_category_and_field_keys(client):
    response = await client.post("/api/onboarding/skills", json={
        "category": "running",
        "field_keys": ["distance_km", "duration_min"],
    }, headers=headers)
    assert response.status_code == 200
    assert set(response.json()["skill"]["schema"]["properties"]) == {
        "distance_km", "duration_min"
    }

@pytest.mark.parametrize("body", [
    {"category": "sleep", "field_keys": ["hours"]},
    {"category": "running", "field_keys": []},
    {"category": "running", "field_keys": ["distance_km", "distance_km"]},
    {"category": "running", "field_keys": ["unknown"]},
    {"category": "running", "fields": [{"key": "distance_km", "type": "text"}]},
])
async def test_skill_creation_rejects_non_catalog_schema_input(client, body):
    response = await client.post(
        "/api/onboarding/skills", headers=headers, json=body
    )
    assert response.status_code in {400, 422}
```

Extend manual preview coverage so missing numeric fields preserve their catalog type:

```python
assert {field["key"]: field["type"] for field in body["manual_fields"]}[
    "distance_km"
] == "number"
```

**Step 2: Write failing idempotency tests**

Add three concrete contract cases. Reuse the existing `confirm` request shape:

1. Post `{distance_km: 5}` twice with key `same-payload` and assert both responses
   carry the same `asset_id`, with `created` changing from true to false.
2. Post `{distance_km: 5}` and then `{distance_km: 6}` with key
   `different-payload` and assert the second response is HTTP 409.
3. Create an asset and marker through the first request, set that marker's
   `request_fingerprint` to null through `AsyncSessionFactory`, then assert an
   identical retry backfills and succeeds while a changed retry is HTTP 409.

Update the migration round-trip assertion to expect `0032_onboarding_request_fp` and a nullable `request_fingerprint VARCHAR(64)` column.

**Step 3: Run RED tests**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test \
  python -m pytest -q \
  tests/contract/test_onboarding_api.py \
  tests/unit/test_onboarding_service.py \
  -k 'curated or catalog_schema or preserves or fingerprint or different_payload'
```

Expected: the old `fields` contract accepts arbitrary schema, missing numeric fields are mutated to text, and key reuse with a different payload silently replays the first asset.

**Step 4: Derive schema exclusively from the catalog**

Change the public request:

```python
class SkillFieldsRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    category: str = Field(min_length=1, max_length=100)
    field_keys: list[str] = Field(min_length=1, max_length=30)
```

Replace the `create_onboarding_skill` `fields` argument with `field_keys`. Validate category existence, duplicates, and subset membership, then retain catalog order:

```python
entry = get_category(category)
if entry is None:
    raise OnboardingError("记录类型不在预制目录中")
if len(field_keys) != len(set(field_keys)):
    raise OnboardingError("记录字段不能重复")
fields_by_key = {field["key"]: field for field in entry["fields"]}
if any(key not in fields_by_key for key in field_keys):
    raise OnboardingError("记录字段不属于所选类型")
fields = [field for field in entry["fields"] if field["key"] in set(field_keys)]
```

Delete custom-category field validation and update the module contract. In `extract_preview`, remove `field["type"] = "text"`; extraction state is represented by payload membership, not schema mutation.

**Step 5: Add fingerprint migration and model field**

Create forward migration file `0032_onboarding_request_fingerprint.py` with Alembic revision `0032_onboarding_request_fp` from `0031_challenge_indexes`:

```python
def upgrade() -> None:
    op.add_column(
        "onboarding_asset_results",
        sa.Column("request_fingerprint", sa.String(length=64), nullable=True),
    )

def downgrade() -> None:
    op.drop_column("onboarding_asset_results", "request_fingerprint")
```

Add the nullable mapped column to `AssetResultMarker`.

**Step 6: Bind confirmation retries to canonical content**

Canonicalize `skill_id` plus the JSON payload with sorted keys and compact separators:

```python
def _confirmation_fingerprint(skill_id: str, payload: dict) -> str:
    canonical = json.dumps(
        {"skill_id": skill_id, "payload": payload},
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()
```

For an existing marker:

- equal stored fingerprint: return its asset;
- different non-null fingerprint: raise `IdempotencyConflict` and map to HTTP 409;
- null legacy fingerprint: load the owned `Asset`, derive its fingerprint from `user_skill_id` and `payload_json`, backfill only if it matches; otherwise return 409.

On create, persist `request_fingerprint=fingerprint`. On `IntegrityError`, re-read the winner and run the same comparison instead of returning it unconditionally.

**Step 7: Run GREEN tests, including migration round-trip only after the focused contract is green**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test \
  python -m pytest -q \
  tests/contract/test_onboarding_api.py \
  tests/unit/test_onboarding_service.py
docker compose -f docker-compose.theme-v2.yml run --rm test \
  python -m pytest -q tests/integration/test_migrations.py \
  -k foundation_migration_round_trip_and_physical_types
```

Expected: both commands pass and Alembic head is `0032_onboarding_request_fp`.

**Step 8: Commit**

```bash
git add theme_v2_service/app/domains/onboarding/api.py \
  theme_v2_service/app/domains/onboarding/service.py \
  theme_v2_service/app/domains/onboarding/catalog.py \
  theme_v2_service/migrations/versions/0032_onboarding_request_fingerprint.py \
  theme_v2_service/tests/contract/test_onboarding_api.py \
  theme_v2_service/tests/unit/test_onboarding_service.py \
  theme_v2_service/tests/integration/test_migrations.py
git commit -m "fix: constrain onboarding to curated record types"
```

---

### Task 4: Simplify Flutter onboarding and make retries deterministic

**Files:**

- Modify: `mobile/lib/theme_v2/onboarding/onboarding_repository.dart`
- Modify: `mobile/lib/theme_v2/onboarding/onboarding_controller.dart`
- Modify: `mobile/lib/theme_v2/onboarding/onboarding_page.dart`
- Modify: `mobile/test/theme_v2/onboarding/onboarding_test_helpers.dart`
- Modify: `mobile/test/theme_v2/onboarding/onboarding_controller_test.dart`
- Modify: `mobile/test/theme_v2/onboarding/onboarding_page_test.dart`

**Step 1: Write failing controller tests**

Cover all four local fallback categories, no custom-category insertion, preset field-key serialization, busy notification, error notification, and retry-key rotation:

```dart
test('fallback catalog contains all curated record types and no custom type', () async {
  final controller = OnboardingController(repository: failingRepository);
  await controller.loadCatalog();
  expect(controller.categories.map((item) => item['id']),
      containsAll(['running', 'drinking_water', 'baby_feeding', 'dancing']));
  expect(controller.categories.map((item) => item['id']), isNot(contains('custom')));
});

test('same canonical confirmation retries reuse one UUID and changed payload rotates it', () async {
  repository.failConfirm = true;
  await controller.confirmFromEdits(rawValues: {'distance_km': '5'});
  final firstKey = repository.lastIdempotencyKey;
  await controller.confirmFromEdits(rawValues: {'distance_km': '5'});
  expect(repository.lastIdempotencyKey, firstKey);
  await controller.confirmFromEdits(rawValues: {'distance_km': '6'});
  expect(repository.lastIdempotencyKey, isNot(firstKey));
});
```

Use a delayed fake to assert a second create/preview/confirm/skip call is ignored while busy, listeners receive both busy-on and busy-off, and entered source/edit values remain after failure.

**Step 2: Write failing widget tests**

Add widget assertions:

- category screen has a back button and a skip action;
- only four preset records are shown;
- field screen has no custom-field text box or Add button;
- selected fields are multi-select and at least one is required;
- buttons display/disable during busy states;
- failed preview/confirm displays the error without clearing source/editor values.

**Step 3: Run RED Flutter tests**

Run from `mobile/`:

```bash
flutter test \
  test/theme_v2/onboarding/onboarding_controller_test.dart \
  test/theme_v2/onboarding/onboarding_page_test.dart
```

Expected: custom UI is still present, only running is available offline, repeated submissions are allowed, and errors do not notify reliably.

**Step 4: Change repository and controller contract**

Repository sends only curated identifiers:

```dart
Future<Map<String, dynamic>> createSkill({
  required String category,
  required List<String> fieldKeys,
}) => _client.postJson('/api/onboarding/skills', {
  'category': category,
  'field_keys': fieldKeys,
});
```

Controller changes:

- mirror the full backend catalog locally;
- remove custom category/name/field state and methods;
- add explicit `creatingSkill`, `previewing`, `confirming`, and `skipping` flags;
- use `try/catch/finally` and always `notifyListeners()` on transitions;
- keep source/editor state outside `clear` until success;
- generate UUID v4 keys with `Uuid().v4()`;
- derive a stable canonical payload signature with recursively sorted map keys;
- retain `(signature, key)` only after a network confirm attempt; reuse on identical retry, rotate on changed payload; clear it after success.

The public `confirmFromEdits` no longer accepts an idempotency key from the page.

**Step 5: Simplify the page**

Remove `SharedPreferences`, `_customNameController`, `_customFieldController`, and page-level `_idempotencyKey`. Add reusable back/skip navigation on category and field steps. Replace “创建记录类型” with “继续”, remove all custom inputs, and wire buttons to the controller busy flags:

```dart
FilledButton(
  onPressed: controller.creatingSkill ? null : _createSkill,
  child: controller.creatingSkill
      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator())
      : const Text('继续'),
)
```

Preserve the existing fully skippable completion behavior through `AuthController.updateOnboardingStatus` after the backend reports success.

**Step 6: Run GREEN tests and changed-file analysis**

Run:

```bash
flutter test \
  test/theme_v2/onboarding/onboarding_controller_test.dart \
  test/theme_v2/onboarding/onboarding_page_test.dart
flutter analyze \
  lib/theme_v2/onboarding/onboarding_repository.dart \
  lib/theme_v2/onboarding/onboarding_controller.dart \
  lib/theme_v2/onboarding/onboarding_page.dart \
  test/theme_v2/onboarding/onboarding_controller_test.dart \
  test/theme_v2/onboarding/onboarding_page_test.dart
```

Expected: tests pass and analysis reports no errors or warnings in changed files.

**Step 7: Commit**

```bash
git add mobile/lib/theme_v2/onboarding/onboarding_repository.dart \
  mobile/lib/theme_v2/onboarding/onboarding_controller.dart \
  mobile/lib/theme_v2/onboarding/onboarding_page.dart \
  mobile/test/theme_v2/onboarding/onboarding_test_helpers.dart \
  mobile/test/theme_v2/onboarding/onboarding_controller_test.dart \
  mobile/test/theme_v2/onboarding/onboarding_page_test.dart
git commit -m "fix: simplify onboarding to curated record types"
```

---

### Task 5: Harden deployment configuration and regenerate the lockfile

**Files:**

- Modify: `theme_v2_service/app/config.py`
- Modify: `theme_v2_service/tests/unit/test_config.py`
- Modify: `mobile/pubspec.lock`

**Step 1: Write failing production JWT tests**

Add parameterized tests:

```python
@pytest.mark.parametrize("secret", [
    "short",
    "x" * 31,
    "replace-with-real-secret-that-is-long-enough",
    "example-secret-that-is-long-enough",
    "change-me-change-me-change-me-change-me",
    "test-secret-test-secret-test-secret-test",
])
def test_prod_rejects_short_or_placeholder_jwt_secret(secret):
    _assert_prod_rejects({"jwt_secret": secret})
```

Keep the approved merge-only behavior that absolute HTTPS `example.com` terms/privacy placeholders are accepted. Deployment remains responsible for replacing them.

**Step 2: Run RED config tests**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test \
  python -m pytest -q tests/unit/test_config.py \
  -k 'jwt_secret or placeholder'
```

Expected: production accepts short or marker-bearing JWT secrets other than the exact old default.

**Step 3: Harden the validator**

Require at least 32 UTF-8 bytes and reject case-insensitive secret markers:

```python
_JWT_SECRET_MARKERS = ("replace-with", "example", "change-me", "test-secret")

def _is_unsafe_jwt_secret(value: str) -> bool:
    normalized = value.strip().lower()
    return (
        len(value.encode("utf-8")) < 32
        or any(marker in normalized for marker in _JWT_SECRET_MARKERS)
    )
```

Apply only in `prod`/`production`; test/dev defaults remain usable.

**Step 4: Run GREEN config tests**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test \
  python -m pytest -q tests/unit/test_config.py
```

Expected: all pass.

**Step 5: Regenerate and audit Flutter lockfile**

From `mobile/` run:

```bash
flutter pub get
git diff -- pubspec.lock
git status --short
```

Expected: Baizhi OAuth transitive dependencies disappear, the current Flutter SDK test dependency chain is reflected, and no generated local state is staged.

Run a targeted dependency/build smoke check:

```bash
flutter pub deps --style=compact
flutter test test/auth/auth_controller_test.dart test/pages/login_page_test.dart
```

If these exact test paths differ, use `rg --files test | rg 'auth_controller|login_page'` and run only the matching auth tests.

**Step 6: Commit**

```bash
git add theme_v2_service/app/config.py \
  theme_v2_service/tests/unit/test_config.py \
  mobile/pubspec.lock
git commit -m "fix: harden production auth config and refresh lockfile"
```

---

### Task 6: Focused merge verification and branch publication

**Files:**

- Verify only; no expected production edits.

**Step 1: Run backend focused matrix**

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test \
  python -m pytest -q \
  tests/unit/test_email_challenges.py \
  tests/unit/test_auth.py \
  tests/unit/test_config.py \
  tests/unit/test_onboarding_service.py \
  tests/contract/test_auth_api.py \
  tests/contract/test_account_api.py \
  tests/contract/test_onboarding_api.py
```

Expected: all pass.

**Step 2: Run migration head round-trip**

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test \
  python -m pytest -q tests/integration/test_migrations.py \
  -k foundation_migration_round_trip_and_physical_types
```

Expected: pass at revision `0032_onboarding_request_fp`.

**Step 3: Run Flutter focused matrix**

```bash
cd mobile
flutter test \
  test/theme_v2/onboarding/onboarding_controller_test.dart \
  test/theme_v2/onboarding/onboarding_page_test.dart \
  test/auth/auth_controller_test.dart \
  test/pages/login_page_test.dart
flutter analyze \
  lib/theme_v2/onboarding/onboarding_repository.dart \
  lib/theme_v2/onboarding/onboarding_controller.dart \
  lib/theme_v2/onboarding/onboarding_page.dart
```

Expected: all selected tests pass; analysis has no error/warning in changed files.

**Step 4: Run static and diff checks**

```bash
python -m compileall -q theme_v2_service/app
git diff --check
git status --short
git log --oneline --decorate -8
```

If host Python cannot write bytecode outside the worktree, set `PYTHONPYCACHEPREFIX=/private/tmp/eureka-pr4-pycache` for this command. Expected: compile and diff checks exit 0; worktree is clean after commits.

**Step 5: Publish the replacement branch**

```bash
git push -u origin codex/pr4-merge-blockers
```

Do not merge locally. Report the branch name, commit list, focused verification evidence, the new migration requirement, and deployment placeholders still requiring replacement (`TERMS_URL`, `PRIVACY_URL`, `JWT_SECRET`, DirectMail credentials).
