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
var logo_phase: int = 0  # 0=BOXPRO (shrinking box), 1=LOGPRO (approaching logo)
var logo_fary: int = 0x19   # Far depth (increases in BOXPRO, decreases in LOGPRO)
var logo_neary: int = 0x18  # Near depth (increases in BOXPRO, decreases in LOGPRO)

# INSERT COIN flash state
var show_insert_coin: bool = true
var has_credits: bool = false

# --- Coordinate mapping ---
# VG coordinate system: center-origin, Y-up, range ~ ±500 at binary scale 1.
# Our viewport: 1024x1024, (0,0) top-left.
# Binary scale 0 = 2x size, scale 1 = 1x, scale 2 = 0.5x.
const SCREEN_CX: float = 512.0
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
## Layout: P1 score top-left, high score top-center, lives top-right.
func _draw_gameplay() -> void:
	var green: Color = Colors.get_color(Colors.GREEN)
	var yellow: Color = Colors.get_color(Colors.YELLOW)

	# Score — top left (Player 1 score)
	VectorFont.draw_text(self, str(score), Vector2(20, 30), green, SCALE_1, LW_1)

	# High score — top center
	VectorFont.draw_text_centered(self, str(high_score), Vector2(SCREEN_CX, 30), green, SCALE_1, LW_1)

	# Lives — top right (displayed as count)
	VectorFont.draw_text_right(self, str(lives), Vector2(1000, 30), yellow, SCALE_1, LW_1)

	# Wave — bottom center
	VectorFont.draw_text_centered(self, "WAVE " + str(wave), Vector2(SCREEN_CX, 990), green, SCALE_1, LW_1)

	# Center message (GAME OVER, SUPERZAPPER RECHARGE, bonus, etc.)
	if message != "":
		VectorFont.draw_text_centered(self, message, Vector2(SCREEN_CX, SCREEN_CY), Colors.get_color(Colors.WHITE), SCALE_0, LW_0)


