extends Node3D
## App orchestration only: rules, visuals, HUD and input remain separate modules.
const Simulation = preload("res://scripts/simulation.gd")
const Data = preload("res://scripts/game_data.gd")
const WorldView = preload("res://scripts/world_view.gd")
const HUD = preload("res://scripts/hud.gd")
const Sounds = preload("res://scripts/soundscape.gd")
const SelectionOverlay = preload("res://scripts/selection_overlay.gd")
var sim = Simulation.new()
var world
var hud
var audio
var camera: Camera3D
var selection_box
var selected: Array = []
var groups: Dictionary = {}
var camera_focus := Vector2(21, 55)
var camera_size := 39.0
var paused := true
var match_started := false
var build_kind := ""
var order_mode := ""
var multiselect := false
var touch_mode := false
var tutorial_step := 0
var tutorial_active := true
var tutorial_flags: Dictionary = {}
var settings := {"quality": 1, "volume": 0.55, "music": true, "difficulty":"relaxed", "large_text": false}
var _visible_enemies: Dictionary = {}
var _next_threat := 0.0
var _threat_point := Vector2.ZERO
var _mouse_down := false
var _mouse_start := Vector2.ZERO
var _middle_down := false
var _touches: Dictionary = {}
var _touch_start := Vector2.ZERO
var _touch_moved := false
var _had_multitouch := false
var _hud_clock := 0.0
var _save_clock := 0.0
var _result_shown := false
var _result_visual_clock := 0.0
var _suspended := false
var _test_running := false
var _startup := true
var _tutorial_origin := 0
const SAVE_PATH := "user://campaign.json"
const SETTINGS_PATH := "user://settings.cfg"

func _ready() -> void:
	Engine.max_fps = 60
	get_window().content_scale_size = Vector2i.ZERO
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_apply_display_scale()
	_load_settings()
	world = WorldView.new()
	add_child(world)
	world.setup()
	world.set_quality(int(settings.quality))
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 240.0
	camera.current = true
	add_child(camera)
	_update_camera()
	audio = Sounds.new()
	add_child(audio)
	audio.apply(float(settings.volume), bool(settings.music))
	hud = HUD.new()
	add_child(hud)
	hud.setup(sim)
	selection_box = SelectionOverlay.new()
	hud.add_child(selection_box)
	_connect_hud()
	get_viewport().size_changed.connect(_resized)
	get_window().dpi_changed.connect(_resized)
	touch_mode = DisplayServer.is_touchscreen_available()
	world.sync(sim.entities, selected, sim, 0.0)
	_refresh_hud()
	_startup = false
	call_deferred("_show_start")
	if "--package-smoke" in OS.get_cmdline_user_args():
		_test_running = true
		call_deferred("_package_smoke")
	if "--visual-test" in OS.get_cmdline_user_args():
		_test_running = true
		call_deferred("_run_visual_test")

func _connect_hud() -> void:
	hud.action.connect(_on_action)
	hud.map_clicked.connect(func(point: Vector2):
		if match_started and not hud.is_modal_open():
			camera_focus = point
			_update_camera()
	)
	hud.set_large_text(bool(settings.large_text))
	hud._volume = float(settings.volume)
	hud._quality = ["low", "medium", "high"][int(settings.quality)]

func _show_start() -> void:
	hud.show_menu("main")

func _process(dt: float) -> void:
	if _startup:
		return
	var blocked: bool = paused or hud.is_modal_open() or _suspended or _portrait()
	audio.set_harvest_paused(blocked)
	if match_started and not blocked and sim.result == "":
		sim.step(minf(dt, 0.1))
		_consume_events()
		_update_threats()
		_update_tutorial()
		_save_clock += dt
		if _save_clock >= 60.0:
			_save_clock = 0.0
			_save_game(false)
	if not blocked and match_started:
		_keyboard_camera(dt)
	world.sync(sim.entities, selected, sim, 0.0 if blocked else minf(dt, 0.1))
	if not build_kind.is_empty() and not blocked:
		var p := ground_point(get_viewport().get_mouse_position())
		world.set_preview(build_kind, p, sim.can_place(build_kind, p) and sim.is_visible(p))
	selected = selected.filter(func(id): return not sim.entity(int(id)).is_empty())
	_hud_clock += dt
	if _hud_clock > 0.15:
		_hud_clock = 0.0
		_refresh_hud()
	if sim.result != "" and not _result_shown and not blocked:
		# Rules already ended. Let the final heart collapse before opening the result
		# modal; an explicit pause still freezes this short visual-only interval.
		_result_visual_clock += minf(dt,0.1)
		if _result_visual_clock >= 1.5:
			_result_shown = true
			paused = true
			hud.show_menu("victory" if sim.result == "win" else "defeat")
			audio.play_cue("win" if sim.result == "win" else "error")

