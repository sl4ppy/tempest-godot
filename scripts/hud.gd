extends Node2D
## HUD overlay — score, lives, high score, wave number.
## See DATA_ASSETS.md § Text Display.

var score: int = 0
var high_score: int = 0
var lives: int = 4
var wave: int = 1


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 20
	var color: Color = Colors.get_color(Colors.BLULET)

	# Score — top left
	draw_string(font, Vector2(20, 30), str(score), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

	# High score — top center
	draw_string(font, Vector2(400, 30), str(high_score), HORIZONTAL_ALIGNMENT_CENTER, 224, font_size, color)

	# Lives — top right
	draw_string(font, Vector2(900, 30), "x" + str(lives), HORIZONTAL_ALIGNMENT_RIGHT, 100, font_size, color)

	# Wave — bottom center
	draw_string(font, Vector2(460, 1000), "WAVE " + str(wave), HORIZONTAL_ALIGNMENT_CENTER, 100, font_size, color)


func update_display(new_score: int, new_lives: int, new_wave: int) -> void:
	score = new_score
	lives = new_lives
	wave = new_wave
	if score > high_score:
		high_score = score
	queue_redraw()
