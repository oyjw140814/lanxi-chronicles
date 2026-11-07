extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
const World = preload("res://scripts/world_view.gd")
var checks := 0
var failures := 0
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("ART_CONTRACT ","PASS " if ok else "FAIL ",text)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var sim := Sim.new()
	sim.ai_enabled = false
	var world := World.new()
	root.add_child(world)
	world.setup()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 22.0
	root.add_child(camera)
	camera.position = Vector3(59,38,84)
	camera.look_at(Vector3(30,0,55))
	camera.current = true
	var target := sim._spawn("rider",1,Vector2(30,52.8))
	var units: Array = []
	for kind in ["lancer","rider","guard","ranger"]:
		var e := sim._spawn(kind,0,Vector2(30,55))
		e.target = target.id
		e.state = "attack"
		e.cooldown = 0.08
		units.append(e)
	sim._update_fog()
	world.sync(sim.entities,[],sim,0.0)
	for i in range(20): world.sync(sim.entities,[],sim,1.0/30.0)
	for e in units:
		var art: Node3D = world.visuals[e.id].art
		if e.kind in ["lancer","rider"]:
			var weapon: Node3D = art.get_meta("weapon")
			check(weapon.global_basis.y.normalized().dot(-art.global_basis.z.normalized()) > 0.70,"备战武器尖端朝敌方："+str(e.kind))
		elif e.kind == "ranger":
			var bow: Node3D = art.get_meta("bow_string")
			check(bow.global_basis.y.normalized().dot(Vector3.UP)>0.95,"射手抬臂时弓保持直立")
			check(absf(bow.get_node("Upper").rotation.x)>0.1,"预备动作真实拉开弓弦")
	var v: Dictionary = world.visuals[units[0].id]
	units[0].hp -= 3.0
	world.sync(sim.entities,[],sim,0.01)
	check(float(v.hit_age)<0.02,"可见目标生命下降会受击，即使未派发攻击来源")
	var last_hit := float(v.hit_age)
	var pose: Transform3D = v.art.get_meta("body").transform
	for i in range(5): world.sync(sim.entities,[],sim,0.0)
	check(float(v.hit_age)==last_hit and v.art.get_meta("body").transform == pose,"受击恢复在暂停时冻结")
	var snapshot := JSON.stringify(sim.save_dict())
	world.set_decoration_profile({"roads":[PackedVector2Array([Vector2(20,50),Vector2(40,60)])],"clearings":[{"point":Vector2(30,55),"radius":5.0}],"road_width":2.5})
	world.sync(sim.entities,[],sim,0.02)
	check(JSON.stringify(sim.save_dict())==snapshot,"03装饰配置不改规则/导航/资源")
	world.set_visual_detail(1,false)
	world.sync(sim.entities,[],sim,0.02)
	check(not world._decor_root.get_node("InstancedSaltgrass").visible and not world.battle_fx.secondary,"06关闭次要细节同时关闭草丛和多余碎屑")
	check(world.visuals.values().all(func(a): return int(a.art.get_meta("lod",-1))==1),"06简化模型接口作用于所有存活实体")
	world.set_visual_detail(0,true)
	world.sync(sim.entities,[],sim,0.02)
	check(world._decor_root.get_node("InstancedSaltgrass").visible,"06细节恢复可逆")
	# Exact authoritative event is the only source of a trajectory/hit; no delayed second damage.
	var e: Dictionary = units[3]
	var before: float = target.hp
	sim.events.clear()
	sim._deal_damage(e,target,12.0)
	check(sim.events.size()==1 and sim.events[0].type=="attack" and target.hp==before-12.0,"射手原始事件即时且只有一次结算")
	world.show_combat(sim.events[0])
	var effects := world.battle_fx.stats()
	check(effects.effects >= 5,"即时事件创建箭头/方向轨迹/命中碎屑")
	for i in range(12): world.sync(sim.entities,[],sim,1.0/30.0)
	check(target.hp==before-12.0,"视觉弹道完成不触发第二次伤害")
	world.reset_entities()
	check(world.battle_fx.stats().effects==0 and world.visuals.is_empty(),"运行中的轨迹及过渡在重置时清空")
	await process_frame
	world.queue_free()
	camera.queue_free()
	await process_frame
	print("ART_CONTRACT_SUMMARY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
