# Character Sprite Atlases

Phase 25 uses this directory for 2.5D character sprite assets rendered by `BattleSpriteRenderer`.

The first implementation uses a procedural shader placeholder, so there are no required atlas files yet. Final sprite assets should live here instead of inside `scripts/`.

Current candidate assets:

```text
medieval_pikeman_red_iso_v2.png    # 6x4 smoke-test atlas
medieval_pikeman_blue_iso_v2.png
medieval_pikeman_iso_v2.json

medieval_pikeman_red_iso_v3.png    # 8x4 Phase 25G animation upgrade candidate
medieval_pikeman_blue_iso_v3.png
medieval_pikeman_iso_v3.json

medieval_pikeman_red_iso_v3_oblique.png    # 8x4 stronger 45-degree oblique candidate
medieval_pikeman_blue_iso_v3_oblique.png
medieval_pikeman_iso_v3_oblique.json
```

The JSON metadata should describe atlas frames for states such as:

```text
run
attack
hit
death
```

Keep the atlas authored for the Phase 9/24 45-degree orthographic camera unless a later phase introduces multi-direction sprite rendering. Side-view / horizontal beat-em-up style sprites are rejected for Phase 25 because they do not match the in-engine isometric camera.