func _update_camera() -> void:
	camera_focus = camera_focus.clamp(Vector2(3, 3), Vector2(77, 77))
	camera_size = clampf(camera_size, 22.0, 72.0)
	camera.size = camera_size
	var target := Vector3(camera_focus.x, 0.0, camera_focus.y)
	camera.position = target + Vector3(29, 38, 29)
	camera.look_at(target)

func _keyboard_camera(dt: float) -> void:
	var direction := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_LEFT): direction.x -= 1
	if Input.is_physical_key_pressed(KEY_RIGHT): direction.x += 1
	if Input.is_physical_key_pressed(KEY_UP): direction.y -= 1
	if Input.is_physical_key_pressed(KEY_DOWN): direction.y += 1
	if direction != Vector2.ZERO:
		var planar := Vector2(direction.x + direction.y, direction.y - direction.x).normalized()
		camera_focus += planar * dt * camera_size * 0.6
		_update_camera()

func ground_point(screen: Vector2) -> Vector2:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	if absf(direction.y) < 0.001:
		return camera_focus
	var hit := origin + direction * (-origin.y / direction.y)
	return Vector2(hit.x, hit.z)

func _pan(from: Vector2, to: Vector2) -> void:
	camera_focus += ground_point(from) - ground_point(to)
	_update_camera()

func _pick(screen: Vector2) -> int:
	var nearest := -1
	var best := INF
	for e in sim.entities:
		if e.hp <= 0: continue
		if e.team != 0 and not sim.is_visible(e.pos):
			continue
		var unit: bool = Data.UNITS.has(e.kind)
		var height := (1.4 if e.kind == "rider" else 0.9) if unit else (1.6 if e.team >= 0 else 1.0)
		var position3 := Vector3(e.pos.x, height, e.pos.y)
		if unit and world.visuals.has(int(e.id)):
			position3 = world.visuals[int(e.id)].node.global_position + Vector3(0,height-0.1,0)
		if camera.is_position_behind(position3):
			continue
		var projected := camera.unproject_position(position3)
		var radius := 23.0 if touch_mode else 16.0
		if not unit:
			var edge := camera.unproject_position(position3 + Vector3(float(e.radius), 0, 0))
			radius = maxf(radius, projected.distance_to(edge) * 1.45)
		var distance := projected.distance_to(screen)
		if not unit and world.visuals.has(int(e.id)):
			# Include the visible crown/roof, not only a small circle near the ground.
			var top := camera.unproject_position(Vector3(e.pos.x, float(world.visuals[int(e.id)].art_height) * 0.85, e.pos.y))
			var base := camera.unproject_position(Vector3(e.pos.x, 0.35, e.pos.y))
			distance = Geometry2D.get_closest_point_to_segment(screen, base, top).distance_to(screen)
		if distance < radius and distance / radius < best:
			best = distance / radius
			nearest = int(e.id)
	return nearest

func _select_one(id: int, append: bool = false) -> void:
	var e: Dictionary = sim.entity(id)
	if e.is_empty():
		if not append: selected.clear()
		return
	if append and e.team == 0 and Data.UNITS.has(e.kind):
		selected = selected.filter(func(value): return sim.entity(value).get("team", -1) == 0 and Data.UNITS.has(sim.entity(value).get("kind", "")))
		if id in selected: selected.erase(id)
		else: selected.append(id)
	else:
		selected = [id]
	if e.kind == "worker" and e.team == 0:
		tutorial_flags["selected_worker"] = true
		sim.stats.selected_worker = true
	audio.play_cue("select")
	_refresh_hud()

func _box_select(rect: Rect2, append: bool) -> void:
	if not append: selected.clear()
	selected = selected.filter(func(value): return sim.entity(value).get("team", -1) == 0 and Data.UNITS.has(sim.entity(value).get("kind", "")))
	for e in sim.entities:
		if e.team == 0 and Data.UNITS.has(e.kind):
			var position3 := Vector3(e.pos.x,0.8,e.pos.y)
			if world.visuals.has(int(e.id)): position3 = world.visuals[int(e.id)].node.global_position + Vector3(0,0.7,0)
			var point := camera.unproject_position(position3)
			if rect.has_point(point) and not e.id in selected:
				selected.append(e.id)
				if e.kind == "worker": tutorial_flags["selected_worker"] = true
	selection_box.clear_box()
	if not selected.is_empty(): audio.play_cue("select")
	_refresh_hud()

