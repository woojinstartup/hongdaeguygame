class_name HEWorld
extends Node2D
## Top-down stealth simulation and pixel rendering for one Hongdae stage (320x160 base pixels).

signal encounter_started(kind: String)
signal shield_blocked
signal stage_cleared
signal item_collected(item: String)

const TILE := 16
const COLS := 20
const ROWS := 10
const PLAYER_SPEED := 64.0
const CROWD_SPEED_MULT := 0.6
const PLAYER_RADIUS := 5.0
const VIEW_RANGE := 58.0
const VIEW_HALF_ANGLE := deg_to_rad(36.0)
const ALERT_TIME := 0.45
const LOSE_TIME := 2.5
const CONTACT_DIST := 10.0
const AIRPODS_TIME := 6.0
const FRIEND_TIME := 6.0
const FRIEND_RADIUS := 44.0
const CONFUSE_TIME := 4.5
const CONFUSE_RADIUS := 80.0
const GRACE_TIME := 1.6
const SPEEDS := {"basic": 30.0, "dasher": 34.0, "trio": 30.0, "photo": 26.0, "boss": 0.0}
const CHASE_SPEEDS := {"basic": 46.0, "dasher": 44.0, "trio": 40.0, "photo": 54.0, "boss": 0.0}
const DASH_SPEED := 135.0
const ITEM_NAMES := {"a": "airpods", "b": "shield", "f": "friend", "n": "noenglish"}

var stage_index := 0
var stage: Dictionary = {}
var grid: Array = []
var player_pos := Vector2.ZERO
var player_start := Vector2.ZERO
var goal_tile := Vector2i.ZERO
var facing_left := false
var enemies: Array = []
var items: Dictionary = {}
var bullets: Array = []
var bubbles: Array = []
var airpods_time := 0.0
var friend_time := 0.0
var grace_time := 0.0
var shield := 0
var inventory := {"airpods": 0, "friend": 0, "noenglish": 0}
var elapsed := 0.0
var active := false
var move_override: Variant = null
var encounter_enemy := -1
var _clock := 0.0
var _rng := RandomNumberGenerator.new()

func load_stage(index: int, carry: Dictionary = {}) -> void:
	stage_index = index
	stage = HEStageData.get_stage(index)
	grid = []
	items.clear()
	for y: int in ROWS:
		var row: String = stage["map"][y]
		var clean := ""
		for x: int in COLS:
			var ch := row[x]
			if ch == "S":
				player_start = tile_center(Vector2i(x, y))
				ch = "."
			elif ch == "G":
				goal_tile = Vector2i(x, y)
			elif ITEM_NAMES.has(ch):
				items[Vector2i(x, y)] = ITEM_NAMES[ch]
				ch = "."
			clean += ch
		grid.append(clean)
	inventory = carry.get("inventory", {"airpods": 0, "friend": 0, "noenglish": 0}).duplicate()
	shield = int(carry.get("shield", 0))
	_rng.seed = 7331 + index
	elapsed = 0.0
	_reset_actors()
	active = true
	queue_redraw()

func _reset_actors() -> void:
	player_pos = player_start
	airpods_time = 0.0
	friend_time = 0.0
	grace_time = GRACE_TIME
	bullets.clear()
	bubbles.clear()
	encounter_enemy = -1
	enemies = []
	for spec: Dictionary in stage["enemies"]:
		var route: Array = spec["route"]
		var start := tile_center(route[0])
		enemies.append({
			"kind": spec["kind"], "route": route, "wp": 0, "pos": start, "home": start,
			"facing": Vector2.RIGHT if route.size() < 2 or route[1].x != route[0].x else Vector2.DOWN,
			"state": "patrol", "timer": 0.0, "lose": 0.0, "cooldown": 0.0,
			"revealed": spec["kind"] != "photo", "dash_time": 0.0, "dash_cd": 0.0,
			"dash_dir": Vector2.ZERO, "phase": float(spec.get("phase", 0.0)),
			"last_seen": start, "fire": 1.5, "pattern": 0,
		})

