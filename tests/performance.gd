extends SceneTree
var game
var frames: Array[float] = []
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._test_running = true
	game._new_game()
	game.sim.ai_enabled = false
	game.tutorial_active = false
	game._refresh_hud()
	await create_timer(1.0).timeout
	await sample("opening_12_units", 5.0)
	game.world.reset_entities()
	game.sim.entities.clear()
	game.sim._by_id.clear()
	game.sim._spawn("heart", 0, Vector2(18, 58))
	game.sim._spawn("heart", 1, Vector2(62, 22))
	for team in range(2):
		for i in range(80):
			game.sim._spawn(["guard", "ranger", "lancer", "rider", "breaker"][i % 5], team, Vector2(24 + (i % 10) * 2.4, 22 + (i / 10) * 2.4 + team * 16))
	game.sim._rebuild_grid()
	game.sim._update_fog()
	game.camera_focus = Vector2(40, 40)
	game.camera_size = 72.0
	game._update_camera()
	await create_timer(1.0).timeout
	await sample("synthetic_160_units", 5.0)
	game.queue_free()
	await process_frame
	quit()

func sample(label: String, seconds: float) -> void:
	var deltas: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while (Time.get_ticks_usec() - start) / 1000000.0 < seconds:
		await process_frame
		var now := Time.get_ticks_usec()
		deltas.append((now - previous) / 1000.0)
		previous = now
	var total := 0.0
	for delta in deltas: total += delta
	deltas.sort()
	print("BENCHMARK ", label, " frames=", deltas.size(), " avg_fps=", snappedf(deltas.size() * 1000.0 / total, 0.1), " p95_frame_ms=", snappedf(deltas[int(deltas.size() * 0.95)], 0.1), " entities=", game.sim.entities.size(), " draw_calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " viewport=", root.size, " quality=", game.settings.quality)
