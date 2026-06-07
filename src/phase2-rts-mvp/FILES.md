# Phase 2 RTS MVP — File and Folder Plan

This folder is the new mainline game root for Phase 27 and later.

It intentionally starts as a clean project structure instead of copying all of `src/phase1-rts-mvp`. Phase 1 remains the technical prototype and regression reference. Phase 2 should only port stable systems that serve the family-war RTS MVP.

## Top-Level

| Path | Responsibility |
|---|---|
| `project.godot` | Godot project file. Created when implementation starts. |
| `config/` | Runtime JSON configs: default sandbox settings, name pools, scenario seeds. |
| `scenes/` | Godot scenes only. Keep gameplay logic in scripts. |
| `scripts/` | Game code, split by architectural layer. |
| `tests/` | Headless and scenario-level validation for the MVP. |
| `tools/` | Offline generators, balance scripts, report exporters. |
| `assets/` | Phase 2-specific art/audio/data assets. |
| `docs/` | Engineering notes local to this Godot project. |
| `addons/` | Godot addons, if needed. |

## scripts/

### `scripts/app/`

Application composition and lifecycle.

Expected files:

- `game_app.gd`: main scene bootstrap, wires systems together.
- `game_state.gd`: top-level state: setup / playing / paused / ended.
- `config_loader.gd`: loads `config/*.json`.
- `seed_service.gd`: owns deterministic run seed.

Rule: app scripts may depend on all layers, but lower layers must not depend on `app/`.

### `scripts/domain/`

Pure gameplay data and deterministic rules.

Expected files:

- `family.gd`
- `character.gd`
- `battalion.gd`
- `location.gd`
- `war_event.gd`
- `relation_state.gd`

Rule: domain scripts should avoid scene-tree dependencies. Prefer dictionaries / typed data containers / PackedArrays.

### `scripts/world/`

Map template, locations, capitals, resource points, villages.

Expected files:

- `map_template.gd`
- `location_instance.gd`
- `capital_site.gd`
- `resource_site.gd`
- `village_site.gd`

Rule: world owns spatial placement and ownership markers, not economy rules.

### `scripts/systems/`

Gameplay systems that advance the RTS loop.

Expected files:

- `family_generator.gd`
- `economy_system.gd`
- `production_system.gd`
- `event_system.gd`
- `succession_system.gd`
- `capture_system.gd`
- `ai_family_controller.gd`
- `victory_system.gd`
- `chronicle_system.gd`

Rule: systems operate on domain/world state and emit events. They should not directly render UI.

### `scripts/simulation/`

High-frequency movement and battle simulation.

Expected files:

- `battalion_movement.gd`
- `battle_contact_solver.gd`
- `formation_pressure_engine.gd`
- `phase26_adapter.gd`
- `battle_metrics.gd`

Rule: this layer must stay profile-friendly. Avoid per-soldier nodes. Reuse PackedArrays and SpatialHash patterns from Phase 24–26.

### `scripts/ui/`

HUD and player interaction.

Expected files:

- `sandbox_hud.gd`
- `selection_controller.gd`
- `command_panel.gd`
- `event_log_view.gd`
- `prisoner_dialog.gd`
- `chronicle_view.gd`

Rule: UI sends commands/intents to systems. UI should not mutate simulation arrays directly.

## scenes/

| Path | Responsibility |
|---|---|
| `scenes/main/` | Main playable entry scene. |
| `scenes/sandbox/` | Sandbox map scene and debug variants. |
| `scenes/ui/` | Reusable UI scenes. |

## tests/

| Path | Responsibility |
|---|---|
| `tests/headless/` | Test runner and headless bootstrap. |
| `tests/scenarios/` | JSON scenario definitions and deterministic seeds. |

Initial target scenario:

- `family_war_mvp`: generate 3 families, run the RTS loop, produce at least 5 war events, finish with a victory state.

## Porting Policy From `phase1-rts-mvp`

Port selectively:

- Phase 24–26 data-oriented battle simulation ideas.
- Battle sprite renderer if still useful.
- AI renderer/test utilities only if they serve Phase 2 validation.

Do not blindly copy:

- Legacy node-per-unit combat.
- Old bootstrap as a central god object.
- Test scenes unrelated to the family-war MVP.
- UID churn unless Godot generates it for active scenes.

## Naming

Use Phase 2 naming for new gameplay concepts:

- `Family`, not team/faction when referring to narrative houses.
- `Character`, not hero/general when referring to generated people.
- `Battalion`, not soldier group / army blob.
- `WarEvent`, not log line.
- `Chronicle`, not result summary.
