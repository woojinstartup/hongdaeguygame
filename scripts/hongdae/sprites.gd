class_name HESprites
extends RefCounted
## Procedural 16x16 pixel-art characters drawn with draw_rect.

const PLAYER := [
	"................",
	"......YYYY......",
	".....YYYYYY.....",
	".....YSSSSY.....",
	".....YSKSKY.....",
	".....YSSSSY.....",
	"......SSSS......",
	"....TTTTTTTT....",
	"...TTBTTTTBTT...",
	"...STTBTTBTTS...",
	"...S.TTTTTT.S...",
	".....TTTTTT.....",
	".....DDDDDD.....",
	".....DD..DD.....",
	".....DD..DD.....",
	".....WW..WW.....",
]

const GUY := [
	"................",
	".....HHHHHH.....",
	"....HHHHHHHH....",
	"....HHSSSSHH....",
	"....HSKSSKSH....",
	".....SSSSSS.....",
	"......SSSS......",
	"....LlLWWLlL....",
	"...LLlLWWLlLL...",
	"...LLLLWWLLLLS..",
	"...SLLLLLLLLLP..",
	".....LLLLLL.....",
	".....GGGGGG.....",
	".....GG..GG.....",
	".....GG..GG.....",
	".....RR..RR.....",
]

const BOSS := [
	"....C.C..C.C....",
	"....CCCCCCCC....",
	".....HHHHHH.....",
	"....HHHHHHHH....",
	"....HKKKKKKH....",
	"....HSKKSKKH....",
	".....SSSSSS.....",
	"....LlCCCClL....",
	"...LLlLCCLlLL...",
	"..LLLLLWWLLLLL..",
	"..SLLLLWWLLLLS..",
	"..SLLLLLLLLLLP..",
	".....GGGGGG.....",
	".....GG..GG.....",
	".....GG..GG.....",
	"....RRR..RRR....",
]

const FRIEND := [
	"................",
	"......NNNN......",
	".....NNNNNN.....",
	".....NssssN.....",
	".....NsKsKN.....",
	".....NssssN.....",
	"......ssss......",
	"....OOOOOOOO....",
	"...OOOOOOOOOO...",
	"...sOOOOOOOOs...",
	"...s.OOOOOO.s...",
	".....OOOOOO.....",
	".....DDDDDD.....",
	".....DD..DD.....",
	".....DD..DD.....",
	".....WW..WW.....",
]

const BASE_PALETTE := {
	"Y": Color("f7d774"), "S": Color("f2c6a0"), "K": Color("1a1020"),
	"T": Color("2ec4b6"), "B": Color("7a4b2a"), "D": Color("3d5a98"),
	"W": Color("f4f4f4"), "H": Color("15121c"), "G": Color("6b6b78"),
	"R": Color("1a1a1a"), "P": Color("5ff3ff"), "C": Color("ffd23f"),
	"N": Color("6b3a1f"), "s": Color("c98d63"), "O": Color("ff8c42"),
	"L": Color("2b2b36"), "l": Color("5a5a6e"),
}

static func palette_for(kind: String, revealed: bool = true) -> Dictionary:
	var p := BASE_PALETTE.duplicate()
	match kind:
		"dasher":
			p["R"] = Color("e63946")
			p["P"] = Color("ffffff")
		"trio":
			p["L"] = Color("3a2a22")
			p["l"] = Color("6e5444")
			p["W"] = Color("ffd23f")
		"photo":
			if not revealed:
				p["L"] = Color("c9b28a")
				p["l"] = Color("e3d3b0")
				p["W"] = Color("8fb3d9")
				p["P"] = Color("222222")
	return p

static func draw_pattern(ci: CanvasItem, pattern: Array, palette: Dictionary, origin: Vector2, flip: bool = false, px: float = 1.0) -> void:
	var height := pattern.size()
	for y: int in height:
		var row: String = pattern[y]
		var width := row.length()
		for x: int in width:
			var ch := row[x]
			if ch == ".":
				continue
			var color: Color = palette.get(ch, Color.MAGENTA)
			var dx := (width - 1 - x) if flip else x
			ci.draw_rect(Rect2(origin + Vector2(dx, y) * px, Vector2(px, px)), color)

static func draw_player(ci: CanvasItem, center: Vector2, facing_left: bool, airpods: bool) -> void:
	var origin := (center - Vector2(8, 12)).round()
	draw_pattern(ci, PLAYER, BASE_PALETTE, origin, facing_left)
	if airpods:
		ci.draw_rect(Rect2(origin + Vector2(4, 4), Vector2(1, 2)), Color.WHITE)
		ci.draw_rect(Rect2(origin + Vector2(11, 4), Vector2(1, 2)), Color.WHITE)

static func draw_guy(ci: CanvasItem, kind: String, center: Vector2, facing_left: bool, revealed: bool) -> void:
	var origin := (center - Vector2(8, 12)).round()
	if kind == "boss":
		draw_pattern(ci, BOSS, BASE_PALETTE, (center - Vector2(12, 20)).round(), facing_left, 1.5)
		return
	draw_pattern(ci, GUY, palette_for(kind, revealed), origin, facing_left)
	if kind == "photo" and not revealed:
		# Camera instead of a phone.
		ci.draw_rect(Rect2(origin + Vector2(6, 8), Vector2(4, 3)), Color("222222"))
		ci.draw_rect(Rect2(origin + Vector2(7, 9), Vector2(2, 1)), Color("8fd3ff"))

static func draw_friend(ci: CanvasItem, center: Vector2) -> void:
	draw_pattern(ci, FRIEND, BASE_PALETTE, (center - Vector2(8, 12)).round())

static func draw_exclaim(ci: CanvasItem, top_center: Vector2, color: Color = Color("ff2a4d")) -> void:
	var o := top_center.round() - Vector2(1, 0)
	ci.draw_rect(Rect2(o - Vector2(1, 1), Vector2(4, 9)), Color("1a0010"))
	ci.draw_rect(Rect2(o, Vector2(2, 5)), color)
	ci.draw_rect(Rect2(o + Vector2(0, 6), Vector2(2, 1)), color)

static func draw_question(ci: CanvasItem, top_center: Vector2) -> void:
	var o := top_center.round() - Vector2(2, 0)
	var c := Color("8fd3ff")
	for r: Rect2 in [Rect2(0, 0, 4, 1), Rect2(3, 1, 1, 2), Rect2(1, 3, 2, 1), Rect2(1, 4, 1, 1), Rect2(1, 6, 1, 1)]:
		ci.draw_rect(Rect2(o + r.position, r.size), c)

static func draw_heart(ci: CanvasItem, center: Vector2, color: Color) -> void:
	var o := center.round() - Vector2(2, 2)
	ci.draw_rect(Rect2(o + Vector2(0, 0), Vector2(2, 2)), color)
	ci.draw_rect(Rect2(o + Vector2(3, 0), Vector2(2, 2)), color)
	ci.draw_rect(Rect2(o + Vector2(0, 1), Vector2(5, 2)), color)
	ci.draw_rect(Rect2(o + Vector2(1, 3), Vector2(3, 1)), color)
	ci.draw_rect(Rect2(o + Vector2(2, 4), Vector2(1, 1)), color)
