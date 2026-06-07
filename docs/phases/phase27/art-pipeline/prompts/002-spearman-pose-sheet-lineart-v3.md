# 002 Spearman Pose Sheet Lineart V3

## Goal

Fix the main failure in V2: standing and attack spear directions are not aligned to the same perspective.

This revision must add visible perspective helper lines around each spear so the spear shaft and spear tip clearly sit on the same shared ground-plane direction across all frames.

## Positive Prompt

Create a revised construction-line pose sheet for one medieval spearman, using the visible reference perspective master as the strict camera base.

Critical perspective requirement:
- Draw visible light-blue perspective helper lines for the spear in every frame.
- Each frame must include two or three faint parallel guide rails on the ground plane that show the spear direction.
- The spear shaft must lie exactly on one of these guide rails.
- The spear butt and spear tip must sit on the same guide rail.
- The guide rails must point in the same diagonal battle-line direction in every standing/action frame.
- Use the same ground-plane grid orientation and same 45-degree orthographic RTS camera across all frames.

Create exactly six poses in a neat 3x2 grid:
1. idle ready
2. march step
3. low brace / hold line
4. thrust attack from the brace pose
5. hit stagger
6. fallen

For every pose:
- keep the same non-heroic mass-soldier body proportion
- show construction anatomy: head sphere, chest box, pelvis block, limb cylinders, joint circles
- show foot contact points and a small ground ellipse or grid
- show spear perspective rails before drawing the spear
- keep the spear length consistent
- keep the body facing the same diagonal direction
- keep the attack direction aligned with the idle/brace spear direction

Style:
- pencil/ink construction sketch
- black/gray body construction lines
- light blue perspective guide lines and spear rails
- line art only
- white or very light gray paper background
- no color fill
- no shadows
- no labels
- no watermark

## Negative Prompt

Avoid finished colored art, detailed armor, side-view sprites, front-facing pose sheet, horizontal brawler animation, random spear directions, spear not on guide rails, missing spear helper lines, inconsistent ground grids, perspective distortion, inconsistent body scale, cropped spear, cropped feet, text labels, UI, scenery, multiple different characters, shadows, painterly rendering.

## Input References

- Perspective master: `docs/phases/phase27/art-pipeline/outputs/001-spearman-perspective-construction.png`
- Failed V2: `docs/phases/phase27/art-pipeline/outputs/002-spearman-pose-sheet-lineart-v2.png`

## Output

- `docs/phases/phase27/art-pipeline/outputs/002-spearman-pose-sheet-lineart-v3.png`

## Review

Passed for spear perspective alignment. See `docs/phases/phase27/art-pipeline/reviews/002-spearman-pose-sheet-lineart-v3-review.md`.

## Next Revision

Before atlas production, normalize per-frame bounds and reduce the fallen pose footprint so it does not read larger than the standing poses.

