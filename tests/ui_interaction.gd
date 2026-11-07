extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game._test_running = true
	root.add_child(game)
	for i in range(12): await process_frame
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(Vector2(1280,800) * game._display_density())
	await create_timer(0.3).timeout
	game.hud.set_large_text(false)
	var input = load("res://tests/runtime_input.gd").new()
	var failures: int = await input.run(game)
	var content = load("res://tests/content_ui.gd").new()
	failures += await content.run(game)
	print("UI_INTERACTION failures=",failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
