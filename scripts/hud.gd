extends Node2D
## HUD overlay — score, lives, high score, wave number, messages.
## Implements display routines matching original ALSCO2.MAC:
## LDRDSP (high scores), GETDSP (initials), RQRDSP (wave select),
## BOXPRO/LOGPRO (logo rainbow). See ATTRACT_MODE.md, UI.md.

# Display modes matching original display states (QDSTATE)
enum Mode {
	GAMEPLAY,     # CDPLAY — Normal score/lives/wave (INFO routine)
	WAVE_SELECT,  # CDREQRA — "Rate Yourself" skill selection (RQRDSP)
	HIGH_SCORES,  # CDHITB — High score ladder display (LDRDSP)
	INITIALS,     # CDGETI — Initials entry after game over (GETDSP)
	LOGO,         # CDBOXP/CDLOGP — BOXPRO/LOGPRO rainbow sequences
}

var mode: Mode = Mode.GAMEPLAY

# Gameplay state
var score: int = 0
var high_score: int = 0
var lives: int = 4
var wave: int = 1
var message: String = ""

# Wave select state — uses LevelData.LEVEL_TABLE indexed by cursor/hirate
# See RQRDSP: 5 visible columns, scrolling window via LEFSID/RITSID
var select_cursor: int = 0  # Currently highlighted index in LEVEL_TABLE (CURSL1)
var select_hirate: int = 0  # Max selectable index (HIRATE)
var select_timer: int = 0   # Countdown in seconds (QTMPAUS)
var select_qframe: int = 0  # For cursor flash (QFRAME)
var select_lefsid: int = 0  # Left edge of visible window (LEFSID)

# High score state
var score_table: Array[Dictionary] = []  # {score: int, initials: String}
var highlight_idx: int = -1  # Row to highlight (-1 = none, else index*3 for LDROUT glow)

# Initials entry state
var entry_initials: String = "   "  # Current 3-char initials
var entry_slot: int = 0  # Active slot (0, 1, 2)
var entry_score: int = 0  # Score being entered
var entry_char: int = 0  # Current character index
var entry_player: int = 1  # Player number (1 or 2)

# Logo state — BOXPRO/LOGPRO rainbow parameters from SCARNG
# See ALSCO2.MAC § LOGINI, BOXPRO, LOGPRO, SCARNG
var logo_phase: int = 0    # 0=BOXPRO (shrinking box), 1=LOGPRO (approaching logo)
var logo_fary: float = 0x19   # Far depth (float for smooth frame-rate animation)
var logo_neary: float = 0x18  # Near depth (float for smooth frame-rate animation)

# INSERT COINS flash state
var show_insert_coin: bool = true
var has_credits: bool = false
var attract_mode: bool = false  # When true, gameplay shows attract overlay (INFO+DSPCRD)

# --- Coordinate mapping ---
# VG coordinate system: center-origin, Y-up, range ~ ±500 at binary scale 1.
# Our viewport: 768x1024 (3:4 portrait), (0,0) top-left.
# Binary scale 0 = 2x size, scale 1 = 1x, scale 2 = 0.5x.
const SCREEN_CX: float = 384.0
const SCREEN_CY: float = 512.0

# Scale factors for text: binary scale 0 = big, 1 = normal
const SCALE_0: float = 1.6  # Big text (titles)
const SCALE_1: float = 0.8  # Normal text (body)
const LW_0: float = 2.5     # Line width for scale 0
const LW_1: float = 1.5     # Line width for scale 1

# Map a VG Y-position (signed, Y-up, relative to center) to screen Y
# binary_scale: 0 = full (2x), 1 = half (1x)
func _vg_y(vg_y: int, binary_scale: int = 1) -> float:
	var multiplier: float = 2.0 if binary_scale == 0 else 1.0
	return SCREEN_CY - float(vg_y) * multiplier

# VG X offset from center to screen X
func _vg_x(vg_x: int, binary_scale: int = 1) -> float:
	var multiplier: float = 2.0 if binary_scale == 0 else 1.0
	return SCREEN_CX + float(vg_x) * multiplier

## Map a MESS table Y byte to screen Y. See ALSCO2.MAC § MSGS, ALVGUT.MAC § VGVTR1.
## MSGS positions text at VG binary scale 1 via VGVTR1 which multiplies the signed
## byte by 4 to get VG displacement from center. The 0.82 factor accounts for the
## analog vector monitor's deflection characteristics vs our pixel viewport.
const VG_SCALE: float = 0.82
func _msgs_y(mess_byte: int) -> float:
	var signed_val: int = mess_byte if mess_byte < 0x80 else mess_byte - 0x100
	return SCREEN_CY - float(signed_val) * 4.0 * VG_SCALE

## Map a raw signed VG Y value (e.g., LDROUT TEMP3 in decimal) through VGVTR1.
func _vgvtr1_y(signed_val: int) -> float:
	return SCREEN_CY - float(signed_val) * 4.0 * VG_SCALE

## Map a MESS table X byte (signed) through VGVTR1 to screen X.
func _vgvtr1_x(signed_val: int) -> float:
	return SCREEN_CX + float(signed_val) * 4.0 * VG_SCALE