## Called after a failed encounter: back to the stage start, enemies reset, items kept.
func respawn() -> void:
	_reset_actors()
	active = true

func tile_center(t: Vector2i) -> Vector2:
	return Vector2(t.x * TILE + TILE * 0.5, t.y * TILE + TILE * 0.5)

func tile_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(floor(p.x / TILE)), 0, COLS - 1), clampi(int(floor(p.y / TILE)), 0, ROWS - 1))

func tile_char(t: Vector2i) -> String:
	if t.x < 0 or t.y < 0 or t.x >= COLS or t.y >= ROWS:
		return "#"
	return grid[t.y][t.x]

func is_solid_for_player(t: Vector2i) -> bool:
	return tile_char(t) in ["#", "P", "T"]

func is_solid_for_enemy(t: Vector2i) -> bool:
	return tile_char(t) in ["#", "P", "T", "C"]

func blocks_sight(t: Vector2i) -> bool:
	return tile_char(t) in ["#", "T"]

func player_hidden() -> bool:
	return tile_char(tile_of(player_pos)) in ["B", "C"]

func player_in_store() -> bool:
	return tile_char(tile_of(player_pos)) == "C"

# ---------------------------------------------------------------- simulation

func _physics_process(delta: float) -> void:
	_clock += delta
	if active:
		step(delta)
	queue_redraw()

func step(delta: float) -> void:
	if not active:
		return
	elapsed += delta
	airpods_time = maxf(0.0, airpods_time - delta)
	friend_time = maxf(0.0, friend_time - delta)
	grace_time = maxf(0.0, grace_time - delta)
	_update_bubbles(delta)
	_move_player(delta)
	_collect_items()
	if tile_of(player_pos) == goal_tile:
		active = false
		stage_cleared.emit()
		return
	for i: int in enemies.size():
		_update_enemy(enemies[i], delta)
	_update_bullets(delta)
	if active:
		_check_contacts()

func _input_vector() -> Vector2:
	if move_override != null:
		return move_override
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")

func _move_player(delta: float) -> void:
	var dir: Vector2 = _input_vector()
	if dir.length() > 1.0:
		dir = dir.normalized()
	if absf(dir.x) > 0.1:
		facing_left = dir.x < 0.0
	var speed := PLAYER_SPEED * (CROWD_SPEED_MULT if tile_char(tile_of(player_pos)) == "B" else 1.0)
	var motion := dir * speed * delta
	var next := player_pos + Vector2(motion.x, 0)
	if not _player_collides(next):
		player_pos = next
	next = player_pos + Vector2(0, motion.y)
	if not _player_collides(next):
		player_pos = next

func _player_collides(p: Vector2) -> bool:
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		if is_solid_for_player(tile_of(p + corner * PLAYER_RADIUS)):
			return true
	return false

func _collect_items() -> void:
	var t := tile_of(player_pos)
	if not items.has(t):
		return
	var item: String = items[t]
	items.erase(t)
	if item == "shield":
		shield += 1
	else:
		inventory[item] = int(inventory.get(item, 0)) + 1
	add_bubble(player_pos, _item_pickup_text(item), Color("ffd23f"))
	item_collected.emit(item)

func _item_pickup_text(item: String) -> String:
	match item:
		"airpods": return "+ AirPods"
		"shield": return "+ 'I have a boyfriend'"
		"friend": return "+ Call a Friend"
		_: return "+ 'No English'"

func use_item(item: String) -> bool:
	if not active or int(inventory.get(item, 0)) <= 0:
		return false
	inventory[item] = int(inventory[item]) - 1
	match item:
		"airpods":
			airpods_time = AIRPODS_TIME
			add_bubble(player_pos, "*AirPods in. Can't hear you.*", Color.WHITE)
		"friend":
			friend_time = FRIEND_TIME
			add_bubble(player_pos, "\"Hey bestie! Over here!\"", Color("ff8c42"))
		"noenglish":
			add_bubble(player_pos, "\"No English! Sorry!\"", Color("8fd3ff"))
			for e: Dictionary in enemies:
				if e["kind"] != "boss" and e["pos"].distance_to(player_pos) <= CONFUSE_RADIUS:
					e["state"] = "confused"
					e["timer"] = CONFUSE_TIME
					add_bubble(e["pos"], "???", Color("8fd3ff"))
	return true

