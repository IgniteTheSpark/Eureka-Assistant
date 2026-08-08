# Theme V2 Todo Deadline、Thinking Orbs 与 Session 卡片协议设计

日期：2026-08-08
状态：待用户审阅
分支：`codex/theme-v2-ui-refactor`

## 1. 背景

Theme V2 当前有三类相互关联的问题：

1. Todo 可以缺少具体 deadline，导致首页 Next、Calendar 时间轴、Session
   卡片和逾期判断不能共享同一个时间落点。
2. Thinking Orbs 的状态主要通过速度与疏密区分，所有状态共用单一主题色；
   Session 还把四个 Agent 工作态压缩成两种 Orb 形态。
3. Session 卡片存在多套结构。服务端有时持久化格式化展示文本，有时只持久化
   ID 引用，普通 Chat 与闪念 Session 又分别恢复卡片，造成时间过度详细、类型
   判断错误和详情路由失败。

产品尚未上线，现有内容均为测试数据。本设计只定义最新协议，不迁移、不兼容
旧 Session 卡片或旧测试快照。

## 2. 目标

- 每个新建 Todo 最终都有带时区的具体 `due_date`。
- 硬件闪念、Session 对话和手动创建共享同一个 deadline 规则。
- Todo 的初始完成状态只由创建时的 deadline 与当前时间决定。
- 所有页面使用同一时间展示规则，卡片不再展示原始 ISO 字符串。
- Thinking Orbs 使用选定的 A「有机编舞」方向，每个状态都有独立形态。
- Light 与 Dark 顶栏接管态都有清晰的反差光带。
- 普通 Chat 与闪念 Session 只消费一种最新卡片协议。

## 3. 非目标

- 不兼容或迁移旧 Session 卡片。
- 不为旧字段增加 fallback、推断或多版本 hydrator。
- 不调整 Agent、Capture、Session 的总体架构或后端状态机。
- 不在本阶段实现 reduced motion 或额外无障碍动效策略。
- 不为每个 Orb 状态建立完全独立的颜色体系；形态是主要状态信号。

## 4. Todo Deadline 设计

### 4.1 单一归一入口

新增纯业务组件 `TodoDeadlineNormalizer`。所有 Todo 创建入口必须在写入资产前
调用它：

- 硬件录音和音频上传；
- Session Chat 工具创建；
- 手动创建页；
- Report 或其他 Agent 产生的 Todo。

模型只抽取用户明确表达的事实：日期、时段、具体钟点。模型不选择默认时间。
默认值由 normalizer 以用户时区和捕捉发生时间为基准确定。

### 4.2 时间优先级

归一顺序从高到低为：

1. **明确日期与钟点**：直接使用用户说出的具体时间。
2. **明确日期与时段**：使用该日期的时段末端。
3. **只有明确日期**：使用该日期 18:00。
4. **只有时段、没有日期**：该时段末端尚未经过时使用今天；已经经过时使用
   明天。
5. **日期、时段和钟点均未表达**：当前时间不晚于 18:00 时使用今天 18:00；
   超过 18:00 时使用明天 18:00。

“超过 18:00”使用严格大于判断。18:00 整创建且没有时间信息的 Todo 仍落在
今天 18:00。

### 4.3 时段末端

| 时段 | 默认 deadline |
|---|---:|
| 凌晨 | 05:00 |
| 上午 | 11:00 |
| 中午 | 12:30 |
| 下午 | 17:00 |
| 晚上 | 23:00 |

Todo 可以继续保留现有 `period` 元数据，用于解释用户原始表达；实际排序、Next、
Calendar 网格和逾期判断统一使用具体 `due_date`。

### 4.4 初始完成状态

创建 Todo 时：

- `due_date < now`：初始状态为完成；
- `due_date >= now`：初始状态为未完成。

这是一条纯时间规则，不分析句子的完成语义。

该规则只发生在创建动作：

- 原本未完成的未来 Todo 后续自然超过 deadline 时，进入逾期，不自动完成；
- 编辑已有 Todo 并把 deadline 改到过去时，保留编辑前的完成状态；
- 用户主动勾选或取消完成仍是正常的状态修改动作。

### 4.5 必填与业务不变量

`due_date` 不是要求用户亲自填写的表单必填项，而是系统在写入前保证的业务
不变量：

- 手动创建页打开时已经有默认 deadline；
- Agent 未抽取到时间时由 normalizer 补全；
- 服务端持久化新 Todo 前断言 `due_date` 存在且可解析。

