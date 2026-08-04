# Theme V2 Calendar — Day Detail 与手动记录设计

> 日期：2026-07-29  
> 状态：已实施并完成 Light / Dark 画布验收  
> 设计源：`redesignureka.pen`

## 1. 范围

本轮只处理 Calendar：

- Schedule 全部状态中的全天日程与未排期代办头部。
- Progressive Day Summary 的 Asset 图标。
- Day Detail 的 Flash 数量入口、手动记录入口和空态。
- Flow 空日与 Day Detail 共用的手动记录 Skill 选择器。

全局 Asset Emoji 映射、Goal、设备和其他页面不在本轮范围。

## 2. Schedule 头部

所有 Schedule 状态共用同一结构和尺寸：

- `全天日程 · N`
- `未排期代办 · N`

标题本身不加图标。真实事件和待办子项目显示所属 Skill 图标。

未排期代办最多同时显示三项；超过三项时内部纵向滚动，容器高度不增长。

## 3. Progressive Day Summary

`ZfqSF` 与 `UcZjE` 中每条真实 Asset 记录显示所属 Skill 图标，与 Flow 和 Day
Detail 共用同一密集 Asset row 规则。上午、下午、晚上等时间带标题不加图标。

## 4. Flash 数量入口

Day Detail 中的 Flash 条只表达当天 Flash Session 的数量：

```text
⚡ 闪念 5
```

- 删除“今天记一笔”等 hint。
- 点击进入当天 Flash Session。
- 不创建 Flash，不打开输入，不触发“记一笔”。
- 本轮数量为零时仍显示 `⚡ 闪念 0`，点击进入空 Flash Session。

## 5. Day Detail 手动记录入口

Day Detail 头部提供两个并列操作：

- `日程`
- `＋ 手动记录`

点击“手动记录”打开 Skill Picker，并把当前 Day Detail 日期作为
`effective_date` 上下文。

所有教学性 hint 删除。可点击性由按钮、卡片和 disclosure 形态表达。

## 6. Day Detail 空态

空态只由 Asset 数量决定：

```text
asset_count = 0
→ 显示 Day Detail Asset 空态
```

即使 `flash_count > 0`，仍然是 Asset 空态，并保留 Flash 数量入口。

空态保留：

- 日期头部。
- `日程`。
- `＋ 手动记录`。
- `⚡ 闪念 N`。
- 顶部 `返回日历`；不显示 Floating Dock。

内容区只显示：

```text
今天还没有记录
[手动记录]
```

不显示操作教程、二次说明或“从闪念开始”等 hint。

## 7. Manual Record Skill Picker

使用移动端 bottom sheet，不使用居中小弹窗。

结构：

```text
手动记录                                  [关闭]
选择要记录的 Skill

[常用 Skill，两列 tiles]
[全部 Skill，两列 tiles，内部纵向滚动]
```

规则：

- 同时包含系统默认 Skill 和用户自定义 Skill。
- 每个 tile 显示 Skill 图标与 `display_name`。
- Skill 数量过多时只滚动 sheet 内容，背景不滚动。
- 点击 Skill 后关闭选择器，进入该 Skill 对应的 Asset Edit 页。
- 从 Day Detail 打开时携带当前日期。
- 从 Flow 空日打开时携带被点击的空日日期。
- 选择器不创建 Asset；只有 Asset Edit 最终保存后才创建。
- Light / Dark 共用结构，仅切换主题 token。
- 键盘不会在 Skill Picker 阶段自动打开。

## 8. Flow 空日

空日仍保留在 Flow 中。点击空日的日期或空白区域，直接显示手动记录确认入口；
点击“手动记录”后打开同一个 Skill Picker。

删除“再次点击日期”等 hint。点击已有内容日期仍直接进入 Day Detail。

## 9. 验收

- Schedule 所有状态的两类头部完全一致。
- Progressive Day Summary 的每条 Asset 均有 Skill 图标。
- Flash 条不存在“今天记一笔”且不能触发创建。
- Day Detail 有明确的手动记录入口。
- 无 Asset、有 Flash 时仍显示 Asset 空态并保留 Flash 数量。
- Flow 空日和 Day Detail 调用同一 Skill Picker。
- Picker 点击 Skill 后进入对应 Edit 页，并正确携带目标日期。
- 页面中不存在教学性 hint 文案。