func can_see_player(e: Dictionary) -> bool:
	if player_hidden() or not bool(e["revealed"]):
		return false
	var to_player: Vector2 = player_pos - e["pos"]
	var dist := to_player.length()
	if dist > VIEW_RANGE or dist < 0.01:
		return dist < 0.01
	var facing: Vector2 = e["facing"]
	if absf(facing.angle_to(to_player)) > VIEW_HALF_ANGLE:
		return false
	return has_line_of_sight(e["pos"], player_pos)

func has_line_of_sight(a: Vector2, b: Vector2) -> bool:
	var dist := a.distance_to(b)
	var steps := int(ceil(dist / 3.0))
	for i: int in range(1, steps):
		if blocks_sight(tile_of(a.lerp(b, float(i) / steps))):
			return false
	return true

func _update_enemy(e: Dictionary, delta: float) -> void:
	e["cooldown"] = maxf(0.0, float(e["cooldown"]) - delta)
	e["dash_cd"] = maxf(0.0, float(e["dash_cd"]) - delta)
	var state: String = e["state"]
	if state == "stunned" or state == "confused":
		e["timer"] = float(e["timer"]) - delta
		if float(e["timer"]) <= 0.0:
			e["state"] = "return"
		return
	if e["kind"] == "boss":
		_update_boss(e, delta)
		return
	var dist: float = e["pos"].distance_to(player_pos)
	# Friend nearby: everyone backs off.
	if friend_time > 0.0 and dist < FRIEND_RADIUS:
		var away: Vector2 = (e["pos"] - player_pos).normalized()
		_enemy_slide(e, away * 40.0 * delta)
		if state == "chase" or state == "alert":
			e["state"] = "return"
		return
	if e["kind"] == "photo" and not bool(e["revealed"]):
		if float(e["cooldown"]) <= 0.0 and dist < 30.0 and not player_hidden() and has_line_of_sight(e["pos"], player_pos):
			e["revealed"] = true
			e["state"] = "alert"
			e["timer"] = ALERT_TIME
			add_bubble(e["pos"], "Let me take your photo!", Color("ff4fa3"))
			return
		_patrol(e, delta)
		return
	match state:
		"patrol", "return":
			if float(e["cooldown"]) <= 0.0 and can_see_player(e):
				e["state"] = "alert"
				e["timer"] = ALERT_TIME
				return
			if e["kind"] == "trio":
				_trio_guard(e, delta)
			else:
				_patrol(e, delta)
		"alert":
			e["facing"] = (player_pos - e["pos"]).normalized()
			e["timer"] = float(e["timer"]) - delta
			if float(e["timer"]) <= 0.0:
				e["state"] = "chase"
				e["lose"] = 0.0
				e["last_seen"] = player_pos
		"chase":
			_chase(e, delta)

func _chase(e: Dictionary, delta: float) -> void:
	if player_in_store():
		add_bubble(e["pos"], "...she went shopping?", Color("cccccc"))
		e["state"] = "return"
		return
	var sees: bool = can_see_player(e) or (not player_hidden() and e["pos"].distance_to(player_pos) < 24.0 and has_line_of_sight(e["pos"], player_pos))
	if sees:
		e["last_seen"] = player_pos
		e["lose"] = 0.0
	else:
		e["lose"] = float(e["lose"]) + delta
		if float(e["lose"]) > LOSE_TIME:
			e["state"] = "return"
			return
	if e["kind"] == "dasher":
		if float(e["dash_time"]) > 0.0:
			e["dash_time"] = float(e["dash_time"]) - delta
			if not _enemy_slide(e, e["dash_dir"] * DASH_SPEED * delta):
				e["dash_time"] = 0.0
			return
		if sees and float(e["dash_cd"]) <= 0.0:
			e["dash_dir"] = (player_pos - e["pos"]).normalized()
			e["facing"] = e["dash_dir"]
			e["dash_time"] = 0.45
			e["dash_cd"] = 2.2
			add_bubble(e["pos"], "Instagram?!", Color("ff4fa3"))
			return
	_move_toward_point(e, e["last_seen"], CHASE_SPEEDS[e["kind"]] * delta)

