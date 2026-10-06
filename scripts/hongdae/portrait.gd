extends Control
## Big pixel close-up used by the encounter cut-in.

var kind := "basic"

func set_kind(value: String) -> void:
	kind = value
	queue_redraw()

func _draw() -> void:
	var px := floorf(minf(size.x, size.y) / 16.0)
	var origin := ((size - Vector2(16, 16) * px) * 0.5).floor()
	draw_rect(Rect2(Vector2.ZERO, size), Color("2b1840"))
	for i: int in 6:
		draw_rect(Rect2(0, i * size.y / 6.0, size.x, 3), Color("ff2e88").darkened(0.5 + i * 0.06))
	var pattern := HESprites.BOSS if kind == "boss" else HESprites.GUY
	HESprites.draw_pattern(self, pattern, HESprites.palette_for(kind, true), origin, false, px)
