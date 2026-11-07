extends Node3D
## Rendering adapter for the deterministic simulation; world X/Z corresponds to sim Vector2.
const AssetFactory = preload("res://scripts/asset_factory.gd")
const UNIT_KINDS := ["worker", "guard", "ranger", "lancer", "rider", "breaker"]
const BUILDING_KINDS := ["heart", "hq", "house", "barracks", "tower"]
signal presentation_event(event: Dictionary)
const Motion = preload("res://scripts/unit_motion.gd")
const Effects = preload("res://scripts/battle_effects.gd")
const Condition = preload("res://scripts/building_condition.gd")
const Dressing = preload("res://scripts/battlefield_dressing.gd")
const MAX_EFFECTS := 64
var motion = Motion.new()
var condition = Condition.new()
var dressing = Dressing.new()
var battle_fx = Effects.new()
var _view_sim
var _last_selected: Array = []
var _model_lod := 0
var _secondary_details := true
var factory = AssetFactory.new()
var visuals: Dictionary = {}
var _entity_root: Node3D
var _decor_root: Node3D
var _sun: DirectionalLight3D
var _environment: WorldEnvironment
var _water: MeshInstance3D
var _preview: Node3D
var _preview_kind := ""
var _preview_valid := true
var _fog_image: Image
var _fog_texture: ImageTexture
var _fog_material: ShaderMaterial
var _fog_clock := 1.0
var _time := 0.0
var _effects: Array[Dictionary] = []
var _quality := 1
var _setup_done := false

func setup() -> void:
	if _setup_done:
		return
	_setup_done = true
	_entity_root = Node3D.new()
	_entity_root.name = "Entities"
	add_child(_entity_root)
	_decor_root = Node3D.new()
	_decor_root.name = "IslandDetails"
	add_child(_decor_root)
	_create_environment()
	_create_island()
	_create_water()
	_create_decor()
	_create_fog()
	add_child(battle_fx)
	battle_fx.setup(factory)
	set_quality(_quality)

func _create_environment() -> void:
	_environment = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("183d47")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("abd9d3")
	env.ambient_light_energy = 0.40
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	_environment.environment = env
	add_child(_environment)
	_sun = DirectionalLight3D.new()
	_sun.name = "GoldenHourSun"
	_sun.light_color = Color("fff0c8")
	_sun.light_energy = 0.85
	_sun.rotation_degrees = Vector3(-56,-28,0)
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 135.0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.shadow_bias = 0.07
	_sun.shadow_normal_bias = 0.9
	add_child(_sun)
	var fill := DirectionalLight3D.new()
	fill.name = "OceanBounce"
	fill.rotation_degrees = Vector3(-30,145,0)
	fill.light_color = Color("87c9ce")
	fill.light_energy = 0.12
	fill.shadow_enabled = false
	add_child(fill)

func _terrain_color(x: float, z: float) -> Color:
	var edge := minf(minf(x,80.0-x),minf(z,80.0-z))
	var noise := sin(x*0.17+cos(z*0.18)*1.3)*cos(z*0.12)+sin(x*0.63+z*0.23)*0.15
	var base := Color("809b73").lerp(Color("527f6b"),clampf(noise*0.28+0.4,0.0,1.0))
	base = base.darkened((sin(x*2.3+z*1.7)*cos(z*2.1)*0.5+0.5)*0.055)
	if edge < 5.0:
		base = Color("d5c79c").lerp(base,smoothstep(1.0,5.0,edge))
	# Broad, worn limestone routes linking the two settlements through the atoll.
	base = dressing.road_color(Vector2(x,z),base)
	var clearing_a := Vector2(x,z).distance_to(Vector2(18,58))
	var clearing_b := Vector2(x,z).distance_to(Vector2(62,22))
	var clearing := smoothstep(4.0,10.0,minf(clearing_a,clearing_b))
	return Color("b6b48d").lerp(base,clearing)

