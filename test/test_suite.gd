extends Node
## Hongdae Escape gameplay checks. Drives real world steps, dialogue choices and main-flow actions.

var _failures := PackedStringArray()
var _checks := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_stages()
	_test_dialogue()
	_test_world_detection_and_contact()
	_test_world_hiding_items_and_shield()
	_test_corner_assist()
	_test_boss_bullets()
	await _test_main_flow()
	if _failures.is_empty():
		print("[game-generic-tests] PASS: %d checks" % _checks)
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[game-generic-tests] " + failure)
	print("[game-generic-tests] FAIL: %d failures across %d checks" % [_failures.size(), _checks])
	get_tree().quit(1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)

func _new_world(index: int) -> HEWorld:
	var w := HEWorld.new()
	add_child(w)
	w.set_physics_process(false)
	w.load_stage(index)
	return w

func _step(w: HEWorld, seconds: float, dir: Vector2 = Vector2.ZERO) -> void:
	w.move_override = dir
	var t := 0.0
	while t < seconds and w.active:
		w.step(1.0 / 60.0)
		t += 1.0 / 60.0

func _test_stages() -> void:
	_check(HEStageData.count() == 4, "four stages")
	for i: int in HEStageData.count():
		var st := HEStageData.get_stage(i)
		var m: Array = st["map"]
		_check(m.size() == 10, "stage %d has 10 rows" % i)
		for row: String in m:
			_check(row.length() == 20, "stage %d row width 20" % i)
		var w := _new_world(i)
		var start := w.tile_of(w.player_start)
		var seen := {start: true}
		var queue: Array[Vector2i] = [start]
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_front()
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := cur + d
				if not seen.has(n) and not w.is_solid_for_player(n):
					seen[n] = true
					queue.append(n)
		_check(seen.has(w.goal_tile), "stage %d goal reachable" % i)
		for e: Dictionary in w.enemies:
			for t: Vector2i in e["route"]:
				_check(not w.is_solid_for_enemy(t), "stage %d enemy route tile %s walkable" % [i, t])
		w.free()
	var boss_found := false
	for e: Dictionary in HEStageData.get_stage(3)["enemies"]:
		boss_found = boss_found or e["kind"] == "boss"
	_check(boss_found, "club street has the boss")

func _test_dialogue() -> void:
	var d := HEDialogue.new()
	d.start("basic", 1)
	_check(d.options.size() == 3 and not d.line().is_empty(), "dialogue has line and 3 options")
	_check(d.choose(d.index_of_kind("witty")).get("result") == "escape", "witty reply escapes")
	d.start("basic", 2)
	_check(d.choose(d.index_of_kind("risky")).get("result") == "continue", "risky reply continues")
	_check(d.round_index == 2, "risky advances round")
	d.choose(d.index_of_kind("risky"))
	_check(d.choose(d.index_of_kind("risky")).get("result") == "fail", "three risky replies fail")
	d.start("dasher", 3)
	_check(d.choose(d.index_of_kind("evasive"), 0.1).get("result") == "escape", "lucky evasive escapes")
	d.start("dasher", 4)
	_check(d.choose(d.index_of_kind("evasive"), 0.9).get("result") == "continue", "unlucky evasive continues")
	d.start("boss", 5)
	_check(d.wins_needed == 2, "boss needs two burns")
	_check(d.choose(d.index_of_kind("witty")).get("result") == "continue", "first boss burn continues")
	_check(d.choose(d.index_of_kind("witty")).get("result") == "escape", "second boss burn escapes")
	d.start("photo", 6)
	_check(d.tick(HEDialogue.ROUND_TIME + 0.1).get("result") == "fail", "timeout fails")

