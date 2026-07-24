# UReka Figma Design Source of Truth

**Date:** 2026-07-24

**Status:** Approved design

**Owner model:** Single maintainer

**Figma location:** `KD's team / Drafts`

**Figma file name:** `UReka Design System · Source of Truth`

## 1. Context

UReka currently has strong product and design documentation, but no editable visual source of truth. UI decisions are distributed across Flutter code, screenshots, HTML prototypes, handoff documents, and page-specific experiments.

The current Flutter implementation contains approximately:

- 26 page entry files
- 224 hardcoded color declarations
- 512 independent font-size declarations
- 232 hardcoded circular radii
- 423 direct `EdgeInsets` usages

The problem is therefore not a lack of design ideas. The problem is the absence of one reusable, auditable system connecting foundations, components, high-fidelity screens, and implementation.

## 2. Decision

Build a new Figma-first visual source of truth using the approved **Quiet Warm Minimalism** direction.

The current app and screenshots are reference material, not the visual authority. The new Figma system may preserve working interaction and information architecture while correcting inconsistency in hierarchy, surface treatment, spacing, typography, component structure, and state expression.

Figma owns visual and interaction truth. Flutter remains the implementation and business-logic truth.

## 3. Goals

1. Provide one editable source for the visual language and every user-facing page.
2. Make future pages composable from reusable variables, components, and templates.
3. Make design drift visible without introducing a heavyweight team process.
4. Preserve a clear relationship between Figma components and Flutter implementation files.
5. Support both light and dark appearance from one semantic variable system.
6. Cover canonical screens and layout-changing states at high fidelity.

## 4. Non-goals

- Reproduce current screenshots pixel for pixel.
- Add approval workflows, design branches, CI gates, or formal release management.
- Generate every possible state combination for every page.
- Turn debug and engineering tools into consumer-product surfaces.
- Move business rules, API contracts, or localization source text into Figma.

## 5. Source-of-truth Rule

The maintenance rule is deliberately small:

> Any change the user can see must update Figma and the app in the same body of work.

This means:

- Visual, layout, component, interaction, and user-visible state changes update Figma.
- Token or shared-component changes start in Figma, then update Flutter.
- Urgent visual fixes may land in code first, but Figma is backfilled in the same task.
- Pure business logic, API, performance, and internal refactors do not update Figma unless they alter visible behavior.
- Figma carries representative copy and layout. Complete localized strings remain in the app's i18n source.

No `Draft → Review → Ready` workflow, component version ledger, design manifest, or CI design gate is required for the single-maintainer model.

## 6. Figma File Structure

The source file contains four pages.

### `00 · Foundations`

Contains the visual primitives and semantic decisions:

- Color primitives
- Semantic light/dark color modes
- Typography scale and text styles
- Spacing scale
- Radius scale
- Border and elevation rules
- Opacity
- Motion duration and easing
- Domain identity colors
- Accessibility and contrast examples

Variables use two levels:

1. **Primitive values**, such as raw palette values and numeric scales.
2. **Semantic aliases**, such as `surface/default`, `text/secondary`, and `action/primary`.

Screens and components consume semantic variables, not raw primitives.

### `01 · Components`

Contains reusable components, variants, and important interaction states.

Each component documents only:

- Intended use
- Variants and sizes
- Important states
- Corresponding Flutter implementation file or intended implementation location

Components are organized into:

1. **Primitives**
   - Button
   - Icon Button
   - Input
   - Text Area
   - Chip
   - Badge
   - Domain Dot
   - Divider
   - Progress
   - Skeleton
   - Avatar

2. **Containers**
   - Quiet Surface
   - List Tile
   - Section
   - Card Frame
   - Bottom Sheet
   - Dialog
   - Toast
   - Menu
   - Page Header

3. **Product components**
   - Asset Tile
   - Timeline Item
   - Skill Card
   - Event Card
   - Report Card
   - Offer Card
   - Device Card
   - Reka Bubble
   - Chat Composer
   - Capture Status

4. **Patterns and templates**
   - Global Shell
   - Main navigation
   - List page
   - Detail page
   - Edit/form page
   - Conversation page
   - Report page
   - Loading, empty, error, and offline layouts
   - Internal Tools Template

### `02 · Hi-Fi Screens`

Contains the current canonical high-fidelity screen for every user-facing page.

Each screen includes:

- A canonical `390 × 844` mobile frame
- Constraints that remain valid at `360px` width
- Light and dark appearance
- Key states that materially change layout or decisions
- Interaction notes where behavior is not visually obvious
- The corresponding Flutter route/page file

Common component states are documented on the component page. A screen only repeats states that meaningfully change that page.

### `99 · Archive`

Contains replaced concepts and superseded screens. Archived work is clearly separated from current design truth and is not used for implementation.

## 7. Visual Direction

The approved direction is **Quiet Warm Minimalism**:

- Warm monochrome backgrounds
- Quiet paper-like surfaces
- Thin borders and restrained shadows
- Stable typographic hierarchy
- Domain color used as a small identity signal, not a large card fill
- Reka as the primary emotional layer
- Motion used to explain state change, not decorate static content