现有技能 Schema 的 `required` 语义保持不变：手动写入严格校验；Agent 写入仍可
对自定义技能使用 best-effort 校验。Todo 的 `title` 继续是业务 Schema required。

## 5. 手动 Todo 交互

Todo 创建与编辑使用专用 deadline 组件，不再用普通单行文本输入时间。

### 5.1 创建

- 页面打开时根据第 4 节立即填入默认 deadline。
- 提供 `今天`、`明天` 两个快捷按钮。
- 点击快捷按钮后使用目标日期 18:00。
- 提供 `自定义` 入口，用户依次选择日期和时间。
- 用户可修改默认值，但保存时 deadline 始终存在。

### 5.2 编辑

- 编辑页复用同一个 deadline 组件和中文字段标签。
- 打开时展示当前 deadline，不重新应用创建默认值。
- 把时间改到过去不会自动修改完成状态。

## 6. 时间展示

### 6.1 数据原则

- 服务端只返回带时区的原始时间值。
- 服务端不把 ISO 时间拼进 `title`、`subtitle` 或 `meta_fields`。
- Flutter 使用一个共享 formatter，根据展示上下文决定粒度。

### 6.2 展示规则

| 场景 | 示例 |
|---|---|
| Session Todo 卡片 | `今天 18:00`、`明天 11:00`、`周一 17:00`、`8月15日 18:00` |
| 首页 Next | 倒计时 + 具体落点 |
| Calendar 时间轴 | `HH:mm` |
| Event 卡片 | `15:30–16:00` |
| 资产详情与编辑 | 完整本地日期时间 |

同一天不重复显示月日；跨年绝对日期需要包含年份。formatter 使用用户时区，不能
依赖设备对无时区字符串的隐式解析。

## 7. Thinking Orbs：A「有机编舞」

### 7.1 视觉状态层

新增 `ThinkingOrbVisualState`，只负责 UI 表达。Capture 与 Agent 现有状态映射到
它，不修改后端工作流。

| 视觉状态 | 形态与运动 |
|---|---|
| listening | 两个较大的外侧软球向外舒张 |
| receiving | 三个软球从不同方向被吸向中心 |
| transcribing | 三个节点横向依次脉冲 |
| understanding | 四个不对称软球围绕核心缓慢运动 |
| executing | 稳定核心加一至两个快速卫星节点 |
| composing | 两组软球交叉、编织并逐步对齐 |
| organizing | 分散节点持续向中心收束、合并 |
| success | 收束为稳定单球，短暂出现光晕 |
| empty | 空心、低振幅 Orb，不使用失败色 |
| failed | Orb 分裂成两部分，使用缓慢珊瑚色边缘脉冲，不抖动 |

状态切换采用约 220ms 的平滑形态过渡。Orb 始终保持同一种有机生命体身份，
状态识别依靠聚散、轨道、重心和节点数量，而不是依靠文字或单独颜色。

### 7.2 色彩

Orb 使用受控的统一色组：

- 主色：青色；
- 第二层：紫色；
- 少量强调：珊瑚色或暖黄色。

Light 顶栏接管态使用冷白至浅蓝紫背景，叠加紫色—珊瑚色—暖黄色反差光带。
Dark 顶栏接管态使用蓝黑至深紫背景，叠加暖黄色—洋红色—亮青色反差光带。

光带只做小距离、低速度移动，不快速扫过屏幕。

### 7.3 展示表面

- 顶部导航在捕捉期间继续整栏接管，保留来源、状态文案和队列数量。
- Session 使用同一 visual state 与 Orb 形态，但保持紧凑尺寸。
- Session 内容块不复制完整顶栏光带，避免聊天区域过重。
- `done`、`empty`、`failed` 使用各自终态后释放顶部导航。

## 8. 最新 Session 卡片协议

### 8.1 单一协议

新 Session 消息中的每张卡片只持久化以下结构：

```json
{
  "entity_kind": "asset | event | contact",
  "entity_id": "uuid",
  "skill_machine_name": "todo",
  "entity": {},
  "source": {
    "session_id": "uuid",
    "input_turn_id": "uuid",
    "kind": "capture | chat | report"
  }
}
```

约束：

