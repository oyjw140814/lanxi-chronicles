extends Node3D
## Bounded reusable visual objects, never registered as simulation entities or colliders.
const MAX_EFFECTS := 64
const MAX_REMAINS := 16
var factory
var effects: Array[Dictionary] = []
var remains: Array[Dictionary] = []
var secondary := true
var allocated_effects := 0
var allocated_remains := 0
var admitted_deaths := 0
var rejected_deaths := 0
var serial := 0

func setup(asset_factory) -> void: factory = asset_factory

func _visible(point: Vector2, sim, camera: Camera3D) -> bool:
	return sim != null and sim.is_visible(point,0) and camera != null and camera.is_position_in_frustum(Vector3(point.x,0.9,point.y))

func _effect(kind: String, pos: Vector3, color: Color, life: float, point: Vector2, from: Vector2) -> Dictionary:
	var slot: Dictionary = {}
	for entry in effects:
		if not entry.active:
			slot = entry
			break
	if slot.is_empty() and effects.size() < MAX_EFFECTS:
		var n := MeshInstance3D.new()
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(n)
		slot = {"node":n}
		effects.append(slot)
		allocated_effects += 1
	if slot.is_empty():
		slot = effects[0]
		for entry in effects:
			if int(entry.serial) < int(slot.serial): slot = entry
	serial += 1
	slot.merge({"active":true,"kind":kind,"age":0.0,"duration":life,"point":point,"from":from,"serial":serial,"origin":pos,"velocity":Vector3.ZERO},true)
	var node: MeshInstance3D = slot.node
	node.visible = true
	node.transform = Transform3D.IDENTITY
	node.position = pos
	node.material_override = factory.material(color,0.15,0.8)
	node.mesh = factory.sphere(0.09,0.12)
	return slot

func combat(event: Dictionary, sim, camera: Camera3D) -> void:
	var point: Vector2 = event.get("point",Vector2.INF)
	var from: Vector2 = event.get("from",Vector2.INF)
	if not point.is_finite() or not from.is_finite(): return
	if not _visible(point,sim,camera) or not sim.is_visible(from,0): return
	var kind := str(event.get("kind","guard"))
	var color := Color("cfddbc") if int(event.get("team",0)) == 0 else Color("e4aa7d")
	var start := Vector3(from.x,4.3 if kind == "tower" else (2.0 if kind == "rider" else 1.15),from.y)
	var finish := Vector3(point.x,0.9,point.y)
	var target: Dictionary = sim.entity(int(event.get("target",-1)))
	if not target.is_empty(): finish.y = minf(2.4,factory.height_for(str(target.kind))*0.55)
	if kind in ["ranger","tower"]:
		# Rules use instant hits. The arrowhead reaches the target ON that event;
		# 3 short trajectory afterimages contract toward it over 140ms. No delayed hit.
		var arrow := _effect("arrow",finish,color,0.14,point,from)
		arrow.node.mesh = factory.cylinder(0.07,0.0,0.28,4)
		_align(arrow.node,finish-start)
		for i in range(3):
			var t := 0.18+float(i)*0.23
			var pos := start.lerp(finish,t)+Vector3.UP*sin(t*PI)*0.25
			var trace := _effect("trace",pos,color,0.14,point,from)
			trace.node.mesh = factory.cylinder(0.022,0.012,0.45,5)
			trace.finish = finish
			_align(trace.node,finish-start)
	# A small contact chip burst is shared by hits, including lethal hits.
	for i in range(3 if secondary else 1):
		var chip := _effect("chip",finish,Color("d1bd95"),0.24,point,point)
		chip.velocity = Vector3(float(i-1)*1.1,1.7+float(i)*0.2,-0.6+float(i)*0.45)
		chip.node.mesh = factory.box(Vector3(0.075,0.06,0.09))
	if kind == "breaker" and secondary:
		var dust := _effect("dust",Vector3(point.x,0.18,point.y),Color("b9b394"),0.35,point,point)
		dust.node.mesh = factory.sphere(0.25,0.15)

func _align(node: Node3D, direction: Vector3) -> void:
	if direction.length_squared() < 0.001: return
	var y := direction.normalized()
	var reference := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := y.cross(reference).normalized()
	node.basis = Basis(x,y,x.cross(y).normalized())

func order(point: Vector2, attack: bool) -> void:
	var slot := _effect("order",Vector3(point.x,0.18,point.y),Color("f1aa7e") if attack else Color("c2f2d1"),0.7,point,point)
	slot.node.mesh = factory.ring(0.72,0.04)

