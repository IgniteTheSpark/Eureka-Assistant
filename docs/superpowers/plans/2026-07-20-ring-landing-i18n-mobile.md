# Eureka Ring Landing i18n and Mobile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a bilingual Eureka Ring landing page that defaults to English, can switch to Chinese without reloading the 3D ring, uses the supplied Eureka logo and WeChat QR code, and works cleanly on mobile.

**Architecture:** A lightweight locale provider owns `en | zh-CN`, persists the manual choice in a cookie, and exposes a typed content dictionary to existing landing components. The 3D `LivingRingStage` stays mounted while text changes. Responsive CSS and viewport-aware journey frames adapt the existing single-canvas ring story instead of creating a second mobile implementation.

**Tech Stack:** React 18, TypeScript, Vite, Vitest, Testing Library, GSAP/ScrollTrigger, Three.js/R3F, CSS media queries.

## Global Constraints

- Phase 1 defaults to English and supports manual switching to Chinese; IP detection is deferred.
- Product name remains `Eureka Ring` in both languages.
- Landing and Flash/Vibe demo routes remain isolated; only `/` is in scope.
- One `LivingRingStage`/Canvas instance must survive locale changes.
- Supplied QR pixels must not be blurred, transformed, or lossily recompressed.
- Existing uncommitted CTA no-wrap work must be preserved.
- Key QA viewports: 375×812, 768×1024, 1440×900.

---

### Task 1: Typed locale state and persistence

**Files:**
- Create: `ring-demo/src/i18n/locale.ts`
- Create: `ring-demo/src/i18n/LocaleProvider.tsx`
- Test: `ring-demo/src/i18n/LocaleProvider.test.tsx`
- Modify: `ring-demo/src/main.tsx`

**Interfaces:**
- Produces: `type Locale = "en" | "zh-CN"`
- Produces: `readStoredLocale(): Locale`
- Produces: `writeStoredLocale(locale: Locale): void`
- Produces: `useLocale(): { locale: Locale; setLocale(locale: Locale): void }`

- [ ] **Step 1: Write failing locale tests**

Test that no cookie resolves to `en`, a `eureka_locale=zh-CN` cookie resolves to Chinese, toggling updates `<html lang>`, and rerendering children does not unmount a stable sentinel component.

- [ ] **Step 2: Run the focused test and confirm failure**

Run: `npm test -- --run src/i18n/LocaleProvider.test.tsx`  
Expected: FAIL because locale modules do not exist.

- [ ] **Step 3: Implement the locale boundary**

Use the cookie name `eureka_locale`, `Max-Age=31536000`, `Path=/`, and `SameSite=Lax`. Default to `en`; do not read `navigator.language` in this phase. Wrap `<App />` with `<LocaleProvider>` inside `main.tsx`.

- [ ] **Step 4: Run the focused test**

Run: `npm test -- --run src/i18n/LocaleProvider.test.tsx`  
Expected: PASS.

### Task 2: Typed bilingual content and landing migration

**Files:**
- Modify: `ring-demo/src/components/landing/landing-content.ts`
- Modify: `ring-demo/src/components/landing/landing-content.test.ts`
- Modify: `ring-demo/src/pages/HomePage.tsx`
- Modify: `ring-demo/src/components/landing/LandingStory.tsx`
- Modify: `ring-demo/src/components/landing/SystemFinale.tsx`
- Modify: `ring-demo/src/components/landing/CommunityCta.tsx`
- Modify: `ring-demo/src/pages/HomePage.test.tsx`
- Modify: `ring-demo/src/components/landing/LandingStory.test.tsx`
- Modify: `ring-demo/src/components/landing/SystemFinale.test.tsx`

**Interfaces:**
- Consumes: `useLocale()` from Task 1.
- Produces: `getLandingContent(locale: Locale): LandingContent`.
- Produces: English and Chinese values for every visible string, `alt`, and ARIA label.

