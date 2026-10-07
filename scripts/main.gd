extends Control
## Hongdae Escape: title, HUD, dialogue battles, pause, results and a local leaderboard.

const OpenSourceLicenses = preload("res://scripts/manus/open_source_licenses.gd")
const PortraitScript := preload("res://scripts/hongdae/portrait.gd")
const OverlayScript := preload("res://scripts/hongdae/overlay.gd")
const FONT_BOLD := preload("res://assets/template/fonts/ui_bold.tres")
const FONT_REG := preload("res://assets/template/fonts/ui_regular.tres")

const BASE_SIZE := Vector2(1280, 720)
const WORLD_SCALE := 4.0
const WORLD_OFFSET := Vector2(0, 80)
const START_LIVES := 3
const STAGE_CLEAR_POINTS := 1000
const ESCAPE_POINTS := 200
const ITEM_POINTS := 50
const PINK := Color("ff2e88")
const PURPLE := Color("b14aed")
const YELLOW := Color("ffd23f")
const INK := Color("0f0819")
const TEXT := Color("f5ecff")
const MUTED := Color("b9a7d6")
const KIND_NAMES := {
	"basic": "Leather Jacket Guy", "dasher": "iPhone Dasher", "trio": "Trio Squad Member",
	"photo": "'Photographer'", "boss": "THE HONGDAE GUY KING",
}

var _world: HEWorld
var _overlay: Control
const SAVE_PATH := "user://hongdae_scores.json"

var _title_screen: Control
var _name_input: LineEdit
var _title_status: Label
var _hud: Control
var _hud_stage: Label
var _hud_stats: Label
var _hud_items: Label
var _hud_hint: Label
var _encounter_screen: Control
var _portrait: Control
var _enc_name: Label
var _enc_cutin: Label
var _enc_line: Label
var _enc_round: Label
var _enc_timer: ProgressBar
var _enc_message: Label
var _enc_buttons: Array[Button] = []
var _pause_screen: Control
var _stage_screen: Control
var _stage_title: Label
var _stage_body: Label
var _result_screen: Control
var _result_title: Label
var _result_body: Label
var _result_score: Label
var _submit_button: Button
var _result_status: Label
var _leaderboard_screen: Control
var _leaderboard_rows: VBoxContainer
var _leaderboard_status: Label
var _leaderboard_return := "title"
var _howto_screen: Control

var _screen := "title"
var _stage_index := 0
var _lives := START_LIVES
var _retry_pending := false
var _score := 0
var _escapes := 0
var _run_elapsed := 0.0
var _run_completed := false
var _dialogue: HEDialogue
var _enc_phase := ""
var _enc_phase_time := 0.0
var _enc_outcome := ""
var _submitted := false
var _last_stage_bonus := 0

func _ready() -> void:
	var i18n := get_node_or_null("/root/I18n")
	if i18n != null and i18n.has_method("set_locale"):
		i18n.call("set_locale", "en")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_world = HEWorld.new()
	_world.name = "World"
	_world.scale = Vector2(WORLD_SCALE, WORLD_SCALE)
	_world.position = WORLD_OFFSET
	_world.visible = false
	add_child(_world)
	_world.encounter_started.connect(_on_encounter_started)
	_world.stage_cleared.connect(_on_stage_cleared)
	_world.item_collected.connect(_on_item_collected)
	_overlay = OverlayScript.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.set("world", _world)
	_overlay.set("world_scale", WORLD_SCALE)
	_overlay.set("world_offset", WORLD_OFFSET)
	add_child(_overlay)
	_dialogue = HEDialogue.new()
	_build_hud()
	_build_title()
	_build_howto()
	_build_encounter()
	_build_pause()
	_build_stage_screen()
	_build_result()
	_build_leaderboard()
	_show_screen("title")

# ------------------------------------------------------------------ UI helpers

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

func _label(text: String, size: int, color: Color = TEXT, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT_BOLD if bold else FONT_REG)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _button(text: String, size: int = 24) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", FONT_BOLD)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_focus_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("2b1840")
	normal.border_color = PINK
	normal.set_border_width_all(3)
	normal.set_content_margin_all(12)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = PINK
	hover.border_color = YELLOW
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("pressed", hover)
	return b

