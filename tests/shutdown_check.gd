extends SceneTree
## Isolates HUD ownership from the native visual-test coroutine.
## Run with --headless --verbose --script tests/shutdown_check.gd.
## Add `-- --live-exit` to quit while the settings menu remains open.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var sim = load("res://scripts/simulation.gd").new()
	var hud = load("res://scripts/hud.gd").new()
	root.add_child(hud)
	hud.setup(sim)
	for iteration in range(5):
		for page in ["main", "settings", "manual", "pause"]:
			hud.show_menu(page)
			await process_frame
			await process_frame
	hud.show_menu("settings")
	await process_frame
	await process_frame
	if "--live-exit" in OS.get_cmdline_user_args():
		print("SHUTDOWN live settings menu; ownership released by SceneTree shutdown")
		quit()
		return
	var references: Array[WeakRef] = [weakref(hud), weakref(hud._theme), weakref(hud._display_font), weakref(hud._theme.default_font), weakref(sim)]
	hud.queue_free()
	hud = null
	sim = null
	await process_frame
	await process_frame
	var retained := 0
	for reference in references:
		if reference.get_ref() != null:
			retained += 1
			print("SHUTDOWN retained ", reference.get_ref())
	print("SHUTDOWN references_checked=", references.size(), " retained=", retained)
	quit(1 if retained > 0 else 0)