- [ ] **Step 1: Convert content tests to validate both locales**

Assert `getLandingContent("en").hero.title === "Intelligence · Within Reach"`, `getLandingContent("zh-CN").hero.title === "智能 · 触手可及"`, both locales contain four Flash examples, three senses, and five system nodes, and all nodes have localized labels/details/signals.

- [ ] **Step 2: Run focused landing tests and confirm failure**

Run: `npm test -- --run src/components/landing/landing-content.test.ts src/pages/HomePage.test.tsx src/components/landing/LandingStory.test.tsx src/components/landing/SystemFinale.test.tsx`  
Expected: FAIL against the current single Chinese constant.

- [ ] **Step 3: Add the full English dictionary and migrate components**

Use natural English copy rather than literal word-for-word translations. Keep app names and `Eureka Ring`, `Flash`, and `Vibe` unchanged. Replace direct `LANDING_CONTENT` imports in render components with `useLandingContent()` or `getLandingContent(locale)` while keeping constant arrays such as logo sources independent from locale.

- [ ] **Step 4: Keep the Canvas stable across a locale switch**

Keep `LivingRingStage` outside any keyed locale subtree. Do not use `key={locale}` on `HomePage`, `main`, `LandingStory`, or `LivingRingStage`. Trigger `ScrollTrigger.refresh()` after localized layout changes without recreating Journey refs.

- [ ] **Step 5: Run focused landing tests**

Run the command from Step 2.  
Expected: PASS.

### Task 3: Brand signature, language switch, metadata, and assets

**Files:**
- Create: `ring-demo/src/components/landing/LanguageSwitch.tsx`
- Test: `ring-demo/src/components/landing/LanguageSwitch.test.tsx`
- Modify: `ring-demo/src/pages/HomePage.tsx`
- Modify: `ring-demo/src/styles.css`
- Modify: `ring-demo/index.html`
- Add: `ring-demo/public/brand/eureka-logo.png`

**Interfaces:**
- Consumes: `useLocale()` from Task 1.
- Produces: accessible `LanguageSwitch` with two real buttons labelled `English` and `中文`.

- [ ] **Step 1: Write the failing switch test**

Render `LanguageSwitch` in `LocaleProvider`; click `中文`; assert the Chinese button has `aria-pressed="true"`, English has `false`, and `<html lang="zh-CN">`.

- [ ] **Step 2: Copy the exact supplied logo asset**

Source: `/var/folders/nr/ylgpdgnj44z_969x516hjd5c0000gn/T/codex-clipboard-235b3e07-d5de-4cfc-9070-8067ae1b89ad.png`  
Destination: `ring-demo/public/brand/eureka-logo.png`

- [ ] **Step 3: Implement the brand signature and switch**

Replace the hero text-only signature with the logo mark, `Eureka Ring`, and localized descriptor. Place `LanguageSwitch` at the hero top-right on desktop and in normal document flow at the top on mobile. Keep the logo small enough that the shuffled H1 remains the focal point.

- [ ] **Step 4: Localize document metadata**

On locale change set `document.title` and the existing description meta tag. Keep `index.html` default language and metadata English so the static fallback matches Phase 1.

- [ ] **Step 5: Run focused tests**

Run: `npm test -- --run src/components/landing/LanguageSwitch.test.tsx src/pages/HomePage.test.tsx`  
Expected: PASS.

### Task 4: Real QR code and bilingual final CTA

**Files:**
- Add: `ring-demo/public/community/eureka-ring-wechat-group.png`
- Modify: `ring-demo/src/components/landing/CommunityCta.tsx`
- Modify: `ring-demo/src/components/landing/LandingStory.test.tsx`
- Modify: `ring-demo/src/styles.css`

**Interfaces:**
- Consumes: localized `community` content.
- Produces: a stable `.community-qr-crop` that visually isolates the QR area without modifying QR pixels.

