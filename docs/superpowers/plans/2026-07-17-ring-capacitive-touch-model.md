# 7·17 Ring Capacitive Touch Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 使用 7·17 新 GLB 展示真实电容触控区，并消除戒指切换时的双层重叠。

**Architecture:** 保留现有单 Canvas 与滚动状态机，只扩展模型准备结果，使触控材质可以被单独动画。静态 poster 只作为 WebGL 首帧前或失败时的 fallback，ready 后卸载。

**Tech Stack:** React 18、TypeScript、Three.js、React Three Fiber、Vitest、Testing Library。

## Global Constraints

- 不重建或简化设计师提供的戒指几何。
- 触控区只在「触」章节轻微强调。
- Flash 与 Vibe demo 页面不重新接入 landing page。
- 不修改 landing page 之外的功能链路。

---

### Task 1: 锁定新模型契约

**Files:**
- Modify: `ring-demo/src/components/living-ring/scene-config.test.ts`
- Modify: `ring-demo/src/components/living-ring/source-model.test.ts`
- Modify: `ring-demo/src/components/living-ring/LivingRingStage.test.tsx`

**Interfaces:**
- Produces: 新模型 URL、触控材质集合以及 ready 后单渲染源的行为契约。

- [ ] **Step 1: 写入新模型、触控材质和 poster 卸载的失败测试**
- [ ] **Step 2: 运行聚焦测试，确认失败原因分别是旧 URL、缺少 `touchMaterials`、poster 仍在 DOM**

### Task 2: 接入 7·17 GLB 与触控材质

**Files:**
- Create: `ring-demo/public/ring/ring-capacitive-7-17.glb`
- Modify: `ring-demo/src/components/living-ring/scene-config.ts`
- Modify: `ring-demo/src/components/living-ring/source-model.ts`
- Modify: `ring-demo/src/components/living-ring/LivingRingScene.tsx`

**Interfaces:**
- Produces: `PreparedSourceRing.touchMaterials: MeshStandardMaterial[]`。
- Consumes: `RingJourneyFrame.effectChapter`，值为 `"touch"` 时启用局部强调。

- [ ] **Step 1: 复制设计师 GLB 到带版本的新 URL**
- [ ] **Step 2: 收集 `材质.005` 并保存其原始 PBR 状态**
- [ ] **Step 3: 在帧循环中根据 `effectChapter` 平滑插值 emissive 与环境反射**
- [ ] **Step 4: 运行模型与配置测试，确认通过**

### Task 3: 消除双层戒指

**Files:**
- Modify: `ring-demo/src/components/living-ring/LivingRingStage.tsx`
- Modify: `ring-demo/src/styles.css`

**Interfaces:**
- Consumes: `sceneReady`。
- Produces: WebGL ready 后 DOM 中只保留 Canvas 戒指。

- [ ] **Step 1: 把 poster 渲染条件改为 `!sceneReady`**
- [ ] **Step 2: 删除 poster 与 Canvas 的交叉淡入规则，保留失败 fallback**
- [ ] **Step 3: 运行 Stage 测试，确认 ready 后 poster 被卸载**

### Task 4: 验证 landing 构建

**Files:**
- Verify: `ring-demo/`

**Interfaces:**
- Produces: 可交给用户截图 QA 的本地构建。

- [ ] **Step 1: 运行 living-ring 聚焦测试**
- [ ] **Step 2: 运行 `npm run typecheck`**
- [ ] **Step 3: 运行 `npm run build`**
