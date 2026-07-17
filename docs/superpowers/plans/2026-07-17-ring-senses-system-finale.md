# Eureka Ring 说触感与系统总结实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Landing Page 后半段升级为双行软件生态、连续的“说触感”交互演示，以及以电脑或手机为必要连接层的品牌与系统总结。

**Architecture:** 保留唯一的全局 `LivingRingStage` 与 WebGL Canvas，页面章节只提供锚点和文案。Logo Loop 使用纯 CSS 双轨；说触感使用固定在 Ring Stage 内的 DOM 特效层；系统总结使用独立语义组件和 CSS 光路。现有 `LANDING_RING_STOPS` 继续作为唯一滚动姿态数据源。

**Tech Stack:** React 18、TypeScript、GSAP ScrollTrigger、React Three Fiber、CSS transforms、Vitest、Testing Library。

## Global Constraints

- 不创建第二个 3D 戒指或 WebGL Canvas。
- 章节顺序必须为 Flash → Vibe → 说 → 触 → 感 → 品牌/系统总结 → CTA。
- 触只展示 7 种已验证手势：单击、双击、三击、上滑、下滑、左滑、右滑；不展示长按。
- 感只展示 3 种已验证反馈：强力、持续、渐变。
- 系统链路必须明确戒指通过电脑或手机连接个人智能、应用与资产。
- 动画只使用 transform 与 opacity；Reduced Motion 下内容必须完整可读。
- Logo 资源放在 `ring-demo/public/logos/`，支持透明 SVG 与 PNG，缺失时使用内置 fallback。

---

### Task 1: 双行软件生态 Logo Loop

**Files:**
- Modify: `ring-demo/src/components/landing/AppLogoLoop.tsx`
- Modify: `ring-demo/src/components/landing/AppLogoLoop.test.tsx`
- Modify: `ring-demo/src/components/landing/LandingStory.tsx`
- Modify: `ring-demo/src/components/landing/landing-content.ts`
- Modify: `ring-demo/src/styles.css`

**Interfaces:**
- Consumes: `readonly AppLogoItem[]` from `LandingStory`.
- Produces: `AppLogoItem { kind, name, src?, alt? }` and `AppLogoLoop({ rows })` with two accessible tracks.

- [ ] **Step 1: Write the failing component tests**

```tsx
render(<AppLogoLoop rows={[firstRow, secondRow]} />);
expect(screen.getAllByRole("list", { name: /示例连接软件/ })).toHaveLength(2);
expect(container.querySelectorAll(".app-logo-row")).toHaveLength(2);
expect(container.querySelector(".app-logo-row-reverse")).toBeInTheDocument();
expect(screen.getByRole("img", { name: "Codex" })).toHaveAttribute("src", "/logos/codex.svg");
```

- [ ] **Step 2: Run the focused test and verify failure**

Run: `cd ring-demo && npm test -- --run src/components/landing/AppLogoLoop.test.tsx`

Expected: FAIL because `rows`, `src`, and the second track are not implemented.

- [ ] **Step 3: Implement the two-row API and asset fallback**

```tsx
export interface AppLogoItem {
  kind: AppLogoKind;
  name: string;
  src?: string;
  alt?: string;
}

export function AppLogoLoop({ rows }: { rows: readonly (readonly AppLogoItem[])[] }) {
  return (
    <div className="app-logo-loop" data-testid="app-logo-loop">
      {rows.map((items, index) => (
        <div className={`app-logo-row${index === 1 ? " app-logo-row-reverse" : ""}`} key={index}>
          <div className="app-logo-track">
            <LogoSet items={items} label={`示例连接软件第 ${index + 1} 行`} />
            <LogoSet hidden items={items} />
          </div>
        </div>
      ))}
    </div>
  );
}
```

When `item.src` exists, render `<img alt={item.alt ?? item.name} src={item.src} />`; otherwise render `AppLogoMark`.

- [ ] **Step 4: Update Vibe content and CSS**