func _draw() -> void:
	match mode:
		Mode.GAMEPLAY:
			_draw_gameplay()
		Mode.WAVE_SELECT:
			_draw_wave_select()
		Mode.HIGH_SCORES:
			_draw_high_scores()
		Mode.INITIALS:
			_draw_initials_entry()
		Mode.LOGO:
			_draw_logo()


## CDPLAY — In-game HUD. See UI.md § In-Game HUD, ALSCO2.MAC § INFO/UPSCLI.
## In attract mode, INFO shows the same overlay as the high score screen
## (high score + initials, INSERT COINS/GAME OVER, copyright, bonus, credits)
## but without the score table — the well is visible behind it.
func _draw_gameplay() -> void:
	var green: Color = Colors.get_color(Colors.GREEN)
	var yellow: Color = Colors.get_color(Colors.YELLOW)
	var red: Color = Colors.get_color(Colors.RED)

	if attract_mode:
		# --- Attract mode gameplay: INFO + DSPCRD overlay ---
		# Same layout as high score screen top/bottom, no score table in middle.

		# High score + #1 initials — GREEN, centered
		if score_table.size() > 0:
			var hs_entry: Dictionary = score_table[0]
			var hs_text: String = str(hs_entry.score) + " " + hs_entry.initials
			VectorFont.draw_text_centered(self, hs_text, Vector2(SCREEN_CX, 50), green, SCALE_1, LW_1)

		# Player score — GREEN, top-left
		VectorFont.draw_text(self, str(score), Vector2(20, 30), green, SCALE_1, LW_1)

		# INSERT COINS / GAME OVER — RED, alternating
		if show_insert_coin:
			VectorFont.draw_text_centered(self, "INSERT COINS", Vector2(SCREEN_CX, _msgs_y(0x56)), red, SCALE_1, LW_1)
		else:
			VectorFont.draw_text_centered(self, "GAME OVER", Vector2(SCREEN_CX, _msgs_y(0x56)), red, SCALE_1, LW_1)

		# DSPCRD — bottom section
		_draw_dspcrd()
	else:
		# --- Normal gameplay HUD ---
		# Score — top left (Player 1 score)
		VectorFont.draw_text(self, str(score), Vector2(20, 30), green, SCALE_1, LW_1)

		# High score — top center
		VectorFont.draw_text_centered(self, str(high_score), Vector2(SCREEN_CX, 30), green, SCALE_1, LW_1)

		# Lives — top right (displayed as count)
		VectorFont.draw_text_right(self, str(lives), Vector2(748, 30), yellow, SCALE_1, LW_1)

		# Wave — bottom center
		VectorFont.draw_text_centered(self, "WAVE " + str(wave), Vector2(SCREEN_CX, 990), green, SCALE_1, LW_1)

	# Center message (GAME OVER, SUPERZAPPER RECHARGE, bonus, etc.)
	if message != "":
		VectorFont.draw_text_centered(self, message, Vector2(SCREEN_CX, SCREEN_CY), Colors.get_color(Colors.WHITE), SCALE_0, LW_0)


## RQRDSP — "Rate Yourself" wave select screen.
## See ALSCO2.MAC § RQRDSP: 5 visible columns at XPOTAB positions,
## scrolling window via LEFSID/RITSID, level numbers + hole previews + bonus.
## Messages displayed in reverse order from MSGTAB.
## Column layout: LEVEL row (numbers), HOLE row (miniature wells), BONUS row (points).
## Row labels (LEVEL, HOLE, BONUS) on far left (ASCVH prefix 0x8B = -117).

# BONPTM table from ALWELG.MAC — BCD values ×100 for display.
# 28 entries, one per LEVEL table index.
const BONUS_DISPLAY: Array[int] = [
	0, 6000, 16000, 32000, 54000, 74000, 94000, 114000, 134000,
	152000, 170000, 188000, 208000, 226000, 248000, 266000, 300000, 340000,
	382000, 415000, 439000, 472000, 531000, 581000,
	624000, 656000, 766000, 898000,
]

# Wave select X multiplier — the standard VGVTR1 multiplier (4.0 × VG_SCALE = 3.28)
# pushes ASCVH -117 labels to pixel 0, off the visible screen. The original VG hardware
# displayed on a 1024×1024 space mapped to a 3:4 portrait CRT where labels at VG X=44
# were visible. Our 768-wide viewport needs a reduced X multiplier to keep labels
# on-screen while maintaining correct column spacing proportions.
const _WS_XM: float = 2.65

# Difficulty band colors — each 16-wave band has a uniform color.
# Matches the original Tempest progression: Blue, Red, Yellow, Cyan, Green, Purple.
const BAND_COLORS: Array[int] = [6, 3, 1, 4, 5, 2]

func _ws_x(vg_signed: int) -> float:
	return SCREEN_CX + float(vg_signed) * _WS_XM

func _get_band_color(wave_num: int) -> Color:
	@warning_ignore("integer_division")
	var band: int = (wave_num - 1) / 16
	return Colors.get_color(BAND_COLORS[band % BAND_COLORS.size()])

