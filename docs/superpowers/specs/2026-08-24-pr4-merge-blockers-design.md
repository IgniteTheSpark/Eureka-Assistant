# PR #4 Merge Blockers 修复设计

日期：2026-08-24  
目标分支：`codex/pr4-merge-blockers`  
基线：PR #4 head `589ae76334f59fdbca3fe4e40c038b6602776afe`

## 1. 目标

以 PR #4 的完整代码为基线，修复阻止用户注册、登录、首次 onboarding 和账户安全流程可靠上线的问题。修复完成后，本分支可以替代原 PR 直接合入 `main`，不依赖原 PR 作者 cherry-pick。

本轮只处理合并阻断项：

- 验证码新旧状态、消费事务与失败计数；
- 并发改密和 `auth_version` 会话撤销；
- 登录限流、未知账户时序保护和异步服务可用性；
- 预制 onboarding 记录类型、字段选择、手动录入类型与幂等确认；
- onboarding 的 busy、错误反馈、返回和跳过；
- 生产 JWT 密钥强度；
- Flutter `pubspec.lock` 可复现性。

## 2. 非目标

- 不在 onboarding 中创建完全自定义的记录类型；
- 不在 onboarding 中添加自定义字段；
- 不实现个人中心的记录类型管理入口；
- 不重写导出为流式协议；
- 不整理已经存在的 `0028/0030` 迁移历史；
- 不处理本轮审查中的纯视觉、无障碍和非阻断性能建议。

## 3. 分支和交付方式

所有工作在隔离 worktree 的 `codex/pr4-merge-blockers` 分支完成，避免改动当前 `main` 工作区中的未提交设计文件。

提交按以下边界拆分：

1. 认证验证码与登录安全；
2. onboarding 预制类型和确认契约；
3. Flutter onboarding 状态反馈；
4. 生产配置与 `pubspec.lock`。

最终推送到 `origin/codex/pr4-merge-blockers`，作为包含 PR #4 全部内容的替代合并分支。

## 4. 认证设计

### 4.1 验证码生命周期

签发新验证码时，在同一事务内失效同邮箱、同用途的所有旧未消费验证码，再插入新验证码。验证时只接受最新记录，旧验证码不能在新验证码被消费后重新变为有效。

错误验证码的失败次数和锁定时间必须独立持久化，不能因为 API 返回 400 而回滚。成功消费不能提前提交；它必须与注册账号、初始化基础 Skills 或修改密码处于同一事务。

结果语义：

- 错误码：独立提交失败计数，API 返回 400/429；
- 正确码且业务写入成功：验证码消费和业务写入一起提交；
- 正确码但业务写入失败：全部回滚，原验证码仍可重试。

### 4.2 密码与会话撤销

修改密码、重置密码和停用账户读取 `UserAccount` 时使用行锁，所有密码校验、密码写入和 `auth_version` 增量均在锁内完成。返回 token 必须使用数据库事务中的最终版本，避免两个并发请求签发相同版本的有效 token。

### 4.3 登录保护

登录在执行 PBKDF2 前使用数据库原子限流桶预留尝试次数。固定 15 分钟窗口内，每个邮箱最多 10 次、每个 IP 最多 50 次；达到上限时返回 429 和 `Retry-After`。该限额统计所有尝试，从而在密码哈希前阻断 CPU 放大。未知邮箱、已停用账户和无密码账户使用固定 dummy hash，使失败路径与真实账户接近。PBKDF2 hash/verify 通过每进程并发上限为 8 的受限线程执行，避免阻塞 FastAPI 事件循环。

所有认证请求增加明确输入边界：邮箱最大 320 字符、验证码为 6 位数字、密码最大 128 字符。错误响应不泄露邮箱是否存在。

## 5. Onboarding 设计

### 5.1 仅允许预制记录类型

Onboarding 只展示服务端 catalog 中的四个预制记录类型：

- 跑步；
- 喝水；
- 宝宝喂养；
- 跳舞。

用户选择一个记录类型后，从该类型的预制字段中多选，至少选择一个。不展示“自定义记录”，不允许输入自定义记录名称，也不允许添加自定义字段。

移动端本地 fallback 必须包含相同的四个记录类型、字段和提示语。

### 5.2 创建契约

创建接口接收 `category` 和 `field_keys`，不再信任客户端提交 label、type 或 schema。服务端必须验证：

- `category` 存在于 catalog；
- `field_keys` 非空且不重复；
- 每个 key 均属于该 category。

