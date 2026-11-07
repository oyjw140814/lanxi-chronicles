extends SceneTree
var checks := 0
var failures := 0
var game
var input
func _initialize() -> void: call_deferred("run")
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("REFINEMENT ", "PASS " if ok else "FAIL ", title)
func settle() -> void:
	for frame in range(12): await process_frame
func capture(label: String) -> void:
	await settle()
	RenderingServer.force_draw()
	var img := root.get_texture().get_image()
	check(img.save_png("res://builds/ui-refinement/"+label+".png") == OK, "capture " + label)
func baseline(label: String, page := "") -> void:
	var source := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--baseline-hud="): source = arg.trim_prefix("--baseline-hud=")
	if source.is_empty(): return
	var legacy = load(source).new()
	game.add_child(legacy)
	legacy.setup(game.sim)
	legacy.refresh(game.selected, game.camera_focus, game.paused)
	legacy.set_tutorial(game.tutorial_step if game.tutorial_active else -1)
	if page == "recruit": legacy.show_recruitment(game.hud._recruit_id)
	elif not page.is_empty(): legacy.show_menu(page)
	game.hud.visible = false
	await capture(label)
	print("COMPARISON ",label," old_bottom=",legacy._bottom.size.y," new_bottom=",game.hud._bottom.size.y)
	legacy.queue_free()
	game.hud.visible = true
	await settle()