func _draw_wave_select() -> void:
	var red: Color = Colors.get_color(Colors.RED)
	var green: Color = Colors.get_color(Colors.GREEN)
	var white: Color = Colors.get_color(Colors.WHITE)
	var turqoi: Color = Colors.get_color(Colors.TURQOI)
	var yellow: Color = Colors.get_color(Colors.YELLOW)
	var blulet: Color = Colors.get_color(Colors.BLULET)

	# Copyright at Y=0x60 via MSGEN3. See RQRDSP line 1081.
	VectorFont.draw_text_centered(self, "© MCMLXXX ATARI", Vector2(SCREEN_CX, _msgs_y(0x60)), blulet, SCALE_1, LW_1)

	# "PLAYER X" — DPLRNO: MPLAYR at Y=0x1A, scale 0, prefix 0xCD(-51).
	VectorFont.draw_text_centered(self, "PLAYER " + str(entry_player), Vector2(SCREEN_CX, _msgs_y(0x1A)), white, SCALE_0, LW_0)

	# Messages from MSGTAB in reverse order (per RQRDSP loop).
	# All positions from ALLANG.MAC MESS definitions, rendered via MSGS/VGVTR1.
	# MRATE — GREEN, scale 1, Y=10 (decimal)
	VectorFont.draw_text_centered(self, "RATE YOURSELF", Vector2(SCREEN_CX, _vgvtr1_y(10)), green, SCALE_1, LW_1)

	# MPRMOV — TURQOI, scale 1, Y=0
	VectorFont.draw_text_centered(self, "SPIN KNOB TO CHANGE", Vector2(SCREEN_CX, _vgvtr1_y(0)), turqoi, SCALE_1, LW_1)

	# MPRFIR — YELLOW, scale 1, Y=-10 (decimal)
	VectorFont.draw_text_centered(self, "PRESS FIRE TO SELECT", Vector2(SCREEN_CX, _vgvtr1_y(-10)), yellow, SCALE_1, LW_1)

	# MNOVIC — RED, scale 1, Y=-30, ASCVH prefix 0xAA (-86 signed)
	VectorFont.draw_text(self, "NOVICE", Vector2(_ws_x(-86), _vgvtr1_y(-30)), red, SCALE_1, LW_1)

	# MEXPER — RED, scale 1, Y=-30, ASCVH prefix 0x4A (+74 signed)
	VectorFont.draw_text(self, "EXPERT", Vector2(_ws_x(74), _vgvtr1_y(-30)), red, SCALE_1, LW_1)

	# Row labels — GREEN, scale 1, ASCVH prefix 0x8B (-117 signed)
	# MLEVEL Y=-40, MHOLE Y=-55, MBONUS Y=-70 (all decimal)
	var label_x: float = _ws_x(-117)
	VectorFont.draw_text(self, "LEVEL", Vector2(label_x, _vgvtr1_y(-40)), green, SCALE_1, LW_1)
	VectorFont.draw_text(self, "HOLE", Vector2(label_x, _vgvtr1_y(-55)), green, SCALE_1, LW_1)
	VectorFont.draw_text(self, "BONUS", Vector2(label_x, _vgvtr1_y(-70)), green, SCALE_1, LW_1)

	# 5 visible columns — XPOTAB: 0xBE(-66), 0xE3(-29), 0x09(+9), 0x30(+48), 0x58(+88)
	# All content centered on column X position for proper alignment.
	var xpotab: Array[int] = [-66, -29, 9, 48, 88]

	for col_idx in 5:
		var level_idx: int = select_lefsid + col_idx
		if level_idx < 0 or level_idx > select_hirate:
			continue
		if level_idx >= LevelData.LEVEL_TABLE.size():
			continue

		var level_num: int = LevelData.LEVEL_TABLE[level_idx]
		if level_num > 99:
			continue

		var is_selected: bool = (level_idx == select_cursor)
		var col_cx: float = _ws_x(xpotab[col_idx])
		var band_color: Color = _get_band_color(level_num)

		# Level number — band color (WHITE if selected), centered on column
		var lvl_y: float = _vgvtr1_y(-40)
		var num_color: Color = white if is_selected else band_color
		VectorFont.draw_text_centered(self, str(level_num), Vector2(col_cx, lvl_y), num_color, SCALE_1, LW_1)

		# Hole preview — miniature well shape, Y=-52 (0xCC), centered on column
		# See ALDISP.MAC § DSPHOL: draws well outline at VG binary scale 5.
		var hole_y: float = _vgvtr1_y(-52)
		_draw_well_preview(level_num, Vector2(col_cx, hole_y), band_color)

		# Bonus — RED, Y=-70, centered on column
		var bonus_y: float = _vgvtr1_y(-70)
		var bonus_idx: int = mini(level_idx, BONUS_DISPLAY.size() - 1)
		var bonus_str: String = str(BONUS_DISPLAY[bonus_idx])
		VectorFont.draw_text_centered(self, bonus_str, Vector2(col_cx, bonus_y), red, SCALE_1, LW_1)

		# Selection box — WHITE, encompasses LEVEL/HOLE/BONUS rows.
		# BOXTAB: 26 wide × 28 tall in VGVTR1 units, centered on column.
		if is_selected:
			var box_hw: float = 13.0 * _WS_XM  # Half-width (BOXTAB 26/2)
			var box_top: float = lvl_y - 8.0
			var box_bot: float = bonus_y + 16.0
			draw_rect(Rect2(col_cx - box_hw, box_top, box_hw * 2.0, box_bot - box_top), white, false, 1.5)

	# TIME — GREEN, Y=0x98, centered with timer value
	var time_y: float = _msgs_y(0x98)
	var time_str: String = "TIME " + (str(select_timer) if select_timer >= 0 else "")
	VectorFont.draw_text_centered(self, time_str, Vector2(SCREEN_CX, time_y), green, SCALE_1, LW_1)