func _test_world_detection_and_contact() -> void:
	var w := _new_world(0)
	var e: Dictionary = w.enemies[0]
	e["pos"] = w.tile_center(Vector2i(8, 5))
	e["facing"] = Vector2.RIGHT
	e["route"] = [Vector2i(8, 5)]
	w.enemies[1]["pos"] = w.tile_center(Vector2i(18, 1))
	w.enemies[1]["route"] = [Vector2i(18, 1)]
	w.player_pos = w.tile_center(Vector2i(11, 5))
	w.grace_time = 0.0
	_check(w.can_see_player(e), "enemy sees player in cone")
	var started := [""]
	w.encounter_started.connect(func(kind: String) -> void: started[0] = kind)
	_step(w, 0.2)
	_check(e["state"] == "alert", "enemy alerts (red !) when player spotted")
	_step(w, 3.0)
	_check(started[0] == "basic", "chase reaches player and starts dialogue battle")
	_check(not w.active, "world pauses during encounter")
	w.resolve_encounter_win()
	_check(w.active and e["state"] == "stunned", "winning stuns the guy and resumes")
	var w2 := _new_world(0)
	var e2: Dictionary = w2.enemies[0]
	e2["pos"] = w2.tile_center(Vector2i(12, 5))
	e2["facing"] = Vector2.RIGHT
	w2.player_pos = w2.tile_center(Vector2i(10, 5))
	_check(not w2.can_see_player(e2), "enemy does not see behind")
	w.free()
	w2.free()

func _test_world_hiding_items_and_shield() -> void:
	var w := _new_world(0)
	w.player_pos = w.tile_center(Vector2i(13, 1))
	for en: Dictionary in w.enemies:
		en["pos"] = w.tile_center(Vector2i(1, 8))
		en["route"] = [Vector2i(1, 8)]
	_step(w, 0.4, Vector2.RIGHT)
	_check(int(w.inventory["airpods"]) == 1, "walking onto AirPods collects them")
	_check(w.use_item("airpods") and w.airpods_time > 0.0, "AirPods activate")
	_check(not w.use_item("airpods"), "cannot use an item you do not have")
	w.player_pos = w.tile_center(Vector2i(12, 3))
	_check(w.player_hidden() and w.player_in_store(), "store tile hides player")
	var e: Dictionary = w.enemies[0]
	e["pos"] = w.tile_center(Vector2i(12, 5))
	e["facing"] = Vector2.UP
	_check(not w.can_see_player(e), "hidden player is not seen")
	w.airpods_time = 0.0
	w.shield = 1
	w.grace_time = 0.0
	w.player_pos = w.tile_center(Vector2i(5, 5))
	e["pos"] = w.player_pos + Vector2(4, 0)
	e["state"] = "chase"
	e["cooldown"] = 0.0
	var blocked := [false]
	w.shield_blocked.connect(func() -> void: blocked[0] = true)
	_step(w, 0.05)
	_check(blocked[0] and w.shield == 0 and w.active, "boyfriend shield blocks one encounter")
	w.inventory["noenglish"] = 1
	e["state"] = "patrol"
	e["cooldown"] = 0.0
	e["pos"] = w.player_pos + Vector2(30, 0)
	_check(w.use_item("noenglish") and e["state"] == "confused", "No English confuses nearby guy")
	w.inventory["friend"] = 1
	e["state"] = "chase"
	e["pos"] = w.player_pos + Vector2(20, 0)
	var before: float = e["pos"].distance_to(w.player_pos)
	_check(w.use_item("friend"), "call a friend")
	_step(w, 0.5)
	_check(e["pos"].distance_to(w.player_pos) >= before, "friend makes guys back off")
	var cleared := [false]
	w.stage_cleared.connect(func() -> void: cleared[0] = true)
	w.player_pos = w.tile_center(Vector2i(18, 7))
	for en: Dictionary in w.enemies:
		en["state"] = "stunned"
		en["timer"] = 10.0
	_step(w, 1.0, Vector2.DOWN)
	_check(cleared[0], "reaching the goal clears the stage")
	w.free()