- [ ] **Step 1: Update the CTA test to require the supplied asset**

Assert the QR image source is `/community/eureka-ring-wechat-group.png`, its alt is localized, and English copy mentions `WeChat` while Chinese copy mentions `微信群`.

- [ ] **Step 2: Copy the exact supplied QR screenshot**

Source: `/var/folders/nr/ylgpdgnj44z_969x516hjd5c0000gn/T/codex-clipboard-d6b2b9cb-fb1e-4a84-9a28-9e12c68ee4bb.png`  
Destination: `ring-demo/public/community/eureka-ring-wechat-group.png`

- [ ] **Step 3: Implement the CTA crop and brand lockup**

Use an overflow-hidden square crop container and an unfiltered `<img>` with `object-fit: cover`/`object-position` tuned to the QR area. Do not apply blur, rotation, perspective, or image compression. Preserve the existing non-breaking `Eureka Ring` title work.

- [ ] **Step 4: Run CTA tests**

Run: `npm test -- --run src/components/landing/LandingStory.test.tsx`  
Expected: PASS.

### Task 5: Mobile layout and single-canvas ring journey

**Files:**
- Modify: `ring-demo/src/styles.css`
- Modify: `ring-demo/src/components/living-ring/landing-journey.ts`
- Modify: `ring-demo/src/components/living-ring/landing-journey.test.ts`
- Modify: `ring-demo/src/components/living-ring/LivingRingStage.tsx`
- Modify: `ring-demo/src/pages/HomePage.tsx`

**Interfaces:**
- Produces: viewport-aware journey mapping using the existing `RingJourneyFrame` ref.
- Produces: one-column mobile layouts below 768px.

- [ ] **Step 1: Add failing mobile journey tests**

Add deterministic tests for the mobile path: the ring remains near the center corridor through the mode thesis, enters each sense chapter in sequence, and ends between CTA copy and QR without position discontinuities larger than the allowed frame delta.

- [ ] **Step 2: Implement mobile anchors and safe rendering limits**

Select mobile frames with `matchMedia("(max-width: 767px)")` or a measured viewport flag. Keep the same Canvas and GLB. Cap mobile DPR, reduce nonessential postprocessing, and preserve the capacitive touch surface material.

- [ ] **Step 3: Implement responsive layout CSS**

At `<768px`, stack all grids, constrain headings with `clamp()`, keep 44px language controls, prevent horizontal overflow, give QR a scannable width, and reserve explicit corridors for the ring. At `768–1023px`, use tablet spacing without shrinking desktop type directly.

- [ ] **Step 4: Run journey and rendering tests**

Run: `npm test -- --run src/components/living-ring/landing-journey.test.ts src/pages/HomePage.test.tsx`  
Expected: PASS.

### Task 6: Full verification and phased-IP documentation

**Files:**
- Modify: `docs/superpowers/specs/2026-07-20-ring-landing-i18n-mobile-design.md`

**Interfaces:** None.

- [ ] **Step 1: Run the full landing test suite**

Run: `npm test -- --run`  
Expected: all tests pass.

- [ ] **Step 2: Run typecheck and production build**

Run: `npm run typecheck && npm run build`  
Expected: both commands exit 0.

- [ ] **Step 3: Inspect responsive screenshots**

Run the app and inspect 375×812, 768×1024, and 1440×900. Confirm no horizontal overflow, no duplicate/deformed ring, readable English/Chinese type, a usable language switch, and a scannable QR.

- [ ] **Step 4: Document Phase 2 IP behavior**

Keep IP middleware explicitly deferred. Record the future priority as manual Cookie → Vercel country → browser language → English, with `CN → zh-CN` and all other countries → `en`.

- [ ] **Step 5: Review the final diff without committing unrelated files**

Run: `git status --short && git diff --check`  
Expected: only intended landing, tests, docs, and supplied assets are present; no whitespace errors.