## RQRDSP — "Rate Yourself" wave select screen.
## See ALSCO2.MAC § RQRDSP: 5 visible columns at XPOTAB positions,
## scrolling window via LEFSID/RITSID, level numbers + bonus + well preview.
## Messages displayed in reverse order from MSGTAB.
func _draw_wave_select() -> void:
	var red: Color = Colors.get_color(Colors.RED)
	var green: Color = Colors.get_color(Colors.GREEN)
	var white: Color = Colors.get_color(Colors.WHITE)
	var turqoi: Color = Colors.get_color(Colors.TURQOI)
	var yellow: Color = Colors.get_color(Colors.YELLOW)
	var blulet: Color = Colors.get_color(Colors.BLULET)

	# Atari copyright at Y=0x60=96 (MSGEN3 with A=0x60). See RQRDSP.
	VectorFont.draw_text_centered(self, "MCMLXXX ATARI", Vector2(SCREEN_CX, _vg_y(0x60)), blulet, SCALE_1, LW_1)

	# "PLAYER 1" — drawn by DPLRNO
	VectorFont.draw_text_centered(self, "PLAYER " + str(entry_player), Vector2(SCREEN_CX, _vg_y(0x1A, 0)), white, SCALE_0, LW_0)

	# Messages from MSGTAB in reverse order (per RQRDSP loop):
	# RATE YOURSELF — GREEN, scale 1, Y=10
	VectorFont.draw_text_centered(self, "RATE YOURSELF", Vector2(SCREEN_CX, _vg_y(10)), green, SCALE_1, LW_1)

	# SPIN KNOB TO CHANGE — TURQOI, scale 1, Y=0
	VectorFont.draw_text_centered(self, "SPIN KNOB TO CHANGE", Vector2(SCREEN_CX, _vg_y(0)), turqoi, SCALE_1, LW_1)

	# PRESS FIRE TO SELECT — YELLOW, scale 1, Y=-10
	VectorFont.draw_text_centered(self, "PRESS FIRE TO SELECT", Vector2(SCREEN_CX, _vg_y(-10)), yellow, SCALE_1, LW_1)

	# NOVICE — RED, scale 1, Y=-30
	VectorFont.draw_text_centered(self, "NOVICE", Vector2(SCREEN_CX - 120, _vg_y(-30)), red, SCALE_1, LW_1)

	# EXPERT — RED, scale 1, Y=-30
	VectorFont.draw_text_centered(self, "EXPERT", Vector2(SCREEN_CX + 120, _vg_y(-30)), red, SCALE_1, LW_1)

	# LEVEL label — GREEN, scale 1, Y=-40
	VectorFont.draw_text_centered(self, "LEVEL", Vector2(SCREEN_CX, _vg_y(-40)), green, SCALE_1, LW_1)

	# 5 visible columns of level numbers
	# XPOTAB: 0xBE, 0xE3, 0x09, 0x30, 0x58 — signed X offsets from center
	# 0xBE = -66, 0xE3 = -29, 0x09 = 9, 0x30 = 48, 0x58 = 88
	var xpotab: Array[int] = [-66, -29, 9, 48, 88]

	# Visible range: 5 columns starting at select_lefsid
	for col_idx in 5:
		var level_idx: int = select_lefsid + col_idx
		if level_idx < 0 or level_idx > select_hirate:
			continue
		if level_idx >= LevelData.LEVEL_TABLE.size():
			continue

		var level_num: int = LevelData.LEVEL_TABLE[level_idx]
		if level_num > 99:
			continue

		var col_x: float = SCREEN_CX + float(xpotab[col_idx]) * 2.5

		# Level number — GREEN at Y offset for levels
		var is_selected: bool = (level_idx == select_cursor)
		var num_color: Color = white if is_selected else green
		VectorFont.draw_text_centered(self, str(level_num), Vector2(col_x, _vg_y(-55)), num_color, SCALE_1, LW_1)

		# Selection box around current level — WHITE
		if is_selected:
			var box_cx: float = col_x
			var box_cy: float = _vg_y(-55) + 6.0
			var bw: float = 30.0
			var bh: float = 24.0
			draw_rect(Rect2(box_cx - bw/2, box_cy - bh/2, bw, bh), white, false, 1.5)

	# BONUS label — GREEN, scale 1, Y=-70
	VectorFont.draw_text_centered(self, "BONUS", Vector2(SCREEN_CX, _vg_y(-70)), green, SCALE_1, LW_1)

	# Bonus points for each visible column
	# WAVE_BONUS table: [0, 60, 160, 320, 540, 740, 940, 1140, 1340]
	var wave_bonus: Array[int] = [0, 60, 160, 320, 540, 740, 940, 1140, 1340]
	for col_idx in 5:
		var level_idx: int = select_lefsid + col_idx
		if level_idx < 0 or level_idx > select_hirate:
			continue
		if level_idx >= LevelData.LEVEL_TABLE.size():
			continue
		var col_x: float = SCREEN_CX + float(xpotab[col_idx]) * 2.5
		var bonus_idx: int = mini(level_idx, wave_bonus.size() - 1)
		VectorFont.draw_text_centered(self, str(wave_bonus[bonus_idx]), Vector2(col_x, _vg_y(-85)), red, SCALE_1 * 0.7, LW_1)

	# TIME display — GREEN, scale 1, Y=0x98=152
	VectorFont.draw_text_centered(self, "TIME", Vector2(SCREEN_CX - 60, _vg_y(-110)), green, SCALE_1, LW_1)
	if select_timer >= 0:
		VectorFont.draw_text(self, str(select_timer), Vector2(SCREEN_CX + 30, _vg_y(-110)), green, SCALE_1, LW_1)

	# INSERT COIN / PRESS START at bottom
	_draw_coin_prompt()