func resize(size: Vector2i) -> void:
	root.size = Vector2i(Vector2(size) * game._display_density())
	await create_timer(0.25).timeout
	game._apply_display_scale()
	await settle()
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game._test_running = true
	root.add_child(game)
	await settle()
	root.mode = Window.MODE_WINDOWED
	await resize(Vector2i(1280,800))
	game.hud.set_large_text(false)
	game.hud.show_menu("main")
	await capture("01-title")
	await baseline("before-title", "main")
	check(not game.hud._top.visible and not game.hud._bottom.visible, "title hides battle HUD")
	game._new_game()
	game.sim.ai_enabled = false
	game.set_process(false)
	game._on_action("select_workers")
	game._refresh_hud()
	await capture("02-desktop")
	await baseline("before-desktop")
	check(game.hud._action_scroll.get_h_scroll_bar().max_value <= game.hud._action_scroll.size.x, "desktop actions do not scroll horizontally")
	for button in game.hud._actions.get_children():
		if button is Button: check(game.hud._action_scroll.get_global_rect().encloses(button.get_global_rect()), "desktop action visible " + button.text)
	game._on_action("recruit")
	await capture("03-recruitment")
	await baseline("before-recruitment", "recruit")
	game.hud._modal_scroll.scroll_vertical = 100
	await settle()
	var scroll: int = game.hud._modal_scroll.scroll_vertical
	var card_id: int = game.hud._recruit_grid.get_child(0).get_instance_id()
	var balance: int = game.sim.resources[0].food
	game._on_action("recruit_unit", "worker")
	await settle()
	check(game.sim.resources[0].food == balance - 45, "recruit deducts real resources")
	check(game.hud._modal_scroll.scroll_vertical == scroll and game.hud._recruit_grid.get_child(0).get_instance_id() == card_id, "recruit preserves scroll and cards")
	game.sim.resources[0].food = 0
	game._on_action("recruit_unit", "ranger")
	check("资源不足" in game.hud._recruit_feedback, "insufficient resources explained")
	game.sim.resources[0] = {"food":9999,"wood":9999,"crystal":9999}
	var heart: Dictionary = game.sim._heart(0)
	heart.queue.clear()
	game.sim._spawn("house",0,Vector2(30,60))
	for i in range(5): game._on_action("recruit_unit", "worker")
	var queue_size: int = heart.queue.size()
	game._on_action("recruit_unit", "worker")
	check(heart.queue.size() == queue_size and "队列" in game.hud._recruit_feedback, "full queue explained without extra recruitment")
	heart.queue.clear()
	for entity in game.sim.entities:
		if entity.team == 0 and entity.kind == "house": entity.hp = 0
	for i in range(4): game.sim._spawn("worker",0,Vector2(25+i,60))
	game._on_action("recruit_unit", "worker")
	check("人口" in game.hud._recruit_feedback and heart.queue.is_empty(), "population cap explained")
	game._on_action("resume")
	game._on_action("manual")
	check(game.hud._return_page == "", "F1-style entry returns to battle")
	game.hud._dispatch("ui_back", null)
	check(not game.paused and not game.hud.is_modal_open(), "fixed back resumes battle")
	game._on_action("settings")
	await capture("04-settings")
	game._on_action("large_text", true)
	await capture("05-large-text")
	check(game.settings.large_text and game.hud._font_size(16) == 20, "large text preference applies")
	game.hud.show_menu("victory")
	await capture("06-result")
	game._new_game()
	game.sim.ai_enabled = false
	game._on_action("select_workers")
	game.hud.set_large_text(false)
	await resize(Vector2i(844,390))
	game._refresh_hud()
	await capture("07-mobile")
	await baseline("before-mobile")
	check(not game.hud._map_panel.visible, "mobile map collapsed by default")
	check(game.hud._bottom.size.y <= 150, "mobile HUD leaves battlefield space")
	for button in game.hud._actions.get_children():
		if button is Button:
			check(game.hud._action_scroll.get_global_rect().encloses(button.get_global_rect()), "mobile action visible " + button.text)
			check(button.size.x >= 48 and button.size.y >= 48, "mobile touch target " + button.text)
	input = load("res://tests/runtime_input.gd").new()
	var build_button = input.find_button(game.hud, "建造")
	await input.tap(game, build_button.get_global_rect().get_center())
	check(game.hud._page == "build_list" and game.paused, "touch opens construction catalog")
	await capture("08-mobile-build")
	var place_button = input.find_button(game.hud, "建造风栖居")
	await input.tap(game, place_button.get_global_rect().get_center())
	check(game.build_kind == "house" and not game.hud.is_modal_open(), "build catalog starts real placement")
	game._on_action("cancel")
	game._on_action("select_workers")
	game.hud._toast_time = 0
	game.hud.set_large_text(true)
	await capture("09-mobile-large")
	game.hud._dispatch("map_toggle", null)
	await settle()
	check(game.hud._map_panel.visible and not game.hud._map_panel.get_global_rect().intersects(game.hud._bottom.get_global_rect()), "expanded mobile map clears commands")
	await capture("09b-mobile-map")
	game.hud._dispatch("map_toggle", null)
	game.hud._safe_area_override = Rect2(44,0,756,369)
	game.hud._layout()
	await capture("10-safe-area")
	check(game.hud._bottom.get_global_rect().position.x >= 44 and game.hud._bottom.get_global_rect().end.x <= 800, "safe area respected")
	game.hud._safe_area_override = Rect2()
	game.hud.set_large_text(false)
	await resize(Vector2i(1920,1080))
	game._refresh_hud()
	await capture("11-desktop-wide")
	game.hud.show_menu("manual")
	await capture("12-manual")
	game.hud._clear_modal()
	game.hud._modal_caption.text = "潮晶界面 · 控件样板"
	for entry in [["普通指令", "normal"], ["悬停反馈", "hover"], ["按下反馈", "pressed"], ["键盘焦点", "focus"], ["不可用", "disabled"]]:
		var button = game.hud._button(entry[0], "")
		if entry[1] == "disabled": button.disabled = true
		elif entry[1] == "focus": button.grab_focus.call_deferred()
		else: button.add_theme_stylebox_override("normal", game.hud.UI.button_style(entry[1]))
		game.hud._modal_body.add_child(button)
	game.hud._modal_body.add_child(game.hud._button("启程 · 主要操作", "", null, true))
	game.hud._modal_body.add_child(game.hud._button("重新开始 · 危险操作", "restart"))
	await capture("14-button-specimen")
	await resize(Vector2i(390,844))
	await capture("13-portrait")
	print("REFINEMENT_SUMMARY checks=",checks," failures=",failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