## Draw miniature well shape preview for RQRDSP HOLE row.
## See ALDISP.MAC § DSPHOL: draws well outline at VG binary scale 5 (1/32).
## Uses LINEX/LINEZ vertices, adjusted from unsigned (center=0x80) to signed.
func _draw_well_preview(wave_num: int, center: Vector2, override_color: Color = Color(-1, -1, -1)) -> void:
	var shape_data: Dictionary = LevelData.get_well_data(wave_num)
	var linex: Array = shape_data.linex
	var linez: Array = shape_data.linez
	var planar: bool = shape_data.planar
	# VG scale 5 = 4/(2^5) = 0.125 per unit. With VG_SCALE ≈ 0.1 per unit.
	var preview_scale: float = 0.13
	var color: Color = override_color if override_color.r >= 0.0 else Colors.get_well_color(wave_num)

	var points: Array[Vector2] = []
	for i in 16:
		var sx: float = (float(linex[i]) - 128.0) * preview_scale
		var sz: float = (float(linez[i]) - 128.0) * preview_scale
		points.append(center + Vector2(sx, -sz))

	var num_segments: int = 15 if planar else 16
	for i in num_segments:
		var next_idx: int = (i + 1) % 16
		draw_line(points[i], points[next_idx], color, 1.0)


## CDHITB — High score table ("Ladder"). See ALSCO2.MAC § LDRDSP/LDROUT.
## LDRDSP calls INFO first (score/lives/insert coins), then LDROUT (table).
## LDROUT: MHIGHS at Y=0x38 scale 0, entries at TEMP3=40 to -30 (step -10),
## X=0xD0(-48 signed). DSPCRD draws copyright, bonus interval, credits, coin mode.
##
## MESS table Y values are HEX bytes (assembler default radix) passed through
## VGVTR1 which multiplies by 4. Values ≥ 0x80 are negative signed bytes.
## ALLANG.MAC message definitions:
##   MHIGHS: RED, scale 0, Y=0x38 (+56, VGVTR1→+224)
##   MINSER: RED, scale 1, Y=0x56 (+86, VGVTR1→+344)
##   MATARI: BLULET, scale 1, Y=0x92 (-110 signed, VGVTR1→-440)
##   MBOLIF: TURQOI, scale 1, Y=0x89 (-119 signed, VGVTR1→-476)
##   MCREDI: GREEN, scale 1, Y=0x80 (-128 signed, VGVTR1→-512)
##   MCMOD2: GREEN, scale 1, Y=0x80 (-128 signed, VGVTR1→-512)
func _draw_high_scores() -> void:
	var red: Color = Colors.get_color(Colors.RED)
	var green: Color = Colors.get_color(Colors.GREEN)
	var blulet: Color = Colors.get_color(Colors.BLULET)
	var white: Color = Colors.get_color(Colors.WHITE)
	var turqoi: Color = Colors.get_color(Colors.TURQOI)

	# --- INFO section (top of screen) ---
	# See ALSCO2.MAC § INFO: displays score/lives in attract mode, flashing INSERT COINS.
	# In attract mode, INFO shows: high score + #1 initials at top, player score at left.

	# High score + #1 initials — GREEN, scale 1, top area
	# SCORES template (ALVROM.MAC): CSTAT GREEN, positioned via VCTR -30,30 from lives.
	# VG offset dy=+364 from center → screen Y ≈ 148. High score at VG Y ≈ +396 → screen Y ≈ 116.
	# No "HIGH SCORE" text label — just raw digits + initials (INFO doesn't call MHIGHS).
	if score_table.size() > 0:
		var hs_entry: Dictionary = score_table[0]
		var hs_text: String = str(hs_entry.score) + " " + hs_entry.initials
		VectorFont.draw_text_centered(self, hs_text, Vector2(SCREEN_CX, 50), green, SCALE_1, LW_1)

	# Player 1 score — GREEN, top-left (same position as gameplay HUD)
	# SCORES template: VCTR -1C0,16C from center → screen X≈64, Y≈148
	VectorFont.draw_text(self, str(score), Vector2(20, 30), green, SCALE_1, LW_1)

	# INSERT COINS / GAME OVER — RED, scale 1, Y=0x56 (centered, alternating)
	# Original INFO routine: D2GAME flashes INSERT COINS, DGOVER shows GAME OVER.
	# In attract mode, these alternate on a 32-frame cycle (QFRAME & 0x1F < 0x10).
	# If message is set (e.g., "PRESS START"), it replaces both at the same Y.
	if message == "":
		if show_insert_coin:
			VectorFont.draw_text_centered(self, "INSERT COINS", Vector2(SCREEN_CX, _msgs_y(0x56)), red, SCALE_1, LW_1)
		else:
			VectorFont.draw_text_centered(self, "GAME OVER", Vector2(SCREEN_CX, _msgs_y(0x56)), red, SCALE_1, LW_1)

	# --- LDROUT: High score table ---

	# "HIGH SCORES" — RED, binary scale 0 (big), Y=0x38
	# MSGS positions at scale 1 via VGVTR1, then renders text at scale 0 (2x size).
	VectorFont.draw_text_centered(self, "HIGH SCORES", Vector2(SCREEN_CX, _msgs_y(0x38)), red, SCALE_0, LW_0)

	# Score entries — LDROUT loop: 8 entries (NHISCO)
	# TEMP3 starts at 40. (decimal), decrements by 10. per row → 40,30,20,10,0,-10,-20,-30
	# Colors: BLULET default, WHITE for glowing entry (SZL match)
	# Format: rank space initials spaces score — centered on screen
	var temp3: int = 40  # Decimal, per LDROUT: "LDA I,40."

	for i in range(score_table.size()):
		var entry: Dictionary = score_table[i]
		var row_color: Color = white if (i == highlight_idx) else blulet
		var row_y: float = _vgvtr1_y(temp3)

		var rank_str: String = str(i + 1)
		var ini: String = entry.initials if entry.initials.strip_edges() != "" else "   "
		var sc_str: String = str(entry.score) if entry.score > 0 else "0"

		# Build formatted row: "N  INI    SCORE" centered on screen
		var row_text: String = rank_str + " " + ini + "    " + sc_str
		VectorFont.draw_text_centered(self, row_text, Vector2(SCREEN_CX, row_y), row_color, SCALE_1, LW_1)

		temp3 -= 10  # "SBC I,10." — decimal 10

	# DSPCRD: Bottom info section
	_draw_dspcrd()

	# Optional message overlay (e.g., "PRESS START" after game over)
	if message != "":
		VectorFont.draw_text_centered(self, message, Vector2(SCREEN_CX, _msgs_y(0x56)), red, SCALE_1, LW_1)


