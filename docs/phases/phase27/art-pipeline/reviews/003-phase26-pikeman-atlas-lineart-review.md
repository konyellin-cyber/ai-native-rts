# 003 Phase26 Pikeman Atlas Lineart Review

## Output

- `docs/phases/phase27/art-pipeline/outputs/003-phase26-pikeman-atlas-lineart-source.png`
- `docs/phases/phase27/art-pipeline/outputs/003-phase26-pikeman-atlas-lineart-2048x1024.png`
- `docs/phases/phase27/art-pipeline/outputs/003-phase26-pikeman-atlas-lineart.json`

## Pass / Fail

Pass for Phase 26 frame-contract rehearsal.

Not a final runtime atlas.

## Checks

- Atlas layout: pass. The sheet is organized as 8 columns x 4 rows.
- Animation rows: pass. Rows correspond to charge/run, thrust, hit recoil, and death/fall.
- Frame contract: pass after normalization. The normalized copy is 2048x1024 and matches 256x256 frame slicing.
- Camera: pass. Frames keep the 45-degree oblique RTS view.
- Spear direction: partial pass. Spear direction is much more consistent than earlier pose sheets, especially in run and thrust rows.
- Construction guides: pass for pipeline rehearsal; fail for final art because guide rails remain visible.
- Runtime readiness: fail. The image is RGB with white paper background, not alpha PNG.

## Issues

- The generated source was 1536x1024, so the 2048x1024 version was normalized after generation. This is acceptable for layout rehearsal but not ideal for final art.
- Guide rails are useful for perspective validation, but they should become a separate construction layer or be removed before runtime use.
- The death row has good readability but should be checked in-engine because fallen silhouettes occupy wider frame bounds.

## Decision

Use this as the first Phase 27 proof that the pipeline can produce a Phase 26-compatible frame animation atlas from the perspective-line workflow.

Do not wire it into Phase 26 runtime yet. Next step should generate a native 2048x1024 alpha-background candidate or split construction and clean-line passes.

