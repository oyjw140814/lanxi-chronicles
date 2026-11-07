extends SceneTree
## Explicit visual fixture. Real Simulation.command/step/damage/cleanup; synthetic spawn/HP
## setup isolates animation, so this does not claim a normally financed match or FPS target.
const Sim = preload("res://scripts/simulation.gd")
const Factory = preload("res://scripts/asset_factory.gd")
var game
var checks := 0
var failures := 0
var evidence: Dictionary = {"fixture":true,"engine":Engine.get_version_info().string,"models":{},"draw_calls":{},"events":{}}
var poses: Dictionary = {}
var movie_frames := 0
const EVIDENCE_DIR := "res://builds/modeling-20261017"

func _initialize() -> void: call_deferred("run")
func check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("ART ","PASS " if ok else "FAIL ",detail)

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EVIDENCE_DIR))
	image.save_png(EVIDENCE_DIR+"/"+label+".png")
	print("ART_FRAME ",label)

func metrics(node: Node) -> Dictionary:
	var value := {"meshes":0,"surfaces":0,"vertices":0}
	if node is MeshInstance3D and node.mesh != null:
		value.meshes += 1
		value.surfaces += node.mesh.get_surface_count()
		for i in range(node.mesh.get_surface_count()):
			value.vertices += node.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX].size()
	for child in node.get_children():
		var sub := metrics(child)
		for key in value: value[key] += sub[key]
	return value

func tick(count: int, dt: float = 1.0/30.0, simulate: bool = true, film: bool = false) -> void:
	for i in range(count):
		if simulate:
			game.sim.step(dt)
			game._consume_events()
		game.world.sync(game.sim.entities,game.selected,game.sim,dt)
		for id in game.world.visuals:
			var v: Dictionary = game.world.visuals[id]
			var key := str(v.kind)+"/"+str(v.get("pose_phase","static"))
			poses[key] = int(poses.get(key,0))+1
		await process_frame
		if film and "--film-modeling" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			image.resize(1280,800,Image.INTERPOLATE_LANCZOS)
			image.save_jpg("res://builds/motion-frames/%05d.jpg" % movie_frames,0.86)
			movie_frames += 1

func fixture() -> void:
	game.world.reset_entities()
	game.sim.reset()
	game.sim.entities.clear()
	game.sim._by_id.clear()
	game.sim.events.clear()
	game.sim.ai_enabled = false
	game.selected.clear()
	game.sim._rebuild_grid()
	game.hud._root.visible = false

func camera(point: Vector2, zoom: float) -> void:
	game.camera_focus = point
	game._update_camera()
	game.camera.size = zoom