## CDGETI — "Enter Your Initials" screen. See ALSCO2.MAC § GETDSP.
## "PLAYER X" at Y=0xC0 (via MSGEN3), "ENTER YOUR INITIALS" at default Y=0xB0,
## "SPIN KNOB TO CHANGE" at Y=0xA6, "PRESS FIRE TO SELECT" at Y=0x9C,
## Atari copyright via MSGS, then falls into LDROUT for high score table.
func _draw_initials_entry() -> void:
	var red: Color = Colors.get_color(Colors.RED)
	var white: Color = Colors.get_color(Colors.WHITE)
	var turqoi: Color = Colors.get_color(Colors.TURQOI)
	var yellow: Color = Colors.get_color(Colors.YELLOW)
	var blulet: Color = Colors.get_color(Colors.BLULET)

	# "PLAYER" at Y=0xC0 (MSGEN3 override), scale 0 (big), WHITE
	# 0xC0 signed = -64, so this goes below center
	# Actually 0xC0 unsigned = 192 → high on screen
	VectorFont.draw_text_centered(self, "PLAYER " + str(entry_player), Vector2(SCREEN_CX, _vg_y(0x38, 0)), white, SCALE_0, LW_0)

	# "ENTER YOUR INITIALS" — RED, scale 1, Y=0xB0=176 → upper area
	VectorFont.draw_text_centered(self, "ENTER YOUR INITIALS", Vector2(SCREEN_CX, _vg_y(30)), red, SCALE_1, LW_1)

	# Current initials display — large, centered, with active slot highlighted
	var init_y: float = _vg_y(10)
	var init_total_w: float = VectorFont.measure_text("A A A", SCALE_0)
	var init_start_x: float = SCREEN_CX - init_total_w / 2.0
	var char_w: float = VectorFont.measure_text("A", SCALE_0)
	var space_w: float = VectorFont.measure_text(" ", SCALE_0)

	for i in 3:
		var ch: String = entry_initials[i] if i < entry_initials.length() else " "
		var slot_x: float = init_start_x + float(i) * (char_w + space_w)
		var is_active: bool = (i == entry_slot)
		var c: Color = white if is_active else blulet
		VectorFont.draw_text(self, ch, Vector2(slot_x, init_y), c, SCALE_0, LW_0)
		# Underline active slot
		if is_active:
			var uw: float = char_w
			draw_line(Vector2(slot_x, init_y + 4), Vector2(slot_x + uw, init_y + 4), white, 2.0)

	# "SPIN KNOB TO CHANGE" — TURQOI, scale 1, Y=0 (PRMOV)
	VectorFont.draw_text_centered(self, "SPIN KNOB TO CHANGE", Vector2(SCREEN_CX, _vg_y(-10)), turqoi, SCALE_1, LW_1)

	# "PRESS FIRE TO SELECT" — YELLOW, scale 1, Y=-10 (PRFIR)
	VectorFont.draw_text_centered(self, "PRESS FIRE TO SELECT", Vector2(SCREEN_CX, _vg_y(-20)), yellow, SCALE_1, LW_1)

	# Atari copyright — BLULET, scale 1
	VectorFont.draw_text_centered(self, "© MCMLXXX ATARI", Vector2(SCREEN_CX, _vg_y(0x92)), blulet, SCALE_1, LW_1)

	# High score table below (GETDSP falls into LDROUT)
	# Draw compact version of the ladder with the new entry glowing
	var temp3: int = -35
	for i in range(score_table.size()):
		var entry: Dictionary = score_table[i]
		var row_color: Color = white if (i == highlight_idx) else blulet
		var row_y: float = _vg_y(temp3)
		var row_x: float = _vg_x(-48)

		var rank_str: String = str(i + 1) + "."
		var ini: String = entry.initials if entry.initials.strip_edges() != "" else "   "
		# Zero-suppressed score display per original NWHEXZ routine
		var sc_str: String = str(entry.score) if entry.score > 0 else "0"

		var x_cursor: float = row_x
		x_cursor += VectorFont.draw_text(self, rank_str, Vector2(x_cursor, row_y), row_color, SCALE_1 * 0.8, LW_1)
		x_cursor += VectorFont.draw_text(self, " ", Vector2(x_cursor, row_y), row_color, SCALE_1 * 0.8, LW_1)
		x_cursor += VectorFont.draw_text(self, ini, Vector2(x_cursor, row_y), row_color, SCALE_1 * 0.8, LW_1)
		x_cursor += VectorFont.draw_text(self, " ", Vector2(x_cursor, row_y), row_color, SCALE_1 * 0.8, LW_1)
		VectorFont.draw_text(self, sc_str, Vector2(x_cursor, row_y), row_color, SCALE_1 * 0.8, LW_1)

		temp3 -= 8