func _create_island() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(40):
		for x in range(40):
			var verts := [Vector3(x*2,0,z*2),Vector3(x*2+2,0,z*2),Vector3(x*2,0,z*2+2),Vector3(x*2+2,0,z*2),Vector3(x*2+2,0,z*2+2),Vector3(x*2,0,z*2+2)]
			for v in verts:
				st.set_color(_terrain_color(v.x,v.z))
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	var ground := get_node_or_null("TravellableAtoll") as MeshInstance3D
	if ground != null:
		ground.mesh = st.commit()
		return
	ground = MeshInstance3D.new()
	ground.name = "TravellableAtoll"
	ground.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.material_override = mat
	add_child(ground)
	# Stacked exposed strata; the top is rigorously flat so clicks and paths share one plane.
	for level in range(3):
		var h := 0.7
		var size := 80.0 + float(level)*0.45
		var layer := factory.piece(self,factory.box(Vector3(size,h,size)),Color("b5b192").darkened(float(level)*0.12),Vector3(40,-0.38-float(level)*0.66,40))
		layer.name = "CoastalStratum" + str(level)
		layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Low shoreline rocks remain outside the playable boundary.
	var rng := RandomNumberGenerator.new()
	rng.seed = 72241
	var shore := Node3D.new()
	shore.name = "ShoreRocks"
	_decor_root.add_child(shore)
	for i in range(72):
		var side := i % 4
		var along := rng.randf_range(-1,81)
		var pos := Vector3(along,-0.78,-0.7-rng.randf_range(0,1.5))
		if side == 1: pos = Vector3(along,-0.78,80.7+rng.randf_range(0,1.5))
		if side == 2: pos = Vector3(-0.7-rng.randf_range(0,1.5),-0.78,along)
		if side == 3: pos = Vector3(80.7+rng.randf_range(0,1.5),-0.78,along)
		var rock := factory.piece(shore,factory.sphere(rng.randf_range(0.4,1.2),rng.randf_range(0.5,1.4)),Color("c0b997"),pos,Vector3(0,rng.randf()*360,0))
		rock.scale.x = rng.randf_range(1.1,1.8)

	factory.batcher.bake(shore,"shoreline")
	factory.set_lod(shore,1)

func _create_water() -> void:
	_water = MeshInstance3D.new()
	_water.name = "TidalSea"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(310,310)
	mesh.subdivide_width = 55
	mesh.subdivide_depth = 55
	_water.mesh = mesh
	_water.position = Vector3(40,-1.68,40)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/water.gdshader")
	_water.material_override = mat
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)
	# Soft foam lines frame the coastline without changing navigation.
	for side in range(4):
		var pos := Vector3(40,-1.47,-1.8)
		var size := Vector3(81,0.025,0.18)
		if side == 1: pos = Vector3(40,-1.47,81.8)
		if side == 2:
			pos = Vector3(-1.8,-1.47,40)
			size = Vector3(0.18,0.025,81)
		if side == 3:
			pos = Vector3(81.8,-1.47,40)
			size = Vector3(0.18,0.025,81)
		var foam := factory.piece(_decor_root,factory.box(size),Color("8db6ab"),pos)
		foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _create_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 19932
	# Small, quiet grass accents only. Keep the field readable around units and buildings.
	var blade := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(2):
		var angle := TAU * i / 3.0
		var tangent := Vector3(cos(angle),0,sin(angle))
		st.set_color(Color("758c65"))
		st.add_vertex(tangent*-0.10)
		st.set_color(Color("adc090"))
		st.add_vertex(Vector3(0.03,0.12+float(i)*0.025,0.015))
		st.set_color(Color("758c65"))
		st.add_vertex(tangent*0.10)
	st.generate_normals()
	blade = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	blade.surface_set_material(0,mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = blade
	mm.instance_count = 180
	for i in range(180):
		# A loose 12x15 layout is calmer and easier to read than fully random scatter.
		var col := i % 12
		var row := i / 12
		var p := Vector3(5.0 + float(col) * 6.0 + rng.randf_range(-1.1,1.1),0.03,5.0 + float(row) * 4.9 + rng.randf_range(-1.1,1.1))
		var basis := Basis(Vector3.UP,[-0.18,0.0,0.18][i % 3]).scaled(Vector3.ONE*(0.82 if i % 4 else 0.94))
		mm.set_instance_transform(i,Transform3D(basis,p))
	var grass := MultiMeshInstance3D.new()
	grass.name = "InstancedSaltgrass"
	grass.multimesh = mm
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_decor_root.add_child(grass)

func _create_fog() -> void:
	_fog_image = Image.create(40,40,false,Image.FORMAT_RGBA8)
	_fog_image.fill(Color(0,0,0,0.94))
	_fog_texture = ImageTexture.create_from_image(_fog_image)
	_fog_material = ShaderMaterial.new()
	_fog_material.shader = preload("res://shaders/fog.gdshader")
	_fog_material.set_shader_parameter("visibility_map",_fog_texture)
	var fog := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80,80)
	fog.mesh = plane
	fog.material_override = _fog_material
	fog.position = Vector3(40,0.085,40)
	fog.name = "ExplorationFog"
	fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fog)