- `entity_kind`、`entity_id`、`entity` 与 `source` 是服务端生成协议所需的技术字段；
- `skill_machine_name` 只对 `asset` 必需；
- 这些不是用户表单必填项；
- 服务端在消息落库前构造并验证该结构；
- 缺少技术身份时不持久化卡片，并记录可定位的服务端诊断。

### 8.2 展示

- `entity` 保存未经过 UI 格式化的实体字段与 payload。
- 不持久化格式化后的标题、副标题、图标、时间和 meta 文本。
- Flutter 统一根据 `entity_kind`、`skill_machine_name`、render spec 与时间
  formatter 生成卡片。
- 普通 Chat 与闪念 Session 复用同一个 resolver 和详情路由。
- 实体后来被删除时，显示“这条记录已不存在”。

### 8.3 无旧数据兼容

- 不读取旧 `card_type`、`kind`、`asset_id`、`event_id` 等混合协议。
- 不写数据迁移脚本。
- 不增加客户端 fallback。
- 旧测试 Session 和旧卡片不作为验收数据；验收使用新生成或重新 seed 的数据。

## 9. 数据流

### 9.1 Todo

1. 输入入口取得原始文字和可信 `reference_datetime`。
2. Agent 或手动表单产生标题及可选日期、时段、钟点。
3. `TodoDeadlineNormalizer` 产生带用户时区的 `due_date`。
4. 创建服务根据 `due_date < now` 决定初始完成状态。
5. Asset 服务校验业务不变量并写入。
6. Timeline、Next、Session 与详情从同一 `due_date` 读取时间。

### 9.2 Session 卡片

1. 工具成功创建实体。
2. 服务端根据实体构造最新卡片协议。
3. Session 消息持久化未格式化卡片数据。
4. Flutter resolver 根据实体类型和 render spec 生成卡片。
5. 点击后使用 `entity_kind + entity_id` 打开统一详情。

### 9.3 Thinking Orbs

1. Capture 或 Agent 状态保持现有来源。
2. UI 映射层转换为 `ThinkingOrbVisualState`。
3. 顶栏与 Session Orb 读取同一 visual state。
4. 终态结束后恢复常驻导航。

## 10. 错误处理

- Todo normalizer 无法解析显式日期时，创建失败并返回可读错误，不回退到错误日期。
- 用户时区不可用时使用产品默认时区，并记录诊断。
- 新卡片协议构造失败时，不写入残缺卡片；实体本身的成功创建不被伪装成卡片成功。
- 详情实体不存在时显示明确的删除态，不显示“无法处理”。
- Orb 的 failed 只表达对应任务失败，不作为全 Session 沉底错误。

## 11. 验证

### 11.1 后端

- 精确钟点、日期 + 时段、只有日期、只有时段、完全无时间的表驱动测试。
- 18:00 边界、23:00 跨日、用户时区和夏令时地区测试。
- 新建过去 deadline 自动完成；未来 Todo 后续逾期不自动完成。
- 编辑到过去不改变完成状态。
- 硬件、Chat、手动、Report Todo 入口的归一结果一致。
- 最新 Session 卡片协议 contract 测试。

### 11.2 Flutter

- `今天 / 明天 / 周几 / 绝对日期` formatter 测试。
- Todo 快捷按钮、日期时间选择与编辑状态测试。
- 普通 Chat 与闪念 Session 使用同一 resolver 的测试。
- `asset / event / contact` 详情路由测试。
- Light/Dark 顶栏 golden 与十个 Orb visual state 的组件测试。

### 11.3 真机

- 戒指、卡片与音频上传各创建一次 Todo。
- 在 18:00 前后分别创建无时间 Todo。
- 创建明确过去 deadline 的 Todo 并确认初始为完成。
- 在 Session、首页 Next、Calendar 和资产详情核对同一 deadline。
- 在 Light/Dark 模式逐一检查顶部光带、状态形态与 Session 紧凑 Orb。
- 使用本轮新数据验证事件、联系人、Todo 和自定义资产卡片可打开。

## 12. 验收标准

- 任一新 Todo 均有可解析、带时区的具体 `due_date`。
- 任一入口对相同时间表达得到相同 deadline 和初始状态。
- Session Todo 卡片不出现 ISO 字符串。
- 新 Session 卡片只有最新协议，不包含旧结构兼容分支。
- Light/Dark 顶栏均有可见但不过度抢眼的反差光带。
- 每个 Orb 状态在 28px Session 尺寸和 32px 顶栏尺寸下均可区分。
- 新生成的 Session 卡片均可进入正确详情。