func _click(screen: Vector2, append: bool = false) -> void:
	var point := ground_point(screen)
	if not build_kind.is_empty():
		var error: String = sim.build(build_kind, point, _friendly_selected())
		if _feedback(error, "已安排建造，拾光者会前往施工。"):
			build_kind = ""
			hud.set_build_mode("")
			world.clear_preview()
			_consume_events()
		_refresh_hud()
		return
	if not order_mode.is_empty():
		if _issue_order(screen, order_mode):
			order_mode = ""
		_refresh_hud()
		return
	var id := _pick(screen)
	if not _friendly_selected().is_empty() and not (append or multiselect):
		var e := sim.entity(id)
		if e.is_empty() or e.team != 0 or (e.team == 0 and e.built < 1.0):
			_issue_order(screen)
			return
	_select_one(id, append or multiselect)

func _friendly_selected() -> Array:
	return selected.filter(func(id): return sim.entity(int(id)).get("team", -1) == 0 and Data.UNITS.has(sim.entity(int(id)).get("kind", "")))

func _issue_order(screen: Vector2, forced: String = "") -> bool:
	var point := ground_point(screen)
	var id := _pick(screen)
	var target: Dictionary = sim.entity(id)
	var action := forced
	if action == "":
		action = "move"
		if not target.is_empty():
			if target.team == 1: action = "attack"
			elif target.team == -1: action = "gather"
			elif target.built < 1.0: action = "build"
	if action == "move": id = -1
	if action == "attack" and (target.is_empty() or target.team != 1): id = -1
	if action == "gather" and (target.is_empty() or not Data.RESOURCE_KINDS.has(target.get("kind", ""))):
		_feedback("请点击风铃木、穗果丛或岚晶矿；Esc 或「取消指令」退出采集指令。")
		return false
	var error: String = sim.command(_friendly_selected(), action, point, id)
	var message := ""
	if action == "gather": message = "已安排采集%s，装满后自动运回回响心。" % Data.title(str(target.kind))
	if action == "build": message = "已安排拾光者继续施工。"
	var success := _feedback(error, message)
	if success:
		world.show_order(target.pos if id >= 0 else point, action == "attack")
		audio.play_cue("order")
	_consume_events()
	return success

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_key(event)
		return
	if not match_started or paused or hud.is_modal_open() or _portrait():
		return
	if event is InputEventMouseButton:
		if event.device == InputEvent.DEVICE_ID_EMULATION: return
		touch_mode = false
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_size *= 0.91
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_size *= 1.10
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_middle_down = event.pressed
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if not build_kind.is_empty() or not order_mode.is_empty(): _cancel_order()
			else: _issue_order(event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_mouse_down = true
				_mouse_start = event.position
			elif _mouse_down:
				_mouse_down = false
				if _mouse_start.distance_to(event.position) > 10.0 and build_kind.is_empty() and order_mode.is_empty():
					_box_select(Rect2(_mouse_start, event.position - _mouse_start).abs(), event.shift_pressed or multiselect)
				else: _click(event.position, event.shift_pressed)
				selection_box.clear_box()
	elif event is InputEventMouseMotion:
		if _middle_down:
			_pan(event.position - event.relative, event.position)
		elif _mouse_down and build_kind.is_empty() and order_mode.is_empty():
			if _mouse_start.distance_to(event.position) > 10.0:
				selection_box.show_box(_mouse_start, event.position)
	elif event is InputEventScreenTouch:
		if event.canceled:
			_clear_pointers()
			return
		touch_mode = true
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() == 1:
				_touch_start = event.position
				_touch_moved = false
				_had_multitouch = false
			else:
				_had_multitouch = true
				selection_box.clear_box()
		elif _touches.has(event.index):
			if _touches.size() == 1 and not _had_multitouch:
				if not _touch_moved: _click(event.position)
				elif multiselect: _box_select(Rect2(_touch_start, event.position - _touch_start).abs(), true)
			_touches.erase(event.index)
			if _touches.is_empty(): selection_box.clear_box()
	elif event is InputEventScreenDrag and _touches.has(event.index):
		var old: Vector2 = _touches[event.index]
		if _touches.size() >= 2:
			var keys: Array = _touches.keys()
			var other: Vector2 = _touches[keys[1] if keys[0] == event.index else keys[0]]
			var before := old.distance_to(other)
			var after: float = event.position.distance_to(other)
			if before > 10.0 and after > 10.0:
				camera_size *= before / after
				_update_camera()
			_pan((old + other) * 0.5, (event.position + other) * 0.5)
		else:
			if event.position.distance_to(_touch_start) > 10.0: _touch_moved = true
			if _touch_moved:
				if multiselect: selection_box.show_box(_touch_start, event.position)
				else: _pan(old, event.position)
		_touches[event.index] = event.position
	elif event is InputEventMagnifyGesture:
		camera_size /= maxf(event.factor, 0.01)
		_update_camera()
	elif event is InputEventPanGesture:
		_pan(event.position, event.position - event.delta * 9.0)

func _key(event: InputEventKey) -> void:
	if event.keycode == KEY_ESCAPE:
		if build_kind != "" or order_mode != "" or multiselect: _cancel_order()
		elif hud.is_modal_open(): _on_action("resume", null)
		else: _on_action("pause", null)
		return
	if event.keycode == KEY_F1:
		_on_action("manual", null)
		return
	if not match_started or hud.is_modal_open() or _portrait(): return
	match event.physical_keycode:
		KEY_SPACE: _on_action("pause", null)
		KEY_H: _on_action("home", null)
		KEY_A: _on_action("attack", null)
		KEY_S: _on_action("stop", null)
		KEY_B: _on_action("build", "house")
		KEY_F5: _on_action("save", null)
		KEY_F9: _on_action("load", null)
	if event.keycode >= KEY_1 and event.keycode <= KEY_5:
		var index := int(event.keycode - KEY_0)
		if event.ctrl_pressed or event.meta_pressed:
			groups[index] = _friendly_selected().duplicate()
			hud.show_toast("编队 %d 已保存（%d 个单位）。" % [index, groups[index].size()])
		elif groups.has(index):
			selected = groups[index].filter(func(id): return not sim.entity(id).is_empty())
			_refresh_hud()

func _cancel_order() -> void:
	build_kind = ""
	if hud: hud.set_build_mode("")
	order_mode = ""
	multiselect = false
	world.clear_preview()
	_clear_pointers()
	_refresh_hud()

func _clear_pointers() -> void:
	_mouse_down = false
	_middle_down = false
	_touches.clear()
	if selection_box: selection_box.clear_box()

func _portrait() -> bool:
	var size := get_viewport().get_visible_rect().size
	return size.y > size.x

func _resized() -> void:
	_apply_display_scale()
	_clear_pointers()
	_update_camera()

func _notification(what: int) -> void:
	if _startup: return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_clear_pointers()
		if match_started and not _test_running:
			_suspended = true
			_save_game(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if _suspended:
			_suspended = false
			if match_started and not hud.is_modal_open():
				paused = true
				hud.show_menu("pause")

func _refresh_hud() -> void:
	if hud == null: return
	hud.set_build_mode(build_kind)
	hud.set_order_mode(order_mode)
	hud.set_multiselect(multiselect)
	hud.refresh(selected, camera_focus, paused or _suspended or _portrait())
	hud.set_tutorial(tutorial_step if tutorial_active else -1)

func _on_action(action: String, payload: Variant = null) -> void:
	match action:
		"start", "restart":
			_new_game()
		"pause":
			paused = true
			_clear_pointers()
			hud.show_menu("pause" if match_started else "main")
		"resume":
			if not match_started:
				hud.show_menu("main")
			elif sim.result != "" and _result_shown:
				hud.show_menu("victory" if sim.result == "win" else "defeat")
			else:
				paused = false
				hud.hide_menu()
		"manual", "settings":
			paused = true
			_clear_pointers()
			hud.show_menu(action)
		"ui_page":
			paused = true
			_clear_pointers()
			hud.show_menu(str(payload))
		"large_text":
			settings.large_text = bool(payload)
			hud.set_large_text(settings.large_text)
			_save_settings()
		"recruit":
			var building_id := int(payload) if payload != null else -1
			if building_id < 0:
				for e in sim.entities:
					if e.team == 0 and e.kind == "heart": building_id = e.id; break
			if building_id >= 0:
				selected = [building_id]
				paused = true
				_clear_pointers()
				hud.show_recruitment(building_id)
		"recruit_unit":
			var building: Dictionary = sim.entity(hud._recruit_id)
			var error := "需要己方招募建筑。"
			if not building.is_empty() and building.team == 0:
				error = sim.train(building.id,str(payload))
			audio.play_cue("train" if error.is_empty() else "error")
			hud.show_recruitment(hud._recruit_id,"已加入队列：%s。返回战场后继续训练。" % Data.title(str(payload)) if error.is_empty() else error)
		"focus_threat":
			camera_focus = _threat_point
			_update_camera()
			hud.clear_threat()
		"difficulty":
			if str(payload) in ["relaxed","standard"]:
				settings.difficulty = str(payload)
				sim.set_difficulty(str(payload))
				_save_settings()
				hud.show_menu("settings")
		"save":
			_save_game(true)
		"load":
			_load_game()
		"skip_tutorial":
			tutorial_active = false
		"replay_tutorial":
			tutorial_active = true
			tutorial_step = 0
			tutorial_flags.clear()
			if not match_started: _new_game()
			paused = false
			hud.hide_menu()
		"select_workers", "select_army":
			selected.clear()
			for e in sim.entities:
				if e.team != 0 or not Data.UNITS.has(e.kind): continue
				if (action == "select_workers" and e.kind == "worker") or (action == "select_army" and e.kind != "worker"):
					selected.append(e.id)
			if action == "select_workers" and not selected.is_empty(): tutorial_flags["selected_worker"] = true
			audio.play_cue("select")
		"home":
			for e in sim.entities:
				if e.kind == "heart" and e.team == 0:
					camera_focus = e.pos + Vector2(2, -3)
					_update_camera()
		"zoom":
			camera_size *= 0.86 if int(payload) > 0 else 1.16
			_update_camera()
		"multiselect":
			multiselect = bool(payload)
			order_mode = ""
			hud.show_toast("多选已开启：逐个点选或拖框选择。" if multiselect else "已恢复单选。")
		"build":
			var workers := _friendly_selected().filter(func(id): return sim.entity(id).kind == "worker")
			if workers.is_empty():
				_feedback("请先选择拾光者，或点下方「工人」。")
			else:
				build_kind = str(payload)
				order_mode = ""
				multiselect = false
				hud.set_build_mode(build_kind)
		"train":
			var building_id := -1
			for id in selected:
				var e := sim.entity(id)
				if e.get("team", -1) == 0 and Data.BUILDINGS.has(e.get("kind", "")):
					building_id = id
					break
			_feedback(sim.train(building_id, str(payload)), "已加入生产队列：" + Data.title(str(payload)))
		"research":
			_feedback(sim.research(0), "潮晶共鸣已完成：全军攻击 +25%，采集速度 +20%。")
		"stop":
			_cancel_order()
			_feedback(sim.command(_friendly_selected(), "stop"), "已停止当前指令。")
		"move", "attack", "gather":
			if _friendly_selected().is_empty():
				_feedback("请先选择单位。")
			elif action == "gather" and not _friendly_selected().any(func(id): return sim.entity(id).kind == "worker"):
				_feedback("请先选择拾光者，或点下方「工人」。")
			else:
				_cancel_order()
				order_mode = action
				hud.show_toast({"attack":"点击目的地，沿途迎击敌军。", "move":"点击目的地移动。", "gather":"点击风铃木、穗果丛或岚晶矿开始采集。"}[action])
		"cancel":
			_cancel_order()
		"quality":
			settings.quality = {"low": 0, "medium": 1, "high": 2}.get(str(payload), 1)
			world.set_quality(int(settings.quality))
			get_viewport().msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][int(settings.quality)]
			_save_settings()
		"volume":
			settings.volume = clampf(float(payload), 0.0, 1.0)
			audio.apply(float(settings.volume), bool(settings.music))
			_save_settings()
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(payload) else DisplayServer.WINDOW_MODE_WINDOWED)
	_refresh_hud()