func _update_fog(sim) -> void:
	if not sim.has_method("is_visible") or not sim.has_method("is_explored"):
		_fog_image.fill(Color(0,0,0,0))
	else:
		for y in range(40):
			for x in range(40):
				var pos := Vector2(x*2+1,y*2+1)
				var alpha := 0.0 if sim.is_visible(pos,0) else (0.52 if sim.is_explored(pos,0) else 0.96)
				_fog_image.set_pixel(x,y,Color(0,0,0,alpha))
	_fog_texture.update(_fog_image)
	dressing.apply_visibility(_decor_root.get_node_or_null("InstancedSaltgrass"),sim)

func sync(entities: Array, selected: Array, sim, dt: float) -> void:
	if not _setup_done:
		setup()
	_view_sim = sim
	if selected != _last_selected:
		_last_selected = selected.duplicate()
		presentation_event.emit({"type":"selection","ids":selected.duplicate()})
	_time += dt
	_water.material_override.set_shader_parameter("visual_time",_time)
	dressing.refresh_grass(_decor_root.get_node_or_null("InstancedSaltgrass"),entities)
	_fog_clock += dt
	var living: Dictionary = {}
	for e in entities:
		var id: int = int(e.id)
		living[id] = true
		if float(e.get("hp",1.0)) <= 0.0:
			if visuals.has(id):
				_discard_visual(id)
			continue
		if visuals.has(id):
			var cached: Dictionary = visuals[id]
			if str(cached.kind) != str(e.kind) or int(cached.team) != int(e.team):
				# Saves may reuse identifiers for a completely different entity.
				_discard_visual(id)
		if not visuals.has(id):
			_create_entity(e)
		var visual: Dictionary = visuals[id]
		var node: Node3D = visual.node
		var pos: Vector2 = e.pos
		var is_seen := true
		if int(e.team) != 0 and sim.has_method("is_visible"):
			is_seen = sim.is_visible(pos,0)
			if int(e.team) == -1 and sim.has_method("is_explored"):
				is_seen = sim.is_explored(pos,0)
		if is_seen and bool(visual.get("was_seen",false)) and float(e.hp) < float(visual.get("last_hp",e.hp)):
			visual.hit_age = 0.0
		visual.last_hp = float(e.hp)
		visual.was_seen = is_seen
		node.visible = is_seen
		if not is_seen:
			continue
		var previous_position := node.position
		var target_position := Vector3(pos.x,0.10,pos.y)
		var movement := target_position-node.position
		var is_unit: bool = e.kind in UNIT_KINDS
		# The rules tick at 10 Hz; interpolate only the visual transform so walking
		# and limb cycles do not stop on the intervening rendered frames.
		visual.motion_time = maxf(0.0,float(visual.get("motion_time",0.0))-dt)
		if is_unit and movement.length_squared() > 0.001:
			visual.motion_time = 0.14
		if is_unit and movement.length_squared() > 0.0005 and movement.length_squared() < 30.0:
			var yaw := atan2(-movement.x,-movement.z)
			visual.art.rotation.y = lerp_angle(visual.art.rotation.y,yaw,minf(dt*12.0,1.0))
		node.position = node.position.lerp(target_position,minf(1.0,dt*20.0)) if is_unit and dt > 0.0 and movement.length_squared() < 30.0 else (node.position if dt <= 0.0 and is_unit else target_position)
		visual.travel = node.position.distance_to(previous_position)
		var desired_lod := 1 if _model_lod > 0 or (get_viewport().get_camera_3d() != null and get_viewport().get_camera_3d().size >= 60.0) else 0
		if int(visual.art.get_meta("lod",0)) != desired_lod: factory.set_lod(visual.art,desired_lod)
		var chosen := selected.has(id)
		visual.ring.visible = chosen
		var fraction := clampf(float(e.get("hp",1.0))/maxf(float(e.get("max_hp",1.0)),1.0),0.0,1.0)
		_sync_health(visual, e, fraction, chosen)
		if e.kind in BUILDING_KINDS:
			var built := clampf(float(e.get("built",1.0)),0.0,1.0)
			visual.art.scale.y = 0.12 + built*0.88
			visual.scaffold.visible = built < 0.999
			condition.update(visual,e,_time,_secondary_details)
		if is_unit:
			_animate_unit(visual,e,dt,float(visual.motion_time) > 0.0)
		elif visual.art.has_meta("crystal"):
			var gem: MeshInstance3D = visual.art.get_meta("crystal")
			gem.rotation.y += dt*0.32
			gem.position.y = 3.98 + sin(_time*1.4+id)*0.055
		if visual.art.has_meta("banner"):
			var flag: MeshInstance3D = visual.art.get_meta("banner")
			flag.rotation.y = sin(_time*1.7+id)*0.10
	for id in visuals.keys():
		if not living.has(id):
			_discard_visual(int(id))
	if _fog_clock > 0.23:
		_fog_clock = 0.0
		_update_fog(sim)
	battle_fx.update(dt,sim,get_viewport().get_camera_3d())