func _patrol(e: Dictionary, delta: float) -> void:
	var route: Array = e["route"]
	var target := tile_center(route[int(e["wp"]) % route.size()])
	if e["state"] == "return" and e["pos"].distance_to(target) < 2.0:
		e["state"] = "patrol"
	if e["pos"].distance_to(target) < 1.5:
		e["wp"] = (int(e["wp"]) + 1) % route.size()
		target = tile_center(route[int(e["wp"])])
		if e["state"] == "return":
			e["state"] = "patrol"
	_move_toward_point(e, target, SPEEDS[e["kind"]] * delta)

func _trio_guard(e: Dictionary, delta: float) -> void:
	var post: Vector2 = e["home"]
	if e["pos"].distance_to(post) > 1.5:
		_move_toward_point(e, post, SPEEDS["trio"] * delta)
		return
	e["state"] = "patrol"
	var angle := PI * 0.5 + sin(_clock * 0.9 + float(e["phase"])) * 1.4 + (PI if int(floor((_clock + float(e["phase"])) / 6.0)) % 2 == 1 else 0.0)
	e["facing"] = Vector2.RIGHT.rotated(angle)

func _move_toward_point(e: Dictionary, target: Vector2, amount: float) -> void:
	var from_tile := tile_of(e["pos"])
	var to_tile := tile_of(target)
	var waypoint := target
	if from_tile != to_tile:
		var next := next_step(from_tile, to_tile)
		if next == from_tile:
			return
		waypoint = tile_center(next)
	var delta_vec: Vector2 = waypoint - e["pos"]
	if delta_vec.length() < 0.01:
		return
	var move := delta_vec.normalized() * minf(amount, delta_vec.length())
	e["facing"] = delta_vec.normalized()
	e["pos"] = e["pos"] + move

func _enemy_slide(e: Dictionary, motion: Vector2) -> bool:
	var moved := false
	var next: Vector2 = e["pos"] + Vector2(motion.x, 0)
	if not is_solid_for_enemy(tile_of(next + Vector2(signf(motion.x) * 4.0, 0))):
		e["pos"] = next
		moved = true
	next = e["pos"] + Vector2(0, motion.y)
	if not is_solid_for_enemy(tile_of(next + Vector2(0, signf(motion.y) * 4.0))):
		e["pos"] = next
		moved = true
	return moved

## BFS on the tile grid; returns the next tile toward `to` (or `from` if unreachable).
func next_step(from: Vector2i, to: Vector2i) -> Vector2i:
	if is_solid_for_enemy(to):
		# Target inside a store or obstacle: aim for the nearest open neighbour.
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not is_solid_for_enemy(to + d):
				to = to + d
				break
	var came := {from: from}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		if cur == to:
			break
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := cur + d
			if not came.has(n) and not is_solid_for_enemy(n):
				came[n] = cur
				queue.append(n)
	if not came.has(to):
		return from
	var step_tile := to
	while came[step_tile] != from and step_tile != from:
		step_tile = came[step_tile]
	return step_tile

func _update_boss(e: Dictionary, delta: float) -> void:
	e["facing"] = (player_pos - e["pos"]).normalized()
	if e["pos"].distance_to(player_pos) > 150.0:
		return
	e["fire"] = float(e["fire"]) - delta
	if float(e["fire"]) > 0.0:
		return
	e["fire"] = 1.6
	e["pattern"] = (int(e["pattern"]) + 1) % 2
	if int(e["pattern"]) == 0:
		for i: int in 10:
			var a := TAU * i / 10.0 + _clock
			bullets.append({"pos": e["pos"], "vel": Vector2.RIGHT.rotated(a) * 40.0, "life": 4.0})
		add_bubble(e["pos"], "OPEN-MINDED?!", Color("ffd23f"))
	else:
		var aim: Vector2 = (player_pos - e["pos"]).normalized()
		for spread: float in [-0.25, 0.0, 0.25]:
			bullets.append({"pos": e["pos"], "vel": aim.rotated(spread) * 62.0, "life": 4.0})
		add_bubble(e["pos"], "Instagram? Kakao? Club?", Color("ffd23f"))