func _new_game() -> void:
	audio.reset_harvest()
	world.reset_entities()
	sim.difficulty = str(settings.difficulty)
	sim.reset(42)
	sim.ai_enabled = true
	selected.clear()
	groups.clear()
	_cancel_order()
	camera_focus = Vector2(21, 55)
	camera_size = 39.0
	_update_camera()
	tutorial_step = 0
	tutorial_flags.clear()
	tutorial_active = true
	_tutorial_origin = int(sim.stats.explored)
	_result_shown = false
	_result_visual_clock = 0.0
	match_started = true
	paused = false
	_suspended = false
	_save_clock = 0.0
	_visible_enemies.clear()
	_next_threat = 0.0
	hud.clear_threat()
	hud.hide_menu()
	world.sync(sim.entities, selected, sim, 0.0)
	_refresh_hud()

func _feedback(error: String, success: String = "") -> bool:
	if error != "":
		hud.show_toast(error)
		audio.play_cue("error")
		return false
	if success != "": hud.show_toast(success)
	return true

func _consume_events() -> void:
	for event in sim.events:
		var type: String = event.get("type", "")
		if type == "attack" and sim.is_visible(event.point) and sim.is_visible(event.from):
			world.show_combat(event)
		if type == "destroyed": world.show_destroyed(event)
		if int(event.get("team", -1)) == 0:
			match type:
				"harvest": _play_harvest(event)
				"gathered": tutorial_flags["gathered"] = true
				"built":
					if event.kind == "barracks": tutorial_flags["barracks"] = true
					audio.play_cue("build")
					hud.show_toast(Data.title(event.kind) + "已建成。")
				"trained":
					if event.kind != "worker": tutorial_flags["trained"] = true
					audio.play_cue("train")
				"attack":
					tutorial_flags["battle"] = true
					audio.play_cue("attack")
		if type == "raid": hud.show_toast("斥候警报：赤铜远征队正在集结，留意基地防守。")
	sim.events.clear()

