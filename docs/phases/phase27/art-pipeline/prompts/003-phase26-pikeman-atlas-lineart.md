# 003 Phase26 Pikeman Atlas Lineart

## Goal

Generate a line-art frame animation atlas that matches the current Phase 26 / Phase 25 pikeman atlas contract.

This is not a final colored runtime asset. It is a construction-line atlas rehearsal based on the accepted perspective sheet, intended to test whether the pipeline can produce the same frame organization expected by `BattleSpriteRenderer`.

## Phase 26 Atlas Contract

- Columns: 8
- Rows: 4
- Total frames: 32
- Frame size target: 256 x 256
- Atlas target: 2048 x 1024
- Row 0 / frames 0-7: `charge_run`
- Row 1 / frames 8-15: `spear_thrust`
- Row 2 / frames 16-23: `hit_recoil`
- Row 3 / frames 24-31: `death_fall`

## Positive Prompt

Using the visible V3 spearman construction pose sheet as the strict perspective and spear-direction reference, create a 2D animation sprite atlas for one medieval pikeman / spearman.

Atlas layout:
- exact 8 columns x 4 rows grid
- 32 total frames
- each cell should behave like a 256 x 256 frame
- clean margins inside every cell
- one consistent character across all frames
- no text labels, no frame numbers

Animation rows:
- Row 1: charge_run, 8 frames, spearman running/pressing forward with spear aligned to the same diagonal ground-plane direction
- Row 2: spear_thrust, 8 frames, from low brace into forward thrust and recover, impact around frames 4-5 of the row
- Row 3: hit_recoil, 8 frames, body jolts backward but keeps the same 45-degree camera and grounded foot logic
- Row 4: death_fall, 8 frames, collapse to the ground, final frames readable as fallen corpse, same camera and scale

Perspective requirements:
- 45-degree orthographic RTS camera, matching Phase 26 / Phase 25 oblique pikeman atlas style
- visible helmet top, shoulders, chest top plane, pelvis, and boot placement
- spear direction must follow the same diagonal battle-line direction in every non-fallen frame
- include faint light-blue spear perspective guide rails in each frame, especially charge_run and spear_thrust
- spear shaft, spear butt, and spear tip must lie on the same guide rail
- no side-view, no horizontal brawler view, no front-facing character sheet

Style:
- construction-line / cleaned pencil-and-ink animation atlas
- black and gray body lines
- light-blue perspective guide lines
- white or very light gray background
- no color fill
- no material rendering
- no shadows
- no painterly detail

## Negative Prompt

Avoid colored finished art, rendered armor, side-view sprites, front-facing poses, horizontal brawler animation, random spear directions, missing guide rails, inconsistent body scale, inconsistent spear length, cropped spear, cropped feet, text labels, frame numbers, UI, scenery, shadows, painterly rendering, multiple characters per frame.

## Input References

- Perspective master: `docs/phases/phase27/art-pipeline/outputs/001-spearman-perspective-construction.png`
- V3 pose sheet: `docs/phases/phase27/art-pipeline/outputs/002-spearman-pose-sheet-lineart-v3.png`
- Phase 26 atlas metadata: `src/phase1-rts-mvp/assets/characters/sprites/medieval_pikeman_iso_v3_oblique.json`

## Output

- `docs/phases/phase27/art-pipeline/outputs/003-phase26-pikeman-atlas-lineart-source.png`
- `docs/phases/phase27/art-pipeline/outputs/003-phase26-pikeman-atlas-lineart-2048x1024.png`
- `docs/phases/phase27/art-pipeline/outputs/003-phase26-pikeman-atlas-lineart.json`

## Review

Accepted as a Phase 26 frame-contract rehearsal, not as final runtime art. See `docs/phases/phase27/art-pipeline/reviews/003-phase26-pikeman-atlas-lineart-review.md`.

## Next Revision

Next revision should remove guide rails into a separate construction layer, produce a transparent-background runtime candidate, and avoid non-uniform normalization by generating at native 2048x1024 if possible.

