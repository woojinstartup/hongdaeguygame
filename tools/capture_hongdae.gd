extends SceneTree
# Native renderer captures for visual review; tools/ is excluded from exports.
func _initialize() -> void:
	call_deferred("_capture")

func _shot(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)

func _capture() -> void:
	var out := OS.get_environment("HE_CAPTURE_DIR")
	var main: Variant = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _shot(out + "/title.png")
	main._start_new_run()
	var world: Variant = main._world
	world.move_override = Vector2.ZERO
	for i: int in 50:
		world.step(1.0 / 60.0)
	world.player_pos = world.tile_center(Vector2i(5, 5))
	world.enemies[0]["state"] = "alert"
	world.add_bubble(world.enemies[0]["pos"], "Are you open-minded?", Color("ff4fa3"))
	world.set_physics_process(false)
	main._update_hud()
	await _shot(out + "/stage1.png")
	for idx: int in [1, 2, 3]:
		main._stage_index = idx
		world.load_stage(idx, {"shield": 1})
		for i: int in 150:
			world.step(1.0 / 60.0)
		world.active = true
		world.set_physics_process(false)
		main._update_hud()
		await _shot(out + "/stage%d.png" % (idx + 1))
	world.shield = 0
	world.grace_time = 0.0
	world._on_contact(0)
	main._update_encounter(1.0)
	await _shot(out + "/encounter.png")
	quit(0)