func _play_harvest(event: Dictionary) -> void:
	if not match_started or paused or _suspended or hud.is_modal_open(): return
	var point: Vector2 = event.point
	if not sim.is_visible(point): return
	var location := Vector3(point.x, 0.8, point.y)
	if camera.is_position_behind(location): return
	var screen := camera.unproject_position(location)
	var bounds := get_viewport().get_visible_rect()
	if not bounds.has_point(screen): return
	# Only nearby on-screen work is audible; fade gently at the viewport edges.
	var edge := minf(minf(screen.x, bounds.size.x-screen.x), minf(screen.y, bounds.size.y-screen.y))
	var near := 1.0 - smoothstep(12.0, 42.0, point.distance_to(camera_focus))
	var gain := near * smoothstep(0.0, 90.0, edge)
	audio.play_harvest(str(event.resource), int(event.id), gain)

func _update_threats() -> void:
	var visible_now: Dictionary = {}
	var new_enemy: Dictionary = {}
	for e in sim.entities:
		if e.team != 1 or e.hp <= 0 or not Data.UNITS.has(e.kind) or not sim.is_visible(e.pos): continue
		visible_now[e.id] = true
		if not _visible_enemies.has(e.id) and new_enemy.is_empty(): new_enemy = e
	_visible_enemies = visible_now
	if not new_enemy.is_empty() and sim.elapsed >= _next_threat:
		_next_threat = sim.elapsed + 12.0
		_threat_point = new_enemy.pos
		hud.show_threat()
		audio.play_cue("alert")
		world.show_order(new_enemy.pos,true)

