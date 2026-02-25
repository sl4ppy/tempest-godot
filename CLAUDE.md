# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Faithful recreation of Atari's 1981 Tempest arcade game in Godot 4 (GDScript). This is a **behavioral recreation** — we implement the documented game logic directly, not a hardware emulator.

## Rules
- Never guess or assume on implementation.  When implementing any aspect, system, screen, flow, or element of this project, review both the documentation provided and also review the original source code.  All implementation must match the original game as closely as possible in every aspect.

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
- **`docs/VECTOR_GRAPHICS.md`** — Complete vector graphics technical reference (AVG hardware, macro system, shape encoding, pitfalls)

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
- **Two entity rendering systems**: Flipper and Pulsar use the **ONELIN** parametric system (shapes drawn between lane edges via unit/perp VEC multipliers). All other entities use **SCAPIC** (centered, normalized shapes). Both implemented in `vector_shapes.gd`. See "Entity Rendering" section below.
- **Vector beam font**: All in-game text rendered via `vector_font.gd` using exact character stroke data from `ANVGAN.MAC`. Autoload singleton `VectorFont`.
- **Data-driven sound**: POKEY synthesis via AudioStreamGenerator using the original 4-byte sequence format (start_value, frame_count, change, num_changes).
- **Fixed tick rate**: Game logic at 20 Hz (`SECOND = 20`), rendering at 60 FPS with interpolation.
- **CRT aesthetic**: All vectors drawn to SubViewport, post-processed with phosphor glow shader (bloom + persistence).
- **Perspective-correct depth**: Entity screen positions use inverse-depth mapping (`depth_to_frac()`) rather than linear lerp, matching the 1/y projection behavior.
- **Attract mode AI**: `AUTOCU` greedy nearest-enemy targeting with POLDEL shortest-path polar distance. Replaces human input during demo.
- **Attract mode cycle**: CDLADR (high scores, ~1s) → CLOGO (BOXPRO/LOGPRO animation + 3s hold) → demo gameplay (ends on wave clear per NEWAV2, or player death) → repeat.
- **Inter-level drop**: `CDROP` state — player descends through well with acceleration `(20 + min(wave, 30)) / 256` per frame, can fire at spikes.

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

### Entity Rendering

Two rendering systems from the original hardware, both in `vector_shapes.gd`:

**ONELIN** (`draw_onelin`) — Flipper, Pulsar (from `ALDISP.MAC`):
- Shapes drawn between left and right lane edge endpoints
- VEC format: `[delta_unit, delta_perp, draw_flag]`, 8 units = full lane width
- Flipper: single non-animating bowtie shape (CINVA1). **Does NOT animate.**
- Pulsar: 5 frames (PULS0-4), flat line → zigzag, driven by PULSON timer

**SCAPIC** (`draw_shape`) — Tanker, Spiker, Fuseball, Enemy Shots, Player (from `ALVROM.MAC`):
- Shapes centered at entity position, normalized, perspective-scaled
- SCVEC operands are absolute positions (assembler macros compute deltas)

**WARNING**: The ENER11-14 (flipper) and ENER21-24 (pulsar) shapes in `ALVROM.MAC` are from an **unused Space Game mode** (`SPACG=0`, conditionally compiled out). Do NOT use them. The actual shipped shapes are ONELIN data in `ALDISP.MAC`.

### UI Screens (hud.gd)

All UI screens implemented from actual 6502 assembly source (ALSCO2.MAC, ALLANG.MAC, ALVROM.MAC):

**BOXPRO/LOGPRO** (Logo sequence): SCARNG routine draws shape at multiple depths from NEARY to FARY (step 2). Scale: `binary=INDEX>>5, linear=(INDEX<<2)&0x7F`. Color: leading=WHITE, trailing=`(INDEX>>3)&7` with 7→RED. BOXPRO uses VORBOX (rectangle), LOGPRO uses VORLIT (TEMPEST text).

**LDRDSP** (High scores): Full screen with three sections:
- **INFO** (top): P1 score GREEN top-left, high score + #1 initials GREEN center (SCORES template in ALVROM.MAC, no text label). INSERT COINS / GAME OVER alternating RED (QFRAME & 0x1F < 0x10).
- **LDROUT** (middle): "HIGH SCORES" RED scale 0 Y=0x38. 8 entries BLULET at X=-48, Y from 40 to -30 (decimal step -10). Format: rank.dot space initials space score.
- **DSPCRD** (bottom): "© MCMLXXX ATARI" BLULET Y=0x92, "BONUS EVERY 20000" TURQOI Y=0x89, "CREDITS 0" + "1 COIN 1 PLAY" GREEN Y=0x80.

**GETDSP** (Initials entry): "PLAYER X" at Y=0xC0, "ENTER YOUR INITIALS" RED, "SPIN KNOB" TURQOI, "PRESS FIRE" YELLOW. Falls into LDROUT for score table.

**RQRDSP** (Wave select): 5-column scrolling display. XPOTAB X-positions: -66,-29,9,48,88. LEFSID/RITSID window tracking. LEVEL table (28 entries) gated by HIRATE. Uses local X multiplier (`_WS_XM=2.65`) instead of standard VGVTR1 (3.28) to keep ASCVH -117 labels on-screen within our 768-wide viewport. All column content (level number, hole shape, bonus) centered on XPOTAB column position. Level numbers and hole shapes use per-band difficulty colors (Blue/Red/Yellow/Cyan/Green/Purple cycling every 16 waves via `BAND_COLORS`).

### VG Coordinate Mapping

Two mapping systems for positioning UI text:

**MSGS/VGVTR1** — Used by MESS table messages (ALLANG.MAC):
- MESS Y values are hex bytes (assembler default radix). Values ≥ 0x80 are negative signed bytes.
- VGVTR1 (ALVGUT.MAC) multiplies signed byte by 4 via two ASL operations.
- Mapping: `screen_y = 512 - signed_val * 4.0 * VG_SCALE` where `VG_SCALE = 0.82` accounts for analog CRT deflection vs pixel viewport.
- Example: Y=0x92 → signed -110 → ×4 = -440 → ×0.82 = -360.8 → screen Y = 872.8

**Direct VCTR** — Used by SCORES template (ALVROM.MAC):
- Raw VG coordinates, not multiplied. Positioned via VCTR macro from CNTR origin.
- Only used for the persistent score/lives overlay (INFO section).

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
