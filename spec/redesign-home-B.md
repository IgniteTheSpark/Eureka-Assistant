# 今日页 = 首页 重设计 · 方向 B「潮汐」(UReka) — 设计真值（收录）

> **来源 = 用户做的 hifi 设计 README（`Calendar page redesign (1).zip` / `README-home-redesign-B.md`），逐字收录为设计真值。**
> 逻辑/数据/决策真值 = [§4.5.0](04-frontend.md);本卡 = hifi 视觉/交互真值。给 design agent 的 brief = [handoff-today-home-design.md](handoff-today-home-design.md)。

## ⚠️ 与 spec 的对齐补丁（2026-06，读本卡先看这几条）
- **域色 = §8.3 B「潮汐」低饱和 8 色板，已锁定并解耦**（真源 = `theme/domains.dart` `domainColor()`，日历 dot + 首页共用）。本卡正文给的 hex 即终值，但**以 `domainColor()` 为准**、别硬编。
- **dismiss（左滑跳过）= 软「今天不想做」+ 压一天**：当天不再 offer、第二天条件仍在则重新 offer；进通知 feed 可翻回做。**不要「14 天不打扰」抑制**（那只挡 push peek，不挡首页 PULL）。详见 [§14.5a](14-proactive-reka.md)。
- **⚡闪念 entry = 打开「当日闪念 session」**（复用 `SessionDetailPage`），不是开 chat。
- **天气 = 和风天气 QWeather**（server-side key）+ **IP 粗定位到城市**（不弹定位权限）。
- **默认落点 = 今日安排 · Tinder；类型 chips 砍掉**（看同类走「长按球 → 同类毛玻璃浮层」）。
- offer 重新生成（↻）= 重发**用户刚跳过的**；offer 增量 = 水位线只总结新批（[§14.5a](14-proactive-reka.md) / §14.3）。

---

## What this is
The new **home screen** redesign for UReka. Replaces the old today page's dashboard/charts/morning-brief. The bubble pool stays as a permanent background; the foreground becomes **two switchable screens**:

- **【今日安排】** — timed events / todos / habits for today.
- **【Reka Offer】** — things Reka can do for you (整理随记 / 消费总结 / 学习 quiz / 会前调研 / 习惯提醒 / 逾期).

Default entry = **今日安排 · Tinder**. The two screens switch by **full-screen left/right swipe** (top underline indicator) OR tapping the segment labels. Each screen also has a **墙(wall)** mode (▦, see-everything list) vs **Tinder** mode (⚡, one card at a time).

## Key interaction rules (locked)
- **今日安排 swipe = browse only** (‹ 上一个 / 下一个 ›) — never consumes/snoozes. Global big action icon appears mid-drag (‹ / ›). Bottom Tinder twin-buttons mirror it. Finish browsing → ↻ 回到当前.
- **Reka Offer swipe**: right = ✓ 执行 (Reka does it now, green global icon + reveal), left = ✕ 跳过 (into notification feed; **软「今天不想做」+ 压一天**, 见对齐补丁/§14.5a, red global icon). Finish → ↻ 重新生成 (重发刚跳过的). Bottom ✕/✓ twin-buttons.
- **Tinder global icon**: while dragging a card, a large centered icon + label fades in over the screen telling the user the action (Tinder-style heart/cross), color-coded (blue browse / green execute / red dismiss / amber snooze).
- **待办 延后 = on-card button, NOT a swipe.** Tap「⏰ 延后」→ quick reschedule popover (**1 小时 / 明天 / 后天 / 自定义时间…**) = move the reminder into the future. Long-press = precise reschedule. Complete + 延后 are **two separate buttons** on the card. **延到哪天就去哪天**（从今天消失，出现在那天）。
- **事件 has no reminder button** — reminders fire automatically; show a passive「🔔 到点自动提醒」line only.
- **长按一颗球** → frosted overlay rises from the bottom listing all of that **type's** records today; same-type balls in the pool highlight, others dim. (Replaces type-filter chips.)
- **⚡闪念 entry** appears on BOTH screens → **opens today's flash session**. Counts derive from records.
- **Card varies by type**: event (countdown + auto-reminder line) / todo (✓完成 + ⏰延后 buttons) / habit (streak 🔥 + 记一杯) / offer (Reka 帮你 + 一键 CTA) / overdue (gentle, 改期/完成).

## Warm top
A soft greeting strip absorbs the old morning brief: 早安 + **weather (QWeather + IP-city, ☀️26°)** + 今日一览 chips (N 日程 / N 待办 / ⚡N 闪念). Prominent at empty/清晨, can shrink during the day.

## Empty states (4)
今日安排空 · Reka Offer 空 · 气泡池空 · 全空·清晨.

## Colors = §8 domains only
Card body is single-color; the only color is one domain dot. 8 domains（终值见 §8.3 / `domainColor()`）: 工作 #8AB4FF · 学习 #B89CF0 · 健康 #84C9A0 · 运动 #6FD0D8 · 社交 #F5C977 · 娱乐 #F08A8A · 生活 #9FB0C9 · 灵感 #C3BCD0. Action-icon colors: browse #6F9EFF, execute #84C9A0, dismiss #F08A8A, snooze #F5C977. Theme: dark navy atmosphere (page #0B1220, panels rgba(15,23,40,.66)+blur, brand #6F9EFF). Type: Manrope + JetBrains Mono.

## Next step (not yet built)
Interactive hi-fi for B: real Tinder drag (follow-finger + live global icon + rebound), right-swipe execute generation, todo snooze popover, long-press reveal, reusing the existing pool physics.
