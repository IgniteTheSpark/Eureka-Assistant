# UReka Vibe Coding Intro

This folder is prepared for building a `frontend-slides` deck.

## Contents

- `index.html` — the generated frontend-slides HTML deck.
- `content/slides-script.md` — the current 14-slide speaker-led script, including slide copy, image guidance, and talk track.
- `content/outline.md` — the longer source outline and earlier structure notes.
- `assets/images/` — currently available user-provided screenshots with semantic filenames.
- `assets/needed/` — placeholder notes for missing images that should be added before final slide generation.

## Recommended Deck Mode

- Purpose: internal presentation
- Length: medium, 10-20 slides
- Density: low density / speaker-led
- Target duration: 30 minutes

## Current Image Mapping

| File | Suggested slide | Purpose |
|---|---|---|
| `assets/images/01-codex-workflow.png` | Slide 6: Agent development workflow | Shows the updated Codex thread organization for UReka, hardware, bugs, requirements, and AI sharing work. |
| `assets/images/02-variant-home.png` | Slide 13: Taste as input ability | Shows external visual reference as AI design input. |
| `assets/images/03-github-commits.png` | Slide 11: Iteration density | Shows frequent spec/design/implementation/review commits. |
| `assets/images/04-generated-report.png` | Slide 12: Reports as experience | Shows generated report as a designed reading experience. |
| `assets/images/05-custom-skill-baby-milk.png` | Slide 4 or Slide 9: Unified input + custom skills | Shows custom skill creation for baby feeding records. |
| `assets/images/06-custom-skill-tennis.png` | Slide 4 or Slide 9: Unified input + custom skills | Shows custom skill creation for tennis match records. |
| `assets/images/07-flash-history-sessions.png` | Slide 3 or Slide 4: Flash as daily capture entry | Shows flash history sessions as repeated fragmented capture. |
| `assets/images/08-home-reka-offer.png` | Slide 7: Today page / Reka Offer | Shows proactive offer card on home page. |
| `assets/images/09-reka-notification-popup.png` | Slide 9: Heartbeat / nudge / notification loop | Shows Reka reminder popup driven by notification/nudge layer. |
| `assets/images/10-morning-briefing.png` | Slide 9 or technical architecture extension | Shows scheduled/briefing output as proactive assistant behavior. |
| `assets/images/11-day-view-non-schedule.png` | Slide 4 or Slide 9: Asset organization | Shows day view with non-schedule records grouped alongside time context. |
| `assets/images/12-home-bubble-pool.png` | Slide 8: Asset drop / positive feedback | Shows the updated home bubble pool and generated assets as visible feedback. |
| `assets/images/13-flash-to-asset-session.png` | Slide 9: Flash pipeline / local Agent loop | Shows flash session input becoming structured asset cards. |
| `assets/images/14-ring-photo.png` | Slide 10: Hardware capture entry | Shows the physical ring hardware. |
| `assets/images/15-hardware-flash-button.png` | Slide 3 or Slide 10: Hardware card view | Shows the updated EUREKA hardware card/product view that frames low-friction capture as a tangible device experience. |
| `assets/images/16-day-view-schedule.png` | Slide 4 or Slide 9: Asset organization | Shows the schedule timeline view with timed events and all-day records. |
| `assets/images/17-asset-library.png` | Slide 4: UReka product surface | Shows the updated asset library, custom skills, permanent categories, and recent records. |
| `assets/images/18-hardware-real-device.png` | Slide 10: Hardware integration | Shows the more realistic hardware device view used in the hardware pipeline case. |

## Missing Priority Images

Add these before final slide generation if possible:

1. `19-ring-recording-status.png` — ring connection / recording / ASR status.
2. `20-taste-reference-grid.png` — Craftwork / Hugeicons / Web to Design collage, if not generated directly in slides.

If only one more image can be added, prioritize `19-ring-recording-status.png`, because it proves the hardware-to-AI pipeline, not only the physical device.

## Generation Notes

When using `frontend-slides`, treat the images as part of the outline design, not decoration. Large screenshots should usually get their own slide or be cropped into focused panels with short captions.
