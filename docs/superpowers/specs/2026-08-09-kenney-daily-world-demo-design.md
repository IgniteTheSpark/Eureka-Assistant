# Kenney Daily World Demo Design

> Date: 2026-08-09
> Status: Approved concept, awaiting written-spec review
> Scope: A standalone visual prototype for the Theme V2 daily home world

## 1. Objective

Build a standalone, portrait-oriented prototype that answers two design questions:

1. How can the CC0 Kenney Nature Kit be combined into varied daily content objects?
2. How much visual modification is required before those objects feel native to Eureka rather than like an imported game asset pack?

The prototype must use the actual Kenney Nature Kit artwork. It is not a production implementation of the Theme V2 home page and does not connect to live assets, Reka signals, report jobs, or Flutter navigation.

## 2. Chosen Approach

Use the four-direction isometric PNG renders included in the Kenney Nature Kit, with the southeast-facing set as the initial consistent camera direction.

The prototype will compose those PNGs in HTML layers instead of loading GLB models at runtime. This matches the intended first-release pseudo-3D direction, keeps the prototype self-contained, and isolates visual decisions from 3D-engine and mobile-renderer decisions.

The rejected alternatives are:

- Runtime GLB rendering with Three.js. This would better demonstrate camera and lighting control but would shift the evaluation toward true-3D performance and interaction.
- Offline Blender rerendering. This offers the best final material control but requires an asset-production pipeline before the composition concept has been validated.

## 3. Deliverables

Create the following standalone prototype folder:

```text
spec/design/kenney-daily-world-demo/
  index.html
  assets/
    kenney/
      selected isometric PNG files
  third-party/
    Kenney-Nature-Kit-License.txt
  README.md
```

`index.html` must open locally without a build step or remote asset requests. The README will identify the source pack, explain how to run the demo, and distinguish prototype-only transformations from a production asset pipeline.

## 4. Screen and World Structure

The browser page presents a centered portrait phone viewport based on a 390 × 844 logical-pixel screen. The app itself remains portrait-only.

Inside the phone viewport:

- The world is wider than the screen and scrolls horizontally.
- Touch drag, mouse drag, trackpad horizontal scroll, and keyboard arrow keys move through the world.
- A small “return to now” control recenters the current-time position after the user travels away from it.
- The atmospheric background loops visually, while the ground is one continuous 1,800-pixel strip and content objects do not repeat.
- The scene contains exactly five demonstration objects; the failed report reuses the report-generating object through the debug-state control.

The pseudo-3D scene uses four visual depths:

1. distant atmospheric background;
2. back terrain and small vegetation;
3. interactive content clusters;
4. foreground grass, stones, and haze.

Objects lower on the ground plane render above objects farther back. Horizontal movement applies subtle parallax between layers. No perspective camera rotation is included.

## 5. Kenney Composition Grammar

Kenney tree PNGs are complete tree renders, not separable trunk and canopy layers. The prototype therefore generates a content object at the scene-cluster level:

```text
content cluster =
  one primary tree
  + zero or one bush
  + zero to two small accents
  + one ground treatment
  + one semantic icon anchor
  + one lifecycle state treatment
```

The selected library will contain exactly:

- 8 primary tree silhouettes;
- 3 bush silhouettes;
- 3 flower, grass, or mushroom accents;
- 4 small or medium rocks;
- 2 ground-shadow treatments implemented in CSS.

The primary tree is chosen independently of content type. A Todo and a running record may use the same tree silhouette, and two Todos may use different silhouettes. The semantic icon, title, and action communicate content meaning.

Each cluster uses a deterministic seed:

```text
clusterSeed = hash(localDate + entityId)
```

The seed chooses the tree, accessory set, scale, lean, foreground overlap, and small positional offsets. Pressing “换一天” changes the local-date seed. Reopening or refreshing the same day preserves the same composition.

## 6. Eureka Visual Transformation

The prototype contains a persistent comparison control with two modes.

### 6.1 Original Kenney

- Use the source PNG colors and proportions.
- Use a neutral presentation ground.
- Keep only the minimum interaction overlay needed to identify the object.
- Disable Eureka atmospheric treatment and decorative state effects.

### 6.2 Eureka

Apply the following non-destructive browser treatments while retaining the recognizable Kenney geometry:

- reduce saturation and shift foliage toward the current quiet, warm Theme V2 palette;
- soften contrast and use warmer trunks and ground colors;
- add a consistent soft contact shadow under every cluster;
- introduce low-opacity atmospheric haze between depth layers;
- normalize apparent tree height without making all silhouettes identical;
- add restrained highlight and bloom only for active lifecycle states;
- place a consistent, camera-facing semantic icon anchor in front of the lower tree crown;
- use Eureka typography and concise one-line content labels when focused.

The comparison control keeps content positions and random choices unchanged so the effect of the transformation can be judged directly.

The prototype does not permanently edit the source PNG files. It applies CSS filters, opacity, blend layers, shadows, and surrounding composition. A later production pipeline may instead recolor the GLB materials and rerender sprites.

## 7. Demonstration Content and States

The default day includes these representative objects:

| Object | Semantic anchor | Default lifecycle treatment | Tap result |
| --- | --- | --- | --- |
| Rhythm reminder | recording/heartbeat icon | a compact tree at 65% mature scale with a slow pulse | show “记录一次” and “手动记录” actions |
| Overdue Todo | Todo/check icon | mature tree with a restrained warm warning at the root | open a Todo-style action popover |
| Running asset | running/activity icon | stable completed tree | show one-line record title and an “打开记录” action |
| Report generating | report/progress icon | staged vertical growth and moving light through the crown | show generating state; repeated taps do not restart it |
| Report completed | report icon | stable mature tree with one subtle luminous accent | show one-line report title and an “打开报告” action |
| Failed report, debug state | warning/report icon | growth stops, highlight cools, small retry marker appears | offer retry or dismiss |

The failed-report treatment is shown by a state-demo control that switches the report-generating object between generating and failed without adding a permanent sixth object.

State animation is separate from tree selection. Changing an object from generating to completed must preserve its tree identity and position.

## 8. Icon and Content Presentation

Each interactive cluster has three information levels:

1. The icon is always visible and is the primary semantic anchor.
2. The nearest or tapped cluster reveals a one-line title.
3. Tapping again or choosing the visible action opens a small prototype action popover.

The icon is rendered as an independent, camera-facing layer rather than baked into the Kenney sprite. It uses one consistent softly squared mount with sufficient contrast in light and dark scene areas.

The prototype uses local inline SVG symbols and does not depend on emoji or a remote icon font. Every icon also has an accessible text label.

## 9. Interaction Rules

- Horizontal drag moves the world and must not accidentally activate a tree after a meaningful drag distance.
- A short tap focuses a cluster.
- Focusing lifts the cluster slightly, raises its icon, and reveals its one-line title without blocking neighboring objects.
- Tapping empty ground clears focus.
- Only one action popover can be open at a time.
- Repeated taps on “report generating” reveal the same generating state and never create or restart a job.
- “换一天” regenerates cluster composition and resets the viewport to now.
- Switching Original/Eureka mode does not regenerate or reposition clusters.
- Reduced-motion mode removes continuous pulse, parallax, and growth loops while preserving state differences.

All controls and content objects meet a minimum 44 × 44 logical-pixel touch target.

## 10. Data Model

The prototype uses a small local configuration array:

```text
DemoEntity
  id
  kind                 rhythm | todo | running | report
  state                signal | overdue | generating | completed | failed
  title
  actionLabel
  worldX
  depthBand
```

The generated visual properties are derived and must not be stored separately:

```text
GeneratedCluster
  treeAsset
  accessoryAssets[]
  scale
  lean
  offsets
  stateClass
```

This separation demonstrates the proposed product rule: tree form is visual variation, icon is semantics, and animation is lifecycle state.

## 11. Loading and Failure Handling

- All selected images are local and preloaded before the first scene reveal.
- While images load, the scene shows ground and lightweight silhouette placeholders rather than shifting layout.
- If one asset fails, the affected cluster falls back to a CSS silhouette and remains interactive.
- Failure of a decorative bush, flower, or rock does not hide the primary content object.
- The prototype must remain usable from `file://` and from a local static server.

## 12. Performance and Accessibility

- Limit the page to the selected asset subset rather than copying the full Nature Kit.
- Animate only transform and opacity properties where possible.
- Pause continuous animation when the page is hidden.
- Precompute seeded choices once per generated day instead of on every frame.
- Provide visible focus states, keyboard navigation, semantic buttons, and accessible names.
- Respect `prefers-reduced-motion`.
- Prevent vertical page movement from being captured by horizontal drag until horizontal intent is clear.

## 13. License and Provenance

The selected Kenney Nature Kit files remain under CC0. The prototype will copy the pack’s original `License.txt` into `third-party/Kenney-Nature-Kit-License.txt` and identify the source in the README.

The prototype must not use the Kenney logo or imply endorsement. Eureka-owned SVG icons and styling remain visually and structurally separate from the third-party sprite files.

## 14. Verification

The prototype is complete when all of the following pass:

1. It opens locally without a build step and makes no remote asset request.
2. It works in a 390 × 844 portrait viewport without vertical overflow or orientation changes.
3. Mouse, touch-style drag, wheel/trackpad, and keyboard navigation can traverse the horizontal world.
4. Original Kenney and Eureka modes preserve identical cluster identity and position.
5. “换一天” produces a different composition, while refresh within the same selected day is stable.
6. All five default content examples expose a recognizable icon and concise focused title.
7. Generating, completed, failed, overdue, and rhythm-signal states remain distinguishable without relying on color alone.
8. Dragging does not accidentally activate a content object.
9. Missing decorative assets degrade independently without hiding the content object.
10. Reduced-motion mode remains complete and interactive.
11. The Kenney license and source record ship with the selected assets.
12. Automated browser checks show no console errors or failed network requests at the portrait viewport.

## 15. Non-goals

- No Flutter integration or production Theme V2 code changes.
- No live backend, authentication, asset, report, Todo, Rhythm, or Reka API calls.
- No domain-based generation.
- No true 3D camera rotation, physics, terrain generation, or GLB rendering.
- No historical world, weekly island, or persistence beyond the local demo seed.
- No final production decision about Sprite versus GLB rendering.
- No asset-creation pipeline in Blender.

## 16. Success Criterion

After using the prototype, the team can make a grounded decision on whether Kenney geometry plus Eureka styling is visually distinctive enough for the first homepage release, and can identify which transformations must move into a production asset pipeline.
