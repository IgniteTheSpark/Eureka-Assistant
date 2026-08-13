# M1 / M2 验证清单

> 用于验证 Theme V2 账号与 Onboarding 后端里程碑。
> 后端已运行:`http://127.0.0.1:8100`(验证码为 mock,从 `/tmp/eureka-api.log` 提取)。

## M1 — 账号注册 / 登录 / 验证码 / 密码重置 / auth_version

### 自动化测试(约 1 分钟)
```bash
cd /Users/mr.zhou/Desktop/Projects/kevin/Eureka-Assistant/theme_v2_service
DATABASE_URL="mysql://theme_v2:theme_v2@127.0.0.1:13307/eureka_theme_v2_test" \
/tmp/eureka-venv/bin/python -m pytest tests/unit/test_auth.py tests/unit/test_email_challenges.py tests/contract/test_auth_api.py -q
```
预期:`35 passed`

### 手动 curl 验证

**1. 请求注册验证码**
```bash
curl -s -X POST http://127.0.0.1:8100/api/auth/verification-codes \
  -H "Content-Type: application/json" -d '{"email":"verify1@test.com","purpose":"register"}'
```
预期:`{"ok":true,"resend_delay_seconds":60,"expires_in_seconds":600}`
从日志取码:`grep "verify1" /tmp/eureka-api.log | tail -1` → `code=XXXXXX`

**2. 注册(验证码 + 条款)**
```bash
curl -s -X POST http://127.0.0.1:8100/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"verify1@test.com","verification_code":"<code>","password":"secret123","terms_version":"2026-08-v1","terms_accepted":true}'
```
预期:`{"ok":true,"token":"...","user":{"email":"verify1@test.com","email_verified":true,"onboarding_status":"pending"}}`

**3. 登录**
```bash
curl -s -X POST http://127.0.0.1:8100/api/auth/login \
  -H "Content-Type: application/json" -d '{"email":"verify1@test.com","password":"secret123"}'
```
预期:`{"ok":true,"token":"...","user":{...}}`

**4. 改密 → 旧 token 失效**
```bash
# 保存第 3 步的 token 为 $OLD
curl -s -X PATCH http://127.0.0.1:8100/api/account/password \
  -H "Content-Type: application/json" -H "Authorization: Bearer $OLD" \
  -d '{"current_password":"secret123","new_password":"newpass456"}'
# 预期:返回新 token(av=2)

curl -s http://127.0.0.1:8100/api/auth/me -H "Authorization: Bearer $OLD"
# 预期:{"detail":"登录已失效，请重新登录"} HTTP 401
```

## M2 — Onboarding 后端

### 自动化测试(约 40 秒)
```bash
cd /Users/mr.zhou/Desktop/Projects/kevin/Eureka-Assistant/theme_v2_service
DATABASE_URL="mysql://theme_v2:theme_v2@127.0.0.1:13307/eureka_theme_v2_test" \
/tmp/eureka-venv/bin/python -m pytest tests/contract/test_onboarding_api.py -q
```
预期:`12 passed`

### 手动 curl 验证(用上面注册的 token)

**5. 分类目录(无需登录)**
```bash
curl -s http://127.0.0.1:8100/api/onboarding/catalog
```
预期:`categories` 含 running / drinking_water / baby_feeding / dancing,各 3 字段

**6. 创建 Skill(跑步)**
```bash
curl -s -X POST http://127.0.0.1:8100/api/onboarding/skills \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"category":"running","fields":[{"key":"distance_km","label":"距离(公里)","type":"number"},{"key":"duration_min","label":"时长(分钟)","type":"duration"}]}'
```
预期:`{"skill":{"id":"...","schema":{...}},"created":true}`(重复提交 created=false)

**7. 提取预览**
```bash
curl -s -X POST http://127.0.0.1:8100/api/onboarding/preview \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"user_skill_id":"<skill_id>","source_text":"我跑了5公里,用了32分钟"}'
```
预期:`{"payload":{"distance_km":"5","duration_min":"32"},"field_warnings":[...]}`
无数字输入时预期:`{"payload":null,"manual_fields":[...]}`(降级手填)

**8. 确认创建 Asset(幂等)**
```bash
curl -s -X POST http://127.0.0.1:8100/api/onboarding/confirm \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"skill_id":"<skill_id>","payload":{"distance_km":5,"duration_min":32},"idempotency_key":"verify-conf-1"}'
# 重复同 key:{"ok":true,"asset_id":"<同id>","created":false}
```

**9. Skip**
```bash
curl -s -X POST http://127.0.0.1:8100/api/onboarding/skip \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"idempotency_key":"verify-skip-1"}'
```
预期:`{"ok":true,"onboarding_status":"skipped"}`

---

## 验证通过标准
- [ ] M1 自动化 35 passed
- [ ] M1 手动:注册 → 登录 → 改密 → 旧 token 401
- [ ] M2 自动化 12 passed
- [ ] M2 手动:catalog → skill(幂等)→ preview(提取+降级)→ confirm(幂等)→ skip

## 注意
- 验证码 60 秒冷却:连续测试请换不同邮箱
- 后端日志:`/tmp/eureka-api.log`(mock 验证码)
