extends SceneTree
var _failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_verify")
func _verify() -> void:
	_check(ProjectSettings.get_setting("application/config/name") == "Hongdae Escape", "exported identity")
	for path: String in ["fonts/Figtree-VF.subset.woff2", "fonts/ui_bold.tres", "fonts/ui_regular.tres"]:
		_check(ResourceLoader.exists("res://assets/template/" + path), "pack resource: " + path)
	_check(not ResourceLoader.exists("res://test/test_suite.tscn"), "test scene excluded")
	_check(not ResourceLoader.exists("res://tools/capture_native.gd"), "native capture tool excluded")
	var font := load("res://assets/template/fonts/ui_bold.tres") as Font
	_check(font != null, "exported font")
	for ch: String in "ABCXYZabcxyz0123456789'\"?!*-.,/()[]":
		_check(font != null and font.has_char(ch.unicode_at(0)), "exported glyph: " + ch)
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "exported main scene")
	if packed != null:
		var main := packed.instantiate()
		root.add_child(main)
		await process_frame
		await process_frame
		_check(bool((main.get("_title_screen") as Control).visible), "pack boots to title")
		main.call("_start_new_run")
		await process_frame
		var world: Variant = main.get("_world")
		_check(world != null and bool(world.get("active")), "pack starts gameplay")
		main.queue_free()
		await process_frame
	if _failures.is_empty():
		print("[exported-pack] PASS: identity, fonts, exclusions, boot, gameplay")
		quit(0)
	else:
		for failure: String in _failures:
			push_error("[exported-pack] " + failure)
		quit(1)
func _check(condition: bool, context: String) -> void:
	if not condition and context not in _failures:
		_failures.append(context)
