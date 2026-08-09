# Kenney Daily World Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone portrait HTML prototype that combines real Kenney Nature Kit sprites into a horizontally scrollable Eureka daily world and compares raw Kenney presentation with Eureka styling and lifecycle states.

**Architecture:** Keep licensed source sprites immutable and compose them into deterministic scene clusters in the browser. A pure CommonJS-compatible core owns seeded generation and state transitions; a DOM adapter renders the scene and handles gestures; CSS owns pseudo-3D depth, visual transformation, and motion. The demo is isolated under `spec/design/kenney-daily-world-demo/` and does not touch Flutter or backend code.

**Tech Stack:** Vanilla HTML5, CSS, browser JavaScript, Node.js built-in test runner, Kenney Nature Kit isometric PNG assets, gstack browse for viewport verification.

## Global Constraints

- The app viewport is portrait-only and based on 390 × 844 logical pixels.
- The interactive world is one continuous 1,800-pixel strip and scrolls only horizontally.
- The prototype uses southeast-facing isometric PNGs from the actual Kenney Nature Kit.
- No build step, package install, remote font, remote icon, or remote asset request is allowed.
- Tree silhouette is random visual variation; inline SVG icon is semantics; CSS state class is lifecycle.
- `clusterSeed = hash(localDate + entityId)` must be deterministic.
- The default scene contains exactly five objects; failed report reuses the report-generating object.
- Original and Eureka modes must preserve identical generated choices and positions.
- All controls and objects have a minimum 44 × 44 logical-pixel target.
- `prefers-reduced-motion` must remove continuous motion without removing state information.
- Preserve the original Kenney CC0 license and do not use the Kenney logo.
- Do not modify any existing Theme V2, Flutter, backend, or ring-demo source file.

---

## File Structure

```text
spec/design/kenney-daily-world-demo/
  index.html                         semantic phone shell and controls
  styles.css                        world geometry, modes, states, accessibility
  world-core.js                     pure deterministic generator and state reducer
  world-app.js                      DOM rendering, preload, input, and focus handling
  asset-manifest.js                 browser/Node third-party sprite inventory
  README.md                          usage, design intent, and provenance
  tests/
    asset-manifest.test.cjs         selected-file and license contract
    world-core.test.cjs             deterministic generation and state reducer
    document-contract.test.cjs      self-contained HTML and accessibility contract
    styles-contract.test.cjs        required mode/state/reduced-motion selectors
  assets/kenney/
    18 selected PNG sprites
  third-party/
    Kenney-Nature-Kit-License.txt
```

The files are split by responsibility so the generator can be tested without a browser and the third-party source files remain separate from Eureka-owned code.

---

### Task 1: Create the Licensed Asset Subset and Provenance Contract

**Files:**
- Create: `spec/design/kenney-daily-world-demo/asset-manifest.js`
- Create: `spec/design/kenney-daily-world-demo/tests/asset-manifest.test.cjs`
- Create: `spec/design/kenney-daily-world-demo/assets/kenney/*.png`
- Create: `spec/design/kenney-daily-world-demo/third-party/Kenney-Nature-Kit-License.txt`

**Interfaces:**
- Consumes: `/tmp/kenney_nature-kit.zip`, previously downloaded from the official Kenney Nature Kit page.
- Produces: `TREE_ASSETS`, `BUSH_ASSETS`, `ACCENT_ASSETS`, `ROCK_ASSETS`, and `ALL_ASSETS` arrays for `world-core.js`.

- [ ] **Step 1: Write the failing asset inventory test**

```js
// tests/asset-manifest.test.cjs
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const manifest = require('../asset-manifest.js');

const root = path.resolve(__dirname, '..');

test('manifest contains the exact selected asset counts', () => {
  assert.equal(manifest.TREE_ASSETS.length, 8);
  assert.equal(manifest.BUSH_ASSETS.length, 3);
  assert.equal(manifest.ACCENT_ASSETS.length, 3);
  assert.equal(manifest.ROCK_ASSETS.length, 4);
  assert.equal(manifest.ALL_ASSETS.length, 18);
});

test('every selected Kenney sprite and the original license are present', () => {
  for (const filename of manifest.ALL_ASSETS) {
    assert.equal(fs.existsSync(path.join(root, 'assets', 'kenney', filename)), true, filename);
  }
  const license = fs.readFileSync(
    path.join(root, 'third-party', 'Kenney-Nature-Kit-License.txt'),
    'utf8',
  );
  assert.match(license, /Creative Commons Zero, CC0/);
  assert.match(license, /commercial projects/);
});
```

- [ ] **Step 2: Run the inventory test and verify it fails**

Run:

```bash
node --test spec/design/kenney-daily-world-demo/tests/asset-manifest.test.cjs
```

Expected: FAIL because `asset-manifest.js` does not exist.

- [ ] **Step 3: Create the exact manifest**

```js
// asset-manifest.js
(function attachAssetManifest(root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (root) root.EurekaAssetManifest = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function createAssetManifest() {
  'use strict';

  const TREE_ASSETS = Object.freeze([
  'tree_default_SE.png',
  'tree_oak_SE.png',
  'tree_plateau_SE.png',
  'tree_pineRoundC_SE.png',
  'tree_thin_SE.png',
  'tree_blocks_SE.png',
  'tree_detailed_SE.png',
  'tree_tall_SE.png',
]);

  const BUSH_ASSETS = Object.freeze([
  'plant_bushDetailed_SE.png',
  'plant_bushSmall_SE.png',
  'plant_bushTriangle_SE.png',
]);

  const ACCENT_ASSETS = Object.freeze([
  'flower_yellowB_SE.png',
  'grass_leafsLarge_SE.png',
  'mushroom_tanGroup_SE.png',
]);

  const ROCK_ASSETS = Object.freeze([
  'rock_smallTopB_SE.png',
  'rock_smallC_SE.png',
  'rock_largeC_SE.png',
  'rock_tallA_SE.png',
]);

  const ALL_ASSETS = Object.freeze([
  ...TREE_ASSETS,
  ...BUSH_ASSETS,
  ...ACCENT_ASSETS,
  ...ROCK_ASSETS,
]);

  return { TREE_ASSETS, BUSH_ASSETS, ACCENT_ASSETS, ROCK_ASSETS, ALL_ASSETS };
});
```

- [ ] **Step 4: Extract only the selected sprites and original license**

Run from the repository root:

```bash
mkdir -p spec/design/kenney-daily-world-demo/assets/kenney
mkdir -p spec/design/kenney-daily-world-demo/third-party
unzip -jo /tmp/kenney_nature-kit.zip \
  'Isometric/tree_default_SE.png' \
  'Isometric/tree_oak_SE.png' \
  'Isometric/tree_plateau_SE.png' \
  'Isometric/tree_pineRoundC_SE.png' \
  'Isometric/tree_thin_SE.png' \
  'Isometric/tree_blocks_SE.png' \
  'Isometric/tree_detailed_SE.png' \
  'Isometric/tree_tall_SE.png' \
  'Isometric/plant_bushDetailed_SE.png' \
  'Isometric/plant_bushSmall_SE.png' \
  'Isometric/plant_bushTriangle_SE.png' \
  'Isometric/flower_yellowB_SE.png' \
  'Isometric/grass_leafsLarge_SE.png' \
  'Isometric/mushroom_tanGroup_SE.png' \
  'Isometric/rock_smallTopB_SE.png' \
  'Isometric/rock_smallC_SE.png' \
  'Isometric/rock_largeC_SE.png' \
  'Isometric/rock_tallA_SE.png' \
  -d spec/design/kenney-daily-world-demo/assets/kenney
unzip -jo /tmp/kenney_nature-kit.zip License.txt \
  -d spec/design/kenney-daily-world-demo/third-party
mv spec/design/kenney-daily-world-demo/third-party/License.txt \
  spec/design/kenney-daily-world-demo/third-party/Kenney-Nature-Kit-License.txt
```

Expected: exactly 18 PNG files and one renamed license file are created.

- [ ] **Step 5: Run the inventory test and verify it passes**

Run:

```bash
node --test spec/design/kenney-daily-world-demo/tests/asset-manifest.test.cjs
```

Expected: 2 tests PASS.

- [ ] **Step 6: Commit the licensed subset**

```bash
git add spec/design/kenney-daily-world-demo/asset-manifest.js \
  spec/design/kenney-daily-world-demo/tests/asset-manifest.test.cjs \
  spec/design/kenney-daily-world-demo/assets/kenney \
  spec/design/kenney-daily-world-demo/third-party/Kenney-Nature-Kit-License.txt
git commit -m "chore(theme-v2): add Kenney demo asset subset"
```

---

### Task 2: Build the Deterministic Scene Generator and State Reducer

**Files:**
- Create: `spec/design/kenney-daily-world-demo/world-core.js`
- Create: `spec/design/kenney-daily-world-demo/tests/world-core.test.cjs`

**Interfaces:**
- Consumes: `EurekaAssetManifest` from `asset-manifest.js` in the browser or `require('./asset-manifest.js')` under Node.
- Produces: `window.EurekaWorldCore` and `module.exports` with `DEMO_ENTITIES`, `localDateKey`, `hashString`, `createRandom`, `generateCluster`, `generateScene`, `classifyGesture`, and `reduceDemoState`.

- [ ] **Step 1: Write failing deterministic-generation and reducer tests**

```js
// tests/world-core.test.cjs
const test = require('node:test');
const assert = require('node:assert/strict');
const core = require('../world-core.js');

test('same date and entity produce the same cluster', () => {
  const entity = core.DEMO_ENTITIES[0];
  assert.deepEqual(
    core.generateCluster('2026-08-09', entity),
    core.generateCluster('2026-08-09', entity),
  );
});

test('local date key does not depend on UTC rollover', () => {
  assert.equal(core.localDateKey(new Date(2026, 7, 9, 23, 30)), '2026-08-09');
});

test('changing the date changes at least one generated choice', () => {
  const first = core.generateScene('2026-08-09', core.DEMO_ENTITIES);
  const second = core.generateScene('2026-08-10', core.DEMO_ENTITIES);
  assert.notDeepEqual(
    first.map(({ treeAsset, bushAsset, accentAsset, rockAsset }) => ({
      treeAsset, bushAsset, accentAsset, rockAsset,
    })),
    second.map(({ treeAsset, bushAsset, accentAsset, rockAsset }) => ({
      treeAsset, bushAsset, accentAsset, rockAsset,
    })),
  );
});

test('state changes preserve generated tree identity', () => {
  const scene = core.generateScene('2026-08-09', core.DEMO_ENTITIES);
  const initial = core.createInitialState('2026-08-09', scene);
  const tree = initial.scene.find((item) => item.id === 'report-generating').treeAsset;
  const failed = core.reduceDemoState(initial, { type: 'TOGGLE_REPORT_FAILURE' });
  assert.equal(failed.scene.find((item) => item.id === 'report-generating').treeAsset, tree);
  assert.equal(failed.reportFailed, true);
});

test('gesture classifier protects taps after horizontal drag', () => {
  assert.equal(core.classifyGesture(4, 3), 'tap');
  assert.equal(core.classifyGesture(18, 2), 'horizontal-drag');
  assert.equal(core.classifyGesture(3, 20), 'vertical-intent');
});
```

- [ ] **Step 2: Run the tests and verify they fail**

Run:

```bash
node --test spec/design/kenney-daily-world-demo/tests/world-core.test.cjs
```

Expected: FAIL because `world-core.js` does not exist.

- [ ] **Step 3: Implement the pure generator and reducer**

Create `world-core.js` as a strict-mode IIFE. It must:

```js
(function attachWorldCore(root, factory) {
  const manifest = typeof module === 'object' && module.exports
    ? require('./asset-manifest.js')
    : root.EurekaAssetManifest;
  const api = factory(manifest);
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (root) root.EurekaWorldCore = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function createWorldCore(manifest) {
  'use strict';

  const TREES = manifest.TREE_ASSETS;
  const BUSHES = manifest.BUSH_ASSETS;
  const ACCENTS = manifest.ACCENT_ASSETS;
  const ROCKS = manifest.ROCK_ASSETS;

  const DEMO_ENTITIES = Object.freeze([
    { id: 'rhythm', kind: 'rhythm', state: 'signal', title: '晨间状态还没有记录',
      actionLabel: '记录一次', worldX: 310, depthBand: 1 },
    { id: 'todo-overdue', kind: 'todo', state: 'overdue', title: '回复产品方案反馈',
      actionLabel: '打开代办', worldX: 650, depthBand: 2 },
    { id: 'running', kind: 'running', state: 'completed', title: '户外跑步 · 4.8 公里',
      actionLabel: '打开记录', worldX: 980, depthBand: 1 },
    { id: 'report-generating', kind: 'report', state: 'generating', title: '睡眠节律报告生成中',
      actionLabel: '查看进度', worldX: 1320, depthBand: 2 },
    { id: 'report-completed', kind: 'report', state: 'completed', title: '本周恢复趋势',
      actionLabel: '打开报告', worldX: 1610, depthBand: 1 },
  ]);

  function localDateKey(date) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  function hashString(value) {
    let hash = 2166136261;
    for (let index = 0; index < value.length; index += 1) {
      hash ^= value.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return hash >>> 0;
  }

  function createRandom(seed) {
    return function nextRandom() {
      seed |= 0;
      seed = (seed + 0x6D2B79F5) | 0;
      let value = Math.imul(seed ^ (seed >>> 15), 1 | seed);
      value = (value + Math.imul(value ^ (value >>> 7), 61 | value)) ^ value;
      return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
    };
  }

  function pick(values, random) {
    return values[Math.floor(random() * values.length)];
  }

  function generateCluster(dayKey, entity) {
    const random = createRandom(hashString(`${dayKey}:${entity.id}`));
    return Object.freeze({
      ...entity,
      treeAsset: pick(TREES, random),
      bushAsset: random() > 0.28 ? pick(BUSHES, random) : null,
      accentAsset: random() > 0.18 ? pick(ACCENTS, random) : null,
      rockAsset: random() > 0.42 ? pick(ROCKS, random) : null,
      scale: Number((0.88 + random() * 0.22).toFixed(3)),
      lean: Number((-3 + random() * 6).toFixed(2)),
      offsetX: Math.round(-14 + random() * 28),
      offsetY: Math.round(-5 + random() * 10),
    });
  }

  function generateScene(dayKey, entities) {
    return entities.map((entity) => generateCluster(dayKey, entity));
  }

  function createInitialState(dayKey, scene) {
    return { dayKey, mode: 'eureka', focusedId: null, popoverId: null,
      reportFailed: false, scene };
  }

  function classifyGesture(deltaX, deltaY) {
    if (Math.abs(deltaX) <= 8 && Math.abs(deltaY) <= 8) return 'tap';
    return Math.abs(deltaX) > Math.abs(deltaY) ? 'horizontal-drag' : 'vertical-intent';
  }

  function reduceDemoState(state, action) {
    switch (action.type) {
      case 'SET_MODE': return { ...state, mode: action.mode };
      case 'FOCUS': return { ...state, focusedId: action.id, popoverId: null };
      case 'OPEN_POPOVER': return { ...state, focusedId: action.id, popoverId: action.id };
      case 'CLEAR_FOCUS': return { ...state, focusedId: null, popoverId: null };
      case 'TOGGLE_REPORT_FAILURE': return { ...state, reportFailed: !state.reportFailed };
      case 'SET_DAY': {
        const scene = generateScene(action.dayKey, DEMO_ENTITIES);
        return createInitialState(action.dayKey, scene);
      }
      default: return state;
    }
  }

  return { DEMO_ENTITIES, localDateKey, hashString, createRandom, generateCluster, generateScene,
    createInitialState, classifyGesture, reduceDemoState };
});
```

- [ ] **Step 4: Run the generator tests and verify they pass**

Run:

```bash
node --test spec/design/kenney-daily-world-demo/tests/world-core.test.cjs
```

Expected: 5 tests PASS.

- [ ] **Step 5: Commit the deterministic core**

```bash
git add spec/design/kenney-daily-world-demo/world-core.js \
  spec/design/kenney-daily-world-demo/tests/world-core.test.cjs
git commit -m "feat(theme-v2): add deterministic daily world generator"
```

---

### Task 3: Build the Self-Contained Portrait Scene and Mode Comparison

**Files:**
- Create: `spec/design/kenney-daily-world-demo/index.html`
- Create: `spec/design/kenney-daily-world-demo/styles.css`
- Create: `spec/design/kenney-daily-world-demo/world-app.js`
- Create: `spec/design/kenney-daily-world-demo/tests/document-contract.test.cjs`

**Interfaces:**
- Consumes: `window.EurekaWorldCore` from `world-core.js` and local files under `assets/kenney/`.
- Produces: DOM elements with `data-entity-id`, `data-kind`, and `data-state`, plus controls `#mode-original`, `#mode-eureka`, `#next-day`, `#return-now`, and `#report-state`.

- [ ] **Step 1: Write the failing document contract test**

```js
// tests/document-contract.test.cjs
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');

test('document is local-only and exposes the required controls', () => {
  const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
  assert.doesNotMatch(html, /https?:\/\//);
  for (const id of ['mode-original', 'mode-eureka', 'next-day', 'return-now',
    'report-state', 'world-scroll', 'world-strip']) {
    assert.match(html, new RegExp(`id=["']${id}["']`));
  }
  assert.match(html, /width=device-width/);
  assert.match(html, /aria-label=/);
});