## CDHITB — High score table ("Ladder"). See ALSCO2.MAC § LDRDSP/LDROUT.
## "HIGH SCORES" in RED at scale 0 (big), Y=0x38=56.
## 8 rows: rank.initials.score in BLULET (or WHITE for glowing entry).
## Rows positioned at X=-48 from center, Y from 40 to -30 (step -10) at scale 1.
## Atari copyright at bottom via MATARI message.
func _draw_high_scores() -> void:
	var red: Color = Colors.get_color(Colors.RED)
	var blulet: Color = Colors.get_color(Colors.BLULET)
	var white: Color = Colors.get_color(Colors.WHITE)

	# "HIGH SCORES" — RED, binary scale 0 (big), Y=0x38=56
	# MSGS draws centered text at scale 0
	VectorFont.draw_text_centered(self, "HIGH SCORES", Vector2(SCREEN_CX, _vg_y(0x38, 0)), red, SCALE_0, LW_0)

	# Score entries — LDROUT loop: 8 entries (NHISCO)
	# VGCNTR + VGVTR1(A=0xD0=-48signed, X=TEMP3)
	# TEMP3 starts at 40, decrements by 10 per row
	# Colors: BLULET default, WHITE for glowing entry (SZL match)
	# Format: rank. [space] initials [space] score
	var temp3: int = 40
	for i in range(score_table.size() - 1, -1, -1):
		var entry: Dictionary = score_table[i]
		var row_color: Color = white if (i == highlight_idx) else blulet
		var row_y: float = _vg_y(temp3)
		# X = -48 from center at scale 1
		var row_x: float = _vg_x(-48)

		var rank_str: String = str(i + 1) + "."
		var ini: String = entry.initials if entry.initials.strip_edges() != "" else "   "
		var sc_str: String = str(entry.score).pad_zeros(6) if entry.score > 0 else "     0"

		# Draw: rank, space, initials, space, score
		var x_cursor: float = row_x
		x_cursor += VectorFont.draw_text(self, rank_str, Vector2(x_cursor, row_y), row_color, SCALE_1, LW_1)
		x_cursor += VectorFont.draw_text(self, " ", Vector2(x_cursor, row_y), row_color, SCALE_1, LW_1)
		x_cursor += VectorFont.draw_text(self, ini, Vector2(x_cursor, row_y), row_color, SCALE_1, LW_1)
		x_cursor += VectorFont.draw_text(self, " ", Vector2(x_cursor, row_y), row_color, SCALE_1, LW_1)
		VectorFont.draw_text(self, sc_str, Vector2(x_cursor, row_y), row_color, SCALE_1, LW_1)

		temp3 -= 10

	# Atari copyright — BLULET, scale 1, Y=0x92=146
	VectorFont.draw_text_centered(self, "MCMLXXX ATARI", Vector2(SCREEN_CX, _vg_y(0x92)), blulet, SCALE_1, LW_1)

	# Credits — GREEN, scale 1, Y=0x80=128
	VectorFont.draw_text_centered(self, "CREDITS 0", Vector2(SCREEN_CX, _vg_y(0x80)), Colors.get_color(Colors.GREEN), SCALE_1, LW_1)

	# INSERT COIN / PRESS START
	_draw_coin_prompt()

	# Optional message (e.g., "PRESS START" after game over)
	if message != "":
		VectorFont.draw_text_centered(self, message, Vector2(SCREEN_CX, _vg_y(0x56)), red, SCALE_1, LW_1)


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
	VectorFont.draw_text_centered(self, "MCMLXXX ATARI", Vector2(SCREEN_CX, _vg_y(0x92)), blulet, SCALE_1, LW_1)

	# High score table below (GETDSP falls into LDROUT)
	# Draw compact version of the ladder with the new entry glowing
	var temp3: int = -35
	for i in range(score_table.size() - 1, -1, -1):
		var entry: Dictionary = score_table[i]
		var row_color: Color = white if (i == highlight_idx) else blulet
		var row_y: float = _vg_y(temp3)
		var row_x: float = _vg_x(-48)

		var rank_str: String = str(i + 1) + "."
		var ini: String = entry.initials if entry.initials.strip_edges() != "" else "   "
		var sc_str: String = str(entry.score).pad_zeros(6) if entry.score > 0 else "     0"

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

	# Atari copyright — always shown during logo. See SCARNG: MSGEN3 at Y=0xD0
	var blulet: Color = Colors.get_color(Colors.BLULET)
	VectorFont.draw_text_centered(self, "MCMLXXX ATARI", Vector2(SCREEN_CX, _vg_y(-100)), blulet, SCALE_1, LW_1)

	# INSERT COIN / PRESS START
	_draw_coin_prompt()