func _sync_health(visual: Dictionary, e: Dictionary, fraction: float, chosen: bool) -> void:
	var health: Node3D = visual.health
	var camera := get_viewport().get_camera_3d()
	health.visible = int(e.team) >= 0 and (chosen or fraction < 0.995) and camera != null
	if not health.visible:
		return
	var growth := 0.12 + clampf(float(e.get("built", 1.0)), 0.0, 1.0) * 0.88 if e.kind in BUILDING_KINDS else 1.0
	health.position.y = float(visual.art_height) * growth + 0.30
	if camera.is_position_behind(health.global_position):
		health.visible = false
		return
	# Rotate the whole bar, including the fill's local offset, in one coordinate frame.
	# Independent material billboards leave the shrinking fill displaced along world X.
	var facing := camera.global_basis.orthonormalized()
	var center := camera.unproject_position(health.global_position)
	var pixels_per_unit := center.distance_to(camera.unproject_position(health.global_position + facing.x))
	var width := 64.0 if e.kind in BUILDING_KINDS else 44.0
	health.global_basis = facing.scaled(Vector3.ONE * width / maxf(pixels_per_unit * 1.06, 0.01))
	var fill: MeshInstance3D = visual.fill
	fill.scale.x = maxf(fraction, 0.001)
	fill.position.x = -0.47 * (1.0 - fraction)
	var color := Color("8ae0b2") if int(e.team) == 0 else Color("ed9d75")
	if fraction < 0.25:
		color = Color("ff7664")
	elif fraction < 0.5:
		color = Color("f2c66b")
	fill.material_override.albedo_color = color

func _art_top(node: Node3D, transform_from_art: Transform3D = Transform3D.IDENTITY) -> float:
	var top := 0.0
	if node is MeshInstance3D:
		var bounds: AABB = transform_from_art * node.get_aabb()
		top = bounds.end.y
	for child in node.get_children():
		if child is Node3D:
			top = maxf(top, _art_top(child, transform_from_art * child.transform))
	return top

