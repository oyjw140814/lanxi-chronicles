extends SceneTree
const Factory = preload("res://scripts/asset_factory.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(192, 192)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.TRANSPARENT
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b5d9d2")
	environment.environment.ambient_light_energy = 0.7
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45,-30,0)
	light.light_energy = 1.5
	viewport.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	viewport.add_child(camera)
	var factory := Factory.new()
	for kind in ["worker","guard","ranger","lancer","rider","breaker","heart","house","barracks","tower"]:
		var art := factory.make(kind,0)
		viewport.add_child(art)
		var h := factory.height_for(kind)
		var radius := factory.radius_for(kind)
		camera.size = maxf(h * 1.35, radius * 2.7)
		var target := Vector3(0,h*0.46,0)
		camera.position = target + Vector3(6,4.5,-8)
		camera.look_at(target)
		for i in range(4): await process_frame
		await RenderingServer.frame_post_draw
		var err := viewport.get_texture().get_image().save_png("res://assets/ui/portraits/%s.png" % kind)
		if err != OK: quit(1); return
		viewport.remove_child(art)
		art.free()
	print("UI_PORTRAITS 10 rendered from original models")
	quit()
