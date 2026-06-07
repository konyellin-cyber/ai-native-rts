# 001 Spearman Animation Sheet

## Goal

Test whether Phase 27 can generate a stable Phase 26 spearman animation asset for the existing 45-degree orthographic RTS camera.

The key validation is not final beauty. The output should show whether a generated spearman can keep consistent body proportion, camera angle, spear direction, and readable silhouette across several animation states.

## Positive Prompt

Create a clean production sprite-sheet concept for a medieval spearman / pikeman used in a 45-degree orthographic RTS battle.

Asset requirements:
- One consistent character only: a medieval light-armored spearman with a long spear.
- Camera: 45-degree orthographic RTS view, visible helmet top, shoulders, torso, and ground-plane diagonal spear angle.
- Not side-view, not horizontal beat-em-up, not front-facing portrait.
- Six animation key poses in a single sheet: idle, march, brace, thrust attack, hit stagger, fallen.
- Same body proportion, same armor, same spear length, same camera angle in every pose.
- Clean readable silhouette at small RTS scale.
- Simple line art with restrained flat color accents, low detail, low visual noise.
- Spear should clearly project along the battle line, suitable for dense Phase 26 front-line formations.
- Arrange poses in a neat grid with generous spacing.
- Use a perfectly flat solid #ff00ff chroma-key background for later background removal.

Style:
- hand-drawn but practical game production sheet
- crisp edges
- muted medieval colors: iron helmet, leather straps, dull cloth, small red family cloth accent
- no dramatic lighting
- no cast shadow
- no text labels
- no watermark

## Negative Prompt

Avoid side-view sprites, brawler style, anime proportions, oversized heroic fantasy armor, painterly background, dramatic shadows, perspective camera distortion, inconsistent body sizes, inconsistent spear length, duplicate characters in one frame, cropped limbs, text labels, UI, watermarks, scenery, transparent checkerboard.

## Input References

- Phase 26 requirements from `docs/phases/phase26/design.md`: dense front-line soldier formations, 45-degree battle readability, front-line pressure.
- Sprite README requirement from `src/phase1-rts-mvp/assets/characters/sprites/README.md`: authored for Phase 9/24 45-degree orthographic camera; side-view / horizontal beat-em-up style is rejected.

## Output

- `docs/phases/phase27/art-pipeline/rejected/001-spearman-animation-sheet-source.png`
- `docs/phases/phase27/art-pipeline/rejected/001-spearman-animation-sheet-alpha.png`

## Review

Rejected. See `docs/phases/phase27/art-pipeline/reviews/001-spearman-animation-sheet-rejected.md`.

## Next Revision

Restarted the pipeline with `001-spearman-perspective-construction.md`, focusing on perspective construction lines before finished art.