func _update_bullets(delta: float) -> void:
	var keep: Array = []
	for b: Dictionary in bullets:
		b["pos"] = b["pos"] + b["vel"] * delta
		b["life"] = float(b["life"]) - delta
		if float(b["life"]) <= 0.0 or blocks_sight(tile_of(b["pos"])):
			continue
		if b["pos"].distance_to(player_pos) < 6.0 and grace_time <= 0.0 and not player_in_store():
			if airpods_time > 0.0 or friend_time > 0.0:
				continue
			bullets = keep
			_on_contact(_boss_index())
			return
		keep.append(b)
	bullets = keep

func _boss_index() -> int:
	for i: int in enemies.size():
		if enemies[i]["kind"] == "boss":
			return i
	return -1

func _check_contacts() -> void:
	if grace_time > 0.0 or player_in_store():
		return
	for i: int in enemies.size():
		var e: Dictionary = enemies[i]
		if e["state"] in ["stunned", "confused"] or float(e["cooldown"]) > 0.0 or not bool(e["revealed"]):
			continue
		var reach := CONTACT_DIST + (4.0 if e["kind"] == "boss" else 0.0)
		if e["pos"].distance_to(player_pos) < reach:
			_on_contact(i)
			return

func _on_contact(index: int) -> void:
	if index < 0:
		return
	var e: Dictionary = enemies[index]
	if airpods_time > 0.0:
		add_bubble(e["pos"], "...hello? HELLO?", Color("cccccc"))
		_stun(e, 2.5)
		return
	if friend_time > 0.0:
		_stun(e, 2.0)
		return
	if shield > 0:
		shield -= 1
		add_bubble(player_pos, "\"I have a boyfriend!\"", Color("ff8c42"))
		add_bubble(e["pos"], "...oh. Okay.", Color("cccccc"))
		_stun(e, 3.0)
		grace_time = 1.0
		shield_blocked.emit()
		return
	active = false
	encounter_enemy = index
	encounter_started.emit(str(e["kind"]))

func _stun(e: Dictionary, time: float) -> void:
	e["state"] = "stunned"
	e["timer"] = time
	e["cooldown"] = time + 2.5
	if e["kind"] == "photo":
		e["revealed"] = false

## Win: the guy is left speechless and the player gets a moment to leave.
func resolve_encounter_win() -> void:
	if encounter_enemy >= 0 and encounter_enemy < enemies.size():
		var e: Dictionary = enemies[encounter_enemy]
		_stun(e, 3.5)
		add_bubble(e["pos"], "...", Color("cccccc"))
	bullets.clear()
	grace_time = GRACE_TIME
	encounter_enemy = -1
	active = true

# ---------------------------------------------------------------- bubbles

func add_bubble(pos: Vector2, text: String, color: Color) -> void:
	bubbles.append({"pos": pos, "text": text, "time": 1.8, "color": color})
	if bubbles.size() > 6:
		bubbles.pop_front()

func _update_bubbles(delta: float) -> void:
	var keep: Array = []
	for b: Dictionary in bubbles:
		b["time"] = float(b["time"]) - delta
		if float(b["time"]) > 0.0:
			keep.append(b)
	bubbles = keep

# ---------------------------------------------------------------- rendering

const NEON := [Color("ff2e88"), Color("b14aed"), Color("2de2e6"), Color("ffd23f"), Color("ff6c11")]

func _floor_color(x: int, y: int) -> Color:
	match str(stage.get("theme", "street")):
		"park":
			return Color("2f5a3c") if (x + y) % 2 == 0 else Color("33603f")
		"club":
			return Color("33264f") if (x + y) % 2 == 0 else Color("372a55")
		_:
			return Color("3b3352") if (x + y) % 2 == 0 else Color("3f3757")