func _panel(min_size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.03, 0.12, 0.95)
	sb.border_color = PURPLE
	sb.set_border_width_all(4)
	sb.set_content_margin_all(28)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = min_size
	return p

func _overlay_screen(dim: float = 0.7) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.01, 0.06, dim)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	add_child(root)
	return root

func _centered(root: Control, child: Control) -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.add_child(child)
	root.add_child(center)

# ------------------------------------------------------------------ screens

func _build_hud() -> void:
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	var bar := ColorRect.new()
	bar.color = Color("150b24")
	bar.size = Vector2(BASE_SIZE.x, WORLD_OFFSET.y)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(bar)
	var line := ColorRect.new()
	line.color = PINK
	line.position = Vector2(0, WORLD_OFFSET.y - 3)
	line.size = Vector2(BASE_SIZE.x, 3)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(line)
	_hud_stage = _label("", 22, YELLOW, true)
	_hud_stage.position = Vector2(16, 6)
	_hud_stage.size = Vector2(600, 30)
	_hud.add_child(_hud_stage)
	_hud_stats = _label("", 22, TEXT, true)
	_hud_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud_stats.position = Vector2(620, 6)
	_hud_stats.size = Vector2(644, 30)
	_hud.add_child(_hud_stats)
	_hud_items = _label("", 17, MUTED)
	_hud_items.position = Vector2(16, 42)
	_hud_items.size = Vector2(1250, 26)
	_hud.add_child(_hud_items)
	_hud_hint = _label("", 18, TEXT, true)
	_hud_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_hint.position = Vector2(0, BASE_SIZE.y - 40)
	_hud_hint.size = Vector2(BASE_SIZE.x, 32)
	_hud_hint.add_theme_color_override("font_outline_color", INK)
	_hud_hint.add_theme_constant_override("outline_size", 8)
	_hud.add_child(_hud_hint)

func _build_title() -> void:
	_title_screen = _overlay_screen(0.0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var eyebrow := _label("A PIXEL SATIRE OF THE 'HONGDAE GUY' MEME", 18, MUTED, true)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(eyebrow)
	var title := _label("HONGDAE ESCAPE", 84, PINK, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", PURPLE)
	title.add_theme_constant_override("outline_size", 14)
	box.add_child(title)
	var sub := _label("Are You Open-Mindeu?  (No.)", 30, YELLOW, true)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var tag := _label("You're a tourist in Hongdae. Leather jackets are everywhere. Get to your hotel.", 20, TEXT)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.custom_minimum_size = Vector2(900, 0)
	box.add_child(tag)
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 12)
	var name_label := _label("Your name:", 20, MUTED, true)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(name_label)
	_name_input = LineEdit.new()
	_name_input.text = "Tourist%03d" % (randi() % 1000)
	_name_input.max_length = 20
	_name_input.custom_minimum_size = Vector2(260, 44)
	_name_input.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name_input.add_theme_font_override("font", FONT_BOLD)
	_name_input.add_theme_font_size_override("font_size", 20)
	name_row.add_child(_name_input)
	box.add_child(name_row)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 18)
	var play := _button("PLAY  [Enter]", 28)
	play.name = "PlayButton"
	play.pressed.connect(_start_new_run)
	buttons.add_child(play)
	var howto := _button("How to Play")
	howto.pressed.connect(func() -> void: _show_screen("howto"))
	buttons.add_child(howto)
	var board := _button("Leaderboard")
	board.pressed.connect(_open_leaderboard)
	buttons.add_child(board)
	box.add_child(buttons)
	_title_status = _label("WASD/Arrows move - 1/2/3 items - Esc pause", 16, MUTED)
	_title_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title_status)
	var licenses := _button("Open Source Licenses", 14)
	licenses.name = "OpenSourceLicensesButton"
	licenses.pressed.connect(OpenSourceLicenses.open.bind(self))
	var lic_row := HBoxContainer.new()
	lic_row.alignment = BoxContainer.ALIGNMENT_CENTER
	lic_row.add_child(licenses)
	box.add_child(lic_row)
	_centered(_title_screen, box)

