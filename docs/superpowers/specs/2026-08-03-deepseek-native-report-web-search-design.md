# DeepSeek 原生 Report Web Search 设计

> 日期：2026-08-03  
> 状态：已确认设计，待实施  
> 范围：Theme V2 Report Pipeline 的外部联网检索阶段

## 目标

使用现有 DeepSeek API Key 和 DeepSeek V4 Flash 的 Responses API 原生
`web_search` 工具，为 Theme V2 Report Pipeline 提供带来源的外部资料。

本次不改变 Report Planner、Report Generator、Pipeline 阶段顺序、Report 数据
模型或移动端契约。联网检索仍是独立阶段，Report Generator 只消费归一化后的
`external_sources`。

## 方案选择

考虑过三种方案：

1. **独立 DeepSeek Responses Web Search Provider（采用）**：使用同一个
   DeepSeek Key，但把检索和报告生成保持为两个受控阶段。保留现有策略、重试、
   Checkpoint、来源存证和隐私边界。
2. **允许 Report Generator 自行联网（不采用）**：调用更少，但搜索过程无法作为
   独立阶段审计和重试，也会绕过 `optional / required /
   authoritative_only` 策略。
3. **继续仅使用 Bocha/Tavily（保留为后备）**：现有实现不删除，但不作为本地
   Theme V2 环境的首选配置。

## 架构

新增 `DeepSeekResponsesWebSearchProvider`，实现现有 `WebSearchProvider`
协议：

```text
sanitized report queries
  → DeepSeek Responses API
  → server-side web_search
  → URL citations / source metadata
  → WebSource[]
  → existing report content generation
```

Provider 直接使用 `httpx.AsyncClient` 调用 DeepSeek Responses API，不通过
当前的 `litellm.acompletion`。原因是当前 LiteLLM 路径使用 Chat Completions
和严格 JSON 输出，并未暴露 DeepSeek Responses 的服务端 `web_search` 工具及
引用结构。

现有 `ConfiguredWebSearchProvider` 继续负责 Bocha/Tavily。Worker Registry
通过一个小型 Provider Factory 根据配置选择实现，Pipeline 不感知具体厂商。

## 配置

增加以下环境变量：

```text
REPORT_WEB_PROVIDER=deepseek | bocha | tavily | none
REPORT_WEB_MODEL=deepseek-v4-flash
REPORT_WEB_API_URL=https://api.deepseek.com
REPORT_WEB_API_KEY=<optional>
```

规则：

- 默认 `REPORT_WEB_PROVIDER=none`，避免升级后意外产生联网调用和费用。
- Theme V2 Docker 本地验收环境显式设置 `REPORT_WEB_PROVIDER=deepseek`。
- `REPORT_WEB_API_KEY` 未设置时可回退到 `REPORT_PROVIDER_API_KEY`，允许同一个
  DeepSeek Key 同时服务 Report Planner、Generator 和 Search。
- `REPORT_WEB_MODEL` 的默认值固定为 `deepseek-v4-flash`。不把
  `deepseek-chat` 或 V4 Pro 当作支持原生搜索的隐式别名。
- Bocha/Tavily 的既有 Key 和 URL 配置保持兼容。

Settings 提供 `report_web_available()` 和配置错误检查。`provider=deepseek`
但缺少 Key、Model 或合法 URL 时，服务 Ready 检查明确报告配置错误；不会静默
回退到另一个供应商。

## 请求与来源归一化

当前 `build_web_queries` 已负责移除姓名、地址和原始记录全文。新 Provider 只接收
这些脱敏 Query，不接收 Asset、Event、联系人或完整 Report Evidence。

每条 Query 最多触发一次 Responses 请求，最多处理现有上限的三条 Query。请求：

- `model = deepseek-v4-flash`
- `tools = [{"type": "web_search"}]`
- `tool_choice` 强制选择 `web_search`
- 输入只包含脱敏 Query 和“返回带引用的简明公开资料”约束

Provider 从 Responses 输出中按以下优先级收集来源：

1. `web_search_call` 中可用的 source metadata。
2. 输出文本的 URL citation annotations。

每个来源归一化为：

```text
title
url
snippet
accessed_at
authoritative=false
```

同一 URL 去重，保留信息更完整的条目。`snippet` 优先使用来源摘要或 cited text；
若只有文本区间则从已返回的输出文本安全截取。Provider 不根据模型正文猜测或伪造
URL。

Responses 成功但没有任何可验证 URL 时视为 Provider 错误：`optional` 策略按
现有逻辑降级，`required` 和 `authoritative_only` 进入可重试失败。

## 错误处理

- 超时、连接失败、HTTP `408 / 409 / 429 / 5xx`：
  `RetryableProviderError`。
- 鉴权失败、模型不支持工具、非法请求及其他确定性 `4xx`：
  `PermanentProviderError`。
- `2xx` 但响应不是合法 JSON、没有可识别输出或没有可验证引用：
  `PermanentProviderError`。
- 单条 Query 失败即结束本次 Search Stage，不返回不完整的“成功”结果。
- Pipeline 继续沿用现有 `optional / required / authoritative_only` 语义。

不会把 API Key、请求头、完整响应正文或用户原始 Evidence 写入日志。

## 测试

采用 TDD，先增加失败测试，再实现：

1. Provider 发出正确的 `/responses` 请求、模型、工具和强制 Tool Choice。
2. 解析 source metadata、URL citations、文本区间和重复 URL。
3. 多 Query 调用和稳定去重顺序。
4. 超时、连接错误、可重试状态码、确定性 `4xx` 和畸形响应分类。
5. 没有可验证 URL 时不得返回成功。
6. Settings 默认关闭、Key 回退、非法配置与 Ready 检查。
7. Worker Provider Factory 对 `deepseek / bocha / tavily / none` 的选择。
8. 现有 Report Web Policy、Checkpoint、Pipeline 和 E2E 测试继续通过。

实现完成后用当前 DeepSeek Key 做一次最小真实 Contract Smoke Test，只记录状态、
来源数量和 URL 域名，不输出 Key 或完整生成内容。随后在独立 Theme V2 Docker 中
验证一次 `optional` Web Report 流程。

## 部署与回滚

本地 Theme V2 Compose 显式启用：

```text
REPORT_WEB_PROVIDER=deepseek
REPORT_WEB_MODEL=deepseek-v4-flash
```

Key 复用现有 `REPORT_PROVIDER_API_KEY`。如果 DeepSeek Search 不可用，将
`REPORT_WEB_PROVIDER` 改为 `none` 可立即回到当前无联网的降级行为；也可改为
`bocha` 或 `tavily` 使用现有 Provider。无需数据库迁移，也不影响已生成 Report。

## 完成标准

- 当前 Theme V2 容器能识别 DeepSeek Web Search 配置并保持 Ready。
- Report Pipeline 的 Web Search Stage 能从 DeepSeek 返回至少一个可验证 URL。
- Report 的 `spec_json` / generation context 继续保存来源和执行状态。
- `optional` 搜索失败时报告仍完成；`required` 搜索失败时可重试。
- Planner、Generator 仍不能自行调用 Web Search。
- 全量 Theme V2 Service 测试通过，现有移动端接口不变。