func _draw() -> void:
	if grid.is_empty():
		return
	for y: int in ROWS:
		for x: int in COLS:
			_draw_tile(x, y)
	_draw_goal()
	for t: Vector2i in items:
		_draw_item(tile_center(t), items[t])
	for e: Dictionary in enemies:
		_draw_cone(e)
	for b: Dictionary in bullets:
		HESprites.draw_heart(self, b["pos"], Color("ff4fa3"))
	var drawables: Array = []
	for e: Dictionary in enemies:
		drawables.append([e["pos"].y, e])
	drawables.append([player_pos.y, null])
	drawables.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for d: Array in drawables:
		if d[1] == null:
			_draw_player()
		else:
			_draw_enemy(d[1])

func _draw_tile(x: int, y: int) -> void:
	var r := Rect2(x * TILE, y * TILE, TILE, TILE)
	var ch: String = grid[y][x]
	var floor_c := _floor_color(x, y)
	match ch:
		"#":
			var base := Color("120b1f") if stage.get("theme") != "park" else Color("10241a")
			draw_rect(r, base)
			draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(14, 14)), Color("1b0f2c") if stage.get("theme") != "park" else Color("16301f"))
			var below := tile_char(Vector2i(x, y + 1))
			if below != "#" and y < ROWS - 1:
				var c: Color = NEON[(x * 7 + y * 3 + stage_index) % NEON.size()]
				draw_rect(Rect2(r.position + Vector2(3, 9), Vector2(10, 4)), c.darkened(0.55))
				draw_rect(Rect2(r.position + Vector2(4, 10), Vector2(8, 2)), c)
			else:
				for wx: int in [3, 9]:
					var lit := (x * 13 + y * 7 + wx) % 3 == 0
					draw_rect(Rect2(r.position + Vector2(wx, 4), Vector2(4, 3)), Color("ffd23f").darkened(0.35) if lit else Color("1a1030"))
		"C":
			draw_rect(r, Color("dff6ff"))
			draw_rect(Rect2(r.position, Vector2(16, 3)), Color("2ecc71"))
			draw_rect(Rect2(r.position + Vector2(2, 6), Vector2(5, 7)), Color("9ad1e8"))
			draw_rect(Rect2(r.position + Vector2(9, 6), Vector2(5, 7)), Color("9ad1e8"))
		"B":
			draw_rect(r, floor_c)
			for i: int in 5:
				var hx := 2 + (i * 5 + x * 3) % 12
				var hy := 3 + (i * 7 + y * 5) % 10
				draw_rect(Rect2(r.position + Vector2(hx, hy), Vector2(3, 3)), NEON[(i + x) % NEON.size()].darkened(0.3))
				draw_rect(Rect2(r.position + Vector2(hx, hy - 1), Vector2(3, 1)), Color("2a1b12"))
		"P":
			draw_rect(r, floor_c)
			var mat := Color("e63946") if (x + y) % 2 == 0 else Color("457b9d")
			draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(14, 14)), mat)
			for i: int in 4:
				draw_rect(Rect2(r.position + Vector2(1 + i * 4, 1), Vector2(2, 14)), Color(1, 1, 1, 0.25))
		"T":
			draw_rect(r, floor_c)
			draw_rect(Rect2(r.position + Vector2(6, 10), Vector2(4, 5)), Color("6b3a1f"))
			draw_rect(Rect2(r.position + Vector2(2, 1), Vector2(12, 10)), Color("2d6a4f"))
			draw_rect(Rect2(r.position + Vector2(4, 2), Vector2(5, 4)), Color("40916c"))
		_:
			draw_rect(r, floor_c)
			if stage.get("theme") != "park" and (x + y * 3) % 5 == 0:
				draw_rect(Rect2(r.position + Vector2(6, 7), Vector2(4, 1)), Color("ffd23f").darkened(0.6))

func _draw_goal() -> void:
	var r := Rect2(goal_tile.x * TILE, goal_tile.y * TILE, TILE, TILE)
	draw_rect(r, Color("ffd23f"))
	draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(12, 12)), Color("ff9f1c"))
	draw_rect(Rect2(r.position + Vector2(5, 4), Vector2(6, 8)), Color("ffd23f"))
	draw_rect(Rect2(r.position + Vector2(7, 7), Vector2(2, 2)), Color("ff9f1c"))

