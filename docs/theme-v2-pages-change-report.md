# Theme V2 新增页面修改报告

**日期**:2026-08-13
**分支**:`codex/theme-v2-account-onboarding-settings`
**依据规范**:`spec/design/design-system-revamp.md`(Design System Revamp Brief · Quiet Warm Minimalism,最新权威设计规范)

---

## 一、新增页面清单(本次交付)

| 页面 | 文件 | 里程碑 | 主题来源 |
|---|---|---|---|
| 登录页(三模式) | `mobile/lib/pages/login_page.dart` | M4 | EurekaColors |
| Onboarding 5 步 | `mobile/lib/theme_v2/onboarding/`(page/controller/repository) | M5 | ThemeV2Tokens |
| 账户页 | `mobile/lib/theme_v2/account/`(page/repository) | M6 | ThemeV2Tokens |

---

## 二、设计规范对齐修改

### 2.1 登录页(login_page.dart)—— 本次实际修改

**背景**:登录页仍使用旧 `EurekaColors` 主题,且主按钮为"品牌渐变 + 重阴影",与最新规范"Quiet Warm Minimalism(克制、可信、避免营销感)"不符。

| 项 | 修改前 | 修改后 | 规范依据 |
|---|---|---|---|
| 主按钮背景 | 蓝→紫 `LinearGradient` | 单色 `eu.brand` | §16.1 避免大饱和渐变/多色堆叠 |
| 按钮阴影 | `blur16 / offset(0,6) / alpha0.4` | `blur10 / offset(0,2) / alpha0.16` | §16.3 超低阴影 |
| 按钮字重 | w700 | w600 | 克制、不抢眼 |

**三模式功能**(M4 已实现,本次未改):登录 / 注册(邮箱+验证码+确认密码)/ 忘记密码。

### 2.2 Onboarding 页(onboarding_page.dart)—— 核对通过,无需改

| 规范点 | 现状 | 结论 |
|---|---|---|
| quiet paper tile 卡片 | 中性 surface + 细边框 + 无阴影 | ✅ 符合 |
| 颜色稀缺(选中态) | accent 15% 轻背景,不做大片底色 | ✅ 符合 |
| 卡片不嵌套 | 分类卡用 Container 非 Card | ✅ 符合 |
| mono 字体仅限时间戳 | 未滥用 | ✅ 符合 |

### 2.3 账户页(account_page.dart)—— 核对通过,无需改

| 规范点 | 现状 | 结论 |
|---|---|---|
| 语义色 | 删除用 `tokens.critical` | ✅ 符合 |
| 克制视觉 | 无渐变/重阴影 | ✅ 符合 |
| 与 shell 一致 | AppBar + ListView,符合 Header 规范 | ✅ 符合 |

---

## 三、设计系统核对发现(未修改,记录待办)

依据 `design-system-revamp.md` §18.2 核对 `theme_v2/foundation/theme_v2_tokens.dart`:

| 规范要求 | 现状 | 差距 |
|---|---|---|
| ink 文字色 5 级(0.95/0.82/0.66/0.48/0.34) | 仅 foreground/muted 2 级 | ❌ 缺 3 级 |
| 语义状态色 success/warning/info | 仅 critical | ❌ 缺 3 槽 |
| shadow/elevation token | 无 | ❌ 缺失 |
| blur/glass token | 无 | ❌ 缺失 |
| icon/emoji sizing token | 仅 iconSize=20 | ⚠️ 缺 token 化 |
| Radius 5 级 | sm/md/lg/pill(缺 xl) | ⚠️ 缺 xl |
| 风格基线色温 | light `F7F9FC` 偏冷蓝灰 | ⚠️ 待核对"暖纸"基线 |

> 以上差距**未修改**(用户指示"先不做,先依标准改新增页面"),留待后续 token 补齐。

---

## 四、验证结果

| 平台 | 验证 | 结果 |
|---|---|---|
| Web | `flutter analyze` 全绿 + Web 构建 | ✅ |
| Android | `flutter analyze` + APK 构建 + 安装 + 启动 | ✅ |
| Android UI | 图像识别:登录按钮"蓝色纯色、无渐变" | ✅ 新样式生效 |
| Android 流程 | 登录→onboarding→跳过→主界面→账户页→退出登录 | ✅ adb 自动化通过 |

---

## 五、相关文档

- 设计规范:`spec/design/design-system-revamp.md`(权威,1399 行)
- 基准规范:`spec/05-design-system.md`(早期版)
- 功能规格:`docs/superpowers/specs/2026-08-13-theme-v2-account-onboarding-settings-design.md`
- 实施计划:`.omo/plans/theme-v2-account-onboarding-settings.md`