## CDBOXP / CDLOGP — Logo presentation. See ALSCO2.MAC § BOXPRO, LOGPRO, SCARNG.
## Phase 0 (BOXPRO): Rainbow trail of VORBOX (screen boundary rectangle)
##   at multiple depths. FARY increases from 0x19→0xA0, NEARY follows.
## Phase 1 (LOGPRO): Rainbow trail of TEMPEST text logo (VORLIT/TEMLIT)
##   approaching the viewer. NEARY decreases, FARY follows.
## SCARNG: Loops from NEARY to FARY stepping by 2, drawing shape at each depth.
##   Leading point = WHITE, trailing points = color cycling (INDEX>>3)&7.
func _draw_logo() -> void:
	if logo_phase == 0:
		_draw_scarng_box()
	else:
		_draw_scarng_logo()

	# Atari copyright — always shown during logo. See SCARNG: MSGEN3 at Y=0xD0 (-48 signed)
	# Original displays "© MCMLXXX ATARI" via MATARI message in ALLANG.MAC.
	# SCARNG does NOT call INFO, so no INSERT COINS during logo phase.
	var blulet: Color = Colors.get_color(Colors.BLULET)
	VectorFont.draw_text_centered(self, "© MCMLXXX ATARI", Vector2(SCREEN_CX, _vg_y(-48)), blulet, SCALE_1, LW_1)


## SCARNG for VORBOX — Draw rainbow trail of screen boundary rectangle.
## VORBOX: rectangle from (-500,-540) to (500,540) at scale (1,0).
## Each depth INDEX from NEARY to FARY (step 2):
##   scale_factor = 2^(-INDEX>>5) * (128 - (INDEX<<2)&0x7F) / 128
##   color: leading = WHITE, trailing = (INDEX>>3)&7 with 7→RED
func _draw_scarng_box() -> void:
	var center: Vector2 = Vector2(SCREEN_CX, SCREEN_CY)  # VG CNTR = screen center
	# Base rectangle half-size (VORBOX: ±500 x ±540 in VG units at scale 1)
	var base_w: float = 500.0
	var base_h: float = 540.0

	var neary_i: int = int(logo_neary)
	var fary_i: int = int(logo_fary)
	var idx: int = neary_i
	while idx <= fary_i:
		var sf: float = _scarng_scale(idx)
		var color: Color = _scarng_color(idx, neary_i)
		var hw: float = base_w * sf
		var hh: float = base_h * sf
		# Draw rectangle at this scale
		var tl: Vector2 = center + Vector2(-hw, -hh)
		var br: Vector2 = center + Vector2(hw, hh)
		draw_rect(Rect2(tl, br - tl), color, false, 1.5)
		idx += 2


## SCARNG for VORLIT — Draw rainbow trail of TEMPEST text logo.
## VORLIT letters: T E M P E S T, drawn at multiple depths.
## Each depth uses same scale/color logic as SCARNG box.
func _draw_scarng_logo() -> void:
	var center: Vector2 = Vector2(SCREEN_CX, SCREEN_CY)  # VG CNTR = screen center

	var neary_i: int = int(logo_neary)
	var fary_i: int = int(logo_fary)
	var idx: int = neary_i
	while idx <= fary_i:
		var sf: float = _scarng_scale(idx)
		var color: Color = _scarng_color(idx, neary_i)
		_draw_tempest_text(center, sf, color)
		idx += 2


