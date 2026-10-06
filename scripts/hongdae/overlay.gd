extends Control
## Draws crisp speech-bubble text above the scaled pixel world.

const FONT := preload("res://assets/template/fonts/ui_bold.tres")
const FONT_SIZE := 15

var world: HEWorld
var world_scale := 4.0
var world_offset := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if world == null or not world.visible:
		return
	for b: Dictionary in world.bubbles:
		var text: String = b["text"]
		var anchor: Vector2 = world_offset + (b["pos"] - Vector2(0, 26)) * world_scale
		var width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var rect := Rect2(anchor - Vector2(width * 0.5 + 8, 22), Vector2(width + 16, 26))
		rect.position.x = clampf(rect.position.x, 4.0, size.x - rect.size.x - 4.0)
		rect.position.y = maxf(rect.position.y, world_offset.y + 2.0)
		var alpha := clampf(float(b["time"]) * 2.0, 0.0, 1.0)
		draw_rect(rect, Color(0.06, 0.03, 0.1, 0.88 * alpha))
		draw_rect(rect, Color(b["color"], alpha), false, 2.0)
		var col: Color = b["color"]
		col.a = alpha
		draw_string(FONT, rect.position + Vector2(8, 19), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col)