func _update_tutorial() -> void:
	if not tutorial_active: return
	if tutorial_step == 0 and sim.elapsed > 4.0: tutorial_step = 1
	if tutorial_step == 1 and tutorial_flags.get("selected_worker", false): tutorial_step = 2
	if tutorial_step == 2 and (tutorial_flags.get("gathered", false) or sim.stats.gathered > 0): tutorial_step = 3
	if tutorial_step == 3:
		for e in sim.entities:
			if e.kind == "barracks" and e.team == 0 and e.built >= 1.0:
				tutorial_step = 4
				break
	if tutorial_step == 4 and tutorial_flags.get("trained", false): tutorial_step = 5
	if tutorial_step == 5 and int(sim.stats.explored) > _tutorial_origin + 50: tutorial_step = 6
	if tutorial_step == 6 and tutorial_flags.get("battle", false): tutorial_step = 7

func _save_game(manual: bool) -> bool:
	if not match_started:
		if manual: _feedback("请先开始一局游戏。")
		return false
	var payload := {
		"format": "lanxiji-campaign", "version": 1, "simulation": sim.save_dict(),
		"camera": [camera_focus.x, camera_focus.y], "zoom": camera_size,
		"tutorial_step": tutorial_step, "tutorial_active": tutorial_active,
		"tutorial_flags": tutorial_flags, "tutorial_origin": _tutorial_origin
	}
	var path := SAVE_PATH if manual else "user://autosave.json"
	if _test_running: path = "res://builds/test-save.json"
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		if manual: _feedback("无法写入存档，请检查存储空间与目录权限。")
		return false
	file.store_string(JSON.stringify(payload))
	file.flush()
	file.close()
	var error := DirAccess.rename_absolute(temporary, path)
	if error != OK:
		if manual: _feedback("保存未完成，原存档仍保留。")
		return false
	if manual: hud.show_toast("战局已保存。")
	return true

