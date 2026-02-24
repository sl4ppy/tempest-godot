# Vector Graphics System — Complete Technical Reference

This document is the definitive reference for understanding, implementing, and debugging Tempest's vector shape rendering system. It covers the original AVG hardware, the assembler macro system, the shape data format, and our GDScript implementation.

## Table of Contents

1. [AVG Hardware Overview](#1-avg-hardware-overview)
2. [AVG Instruction Set](#2-avg-instruction-set)
3. [Assembler Macro System](#3-assembler-macro-system)
4. [Critical: Absolute vs Delta Coordinates](#4-critical-absolute-vs-delta-coordinates)
5. [Color and Brightness](#5-color-and-brightness)
6. [Shape Data Catalog](#6-shape-data-catalog)
7. [GDScript Implementation](#7-gdscript-implementation)
8. [Common Pitfalls](#8-common-pitfalls)
9. [External References](#9-external-references)

---

## 1. AVG Hardware Overview

Tempest uses Atari's **Analog Vector Generator (AVG)**, a hardware state machine that reads instructions from a display list in RAM/ROM and drives X/Y deflection DACs to draw lines on a vector monitor. The AVG is a successor to the earlier DVG (Digital Vector Generator) used in Asteroids.

### Key characteristics

- **Beam-based drawing**: A single electron beam traces shapes by moving between coordinates. Lines are drawn by moving the beam with brightness > 0; repositioning is done with brightness = 0.
- **Analog integrators**: The AVG uses AM6012 12-bit DACs feeding analog integrators (op-amp + capacitor) to sweep the CRT beam. VCTR instructions load delta values into the DAC, and the integrator converts the constant rate into a linearly-changing beam position. This produces true continuous analog lines, not rasterized pixels.
- **Delta-based hardware**: The VCTR instruction specifies **relative displacement** (dx, dy) from the current beam position. The beam position is cumulative across instructions. The only absolute positioning command is CNTR (return to center).
- **Asynchronous execution**: The AVG runs independently from the 6502 CPU. The CPU builds a display list, then signals the AVG to execute it via a write to `VGSTART` ($4800). Double-buffered: one list draws while the CPU builds the next.
- **5-level subroutine stack**: JSRL/RTSL allow shape subroutines to be called from the display list, enabling shape reuse. The stack is implemented in hardware (the "Vector Generator Stack and PC Processor" gate array, designed by Dean Chang).
- **Color via COLPORT**: Tempest uses a dedicated Color Port register at `$0800`. Writing a 4-bit color index sets the color for all subsequent vectors. The CSTAT macro generates the appropriate instruction.
- **State machine driven**: The AVG's behavior is controlled by a PLA (Programmable Logic Array) that implements a state machine with 8-bit input (Run Flag + Opcode + Current State) and 4-bit next-state output. Each instruction sequences through multiple micro-steps.

### Memory map

| Range | Content |
|-------|---------|
| `$0000-$07FF` | Vector RAM (display list, double-buffered in two halves) |
| `$3000-$3FFF` | Vector ROM (ALVROM.MAC — shape definitions) |

### Key hardware registers (6502 side)

| Address | Name | Function |
|---------|------|----------|
| `$0800` | `COLPORT` | Color Port — write 4-bit color index |
| `$4800` | `VGSTART` | Start VG — any write triggers display list execution |
| `$5800` | `VGSTOP` | Stop/Reset VG — any write halts the VG |
| `$0C00` bit 6 | `MHALT` | VG Halt Status — 1 when VG is idle |

### Double buffering

The system uses double buffering to prevent visual tearing:
1. Two display list buffers exist in VECRAM (Buffer A and Buffer B)
2. While the VG reads and draws from one buffer, the 6502 builds the next frame in the other
3. A single `JMPL` instruction is rewritten to atomically switch which buffer the VG follows
4. Objects are drawn in priority order: player cursor, shots, enemies, explosions, nymphs, UI text, well structure, spikes, star field

---

## 2. AVG Instruction Set

The AVG has a small instruction set. Each instruction is 1 or 2 words (16 bits each). The opcode is encoded in the high bits of the first word.

### 2.1 VCTR — Draw Vector (variable length)

The primary drawing instruction. Encodes dx, dy, and brightness (Z).

**Long format (2 words)** — used when dx or dy exceeds ±15:

```
Word 0: [DY & $1FFF]           (13-bit signed: bit 12 = sign, bits 11-0 = magnitude)
Word 1: [Z:3][DX & $1FFF]      (3-bit brightness in bits 15-13, 13-bit signed DX)
```

Bit layout:
```
Word 0:  SYYY YYYY YYYY YYYY    S=sign of DY, Y=|DY| magnitude (12 bits)
Word 1:  0ZZZ SXXX XXXX XXXX    Z=brightness (0-7), S=sign of DX, X=|DX| (12 bits)
```

**Short format (1 word)** — used when both |dx| ≤ 15 and |dy| ≤ 15:

```
Word 0: [1][DY_sign:1][DY:2][Z:3][0][DX_sign:1][DX:2][000]
```

Bit layout:
```
Word 0:  1SYY ZZZ0 SXXO OO00    S=signs, Y/X=2-bit magnitudes, Z=brightness
```

The short vector format packs both dx, dy, and brightness into a single 16-bit word. The assembler automatically selects short vs long format based on the magnitude of dx/dy.

**Brightness Z=0 means invisible** (beam repositioning, no visible line drawn).

### 2.2 CSTAT — Set Color Status (Tempest-specific)

```
.WORD $68C0 + color_index
```

Sets the color for all subsequent vectors until the next CSTAT. Tempest's custom color circuit decodes this.

### 2.3 STAT — Set Status (generic AVG)

```
.WORD $6000 + (ZEN*$400) + (HI*$200) + (IN*$100) + (Z*$10)
```

Sets brightness and mode flags. Used less frequently than CSTAT in Tempest.

### 2.4 SCAL — Set Scale

```
.WORD $7000 + (BSCALE*$100) + LINEAR
```

Sets the binary scale factor (power of 2, 0-7) and linear scale. Affects the magnitude of subsequent VCTR displacements.

### 2.5 JSRL / RTSL — Subroutine Call / Return

```
JSRL: .WORD $A000 + (address & $1FFF) / 2
RTSL: .WORD $C000
```

JSRL pushes the return address onto the AVG's 5-level hardware stack and jumps to a shape subroutine. RTSL pops and returns. Max nesting depth is 5.

### 2.6 JMPL — Jump

```
JMPL: .WORD $E000 + (address & $1FFF) / 2
```

Unconditional jump (no stack push).

### 2.7 HALT — Stop

```
HALT: .WORD $2000
```

Stops the AVG. Placed at the end of every display list.

### 2.8 CNTR — Center

```
CNTR: .WORD $8040
```

Resets the beam position to the center of the screen.

---

## 3. Assembler Macro System

The original Tempest source uses assembler macros to generate AVG instructions. **Understanding these macros is critical** — they transform human-readable shape definitions into hardware VCTR instructions. The macros live in two files:

- **VGMC.MAC** — Low-level macros: `VCTR`, `STAT`, `JSRL`, `RTSL`, etc.
- **ALVROM.MAC** — Shape-specific macros: `ICVEC`, `CVEC`, `SCVEC`, `CALVEC`, `SCDOT`, `CSTAT`

### 3.1 ICVEC — Initialize Cumulative Vector

```asm
.MACRO ICVEC
...OLX = 0
...OLZ = 0
.ENDM
```

Resets the assembler's position-tracking variables to (0, 0). **This is an assembler-time variable, not a runtime instruction.** It tells subsequent macros that the beam starts at the origin.

### 3.2 CVEC — Cumulative Vector (core macro)

```asm
.MACRO CVEC NEWX, NEWZ, BRIT
.NARG ...NUM
...XN  = NEWX - ...OLX          ; Delta X = new position - old position
...ZN  = NEWZ - ...OLZ          ; Delta Z = new position - old position
.IIF EQ,...NUM-2 ...BR=0        ; If no brightness arg, default to 0
.IIF NE,...NUM-2 ...BR=BRIT     ; Otherwise use provided brightness
CS=1
VCTR ...XN*CS, ...ZN*CS, ...BR  ; Emit VCTR with computed DELTAS
...OLX = NEWX                   ; Update tracked position
...OLZ = NEWZ
.ENDM
```

**This is the key macro.** It takes ABSOLUTE coordinates (NEWX, NEWZ) and:
1. Computes deltas from the previously tracked position
2. Emits a VCTR instruction with those deltas
3. Updates the tracked position to the new absolute coordinates

The parameters are **absolute positions**, but the hardware instruction receives **deltas**. This distinction is the source of the most critical implementation pitfall (see [Section 4](#4-critical-absolute-vs-delta-coordinates)).

### 3.3 SCVEC — Scaled Cumulative Vector

```asm
.MACRO SCVEC ...A, ...B, ...C
.NARG ...NUM
.IIF EQ,...NUM-2 CVEC ...A*CM/CD, ...B*CM/CD
.IIF NE,...NUM-2 CVEC ...A*CM/CD, ...B*CM/CD, ...C
.ENDM
```

Applies scale factors CM (multiplier) and CD (divisor) to the coordinates, then calls CVEC. The third parameter is brightness (passed through to CVEC unchanged).

**Expansion chain**: `SCVEC a,b,c` → `CVEC(a*CM/CD, b*CM/CD, c)` → `VCTR(delta_x, delta_y, brightness)`

### 3.4 SCDOT — Scaled Dot

```asm
.MACRO SCDOT ...A, ...B
SCVEC ...A, ...B, 0     ; Move to position (invisible)
VCTR 0, 0, CB           ; Draw zero-length vector at full brightness = dot
.ENDM
```

Moves the beam to an absolute position (via SCVEC with brightness 0), then emits a zero-length VCTR with brightness CB to create a visible dot at that position. Used for player shot (DIARA2).

### 3.5 ICALVE — Initialize for CALVEC

```asm
.MACRO ICALVE
OLDX  = 0
OLDZ  = 0
.BRITE = 0
.ENDM
```

Like ICVEC but uses differently-named tracking variables (OLDX/OLDZ instead of ...OLX/...OLZ) and adds a .BRITE variable. Used exclusively for enemy shapes (Flipper, Pulsar).

### 3.6 CALVEC — Calculated Vector (enemy shapes)

```asm
.MACRO CALVEC NEWX, NEWZ
.XN  = NEWX - OLDX
.ZN  = NEWZ - OLDZ
VCTR .XN, .ZN, .BRITE
OLDX = NEWX
OLDZ = NEWZ
.ENDM
```

Like CVEC but for enemy shapes. Takes **absolute coordinates**, computes deltas, emits VCTR. The brightness is controlled by the `.BRITE` variable which can be toggled between 0 (invisible) and VARBRT (visible) to create the initial move-to followed by drawing.

### 3.7 CSTAT — Set Color

```asm
.MACRO CSTAT ...CLR
.WORD $68C0 + ...CLR
.ENDM
```

Emits a CSTAT instruction word directly. The color index is added to the base opcode `$68C0`.

---

## 4. Critical: Absolute vs Delta Coordinates

> **This is the single most important concept for implementing Tempest shapes correctly.**

### The problem

The shape data in ALVROM.MAC uses macros (SCVEC, CALVEC) whose parameters are **absolute positions**. But the AVG hardware instruction (VCTR) uses **relative deltas**. The macros bridge this gap at assembly time by computing `delta = new_position - old_position`.

### What the source code looks like

```asm
; Player ship (LIFE1)
CM=6
CD=1
LIFE1:  ICVEC                  ; Reset tracked position to (0, 0)
        SCVEC  4, -2, CB       ; ABSOLUTE position (4, -2)
        SCVEC  1, -3, CB       ; ABSOLUTE position (1, -3)
        SCVEC  3, -2, CB       ; ABSOLUTE position (3, -2)
        SCVEC  0, -1, CB       ; ABSOLUTE position (0, -1)
        SCVEC -3, -2, CB       ; ABSOLUTE position (-3, -2)
        SCVEC -1, -3, CB       ; ABSOLUTE position (-1, -3)
        SCVEC -4, -2, CB       ; ABSOLUTE position (-4, -2)
        SCVEC  0,  0, CB       ; ABSOLUTE position (0, 0) — closes the shape
```

### What the hardware receives (after macro expansion)

```
VCTR  24, -12, 7     ; Delta from (0,0) to (24,-12)       [4*6=24, -2*6=-12]
VCTR -18,  -6, 7     ; Delta from (24,-12) to (6,-18)     [1*6=6, -3*6=-18]
VCTR  12,   6, 7     ; Delta from (6,-18) to (18,-12)     [3*6=18, -2*6=-12]
VCTR -18,   6, 7     ; Delta from (18,-12) to (0,-6)      [0*6=0, -1*6=-6]
VCTR -18,  -6, 7     ; Delta from (0,-6) to (-18,-12)
VCTR  12,  -6, 7     ; Delta from (-18,-12) to (-6,-18)
VCTR -18,   6, 7     ; Delta from (-6,-18) to (-24,-12)
VCTR  24,  12, 7     ; Delta from (-24,-12) to (0,0)      — closes the loop
```

### The correct implementation

When storing SCVEC/CALVEC operands, treat them as **absolute positions**:

```gdscript
# CORRECT: Values are absolute positions
for cmd in cmds:
    var nx: float = float(cmd[0])   # Absolute X
    var ny: float = float(cmd[1])   # Absolute Y
    if draw:
        segs.append([cx, cy, nx, ny])  # Line from previous to new
    cx = nx  # Track position
    cy = ny
```

```gdscript
# WRONG: Treating values as cumulative deltas (DO NOT DO THIS)
for cmd in cmds:
    var nx: float = cx + float(cmd[0])   # Accumulated — WRONG!
    var ny: float = cy + float(cmd[1])
    ...
```

### Why this matters

With absolute interpretation, `SCVEC 1,-3` means "draw to position (1,-3)". With cumulative interpretation, it means "move by (+1,-3) from wherever you are". The shapes are completely different:

- **Player (absolute)**: Traces a closed claw shape from (0,0) through 7 vertices back to (0,0)
- **Player (cumulative)**: Traces an open downward curve from (0,0) to (0,-15) — only one side of a claw

- **Tanker (absolute)**: Two concentric diamonds with connecting spokes — the correct Tempest tanker
- **Tanker (cumulative)**: Spirals off to infinity — completely wrong

---

## 5. Color and Brightness

### 5.1 Color Constants

Defined in ALVROM.MAC lines 149-160:

| Constant | Value | Used For |
|----------|-------|----------|
| `WHITE`  | 0     | Screen boundary, enemy shots |
| `YELLOW` | 1     | Player ship, player shot outer ring |
| `PURPLE` | 2     | Tanker frame |
| `RED`    | 3     | Flipper, explosions, enemy shot dots |
| `TURQOI` | 4     | Pulsar, Tanker-Pulsar core |
| `GREEN`  | 5     | Spiker, Tanker-Fuseball core |
| `BLUE`   | 7     | Tanker-Fuseball core arm |
| `PSHCTR` | 8     | Player shot center ring |
| `PDIWHI` | 9     | Player death white |
| `PDIYEL` | 10    | Player death yellow |
| `PDIRED` | 11    | Player death red |
| `FLASH`  | 15    | Screen flash effect |

Note: Value 6 is not assigned a named constant in the source but BLUE is assigned value 7 (see source line 157). The ALCOMN.MAC common definitions also define `NYMCOL=12` (nymph/particle color) and `BLULET=7` (light blue/violet, alternate name for BLUE).

### 5.2 Color hardware

The original monochrome vector generator used a 4-bit resistor ladder DAC to control beam intensity. For color games like Tempest, Atari added a dedicated color circuit:

- **3 bits** control the RGB color channels (one bit each for Red, Green, Blue)
- **1 bit** acts as a "white boost" signal, differentiating colors like dark red vs pink or dark blue vs light blue
- The color vector CRT (Wells-Gardner WG6100 series) accepts separate RGB analog inputs, each with its own Z-amplifier
- Writing to `COLPORT` ($0800) latches the color index and applies it to all subsequent vector draws until changed
- A 10-byte Color RAM Shadow (`COLRAM`) at RAM address `$001A` maintains a software copy

### 5.3 Brightness (Z field)

The VCTR instruction's Z field is 3 bits (0-7):
- **Z=0**: Invisible — beam moves but nothing is drawn (used for repositioning)
- **Z=1 to Z=7**: Increasing brightness. Most shapes use a single brightness level set by the `CB` variable.

### 5.4 Per-shape brightness settings

```
CB=.BRITE  (LIFE1 player)     — uses .BRITE variable (context-dependent)
CB=07      (EXPL1 explosion)  — maximum brightness
CB=0E      (EXPL2 explosion)  — note: only 3 bits used, so 0E → 6
CB=1       (SPIRA1-4 spikers) — minimum visible brightness
CB=6       (ESHOT1-4 shots)   — near-maximum brightness
```

### 5.5 VARBRT — Variable Brightness

```asm
VARBRT = 1
```

Used in CALVEC shapes (Flipper, Pulsar). The `.BRITE` variable is set to 0 for the initial positioning move, then changed to VARBRT (=1) for the visible drawing strokes:

```asm
ENER11:
    ICALVE                  ; .BRITE = 0
    CALVEC -4, 4            ; Move to (-4, 4) — invisible (brightness 0)
    .BRITE = VARBRT         ; Switch to visible
    CALVEC -17., 3          ; Draw to (-17, 3) — visible (brightness 1)
    ...
    .BRITE = 0              ; Switch back to invisible
    CALVEC NXE, 0           ; Final repositioning move
```

### 5.6 NXE — End Marker

```asm
NXE = 0
```

Used as the X coordinate in the final CALVEC of Flipper/Pulsar shapes. Since NXE=0, `CALVEC NXE,0` simply means "move to (0,0)" with brightness 0. It serves as a shape terminator by repositioning the beam to the origin.

---

## 6. Shape Data Catalog

### 6.1 Coordinate systems

All shapes use a local coordinate system centered on the origin (0, 0). The assembler macros track absolute positions relative to this origin.

**Axis convention (VG hardware)**:
- X = horizontal (positive right)
- Z = vertical (positive up) — note: the source uses Z, not Y, for the vertical axis
- The macros use parameter names NEWX/NEWZ and ...A/...B

**In our GDScript implementation**, we use X/Y with Y-up matching the VG convention. The renderer flips Y for screen coordinates.

### 6.2 Scale factors (CM/CD)

Each shape section sets CM (scale multiplier) and CD (scale divisor). SCVEC applies these before passing to CVEC:

| Shape | CM | CD | Effective Scale |
|-------|----|----|-----------------|
| Player (LIFE1) | 6 | 1 | 6x |
| Explosions (EXPL1) | 1 | 1 | 1x |
| Explosions (EXPL2) | 2 | 1 | 2x |
| Explosions (EXPL3) | 4 | 1 | 4x |
| Explosions (EXPL4) | 8 | 1 | 8x |
| Spikers (SPIRA1-4) | 2 | 1 | 2x |
| Enemy shots (ESHOT1-4) | 1 | 1 | 1x |
| Tankers | inherited | inherited | (from prior context) |

**For our implementation, CM/CD scaling doesn't matter** because we normalize all shapes to max extent = 1.0. The scaling only affects the absolute magnitude, not the relative proportions.

### 6.3 Shape types

| Macro System | Used By | Coordinate Type | Brightness Control |
|-------------|---------|-----------------|-------------------|
| ICVEC + SCVEC | Player, Tanker, Spiker, Enemy Shots, Explosions | Absolute (via CVEC) | CB variable |
| ICALVE + CALVEC | Flipper (ENER11-14), Pulsar (ENER21-24) | Absolute (via CALVEC) | .BRITE variable |
| SCDOT (via SCVEC) | Player Shot (DIARA2) | Absolute (dot positions) | CB variable |

### 6.4 Shape inventory

**Player**: LIFE1 — 8 vertices forming closed claw. CSTAT YELLOW.

**Flipper (4 frames)**: ENER11-14 (aliased as CINVA1-4) — 20 CALVEC points each. Smooth curves between ~7 prominent corners. Red by default.

**Tanker (3 variants)**:
- TANKR + GENTNK (plain) — Two concentric rotated squares with connecting spokes. CSTAT PURPLE.
- TANKP + GENTNK (pulsar cargo) — Pulsar core (turquoise) + purple frame.
- TANKF + GENTNK (fuseball cargo) — Fuseball core (multi-color) + purple frame.

**Spiker (4 frames)**: SPIRA1-4 — Spiral patterns expanding outward. CSTAT GREEN.

**Fuseball (4 frames)**: FUSE0-3 — Multi-color organic shapes (RED, YELLOW, GREEN, PURPLE, TURQUOISE arms).

**Pulsar (4 frames)**: ENER21-24 — Two symmetric halves with a gap. Turquoise by default, white when pulsing.

**Enemy Shots (4 frames)**: ESHOT1-4 (via MESHO1-4 macros) — 4 white diagonal line segments + 4 red dots forming a rotating diamond pattern.

**Player Shot**: DIARA2 — Two concentric rings of dots (inner ring PSHCTR, outer ring YELLOW). Uses SCDOT macro.

---

## 7. GDScript Implementation

### 7.1 Data format

Shape data is stored in `scripts/vector_shapes.gd` as arrays of commands:

```gdscript
# Format: [x, y, draw_flag] or [x, y, draw_flag, color_index]
# x, y: ABSOLUTE coordinates (matching SCVEC/CALVEC operands)
# draw_flag: 0 = move (invisible), 1 = draw (visible line), 2 = dot
# color_index: optional, -1 or omitted = use default color
```

### 7.2 Build process

The `_build()` function converts command arrays into normalized line segments:

1. **Trace absolute positions**: Each command specifies the new absolute position. A line segment is drawn from the previous position to the new position.
2. **Center**: Compute bounding box center and shift all coordinates so the shape is centered on (0, 0).
3. **Normalize**: Divide all coordinates by the maximum extent so the shape fits in a ±0.5 unit box.

### 7.3 Rendering

`draw_shape()` transforms normalized segments into screen space using tangent/normal vectors:

```gdscript
# Shape local X → tangent (along lane edge)
# Shape local Y → normal (toward well center)
var p1 = center + (tangent * s[0] + normal * s[1]) * sz
var p2 = center + (tangent * s[2] + normal * s[3]) * sz
```

This orients shapes to align with their lane on the well, matching the original game's appearance.

### 7.4 Normal direction convention

All entity renderers must compute the normal pointing **toward the well center**:

```gdscript
var tangent: Vector2 = (right_edge - left_edge).normalized()
var normal: Vector2 = Vector2(-tangent.y, tangent.x)
if normal.dot(well.screen_center - center) < 0:
    normal = -normal
```

This ensures shapes open/face into the well consistently.

---

## 8. Common Pitfalls

### 8.1 Treating absolute coordinates as deltas

**Symptom**: Shapes spiral off into infinity, appear as random scribbles, or are dramatically larger than expected.

**Cause**: SCVEC/CALVEC operands are absolute positions, not cumulative deltas. Adding them to the running beam position double-accumulates the coordinates.

**Fix**: Use values directly as the new position: `nx = cmd[0]`, NOT `nx = cx + cmd[0]`.

### 8.2 Missing closing vertex

**Symptom**: Player shape appears open (gap between last vertex and origin).

**Cause**: LIFE1 ends with `SCVEC 0,0,CB` which draws back to origin, closing the shape. If this entry is missing from the data array, the shape has a gap.

**Fix**: Include `[0, 0, 1]` as the final entry in the player data.

### 8.3 Screen-space vs lane-oriented rendering

**Symptom**: Shapes render with fixed orientation regardless of which lane they're in. Looks wrong especially at the sides of the well.

**Cause**: Drawing shapes in screen space (using fixed X-right, Y-up) instead of transforming by the lane's tangent/normal vectors.

**Fix**: Map shape X to lane tangent, shape Y to lane normal (toward center).

### 8.4 Inconsistent normal direction

**Symptom**: Shapes face outward on some lanes, inward on others.

**Cause**: Different entity scripts computing the normal differently (some toward center, some away).

**Fix**: Always compute normal toward well center using the dot-product flip technique.

### 8.5 Mirroring shapes that are already complete

**Symptom**: Player shape appears doubled or butterfly-like.

**Cause**: LIFE1 traces a complete closed loop (right side + left side + closing segment). Applying X-axis mirroring produces a duplicate.

**Fix**: Use `_build()` not `_build_mirrored()` for the player shape. The SCVEC operands already trace the complete shape.

### 8.6 Hex vs decimal in source operands

**Symptom**: Tanker or spiker shapes have wrong proportions.

**Cause**: MAC65 assembler defaults to hex for numeric literals. Values like `20` = 0x20 = 32 decimal, `0C` = 12 decimal, `0A` = 10 decimal. The period suffix (e.g., `-17.`, `29.`) forces decimal interpretation. Values 0-9 are the same in both bases.

**Fix**: Convert all hex values to decimal when transcribing shape data:
- `20` → 32, `0A` → 10, `0B` → 11, `0C` → 12, `0E` → 14, `0F` → 15
- `10` → 16, `12` → 18, `14` → 20
- Values with period suffix are already decimal: `-17.` → -17, `29.` → 29

### 8.7 CALVEC first-move brightness

**Symptom**: Flipper/Pulsar shapes have an unwanted line from the origin to the first vertex.

**Cause**: CALVEC shapes use `.BRITE=0` for the initial positioning, then `.BRITE=VARBRT` for drawing. The first CALVEC is a move, not a draw. If marked as draw_flag=1 instead of draw_flag=0, a spurious line appears.

**Fix**: First entry in CALVEC shape data must have draw_flag=0.

---

## 9. External References

### 9.1 Primary sources

- **Original source code**: `docs/tempest-reference/source/ALVROM.MAC` (shapes), `VGMC.MAC` (VG macros), `STATE2.MAC` (VG state machine microcode)
- **Project documentation**: `docs/tempest-reference/docs/DATA_ASSETS.md` (shape catalog), `SYSTEMS.md` (architecture), `HARDWARE_REGISTERS.md` (bit encodings), `DISPLAY_COMPILER.md` (rendering pipeline)

### 9.2 Jed Margolin — "The Secret Life of Vector Generators"

Jed Margolin was the hardware engineer at Atari who designed several vector generator variants. His definitive technical write-up covers the complete hardware architecture:

- **Web**: https://jmargolin.com/vgens/vgens.htm
- **PDF**: https://www.jmargolin.com/vgens/vgens.pdf

Key topics covered:
- Evolution from DVG (Asteroids) to AVG (Tempest/Battlezone)
- AM6012 12-bit DAC design for analog beam deflection
- BIP (Bipolar) offset resistor converting unipolar DAC to bipolar output
- Analog integrator circuit (op-amp + capacitor) converting rate to position
- Sample-and-hold circuit preventing DAC glitching from reaching the monitor
- Timing details for vector drawing clock cycles
- State machine decode and execution pipeline

### 9.3 MAME source code

MAME's Tempest driver is a verified, battle-tested implementation of the AVG:

- **Tempest driver**: `src/mame/atari/tempest.cpp` — machine driver, memory map, I/O
- **AVG implementation**: `src/devices/video/avgdvg.cpp` — instruction decoder and beam simulator
- **AVG header**: `src/devices/video/avgdvg.h` — state machine definition
- **GitHub (current)**: https://github.com/mamedev/mame/blob/master/src/devices/video/avgdvg.cpp
- **GitHub (older, simpler)**: https://github.com/lantus/mame-nx/blob/master/src/vidhrdw/avgdvg.c

Key implementation details:
- VCTR long format: `op1 = DY (13-bit signed)`, `op2 = (Z << 13) | DX (13-bit signed)`
- VCTR short format: auto-selected when both |dx| and |dy| fit in 5 bits (±15)
- SCAL affects subsequent VCTR displacements via binary shift + linear scale
- The AVG state machine runs at the vector clock rate, independent of the 6502 CPU

### 9.4 Computer Archaeology

Detailed disassembly and analysis of Atari vector arcade games:

- **Asteroids DVG documentation**: https://www.computerarcheology.com/Arcade/Asteroids/DVG.html
- **Asteroids Vector ROM**: http://www.computerarcheology.com/Arcade/Asteroids/VectorROM.html

Useful for understanding the DVG predecessor and comparing instruction formats.

### 9.5 Nick Mikstas — AVG CPLD Replacement

Hardware replacement project with detailed reverse-engineering of the AVG gate array:

- **Project page**: https://nmikstas.github.io/portfolio/avgCPLD/avgCPLD.html
- **Source code**: https://github.com/nmikstas/atari-avg-replacements
- **Asteroids HDL**: https://nmikstas.github.io/portfolio/asteroidsHDL/asteroidsHDL.html

Documents the AVG's internal state machine transitions, PC sequencing (the peculiar `1, 0, 3, 2, 5, 4...` byte count pattern), and CNTR flag behavior.

### 9.6 Nick Sayer — Tempest Theory of Operation

Comprehensive Tempest-specific hardware analysis:

- **Web**: https://www.kfu.com/~nsayer/games/tempest.html

Covers Tempest-specific hardware details including the color circuit, Mathbox interface, and POKEY sound.

### 9.7 Additional resources

- **Philip Pemberton — "Hitch-Hacker's Guide to the Atari DVG"**: https://wiki.philpem.me.uk/_media/elec/vecgen/vecgen.pdf — Detailed DVG technical reference (useful for understanding the AVG's predecessor)
- **CMU ECE545 Battlezone FPGA Report**: https://course.ece.cmu.edu/~ece545/F16/reports/F15_BattleZone.pdf — Academic FPGA implementation of AVG for Battlezone, includes state machine diagrams
- **Photonaut AVG Assembler/Disassembler**: https://github.com/Photonaut/AVG-Assembler-Disassembler — Tool for assembling/disassembling AVG binary instructions
- **6502disassembly.com — Battlezone**: https://6502disassembly.com/va-battlezone/ — Annotated disassembly of a closely related AVG game
- **Sprites Mods — Black Widow FPGA VHDL**: https://spritesmods.com/?art=bwidow_fpga&page=3 — Another AVG game implemented in FPGA
- **DVG Simulator**: https://laemeur.sdf.org/dvgsim/ — Interactive DVG instruction simulator

### 9.8 DVG vs AVG comparison

For reference when consulting DVG-era documentation:

| Feature | DVG (Asteroids) | AVG (Tempest) |
|---------|-----------------|---------------|
| Drawing method | Binary Rate Multipliers (7497 chips) | Analog integrators + DACs (AM6012) |
| Vector precision | 10-bit coordinates | 13-bit signed deltas |
| Color | Monochrome only | RGB color via COLPORT |
| Scale control | Per-instruction (0-9) in VEC opcode | Separate SCAL instruction (binary + linear) |
| STAT instruction | Not present | Sets color/intensity/clipping |
| Instructions | 7 (VEC 0-9, LABS, HALT, JSR, RTS, JMP, SVEC) | 9 (VCTR, HALT, SVEC, STAT, SCAL, CNTR, JSRL, RTSL, JMPL) |
| Address space | 12-bit | 12-bit (same) |
| Stack depth | 4 levels | 5 levels |
| Absolute positioning | LABS instruction | CNTR only (return to center) |

---

## Appendix A: Complete Macro Expansion Example

Tracing the player ship shape from source to hardware instructions:

```
Source:  CM=6, CD=1, CB=07
         ICVEC                       → ...OLX=0, ...OLZ=0
         SCVEC 4,-2,CB              → CVEC(24,-12,7)        → VCTR(24,-12,7)
                                       OLX=24, OLZ=-12

         SCVEC 1,-3,CB              → CVEC(6,-18,7)         → VCTR(-18,-6,7)
                                       delta: 6-24=-18, -18-(-12)=-6
                                       OLX=6, OLZ=-18

         SCVEC 3,-2,CB              → CVEC(18,-12,7)        → VCTR(12,6,7)
                                       delta: 18-6=12, -12-(-18)=6
                                       OLX=18, OLZ=-12

         SCVEC 0,-1,CB              → CVEC(0,-6,7)          → VCTR(-18,6,7)
                                       delta: 0-18=-18, -6-(-12)=6
                                       OLX=0, OLZ=-6

         SCVEC -3,-2,CB             → CVEC(-18,-12,7)       → VCTR(-18,-6,7)
                                       delta: -18-0=-18, -12-(-6)=-6
                                       OLX=-18, OLZ=-12

         SCVEC -1,-3,CB             → CVEC(-6,-18,7)        → VCTR(12,-6,7)
                                       delta: -6-(-18)=12, -18-(-12)=-6
                                       OLX=-6, OLZ=-18

         SCVEC -4,-2,CB             → CVEC(-24,-12,7)       → VCTR(-18,6,7)
                                       delta: -24-(-6)=-18, -12-(-18)=6
                                       OLX=-24, OLZ=-12

         SCVEC 0,0,CB               → CVEC(0,0,7)           → VCTR(24,12,7)
                                       delta: 0-(-24)=24, 0-(-12)=12
                                       OLX=0, OLZ=0    ← back to origin
```

**Beam path (absolute positions after CM/CD scaling):**
```
(0,0) → (24,-12) → (6,-18) → (18,-12) → (0,-6) → (-18,-12) → (-6,-18) → (-24,-12) → (0,0)
```

This traces a closed claw/chevron shape symmetric about the Y axis. Dividing by CM=6 gives the unscaled SCVEC coordinates stored in our data arrays.

---

## Appendix B: Tanker Shape Trace (Absolute Coordinates)

The tanker (GENTNK) demonstrates the absolute coordinate system with a geometric shape:

```
Move to (32, 0)
Draw:  (32,0) → (0,32)    outer diamond edge (NW)
       (0,32) → (0,12)    spoke to inner diamond
       (0,12) → (32,0)    spoke back to outer
       (32,0) → (12,0)    spoke to inner
       (12,0) → (0,12)    inner diamond edge
       (0,12) → (-12,0)   inner diamond edge
       (-12,0) → (0,32)   spoke to outer
       (0,32) → (-32,0)   outer diamond edge (SW)
       (-32,0) → (-12,0)  spoke to inner
       (-12,0) → (0,-12)  inner diamond edge
       (0,-12) → (-32,0)  spoke to outer
       (-32,0) → (0,-32)  outer diamond edge (SE)
       (0,-32) → (0,-12)  spoke to inner
       (0,-12) → (12,0)   inner diamond edge
       (12,0) → (0,-32)   spoke to outer
       (0,-32) → (32,0)   outer diamond edge (NE)
       (32,0) → (12,0)    final spoke
```

Result: Two concentric 45-degree-rotated squares with 8 connecting spokes — the classic Tempest tanker shape.
