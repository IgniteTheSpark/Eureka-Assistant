# Handoff · Event 参会人选择与安全绑定

> 给 coding agent。目标：event 支持参会人，手动从名片库选择 / 新增联系人；Flash 创建 event 时如果提到人名，安全绑定已有唯一联系人，重名不乱绑。

## 1. 真值来源

- 数据模型：[../02-data-model.md](../02-data-model.md) §3.10 `event_attendees`
- API：[../03-api-reference.md](../03-api-reference.md) §3.6 `/api/events` + §3.7 `/api/contacts`
- Agent：[../01-agent-architecture.md](../01-agent-architecture.md) 工具表 + event sub-skill 行
- 前端：[../04-frontend.md](../04-frontend.md) §4.4.3b / §4.7.4
- Prompt：[../99-prompts-appendix.md](../99-prompts-appendix.md) A.2.2 `flash-event-skill`

## 2. Backend

### 2.1 Event attendees API

保留已有：

```text
POST /api/events/{id}/attendees
```

新增：

```text
PATCH  /api/events/{id}/attendees/{attendee_id}
DELETE /api/events/{id}/attendees/{attendee_id}
```

`PATCH` 用于把裸名 attendee 绑定到 contact：

```json
{
  "contact_id": "contact_uuid",
  "name": "Alex",
  "role": "attendee"
}
```

`DELETE` 只删 `event_attendees` 行，不删除 `contacts`。

### 2.2 Event GET serialization

`GET /api/events/{id}` 的 `attendees[]` 返回：

```json
{
  "id": "attendee_uuid",
  "contact_id": "contact_uuid_or_null",
  "name_raw": "Alex",
  "display_name": "Alex",
  "role": "attendee",
  "is_resolved": true,
  "contact_summary": "Acme · Product Manager"
}
```

`display_name = contact.name ?? name_raw`。

### 2.3 Contact search

`GET /api/contacts?q=&limit=20` 至少按 `name/company/title/phone/email` 做 contains 模糊匹配。中文直接 contains；英文大小写不敏感。

## 3. Frontend

### 3.1 EventForm

`EventForm` 增加「参会人」区：

- 已选 attendee 用 chip/list 展示。
- `contact_id != null` 显 `display_name` + `contact_summary`。
- `contact_id == null` 显 `name_raw`，可标轻提示「未绑定名片」。
- 支持移除 attendee。

### 3.2 Select contacts sheet

点「添加参会人」打开底部 sheet：

- 标题：`选择参会人`
- 搜索框：输入名字或关键字
- 列表：最近联系人 + 搜索结果
- 多选
- 底部固定栏：`已选` + 已选名字/圆点 + `保存(N)`
- 无结果时显示「新增联系人」

新增联系人复用 `ContactForm`；创建成功后自动选中并添加到当前 event。

### 3.3 EventCard meta

完整/通用 EventCard（资产库、对话内卡片、详情/编辑预览）第二行 meta：

```text
14:00–15:00 · 会议室 · Alex +3
```

拼接顺序：

1. 时间范围
2. location（有则显示）
3. attendees 摘要（有则显示）

attendees 摘要：第一位 `display_name/name_raw` + `+N`，`N = total - 1`。

不做头像，不做 avatar stack。

日历流/月中的紧凑 event item 保持单行 `[时间] [类型 emoji] 标题`，不展示第二行 meta；点开详情后再展示上述完整摘要和参会人。

## 4. Agent / Flash

Flash event skill 创建 event 后抽参会人：

- 0 个 contact 命中：写 `name_raw` attendee，不创建 contact。
- 1 个 contact 命中：写 `contact_id` attendee。
- 2+ 命中 / 重名：写 `name_raw` attendee，不猜第一条。
- 永不因为 event attendee 自动创建联系人。

用户明确说「保存联系人 Alex」时仍走 contact skill。

## 5. 验收

- 手动编辑 event 可以添加 / 删除多个参会人。
- 搜索联系人支持名字和公司/职位/电话关键字。
- 搜不到时能新建联系人，并自动加入当前 event。
- 两个同名联系人时，sheet 显示两条带副信息的候选；用户选择后绑定正确 `contact_id`。
- Flash 输入「明天下午2-3点和 Alex 开会」：
  - 若 Alex 唯一存在，event attendee 绑定 Alex 的 `contact_id`。
  - 若 Alex 不存在，event attendee 为裸名 `name_raw=Alex`。
  - 若 Alex 有多个，event attendee 为裸名，不自动绑定。
- 完整/通用 EventCard 显示类似 `14:00–15:00 · 会议室 · Alex +3`；日历流/月中的紧凑 event item 保持单行标题。