func _load_game() -> bool:
	var path := SAVE_PATH
	if _test_running: path = "res://builds/test-save.json"
	elif not FileAccess.file_exists(path): path = "user://autosave.json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_feedback("没有可读取的存档，请先开始并保存一局游戏。")
		return false
	if file.get_length() > 8000000:
		_feedback("存档大小异常，当前战局未改变。")
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or parsed.get("format", "") != "lanxiji-campaign" or parsed.get("version", 0) != 1 or not parsed.get("simulation", null) is Dictionary:
		_feedback("存档格式不兼容或已损坏，当前战局未改变。")
		return false
	var coords: Variant = parsed.get("camera", [21, 55])
	if not coords is Array or coords.size() != 2 or not _finite_number(coords[0]) or not _finite_number(coords[1]) or not _finite_number(parsed.get("zoom", 39.0)):
		_feedback("存档镜头数据无效，当前战局未改变。")
		return false
	if not parsed.get("tutorial_flags", {}) is Dictionary or not _finite_number(parsed.get("tutorial_step", 0)) or not _finite_number(parsed.get("tutorial_origin", 0)):
		_feedback("存档教学数据无效，当前战局未改变。")
		return false
	if not sim.load_dict(parsed.simulation):
		_feedback("存档内容校验失败，当前战局未改变。")
		return false
	audio.reset_harvest()
	world.reset_entities()
	_visible_enemies.clear()
	_next_threat = 0.0
	hud.clear_threat()
	settings.difficulty = sim.difficulty
	camera_focus = Vector2(float(coords[0]), float(coords[1]))
	camera_size = clampf(float(parsed.get("zoom", 39.0)), 22.0, 72.0)
	_update_camera()
	tutorial_step = clampi(int(parsed.get("tutorial_step", 0)), 0, 7)
	tutorial_active = bool(parsed.get("tutorial_active", true))
	tutorial_flags = parsed.get("tutorial_flags", {})
	_tutorial_origin = int(parsed.get("tutorial_origin", 0))
	selected.clear()
	groups.clear()
	_cancel_order()
	match_started = true
	paused = false
	_result_shown = false
	_result_visual_clock = 0.0
	hud.hide_menu()
	hud.show_toast("战局已恢复。")
	return true

func _finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK: return
	var quality: Variant = config.get_value("display", "quality", 1)
	var volume: Variant = config.get_value("audio", "volume", 0.55)
	settings.large_text = bool(config.get_value("display", "large_text", false))
	if _finite_number(quality): settings.quality = clampi(int(quality), 0, 2)
	if _finite_number(volume): settings.volume = clampf(float(volume), 0, 1)
	settings.music = bool(config.get_value("audio", "music", true))
	var difficulty: String = str(config.get_value("gameplay","difficulty","relaxed"))
	if difficulty in ["relaxed","standard"]: settings.difficulty = difficulty
	sim.set_difficulty(str(settings.difficulty))

func _save_settings() -> void:
	if _test_running: return
	var config := ConfigFile.new()
	config.set_value("display", "quality", settings.quality)
	config.set_value("display", "large_text", settings.large_text)
	config.set_value("audio", "volume", settings.volume)
	config.set_value("audio", "music", settings.music)
	config.set_value("gameplay", "difficulty", settings.difficulty)
	config.save(SETTINGS_PATH)

func _input(event: InputEvent) -> void:
	if _startup or hud == null: return
	# A gesture that finishes on a panel must not leave a stuck drag in the world.
	if event is InputEventMouseButton and not event.pressed and hud.is_pointer_over_ui(event.position):
		_mouse_down = false
		_middle_down = false
		selection_box.clear_box()
	if event is InputEventScreenTouch and not event.pressed and hud.is_pointer_over_ui(event.position):
		_touches.erase(event.index)
		if _touches.is_empty(): selection_box.clear_box()

