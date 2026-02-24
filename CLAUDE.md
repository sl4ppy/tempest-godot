# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Faithful recreation of Atari's 1981 Tempest arcade game in Godot 4 (GDScript). This is a **behavioral recreation** — we implement the documented game logic directly, not a hardware emulator.

## Reference Documentation

The original reverse-engineered documentation is available as a git submodule at `docs/tempest-reference/` (from https://github.com/sl4ppy/tempest-main). Key docs:

- `docs/tempest-reference/docs/SYSTEMS.md` — Core systems architecture
- `docs/tempest-reference/docs/GAME_STATE_FLOW.md` — 19-state game state machine
- `docs/tempest-reference/docs/CAM_SCRIPTS.md` — Enemy AI bytecode (20 opcodes, 11 scripts)
- `docs/tempest-reference/docs/ENTITIES.md` — All entities, collision system, animation data
- `docs/tempest-reference/docs/PLAYFIELD.md` — All 16 well shapes with coordinate tables
- `docs/tempest-reference/docs/LEVEL_DATA.md` — Complete difficulty tables for 99 waves
- `docs/tempest-reference/docs/HARDWARE_REGISTERS.md` — POKEY sound format, VG encoding
- `docs/tempest-reference/docs/DATA_ASSETS.md` — Vector shapes, sound data, text strings

## Architecture

```
scenes/          # Godot scene files (.tscn)
scripts/         # GDScript game logic
  entities/      # Per-entity scripts (player, flipper, tanker, etc.)
data/            # Game data resources (.tres)
shaders/         # CRT phosphor glow shader
```

### Key Design Decisions

- **CAM bytecode VM**: Enemy AI runs as a bytecode interpreter (`cam_interpreter.gd`), executing the original 20 CAM opcodes. Do NOT rewrite enemy behaviors as imperative code.
- **Direct 3D math**: The WORSCR projection is `screen = (world - eye) / depth`. No Mathbox emulation.
- **Data-driven sound**: POKEY synthesis via AudioStreamGenerator using the original 4-byte sequence format (start_value, frame_count, change, num_changes).
- **Fixed tick rate**: Game logic at 20 Hz (`SECOND = 20`), rendering at 60 FPS with interpolation.
- **CRT aesthetic**: All vectors drawn to SubViewport, post-processed with phosphor glow shader (bloom + persistence).

### Projection Formula

```gdscript
func project(world: Vector3, eye: Vector3, z_adjust: float) -> Vector2:
    var dy = world.y - eye.y
    if dy == 0: dy = 1
    var scale = 1.0 / dy
    return Vector2(
        (world.x - eye.x) * scale,
        (world.z - eye.z) * scale + z_adjust
    ) * screen_scale + screen_center
```

### Collision System

Line-based, not bounding-box. Entities share a lane (0-15). Collision checks Y-depth proximity:
- Player shot vs enemy shot: `abs(delta_y) < CHACHA`
- Player shot vs invader: `abs(delta_y) < ENSIZE[enemy_type]`
- `ENSIZE[type] = (abs(speed_hi) + 13) / 2`

## Build & Run

Open `project.godot` in Godot 4.4+, press F5.

## Conventions

- GDScript with static typing where practical
- Node names match entity names from documentation (e.g., `Flipper`, `Pulsar`, `Well`)
- Constants match original names where meaningful (e.g., `PCVELO`, `SECOND`, `NPARTI`)
- Comments reference doc sections: `# See ENTITIES.md § Collision Detection System`