服务端从 catalog 构造 UserSkill schema。UserSkill 是内部实现，用户界面统一使用“记录类型”。

### 5.3 Preview 与手动确认

Preview 返回字段时始终保留 Skill schema 的原始 `number`、`duration`、`time` 或 `text` 类型。无法自动提取只改变 `extracted` 状态，不改变字段类型。

Flutter 根据原始类型转换用户编辑值：`number` 和 `duration` 发送 JSON 数值，其余类型发送字符串。全手动输入距离或时长必须能够成功确认。

### 5.4 幂等确认

新增前向迁移，为 `onboarding_asset_results` 增加可空的 `request_fingerprint`。确认请求的规范身份由 `skill_id` 与 canonical JSON payload 共同决定，并计算 SHA-256 指纹。幂等结果记录保存请求指纹：

- 同一用户、同 key、同指纹：返回已创建 Asset；
- 同一用户、同 key、不同指纹：返回 409；
- 新 key：创建 Asset、幂等记录并将 onboarding 标记为 completed，三者同事务提交。

历史幂等记录的指纹为空时，服务端读取其 Asset 的 `user_skill_id` 和 payload 派生指纹：匹配则回填并 replay，不匹配则返回 409。

Flutter 在内存中保存最后一次 canonical payload 与 UUID v4 操作 key：内容相同的网络重试复用 key，内容变化则生成新 key。页面销毁后不单独持久化一个脱离 payload 的 key。

### 5.5 页面状态

创建记录类型、preview、confirm 和 skip 共享明确的 operation/busy 状态。请求期间禁用对应按钮，避免重复提交。所有失败路径必须：

- 清除 busy；
- 保留类别、字段和文本输入；
- 调用 `notifyListeners()`；
- 展示可重试错误。

分类页提供返回价值首屏和跳过 onboarding 的入口。任意步骤跳过均调用同一幂等 skip 命令。

## 6. 生产配置

生产环境的 `JWT_SECRET` 至少包含 32 个随机字节，并拒绝 `test`、`example`、`replace-with`、`change-me` 等占位标记。DirectMail AccessKey/Secret 继续只通过部署环境注入，不进入 Git。

Terms/Privacy 占位 URL 可以保留在示例配置用于合并，但部署脚本继续拒绝示例值，公开注册前必须替换为正式 HTTPS 地址和版本。

## 7. `pubspec.lock`

在能够访问 `git.100credit.cn` 的当前开发环境执行 `flutter pub get`，只提交 `mobile/pubspec.lock`：

- 移除百智 OAuth 相关依赖；
- 写入 `integration_test` 依赖链；
- 不提交 `.dart_tool`、`.flutter-plugins-dependencies` 或 `pubspec_overrides.yaml`。

## 8. 测试策略

严格执行 RED → GREEN → REFACTOR。

后端回归测试覆盖：

- 签发 A、签发 B、消费 B 后 A 仍失败；
- 注册/重置业务写入失败后验证码未消费；
- 并发改密只保留最终有效会话版本；
- 登录 IP/邮箱限流、dummy hash 和输入上限；
- onboarding 拒绝未知 category、空字段、重复字段、跨 category 字段；
- 全手动 number/duration preview 到 confirm 成功；
- 同 key 同 payload replay、同 key 不同 payload 返回 409。

Flutter 回归测试覆盖：

- 只展示四个预制记录类型；
- 不出现自定义记录和添加字段入口；
- 字段多选、返回和跳过；
- busy 防重复提交；
- create/preview/confirm/skip 失败后显示错误并保留输入；
- 手动数字字段发送 JSON 数值。

合并前定向验证包括认证、账户、onboarding、迁移相邻测试、Flutter 受影响测试、定向 analyze、`flutter pub get` lockfile diff 检查和 debug APK 构建。若需要运行全仓后端和 Flutter 套件，将在执行前单独说明时间成本并取得确认。

## 9. 验收标准

- 用户可以用最新验证码完成注册和找回密码，旧验证码不能恢复有效；
- 数据库失败不会消耗一次成功验证码；
- 并发改密不能留下两个有效 replacement token；
- 登录存在可验证的限流和时序保护；
- onboarding 只能选择预制记录类型和预制字段；
- 全手动数字/时长记录可以保存；
- 请求失败有可见反馈且不会重复提交；
- 幂等重试不会静默保存旧内容；
- 生产弱 JWT 密钥无法启动；
- `flutter pub get` 后受版本控制的 lockfile 无变化；
- 所有定向测试和 debug APK 构建通过。