func _draw_item(c: Vector2, item: String) -> void:
	var o := c - Vector2(5, 5)
	draw_rect(Rect2(o - Vector2(1, 1), Vector2(12, 12)), Color("ffd23f"))
	draw_rect(Rect2(o, Vector2(10, 10)), Color("1a1030"))
	match item:
		"airpods":
			draw_rect(Rect2(o + Vector2(2, 2), Vector2(2, 3)), Color.WHITE)
			draw_rect(Rect2(o + Vector2(6, 2), Vector2(2, 3)), Color.WHITE)
			draw_rect(Rect2(o + Vector2(3, 5), Vector2(1, 3)), Color.WHITE)
			draw_rect(Rect2(o + Vector2(6, 5), Vector2(1, 3)), Color.WHITE)
		"shield":
			HESprites.draw_heart(self, c, Color("ff8c42"))
		"friend":
			draw_rect(Rect2(o + Vector2(3, 1), Vector2(4, 8)), Color("5ff3ff"))
			draw_rect(Rect2(o + Vector2(4, 2), Vector2(2, 5)), Color("1a1030"))
		"noenglish":
			draw_rect(Rect2(o + Vector2(2, 2), Vector2(6, 6)), Color("8fd3ff"))
			draw_rect(Rect2(o + Vector2(3, 3), Vector2(4, 4)), Color("1a1030"))
			draw_rect(Rect2(o + Vector2(4, 4), Vector2(2, 2)), Color("e63946"))

func _draw_cone(e: Dictionary) -> void:
	if e["kind"] == "boss" or not bool(e["revealed"]) or e["state"] in ["stunned", "confused"]:
		return
	var facing: Vector2 = e["facing"]
	if facing.length() < 0.01:
		return
	var hot: bool = e["state"] in ["alert", "chase"]
	var color := Color(1.0, 0.16, 0.3, 0.32) if hot else Color(1.0, 0.31, 0.64, 0.18)
	var points := PackedVector2Array([e["pos"]])
	var segments := 8
	for i: int in segments + 1:
		var a := -VIEW_HALF_ANGLE + 2.0 * VIEW_HALF_ANGLE * i / segments
		var dir := facing.rotated(a)
		var reach := VIEW_RANGE
		var probe := 4.0
		while probe < VIEW_RANGE:
			if blocks_sight(tile_of(e["pos"] + dir * probe)):
				reach = probe
				break
			probe += 4.0
		points.append(e["pos"] + dir * reach)
	draw_colored_polygon(points, color)

func _draw_enemy(e: Dictionary) -> void:
	var facing: Vector2 = e["facing"]
	HESprites.draw_guy(self, e["kind"], e["pos"], facing.x < 0.0, bool(e["revealed"]))
	var head: Vector2 = e["pos"] - Vector2(0, 22 if e["kind"] == "boss" else 21)
	match str(e["state"]):
		"alert", "chase":
			if bool(e["revealed"]) and e["kind"] != "boss":
				HESprites.draw_exclaim(self, head)
		"confused":
			HESprites.draw_question(self, head)
		"stunned":
			draw_rect(Rect2(head + Vector2(-3, 4), Vector2(6, 1)), Color("cccccc"))

func _draw_player() -> void:
	if grace_time > 0.0 and int(_clock * 10.0) % 2 == 0:
		return
	if friend_time > 0.0:
		HESprites.draw_friend(self, player_pos + Vector2(-11 if not facing_left else 11, 2))
		draw_arc(player_pos, FRIEND_RADIUS, 0, TAU, 32, Color(1.0, 0.55, 0.26, 0.35), 1.0)
	if shield > 0:
		draw_arc(player_pos - Vector2(0, 4), 9.0, 0, TAU, 16, Color(1.0, 0.55, 0.26, 0.6), 1.0)
	HESprites.draw_player(self, player_pos, facing_left, airpods_time > 0.0)