Use two item arrays, move `and even more` to row two, set row durations to `34s` and `42s`, reverse the second row, pause both tracks on `.app-logo-loop:hover`, and replace the support copy with:

```text
以上为常见办公与效率软件示例，连接范围仍在持续扩展。
```

- [ ] **Step 5: Run tests and commit**

Run: `cd ring-demo && npm test -- --run src/components/landing/AppLogoLoop.test.tsx src/components/landing/LandingStory.test.tsx`

Expected: PASS.

Commit: `git commit -m "feat(demo): add dual app logo loop"`

---

### Task 2: 说触感语义与特效层

**Files:**
- Create: `ring-demo/src/components/living-ring/SenseRingEffects.tsx`
- Create: `ring-demo/src/components/living-ring/SenseRingEffects.test.tsx`
- Modify: `ring-demo/src/components/living-ring/LivingRingStage.tsx`
- Modify: `ring-demo/src/components/living-ring/LivingRingStage.test.tsx`
- Modify: `ring-demo/src/components/landing/LandingStory.tsx`
- Modify: `ring-demo/src/components/landing/LandingStory.test.tsx`
- Modify: `ring-demo/src/components/landing/landing-content.ts`
- Modify: `ring-demo/src/styles.css`

**Interfaces:**
- Consumes: parent `.living-ring-stage[data-ring-chapter]` set by the existing animation loop.
- Produces: one decorative `.sense-ring-effects` with speak arcs, seven gesture labels, and three haptic signatures.

- [ ] **Step 1: Write failing semantics tests**

```tsx
render(<SenseRingEffects />);
for (const gesture of ["单击", "双击", "三击", "上滑", "下滑", "左滑", "右滑"]) {
  expect(screen.getByText(gesture)).toBeInTheDocument();
}
expect(screen.queryByText("长按")).not.toBeInTheDocument();
for (const haptic of ["强力", "持续", "渐变"]) {
  expect(screen.getByText(haptic)).toBeInTheDocument();
}
expect(container.querySelectorAll(".sense-speech-arc")).toHaveLength(3);
```

- [ ] **Step 2: Run focused test and verify failure**

Run: `cd ring-demo && npm test -- --run src/components/living-ring/SenseRingEffects.test.tsx`

Expected: FAIL because `SenseRingEffects` does not exist.

- [ ] **Step 3: Implement the single decorative effects component**

```tsx
const GESTURES = ["单击", "双击", "三击", "上滑", "下滑", "左滑", "右滑"] as const;
const HAPTICS = ["强力", "持续", "渐变"] as const;

export function SenseRingEffects() {
  return (
    <div aria-hidden="true" className="sense-ring-effects">
      <div className="sense-speech-effect">
        {[0, 1, 2].map((index) => <i className="sense-speech-arc" key={index} />)}
      </div>
      <div className="sense-touch-effect">
        {GESTURES.map((gesture, index) => <span data-index={index} key={gesture}>{gesture}</span>)}
      </div>
      <div className="sense-feel-effect">
        {HAPTICS.map((haptic) => <span className={`haptic-${haptic}`} key={haptic}>{haptic}</span>)}
      </div>
    </div>
  );
}
```

Mount it once inside `LivingRingStage`, after the poster and before the lazy 3D scene.

- [ ] **Step 4: Rebuild senses as three 92svh scenes**

Render one ScrollFloat heading and three `.sense-scene` articles. Use exact copy:

```text
说 / 自然语音输入 / 想法或指令，直接说出来。
触 / 7 种手势交互 / 同一个动作，在不同设备、应用和场景中承担不同含义。
感 / 3 种震动反馈 / 不用查看屏幕，也能感知状态与结果。
```

- [ ] **Step 5: Add transform/opacity-only visual states**

Use parent selectors such as `.living-ring-stage[data-ring-chapter="speak"] .sense-speech-effect`, `.living-ring-stage[data-ring-chapter="touch"] .sense-touch-effect`, and `.living-ring-stage[data-ring-chapter="feel"] .sense-feel-effect`. Under reduced motion, disable keyframes and display the active signatures statically.