## Draw the stylized "TEMPEST" logo using exact VORLIT vector shape data.
## Traced from ALVROM.MAC: VORLIT/TEMLIT subroutine with T,E,M,P,E,S,T letters.
## Each entry: [dx, dy, draw] in VG units (hex→decimal). Y-up in VG, negated for Godot.
## Shape bounding box: X[-512, 534], Y[256, 384]. Center: (11, 320).
const VORLIT_STROKES: Array = [
	# Initial position from CNTR origin — VCTR -1B0,100,0
	[-432, 256, false],
	# === T (first) ===
	[0, 128, true],        # vertical stem up
	[-80, 0, false],       # position crossbar left
	[160, 0, true],        # crossbar right
	# T→E spacing
	[96, 0, false],
	# === E (first) ===
	[-80, 0, true],        # top horizontal left
	[-20, -64, true],      # diagonal to middle
	[112, 0, true],        # middle horizontal right
	[-112, 0, false],      # back left (invisible)
	[-20, -64, true],      # diagonal to bottom
	[132, 0, true],        # bottom horizontal right
	# E→M spacing
	[36, 0, false],
	# === M ===
	[-32, 0, true],        # left serif
	[48, 128, true],       # left diagonal up
	[16, 0, true],         # left peak top
	[32, -88, true],       # inner diagonal down
	[32, 88, true],        # inner diagonal up
	[16, 0, true],         # right peak top
	[48, -128, true],      # right diagonal down
	[-32, 0, true],        # right serif
	# M→P spacing
	[52, 0, false],
	# === P ===
	[-16, 0, true],        # serif
	[0, 128, true],        # vertical stem up
	[92, 0, true],         # top horizontal right
	[26, -72, true],       # bowl right side
	[-118, 0, true],       # bowl bottom left
	# P→E2 spacing — VCTR 0F8,48,0
	[248, 72, false],
	# === E (second) ===
	[-80, 0, true],
	[-20, -64, true],
	[112, 0, true],
	[-112, 0, false],
	[-20, -64, true],
	[132, 0, true],
	# E2→S spacing
	[22, 40, false],
	# === S ===
	[-16, -40, true],      # initial diagonal
	[144, 0, true],        # bottom horizontal
	[0, 56, true],         # right vertical up
	[-112, 32, true],      # middle diagonal left-up
	[16, 40, true],        # upper diagonal right-up
	[100, 0, true],        # top horizontal right
	[-12, -32, true],      # ending diagonal
	# S→T2 spacing
	[96, -96, false],
	# === T (final) — JMPL T ===
	[0, 128, true],
	[-80, 0, false],
	[160, 0, true],
]
func _draw_tempest_text(cntr: Vector2, sf: float, color: Color) -> void:
	if sf < 0.001:
		return
	var lw: float = clampf(sf * 3.0, 0.5, 3.0)
	# Beam starts at CNTR position (screen center). The shape's own VCTR moves
	# handle all positioning — SCARNG SCAL applies to everything including the
	# initial (-432, +256) offset from center. See ALVROM.MAC VORLIT.
	var beam: Vector2 = cntr
	for stroke in VORLIT_STROKES:
		var dx: float = float(stroke[0]) * sf
		var dy: float = float(stroke[1]) * sf
		var new_beam: Vector2 = beam + Vector2(dx, -dy)  # Negate Y for Godot
		if stroke[2]:
			draw_line(beam, new_beam, color, lw)
		beam = new_beam


## SCARNG scale computation. See ALSCO2.MAC § SCARNG.
## Original VG hardware: binary = INDEX>>5, linear = (INDEX<<2)&0x7F.
## VGSCAL sets AVG SCAL instruction: binary determines power-of-2 base size,
## linear interpolates within each binary step (128=full, 0=nearly zero).
## The 2x base multiplier matches our _vg_y mapping (binary_scale 0 = 2 pixels/unit).
## The formula has 16x discontinuities at binary boundaries (every 32 indices)
## which were masked by analog CRT phosphor persistence on the original hardware.
func _scarng_scale(idx: int) -> float:
	var binary: int = idx >> 5
	var linear: int = (idx << 2) & 0x7F
	return maxf(2.0 * pow(2.0, -binary) * float(128 - linear) / 128.0, 0.0001)


## SCARNG color computation. See ALSCO2.MAC § SCARNG.
## Leading point (idx == neary) = WHITE.
## Others: color_idx = (idx >> 3) & 7, with 7 (black) replaced by RED.
## Color indices: 0=WHITE, 1=YELLOW, 2=PURPLE, 3=RED, 4=TURQOI, 5=GREEN, 6=BLUE, 7→RED
func _scarng_color(idx: int, neary: int) -> Color:
	if idx == neary:
		return Colors.get_color(Colors.WHITE)
	var color_idx: int = (idx >> 3) & 7
	if color_idx == 7:
		color_idx = Colors.RED  # Replace black with RED
	return Colors.get_color(color_idx)


