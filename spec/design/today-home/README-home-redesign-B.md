# Handoff: 今日页 = 首页 重设计 · 方向 B「潮汐」(UReka)

## What this is
The new **home screen** redesign for UReka. Replaces the old today page's dashboard/charts/morning-brief. The bubble pool stays as a permanent background; the foreground becomes **two switchable screens**:

- **【今日安排】** — timed events / todos / habits for today.
- **【Reka Offer】** — things Reka can do for you (整理随记 / 消费总结 / 学习 quiz / 会前调研 / 习惯提醒 / 逆期).

Default entry = **今日安排 · Tinder**. The two screens switch by **full-screen left/right swipe** (top underline indicator) OR tapping the segment labels. Each screen also has a **墙(wall)** mode (▦, see-everything list) vs **Tinder** mode (⚡, one card at a time).

## Design files in this bundle
- **`今日页方向板.dc.html`** — the selected direction (B「潮汐」) as a static hi-fi board. Frames: B1 今日安排·滑动浏览 · B1.5 待办·点延后改时间 · B2 Reka Offer·右滑执行 · B3 Reka Offer·左滑跳过+重生 · B4 长按球·同类毛玻璃浮层 · 附录 (墙模式×2, 卡型 gallery, 4 空态).
- **`今日页.dc.html`** — the earlier interactive hi-fi (prior home iteration) — keep as reference for the **bubble-pool physics** (sleeping, nav-as-collider, drag/tap, drop-in) and the navy theme; its dashboard/charts are superseded by this redesign.
- **`README.md`** (the other one) — the prior page's full component + token spec; tokens, domain colors, type→glyph mapping, and physics constants there still apply.

These are **design references to recreate in the real codebase's environment** (mobile app — RN/SwiftUI/Flutter), not HTML to ship. Do not port the `.dc.html` runtime.

## Key interaction rules (locked)
- **今日安排 swipe = browse only** (‹ 上一个 / 下一个 ›) — never consumes/snoozes. Global big action icon appears mid-drag (‹ / ›). Bottom Tinder twin-buttons mirror it. Finish browsing → ↻ 回到当前.
- **Reka Offer swipe**: right = ✓ 执行 (Reka does it now, green global icon + reveal), left = ✕ 跳过 (into notification feed, 14 天不唠叨, red global icon). Finish → ↻ 重新生成. Bottom ✕/✓ twin-buttons.
- **Tinder global icon**: while dragging a card, a large centered icon + label fades in over the screen telling the user the action (Tinder-style heart/cross), color-coded (blue browse / green execute / red dismiss / amber snooze).
- **待办 延后 = on-card button, NOT a swipe.** Tap「⏰ 延后」→ quick reschedule popover (今晚 / 明天 / 周末 / 选时间…) = move the reminder into the future. Long-press = precise reschedule. Complete + 延后 are **two separate buttons** on the card.
- **事件 has no reminder button** — reminders fire automatically; show a passive「🔔 到点自动提醒」line only.
- **长按一颗球** → frosted overlay rises from the bottom listing all of that **type's** records today; same-type balls in the pool highlight, others dim. (Replaces type-filter chips.)
- **⚡闪念 entry** appears on BOTH screens (taps into Reka chat). Counts derive from records.
- **Card varies by type**: event (countdown + auto-reminder line) / todo (✓完成 + ⏰延后 buttons) / habit (streak 🔥 + 记一杯) / offer (Reka 帮你 + 一键 CTA) / overdue (gentle, 改期/完成).

## Warm top
A soft greeting strip absorbs the old morning brief: 早安 + **weather (connect a weather API, e.g. ☀️26°)** + 今日一览 chips (N 日程 / N 待办 / ⚡N 闪念). Prominent at empty/清晨, can shrink during the day.

## Empty states (4)
今日安排空 · Reka Offer 空 · 气泡池空 · 全空·清晨. See 附录 in the board.

## Colors = §8 domains only
Card body is single-color; the only color is one domain dot. 8 domains: 工作 #8ab4ff · 学习 #b89cf0 · 健康 #84c9a0 · 运动 #6fd0d8 · 社交 #f5c977 · 娱乐 #f08a8a · 生活 #9fb0c9 · 灵感 #c3bcd0. Action-icon colors: browse #6f9eff, execute #84c9a0, dismiss #f08a8a, snooze #f5c977. Theme: dark navy atmosphere (page #0b1220, panels rgba(15,23,40,.66)+blur, brand #6f9eff). Type: Manrope + JetBrains Mono.

## Next step (not yet built)
Interactive hi-fi for B: real Tinder drag (follow-finger + live global icon + rebound), right-swipe execute generation, todo snooze popover, long-press reveal, reusing the existing pool physics.