func refresh() -> void:
	game.sim._update_fog()
	game.world._fog_clock = 1.0
	game.world.sync(game.sim.entities,game.selected,game.sim,0.0)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/motion-frames"))
	game = load("res://scripts/main.gd").new()
	root.add_child(game)
	game._test_running = true
	await process_frame
	await process_frame
	game._new_game()
	game.set_process(false)
	game.audio.apply(0.0,false)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920,1200)
	await process_frame
	game._apply_display_scale()
	check(OS.get_user_data_dir().contains("LanXi-Modeling-"),"独立用户数据目录："+OS.get_user_data_dir())
	if failures > 0:
		game.queue_free()
		quit(1)
		return
	# Native default camera, real starting resources/enemies/fog.
	game.world.sync(game.sim.entities,[],game.sim,0.016)
	await capture("01-default-real-start")
	var base_script := GDScript.new()
	base_script.source_code = FileAccess.get_file_as_string("res://handoff/pre-modeling/scripts/asset_factory.gd")
	check(base_script.reload() == OK,"从保存的基线加载原模型")
	var baseline = base_script.new()
	var factory := Factory.new()
	for kind in ["worker","guard","ranger","lancer","rider","breaker","heart","house","barracks","tower"]:
		var old: Node3D = baseline.make(kind,0)
		var current: Node3D = factory.make(kind,0)
		var high := metrics(current)
		factory.set_lod(current,1)
		var low := metrics(current)
		evidence.models[kind] = {"baseline":metrics(old),"lod0":high,"lod1":low}
		check(high.meshes < metrics(old).meshes,"合并刚性小网格："+kind)
		check(low.surfaces <= high.surfaces and low.vertices < high.vertices,"简化网格真实减少表面/顶点："+kind)
		old.free()
		current.free()
	# Same-camera before/after six-unit gallery, rendered one version at a time.
	fixture()
	var index := 0
	for kind in game.Data.UNITS:
		game.sim._spawn(kind,0,Vector2(24+index*2.6,55))
		index += 1
	camera(Vector2(30.5,55),13.0)
	refresh()
	var original := Node3D.new()
	game.add_child(original)
	for e in game.sim.entities:
		var old: Node3D = baseline.make(e.kind,0,e.id)
		old.position = Vector3(e.pos.x,0.1,e.pos.y)
		old.rotation.y = -PI*0.75
		original.add_child(old)
		game.world.visuals[e.id].art.rotation.y = -PI*0.75
	game.world._entity_root.visible = false
	await tick(3,0.0,false)
	evidence.draw_calls.baseline_gallery = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	await capture("02-before-close")
	original.visible = false
	game.world._entity_root.visible = true
	await tick(3,0.0,false)
	evidence.draw_calls.current_gallery = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	await capture("03-after-close")
	camera(Vector2(30.5,55),39.0)
	await capture("04-after-default")
	original.visible = true
	game.world._entity_root.visible = false
	await capture("05-before-default")
	original.free()
	game.world._entity_root.visible = true
	camera(Vector2(30.5,55),13.0)
	game.world.set_visual_detail(1,false)
	await tick(3,0.0,false)
	evidence.draw_calls.lod1_gallery = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	await capture("06-lod1-close")
	game.world.set_visual_detail(0,true)
	# Real movement orders; phase advances from distance, not wall-clock idle time.
	for e in game.sim.entities: game.sim.command([e.id],"move",e.pos+Vector2(0,-5))
	await tick(45,1.0/30.0,true,true)
	await capture("07-walk")
	check(poses.has("rider/walk") and poses.has("breaker/walk"),"坐骑与攻坚兽真实移动驱动步态")
	# Real harvest and paid construction: original resource/popup paths remain playable.
	game._new_game()
	game.set_process(false)
	game.sim.ai_enabled = false
	game.hud._root.visible = false
	var worker: Dictionary = game.sim.entities.filter(func(e): return e.team == 0 and e.kind == "worker")[0]
	var resource: Dictionary = game.sim._nearest_resource(worker.pos,"food")
	check(game.sim.command([worker.id],"gather",resource.pos,resource.id) == "","采集使用现有合法命令")
	camera(resource.pos,12.0)
	refresh()
	await tick(90,1.0/30.0,true)
	await tick(30,1.0/30.0,true,true)
	await capture("07a-harvest")
	check(int(worker.carry)>0 and poses.has("worker/work"),"采集真实产出与0.7秒工作周期动作")
	var before_wood: int = game.sim.resources[0].wood
	var building_point := Vector2(29,58)
	var nearest := INF
	for y in range(55,73):
		for x in range(5,31):
			var candidate := Vector2(x,y)
			if game.sim.can_place("house",candidate) and game.sim.is_visible(candidate) and worker.pos.distance_to(candidate) < nearest:
				building_point = candidate
				nearest = worker.pos.distance_to(candidate)
	var construction_error: String = game.sim.build("house",building_point,[worker.id])
	check(construction_error == "","工人从采集转为合法施工："+construction_error)
	check(game.sim.resources[0].wood == before_wood-game.Data.COSTS.house.wood,"施工正常支付成本")
	camera(building_point,15.0)
	await tick(90,1.0/30.0,true)
	await tick(30,1.0/30.0,true,true)
	await capture("07b-building-work")
	check(game.sim.entities.any(func(e): return e.kind == "house" and e.built > 0.01 and e.built < 1.0),"施工动作关联真实建造进度")
	# Readable building construction / damage, no navigation changes.
	fixture()
	index = 0
	for kind in game.Data.BUILDINGS:
		game.sim._spawn(kind,0,Vector2(20+index*7.0,53))
		index += 1
	camera(Vector2(30.5,53),28.0)
	refresh()
	await capture("08-buildings-complete")
	for e in game.sim.entities: e.built = 0.45; e.hp = e.max_hp*0.505
	refresh()
	await capture("09-construction")
	check(game.world.visuals.values().all(func(v): return v.scaffold.visible and not v.damage.root.visible),"施工脚手架出现，不把未完工生命当伤损")
	for e in game.sim.entities: e.built = 1.0; e.hp = e.max_hp*0.25
	refresh()
	await tick(10,1.0/30.0,false)
	await capture("10-damage")
	check(game.world.visuals.values().all(func(v): return v.damage.root.visible and v.damage.smoke.visible),"重损裂痕、烟尘及屋顶偏移可见")
	# Controlled real combat fixture: ranger fires at guard, guard/lancer/breaker fight.
	fixture()
	var ranged: Dictionary = game.sim._spawn("ranger",0,Vector2(25,55))
	var guard: Dictionary = game.sim._spawn("guard",1,Vector2(31,55))
	var lancer: Dictionary = game.sim._spawn("lancer",0,Vector2(31,58))
	var enemy: Dictionary = game.sim._spawn("rider",1,Vector2(33,58))
	var breaker: Dictionary = game.sim._spawn("breaker",0,Vector2(29,50))
	var house: Dictionary = game.sim._spawn("house",1,Vector2(29,47.8))
	house.hp = 120.0
	guard.hp = 40.0
	game.sim._spawn("worker",0,Vector2(28,53)) # Normal vision coverage during casualties.
	camera(Vector2(29,53),17.0)
	refresh()
	game.world.presentation_event.connect(func(event):
		var type := str(event.get("type",""))
		evidence.events[type] = int(evidence.events.get(type,0))+1)
	game.sim.command([ranged.id],"attack",guard.pos,guard.id)
	game.sim.command([lancer.id],"attack",enemy.pos,enemy.id)
	game.sim.command([breaker.id],"attack",house.pos,house.id)
	game.selected = [ranged.id,lancer.id,breaker.id]
	await tick(4,1.0/30.0,true,true)
	await capture("11-ranged-hit-and-melee")
	var snapshot := JSON.stringify(game.sim.save_dict())
	# Rendering 300 frames of the same event never applies another point of damage.
	for i in range(300): game.world.sync(game.sim.entities,game.selected,game.sim,0.001)
	check(JSON.stringify(game.sim.save_dict()) == snapshot,"300次视觉推进不修改任何规则/伤害状态")
	await tick(45,1.0/30.0,true,true)
	await capture("12-prepare-and-strike")
	await tick(45,1.0/30.0,true,true)
	await capture("13-collapse-stages")
	await tick(60,1.0/30.0,true,true)
	await capture("14-fallen-and-rubble")
	check(int(evidence.events.get("attack",0)) > 0 and evidence.events.get("hit",0) == evidence.events.get("attack",0),"攻击与受击一对一对应原始伤害事件")
	check(int(evidence.events.get("death",0)) > 0 and int(evidence.events.get("collapse",0)) > 0,"单位死亡与建筑倒塌独立实际事件")
	check(not game.sim._by_id.has(house.id) and not game.world.visuals.has(house.id),"建筑倒塌时规则实体和选择对象立即退出")
	# Pause everything, including water, bow, scaffold, smoke, interpolation and remains.
	var transforms := visual_state()
	for i in range(25): game.world.sync(game.sim.entities,game.selected,game.sim,0.0)
	check(visual_state() == transforms,"dt=0 严格冻结全体姿态/弹道/残骸/水面时间")
	await capture("15-paused")
	evidence["real_combat_events"] = evidence.events.duplicate(true)
	# Fog/off-camera death is rejected, even friendly deaths outside the camera.
	var admitted: int = game.world.battle_fx.admitted_deaths
	game.world.show_destroyed({"id":99999,"kind":"guard","team":1,"point":Vector2(70,10)})
	game.world.show_destroyed({"id":99998,"kind":"guard","team":0,"point":Vector2(5,75)})
	check(game.world.battle_fx.admitted_deaths == admitted,"迷雾及镜头外死亡不产生可见残骸")
	# Explicit mass-death fixture: no effect should keep an entity selectable/blocking.
	fixture()
	game.sim._spawn("worker",0,Vector2(30,55))
	var victims: Array = []
	for i in range(40): victims.append(game.sim._spawn("guard",1,Vector2(28+float(i%8)*0.5,53+float(i/8)*0.5)))
	camera(Vector2(30,55),17.0)
	refresh()
	for e in victims: e.hp = 0.0
	game.sim._cleanup_dead()
	game._consume_events()
	check(game.sim.entities.size() == 1 and game.world.battle_fx.stats().remains == 16,"40个同时死亡，规则立即移除、残骸不超过16")
	for i in range(120): game.world.show_combat({"id":-1,"target":-1,"kind":"ranger","team":0,"point":Vector2(30,55),"from":Vector2(29,55)})
	check(game.world.battle_fx.stats().effects <= 64 and game.world.battle_fx.stats().effect_nodes <= 64,"120次弹道爆发的特效节点和活跃数均限制64")
	var allocations: Dictionary = game.world.battle_fx.stats()
	await tick(170,1.0/30.0,false)
	check(game.world.battle_fx.stats().effects == 0 and game.world.battle_fx.stats().remains == 0,"残骸与特效到期全部回收")
	for i in range(16): game.world.show_destroyed({"id":9900+i,"kind":"guard","team":1,"point":Vector2(30,55)})
	check(game.world.battle_fx.stats().remains_slots == allocations.remains_slots,"同兵种再次死亡复用残骸池")
	# Lost vision retires active remains permanently.
	game.sim.entities[0].pos = Vector2(5,75)
	game.sim._update_fog()
	game.world.sync(game.sim.entities,[],game.sim,0.0)
	check(game.world.battle_fx.stats().remains == 0,"失去视野立即隐藏并退休旧残骸")
	await capture("16-fog-hidden")
	# Old save has no visual fields: migration remains rules-only and recreates clean rigs.
	var valid_old_save := Sim.new()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(valid_old_save.save_dict()))
	game.world.reset_entities()
	check(game.sim.load_dict(saved),"旧结构存档无需美术字段即可加载")
	game.world.sync(game.sim.entities,[],game.sim,0.0)
	check(game.world.battle_fx.stats().effects == 0 and game.world.battle_fx.stats().remains == 0,"读档重建无旧弹道和残骸")
	game._new_game()
	game.set_process(false)
	check(game.world.battle_fx.stats().effects == 0 and game.world.battle_fx.stats().remains == 0,"重开清除所有过渡对象")
	# Native projected health checks across zoom/window sizes use existing assertions.
	var health = load("res://tests/health_bars.gd").new()
	failures += await health.run(game)
	game.set_process(false)
	evidence["poses"] = poses
	evidence["pool"] = game.world.battle_fx.stats()
	evidence["movie_frames"] = movie_frames
	evidence["checks"] = checks
	evidence["failures"] = failures
	var report := FileAccess.open(EVIDENCE_DIR+"/art-evidence.json",FileAccess.WRITE)
	report.store_string(JSON.stringify(evidence,"\t"))
	print("ART_SUMMARY checks=",checks," failures=",failures," frames=",movie_frames)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)

func visual_state() -> String:
	var data: Array = [game.world._time,game.world._water.material_override.get_shader_parameter("visual_time")]
	collect_transforms(game.world,data)
	for e in game.world.battle_fx.effects: data.append(e.get("age",0.0))
	for e in game.world.battle_fx.remains: data.append(e.get("age",0.0))
	return str(data)

func collect_transforms(node: Node, values: Array) -> void:
	if node is Node3D: values.append(node.transform)
	for child in node.get_children(): collect_transforms(child,values)