- [ ] **Step 6: Run tests and commit**

Run: `cd ring-demo && npm test -- --run src/components/living-ring/SenseRingEffects.test.tsx src/components/living-ring/LivingRingStage.test.tsx src/components/landing/LandingStory.test.tsx`

Expected: PASS.

Commit: `git commit -m "feat(demo): animate ring speech touch and haptics"`

---

### Task 3: 品牌宣言与系统闭环

**Files:**
- Create: `ring-demo/src/components/landing/SystemFinale.tsx`
- Create: `ring-demo/src/components/landing/SystemFinale.test.tsx`
- Modify: `ring-demo/src/components/landing/LandingStory.tsx`
- Modify: `ring-demo/src/components/landing/LandingStory.test.tsx`
- Modify: `ring-demo/src/components/landing/landing-content.ts`
- Modify: `ring-demo/src/styles.css`

**Interfaces:**
- Consumes: `LANDING_CONTENT.system` manifesto, description, and four node labels.
- Produces: a `150svh` section with a `100svh` sticky canvas and `system-start` / `system-end` anchors.

- [ ] **Step 1: Write failing system tests**

```tsx
render(<SystemFinale />);
expect(screen.getByRole("heading", { name: "不是把助手缩小。是让智能，始终在手边。" })).toBeInTheDocument();
for (const label of ["Eureka Ring", "电脑或手机", "个人智能", "应用、AI 与资产", "触觉反馈"]) {
  expect(screen.getByText(label)).toBeInTheDocument();
}
expect(container.querySelector(".system-flow")).not.toBeInTheDocument();
expect(container.querySelector(".system-proof")).not.toBeInTheDocument();
```

- [ ] **Step 2: Run focused test and verify failure**

Run: `cd ring-demo && npm test -- --run src/components/landing/SystemFinale.test.tsx`

Expected: FAIL because `SystemFinale` does not exist.

- [ ] **Step 3: Implement semantic system finale**

```tsx
export function SystemFinale() {
  return (
    <section className="landing-system-finale" aria-labelledby="landing-system-title">
      <div className="system-finale-sticky">
        <ScrollFloatText id="landing-system-title" lines={[
          { text: "不是把助手缩小。" },
          { text: "是让智能，始终在手边。" },
        ]} text="不是把助手缩小。是让智能，始终在手边。" />
        <p>Eureka Ring 通过电脑或手机连接个人智能，让语音、手势和触觉反馈进入用户正在使用的应用与设备。</p>
        <div className="system-orbit" aria-label="Eureka Ring 系统闭环">
          <span className="system-node system-node-intelligence">个人智能</span>
          <span className="system-node system-node-ring">Eureka Ring</span>
          <span className="system-node system-node-device">电脑或手机</span>
          <span className="system-node system-node-output">应用、AI 与资产</span>
          <span className="system-feedback">触觉反馈</span>
        </div>
      </div>
      <i data-ring-chapter="system-start" />
      <i data-ring-chapter="system-end" />
    </section>
  );
}
```

- [ ] **Step 4: Move senses before the finale and remove old structure**

`LandingStory` order must be Vibe → `.landing-senses` → `<SystemFinale />`. Delete old `system-flow`, `system-proof`, numbered steps, and neon center rail.

- [ ] **Step 5: Add desktop and mobile closed-loop layout**

Desktop: intelligence above, Ring and device across center, output below, feedback arc returning to Ring. Mobile: vertical intelligence → Ring/device → output, feedback arc on the right. Animate appearance only via opacity and translate/scale transforms.

- [ ] **Step 6: Run tests and commit**

Run: `cd ring-demo && npm test -- --run src/components/landing/SystemFinale.test.tsx src/components/landing/LandingStory.test.tsx src/components/landing/landing-content.test.ts`

Expected: PASS.

Commit: `git commit -m "feat(demo): add ring system finale"`

---