func _create_entity(e: Dictionary) -> void:
	var node := Node3D.new()
	node.name = "Entity_"+str(e.id)
	node.position = Vector3(e.pos.x,0.1,e.pos.y)
	_entity_root.add_child(node)
	var art: Node3D = factory.make(str(e.kind),int(e.team),int(e.id))
	node.add_child(art)
	var radius: float = factory.radius_for(str(e.kind))
	var ring := factory.piece(node,factory.ring(radius),Color("b6f8d7"),Vector3(0,0.035,0))
	ring.material_override = _unshaded(Color("9feec8"))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	var health := Node3D.new()
	health.position.y = factory.height_for(str(e.kind))+0.35
	node.add_child(health)
	var bar := QuadMesh.new()
	bar.size = Vector2(1.06,0.17)
	var bg := factory.piece(health,bar,Color("183b37"),Vector3.ZERO)
	var bm := _unshaded(Color("183b37"))
	bm.no_depth_test = true
	bg.material_override = bm
	bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fm := QuadMesh.new()
	fm.size = Vector2(0.94,0.09)
	var fill := factory.piece(health,fm,Color.WHITE,Vector3(0,0,0.01))
	var color := Color("8ae0b2") if int(e.team) != 1 else Color("ed9d75")
	var fmat := _unshaded(color)
	fmat.no_depth_test = true
	fmat.render_priority = 1
	fill.material_override = fmat
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	health.visible = false
	var scaffold := Node3D.new()
	node.add_child(scaffold)
	if e.kind in BUILDING_KINDS:
		for i in range(4):
			var a := TAU*i/4.0+PI/4
			factory.piece(scaffold,factory.cylinder(0.055,0.055,2.2,5),Color("b9986a"),Vector3(sin(a)*radius,1.1,cos(a)*radius))
			factory.piece(scaffold,factory.box(Vector3(radius*1.42,0.065,0.065)),Color("c4a176"),Vector3(0,1.85,(1 if i%2 == 0 else -1)*radius*0.707),Vector3(0,90 if i>1 else 0,0))
			factory.piece(scaffold,factory.box(Vector3(radius*1.40,0.07,0.07)),Color("a88560"),Vector3(0,1.1,(1 if i%2 == 0 else -1)*radius*0.707),Vector3(0,90 if i>1 else 0,25 if i%2 == 0 else -25))
		factory.batcher.bake(scaffold,"scaffold/"+str(e.kind))
	scaffold.visible = false
	var damage := condition.create(factory,str(e.kind),node) if e.kind in BUILDING_KINDS else {}
	visuals[int(e.id)] = {"node":node,"art":art,"art_height":_art_top(art) + (0.12 if e.kind in UNIT_KINDS else 0.06),"ring":ring,"health":health,"background":bg,"fill":fill,"scaffold":scaffold,"kind":str(e.kind),"team":int(e.team),"damage":damage}

