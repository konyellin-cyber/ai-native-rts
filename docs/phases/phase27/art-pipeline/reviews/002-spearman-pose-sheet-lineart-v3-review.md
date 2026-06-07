# 002 Spearman Pose Sheet Lineart V3 Review

## Output

`docs/phases/phase27/art-pipeline/outputs/002-spearman-pose-sheet-lineart-v3.png`

## Pass / Fail

Pass for spear perspective alignment.

## Checks

- View angle: pass. The body frames remain in the same 45-degree RTS construction view.
- Body proportion: mostly pass. Standing, march, brace, thrust, and hit frames are close enough for concept-stage planning.
- Foot placement: pass. Ground ellipses and grids remain visible.
- Spear direction: pass. Light-blue parallel perspective rails now make the spear direction legible and consistent across standing/action frames.
- Attack alignment: pass. Thrust now reads as a continuation of the same battle-line direction instead of a separate local direction.
- Fallen frame: partial pass. The pose is usable, but frame footprint is still larger than standing frames.
- Phase 26 usability: pass as a lineart animation planning sheet. Not yet runtime atlas art.

## Issues

- Fallen frame needs atlas-frame normalization because the body footprint is wider and visually heavier.
- Brace pose is improved, but a later revision may lower the stance further for a denser spear-wall read.
- Spear rails are useful for construction; they should be removed or separated before final silhouette/color assets.

## Decision

Accept V3 as the current best perspective-correct pose sheet. Continue to either a silhouette pass based on V3 or a frame-bound normalization pass before equipment and color.