func _run_visual_test() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	# Production starts maximized; size-driven input tests need a restored window.
	get_window().mode = Window.MODE_WINDOWED
	await get_tree().create_timer(0.5).timeout
	get_window().size = Vector2i(Vector2(1280, 800) * _display_density())
	await get_tree().create_timer(1.0).timeout
	await _capture("01-title")
	var input_checks = load("res://tests/runtime_input.gd").new()
	var input_failures: int = await input_checks.run(self)
	input_checks = null
	var health_checks = load("res://tests/health_bars.gd").new()
	input_failures += await health_checks.run(self)
	health_checks = null
	var content_checks = load("res://tests/content_ui.gd").new()
	input_failures += await content_checks.run(self)
	content_checks = null
	_new_game()
	sim.ai_enabled = false
	_on_action("select_workers")
	await get_tree().create_timer(0.5).timeout
	await _capture("02-desktop")
	# The actual command path is used for construction, production, gathering and save/load.
	var workers := _friendly_selected()
	var resource := -1
	for e in sim.entities:
		if e.kind == "berry" and e.pos.x < 20.0 and e.pos.y > 55:
			resource = e.id
			break
	var gather_error: String = sim.command([workers[0]], "gather", sim.entity(resource).pos, resource)
	print("INTEGRATION gather_order=", gather_error == "")
	var build_error: String = sim.build("barracks", Vector2(29, 58), [workers[1], workers[2]])
	print("INTEGRATION build_order=", build_error == "")
	for tick in range(180): sim.step(0.25)
	_consume_events()
	var barracks_id := -1
	for e in sim.entities:
		if e.kind == "barracks" and e.team == 0 and e.built >= 1.0: barracks_id = e.id
	print("INTEGRATION construction_complete=", barracks_id >= 0)
	if barracks_id >= 0:
		selected = [barracks_id]
		_on_action("train", "guard")
		for tick in range(60): sim.step(0.25)
	print("INTEGRATION resources_delivered=", sim.stats.gathered > 0)
	print("INTEGRATION units_trained=", sim.stats.trained > 0)
	_consume_events()
	_update_tutorial()
	_refresh_hud()
	await get_tree().create_timer(0.3).timeout
	await _capture("03-built")
	var elapsed_before: float = sim.elapsed
	var saved := _save_game(true)
	sim.step(5.0)
	var loaded := _load_game()
	print("INTEGRATION save_load=", saved and loaded and absf(sim.elapsed - elapsed_before) < 0.001)
	# Resize checks use a rendered native Godot window, not browser emulation.
	for size in [Vector2i(1024, 768), Vector2i(844, 390), Vector2i(390, 844), Vector2i(1440, 620)]:
		get_window().size = Vector2i(Vector2(size) * _display_density())
		await get_tree().create_timer(0.45).timeout
		_refresh_hud()
		await _capture("size-%dx%d" % [size.x, size.y])
		print("LAYOUT ", size, " viewport=", get_viewport().get_visible_rect().size, " portrait=", _portrait(), " blocks=", hud.is_modal_open())
	get_window().size = Vector2i(Vector2(1280, 800) * _display_density())
	await get_tree().create_timer(0.2).timeout
	_on_action("manual")
	await get_tree().create_timer(0.2).timeout
	await _capture("04-manual")
	_on_action("settings")
	await get_tree().create_timer(0.2).timeout
	await _capture("05-settings")
	print("VISUAL_TEST_COMPLETE fps=", Engine.get_frames_per_second())
	get_tree().quit(1 if input_failures > 0 else 0)

func _capture(label: String) -> void:
	# Static or occluded windows may not emit another draw signal.
	RenderingServer.force_draw()
	var image := get_viewport().get_texture().get_image()
	var path := "res://builds/" + label + ".png"
	print("SCREENSHOT ", path, " status=", image.save_png(path))

func _display_density() -> float:
	if OS.has_feature("mobile"):
		return clampf(float(DisplayServer.screen_get_dpi()) / 160.0, 1.0, 4.0)
	return clampf(DisplayServer.screen_get_scale(get_window().current_screen), 1.0, 3.0)

func _apply_display_scale() -> void:
	# Layout and input share logical units; 3D and font rendering still use the
	# entire native framebuffer. In particular, Retina pixels are not UI points.
	var window := get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	var logical := Vector2i(Vector2(window.size) / _display_density()).max(Vector2i.ONE)
	if window.content_scale_size != logical:
		window.content_scale_size = logical

func _package_smoke() -> void:
	_new_game()
	sim.ai_enabled = false
	if "--harvest-smoke" in OS.get_cmdline_user_args():
		audio.apply(0.55, false)
		var workers: Array = sim.entities.filter(func(e): return e.team == 0 and e.kind == "worker")
		for index in range(3):
			var source: Dictionary = sim._nearest_resource(workers[index].pos, ["food","wood","crystal"][index])
			sim.command([workers[index].id], "gather", source.pos, source.id)
		while sim.elapsed < 12.0: await get_tree().process_frame
		var heard: Dictionary = audio._harvest_variant.duplicate()
		_on_action("pause")
		await get_tree().create_timer(0.2).timeout
		var stopped: bool = not audio.harvest_voices.any(func(player): return player.playing)
		var passed := heard.has("food") and heard.has("wood") and heard.has("crystal") and stopped
		print("PACKAGED_HARVEST sounds=", heard, " paused_stopped=", stopped, " passed=", passed)
		get_tree().quit(0 if passed else 1)
		return
	await get_tree().create_timer(2.0).timeout
	print("PACKAGED_GAME_READY entities=", sim.entities.size(), " resources=", sim.resources[0], " viewport=", get_viewport().get_visible_rect().size)
	get_tree().quit()

func _exit_tree() -> void:
	if match_started and not _test_running:
		_save_game(false)