## INSERT COINS / PRESS START prompt. See UI.md § 1.6.
## Flash logic: QFRAME & 0x1F < 0x10 → visible; else invisible.
## 32-frame cycle at 60Hz display rate.
func _draw_coin_prompt() -> void:
	var prompt_y: float = _vg_y(0x56)  # MESS INSER/PRESS: Y=0x56, binary_scale=1
	if has_credits:
		# Static "PRESS START"
		VectorFont.draw_text_centered(self, "PRESS START", Vector2(SCREEN_CX, prompt_y), Colors.get_color(Colors.RED), SCALE_1, LW_1)
	elif show_insert_coin:
		# Flashing "INSERT COINS"
		VectorFont.draw_text_centered(self, "INSERT COINS", Vector2(SCREEN_CX, prompt_y), Colors.get_color(Colors.RED), SCALE_1, LW_1)


## DSPCRD — Bottom info section. Called by INFO in attract mode and high score screens.
## Draws copyright, bonus interval, credits count, coin mode.
## See ALSCO2.MAC § DSPCRD.
func _draw_dspcrd() -> void:
	var blulet: Color = Colors.get_color(Colors.BLULET)
	var green: Color = Colors.get_color(Colors.GREEN)
	var turqoi: Color = Colors.get_color(Colors.TURQOI)

	# MATARI — "© MCMLXXX ATARI", BLULET, scale 1, Y=0x92
	VectorFont.draw_text_centered(self, "© MCMLXXX ATARI", Vector2(SCREEN_CX, _msgs_y(0x92)), blulet, SCALE_1, LW_1)

	# BOLOUT — "BONUS EVERY  20000", TURQOI (cyan), scale 1, Y=0x89
	VectorFont.draw_text_centered(self, "BONUS EVERY  20000", Vector2(SCREEN_CX, _msgs_y(0x89)), turqoi, SCALE_1, LW_1)

	# MCREDI — "CREDITS  0", GREEN, scale 1, Y=0x80 (left-aligned)
	# MCMOD2 — "1 COIN 1 PLAY", GREEN, scale 1, Y=0x80 (right side)
	var credits_y: float = _msgs_y(0x80)
	VectorFont.draw_text(self, "CREDITS  0", Vector2(70, credits_y), green, SCALE_1, LW_1)
	VectorFont.draw_text_right(self, "1 COIN 1 PLAY", Vector2(700, credits_y), green, SCALE_1, LW_1)


# --- Public API ---

func update_display(new_score: int, new_lives: int, new_wave: int, qframe: int = 0) -> void:
	score = new_score
	lives = new_lives
	wave = new_wave
	if score > high_score:
		high_score = score
	# Update INSERT COINS flash for attract mode gameplay
	show_insert_coin = (qframe & 0x1F) < 0x10
	queue_redraw()


func set_message(msg: String) -> void:
	message = msg
	queue_redraw()


func show_gameplay(is_attract: bool = false, hs_table: Array[Dictionary] = []) -> void:
	mode = Mode.GAMEPLAY
	attract_mode = is_attract
	if hs_table.size() > 0:
		score_table = hs_table
	queue_redraw()


## Show wave select screen. See RQRDSP.
func show_wave_select(cursor: int, max_idx: int, timer: int, qframe: int, lefsid: int = 0, player: int = 1) -> void:
	mode = Mode.WAVE_SELECT
	select_cursor = cursor
	select_hirate = max_idx
	select_timer = timer
	select_qframe = qframe
	select_lefsid = lefsid
	entry_player = player
	# Flash INSERT COINS based on qframe
	show_insert_coin = (qframe & 0x1F) < 0x10
	queue_redraw()


func show_high_scores(table: Array[Dictionary], highlight: int = -1, msg: String = "", qframe: int = 0) -> void:
	mode = Mode.HIGH_SCORES
	score_table = table
	highlight_idx = highlight
	message = msg
	# Flash INSERT COINS based on qframe (32-frame cycle at 60Hz → ~5 ticks at 20Hz)
	show_insert_coin = (qframe & 0x1F) < 0x10
	queue_redraw()


func show_initials_entry(table: Array[Dictionary], initials: String, slot: int,
		sc: int, highlight: int, char_idx: int, player: int = 1) -> void:
	mode = Mode.INITIALS
	score_table = table
	entry_initials = initials
	entry_slot = slot
	entry_score = sc
	highlight_idx = highlight
	entry_char = char_idx
	entry_player = player
	queue_redraw()


## Show logo screen with BOXPRO/LOGPRO rainbow parameters.
## See ALSCO2.MAC § LOGINI: FARY/NEARY control the rainbow depth range.
## phase: 0=BOXPRO (shrinking box), 1=LOGPRO (approaching logo)
func show_logo(phase: int, fary: float, neary: float, qframe: int = 0) -> void:
	mode = Mode.LOGO
	logo_phase = phase
	logo_fary = fary
	logo_neary = neary
	# Flash INSERT COINS based on qframe
	show_insert_coin = (qframe & 0x1F) < 0x10
	queue_redraw()
