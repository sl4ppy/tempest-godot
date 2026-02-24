extends Node2D
## HUD overlay — score, lives, high score, wave number, messages.
## See DATA_ASSETS.md § Text Display.
## Uses VectorFont autoload for authentic Tempest arcade vector beam text.

var score: int = 0
var high_score: int = 0
var lives: int = 4
var wave: int = 1
var message: String = ""

# Scale: original 24-unit cell → ~20px tall on 1024x1024 viewport
const TEXT_SCALE: float = 0.85
const MSG_SCALE: float = 1.2
const LINE_WIDTH: float = 1.5
const MSG_LINE_WIDTH: float = 2.0


func _draw() -> void:
	var color: Color = Colors.get_color(Colors.BLULET)

	# Score — top left
	VectorFont.draw_text(self, str(score), Vector2(20, 30), color, TEXT_SCALE, LINE_WIDTH)

	# High score — top center
	VectorFont.draw_text_centered(self, str(high_score), Vector2(512, 30), color, TEXT_SCALE, LINE_WIDTH)

	# Lives — top right
	VectorFont.draw_text_right(self, str(lives), Vector2(1000, 30), color, TEXT_SCALE, LINE_WIDTH)

	# Wave — bottom center
	VectorFont.draw_text_centered(self, "WAVE " + str(wave), Vector2(512, 1000), color, TEXT_SCALE, LINE_WIDTH)

	# Center message (GAME OVER, PRESS START, bonus, etc.)
	if message != "":
		var msg_color: Color = Colors.get_color(Colors.WHITE)
		VectorFont.draw_text_centered(self, message, Vector2(512, 520), msg_color, MSG_SCALE, MSG_LINE_WIDTH)


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