func _build_howto() -> void:
	_howto_screen = _overlay_screen(0.85)
	var panel := _panel(Vector2(900, 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.add_child(_label("HOW TO ESCAPE HONGDAE", 34, PINK, true))
	for line: String in [
		"WASD / Arrow keys - walk. Reach the yellow goal tile.",
		"Pink cones = where a Hongdae guy is looking. Red '!' = he spotted you and is coming.",
		"Busking crowds hide you (but slow you). The green 24/7 store is a safe zone.",
		"Caught? Dialogue battle! Pick a witty comeback (escape), a risky reply (he keeps going) or an evasive move (maybe).",
		"Lose a battle = lose a life and restart the stage. 3 lives.",
		"[1] AirPods - 6s, you can't hear them.   [2] Call a Friend - 6s, they back off.",
		"[3] 'No English' - confuses nearby guys.   'I have a boyfriend' - blocks one encounter automatically.",
		"Esc - pause.  Beware the photographer, the iPhone dasher, the trio, and the KING.",
	]:
		var l := _label(line, 20, TEXT)
		l.custom_minimum_size = Vector2(840, 0)
		box.add_child(l)
	var back := _button("Back")
	back.pressed.connect(func() -> void: _show_screen("title"))
	box.add_child(back)
	panel.add_child(box)
	_centered(_howto_screen, panel)

func _build_encounter() -> void:
	_encounter_screen = _overlay_screen(0.82)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	_portrait = PortraitScript.new()
	_portrait.custom_minimum_size = Vector2(420, 460)
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_portrait)
	var panel := _panel(Vector2(740, 460))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_enc_name = _label("", 20, MUTED, true)
	box.add_child(_enc_name)
	_enc_cutin = _label("Are you open mindeu?", 64, PINK, true)
	_enc_cutin.add_theme_color_override("font_outline_color", YELLOW)
	_enc_cutin.add_theme_constant_override("outline_size", 6)
	box.add_child(_enc_cutin)
	_enc_line = _label("", 28, YELLOW, true)
	_enc_line.custom_minimum_size = Vector2(700, 0)
	box.add_child(_enc_line)
	_enc_round = _label("", 16, MUTED)
	box.add_child(_enc_round)
	_enc_timer = ProgressBar.new()
	_enc_timer.max_value = HEDialogue.ROUND_TIME
	_enc_timer.show_percentage = false
	_enc_timer.custom_minimum_size = Vector2(700, 10)
	var fill := StyleBoxFlat.new()
	fill.bg_color = PINK
	_enc_timer.add_theme_stylebox_override("fill", fill)
	box.add_child(_enc_timer)
	for i: int in 3:
		var b := _button("", 20)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(700, 0)
		b.pressed.connect(_choose_option.bind(i))
		_enc_buttons.append(b)
		box.add_child(b)
	_enc_message = _label("", 22, TEXT, true)
	_enc_message.custom_minimum_size = Vector2(700, 0)
	box.add_child(_enc_message)
	panel.add_child(box)
	row.add_child(panel)
	_centered(_encounter_screen, row)

func _build_pause() -> void:
	_pause_screen = _overlay_screen(0.75)
	var panel := _panel(Vector2(440, 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	var t := _label("PAUSED", 40, PINK, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var resume := _button("Resume")
	resume.name = "ResumeButton"
	resume.pressed.connect(_resume)
	box.add_child(resume)
	var restart := _button("Restart run")
	restart.pressed.connect(_start_new_run)
	box.add_child(restart)
	var quit := _button("Quit to title")
	quit.pressed.connect(_return_to_title)
	box.add_child(quit)
	panel.add_child(box)
	_centered(_pause_screen, panel)

func _build_stage_screen() -> void:
	_stage_screen = _overlay_screen(0.7)
	var panel := _panel(Vector2(640, 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_stage_title = _label("", 36, YELLOW, true)
	_stage_title.custom_minimum_size = Vector2(580, 0)
	box.add_child(_stage_title)
	_stage_body = _label("", 22, TEXT)
	_stage_body.custom_minimum_size = Vector2(580, 0)
	box.add_child(_stage_body)
	var next := _button("Continue  [Enter]")
	next.name = "ContinueButton"
	next.pressed.connect(_advance_stage)
	box.add_child(next)
	panel.add_child(box)
	_centered(_stage_screen, panel)

func _build_result() -> void:
	_result_screen = _overlay_screen(0.85)
	var panel := _panel(Vector2(760, 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_result_title = _label("", 42, PINK, true)
	box.add_child(_result_title)
	_result_body = _label("", 22, TEXT)
	_result_body.custom_minimum_size = Vector2(700, 0)
	box.add_child(_result_body)
	_result_score = _label("", 30, YELLOW, true)
	box.add_child(_result_score)
	_submit_button = _button("Save to leaderboard")
	_submit_button.pressed.connect(_submit_score)
	box.add_child(_submit_button)
	_result_status = _label("", 18, MUTED)
	_result_status.custom_minimum_size = Vector2(700, 0)
	box.add_child(_result_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var again := _button("Play again  [Enter]")
	again.name = "PlayAgainButton"
	again.pressed.connect(_start_new_run)
	row.add_child(again)
	var board := _button("Leaderboard")
	board.pressed.connect(_open_leaderboard)
	row.add_child(board)
	var title := _button("Title")
	title.pressed.connect(_return_to_title)
	row.add_child(title)
	box.add_child(row)
	panel.add_child(box)
	_centered(_result_screen, panel)

func _build_leaderboard() -> void:
	_leaderboard_screen = _overlay_screen(0.88)
	var panel := _panel(Vector2(700, 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.add_child(_label("ESCAPE ARTISTS - TOP 10 (this device)", 30, PINK, true))
	_leaderboard_status = _label("", 18, MUTED)
	_leaderboard_status.custom_minimum_size = Vector2(640, 0)
	box.add_child(_leaderboard_status)
	_leaderboard_rows = VBoxContainer.new()
	box.add_child(_leaderboard_rows)
	var back := _button("Back")
	back.pressed.connect(_leaderboard_back)
	box.add_child(back)
	panel.add_child(box)
	_centered(_leaderboard_screen, panel)

func _show_screen(screen: String) -> void:
	_screen = screen
	var in_run := screen in ["playing", "encounter", "paused", "stage_clear"]
	_world.visible = in_run
	_overlay.visible = in_run
	_hud.visible = in_run
	_title_screen.visible = screen == "title"
	_howto_screen.visible = screen == "howto"
	_encounter_screen.visible = screen == "encounter"
	_pause_screen.visible = screen == "paused"
	_stage_screen.visible = screen == "stage_clear"
	_result_screen.visible = screen == "result"
	_leaderboard_screen.visible = screen == "leaderboard"
	_world.set_physics_process(screen == "playing")

# ------------------------------------------------------------------ run flow

func _start_new_run() -> void:
	_stage_index = 0
	_retry_pending = false
	_lives = START_LIVES
	_score = 0
	_escapes = 0
	_run_elapsed = 0.0
	_run_completed = false
	_submitted = false
	_world.load_stage(0)
	_update_hud()
	_show_screen("playing")

func _player_name() -> String:
	var n := _name_input.text.strip_edges()
	return n if not n.is_empty() else "Tourist"

func _process(delta: float) -> void:
	if _screen == "playing":
		_run_elapsed += delta
		_update_hud()
	elif _screen == "encounter":
		_update_encounter(delta)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := (event as InputEventKey).physical_keycode
	var handled := true
	match _screen:
		"playing":
			if event.is_action("pause"):
				_show_screen("paused")
			elif key == KEY_1:
				_world.use_item("airpods")
			elif key == KEY_2:
				_world.use_item("friend")
			elif key == KEY_3:
				_world.use_item("noenglish")
			else:
				handled = false
		"paused":
			if event.is_action("pause"):
				_resume()
			else:
				handled = false
		"encounter":
			if key in [KEY_1, KEY_2, KEY_3]:
				_choose_option(key - KEY_1)
			else:
				handled = false
		"stage_clear":
			if key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
				_advance_stage()
			else:
				handled = false
		"title":
			if key in [KEY_ENTER, KEY_KP_ENTER]:
				_start_new_run()
			else:
				handled = false
		"result":
			if key in [KEY_ENTER, KEY_KP_ENTER]:
				_start_new_run()
			else:
				handled = false
		"howto":
			if event.is_action("pause"):
				_show_screen("title")
			else:
				handled = false
		"leaderboard":
			if event.is_action("pause"):
				_leaderboard_back()
			else:
				handled = false
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()

func _resume() -> void:
	if _screen == "paused":
		_show_screen("playing")

func _return_to_title() -> void:
	_world.active = false
	_show_screen("title")

func _on_item_collected(_item: String) -> void:
	_score += ITEM_POINTS

func _on_stage_cleared() -> void:
	_last_stage_bonus = STAGE_CLEAR_POINTS + maxi(0, int((90.0 - _world.elapsed) * 10.0))
	_score += _last_stage_bonus
	if _stage_index >= HEStageData.count() - 1:
		_finish_run(true)
		return
	_stage_title.text = "CLEARED: %s" % HEStageData.get_stage(_stage_index)["name"]
	_stage_body.text = "+%d points (stage + speed bonus).\nNext: %s" % [_last_stage_bonus, HEStageData.get_stage(_stage_index + 1)["name"]]
	_show_screen("stage_clear")

## Losing a battle on the final stage costs a life and sends you back one stage.
func _offer_stage_retry(target_index: int) -> void:
	_retry_pending = true
	_stage_index = clampi(target_index, 0, HEStageData.count() - 1)
	_world.active = false
	_stage_title.text = "CAUGHT BY THE KING!"
	_stage_body.text = "He got your Insta... -1 life.\nBack to STAGE %d/%d with %d %s left: %s" % [_stage_index + 1, HEStageData.count(), _lives, "life" if _lives == 1 else "lives", HEStageData.get_stage(_stage_index)["name"]]
	_show_screen("stage_clear")

func _advance_stage() -> void:
	if _screen != "stage_clear":
		return
	if _retry_pending:
		_retry_pending = false
		_world.load_stage(_stage_index, {"inventory": _world.inventory, "shield": _world.shield})
		_update_hud()
		_show_screen("playing")
		return
	_stage_index += 1
	_world.load_stage(_stage_index, {"inventory": _world.inventory, "shield": _world.shield})
	_show_screen("playing")

func _finish_run(completed: bool) -> void:
	_run_completed = completed
	_world.active = false
	if completed:
		_score += _lives * 500
		if _lives >= START_LIVES:
			_result_title.text = "HOTEL ENDING"
			_result_body.text = "You reached your hotel without losing a single life. Zero Instagram follows. Zero 'open minds'. A perfect night in Hongdae."
		else:
			_result_title.text = "AIRPORT ENDING"
			_result_body.text = "You made it out... straight to Incheon Airport. You changed your flight to tonight. Hongdae was a lot."
	else:
		_result_title.text = "GAME OVER"
		_result_body.text = "He got your Instagram. Your DMs will never recover.\nCaught at: %s." % HEStageData.get_stage(_stage_index)["name"]
	_result_score.text = "Score: %d    Escapes: %d    Time: %ds" % [_score, _escapes, int(_run_elapsed)]
	_submit_button.disabled = false
	_result_status.text = "Save as '%s'." % _player_name()
	_show_screen("result")

func _load_scores() -> Array:
	if not FileAccess.file_exists(SAVE_PATH):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	return parsed if parsed is Array else []

func _submit_score() -> void:
	if _submitted:
		return
	var rows := _load_scores()
	rows.append({"name": _player_name(), "score": _score, "ending": _result_title.text})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["score"]) > int(b["score"]))
	rows = rows.slice(0, 10)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		_result_status.text = "Could not save on this device."
		return
	f.store_string(JSON.stringify(rows))
	f.close()
	_submitted = true
	_submit_button.disabled = true
	_result_status.text = "Saved! Check the leaderboard."

func _open_leaderboard() -> void:
	_leaderboard_return = _screen if _screen in ["title", "result"] else "title"
	_show_screen("leaderboard")
	for c: Node in _leaderboard_rows.get_children():
		c.queue_free()
	var rows := _load_scores()
	_leaderboard_status.text = "No escapes yet. Be the first!" if rows.is_empty() else ""
	var rank := 1
	for row: Dictionary in rows:
		_leaderboard_rows.add_child(_label("#%d   %s   %d   (%s)" % [rank, str(row.get("name", "?")), int(row.get("score", 0)), str(row.get("ending", ""))], 22, TEXT, true))
		rank += 1

func _leaderboard_back() -> void:
	_show_screen(_leaderboard_return)

# ------------------------------------------------------------------ encounters

func _on_encounter_started(kind: String) -> void:
	_dialogue.start(kind)
	_portrait.call("set_kind", kind)
	_enc_name.text = str(KIND_NAMES.get(kind, "Hongdae Guy")) + " approaches!"
	_enc_phase = "cutin"
	_enc_phase_time = 0.9
	_enc_cutin.visible = true
	_enc_cutin.text = "OPEN MINDEU?!" if kind == "boss" else "Are you open mindeu?"
	_enc_message.text = ""
	_enc_line.text = ""
	_enc_round.text = ""
	_set_options_visible(false)
	_show_screen("encounter")

func _set_options_visible(on: bool) -> void:
	for i: int in _enc_buttons.size():
		var b := _enc_buttons[i]
		b.visible = on
		b.disabled = not on
		if on and i < _dialogue.options.size():
			b.text = "[%d]  %s" % [i + 1, _dialogue.options[i]["text"]]
	_enc_timer.visible = on

func _show_dialogue_round() -> void:
	_enc_phase = "choose"
	_enc_cutin.visible = false
	_enc_line.text = "\"%s\"" % _dialogue.line()
	var need := ("  (needs %d witty burns)" % _dialogue.wins_needed) if _dialogue.wins_needed > 1 else ""
	_enc_round.text = "Round %d / %d%s   - pick with 1 / 2 / 3" % [_dialogue.round_index, HEDialogue.MAX_ROUNDS, need]
	_set_options_visible(true)
	_enc_timer.value = _dialogue.time_left

func _update_encounter(delta: float) -> void:
	match _enc_phase:
		"cutin":
			_enc_phase_time -= delta
			if _enc_phase_time <= 0.0:
				_show_dialogue_round()
		"choose":
			var r := _dialogue.tick(delta)
			_enc_timer.value = _dialogue.time_left
			if not r.is_empty():
				_apply_choice_result(r)
		"result":
			_enc_phase_time -= delta
			if _enc_phase_time <= 0.0:
				_close_encounter()

func _choose_option(index: int) -> void:
	if _screen != "encounter" or _enc_phase != "choose":
		return
	var r := _dialogue.choose(index)
	if not r.is_empty():
		_apply_choice_result(r)

func _apply_choice_result(r: Dictionary) -> void:
	_enc_message.text = str(r.get("message", ""))
	match str(r.get("result", "")):
		"continue":
			_show_dialogue_round()
		"escape", "fail":
			_enc_outcome = str(r["result"])
			_enc_phase = "result"
			_enc_phase_time = 1.4
			_set_options_visible(false)

func _close_encounter() -> void:
	_enc_phase = ""
	if _enc_outcome == "escape":
		_escapes += 1
		_score += ESCAPE_POINTS
		_world.resolve_encounter_win()
		_show_screen("playing")
		return
	_lives -= 1
	if _lives <= 0:
		_lives = 0
		_finish_run(false)
		return
	if _stage_index == HEStageData.count() - 1:
		_offer_stage_retry(_stage_index - 1)
		return
	_world.respawn()
	_world.add_bubble(_world.player_pos, "Deep breath. Try again.", YELLOW)
	_show_screen("playing")

# ------------------------------------------------------------------ HUD

func _update_hud() -> void:
	var st := HEStageData.get_stage(_stage_index)
	_hud_stage.text = "STAGE %d/%d - %s" % [_stage_index + 1, HEStageData.count(), st["name"]]
	_hud_stats.text = "LIVES %d   SCORE %d   TIME %ds" % [_lives, _score, int(_world.elapsed)]
	var inv: Dictionary = _world.inventory
	var status := ""
	if _world.airpods_time > 0.0:
		status += "   AirPods ON %.0fs" % ceilf(_world.airpods_time)
	if _world.friend_time > 0.0:
		status += "   Friend here %.0fs" % ceilf(_world.friend_time)
	if _world.player_hidden():
		status += "   HIDDEN"
	_hud_items.text = "[1] AirPods x%d   [2] Call Friend x%d   [3] 'No English' x%d   Boyfriend shield x%d%s" % [
		int(inv.get("airpods", 0)), int(inv.get("friend", 0)), int(inv.get("noenglish", 0)), _world.shield, status]
	_hud_hint.text = str(st.get("hint", "")) if _world.elapsed < 9.0 else ""
