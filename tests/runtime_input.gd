extends RefCounted
## End-to-end input checks use Godot's real input dispatch and rendered UI rectangles.
var failures := 0
var checks := 0

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("INPUT ", "PASS " if ok else "FAIL ", title)

func frame(game) -> void:
	await game.get_tree().process_frame
	await game.get_tree().process_frame

func mouse(game, point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT, shift: bool = false) -> void:
	# Inject into the actual viewport pipeline. Native trackpad motion can overwrite
	# Input.parse_input_event's accumulated hover between frames on macOS.
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	motion.relative = point - game.get_viewport().get_mouse_position()
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = button
		event.pressed = down
		event.shift_pressed = shift
		game.get_viewport().push_input(motion, true)
		game.get_viewport().push_input(event, true)
		await frame(game)

func tap(game, point: Vector2) -> void:
	for down in [true, false]:
		var motion := InputEventMouseMotion.new()
		motion.position = game.get_viewport().get_screen_transform() * point
		motion.global_position = motion.position
		Input.parse_input_event(motion)
		var event := InputEventScreenTouch.new()
		event.position = game.get_viewport().get_screen_transform() * point
		event.index = 0
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await frame(game)

func find_button(node: Node, caption: String) -> Button:
	if node is Button and caption in node.text and node.is_visible_in_tree(): return node
	for child in node.get_children():
		var found := find_button(child, caption)
		if found: return found
	return null

func run(game) -> int:
	Input.use_accumulated_input = false
	game._new_game()
	game.sim.ai_enabled = false
	game.tutorial_active = false
	game._refresh_hud()
	await frame(game)
	var worker: Dictionary = {}
	for e in game.sim.entities:
		if e.kind == "worker" and e.team == 0:
			worker = e
			break
	var position: Vector2 = game.camera.unproject_position(Vector3(worker.pos.x, 0.85, worker.pos.y))
	await mouse(game, position)
	check(worker.id in game.selected, "鼠标实际点击选择工人")
	var destination := Vector2(32, 57)
	var ground_screen: Vector2 = game.camera.unproject_position(Vector3(destination.x, 0, destination.y))
	check(game.ground_point(ground_screen).distance_to(destination) < 0.02, "3D投影与地面点击坐标一致")
	await mouse(game, ground_screen, MOUSE_BUTTON_RIGHT)
	check(worker.state == "move", "右键通过输入分发下达移动指令")
	var menu := find_button(game.hud, "菜单")
	check(menu != null, "菜单按钮可见")
	if menu == null: return failures
	await mouse(game, menu.get_global_rect().get_center())
	check(game.hud.is_modal_open() and game.paused, "点击菜单暂停战局")
	var commands_before: int = game.sim.stats.commands
	await mouse(game, ground_screen, MOUSE_BUTTON_RIGHT)
	check(game.sim.stats.commands == commands_before, "模态菜单阻止战场指令穿透")
	var resume := find_button(game.hud, "继续战局")
	if resume == null:
		check(false, "暂停菜单提供继续按钮")
		return failures
	await mouse(game, resume.get_global_rect().get_center())
	check(not game.hud.is_modal_open() and not game.paused, "继续按钮恢复战局")
	game.sim.command([worker.id], "stop")
	game.selected.clear()
	position = game.camera.unproject_position(Vector3(worker.pos.x, 0.85, worker.pos.y))
	await tap(game, position)
	check(worker.id in game.selected and game.touch_mode, "触控事件选择工人")
	commands_before = game.sim.stats.commands
	await tap(game, ground_screen)
	check(game.sim.stats.commands == commands_before + 1, "触控点地面恰好下达一次指令")
	var workers_button := find_button(game.hud, "工人")
	game.selected.clear()
	await tap(game, workers_button.get_global_rect().get_center())
	check(game.selected.size() >= 4, "触控实际点击界面按钮")
	var size_before: float = game.camera_size
	commands_before = game.sim.stats.commands
	var center := Vector2(650, 300)
	for index in range(2):
		var touch := InputEventScreenTouch.new()
		touch.index = index
		touch.position = game.get_viewport().get_screen_transform() * (center + Vector2(index * 70, 0))
		touch.pressed = true
		Input.parse_input_event(touch)
		await frame(game)
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = game.get_viewport().get_screen_transform() * (center + Vector2(120, 0))
	drag.relative = Vector2(50, 0) * game._display_density()
	Input.parse_input_event(drag)
	await frame(game)
	for index in range(2):
		var release := InputEventScreenTouch.new()
		release.index = index
		release.position = game.get_viewport().get_screen_transform() * (center + Vector2(index * 120, 0))
		release.pressed = false
		Input.parse_input_event(release)
		await frame(game)
	check(game.camera_size < size_before, "双指张开缩放镜头")
	check(game.sim.stats.commands == commands_before, "双指结束没有产生误移动")
	# Cancel works via an explicit button on touch; root must clear both model and HUD mode.
	game._on_action("select_workers")
	game._on_action("build", "house")
	game._on_action("cancel")
	check(game.build_kind == "" and game.hud._build_kind == "", "取消建造同时清除实际状态与界面状态")
	# Rotate while a match is live; real elapsed game time must freeze.
	game.get_window().size = Vector2i(Vector2(Vector2i(390, 844)) * game._display_density())
	await game.get_tree().create_timer(0.2).timeout
	var elapsed_before: float = game.sim.elapsed
	await game.get_tree().create_timer(0.25).timeout
	check(is_equal_approx(game.sim.elapsed, elapsed_before) and game.hud.is_modal_open(), "竖屏暂停模拟并阻止指令")
	game.get_window().size = Vector2i(Vector2(Vector2i(1280, 800)) * game._display_density())
	await game.get_tree().create_timer(0.2).timeout
	check(not game.hud.is_modal_open(), "恢复横屏解除旋转提示")
	await laptop_commands(game)
	print("INPUT_SUMMARY checks=", checks, " failures=", failures)
	return failures