## SCARNG for VORBOX — Draw rainbow trail of screen boundary rectangle.
## VORBOX: rectangle from (-500,-540) to (500,540) at scale (1,0).
## Each depth INDEX from NEARY to FARY (step 2):
##   scale_factor = 2^(-INDEX>>5) * (128 - (INDEX<<2)&0x7F) / 128
##   color: leading = WHITE, trailing = (INDEX>>3)&7 with 7→RED
func _draw_scarng_box() -> void:
	var center: Vector2 = Vector2(SCREEN_CX, SCREEN_CY - 40)
	# Base rectangle size (VORBOX: ±500 x ±540 in VG units at scale 1)
	var base_w: float = 480.0
	var base_h: float = 480.0

	var idx: int = logo_neary
	while idx <= logo_fary:
		var sf: float = _scarng_scale(idx)
		var color: Color = _scarng_color(idx, logo_neary)
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
	var center: Vector2 = Vector2(SCREEN_CX, SCREEN_CY - 60)

	var idx: int = logo_neary
	while idx <= logo_fary:
		var sf: float = _scarng_scale(idx)
		var color: Color = _scarng_color(idx, logo_neary)
		_draw_tempest_text(center, sf, color)
		idx += 2


## Draw the word "TEMPEST" using the original VORLIT vector shape data.
## See ALVROM.MAC: VORLIT starts at (-432, 256) then draws T,E,M,P,E,S,T
## with specific inter-letter offsets. We simplify to VectorFont at the
## computed scale, which gives the correct visual result.
func _draw_tempest_text(center: Vector2, sf: float, color: Color) -> void:
	var text_scale: float = sf * 5.0  # Scale so it fills screen at sf=1.0
	if text_scale < 0.05:
		return  # Too small to draw
	var lw: float = clampf(text_scale * 2.0, 0.5, 3.0)
	VectorFont.draw_text_centered(self, "TEMPEST", center, color, text_scale, lw)


## SCARNG scale computation. See ALSCO2.MAC § SCARNG.
## binary_scale = INDEX >> 5, linear_scale = (INDEX << 2) & 0x7F
## Total: 2^(-binary) * (128 - linear) / 128
func _scarng_scale(idx: int) -> float:
	@warning_ignore("integer_division")
	var binary: int = idx >> 5
	var linear: int = (idx << 2) & 0x7F
	var scale_val: float = pow(2.0, -float(binary)) * (128.0 - float(linear)) / 128.0
	return maxf(scale_val, 0.01)


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


## INSERT COIN / PRESS START prompt. See UI.md § 1.6.
## Flash logic: QFRAME & 0x1F < 0x10 → visible; else invisible.
## 32-frame cycle at 60Hz display rate.
func _draw_coin_prompt() -> void:
	var prompt_y: float = _vg_y(-120)
	if has_credits:
		# Static "PRESS START"
		VectorFont.draw_text_centered(self, "PRESS START", Vector2(SCREEN_CX, prompt_y), Colors.get_color(Colors.RED), SCALE_1, LW_1)
	elif show_insert_coin:
		# Flashing "INSERT COIN"
		VectorFont.draw_text_centered(self, "INSERT COIN", Vector2(SCREEN_CX, prompt_y), Colors.get_color(Colors.RED), SCALE_1, LW_1)


# --- Public API ---

func update_display(new_score: int, new_lives: int, new_wave: int) -> void:
	score = new_score
	lives = new_lives
	wave = new_wave
	if score > high_score:
		high_score = score
	queue_redraw()


func set_message(msg: String) -> void:
	message = msg
	queue_redraw()


func show_gameplay() -> void:
	mode = Mode.GAMEPLAY
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
	# Flash INSERT COIN based on qframe
	show_insert_coin = (qframe & 0x1F) < 0x10
	queue_redraw()


func show_high_scores(table: Array[Dictionary], highlight: int = -1, msg: String = "") -> void:
	mode = Mode.HIGH_SCORES
	score_table = table
	highlight_idx = highlight
	message = msg
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
func show_logo(phase: int, fary: int, neary: int, qframe: int = 0) -> void:
	mode = Mode.LOGO
	logo_phase = phase
	logo_fary = fary
	logo_neary = neary
	# Flash INSERT COIN based on qframe
	show_insert_coin = (qframe & 0x1F) < 0x10
	queue_redraw()