test('scripts load in file-compatible order without modules', () => {
  const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
  assert.doesNotMatch(html, /type=["']module["']/);
  assert.ok(html.indexOf('asset-manifest.js') < html.indexOf('world-core.js'));
  assert.ok(html.indexOf('world-core.js') < html.indexOf('world-app.js'));
});
```

- [ ] **Step 2: Run the document test and verify it fails**

Run:

```bash
node --test spec/design/kenney-daily-world-demo/tests/document-contract.test.cjs
```

Expected: FAIL because `index.html` does not exist.

- [ ] **Step 3: Create the semantic HTML shell**

`index.html` must contain these exact structural regions:

```html
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
  <title>Eureka · 今日世界 Kenney Demo</title>
  <link rel="stylesheet" href="./styles.css">
  <script src="./asset-manifest.js" defer></script>
  <script src="./world-core.js" defer></script>
  <script src="./world-app.js" defer></script>
</head>
<body>
  <main class="demo-page">
    <section class="phone" aria-label="Eureka 今日世界演示">
      <header class="app-header">
        <div><p class="eyebrow">TODAY · <span id="day-label"></span></p><h1>今天</h1></div>
        <button id="next-day" class="icon-control" type="button" aria-label="换一天">↻</button>
      </header>
      <div class="mode-switch" role="group" aria-label="视觉模式">
        <button id="mode-original" type="button">原始 Kenney</button>
        <button id="mode-eureka" type="button" aria-pressed="true">Eureka</button>
      </div>
      <div id="world-scroll" class="world-scroll" tabindex="0" aria-label="可水平浏览的今日世界">
        <div id="world-strip" class="world-strip" data-mode="eureka">
          <div class="layer layer-sky" aria-hidden="true"></div>
          <div class="layer layer-back" aria-hidden="true"></div>
          <div id="entity-layer" class="layer entity-layer"></div>
          <div class="layer layer-front" aria-hidden="true"></div>
          <div id="now-marker" class="now-marker" aria-hidden="true"><span>现在</span></div>
        </div>
      </div>
      <button id="return-now" class="return-now" type="button">回到现在</button>
      <div class="demo-controls">
        <button id="report-state" type="button">演示报告失败状态</button>
        <p>左右滑动 · 点击树查看内容</p>
      </div>
      <div id="popover-root" class="popover-root" aria-live="polite"></div>
    </section>
  </main>
</body>
</html>
```

- [ ] **Step 4: Create the initial visual system and fixed world geometry**

`styles.css` must define the approved tokens and fixed world geometry before state animation is added:

```css
:root {
  --canvas: #f1efe8; --paper: #fbfaf7; --ink: #1d211f; --muted: #74776f;
  --brand: #476c9b; --warm: #b8874c; --success: #617d62; --danger: #9a5d57;
  --sky-top: #d9e4df; --sky-bottom: #ece8d8; --ground: #b9c6a6;
  --font: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", Arial, sans-serif;
}
* { box-sizing: border-box; }
body { margin: 0; min-height: 100vh; background: var(--canvas); color: var(--ink); font-family: var(--font); }
button { font: inherit; }
.demo-page { min-height: 100vh; display: grid; place-items: center; padding: 8px; overflow: hidden; }
.phone { position: relative; width: min(390px, calc(100vw - 16px)); height: min(844px, calc(100vh - 16px)); overflow: hidden;
  border-radius: 42px; background: var(--paper); box-shadow: 0 28px 80px rgba(34, 39, 34, .16); }
.app-header { position: absolute; z-index: 50; inset: 0 0 auto; display: flex; justify-content: space-between;
  align-items: center; padding: 28px 22px 12px; pointer-events: none; }
.app-header button { pointer-events: auto; }
.eyebrow { margin: 0 0 4px; color: var(--muted); font-size: 10px; letter-spacing: .14em; }
h1 { margin: 0; font-size: 28px; line-height: 1; }
.icon-control, .return-now, .mode-switch button, .demo-controls button { min-width: 44px; min-height: 44px; }
.world-scroll { position: absolute; inset: 0; overflow-x: auto; overflow-y: hidden; scrollbar-width: none;
  touch-action: pan-y; cursor: grab; }
.world-scroll::-webkit-scrollbar { display: none; }
.world-strip { position: relative; width: 1800px; height: 100%; overflow: hidden;
  background: linear-gradient(var(--sky-top), var(--sky-bottom) 56%, var(--ground) 56%); }
.layer { position: absolute; inset: 0; pointer-events: none; }
.layer-back::before, .layer-back::after { content: ""; position: absolute; bottom: 34%; width: 720px; height: 190px;
  border-radius: 55% 45% 0 0; background: rgba(126,147,128,.24); filter: blur(1px); }
.layer-back::before { left: 60px; }
.layer-back::after { left: 930px; transform: scaleX(1.18); }
.layer-front { top: auto; height: 22%; background: linear-gradient(0deg, rgba(75,91,73,.14), transparent); }
.entity-layer { pointer-events: auto; }
.entity { position: absolute; width: 180px; height: 220px; border: 0; padding: 0; background: transparent;
  transform: translate(-50%, 0); transform-origin: 50% 100%; cursor: pointer; }
.entity-visual { position: absolute; inset: 0; transform: scale(var(--cluster-scale, 1)) rotate(var(--cluster-lean, 0deg));
  transform-origin: 50% 100%; }
.sprite { position: absolute; left: 50%; bottom: -78px; width: 512px; height: 512px; object-fit: contain;
  transform: translateX(calc(-50% + var(--asset-x, 0px))) scale(var(--asset-scale, .36)); transform-origin: 50% 100%; }
.tree-sprite { --asset-scale: .38; z-index: 2; }
.rock-sprite { --asset-scale: .27; --asset-x: -42px; z-index: 3; }
.bush-sprite { --asset-scale: .28; --asset-x: 48px; z-index: 4; }
.accent-sprite { --asset-scale: .24; --asset-x: 26px; z-index: 5; }
.tree-shadow { position: absolute; z-index: 1; left: 50%; bottom: 20px; width: 84px; height: 22px;
  transform: translateX(-50%); border-radius: 50%; background: rgba(43,52,43,.32); filter: blur(7px); }
.state-effect { position: absolute; z-index: 6; inset: 14px; border-radius: 50%; pointer-events: none; }
.icon-mount { position: absolute; z-index: 8; left: 50%; top: 56px; display: grid; place-items: center;
  width: 40px; height: 40px; transform: translateX(-50%); border-radius: 13px; background: rgba(251,250,247,.88);
  color: var(--ink); box-shadow: 0 8px 24px rgba(34,39,34,.16); }
.icon-mount svg { width: 22px; height: 22px; fill: none; stroke: currentColor; stroke-width: 1.8; }
.entity-title { position: absolute; z-index: 9; left: 50%; bottom: -4px; max-width: 190px; transform: translateX(-50%);
  overflow: hidden; white-space: nowrap; text-overflow: ellipsis; opacity: 0; padding: 8px 11px; border-radius: 12px;
  background: rgba(251,250,247,.88); color: var(--ink); font-size: 12px; }
.now-marker { position: absolute; z-index: 20; left: 965px; top: 148px; bottom: 96px; border-left: 1px solid rgba(71,108,155,.34); }
.now-marker span { position: absolute; top: 0; left: 8px; color: rgba(71,108,155,.72); font-size: 10px; }
.mode-switch { position: absolute; z-index: 60; top: 92px; left: 50%; transform: translateX(-50%);
  display: flex; padding: 3px; border-radius: 15px; background: rgba(251,250,247,.74); backdrop-filter: blur(18px); }
.mode-switch button { border: 0; border-radius: 12px; padding: 0 12px; background: transparent; color: var(--muted); }
.mode-switch button[aria-pressed="true"] { background: rgba(255,255,255,.82); color: var(--ink); }
.return-now { position: absolute; z-index: 60; right: 18px; bottom: 92px; border: 0; border-radius: 15px;
  padding: 0 14px; background: rgba(251,250,247,.82); color: var(--ink); backdrop-filter: blur(18px); }
.demo-controls { position: absolute; z-index: 60; inset: auto 18px 18px; display: flex; align-items: center;
  justify-content: space-between; gap: 12px; }
.demo-controls button { border: 0; border-radius: 15px; padding: 0 14px; background: rgba(29,33,31,.88); color: white; }
.demo-controls p { margin: 0; color: rgba(29,33,31,.58); font-size: 11px; }
button:focus-visible, .world-scroll:focus-visible, .entity:focus-visible { outline: 3px solid rgba(71,108,155,.48); outline-offset: 3px; }
```

- [ ] **Step 5: Implement initial rendering and mode switching**

`world-app.js` must create one `.entity` button per generated cluster, append local image layers, set `data-kind` and `data-state`, and keep the scene model unchanged when switching modes. Create the complete initial file with this implementation:

```js
const core = window.EurekaWorldCore;
const todayKey = core.localDateKey(new Date());
let state = core.createInitialState(todayKey, core.generateScene(todayKey, core.DEMO_ENTITIES));

function dispatch(action) {
  state = core.reduceDemoState(state, action);
  render();
}

document.querySelector('#mode-original').addEventListener('click', () => dispatch({ type: 'SET_MODE', mode: 'original' }));
document.querySelector('#mode-eureka').addEventListener('click', () => dispatch({ type: 'SET_MODE', mode: 'eureka' }));

function render() {
  document.querySelector('#world-strip').dataset.mode = state.mode;
  document.querySelector('#mode-original').setAttribute('aria-pressed', String(state.mode === 'original'));
  document.querySelector('#mode-eureka').setAttribute('aria-pressed', String(state.mode === 'eureka'));
  document.querySelector('#day-label').textContent = state.dayKey;
  renderEntities(state.scene);
  renderPopover();
}

function iconMarkup(kind) {
  const paths = {
    rhythm: '<path d="M3 12h4l2.2-5 4.1 10 2.2-5H21"/>',
    todo: '<rect x="4" y="4" width="16" height="16" rx="3"/><path d="m8 12 2.4 2.4L16.5 8"/>',
    running: '<circle cx="13" cy="5" r="2"/><path d="m10 21 2-6-3-3 3-4 3 3 4 1M7 21l3-5m4-1 3 6"/>',
    report: '<rect x="5" y="3" width="14" height="18" rx="3"/><path d="M8 8h8M8 12h8M8 16h5"/>',
  };
  return `<svg viewBox="0 0 24 24" aria-hidden="true">${paths[kind] || paths.report}</svg>`;
}

function createSprite(filename, className) {
  if (!filename) return null;
  const image = document.createElement('img');
  image.className = `sprite ${className}`;
  image.src = `./assets/kenney/${filename}`;
  image.alt = '';
  image.draggable = false;
  return image;
}

function renderEntities(scene) {
  const layer = document.querySelector('#entity-layer');
  layer.replaceChildren();
  for (const entity of scene) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'entity';
    button.dataset.entityId = entity.id;
    button.dataset.kind = entity.kind;
    button.dataset.state = entity.state;
    button.setAttribute('aria-label', `${entity.title}，${entity.actionLabel}`);
    button.style.left = `${entity.worldX + entity.offsetX}px`;
    button.style.bottom = `${116 + entity.depthBand * 34 + entity.offsetY}px`;
    button.style.zIndex = String(10 + entity.depthBand);
    button.style.setProperty('--cluster-scale', String(entity.scale));
    button.style.setProperty('--cluster-lean', `${entity.lean}deg`);

    const visual = document.createElement('span');
    visual.className = 'entity-visual';
    visual.innerHTML = '<span class="tree-shadow" aria-hidden="true"></span>';
    for (const [asset, className] of [[entity.treeAsset, 'tree-sprite'],
      [entity.rockAsset, 'rock-sprite'], [entity.bushAsset, 'bush-sprite'],
      [entity.accentAsset, 'accent-sprite']]) {
      const image = createSprite(asset, className);
      if (image) visual.append(image);
    }
    const effect = document.createElement('span');
    effect.className = 'state-effect';
    effect.setAttribute('aria-hidden', 'true');
    visual.append(effect);

    const icon = document.createElement('span');
    icon.className = 'icon-mount';
    icon.innerHTML = iconMarkup(entity.kind);
    const title = document.createElement('span');
    title.className = 'entity-title';
    title.textContent = entity.title;
    button.append(visual, icon, title);
    layer.append(button);
  }
}

function renderPopover() {
  document.querySelector('#popover-root').replaceChildren();
}

render();
```

- [ ] **Step 6: Run the document test and full Node suite**

Run:

```bash
node --test spec/design/kenney-daily-world-demo/tests/*.test.cjs
```

Expected: all current tests PASS.

- [ ] **Step 7: Commit the portrait scene shell**

```bash
git add spec/design/kenney-daily-world-demo/index.html \
  spec/design/kenney-daily-world-demo/styles.css \
  spec/design/kenney-daily-world-demo/world-app.js \
  spec/design/kenney-daily-world-demo/tests/document-contract.test.cjs
git commit -m "feat(theme-v2): render Kenney daily world demo"
```

---

### Task 4: Add Horizontal Gestures, Focus, Day Regeneration, and Action Popovers

**Files:**
- Modify: `spec/design/kenney-daily-world-demo/world-app.js`
- Modify: `spec/design/kenney-daily-world-demo/styles.css`
- Modify: `spec/design/kenney-daily-world-demo/tests/world-core.test.cjs`

**Interfaces:**
- Consumes: `classifyGesture()` and `reduceDemoState()` from `world-core.js`.
- Produces: pointer-safe drag scrolling, keyboard navigation, focused entity labels, a single popover, “换一天”, and “回到现在”.

- [ ] **Step 1: Extend reducer tests for focus, mode, and new-day reset**

```js
test('new day resets focus and regenerates the scene', () => {
  const scene = core.generateScene('2026-08-09', core.DEMO_ENTITIES);
  const focused = core.reduceDemoState(core.createInitialState('2026-08-09', scene),
    { type: 'FOCUS', id: 'running' });
  const next = core.reduceDemoState(focused, { type: 'SET_DAY', dayKey: '2026-08-10' });
  assert.equal(next.focusedId, null);
  assert.equal(next.dayKey, '2026-08-10');
  assert.notDeepEqual(next.scene, scene);
});

test('opening one popover replaces the previous focused action', () => {
  const state = core.createInitialState('2026-08-09',
    core.generateScene('2026-08-09', core.DEMO_ENTITIES));
  const first = core.reduceDemoState(state, { type: 'OPEN_POPOVER', id: 'rhythm' });
  const second = core.reduceDemoState(first, { type: 'OPEN_POPOVER', id: 'todo-overdue' });
  assert.equal(second.popoverId, 'todo-overdue');
  assert.equal(second.focusedId, 'todo-overdue');
});
```

- [ ] **Step 2: Run the reducer tests and confirm the expected status**

Run:

```bash
node --test spec/design/kenney-daily-world-demo/tests/world-core.test.cjs
```

Expected: the tests PASS with the reducer created in Task 2. This is a contract lock before DOM wiring.

- [ ] **Step 3: Implement pointer-safe horizontal drag**

Add one pointer session to `world-app.js`:

```js
const worldScroll = document.querySelector('#world-scroll');
let pointerSession = null;

worldScroll.addEventListener('pointerdown', (event) => {
  pointerSession = { id: event.pointerId, startX: event.clientX, startY: event.clientY,
    startScrollLeft: worldScroll.scrollLeft, classification: 'tap' };
});

worldScroll.addEventListener('pointermove', (event) => {
  if (!pointerSession || pointerSession.id !== event.pointerId) return;
  const deltaX = event.clientX - pointerSession.startX;
  const deltaY = event.clientY - pointerSession.startY;
  pointerSession.classification = core.classifyGesture(deltaX, deltaY);
  if (pointerSession.classification === 'horizontal-drag') {
    worldScroll.setPointerCapture(event.pointerId);
    worldScroll.scrollLeft = pointerSession.startScrollLeft - deltaX;
  }
});

worldScroll.addEventListener('pointerup', (event) => {
  if (!pointerSession || pointerSession.id !== event.pointerId) return;
  worldScroll.dataset.lastGesture = pointerSession.classification;
  pointerSession = null;
});
```

Entity click handlers must ignore a click when `worldScroll.dataset.lastGesture === 'horizontal-drag'`, then clear the flag.

- [ ] **Step 4: Implement keyboard, focus, popover, day, and recenter behavior**

Add these exact behaviors to `world-app.js`:

```js
const NOW_SCROLL_LEFT = 770;
function reducedMotion() {
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}
document.querySelector('#return-now').addEventListener('click', () => {
  worldScroll.scrollTo({ left: NOW_SCROLL_LEFT, behavior: reducedMotion() ? 'auto' : 'smooth' });
});
worldScroll.addEventListener('keydown', (event) => {
  if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
  event.preventDefault();
  worldScroll.scrollBy({ left: event.key === 'ArrowLeft' ? -180 : 180,
    behavior: reducedMotion() ? 'auto' : 'smooth' });
});
document.querySelector('#next-day').addEventListener('click', () => {
  const date = new Date(`${state.dayKey}T12:00:00`);
  date.setDate(date.getDate() + 1);
  dispatch({ type: 'SET_DAY', dayKey: core.localDateKey(date) });
  worldScroll.scrollLeft = NOW_SCROLL_LEFT;
});

let parallaxFrame = 0;
worldScroll.addEventListener('scroll', () => {
  if (parallaxFrame) return;
  parallaxFrame = requestAnimationFrame(() => {
    parallaxFrame = 0;
    document.querySelector('#world-strip').style.setProperty(
      '--parallax-shift', `${-(worldScroll.scrollLeft * 0.035).toFixed(2)}px`,
    );
  });
}, { passive: true });
```

Extend `renderEntities()` so every button reflects focus and owns this exact click behavior:

```js
if (state.focusedId === entity.id) button.classList.add('is-focused');
button.addEventListener('click', () => {
  const gesture = worldScroll.dataset.lastGesture;
  worldScroll.dataset.lastGesture = '';
  if (gesture && gesture !== 'tap') return;
  dispatch({ type: state.focusedId === entity.id ? 'OPEN_POPOVER' : 'FOCUS', id: entity.id });
});
```

Replace the initial `renderPopover()` with:

```js
function renderPopover() {
  const root = document.querySelector('#popover-root');
  root.replaceChildren();
  if (!state.popoverId) return;
  const entity = state.scene.find((item) => item.id === state.popoverId);
  if (!entity) return;
  const popover = document.createElement('section');
  popover.className = 'action-popover';
  popover.setAttribute('aria-label', entity.title);
  const copy = document.createElement('div');
  copy.innerHTML = `<strong>${entity.title}</strong><span>${entity.actionLabel}</span>`;
  const action = document.createElement('button');
  action.type = 'button';
  action.textContent = entity.actionLabel;
  action.addEventListener('click', () => dispatch({ type: 'CLEAR_FOCUS' }));
  const close = document.createElement('button');
  close.type = 'button';
  close.className = 'popover-close';
  close.setAttribute('aria-label', '关闭');
  close.textContent = '×';
  close.addEventListener('click', () => dispatch({ type: 'CLEAR_FOCUS' }));
  popover.append(copy, action, close);
  root.append(popover);
}

worldScroll.addEventListener('click', (event) => {
  if (!event.target.closest('.entity')) dispatch({ type: 'CLEAR_FOCUS' });
});
```

- [ ] **Step 5: Add focused and popover styles**

```css
.entity-visual { position: absolute; inset: 0; transition: transform 220ms ease, filter 220ms ease; }
.entity.is-focused .entity-visual { transform: translateY(-10px) scale(var(--cluster-scale, 1)) rotate(var(--cluster-lean, 0deg));
  filter: brightness(1.04); }
.entity.is-focused .icon-mount { transform: translate(-50%, -7px); }
.entity.is-focused .entity-title { opacity: 1; }
.popover-root { position: absolute; z-index: 90; left: 18px; right: 18px; bottom: 76px; pointer-events: none; }
.action-popover { pointer-events: auto; display: grid; grid-template-columns: 1fr auto 44px; gap: 10px; align-items: center;
  padding: 14px; border-radius: 18px; background: rgba(251,250,247,.94); box-shadow: 0 18px 44px rgba(34,39,34,.16); }
.action-popover strong, .action-popover span { display: block; }
.action-popover span { margin-top: 4px; color: var(--muted); font-size: 11px; }
.action-popover button { min-height: 44px; border: 0; border-radius: 13px; padding: 0 13px; background: var(--ink); color: white; }
.action-popover .popover-close { width: 44px; padding: 0; background: rgba(29,33,31,.08); color: var(--ink); }
```

- [ ] **Step 6: Run the Node suite**

Run:

```bash
node --test spec/design/kenney-daily-world-demo/tests/*.test.cjs
```

Expected: all tests PASS.

- [ ] **Step 7: Commit interactions**

```bash
git add spec/design/kenney-daily-world-demo/world-app.js \
  spec/design/kenney-daily-world-demo/styles.css \
  spec/design/kenney-daily-world-demo/tests/world-core.test.cjs
git commit -m "feat(theme-v2): add daily world demo interactions"
```

---

### Task 5: Add Eureka Transformation, Lifecycle States, Fallbacks, and Reduced Motion

**Files:**
- Modify: `spec/design/kenney-daily-world-demo/styles.css`
- Modify: `spec/design/kenney-daily-world-demo/world-app.js`
- Create: `spec/design/kenney-daily-world-demo/tests/styles-contract.test.cjs`

**Interfaces:**
- Consumes: `data-mode`, `data-state`, `data-kind`, and `reportFailed` from the renderer.
- Produces: visually distinct Original/Eureka modes and signal, overdue, generating, completed, and failed states that do not depend on color alone.

- [ ] **Step 1: Write the failing CSS state contract test**

```js
// tests/styles-contract.test.cjs
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const css = fs.readFileSync(path.resolve(__dirname, '..', 'styles.css'), 'utf8');

test('styles define both presentation modes and every lifecycle state', () => {
  for (const selector of ['[data-mode="original"]', '[data-mode="eureka"]',
    '[data-state="signal"]', '[data-state="overdue"]', '[data-state="generating"]',
    '[data-state="completed"]', '[data-state="failed"]']) {
    assert.ok(css.includes(selector), selector);
  }
});

test('styles include reduced motion and image fallback treatment', () => {
  assert.match(css, /prefers-reduced-motion:\s*reduce/);
  assert.match(css, /\.image-fallback/);
});
```

- [ ] **Step 2: Run the style contract and verify it fails**

Run:

```bash
node --test spec/design/kenney-daily-world-demo/tests/styles-contract.test.cjs
```

Expected: FAIL because lifecycle selectors and reduced-motion rules are absent.

- [ ] **Step 3: Add comparison and lifecycle styles**

Add explicit selectors with structural differences:

```css
[data-mode="original"] .sprite { filter: none; }
[data-mode="original"] .atmosphere, [data-mode="original"] .state-effect { opacity: 0; }
[data-mode="eureka"] .sprite { filter: saturate(.68) hue-rotate(-8deg) brightness(1.04) contrast(.92); }
[data-mode="eureka"] .tree-shadow { opacity: .3; filter: blur(9px); }
[data-mode="eureka"] .layer-back { opacity: .78; transform: translateX(var(--parallax-shift, 0px)); }
[data-state="signal"] .tree-sprite { --asset-scale: .25; }
[data-state="signal"] .bush-sprite { --asset-scale: .18; }
[data-state="signal"] .accent-sprite, [data-state="signal"] .rock-sprite { --asset-scale: .16; }
[data-state="signal"] .state-effect { border: 1px solid rgba(71,108,155,.38); animation: signalPulse 2.8s ease-out infinite; }
[data-state="overdue"] .state-effect::after { content: ""; position: absolute; inset: auto 42px 28px;
  height: 4px; border-radius: 99px; background: var(--danger); animation: overdueMark 2.4s ease-in-out infinite; }
[data-state="generating"] .tree-sprite { clip-path: inset(var(--growth-clip, 26%) 0 0); animation: growTree 4.8s ease-in-out infinite; }
[data-state="generating"] .state-effect::after { content: ""; position: absolute; inset: 25px 48px;
  background: linear-gradient(180deg, transparent, rgba(255,255,255,.54), transparent); animation: scanLight 2.2s linear infinite; }
[data-state="completed"] .state-effect::after { content: ""; position: absolute; width: 9px; height: 9px;
  right: 48px; top: 58px; border-radius: 50%; background: #f5e7a6; box-shadow: 0 0 18px rgba(245,231,166,.8); }
[data-state="failed"] .entity-visual { filter: saturate(.44) brightness(.9); }
[data-state="failed"] .state-effect::after { content: "!"; position: absolute; right: 48px; top: 58px;
  display: grid; place-items: center; width: 22px; height: 22px; border-radius: 8px; background: var(--danger); color: white; font-weight: 700; }
.image-fallback { position: absolute; left: 50%; bottom: 36px; width: 74px; height: 108px;
  transform: translateX(-50%); border-radius: 52% 48% 44% 56%; background: rgba(97,125,98,.48); }
.phone.is-loading::after { content: "正在生成今日世界"; position: absolute; z-index: 100; inset: 0; display: grid;
  place-items: center; background: var(--paper); color: var(--muted); font-size: 12px; letter-spacing: .08em; }
.is-paused * { animation-play-state: paused !important; }
@keyframes signalPulse { 0% { transform: scale(.82); opacity: .7; } 100% { transform: scale(1.18); opacity: 0; } }
@keyframes overdueMark { 0%,100% { transform: scaleX(.72); } 50% { transform: scaleX(1); } }
@keyframes growTree { 0%,12% { clip-path: inset(40% 0 0); } 52%,100% { clip-path: inset(0); } }
@keyframes scanLight { from { transform: translateY(-70px); } to { transform: translateY(130px); } }
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after { scroll-behavior: auto !important; animation-duration: .001ms !important;
    animation-iteration-count: 1 !important; transition-duration: .001ms !important; }
  .layer-back { transform: none !important; }
}
```

- [ ] **Step 4: Implement failed-state toggle, preload, and per-image fallback**

In `world-app.js`:

```js
document.querySelector('#report-state').addEventListener('click', () => {
  dispatch({ type: 'TOGGLE_REPORT_FAILURE' });
});

function effectiveState(entity) {
  return entity.id === 'report-generating' && state.reportFailed ? 'failed' : entity.state;
}

function attachImageFallback(image, role) {
  image.addEventListener('error', () => {
    image.hidden = true;
    if (role === 'tree') {
      const fallback = document.createElement('span');
      fallback.className = 'image-fallback';
      image.parentElement.append(fallback);
    }
  }, { once: true });
}

function preloadScene(scene) {
  const names = new Set();
  for (const item of scene) {
    for (const name of [item.treeAsset, item.bushAsset, item.accentAsset, item.rockAsset]) {
      if (name) names.add(name);
    }
  }
  return Promise.allSettled([...names].map((name) => new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = resolve;
    image.onerror = reject;
    image.src = `./assets/kenney/${name}`;
  })));
}

const phone = document.querySelector('.phone');
async function dispatch(action) {
  const nextState = core.reduceDemoState(state, action);
  if (action.type === 'SET_DAY') {
    phone.classList.add('is-loading');
    await preloadScene(nextState.scene);
  }
  state = nextState;
  render();
  phone.classList.remove('is-loading');
}

phone.classList.add('is-loading');
preloadScene(state.scene).finally(() => {
  render();
  phone.classList.remove('is-loading');
  worldScroll.scrollLeft = NOW_SCROLL_LEFT;
});

document.addEventListener('visibilitychange', () => {
  phone.classList.toggle('is-paused', document.hidden);
});
```

Replace Task 3’s immediate `render()` call and synchronous `dispatch()` definition with the asynchronous versions above. In `renderEntities()`, set `button.dataset.state = effectiveState(entity)` and call `attachImageFallback(image, className === 'tree-sprite' ? 'tree' : 'decoration')` for every created image. In `render()`, set the state-demo label to `恢复报告生成状态` when `state.reportFailed` is true and `演示报告失败状态` otherwise.

- [ ] **Step 5: Run the complete Node suite**

Run:

```bash
node --test spec/design/kenney-daily-world-demo/tests/*.test.cjs
```

Expected: 13 tests PASS.

- [ ] **Step 6: Commit visual transformations and states**

```bash
git add spec/design/kenney-daily-world-demo/styles.css \
  spec/design/kenney-daily-world-demo/world-app.js \
  spec/design/kenney-daily-world-demo/tests/styles-contract.test.cjs
git commit -m "feat(theme-v2): add Eureka world states and styling"
```

---

### Task 6: Document, Browser-Test, and Hand Off the Demo

**Files:**
- Create: `spec/design/kenney-daily-world-demo/README.md`
- Modify only if verification finds defects: `index.html`, `styles.css`, `world-core.js`, `world-app.js`, or tests in the demo folder.

**Interfaces:**
- Consumes: the complete local prototype.
- Produces: documented usage and browser evidence at 390 × 844 and 360 × 800.

- [ ] **Step 1: Write the README**

````markdown
# Kenney Daily World Demo

Standalone visual prototype for the Theme V2 portrait daily world.

## Open

Open `index.html` directly, or run:

```bash
python3 -m http.server 4173 --directory spec/design/kenney-daily-world-demo
```

Then visit `http://127.0.0.1:4173/`.

## What to test

- Drag horizontally and use “回到现在”.
- Switch between “原始 Kenney” and “Eureka”.
- Tap each tree once for its title and again for its action.
- Use “换一天” to regenerate the same five semantic objects.
- Toggle the report-generating object into its failed state.

## Asset provenance

The selected sprites come from Kenney Nature Kit 2.1 and retain its CC0 license.
The original license is stored in `third-party/Kenney-Nature-Kit-License.txt`.
Kenney does not endorse this prototype.
````

- [ ] **Step 2: Run automated tests and static checks**

Run:

```bash
node --test spec/design/kenney-daily-world-demo/tests/*.test.cjs
git diff --check -- spec/design/kenney-daily-world-demo
```

Expected: all tests PASS and `git diff --check` prints nothing.

- [ ] **Step 3: Start the local server**

Run:

```bash
python3 -m http.server 4173 --bind 127.0.0.1 --directory spec/design/kenney-daily-world-demo
```

Expected: server listens at `http://127.0.0.1:4173/`.

- [ ] **Step 4: Verify the reference viewport with gstack browse**

Run:

```bash
B="$HOME/.claude/skills/gstack/browse/dist/browse"
$B viewport 390x844 --scale 2
$B goto http://127.0.0.1:4173/
$B screenshot /tmp/kenney-daily-world-390.png --viewport
$B console --errors
$B network
```

Expected: screenshot shows the full portrait phone without vertical overflow; console contains no errors; network contains no failed requests and no remote host.

- [ ] **Step 5: Exercise the core interaction flow**

Run:

```bash
$B snapshot -i
$B click '#mode-original'
$B click '#mode-eureka'
$B click '#next-day'
$B click '#report-state'
$B click '[data-entity-id="report-generating"]'
$B click '[data-entity-id="report-generating"]'
$B snapshot -D
```

Expected: mode changes do not move entities; next day changes sprite combinations; failed report remains in the same position; second entity click opens one action popover.

- [ ] **Step 6: Verify the narrow viewport and reduced-motion contract**

Run:

```bash
$B viewport 360x800 --scale 2
$B reload
$B screenshot /tmp/kenney-daily-world-360.png --viewport
$B js "({scrollWidth:document.documentElement.scrollWidth,clientWidth:document.documentElement.clientWidth,controls:[...document.querySelectorAll('button')].every(b=>b.getBoundingClientRect().height>=44)})"
```

Expected: document `scrollWidth === clientWidth`, every button height is at least 44, and the phone remains portrait with horizontal movement contained inside `#world-scroll`.

- [ ] **Step 7: Inspect verification screenshots**

Open both PNG files with the local image viewer and check:

- no cropped header, mode switch, return control, or bottom control;
- icon mounts stay readable against every tree;
- foreground objects do not block focused titles;
- original/Eureka difference is visible without changing composition;
- five semantic objects remain discoverable across the world.

Fix only demonstrated defects, then rerun Steps 2, 4, 5, and 6.

- [ ] **Step 8: Commit documentation and verified fixes**

```bash
git add spec/design/kenney-daily-world-demo/README.md \
  spec/design/kenney-daily-world-demo/index.html \
  spec/design/kenney-daily-world-demo/styles.css \
  spec/design/kenney-daily-world-demo/world-core.js \
  spec/design/kenney-daily-world-demo/world-app.js \
  spec/design/kenney-daily-world-demo/tests
git commit -m "docs(theme-v2): finish Kenney daily world demo"
```

The screenshots remain temporary verification evidence and are not committed.
