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
	_corner_assist(dir, speed * delta)
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

## Pac-Man style cornering: when steering into a side corridor, slide onto the
## lane centre so one-tile-wide streets never snag on wall corners.
func _corner_assist(dir: Vector2, amount: float) -> void:
	var here := tile_of(player_pos)
	var centre := tile_center(here)
	if absf(dir.y) > 0.1 and not is_solid_for_player(here + Vector2i(0, int(signf(dir.y)))):
		player_pos.x = move_toward(player_pos.x, centre.x, amount * 1.5)
	if absf(dir.x) > 0.1 and not is_solid_for_player(here + Vector2i(int(signf(dir.x)), 0)):
		player_pos.y = move_toward(player_pos.y, centre.y, amount * 1.5)

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
			add_bubble(player_pos, "(AirPods in. Can't hear you.)", Color.WHITE)
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
			add_bubble(e["pos"], "Picture-eu? Just one!", Color("ff4fa3"))
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
			add_bubble(e["pos"], "Insta ID?!", Color("ff4fa3"))
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
		add_bubble(e["pos"], "OPEN MINDEU?!", Color("ffd23f"))
	else:
		var aim: Vector2 = (player_pos - e["pos"]).normalized()
		for spread: float in [-0.25, 0.0, 0.25]:
			bullets.append({"pos": e["pos"], "vel": aim.rotated(spread) * 62.0, "life": 4.0})
		add_bubble(e["pos"], "Do you libe alone?!", Color("ffd23f"))

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

func _h(x: int, y: int, k: int = 0) -> int:
	return absi((x * 73856093) ^ (y * 19349663) ^ ((k + stage_index * 31) * 83492791)) % 1000

func _theme() -> String:
	return str(stage.get("theme", "street"))