func _test_boss_bullets() -> void:
	var w := _new_world(3)
	var boss: Dictionary = w.enemies[0]
	_check(boss["kind"] == "boss", "boss loaded")
	for i: int in range(1, w.enemies.size()):
		w.enemies[i]["state"] = "stunned"
		w.enemies[i]["timer"] = 99.0
	w.player_pos = w.tile_center(Vector2i(18, 3))
	w.grace_time = 0.0
	var kinds := [""]
	w.encounter_started.connect(func(kind: String) -> void: kinds[0] = kind)
	_step(w, 6.0)
	_check(kinds[0] == "boss", "boss pickup-line bullets trigger the King battle")
	w.free()

func _test_main_flow() -> void:
	var main: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame
	var world: HEWorld = main.get("_world")
	_check(main.get("_screen") == "title" and (main.get("_title_screen") as Control).visible, "boots to title")
	main.call("_start_new_run")
	world.set_physics_process(false)
	_check(main.get("_screen") == "playing" and world.active, "play starts stage 1")
	world.call("_on_contact", 0)
	_check(main.get("_screen") == "encounter", "contact opens dialogue battle")
	main.call("_update_encounter", 1.0)
	var dlg: HEDialogue = main.get("_dialogue")
	main.call("_choose_option", dlg.index_of_kind("witty"))
	main.call("_update_encounter", 2.0)
	world.set_physics_process(false)
	_check(main.get("_screen") == "playing" and int(main.get("_escapes")) == 1, "witty win returns to play")
	_check(int(main.get("_score")) >= 200, "escape scores points")
	world.call("_on_contact", 1)
	main.call("_update_encounter", 1.0)
	for i: int in 3:
		main.call("_choose_option", dlg.index_of_kind("risky"))
	main.call("_update_encounter", 2.0)
	world.set_physics_process(false)
	_check(int(main.get("_lives")) == 2 and world.player_pos == world.player_start, "failed battle costs a life and respawns")
	main.call("_show_screen", "paused")
	main.call("_resume")
	world.set_physics_process(false)
	_check(main.get("_screen") == "playing", "pause and resume")
	world.stage_cleared.emit()
	_check(main.get("_screen") == "stage_clear", "stage clear screen")
	main.call("_advance_stage")
	world.set_physics_process(false)
	_check(int(main.get("_stage_index")) == 1 and world.stage_index == 1, "advance to Walking Street")
	main.set("_stage_index", 3)
	world.load_stage(3)
	world.stage_cleared.emit()
	_check(main.get("_screen") == "result", "final clear shows ending")
	_check(str((main.get("_result_title") as Label).text) == "AIRPORT ENDING", "airport ending with lost lives")
	main.call("_start_new_run")
	world.set_physics_process(false)
	main.set("_lives", 1)
	world.call("_on_contact", 0)
	main.call("_update_encounter", 1.0)
	dlg.time_left = 0.01
	main.call("_update_encounter", 0.1)
	main.call("_update_encounter", 2.0)
	_check(main.get("_screen") == "result" and str((main.get("_result_title") as Label).text) == "GAME OVER", "losing last life is game over")
	main.call("_start_new_run")
	world.set_physics_process(false)
	main.set("_stage_index", 3)
	world.load_stage(3)
	world.stage_cleared.emit()
	_check(str((main.get("_result_title") as Label).text) == "HOTEL ENDING", "hotel ending with full lives")
	main.call("_submit_score")
	_check(bool(main.get("_submitted")), "score saves to local leaderboard")
	main.queue_free()
	await get_tree().process_frame

func _test_corner_assist() -> void:
	var w := _new_world(0)
	for en: Dictionary in w.enemies:
		en["pos"] = w.tile_center(Vector2i(1, 8))
		en["route"] = [Vector2i(1, 8)]
	w.player_pos = w.tile_center(Vector2i(5, 1)) + Vector2(5, 0)
	_step(w, 0.6, Vector2.DOWN)
	_check(w.tile_of(w.player_pos).y >= 2, "off-centre player still turns into a one-tile side street")
	w.free()