func _unshaded(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	if color.a < 0.99:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat

func _animate_unit(visual: Dictionary,e: Dictionary,dt: float,moving: bool) -> void:
	motion.update(visual,e,_view_sim,dt,moving,_time)

func set_preview(kind: String,pos: Vector2,valid: bool) -> void:
	if not _setup_done:
		setup()
	if _preview == null or _preview_kind != kind:
		clear_preview()
		_preview = factory.make(kind,0,999)
		_preview_kind = kind
		add_child(_preview)
		var radius: float = factory.radius_for(kind)
		factory.piece(_preview,factory.ring(radius+0.1,0.065),Color.WHITE,Vector3(0,0.04,0))
		_apply_preview_material(_preview,valid)
	elif valid != _preview_valid:
		_apply_preview_material(_preview,valid)
	_preview_valid = valid
	_preview.position = Vector3(pos.x,0.12,pos.y)

func _apply_preview_material(node: Node,valid: bool) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var col := Color(0.45,0.95,0.76,0.5) if valid else Color(1.0,0.32,0.23,0.5)
		mesh_node.material_override = _unshaded(col)
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_apply_preview_material(child,valid)

func clear_preview() -> void:
	if is_instance_valid(_preview):
		_preview.visible = false
		_preview.queue_free()
	_preview = null
	_preview_kind = ""

func show_order(pos: Vector2,attack: bool = false) -> void:
	if not _setup_done: return
	battle_fx.order(pos,attack)
	presentation_event.emit({"type":"order","point":pos,"attack":attack})

func _discard_visual(id: int) -> void:
	if not visuals.has(id):
		return
	var node: Node3D = visuals[id].node
	if is_instance_valid(node):
		node.visible = false
		node.queue_free()
	visuals.erase(id)

func reset_entities() -> void:
	# Called after reset/load. Hide queued objects immediately to avoid one-frame ghosts.
	for id in visuals.keys():
		_discard_visual(int(id))
	for effect in _effects:
		if is_instance_valid(effect.node):
			effect.node.visible = false
			effect.node.queue_free()
	_effects.clear()
	battle_fx.reset()
	_last_selected.clear()
	clear_preview()
	_time = 0.0
	_fog_clock = 1.0
	if _fog_image != null and _fog_texture != null:
		_fog_image.fill(Color(0,0,0,0.96))
		_fog_texture.update(_fog_image)

func show_combat(event: Dictionary) -> void:
	# Public adapter kept compatible; the controller is still the sole event consumer.
	if not _setup_done or _view_sim == null: return
	var point: Variant = event.get("point")
	var from: Variant = event.get("from")
	if not point is Vector2 or not from is Vector2: return
	if not point.is_finite() or not from.is_finite(): return
	if not _view_sim.is_visible(point,0) or not _view_sim.is_visible(from,0): return
	var source_id := int(event.get("id",-1))
	if visuals.has(source_id):
		motion.strike(visuals[source_id],event)
		if from.distance_squared_to(point) > 0.001:
			visuals[source_id].art.rotation.y = atan2(from.x-point.x,from.y-point.y)
	var target_id := int(event.get("target",-1))
	if visuals.has(target_id): visuals[target_id].hit_age = 0.0
	battle_fx.combat(event,_view_sim,get_viewport().get_camera_3d())
	if battle_fx._visible(point,_view_sim,get_viewport().get_camera_3d()):
		var attack := event.duplicate()
		attack.type = "attack"
		presentation_event.emit(attack)
		var hit := event.duplicate()
		hit.type = "hit"
		presentation_event.emit(hit)

func show_destroyed(event: Dictionary) -> void:
	if not _setup_done or _view_sim == null: return
	var id := int(event.get("id",-1))
	battle_fx.death(event,visuals.get(id,{}),_view_sim,get_viewport().get_camera_3d())
	_discard_visual(id) # Health/selection disappear immediately, independent of the corpse.
	if battle_fx._visible(event.point,_view_sim,get_viewport().get_camera_3d()) and int(event.get("team",-1)) >= 0:
		var death := event.duplicate()
		death.type = "collapse" if str(event.get("kind","")) in BUILDING_KINDS else "death"
		presentation_event.emit(death)

func set_visual_detail(model_lod: int, secondary_details: bool = true) -> void:
	# 06 can call this without affecting shadows, simulation, health or input.
	_model_lod = clampi(model_lod,0,1)
	_secondary_details = secondary_details
	battle_fx.secondary = secondary_details
	if is_instance_valid(_decor_root):
		var grass := _decor_root.get_node_or_null("InstancedSaltgrass") as MultiMeshInstance3D
		if grass != null: grass.visible = secondary_details
	for visual in visuals.values(): factory.set_lod(visual.art,_model_lod)

func set_decoration_profile(profile: Dictionary) -> void:
	# 03 provides roads/exclusion discs after switching maps; no navigation mutation.
	dressing.set_profile(profile)
	if _setup_done: _create_island()

func set_quality(level: int) -> void:
	_quality = clampi(level,0,2)
	set_visual_detail(1 if _quality == 0 else 0,_quality > 0)
	if not _setup_done:
		return
	_sun.shadow_enabled = _quality > 0
	_sun.directional_shadow_max_distance = 145.0 if _quality == 2 else 95.0
	if is_instance_valid(_water):
		_water.material_override.set_shader_parameter("wave_strength",0.04 if _quality == 0 else 0.11)
	if is_instance_valid(_decor_root):
		var grass := _decor_root.get_node_or_null("InstancedSaltgrass") as MultiMeshInstance3D
		if grass:
			grass.multimesh.visible_instance_count = [60,110,180][_quality]
