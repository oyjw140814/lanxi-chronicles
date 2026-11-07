extends RefCounted
## Check projected geometry, not world-space offsets that can hide billboard errors.
var checks := 0
var failures := 0

func check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("HEALTH FAIL ", detail)

func screen(camera: Camera3D, mesh: MeshInstance3D, local: Vector3) -> Vector2:
	return camera.unproject_position(mesh.to_global(local))

func run(game) -> int:
	game._new_game()
	game.set_process(false)
	game.sim.ai_enabled = false
	game.tutorial_active = false
	var entities: Array = game.sim.entities.filter(func(e): return e.team == 0 and e.kind in ["worker", "heart"])
	game.selected = entities.map(func(e): return e.id)
	for size in [Vector2i(1280,800), Vector2i(844,390), Vector2i(1920,1080)]:
		game.get_window().size = Vector2i(Vector2(size) * game._display_density())
		await game.get_tree().create_timer(0.25).timeout
		for zoom in [22.0, 39.0, 72.0]:
			game.camera_size = zoom
			game._update_camera()
			for angle in [0.0, 1.2]:
				var target := Vector3(game.camera_focus.x, 0, game.camera_focus.y)
				game.camera.position = target + Vector3(29,38,29).rotated(Vector3.UP, angle)
				game.camera.look_at(target)
				for fraction in [1.0, 0.6, 0.25, 0.05]:
					for e in entities: e.hp = e.max_hp * fraction
					# Motion changes position and rotates unit art independently of the bar.
					entities[1].pos += Vector2(0.01, 0.0)
					game.world.sync(game.sim.entities, game.selected, game.sim, 0.016)
					for e in [entities[0], entities[1]]:
						var visual: Dictionary = game.world.visuals[e.id]
						var bg: MeshInstance3D = visual.background
						var fill: MeshInstance3D = visual.fill
						var left := screen(game.camera, bg, Vector3(-0.53,0,0))
						var right := screen(game.camera, bg, Vector3(0.53,0,0))
						var fill_left := screen(game.camera, fill, Vector3(-0.47,0,0))
						var fill_right := screen(game.camera, fill, Vector3(0.47,0,0))
						var width := 64.0 if e.kind == "heart" else 44.0
						check(absf(left.y-right.y) < 0.05 and absf(left.y-fill_left.y) < 0.05, "background / fill share a horizontal axis")
						check(absf(left.distance_to(right)-width) < 0.05, "bar stays readable at every window / zoom")
						check(absf(fill_left.x-left.x-width*0.06/1.06) < 0.05, "left padding remains fixed during damage")
						check(absf(fill_left.distance_to(fill_right)-width*0.94/1.06*fraction) < 0.05, "fill shows correct health proportion")
						check(fill_right.x <= right.x and fill_left.x >= left.x, "fill remains inside background")
						check(visual.health.position.y > game.world._art_top(visual.art), "anchor stays above animated model")
	game.get_window().size = Vector2i(Vector2(Vector2i(1280,800)) * game._display_density())
	game.camera_size = 39.0
	game._update_camera()
	for progress in [0.0,0.25,0.75,1.0]:
		entities[0].built = progress
		game.world.sync(game.sim.entities, game.selected, game.sim, 0.0)
		var visual: Dictionary = game.world.visuals[entities[0].id]
		check(absf(visual.health.position.y - (visual.art_height * visual.art.scale.y + 0.30)) < 0.01, "construction bar follows visible building height")
	# Render one overview per zoom with all four health bands visible.
	for i in range(entities.size()): entities[i].hp = entities[i].max_hp * [1.0,0.7,0.4,0.15,0.9][i]
	for zoom in [22.0,39.0,72.0]:
		game.camera_size = zoom
		game._update_camera()
		game.world.sync(game.sim.entities, game.selected, game.sim, 0.0)
		game._refresh_hud()
		await game.get_tree().create_timer(0.2).timeout
		await game._capture("health-zoom-%d" % int(zoom))
	var worker: Dictionary = entities[1]
	worker.hp = worker.max_hp
	game.world.sync(game.sim.entities, [], game.sim, 0.0)
	check(not game.world.visuals[worker.id].health.visible, "healthy unselected unit hides health bar")
	worker.hp = 1.0
	game.world.sync(game.sim.entities, [], game.sim, 0.0)
	check(game.world.visuals[worker.id].health.visible, "damaged unselected unit shows health bar")
	var enemy: Dictionary = game.sim.entities.filter(func(e): return e.team == 1)[0]
	enemy.hp = 1.0
	game.world.sync(game.sim.entities, [], game.sim, 0.0)
	check(not game.world.visuals[enemy.id].health.is_visible_in_tree(), "fog hides enemy health bar")
	worker.hp = 0.0
	game.world.sync(game.sim.entities, [], game.sim, 0.0)
	check(not game.world.visuals.has(worker.id), "death removes bar along with model")
	game.world.reset_entities()
	check(game.world.visuals.is_empty(), "new game / load clears previous bars")
	game.camera_size = 39.0
	game.set_process(true)
	print("HEALTH_SUMMARY checks=", checks, " failures=", failures)
	return failures
