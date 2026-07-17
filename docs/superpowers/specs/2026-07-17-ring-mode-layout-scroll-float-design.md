# Eureka Ring 双模式版式与标题动效设计

## 目标

修正 Landing Page 中第二屏、Flash 与 Vibe 章节的文字遮挡和戒指跳位问题。保留唯一的全屏 `LivingRingStage`，让戒指从 Hero 连续经过第二屏中轴通道，再按镜像四象限结构进入 Flash 与 Vibe 场景。章节标题使用克制的 Scroll Float 入场；Decrypted Text 暂不实现。

## 第二屏

- 标题拆成两个独立行：`一枚戒指` 与 `两种智能体验`。
- 桌面端第一行位于左上，第二行位于右下，中间保留约 220–280px 的纵向安全通道。
- 戒指从 Hero 右侧向中轴收拢，在第二屏沿通道垂直下降，不覆盖标题或两段模式文案。
- 两段模式文案继续左右分列，但不得侵入中轴安全通道。
- 移动端标题恢复自然纵向排列；戒指使用 compact journey，不追求桌面端中轴精确路线。

## Flash 与 Vibe 镜像四象限

### Flash

- 左上：标题、Slogan 与说明。
- 右上：完整戒指展示安全区。
- 左下：驾驶场景图。
- 右下：处理链路、示例或辅助文案。
- 戒指从右上展示位沿弧线滚入左下人物手部，接近照片戒指时缩小并淡出。

### Vibe

- 左上：完整戒指展示安全区。
- 右上：标题、Slogan 与说明。
- 左下：支持范围说明与示例软件文案。
- 右下：办公室场景图。
- 戒指从 Flash 人物手部继续移动到 Vibe 左上并重新展开，再沿镜像弧线滚入右下人物手部。

## 连续戒指路线

`Hero 右侧 → 第二屏中轴 → Flash 右上 → Flash 左下手部 → Vibe 左上 → Vibe 右下手部 → 系统中轴`

- 任何章节切换都不得重置模型或瞬间跳到新位置。
- 只修改 transform、旋转、缩放、透明度和材质参数。
- Flash 与 Vibe 的完整展示位必须 100% 显示戒指，不压标题。
- 场景交接使用缩小与淡出，避免和照片内戒指形成双影。

## Scroll Float

- Hero `h1` 保持稳定，不使用逐字 Scroll Float。
- 第二屏、Flash、Vibe、系统以及“说，触，感”主标题使用统一的 `ScrollFloatText`。
- 每个可见字符包裹为独立 span；空格和标点保持自然宽度。
- 初始状态使用 `autoAlpha: 0`、`yPercent: 65`、`scaleY: 0.82`，以 `power3.out`、约 0.72 秒和 0.022 秒 stagger 进入。
- ScrollTrigger 使用一次性入场，不使用 scrub，不在回滚时反复播放。
- `prefers-reduced-motion` 下直接显示完整文字，不拆分视觉动画。
- 组件保留可访问的完整标题文本，动画字符对辅助技术隐藏。

## 性能与依赖

- 继续使用项目已有 `gsap`、`@gsap/react` 与 `ScrollTrigger`，不新增依赖。
- GSAP selector 必须限定在组件 scope 中并自动 cleanup。
- 只动画 transform 与 opacity；不动画 top、left、width 或 height。
- 不实现 Decrypted Text，不引入 `motion`。

## 验收标准

- 第二屏可读标题为两行，DOM 中存在明确的中轴安全通道。
- 戒指在第二屏不遮挡标题或模式文案。
- Flash 与 Vibe 桌面端呈镜像四象限排版。
- Flash 完整展示位位于右上，Vibe 完整展示位位于左上。
- 戒指路线的 X 方向依次为：中轴、右、左、左、右。
- 章节主标题拥有一次性 Scroll Float；Hero 标题没有该效果。
- Reduced Motion 下全部标题立即可读。
- Decrypted Text 不出现在依赖、组件或样式中。

## 2026-07-17 视觉修订

用户在桌面端实测后确认以下修订，替代上文中冲突的细节：

- Scroll Float 不再是提前结束的一次性入场。采用与 React Bits 示例一致的滚动进度驱动方式，在标题穿过视口时逐字完成位移、纵向拉伸与透明度过渡。
- 总览、Flash、Vibe、系统、“说，触，感”和最终 CTA 的章节主标题全部使用 Scroll Float；Hero 主标题继续保持稳定。
- `modes` 与 `flash-intro` 之间增加 `mode-bridge` 叙事锚点。戒指在桥接点保持中轴、小尺度和完整可见，再进入 Flash 右上展示位，禁止在总览两列文案之间提前放大。
- Flash 的处理链路保留有序细线；示例结果改为独立的“语音 → 资产”结果带，用错落间距、输出标签和背景层次区分，不复用链路的分割线语言。
- Vibe 左下内容替换为持续滚动的软件生态 Logo Loop。Codex、钉钉、VS Code、Cursor、GitHub、Notion、Figma、Slack 与 Chrome 等标识共同出现，并以 `and even more` 收尾；循环外明确说明它们只是示例，连接能力可以扩展到更多桌面工具。
- 戒指进入 Vibe 场景图后保持隐藏，直到系统章节中轴重新出现，避免穿过 Logo Loop 的标题与说明。
- 全局清理装饰性的 `01` 编号、`PRODUCT VIEW`、重复大写 eyebrow 与过度字距。只有真正表示先后顺序的处理链路和系统流程保留编号。
- Decrypted Text 继续搁置。
