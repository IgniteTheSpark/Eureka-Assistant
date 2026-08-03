# Theme V2 API 对接审计（2026-08-03）

分支：`codex/theme-v2-ui-refactor`

范围：只审计 Theme V2 生产 Shell 可到达的页面、通知跳转、硬件闪念链路和当前四份 Theme V2 Spec。旧版页面仍可保留旧 API，但不得从 Theme V2 入口误触发。

## 结论

Theme V2 的生产入口现已收敛到独立 Service 的 Core Record API。审计中确认并修复了以下断链：

- 戒指 8 kHz PCM 直接送 ASR 导致业务失败且错误被吞；改为客户端转 16 kHz，并显示失败状态。
- 每条录音被当成独立 Session；改为按 `Asia/Shanghai` 自然日聚合为 `8月2日 闪念`、`8月3日 闪念`。
- 首页闪念数固定为 0、日历流未读取录音；改接每日 Session 和录音归档 API。
- 创建 / 配置 Skill 仍调用旧 `/api/skills`；改接 `/api/user-skills`，补齐 Draft、Create、Read、Patch 和展示元数据持久化。
- Theme V2 手动创建联系人仍调用 `/api/contacts`；改为 `contact` Skill 的 Asset。
- Theme V2 手动事件的参会人仍调用 `/events/{id}/attendees` 子资源；改为 Event Create / Patch 原子保存 `attendees`。
- Theme V2 事件详情的编辑与联系人关联仍可能落入旧 attendee 子资源；改为 Core Event Patch，并复用 contact Skill Asset 选择器。
- 生产 Shell 已使用 `/api/notifications`，但休眠的 Reka Inbox fallback 仍默认读取旧 `/api/nudges*`；本次也将 fallback 改为通知适配，避免未来开启时重新引入 404。
- `report_available`、`report_plan_ready` 通知没有完整跳转；改为创建或恢复 Report Run。
- Planner 返回 Clarification 时 App 无回答入口；补齐回答和 `POST /decision`。
- Theme V2 报告 Viewer 误探测旧 `/actions`、`/rerender`；Theme V2 下已禁用旧增强接口。

## Theme V2 生产 API 地图

| 能力 | App 使用的 API | Service 状态 |
|---|---|---|
| 登录 | `/api/auth/register`、`/login`、`/me` | 已实现 |
| 戒指绑定 | `/api/cards/binding-info`、`/bindings`、`/unbind` | 已实现 |
| 硬件闪念 | `/api/flash/tencent-asr-sync-results`、`/tencent-asr-s3-uploads` | 已实现 |
| 文字闪念 | `POST /api/flash` | 已实现 |
| 闪念详情 / 重试 | `/api/flash/recordings/{id}`、`/{id}/retry` | 已实现 |
| 每日闪念 | `/api/flash/sessions`、`/{YYYY-MM-DD}` | 本次补齐 |
| 首页 / 日历闪念流 | `/api/flash/recordings` | 本次补齐日期和捕捉时间字段 |
| Skill | `/api/user-skills`、`/draft`、`/{id}`、`/recent-manual` | 本次补齐 |
| Asset | `/api/assets`、`/{id}` | 已实现并对齐 Create / Patch / Delete |
| Event / 参会人 | `/api/events`、`/{id}` | 本次补齐 Event Patch 的 `attendees` |
| 通知 | `/api/notifications`、`/stream`、`/read-all`、`/{id}/read`、`DELETE /{id}` | 已实现 |
| 通知面板 / Reka Inbox fallback | 读取并适配 `/api/notifications`；动作复用统一通知 Target | 生产路径已对齐，本次加固 fallback |
| Trigger Dismiss | `/api/trigger-executions/{id}/dismiss` | 已实现并接入通知左滑 |
| Report Run | `/api/report-generation-runs`、`/{id}`、`/decision`、`/generate`、`/retry` | 后端已实现；App 本次完整接入 |
| Report | `/api/reports`、`/{id}` | 已实现并接入 Theme V2 Viewer |

## 旧 API 隔离结果

以下调用仍存在于兼容旧版的代码中，但 Theme V2 生产入口不再调用：

- `/api/timeline`
- `/api/skills`
- `/api/contacts`
- `/api/sessions`
- `/api/asset-details/*`
- `/api/events/{id}/attendees/*`
- `/api/nudges*`
- `/api/offers/today`
- `/api/reports/{id}/actions`
- `/api/reports/{id}/rerender`

Theme V2 使用显式 `coreRecordsOnly`、独立 Repository 和独立通知 Target，不依赖“先请求旧 API、收到 404 再回退”的生产路径。

## 会前调研配置确认

独立 Docker Compose 已让以下 Report 配置默认复用现有 Capture Agent 配置：

- `REPORT_PLANNER_ENABLED`
- `REPORT_PIPELINE_ENABLED`
- `REPORT_PLANNER_MODEL`
- `REPORT_GENERATOR_MODEL`
- `REPORT_PROVIDER_API_KEY`

当前解析后的 Compose 配置中 Planner、Pipeline、模型和 Provider Key 均可用。

尚未配置：

- `BOCHA_API_KEY`
- `TAVILY_API_KEY`

`pre_event_briefing` 的 Web Search Policy 是 `optional`，所以没有搜索 Key 时报告仍可生成，但只能使用日程和已有 Asset，上网查公司 / 人物公开资料会降级为空。若要验收“完整会前调研”，需要在两者中选择并配置一个；Service 优先使用 Bocha，其次 Tavily。

现有 8 月 3 日那条 `report_available` 对应的 Event 已开始，Trigger Execution 按 Spec 已过期，不能用它重做端到端验收。需要创建一个未来 30–60 分钟开始、标题或参会人信息足够的 Event，等待新通知后验证点击、方案、澄清、生成和报告打开。

## 基础设施边界

Phase 1 只使用独立 MySQL、API、Worker 和数据库 Job / Outbox；不要求 Redis、Kafka 或外部消息队列。这与 Trigger Spec 和 Report Generation Spec 一致，因此本次没有引入架构级改造。

## 验收门槛

- [x] 后端完整测试通过；容器测试进程退出码为 0。
- [x] Flutter 完整测试通过（540 tests）；本次变更范围静态分析为 0 issue。
- [x] 独立 Compose 重建、迁移到 `0009_user_skill_presentation (head)`，`/health` 与 `/ready` 通过。
- [x] OpenAPI 中存在审计要求的全部 Theme V2 路由，无缺失项。
- [x] 真机安装强制开启 Theme V2 的 APK；首页、资产库、Skill Builder 启动正常，应用错误日志为空。
- [ ] 在真机完成一次新的戒指录音，确认通知、每日 Session、Asset 和日历闪念同时出现。
- [ ] 创建未来 Event，完成一次 `report_available` 到 Report Viewer 的流程；外部公开资料搜索需先配置 Bocha 或 Tavily。

最后两项会产生真实业务数据，并调用当前配置的外部模型，需要在明确授权测试数据发送后执行。现有过期的会前调研通知只用于确认通知类型与入口，不作为新流程验收样本。