func _is_wall(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= COLS or y >= ROWS:
		return true
	return grid[y][x] == "#"

func _floor_color(x: int, y: int) -> Color:
	match _theme():
		"park":
			return Color("3f7a4a") if (x + y) % 2 == 0 else Color("437f4e")
		"club":
			return Color("43306a") if (x + y) % 2 == 0 else Color("4a3574")
		_:
			return Color("3a3448")

func _draw_floor(x: int, y: int) -> void:
	var r := Rect2(x * TILE, y * TILE, TILE, TILE)
	var p := r.position
	var theme := _theme()
	draw_rect(r, _floor_color(x, y))
	if theme == "park":
		for i: int in 4:
			var hx := (_h(x, y, i) % 14) + 1
			var hy := (_h(x, y, i + 7) % 13) + 2
			draw_rect(Rect2(p + Vector2(hx, hy), Vector2(1, 2)), Color("2f6439"))
			draw_rect(Rect2(p + Vector2(hx + 1, hy + 1), Vector2(1, 1)), Color("5c9b62"))
		if _h(x, y, 3) % 5 == 0:
			var fx := 3 + _h(x, y, 4) % 10
			var fy := 3 + _h(x, y, 5) % 10
			var fc: Color = [Color("ffd23f"), Color("ff7eb6"), Color("f5ecff")][_h(x, y, 6) % 3]
			draw_rect(Rect2(p + Vector2(fx, fy), Vector2(2, 2)), fc)
		# Gravel path along the edges next to walls.
		if _is_wall(x, y - 1):
			draw_rect(Rect2(p, Vector2(16, 3)), Color("8a7a5c"))
			draw_rect(Rect2(p + Vector2(0, 3), Vector2(16, 1)), Color("2a5233"))
		return
	if theme == "club":
		# Glossy tiles with a thin grout grid and reflections.
		draw_rect(Rect2(p, Vector2(16, 1)), Color("2e2148"))
		draw_rect(Rect2(p, Vector2(1, 16)), Color("2e2148"))
		draw_rect(Rect2(p + Vector2(2, 2), Vector2(5, 1)), Color(1, 1, 1, 0.06))
		if _h(x, y, 1) % 4 == 0:
			var c: Color = NEON[_h(x, y, 2) % NEON.size()]
			draw_rect(Rect2(p + Vector2(3, 6), Vector2(1, 6)), Color(c, 0.35))
			draw_rect(Rect2(p + Vector2(4, 8), Vector2(1, 4)), Color(c, 0.2))
	else:
		# Asphalt speckle.
		for i: int in 5:
			draw_rect(Rect2(p + Vector2(_h(x, y, i) % 16, _h(x, y, i + 9) % 16), Vector2(1, 1)), Color("4a4358") if i % 2 == 0 else Color("2f2a3b"))
		var walls_v := _is_wall(x - 1, y) and _is_wall(x + 1, y)
		var walls_h := _is_wall(x, y - 1) and _is_wall(x, y + 1)
		if walls_h and not walls_v and _h(x, y, 8) % 3 == 0:
			# Crosswalk stripes in horizontal passages.
			for i: int in 4:
				draw_rect(Rect2(p + Vector2(1 + i * 4, 3), Vector2(2, 10)), Color("d9d3e6", 0.55))
		elif walls_v and not walls_h and _h(x, y, 8) % 3 == 0:
			for i: int in 4:
				draw_rect(Rect2(p + Vector2(3, 1 + i * 4), Vector2(10, 2)), Color("d9d3e6", 0.55))
		elif _h(x, y, 10) % 17 == 0:
			draw_circle(p + Vector2(8, 8), 4.0, Color("2a2535"))
			draw_arc(p + Vector2(8, 8), 4.0, 0, TAU, 12, Color("55506a"), 1.0)
		# Sidewalk paving next to buildings.
		if _is_wall(x, y - 1):
			draw_rect(Rect2(p, Vector2(16, 5)), Color("5b5370"))
			draw_rect(Rect2(p + Vector2(0, 5), Vector2(16, 1)), Color("8a82a0"))
			for i: int in 2:
				draw_rect(Rect2(p + Vector2(i * 8 + (y % 2) * 4, 0), Vector2(1, 5)), Color("4a4360"))
	# Building shadow falls onto the tile below it.
	if _is_wall(x, y - 1) and theme != "park":
		draw_rect(Rect2(p, Vector2(16, 2)), Color(0, 0, 0, 0.35))

func _draw_building(x: int, y: int) -> void:
	var r := Rect2(x * TILE, y * TILE, TILE, TILE)
	var p := r.position
	var park := _theme() == "park"
	var club := _theme() == "club"
	var front := not _is_wall(x, y + 1) and y < ROWS - 1
	if park:
		# Hedges and park fences.
		draw_rect(r, Color("1d4a2a"))
		draw_circle(p + Vector2(4, 5), 5.0, Color("2b6a3a"))
		draw_circle(p + Vector2(12, 6), 5.0, Color("2f7340"))
		draw_circle(p + Vector2(8, 10), 6.0, Color("27613a"))
		draw_rect(Rect2(p + Vector2(3, 3), Vector2(2, 1)), Color("4f9a5c"))
		draw_rect(Rect2(p + Vector2(11, 4), Vector2(2, 1)), Color("4f9a5c"))
		if front:
			draw_rect(Rect2(p + Vector2(0, 13), Vector2(16, 3)), Color("6b4a2f"))
			for i: int in 4:
				draw_rect(Rect2(p + Vector2(1 + i * 4, 11), Vector2(1, 5)), Color("8a6a45"))
		return
	var hue := _h(x, y, 20)
	var walls := [Color("2a1c40"), Color("33213f"), Color("23203a"), Color("3a2238")]
	var wall_c: Color = walls[hue % walls.size()]
	if not front:
		# Rooftop: ledge, tar texture, AC units and water tanks.
		draw_rect(r, Color("1a1228"))
		draw_rect(Rect2(p + Vector2(1, 1), Vector2(14, 14)), Color("221830"))
		if _h(x, y, 21) % 3 == 0:
			draw_rect(Rect2(p + Vector2(3, 4), Vector2(6, 5)), Color("6b6b80"))
			draw_rect(Rect2(p + Vector2(4, 5), Vector2(4, 3)), Color("4a4a5c"))
			draw_rect(Rect2(p + Vector2(5, 6), Vector2(2, 1)), Color("8a8aa0"))
		elif _h(x, y, 21) % 3 == 1:
			draw_circle(p + Vector2(10, 8), 3.5, Color("3d8fd1"))
			draw_rect(Rect2(p + Vector2(8, 6), Vector2(2, 1)), Color("8fd3ff"))
		else:
			for i: int in 3:
				var lit := _h(x, y, 30 + i) % 2 == 0
				draw_rect(Rect2(p + Vector2(2 + i * 5, 3), Vector2(3, 3)), Color("ffd23f", 0.75) if lit else Color("140c20"))
				draw_rect(Rect2(p + Vector2(2 + i * 5, 9), Vector2(3, 3)), Color("ffb347", 0.6) if not lit else Color("140c20"))
		return
	# Street-facing facade: wall, upper windows, sign band and shopfront.
	draw_rect(r, wall_c)
	draw_rect(Rect2(p, Vector2(16, 1)), wall_c.lightened(0.15))
	for wx: int in [2, 10]:
		var on := _h(x, y, wx) % 3 != 0
		draw_rect(Rect2(p + Vector2(wx, 1), Vector2(4, 3)), Color("ffd890") if on else Color("150d22"))
		draw_rect(Rect2(p + Vector2(wx, 4), Vector2(4, 1)), wall_c.darkened(0.4))
	var c: Color = NEON[(hue / 7) % NEON.size()]
	var flicker := 1.0 if (int(_clock * 6.0 + hue) % 23) != 0 else 0.45
	var shop := hue % 4
	match shop:
		0:
			# Neon signboard with pixel lettering.
			draw_rect(Rect2(p + Vector2(1, 5), Vector2(14, 5)), Color("120a1c"))
			draw_rect(Rect2(p + Vector2(1, 5), Vector2(14, 5)), Color(c, flicker), false, 1.0)
			for i: int in 4:
				if _h(x, y, 40 + i) % 4 != 0:
					draw_rect(Rect2(p + Vector2(3 + i * 3, 7), Vector2(2, 1 + _h(x, y, 50 + i) % 2)), Color(c.lightened(0.4), flicker))
		1:
			# Striped awning (cafe).
			for i: int in 4:
				draw_rect(Rect2(p + Vector2(i * 4, 6), Vector2(4, 3)), c if i % 2 == 0 else Color("f5ecff"))
			for i: int in 4:
				draw_rect(Rect2(p + Vector2(i * 4 + 1, 9), Vector2(2, 1)), c.darkened(0.3))
		2:
			# Vertical karaoke sign hanging off the wall.
			draw_rect(Rect2(p + Vector2(11, 1), Vector2(4, 10)), Color("120a1c"))
			draw_rect(Rect2(p + Vector2(12, 2), Vector2(2, 8)), Color(c, flicker))
			draw_rect(Rect2(p + Vector2(1, 6), Vector2(9, 3)), Color(c.darkened(0.5), 1.0))
		_:
			# Lightbox sign.
			draw_rect(Rect2(p + Vector2(1, 5), Vector2(14, 4)), Color(c, flicker))
			draw_rect(Rect2(p + Vector2(4, 6), Vector2(8, 2)), Color("120a1c", 0.6))
	# Shopfront: glass, door, warm interior.
	draw_rect(Rect2(p + Vector2(0, 10), Vector2(16, 6)), Color("1a1226"))
	draw_rect(Rect2(p + Vector2(1, 11), Vector2(8, 4)), Color("ffcf8a", 0.55))
	draw_rect(Rect2(p + Vector2(2, 12), Vector2(2, 3)), Color("6e4a8a", 0.7))
	draw_rect(Rect2(p + Vector2(10, 11), Vector2(5, 5)), Color("0e0816"))
	draw_rect(Rect2(p + Vector2(13, 13), Vector2(1, 1)), Color("ffd23f"))

func _draw_store(x: int, y: int) -> void:
	var r := Rect2(x * TILE, y * TILE, TILE, TILE)
	var p := r.position
	var top := tile_char(Vector2i(x, y - 1)) != "C"
	draw_rect(r, Color("e9f6f2"))
	if top:
		draw_rect(Rect2(p, Vector2(16, 4)), Color("7b3fa0"))
		draw_rect(Rect2(p + Vector2(0, 4), Vector2(16, 1)), Color("2ecc71"))
		draw_rect(Rect2(p + Vector2(2, 1), Vector2(3, 2)), Color("f5ecff"))
		draw_rect(Rect2(p + Vector2(6, 1), Vector2(1, 2)), Color("f5ecff"))
		draw_rect(Rect2(p + Vector2(8, 1), Vector2(2, 2)), Color("2ecc71"))
	var y0 := 6 if top else 1
	# Shelves with colourful snacks behind glass.
	draw_rect(Rect2(p + Vector2(1, y0), Vector2(14, 15 - y0)), Color("bfe3f0"))
	for row: int in 3:
		var sy := y0 + 1 + row * 3
		if sy > 14:
			break
		draw_rect(Rect2(p + Vector2(2, sy + 2), Vector2(12, 1)), Color("8aa9b8"))
		for i: int in 5:
			draw_rect(Rect2(p + Vector2(2 + i * 2 + (row % 2), sy), Vector2(1, 2)), NEON[(_h(x, y, i + row * 5)) % NEON.size()])
	draw_rect(Rect2(p + Vector2(0, 15), Vector2(16, 1)), Color("2ecc71"))

func _draw_crowd(x: int, y: int) -> void:
	var p := Vector2(x * TILE, y * TILE)
	_draw_floor(x, y)
	# A busker and a ring of onlookers.
	if _h(x, y, 60) % 3 == 0:
		draw_rect(Rect2(p + Vector2(10, 9), Vector2(4, 6)), Color("1a1226"))
		draw_rect(Rect2(p + Vector2(11, 10), Vector2(2, 2)), Color("6b6b80"))
	for i: int in 4:
		var hx := 1 + (_h(x, y, i) % 11)
		var hy := 2 + (_h(x, y, i + 4) % 8)
		var bob := 1 if int(_clock * 4.0 + i + x) % 2 == 0 else 0
		var body: Color = [Color("e85d75"), Color("4ea8de"), Color("f5c542"), Color("9b5de5"), Color("43aa8b")][_h(x, y, i + 8) % 5]
		draw_rect(Rect2(p + Vector2(hx, hy + 3 - bob), Vector2(4, 4)), body)
		draw_rect(Rect2(p + Vector2(hx + 1, hy - bob), Vector2(2, 3)), Color("f2c6a0"))
		draw_rect(Rect2(p + Vector2(hx + 1, hy - bob), Vector2(2, 1)), Color("2a1b12"))
	if int(_clock * 2.0 + x) % 3 == 0:
		draw_rect(Rect2(p + Vector2(7, 0), Vector2(1, 2)), Color("ffd23f"))
		draw_rect(Rect2(p + Vector2(8, 0), Vector2(1, 1)), Color("ffd23f"))

func _draw_mat(x: int, y: int) -> void:
	var p := Vector2(x * TILE, y * TILE)
	_draw_floor(x, y)
	var base := Color("e63946") if (x + y) % 2 == 0 else Color("457b9d")
	draw_rect(Rect2(p + Vector2(1, 2), Vector2(14, 13)), base.darkened(0.25))
	draw_rect(Rect2(p + Vector2(1, 1), Vector2(14, 13)), base)
	for i: int in 3:
		draw_rect(Rect2(p + Vector2(1 + i * 5, 1), Vector2(2, 13)), Color(1, 1, 1, 0.35))
		draw_rect(Rect2(p + Vector2(1, 2 + i * 5), Vector2(14, 1)), Color(1, 1, 1, 0.25))
	match _h(x, y, 70) % 3:
		0:
			draw_rect(Rect2(p + Vector2(5, 6), Vector2(6, 4)), Color("b5793c"))
			draw_rect(Rect2(p + Vector2(6, 4), Vector2(4, 2)), Color("8a5a2b"))
		1:
			draw_rect(Rect2(p + Vector2(6, 5), Vector2(2, 5)), Color("2ecc71"))
			draw_rect(Rect2(p + Vector2(9, 6), Vector2(2, 4)), Color("f5ecff"))
		_:
			draw_circle(p + Vector2(8, 8), 2.5, Color("ffd23f"))

func _draw_tree(x: int, y: int) -> void:
	var p := Vector2(x * TILE, y * TILE)
	_draw_floor(x, y)
	draw_circle(p + Vector2(8, 13), 5.0, Color(0, 0, 0, 0.25))
	draw_rect(Rect2(p + Vector2(7, 9), Vector2(3, 6)), Color("6b3a1f"))
	draw_circle(p + Vector2(8, 7), 6.5, Color("1f5a35"))
	draw_circle(p + Vector2(6, 5), 4.0, Color("2d7a46"))
	draw_circle(p + Vector2(10, 6), 3.5, Color("2a7342"))
	draw_rect(Rect2(p + Vector2(4, 3), Vector2(3, 1)), Color("5cb36b"))
	draw_rect(Rect2(p + Vector2(10, 4), Vector2(2, 1)), Color("5cb36b"))

func _draw() -> void:
	if grid.is_empty():
		return
	for y: int in ROWS:
		for x: int in COLS:
			_draw_tile(x, y)
	_draw_ambient()
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
	match str(grid[y][x]):
		"#":
			_draw_building(x, y)
		"C":
			_draw_store(x, y)
		"B":
			_draw_crowd(x, y)
		"P":
			_draw_mat(x, y)
		"T":
			_draw_tree(x, y)
		_:
			_draw_floor(x, y)

func _draw_ambient() -> void:
	var theme := _theme()
	if theme == "park":
		# Street lamps glow pools.
		for i: int in 4:
			var lx := (3 + i * 5) * TILE + 8
			draw_circle(Vector2(lx, 5 * TILE), 22.0, Color(1.0, 0.85, 0.5, 0.05))
		return
	# Neon spill onto the street in front of each lit facade.
	for y: int in ROWS - 1:
		for x: int in COLS:
			if grid[y][x] == "#" and not _is_wall(x, y + 1):
				var c: Color = NEON[(_h(x, y, 20) / 7) % NEON.size()]
				var a := 0.10 + 0.04 * sin(_clock * 2.0 + x)
				draw_rect(Rect2(x * TILE, (y + 1) * TILE, TILE, 7), Color(c, a))
	if theme == "club":
		# Sweeping club spotlights.
		for i: int in 3:
			var t := _clock * (0.6 + i * 0.25) + i * 2.1
			var center := Vector2(160 + cos(t) * 120.0, 80 + sin(t * 1.3) * 50.0)
			draw_circle(center, 18.0, Color(NEON[i], 0.08))
			draw_circle(center, 10.0, Color(NEON[i], 0.07))

func _draw_goal() -> void:
	var r := Rect2(goal_tile.x * TILE, goal_tile.y * TILE, TILE, TILE)
	var pulse := 0.5 + 0.5 * sin(_clock * 4.0)
	draw_circle(r.get_center(), 12.0 + pulse * 3.0, Color(1.0, 0.82, 0.25, 0.18))
	draw_rect(r, Color("ffd23f"))
	draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(14, 14)), Color("ff9f1c"))
	draw_rect(Rect2(r.position + Vector2(3, 3), Vector2(10, 10)), Color("ffd23f").lerp(Color.WHITE, pulse * 0.3))
	# Arrow pointing in.
	draw_rect(Rect2(r.position + Vector2(7, 5), Vector2(2, 5)), Color("7a2e00"))
	draw_rect(Rect2(r.position + Vector2(5, 8), Vector2(6, 1)), Color("7a2e00"))
	draw_rect(Rect2(r.position + Vector2(6, 9), Vector2(4, 1)), Color("7a2e00"))

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
