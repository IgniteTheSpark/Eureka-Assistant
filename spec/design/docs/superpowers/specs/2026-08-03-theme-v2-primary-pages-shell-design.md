# Theme V2 Primary Pages Shell Design

> Date: 2026-08-03
> Status: Approved design, pending canvas implementation
> Scope: Today, Calendar, Library, shared global top navigation, shared dock, and asset icon semantics

## 1. Outcome

Theme V2's three primary pages use one common application shell while keeping their page-specific content independent:

```text
Device status bar
→ Global top navigation
→ Page title
→ Page content
→ Floating dock
→ Home indicator
```

The global top navigation keeps the UReka logo and global actions. The page title remains a separate content heading. Today, Calendar, and Library use the same title size, horizontal inset, and vertical position.

Today no longer uses one large outer sheet. Its content is divided into three independent containers:

1. Next Moment.
2. Reka.
3. Today Generated.

## 2. Shared Page Shell

The canonical mobile viewport remains `411 × 960`.

### 2.1 Vertical structure

| Region | Contract |
|---|---|
| Status bar | `44px` high |
| Global top navigation | `60px` high, immediately below the status bar |
| Page title | Starts below the top navigation, aligned to the `18px` page inset |
| Content | Starts below the title with a consistent gap |
| Floating dock | Remains above the home indicator and does not touch page content |
| Dock clearance | At least `16px`, target `20px`, between content and dock |

### 2.2 Global top navigation

All three primary pages reuse the existing Theme V2 global top navigation variants:

- `Theme V2 / Global Top Nav / Device Disconnected`
- `Theme V2 / Global Top Nav / Device Connected`

The navigation keeps:

- UReka brand mark and wordmark.
- Device status.
- Theme control.
- Notification entry and unread state.

The page title must not be placed inside this navigation.

### 2.3 Page title

The primary page titles are:

```text
今日
日历
资产库
```

They share:

- One typography token, targeting `28px` with the current Theme V2 display weight.
- `18px` left and right inset.
- The same top position below global navigation.
- No eyebrow-sized variant on Today.
- No oversized Library-only variant.
- No missing title on Calendar.

## 3. Today Layout

### 3.1 Remove the outer sheet

The current `Today Front Page / Full Sheet` visual wrapper is removed from the rendered page. Today uses the page background directly and presents three sibling containers. Decorative effects must not recreate a full-page outer border or full-page rounded sheet.

### 3.2 Three independent containers

All three containers use the common `18px` page inset and `12px` vertical gap.

#### Next Moment

- Keeps countdown, next event, related todo count, and agenda entry.
- Remains the first content container.
- Uses the same light/dark surface contract as the other two containers.

#### Reka

- Keeps the active queue summary and expandable candidates.
- Remains the second content container.
- Internal scrolling, if shown, stays inside this container.

#### Today Generated

- Becomes a real third container instead of a full-page background layer.
- Has its own header label and optional count.
- Owns the complete bubble animation stage.
- Ends above the floating dock with at least `16px` clearance.

### 3.3 Bubble motion

New asset bubbles enter from the top edge of the Today Generated container and settle toward its bottom. They do not fall from the top of the whole page and do not pass behind Next Moment, Reka, the page title, or the global navigation.

The container clips its contents. The motion contract is:

```text
Created asset
→ bubble appears at the top of Today Generated
→ short downward fall with restrained lateral drift
→ settles into the existing cluster near the bottom
```

The animation must respect reduced-motion settings by replacing the fall with a short fade and scale-in at the settled position.

## 4. Asset Icon Contract

Asset icons are semantic identifiers, not decorative variations.

### 4.1 Resolution order

```text
Asset type canonical icon
→ configured UserSkill icon, when the asset type is custom
→ generic file fallback
```

The icon resolver must not infer a new icon from the asset's title or body text.

### 4.2 Canonical examples

| Asset type | Icon direction |
|---|---|
| Todo | `square-check` |
| Event | `calendar-days` |
| Note / text | `file-text` or the existing canonical note icon |
| Contact | `contact` / canonical contact icon |
| Recording | `mic` |
| Image | `image` |
| Location | `map-pin` |
| Report | canonical report/chart icon |
| Custom UserSkill asset | the UserSkill's configured icon |
| Unknown | `file` fallback |

The same resolver is used by Today bubbles, Calendar entries, Library's Recently Generated items, asset cards, and Session result cards. Color may reflect the asset container or UserSkill, but the icon shape remains type-stable.

## 5. Floating Dock

The dock represents the three primary destinations, not brand or AI actions:

| Destination | Canonical icon |
|---|---|
| Today | `sun` |
| Calendar | `calendar-days` |
| Library | `library` |

The existing Today `sparkles` icon is replaced with `sun` in light and dark shared dock components and their instances.

Selection is communicated through icon color and a restrained soft background or emphasis. Mobile selection does not use an underline. The dock remains visually floating and must not touch a page container.

## 6. Calendar and Library Alignment

### 6.1 Calendar

- Adds the shared global top navigation.
- Adds the `日历` page title below it.
- Moves the date rail and scrollable calendar content below the title.
- Preserves the existing calendar density and hierarchy within the available scroll viewport.
- Keeps the same floating dock clearance used on Today and Library.

### 6.2 Library

- Keeps the shared global top navigation already present.
- Changes `资产库` to the shared primary-page title token and position.
- Reflows the existing statistics, containers, AI Skill banner, and Recently Generated content below the shared title block.
- Recently Generated continues using the independent icon-plus-time treatment, now backed by the canonical asset icon resolver.

## 7. Theme and Variant Coverage

The canvas update covers:

- Today default and agenda examples in light and dark.
- Calendar canonical primary examples in light and dark.
- Library hub canonical examples in light and dark.
- Shared light and dark dock components.
- Connected and disconnected global top navigation variants where already used.

Detail screens and bottom sheets keep their contextual headers. When a detail experience is presented as a full primary-page surface, it inherits the shared global top navigation above its contextual header; modal sheets do not duplicate the global navigation inside the sheet.

## 8. Acceptance Criteria

1. Today, Calendar, and Library show the same global top navigation structure.
2. Their page titles use the same size, inset, and vertical position.
3. Today has no full-page outer sheet or border.
4. Today shows three clearly independent containers.
5. Today Generated owns and clips the full bubble field.
6. New bubbles visually enter from the top of the Today Generated container.
7. The dock has visible whitespace from the nearest content container.
8. The dock uses `sun`, `calendar-days`, and `library` semantics in both themes.
9. Dock selection does not use an underline.
10. Today bubbles use stable asset-type or configured UserSkill icons rather than content-derived icons.
11. Library's Recently Generated icons use the same asset icon resolver.
12. Light and dark canonical screens remain structurally aligned.
13. No content is clipped by the dock or home indicator in the static canvas examples.

## 9. Non-goals

- Redesigning the global device, theme, or notification actions.
- Changing Calendar's scheduling model or asset display density.
- Changing Library's container hierarchy or Recently Generated limit.
- Introducing new asset types.
- Restoring or exposing Goal-related UI.
- Redesigning detail sheets that are not primary-page surfaces.