func click_card(game, caption: String) -> bool:
	var button := find_button(game.hud, caption)
	check(button != null, "指令按钮存在：" + caption.strip_edges())
	if button == null: return false
	var parent := button.get_parent()
	while parent != null and not parent is ScrollContainer:
		parent = parent.get_parent()
	if parent is ScrollContainer:
		parent.ensure_control_visible(button)
	await frame(game)
	check(game.hud.is_pointer_over_ui(button.get_global_rect().get_center()), "按钮点击位置在界面内：" + caption.strip_edges())
	await mouse(game, button.get_global_rect().get_center())
	return true

func laptop_commands(game) -> void:
	game._new_game()
	# Step the economy explicitly below; keep units/camera still between synthetic
	# press and release so hit tests do not race frame-rate-dependent movement.
	game.set_process(false)
	game.sim.ai_enabled = false
	game.tutorial_active = false
	game._refresh_hud()
	await frame(game)
	var workers: Array = game.sim.entities.filter(func(e): return e.kind == "worker" and e.team == 0)
	var worker: Dictionary = workers[0]
	var resource: Dictionary = game.sim.entities.filter(func(e): return e.kind == "berry" and e.pos.x < 15 and e.pos.y > 60)[0]
	var project = func(e, height = 0.85): return game.camera.unproject_position(Vector3(e.pos.x, height, e.pos.y))
	await mouse(game, project.call(worker))
	check(game.selected == [worker.id], "笔记本普通点击选中工人")
	var before: int = game.sim.stats.commands
	await mouse(game, project.call(resource, 1.0))
	check(worker.state == "gather" and worker.target == resource.id and game.selected == [worker.id], "普通点击果丛采集并保留工人选择")
	check(game.sim.stats.commands == before + 1, "普通点击采集仅下达一次指令")
	for tick in range(300): game.sim.step(0.1)
	game.world.sync(game.sim.entities,game.selected,game.sim,0.0)
	check(game.sim.stats.gathered > 0, "普通点击采集后实际运输并入账")
	game.sim.command([worker.id], "stop")
	before = game.sim.stats.commands
	await mouse(game, project.call(workers[1]), MOUSE_BUTTON_LEFT, true)
	check(worker.id in game.selected and workers[1].id in game.selected and game.sim.stats.commands == before, "Shift 点击追加选择不误下令")
	game._on_action("multiselect", true)
	await mouse(game, project.call(workers[2]))
	check(workers[2].id in game.selected and game.sim.stats.commands == before, "多选模式点击不误下令")
	game._on_action("multiselect", false)
	game.selected = [worker.id]
	game._refresh_hud()
	await frame(game)
	if await click_card(game, "采集"):
		check(game.order_mode == "gather", "采集按钮进入指令状态")
		var ground: Vector2 = game.camera.unproject_position(Vector3(32, 0, 57))
		before = game.sim.stats.commands
		await mouse(game, ground)
		check(game.order_mode == "gather" and game.sim.stats.commands == before, "无效采集目标保留指令等待并不移动工人")
		await mouse(game, project.call(resource, 1.0))
		check(worker.state == "gather" and game.order_mode == "", "采集按钮后点击资源成功")
	if await click_card(game, "移动"):
		check(game.order_mode == "move", "移动按钮进入指令状态")
		await mouse(game, game.camera.unproject_position(Vector3(32, 0, 57)))
		check(worker.state == "move" and game.order_mode == "", "移动按钮后普通点击空地下令")
	if await click_card(game, "采集"):
		if await click_card(game, "取消指令"):
			check(game.order_mode == "" and game.hud._order_kind == "", "点击取消清除指令及界面状态")
	var house: Dictionary = game.sim._spawn("house", 0, Vector2(28, 57), 0.2)
	game.world.sync(game.sim.entities, game.selected, game.sim, 0.0)
	await frame(game)
	await mouse(game, project.call(house, 1.3))
	check(worker.state == "build" and worker.target == house.id, "普通点击未完工建筑继续施工")
	var enemy: Dictionary = game.sim._spawn("guard", 1, Vector2(26, 55))
	game.sim._update_fog()
	game.world.sync(game.sim.entities, game.selected, game.sim, 0.0)
	await frame(game)
	await mouse(game, project.call(enemy))
	check(worker.state == "attack" and worker.target == enemy.id, "普通点击可见敌人攻击")
	var home: Dictionary = game.sim.entities[0]
	await mouse(game, project.call(home, 1.6))
	check(game.selected == [home.id], "点击已建成己方建筑选择并显示生产")
	# A resource's visible upper crown must also accept a click.
	game.selected = [worker.id]
	var tree: Dictionary = game.sim._spawn("tree", -1, Vector2(24, 60))
	game.sim._update_fog()
	game.world.sync(game.sim.entities, game.selected, game.sim, 0.0)
	await frame(game)
	before = game.sim.stats.commands
	await mouse(game, project.call(tree, float(game.world.visuals[tree.id].art_height) * 0.8))
	# A full backpack may immediately enter the delivery leg after the click.
	check(worker.state in ["gather", "return"] and worker.source == tree.id and game.sim.stats.commands == before + 1, "点击树冠也能采集，不必点树根")
	game.get_window().size = Vector2i(Vector2(Vector2i(844,390)) * game._display_density())
	await game.get_tree().create_timer(0.3).timeout
	game._refresh_hud()
	await frame(game)
	if await click_card(game, "采集"):
		check(game.order_mode == "gather", "紧凑窗口采集按钮可操作")
		if await click_card(game, "取消指令"):
			check(game.order_mode == "", "紧凑窗口取消按钮可操作")
	game.get_window().size = Vector2i(Vector2(Vector2i(1280,800)) * game._display_density())
	await game.get_tree().create_timer(0.2).timeout
	game.set_process(true)
