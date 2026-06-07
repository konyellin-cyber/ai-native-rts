# 002 Spearman Pose Sheet Lineart V2 Review

## Output

`docs/phases/phase27/art-pipeline/outputs/002-spearman-pose-sheet-lineart-v2.png`

## Pass / Fail

Fail for perspective alignment.

## Checks

- View angle: partial pass. The bodies remain broadly 45-degree top-down.
- Body proportion: pass. Standing frames are consistent enough.
- Foot placement: partial pass. Ground ellipses exist but do not enforce one shared battle direction strongly enough.
- Spear direction: fail. Standing, brace, thrust, stagger, and fallen spear lines do not clearly share one perspective system.
- Phase 26 usability: fail for atlas planning because spear direction is core to front-line readability.

## Issues

- The attack/thrust frame reads as a different direction than the standing/ready frames.
- The spear tips do not consistently land on a common ground-plane rail.
- Each frame has local grid hints, but there is no explicit shared vanishing direction or multi-point helper line controlling the spear.

## Decision

Do not advance to silhouette or equipment. Generate V3 with explicit shared perspective rails for spear placement in every frame.