The design has two coordinated layers:

1. **Data layer:** clear, restrained, trustworthy, content-first.
2. **Reka expression layer:** warm, responsive, alive, but never dominant over the user's information.

## 8. High-fidelity Screen Inventory

### Gate and initialization

- Login — `mobile/lib/pages/login_page.dart`
- Device pairing — `mobile/lib/pages/device_pairing_page.dart`
- Pet initialization — `mobile/lib/pages/pet_spawn_page.dart`

### Main product

- Today — `mobile/lib/pages/today_page.dart`
- Calendar — `mobile/lib/pages/calendar_page.dart`
- Library — `mobile/lib/pages/library_page.dart`

### Capture and AI

- Chat — `mobile/lib/pages/chat_page.dart`
- Day flash view — `mobile/lib/pages/day_flash_view.dart`
- Session detail — `mobile/lib/pages/session_detail_page.dart`
- Morning briefing — `mobile/lib/pages/morning_briefing_page.dart`
- Notifications and offers — `mobile/lib/pages/notifications_page.dart`

### Assets and skills

- Create asset — `mobile/lib/pages/create_asset.dart`
- Category detail — `mobile/lib/pages/category_detail_page.dart`
- Entity list — `mobile/lib/pages/entity_list_page.dart`
- Add skill — `mobile/lib/pages/add_skill.dart`
- Skill configuration — `mobile/lib/pages/skill_config_page.dart`
- Skill management — `mobile/lib/pages/skill_manage_page.dart`
- Event attendees — `mobile/lib/pages/event_attendees.dart`

### Reports

- Report list — `mobile/lib/pages/report_list_page.dart`
- Report viewer — `mobile/lib/pages/report_viewer_page.dart`

### Reka

- Pet — `mobile/lib/pages/pet_page.dart`
- Floating Reka and expression surfaces — `mobile/lib/pet/`

### Devices and integrations

- My device — `mobile/lib/pages/my_device_page.dart`
- My ring — `mobile/lib/pages/my_ring_page.dart`
- Connected apps — `mobile/lib/pages/connected_apps_page.dart`

### Internal tools

- Ring debug — `mobile/lib/pages/ring_debug_page.dart`

Internal tools use a separate utility template. They are represented for completeness but do not consume or define the consumer-product visual language.

## 9. State Coverage

The system-level state set is:

- Default
- Loading
- Empty
- Error
- Offline
- Disabled
- Processing
- Success
- Recording
- ASR/transcribing
- Syncing
- Generating

Each component contains the states intrinsic to that component. Each high-fidelity page contains only the states that alter its content hierarchy, available actions, or layout.

Error, offline, and empty states must always answer:

1. What happened?
2. Is the user's data safe?
3. What can the user do next?

## 10. Accessibility and Interaction Rules

- Body text and essential controls meet WCAG AA contrast.
- Touch targets are at least `44 × 44`.
- Information is not communicated by color alone.
- Text layouts support Chinese and English expansion.
- Light and dark modes preserve semantic hierarchy.
- Reduced-motion behavior is defined for non-essential animation.
- Sheets, dialogs, navigation, loading, and focus behavior remain consistent across pages.

## 11. Delivery Order

### Phase 1 — Foundation proof

1. Create the Figma source file.
2. Build foundations and light/dark semantic modes.
3. Build primitive and container components.
4. Build Global Shell.
5. Produce Today, Calendar, and Library high-fidelity screens.
6. Validate the system at `390px` and `360px`.

### Phase 2 — Product system

1. Build product components.
2. Build Capture, Asset, Skill, Chat, and Session screens.
3. Add shared loading, empty, error, offline, and processing patterns.

### Phase 3 — Remaining surfaces

1. Build Reka, Report, Device, and Integration screens.
2. Apply the Internal Tools Template to debug surfaces.
3. Move superseded directions to Archive.

## 12. Acceptance Criteria

Phase 1 is ready for its first implementation pass when:

- The Figma file exists in `KD's team / Drafts`.
- The four-page file structure is present.
- Foundations use semantic light/dark variables.
- The initial components use variables and Auto Layout.
- Today, Calendar, and Library are complete at high fidelity.
- Those three screens are built from component instances rather than detached drawings.
- Layout remains usable at `360px`.
- Component and page notes identify the corresponding Flutter files.
- Loading, empty, error, and offline patterns are represented.
- The visual direction is consistent with Quiet Warm Minimalism.

The complete design-system task is finished when every user-facing screen in
the inventory has one current canonical high-fidelity design, its
layout-changing states are covered, and the remaining product components are
represented as reusable instances. Internal tools must use the documented
utility template, and replaced concepts must be moved to Archive.

## 13. Key Decisions

- Figma-first redesign, not screenshot reconstruction.
- Figma is the visual truth; Flutter is the implementation truth.
- Single-maintainer workflow with no formal approval machinery.
- `390 × 844` canonical frame with `360px` minimum-width constraints.
- One current high-fidelity design per user-facing page.
- Common states live with components; page-specific states live with pages.
- Debug tools are documented but visually isolated.
- Old designs move to Archive instead of remaining beside current truth.