### Task 4: 全局戒指路线与硬币翻转

**Files:**
- Modify: `ring-demo/src/components/living-ring/landing-journey.ts`
- Modify: `ring-demo/src/components/living-ring/landing-journey.test.ts`
- Modify: `ring-demo/src/components/living-ring/LivingRingStage.tsx`
- Modify: `ring-demo/src/components/living-ring/LivingRingScene.tsx`
- Modify: `ring-demo/src/styles.css`

**Interfaces:**
- Consumes: ordered `[data-ring-chapter]` anchors from `HomePage`.
- Produces: continuous frames ordered `vibe-exit → speak → touch → feel → system-start → system-end → community`.

- [ ] **Step 1: Rewrite failing route expectations**

```ts
expect(LANDING_RING_STOPS.map(({ id }) => id)).toEqual([
  "hero", "modes", "mode-bridge", "flash-intro", "flash-scene",
  "vibe-intro", "vibe-scene", "vibe-exit", "speak", "touch", "feel",
  "system-start", "system-end", "community",
]);
expect(touch.rotation[1] - speak.rotation[1]).toBeCloseTo(Math.PI, 1);
expect(feel.rotation[1] - touch.rotation[1]).toBeCloseTo(Math.PI, 1);
expect(systemStart.position[0]).toBe(0);
expect(systemEnd.position[0]).toBe(0);
```

- [ ] **Step 2: Run focused test and verify failure**

Run: `cd ring-demo && npm test -- --run src/components/living-ring/landing-journey.test.ts`

Expected: FAIL because system currently precedes senses and the rotations exceed one coin flip.

- [ ] **Step 3: Reorder and tune stops**

Use approximate progress allocation `vibe-exit 0.60`, `speak 0.68`, `touch 0.76`, `feel 0.84`, `system-start 0.90`, `system-end 0.96`, `community 1`. Keep senses at the right display position with Y rotations `base`, `base + π`, `base + 2π`; center both system stops.

- [ ] **Step 4: Align poster and DOM effects**

Continue setting `stage.dataset.ringChapter = landingFrame.chapter` in the animation loop. Ensure `.sense-ring-effects` inherits the same poster translation, scale, pointer offsets, and opacity variables so effects remain centered on the visible 3D ring/poster.

- [ ] **Step 5: Run route tests and commit**

Run: `cd ring-demo && npm test -- --run src/components/living-ring/landing-journey.test.ts src/components/living-ring/LivingRingStage.test.tsx`

Expected: PASS.

Commit: `git commit -m "feat(demo): route ring through senses and finale"`

---

### Task 5: Full verification and visual QA

**Files:**
- Modify if needed: `ring-demo/src/styles.css`
- Modify if needed: focused tests from Tasks 1–4

**Interfaces:**
- Consumes: completed landing page.
- Produces: verified desktop/mobile/reduced-motion presentation.

- [ ] **Step 1: Run the complete automated suite**

Run:

```bash
cd ring-demo
npm test -- --run
npm run typecheck
npm run build
```

Expected: all tests pass, typecheck exits 0, production build exits 0. The existing large 3D chunk warning is acceptable; new errors are not.

- [ ] **Step 2: Start the local site and inspect desktop**

Run: `cd ring-demo && npm run dev -- --host 127.0.0.1 --port 5176`

Use gstack `/browse` at `1440×900`. Verify two logo rows, no horizontal overflow, no text occlusion, all seven gestures, all three haptic signatures, and the system loop.

- [ ] **Step 3: Inspect mobile and reduced motion**

Use gstack `/browse` at `390×844`, then emulate `prefers-reduced-motion: reduce`. Verify Logo tracks wrap, labels remain inside viewport, and no continuous animation remains.

- [ ] **Step 4: Check console/network and commit QA fixes**

Expected: no console errors and no failed local asset requests. Missing optional `/logos/*` files must use fallback marks rather than generate 404s.

Commit: `git commit -m "fix(demo): polish landing finale responsiveness"`
