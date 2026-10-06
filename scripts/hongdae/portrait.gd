extends Control
## Visual-novel style illustrated portrait shown during dialogue battles.
## Slides in with a flash and speed lines, then idles with a gentle bob.

const TEXTURES := {
	"basic": preload("res://assets/portraits/basic.png"),
	"dasher": preload("res://assets/portraits/dasher.png"),
	"trio": preload("res://assets/portraits/trio.png"),
	"photo": preload("res://assets/portraits/photo.png"),
	"boss": preload("res://assets/portraits/boss.png"),
}
const ACCENTS := {
	"basic": Color("ff2e88"), "dasher": Color("2de2e6"), "trio": Color("ffd23f"),
	"photo": Color("b14aed"), "boss": Color("ffb000"),
}

var kind := "basic"
var _t := 0.0

func _ready() -> void:
	clip_contents = true

func set_kind(value: String) -> void:
	kind = value if TEXTURES.has(value) else "basic"
	_t = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	queue_redraw()

func _draw() -> void:
	var accent: Color = ACCENTS.get(kind, Color("ff2e88"))
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color("1a0f2e"))
	for i: int in 8:
		var y := fmod(i * size.y / 6.0 + _t * 40.0, size.y + 120.0) - 60.0
		var band := PackedVector2Array([Vector2(0, y), Vector2(size.x, y - 90), Vector2(size.x, y - 70), Vector2(0, y + 20)])
		draw_colored_polygon(band, Color(accent, 0.07 + 0.03 * (i % 2)))
	var c := size * Vector2(0.5, 0.45)
	for i: int in 6:
		draw_circle(c, size.x * (0.55 - i * 0.07), Color(accent, 0.05))
	var burst := clampf(1.0 - _t / 0.9, 0.0, 1.0)
	if burst > 0.0:
		for i: int in 28:
			var a := TAU * i / 28.0 + 0.11 * i
			var r0 := size.x * (0.35 + 0.1 * sin(i * 3.1))
			draw_line(c + Vector2.from_angle(a) * r0, c + Vector2.from_angle(a) * size.x, Color(1, 1, 1, 0.35 * burst), 2.0)
	var tex: Texture2D = TEXTURES[kind]
	var slide := clampf(_t / 0.35, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - slide, 3.0)
	var bob := sin(_t * 2.2) * 4.0 if slide >= 1.0 else 0.0
	var side := size.y * 1.0
	var pos := Vector2((size.x - side) * 0.5 - (1.0 - eased) * size.x * 0.6, size.y - side + 6.0 + bob)
	draw_texture_rect(tex, Rect2(pos, Vector2(side, side)), false, Color(1, 1, 1, eased))
	var flash := clampf(1.0 - _t / 0.18, 0.0, 1.0)
	if flash > 0.0:
		draw_rect(rect, Color(1, 1, 1, 0.7 * flash))
	draw_rect(rect, accent, false, 4.0)
	draw_rect(rect.grow(-6), Color(accent, 0.4), false, 1.0)