func death(event: Dictionary, visual: Dictionary, sim, camera: Camera3D) -> void:
	var point: Vector2 = event.get("point",Vector2.INF)
	var kind := str(event.get("kind",""))
	if not point.is_finite() or not _visible(point,sim,camera) or int(event.get("team",-1)) < 0:
		rejected_deaths += 1
		return
	var team := int(event.get("team",0))
	var key := kind+str(team)
	var slot: Dictionary = {}
	# Reuse rig and nodes for repeated deaths of the same kind. At capacity replace oldest.
	for entry in remains:
		if not entry.active and entry.key == key:
			slot = entry
			break
	if slot.is_empty() and remains.size() < MAX_REMAINS:
		var root := Node3D.new()
		root.name = "VisualRemains"
		add_child(root)
		slot = {"node":root,"key":"","art":null}
		remains.append(slot)
		allocated_remains += 1
	if slot.is_empty():
		slot = remains[0]
		for entry in remains:
			if not entry.active:
				slot = entry
				break
			if int(entry.serial) < int(slot.serial): slot = entry
	if slot.key != key:
		if is_instance_valid(slot.art):
			slot.node.remove_child(slot.art)
			slot.art.free()
		slot.art = factory.make(kind,team,0,1)
		slot.node.add_child(slot.art)
		if kind in ["heart","hq","house","barracks","tower"]:
			var rubble := Node3D.new()
			rubble.name = "Rubble"
			slot.art.add_child(rubble)
			var radius: float = factory.radius_for(kind)*0.85
			for i in range(4):
				var a := float(i)*TAU/4.0
				factory.piece(rubble,factory.box(Vector3(0.45,0.30,0.33)),factory.palette(team).stone,Vector3(sin(a)*radius,0.3,cos(a)*radius),Vector3(12,rad_to_deg(a),17))
			factory.batcher.bake(rubble,"rubble/"+key)
			rubble.visible = false
			slot.art.set_meta("rubble",rubble)
		slot.key = key
	var art: Node3D = slot.art
	_reset_pose(art)
	if not visual.is_empty():
		_copy_pose(visual.art,art)
	if art.has_meta("rubble"): art.get_meta("rubble").visible = false
	art.rotation.x = 0.0
	art.rotation.z = 0.0
	var building := kind in ["heart","hq","house","barracks","tower"]
	serial += 1
	slot.merge({"active":true,"age":0.0,"point":point,"serial":serial,"building":building,"height_scale":art.scale.y,"duration":5.0 if building else 3.8,"yaw":art.rotation.y},true)
	slot.node.position = Vector3(point.x,0.1,point.y)
	slot.node.visible = true
	admitted_deaths += 1
	if building and secondary:
		for i in range(3):
			var dust := _effect("dust",Vector3(point.x+float(i-1)*0.7,0.3,point.y),Color("b9b394"),0.75,point,point)
			dust.node.mesh = factory.sphere(0.4,0.3)

func _reset_pose(node: Node3D) -> void:
	if not node.has_meta("rest_transform"): node.set_meta("rest_transform",node.transform)
	node.transform = node.get_meta("rest_transform")
	for child in node.get_children():
		if child is Node3D: _reset_pose(child)

func _copy_pose(source: Node3D, target: Node3D) -> void:
	target.transform = source.transform
	for child in target.get_children():
		if child is Node3D:
			var original := source.get_node_or_null(NodePath(str(child.name))) as Node3D
			if original != null: _copy_pose(original,child)

func update(dt: float, sim, camera: Camera3D) -> void:
	for slot in effects:
		if not slot.active: continue
		# Lost vision retires the effect permanently; revisiting cannot reveal old combat.
		if not _visible(slot.point,sim,camera) or not sim.is_visible(slot.from,0):
			_release(slot)
			continue
		if dt <= 0.0: continue
		slot.age += dt
		if slot.age >= slot.duration:
			_release(slot)
			continue
		var t: float = slot.age/slot.duration
		match slot.kind:
			"trace":
				slot.node.position = slot.origin.lerp(slot.finish,t)
				slot.node.scale = Vector3(1.0-t,1.0,1.0-t)
			"arrow": slot.node.scale = Vector3.ONE*(1.0-t*0.6)
			"order": slot.node.scale = Vector3.ONE*(0.7+t*0.6)
			"dust": slot.node.scale = Vector3.ONE*(0.8+sin(t*PI)*1.4)*(1.0-t)
			_:
				slot.node.position = slot.origin + slot.velocity*slot.age + Vector3.DOWN*3.0*slot.age*slot.age
				slot.node.scale = Vector3.ONE*(1.0-t)
	for slot in remains:
		if not slot.active: continue
		if not _visible(slot.point,sim,camera):
			_release(slot)
			continue
		if dt <= 0.0: continue
		slot.age += dt
		if slot.age >= slot.duration:
			_release(slot)
			continue
		var art: Node3D = slot.art
		var age := float(slot.age)
		if slot.building and art.has_meta("tiers"):
			var tiers: Array = art.get_meta("tiers")
			if art.has_meta("rubble"): art.get_meta("rubble").visible = age > 0.65
			var roof_fall := smoothstep(0.12,0.85,age)
			var wall_fall := smoothstep(0.50,1.40,age)
			tiers[2].rotation.z = roof_fall*0.30
			tiers[2].position.y = roof_fall*0.20
			tiers[2].scale.y = 1.0-roof_fall*0.60
			tiers[1].scale.y = 1.0-wall_fall*0.85
			tiers[1].rotation.z = -wall_fall*0.12
		else:
			var fall := smoothstep(0.0,0.65,age)
			art.rotation.z = fall*1.48
			art.position.y = fall*0.18
			slot.node.position.y = 0.1
		# Short readable remains, then sink under the terrain (no expensive alpha pass).
		if age > slot.duration-0.6:
			slot.node.position.y = 0.1-(age-(slot.duration-0.6))*2.5

func _release(slot: Dictionary) -> void:
	slot.active = false
	slot.node.visible = false

func reset() -> void:
	for slot in effects: _release(slot)
	for slot in remains: _release(slot)

func stats() -> Dictionary:
	return {"effects":effects.filter(func(e): return e.active).size(),"remains":remains.filter(func(e): return e.active).size(),"effect_nodes":allocated_effects,"remains_slots":allocated_remains,"admitted_deaths":admitted_deaths,"rejected_deaths":rejected_deaths}
