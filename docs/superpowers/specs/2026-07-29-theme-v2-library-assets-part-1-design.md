# Theme V2 Library & Assets Part 1 Design

**Date:** 2026-07-29

**Status:** Approved

**Canonical product handoff:** `spec/design/theme-v2-library-assets-handoff.md`

**Canonical visual source:** `spec/design/redesignureka.pen`, section `WLBLn`

## Scope

Part 1 establishes the shared asset-card contract used by later Library, Asset Detail, Calendar, and Session work. It does not change the Library Hub, Todo behavior, Skill Builder flow, Calendar interaction logic, or Session conversation layout.

The deliverable contains:

- a backward-compatible `CardDisplayConfig`;
- a presentation adapter from asset payloads and `RenderSpec`;
- the four shared card variants `minimalRow`, `minimalLine`, `richCard`, and `iconTime`;
- accessibility, truncation, empty-value, Light/Dark, and geometry coverage.

## Source Priority

Implementation decisions follow this order:

1. current nodes inside Pencil section `WLBLn`;
2. `theme-v2-library-assets-handoff.md`;
3. existing Theme V2 semantic tokens;
4. older implementation and design documents.

Older documents that mention density controls, a manually draggable secondary-field order, or a separate summary field are historical and do not apply.

## Data Compatibility

The current backend stores an open JSON `render_spec`. Existing consumers understand:

- `primary_field`;
- `secondary_field`;
- `meta_fields`.

Theme V2 introduces the canonical presentation shape:

```text
CardDisplayConfig(
  primaryFieldId: String,
  secondaryFieldIds: List<String>, // zero to three, ordered
)
```

Reading follows these rules:

1. Prefer a valid nested `card_display` object.
2. Otherwise use `primary_field`.
3. Build the ordered secondary list from `secondary_field`, then `meta_fields`.
4. Remove blank values, duplicates, and the primary field.
5. Keep at most three secondary fields.

Writing follows these rules:

1. Persist the canonical nested `card_display`.
2. Mirror the first secondary field into `secondary_field`.
3. Mirror the remaining secondary fields into `meta_fields`.
4. Preserve existing field format directives when the same field remains selected.
5. Preserve unrelated render-spec keys such as `icon`, `accent_color`, `actions`, and timeline configuration.

This keeps the current backend, Flash pipeline, Calendar, legacy cards, and older clients functional without a database migration.

## Presentation Projection

`AssetCardViewData` is the card renderer's immutable input. It contains:

- asset mark;
- skill label;
- formatted primary value;
- up to three formatted secondary values;
- optional localized time label.

The projection adapter:

- reads values from the payload using `CardDisplayConfig`;
- applies existing `RenderSpec` formatting directives;
- skips missing and blank values;
- falls back to the skill label when the configured primary value is empty;
- never exposes schema field names as visible fallback content.

The same projection can later be constructed from an editor draft, so sticky previews and persisted cards cannot drift apart.

## Card Variants

### RichCard

- left mark;
- primary field on the first text row;
- divider contained entirely inside the right text column;
- zero to three secondary values on the second row;
- each secondary value truncates independently;
- blank secondary values do not create separators;
- when no secondary value remains, divider and second row disappear and the primary row is vertically centered.

The component adapts to its parent constraints:

- 96 px reference height uses a 44 px mark;
- compact 86 px reference height uses a 40 px mark;
- semantic structure and field order remain identical.

This is responsive geometry, not a user-selectable density setting.

### MinimalRow

- optional context-provided time;
- asset mark;
- skill label and primary value;
- one line only;
- the complete row is one detail target.

### MinimalLine

- skill label and primary value;
- one line only;
- no divider, mark, or secondary metadata;
- height never grows because of content.

### IconTime

- asset mark and localized time only;
- no title or secondary data;
- the complete tile is one detail target.

## Interaction and Accessibility

- `onOpen == null` or `disabled == true` produces a disabled semantic target.
- Enabled cards expose one button semantic rather than multiple nested tap targets.
- Text remains readable at system text scale without horizontal overflow.
- Pressed feedback uses a subtle opacity/luminance change and scale near `0.98`.
- Reduced Motion removes scale animation and keeps a static pressed color response.

## Testing

Part 1 uses test-driven development:

- unit tests for canonical and legacy config parsing;
- unit tests for compatibility serialization and format preservation;
- unit tests for payload projection, ordering, truncation inputs, and blank values;
- widget tests for all four variants and semantics;
- Light/Dark golden tests at 411 px;
- RichCard golden cases for full metadata, no metadata, long metadata, and compact 86 px geometry.

## Later Integration

Part 1 creates components but does not yet replace every existing consumer. Subsequent approved parts will integrate them in this order:

1. Library Shell and Hub;
2. container directories and asset lists;
3. shared half/full Asset Detail;
4. system and custom detail content;
5. dedicated system editors and schema-driven custom editor;
6. Todo behavior;
7. Skill Builder and Card Settings;
8. Calendar and Session card consumers;
9. full regression and real-device verification.
