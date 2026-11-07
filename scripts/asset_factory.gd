extends RefCounted
## Original mesh kit. Coordinates: metres, +Y up, -Z forward, origin at ground centre.
## Assets are composed from shared meshes; no external art or runtime Houdini dependency.
const Batcher = preload("res://scripts/art_batcher.gd")
var batcher = Batcher.new()
var _materials: Dictionary = {}
var _meshes: Dictionary = {}

func material(color: Color, metallic: float = 0.0, roughness: float = 0.8, emissive: float = 0.0) -> StandardMaterial3D:
	var key := str(color) + str(metallic) + str(roughness) + str(emissive)
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	if color.a < 0.99:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emissive > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emissive
	_materials[key] = mat
	return mat

func palette(team: int) -> Dictionary:
	if team == 1:
		return {"stone": Color("b89a80"), "light": Color("e4c4a4"), "roof": Color("963f36"), "roof_light": Color("dc7653"), "metal": Color("493f45"), "cloth": Color("f1ad64"), "glow": Color("ffad5b"), "wood": Color("674842")}
	return {"stone": Color("d6cfac"), "light": Color("f4e4ba"), "roof": Color("207873"), "roof_light": Color("58b2a0"), "metal": Color("bf8b56"), "cloth": Color("daf0c9"), "glow": Color("7cf6d6"), "wood": Color("665744")}

func piece(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO, metallic: float = 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material(color, metallic)
	node.position = pos
	node.rotation_degrees = rot
	parent.add_child(node)
	return node

func box(size: Vector3) -> BoxMesh:
	var key := "b" + str(size)
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]

func cylinder(bottom: float, top: float, height: float, sides: int = 12) -> CylinderMesh:
	var key := "c" + str(bottom) + ":" + str(top) + ":" + str(height) + ":" + str(sides)
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.bottom_radius = bottom
		m.top_radius = top
		m.height = height
		m.radial_segments = sides
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]

func sphere(radius: float, height: float = -1.0) -> SphereMesh:
	if height < 0.0:
		height = radius * 2.0
	var key := "s" + str(radius) + ":" + str(height)
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = height
		m.radial_segments = 10
		m.rings = 5
		_meshes[key] = m
	return _meshes[key]

func ring(radius: float, thickness: float = 0.065) -> TorusMesh:
	var key := "r" + str(radius) + ":" + str(thickness)
	if not _meshes.has(key):
		var m := TorusMesh.new()
		m.inner_radius = radius - thickness
		m.outer_radius = radius + thickness
		m.rings = 36
		m.ring_segments = 6
		_meshes[key] = m
	return _meshes[key]

func height_for(kind: String) -> float:
	match kind:
		"heart", "hq": return 5.4
		"barracks": return 3.6
		"tower": return 5.2
		"house": return 3.0
		"tree": return 3.6
		"ore", "crystal": return 1.7
		"berry", "berries", "food": return 1.1
		"rider": return 3.0
		"lancer": return 2.2
		"breaker": return 1.8
	return 1.6

func radius_for(kind: String) -> float:
	match kind:
		"heart", "hq": return 2.9
		"barracks": return 2.5
		"house": return 1.8
		"rider": return 0.85
		"tower": return 1.45
		"tree": return 0.95
		"ore", "crystal": return 1.0
		"berry", "berries", "food": return 0.9
	return 0.56

func make(kind: String, team: int, seed_id: int = 0, lod: int = 0) -> Node3D:
	var root := Node3D.new()
	root.name = kind + "_" + str(seed_id)
	# Optional authored/Houdini asset replaces the built-in kit without touching simulation.
	var asset_team := maxi(team,0)
	var path := "res://assets/generated/%s_team%d_lod0.glb" % [kind,asset_team]
	if ResourceLoader.exists(path):
		var packed = load(path)
		if packed is PackedScene:
			var imported = packed.instantiate()
			if imported is Node3D:
				root.add_child(imported)
				return root
			imported.queue_free()
	var p := palette(team)
	match kind:
		"heart", "hq": _heart(root, p, team)
		"house": _house(root, p, team)
		"barracks": _barracks(root, p, team)
		"tower": _tower(root, p, team)
		"tree": _tree(root, seed_id)
		"ore", "crystal": _ore(root, seed_id)
		"berry", "berries", "food": _berry(root, seed_id)
		_: _unit(root, kind, p, team)
	if kind in ["heart", "hq", "house", "barracks", "tower"]:
		_building_tiers(root, kind, p)
	for meta_key in ["banner", "crystal", "cape"]:
		if root.has_meta(meta_key): root.get_meta(meta_key).set_meta("art_animated_mesh", true)
	var key := kind + str(team)
	if kind in ["tree", "ore", "berry", "crystal", "food", "berries"]: key += ":" + str(seed_id)
	batcher.bake(root, key)
	set_lod(root, lod)
	return root

func set_lod(root: Node3D, level: int) -> void:
	batcher.set_lod(root, level)
	root.set_meta("lod", level)

func _building_tiers(root: Node3D, kind: String, p: Dictionary) -> void:
	var r := radius_for(kind)
	# Bold continuous cornice/portal details read at RTS distance, then bake together.
	piece(root, cylinder(r*0.91,r*0.96,0.16,12),p.metal,Vector3(0,0.52,0),Vector3.ZERO,0.5)
	match kind:
		"heart", "hq":
			# Stepped lantern drum and brass roof collar, read as a civic landmark.
			piece(root,cylinder(1.15,1.09,0.22,12),p.metal,Vector3(0,3.30,0),Vector3.ZERO,0.5)
		"house":
			# Front sea-cloth awning provides a lower secondary roof silhouette.
			piece(root,box(Vector3(1.03,0.10,0.70)),p.roof_light,Vector3(0,1.48,1.30),Vector3(-13,0,0))
		"barracks":
			# Broad sail-roof ridge cap and open entrance canopy.
			piece(root,cylinder(0.12,0.12,3.40,6),p.metal,Vector3(0,3.0,0),Vector3(90,0,0),0.5)
			piece(root,box(Vector3(1.45,0.13,0.63)),p.roof_light,Vector3(0,1.7,1.48),Vector3(-12,0,0))
		"tower":
			# Ring parapet and massive lower buttresses distinguish the watchtower.
			piece(root,ring(1.06,0.13),p.light,Vector3(0,3.84,0))
			for side in [-1.0,1.0]:
				piece(root,cylinder(0.34,0.14,1.45,5),p.stone,Vector3(side*0.7,0.91,0))
	var children := root.get_children()
	var tiers: Array[Node3D] = []
	for title in ["Foundation","Walls","Roof"]:
		tiers.append(_joint(root,title,Vector3.ZERO))
	var roof_at: float = {"heart":2.1,"hq":2.1,"house":1.7,"barracks":1.9,"tower":3.5}.get(kind,2.0)
	for child in children:
		if child is Node3D:
			var level := 0 if child.position.y < 0.55 else (2 if child.position.y >= roof_at else 1)
			root.remove_child(child)
			tiers[level].add_child(child)
	root.set_meta("tiers",tiers)

func _base(root: Node3D, p: Dictionary, radius: float, sides: int = 8) -> void:
	piece(root, cylinder(radius + 0.22, radius + 0.22, 0.18, sides), p.metal.darkened(0.2), Vector3(0, 0.09, 0))
	piece(root, cylinder(radius + 0.13, radius, 0.2, sides), p.light, Vector3(0, 0.25, 0))
	piece(root, cylinder(radius, radius, 0.09, sides), p.stone, Vector3(0, 0.395, 0))

func _crystal(root: Node3D, position: Vector3, radius: float, h: float, color: Color) -> MeshInstance3D:
	var node := piece(root, cylinder(radius, 0.02, h, 5), color, position, Vector3(0, 20, -8), 0.22)
	node.material_override = material(color, 0.3, 0.28, 0.25)
	return node

func _window(root: Node3D, p: Dictionary, pos: Vector3, turn: float = 0.0, width: float = 0.34) -> void:
	var frame := Node3D.new()
	root.add_child(frame)
	frame.position = pos
	frame.rotation.y = turn
	piece(frame, box(Vector3(width + 0.12, 0.65, 0.10)), p.metal, Vector3.ZERO)
	piece(frame, box(Vector3(width, 0.51, 0.115)), Color("243f3b"), Vector3.ZERO)
	piece(frame, box(Vector3(0.045, 0.51, 0.12)), p.glow.darkened(0.15), Vector3.ZERO)
	piece(frame, box(Vector3(width + 0.20, 0.07, 0.21)), p.light, Vector3(0, -0.34, 0))

func _flag(root: Node3D, p: Dictionary, pos: Vector3, team: int) -> void:
	piece(root, cylinder(0.04, 0.03, 1.45, 6), p.metal, pos + Vector3(0, 0.725, 0), Vector3.ZERO, 0.5)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts: Array[Vector3]
	if team == 1:
		verts = [Vector3(0,0,0), Vector3(0.7,-0.22,0), Vector3(0,-0.48,0)]
	else:
		verts = [Vector3(0,0,0), Vector3(0.62,-0.06,0), Vector3(0.5,-0.48,0), Vector3(0,0,0), Vector3(0.5,-0.48,0), Vector3(0,-0.42,0)]
	for v in verts:
		st.add_vertex(v)
	st.generate_normals()
	var flag := piece(root, st.commit(), p.cloth, pos + Vector3(0,1.38,0))
	var mat := material(p.cloth).duplicate() as StandardMaterial3D
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flag.material_override = mat
	flag.name = "Banner"
	root.set_meta("banner", flag)

func _heart(root: Node3D, p: Dictionary, team: int) -> void:
	_base(root, p, 2.65, 12)
	# Ring hall with buttresses, a copper balcony, and an open central tide lantern.
	piece(root, cylinder(2.25, 2.0, 1.6, 12), p.stone, Vector3(0,1.23,0))
	piece(root, cylinder(2.34, 2.34, 0.12, 12), p.metal, Vector3(0,2.05,0), Vector3.ZERO,0.45)
	piece(root, cylinder(2.9, 1.05, 1.15, 12 if team == 0 else 6), p.roof, Vector3(0,2.67,0))
	piece(root, cylinder(2.94, 2.8, 0.12, 12), p.roof_light, Vector3(0,2.13,0))
	# Keep the civic silhouette readable with six evenly spaced piers.  The old
	# eight-pier/every-side window treatment became noisy at normal RTS zoom.
	for i in range(6):
		var a := TAU * i / 6.0
		var v := Vector3(sin(a),0,cos(a))
		piece(root, box(Vector3(0.22,1.68,0.3)), p.light, v * 2.05 + Vector3(0,1.3,0), Vector3(0,rad_to_deg(a),0))
		if i == 1 or i == 4:
			_window(root,p,v * 2.10 + Vector3(0,1.43,0),a,0.38)
	piece(root, box(Vector3(0.98,1.28,0.18)), p.wood, Vector3(0,1.08,2.23))
	piece(root, box(Vector3(0.08,1.28,0.21)), p.metal, Vector3(0,1.08,2.23))
	for i in range(2):
		piece(root,box(Vector3(1.48,0.15,0.45)),p.light,Vector3(0,0.1+i*0.13,3.0-i*0.3))
	piece(root, cylinder(1.06,1.06,0.17,10),p.metal,Vector3(0,3.25,0),Vector3.ZERO,0.5)
	for i in range(2):
		var a := TAU * i / 2.0 + PI * 0.25
		piece(root,cylinder(0.065,0.045,1.3,6),p.light,Vector3(sin(a)*0.73,3.85,cos(a)*0.73))
	var gem := _crystal(root,Vector3(0,3.98,0),0.43,1.25,p.glow)
	root.set_meta("crystal",gem)
	piece(root,cylinder(1.18,0.12,0.68,6 if team == 1 else 10),p.roof_light,Vector3(0,4.72,0))
	piece(root,sphere(0.11),p.metal,Vector3(0,5.1,0),Vector3.ZERO,0.5)
	_flag(root,p,Vector3(-2.1,1.95,0.1),team)

func _house(root: Node3D, p: Dictionary, team: int) -> void:
	_base(root,p,1.55)
	piece(root,cylinder(1.26,1.13,1.28,8),p.stone,Vector3(0,1.05,0))
	piece(root,cylinder(1.53,1.50,0.13,8),p.metal,Vector3(0,1.74,0),Vector3.ZERO,0.35)
	piece(root,cylinder(1.63,0.18,1.13,8 if team == 0 else 4),p.roof,Vector3(0,2.35,0),Vector3(0,22.5,0))
	piece(root,cylinder(0.28,0.18,0.16,8),p.roof_light,Vector3(0,2.92,0))
	piece(root,box(Vector3(0.53,0.94,0.14)),p.wood,Vector3(0,0.89,1.2))
	for a in [-PI/2,PI/2]:
		_window(root,p,Vector3(sin(a)*1.2,1.18,cos(a)*1.2),a,0.27)
	for a in [PI/4,PI*1.25]:
		piece(root,box(Vector3(0.13,1.3,0.2)),p.light,Vector3(sin(a)*1.2,1.05,cos(a)*1.2),Vector3(0,rad_to_deg(a),0))
	# A single clean awning is enough to identify the doorway; remove the
	# offset chimney and hanging pot that frequently intersected the roof.
	piece(root,box(Vector3(0.8,0.12,0.44)),p.light,Vector3(0,0.12,1.61))

func _barracks(root: Node3D, p: Dictionary, team: int) -> void:
	_base(root,p,2.25)
	piece(root,box(Vector3(3.75,1.48,2.62)),p.stone,Vector3(0,1.15,0))
	piece(root,box(Vector3(3.95,0.13,2.8)),p.metal,Vector3(0,1.93,0),Vector3.ZERO,0.4)
	# Two broad sail roofs give the training hall an unmistakable silhouette.
	for side in [-1.0,1.0]:
		piece(root,box(Vector3(2.28,0.16,3.17)),p.roof,Vector3(side*0.99,2.4,0),Vector3(0,0,-side*27))
		piece(root,box(Vector3(2.34,0.06,0.08)),p.roof_light,Vector3(side*0.99,2.5,1.58),Vector3(0,0,-side*27))
		piece(root,box(Vector3(0.23,1.72,0.24)),p.light,Vector3(side*1.79,1.3,1.29))
		_window(root,p,Vector3(side*1.07,1.28,1.34),0,0.37)
	piece(root,box(Vector3(0.12,0.12,3.3)),p.metal,Vector3(0,2.98,0),Vector3.ZERO,0.4)
	piece(root,box(Vector3(0.93,1.36,0.16)),p.wood,Vector3(0,1.07,1.35))
	piece(root,box(Vector3(1.25,0.12,0.5)),p.light,Vector3(0,0.1,1.9))
	# One straight training spear reads better than a cluster of thin props.
	piece(root,cylinder(0.045,0.035,1.7,5),p.wood,Vector3(-2.13,1.16,0),Vector3(0,0,-8))
	piece(root,cylinder(0.14,0,0.38,4),p.metal,Vector3(-2.25,2.13,0),Vector3.ZERO,0.5)
	_flag(root,p,Vector3(1.8,2.25,-1.1),team)

func _tower(root: Node3D, p: Dictionary, team: int) -> void:
	_base(root,p,1.3)
	piece(root,cylinder(0.91,0.65,3.17,8),p.stone,Vector3(0,1.97,0))
	for i in range(4):
		var a := TAU*i/4.0
		piece(root,box(Vector3(0.14,3.2,0.18)),p.light,Vector3(sin(a)*0.77,1.97,cos(a)*0.77),Vector3(0,rad_to_deg(a),0))
	_window(root,p,Vector3(0,2.65,0.76),0,0.2)
	piece(root,cylinder(1.25,1.25,0.20,8),p.metal,Vector3(0,3.65,0),Vector3.ZERO,0.5)
	for i in range(4):
		var a := TAU*i/4.0
		piece(root,box(Vector3(0.3,0.43,0.3)),p.light,Vector3(sin(a),3.93,cos(a)))
	piece(root,cylinder(0.085,0.055,1.1,6),p.wood,Vector3(0,4.3,0))
	piece(root,box(Vector3(1.6,0.11,0.13)),p.wood,Vector3(0,4.37,0))
	piece(root,cylinder(0.95,0.1,0.6,6 if team == 1 else 8),p.roof,Vector3(0,4.83,0))
	_crystal(root,Vector3(0,5.28,0),0.12,0.29,p.glow)

func _joint(parent: Node3D, title: String, pos: Vector3) -> Node3D:
	var joint := Node3D.new()
	joint.name = title
	joint.set_meta("art_pivot", true)
	joint.position = pos
	parent.add_child(joint)
	return joint

func _unit(root: Node3D, kind: String, p: Dictionary, team: int) -> void:
	if kind == "breaker":
		_breaker(root,p,team)
		return
	var worker := kind == "worker"
	var ranger := kind == "ranger"
	var mounted := kind == "rider"
	if mounted:
		_mount(root, p)
	var body := _joint(root,"Body",Vector3(0,0.86 if mounted else 0.0,0))
	root.set_meta("body",body)
	root.set_meta("rest_height",body.position.y)
	var skin := Color("d5ab88") if team == 0 else Color("be906e")
	# Hips and shoulders are real pivots: boots, hands and equipment follow limbs.
	for side in [-1.0,1.0]:
		# Mounted legs stop above the saddle; the shorter, aligned lower rig
		# prevents boots from passing through the antelope torso during gait.
		var leg_y := 0.75 if mounted else 0.60
		var leg_h := 0.20 if mounted else 0.27
		var leg_center := -0.10 if mounted else -0.14
		var shin_offset := -0.20 if mounted else -0.27
		var shin_h := 0.16 if mounted else 0.22
		var shin_center := -0.08 if mounted else -0.11
		var boot_center := -0.14 if mounted else -0.20
		var boot_h := 0.11 if mounted else 0.13
		var sole_center := -0.20 if mounted else -0.27
		var leg := _joint(body,"LegL" if side < 0 else "LegR",Vector3(side*0.14,leg_y,0))
		piece(leg,cylinder(0.09,0.115,leg_h,8),p.wood,Vector3(0,leg_center,0))
		var shin := _joint(leg,"Shin",Vector3(0,shin_offset,0))
		piece(shin,cylinder(0.08,0.10,shin_h,8),p.roof if not worker else p.wood,Vector3(0,shin_center,0))
		piece(shin,box(Vector3(0.19,boot_h,0.32)),Color("354342"),Vector3(0,boot_center,-0.06))
		piece(shin,box(Vector3(0.17,0.045,0.27)),p.metal.darkened(0.3),Vector3(0,sole_center,-0.07))
		if mounted: leg.rotation.z = side*0.28
		var arm := _joint(body,"ArmL" if side < 0 else "ArmR",Vector3(side*(0.33 if kind == "guard" else 0.28),1.10,0))
		piece(arm,cylinder(0.10,0.13,0.27,8),p.cloth if worker else p.roof_light,Vector3(0,-0.13,0))
		piece(arm,sphere(0.13,0.13),p.metal if not worker else p.roof,Vector3(0,-0.015,0),Vector3.ZERO,0.25)
		var elbow := _joint(arm,"Elbow",Vector3(0,-0.27,0))
		piece(elbow,cylinder(0.065,0.09,0.22,8),p.wood if ranger else skin,Vector3(0,-0.1,-0.025))
		piece(elbow,sphere(0.09,0.15),skin,Vector3(0,-0.22,-0.04))
		piece(elbow,cylinder(0.083,0.083,0.07,8),p.metal,Vector3(0,-0.13,-0.025),Vector3.ZERO,0.3)
	piece(body,cylinder(0.23,0.28 if worker else 0.32,0.58,10),p.cloth if worker else p.roof,Vector3(0,0.86,0))
	piece(body,cylinder(0.28,0.28,0.08,10),p.wood,Vector3(0,0.62,0))
	piece(body,box(Vector3(0.13,0.11,0.065)),p.metal,Vector3(0,0.63,-0.27),Vector3.ZERO,0.45)
	piece(body,box(Vector3(0.075,0.47,0.06)),p.wood,Vector3(-0.09,0.88,-0.23),Vector3(0,0,-25))
	piece(body,box(Vector3(0.10,0.17,0.11)),p.metal if not worker else p.wood,Vector3(0.23,0.64,0.04),Vector3(0,0,-8))
	var head := _joint(body,"Head",Vector3(0,1.38,0))
	piece(head,sphere(0.20,0.34),skin,Vector3.ZERO)
	piece(head,box(Vector3(0.065,0.065,0.07)),skin.lightened(0.08),Vector3(0,-0.015,-0.19))
	for side in [-1.0,1.0]:
		piece(head,sphere(0.045,0.075),skin,Vector3(side*0.19,-0.02,0))
		piece(head,box(Vector3(0.04,0.026,0.018)),Color("243a37"),Vector3(side*0.077,0.038,-0.185))
	piece(head,box(Vector3(0.085,0.018,0.015)),Color("925f4d"),Vector3(0,-0.095,-0.18))
	var hand_r: Node3D = body.get_node("ArmR/Elbow")
	var hand_l: Node3D = body.get_node("ArmL/Elbow")
	if worker:
		piece(head,cylinder(0.34,0.32,0.065,12),p.roof,Vector3(0,0.15,0))
		piece(head,cylinder(0.22,0.14,0.21,10),p.roof_light,Vector3(0,0.27,0))
		# Keep one clean hat rim; the extra metal band read as a floating ring.
		piece(body,cylinder(0.23,0.27,0.46,8),p.wood,Vector3(0,0.91,0.29))
		piece(body,box(Vector3(0.07,0.44,0.255)),p.metal,Vector3(0,0.91,0.24))
		var cargo := _joint(body,"Cargo",Vector3(0,1.20,0.24))
		piece(cargo,sphere(0.17,0.23),p.cloth,Vector3.ZERO)
		root.set_meta("cargo",cargo)
		piece(hand_r,cylinder(0.032,0.032,0.67,8),p.wood,Vector3(0,-0.05,-0.08))
		piece(hand_r,box(Vector3(0.56,0.12,0.16)),p.metal,Vector3(0,0.26,-0.08),Vector3(0,0,9),0.5)
	elif ranger:
		piece(head,cylinder(0.25,0.06,0.33,8),p.roof,Vector3(0,0.19,0.035),Vector3(12,0,0))
		# A single flat cape panel is easier to read and stays behind the torso
		# while the shoulder rig animates.
		var cape := piece(body,box(Vector3(0.44,0.56,0.08)),p.roof_light,Vector3(0,0.84,0.25),Vector3(10,0,0))
		root.set_meta("cape",cape)
		piece(body,cylinder(0.11,0.11,0.52,8),p.wood,Vector3(0.21,0.95,0.23),Vector3(0,0,-12))
		for i in range(2):
			piece(body,cylinder(0.012,0.012,0.32,5),p.light,Vector3(0.18+i*0.045,1.29,0.23))
			piece(body,box(Vector3(0.045,0.10,0.02)),p.cloth,Vector3(0.18+i*0.045,1.43,0.23))
		# Open bow, string and nocked arrow instead of a circular ring. Five
		# segments keep the bow angular without producing a noisy silhouette.
		for i in range(5):
			var y := -0.33 + i*0.165
			var bend := 0.23 * (1.0-pow((y+0.05)/0.40,2.0))
			piece(hand_l,cylinder(0.04,0.03,0.14,6),p.wood,Vector3(0,-0.2+y,-0.16-bend),Vector3(rad_to_deg(-(y+0.05)*0.9),0,0))
		var string_pivot := _joint(hand_l,"BowString",Vector3(0,-0.24,-0.10))
		for side in [-1.0,1.0]:
			var string := piece(string_pivot,cylinder(0.011,0.011,0.39,5),p.cloth,Vector3(0,side*0.195,0))
			string.name = "Upper" if side > 0 else "Lower"
			string.set_meta("art_animated_mesh",true)
		root.set_meta("bow_string",string_pivot)
		var arrow := _joint(hand_l,"NockedArrow",Vector3(0,-0.24,-0.24))
		piece(arrow,box(Vector3(0.027,0.027,0.78)),p.light,Vector3.ZERO)
		root.set_meta("nocked_arrow",arrow)
	else:
		piece(head,sphere(0.215,0.27),p.metal,Vector3(0,0.07,0.015),Vector3.ZERO,0.5)
		piece(head,box(Vector3(0.28,0.065,0.07)),p.roof,Vector3(0,0.12,-0.185))
		piece(head,box(Vector3(0.07,0.18,0.22)),p.roof_light,Vector3(0,0.25,0.03))
		# One centred crest gives a clear class marker while leaving the helmet
		# contour clean and preventing side plates from clipping shoulders.
		piece(body,box(Vector3(0.28,0.27,0.075)),p.metal,Vector3(0,0.93,-0.235),Vector3.ZERO,0.45)
		var spear_length := 2.18 if kind == "lancer" else 1.65
		var weapon := _joint(hand_r,"Weapon",Vector3.ZERO)
		root.set_meta("weapon",weapon)
		if kind == "guard":
			# Broad leaf sword + tall kite shield, not a shortened spear.
			piece(weapon,cylinder(0.055,0.055,0.25,6),p.wood,Vector3(0,-0.12,-0.1))
			piece(weapon,box(Vector3(0.30,0.065,0.10)),p.metal,Vector3(0,0.04,-0.1),Vector3.ZERO,0.5)
			piece(weapon,cylinder(0.12,0.015,0.74,4),p.light,Vector3(0,0.44,-0.1),Vector3(0,45,0),0.5)
			var shield := piece(hand_l,cylinder(0.37,0.37,0.12,5),p.metal,Vector3(0,-0.14,-0.16),Vector3(90,0,0),0.5)
			shield.scale.z = 1.35
			var face := piece(hand_l,cylinder(0.31,0.31,0.14,5),p.roof,Vector3(0,-0.14,-0.20),Vector3(90,0,0))
			face.scale.z = 1.35
			piece(hand_l,box(Vector3(0.055,0.66,0.05)),p.light,Vector3(0,-0.16,-0.29))
		else:
			piece(weapon,cylinder(0.04,0.032,spear_length,8),p.wood,Vector3(0,0.24,-0.10))
			piece(weapon,cylinder(0.115,0.0,0.40,4),p.light,Vector3(0,0.24+spear_length*0.5,-0.1),Vector3.ZERO,0.5)
			if mounted:
				piece(body,box(Vector3(0.74,0.12,0.52)),p.roof_light,Vector3(0,0.49,0.13))
			else:
				piece(head,cylinder(0.19,0.01,0.3,6),p.metal,Vector3(0,0.26,0),Vector3.ZERO,0.5)

	if team == 1:
		piece(head,box(Vector3(0.43,0.085,0.10)),p.cloth,Vector3(0,0.25,0),Vector3(0,0,10))

func _mount(root: Node3D, p: Dictionary) -> void:
	# Original tide-antelope cavalry silhouette with swept horns and a glazed saddle.
	var mount := _joint(root,"Mount",Vector3.ZERO)
	root.set_meta("mount",mount)
	var torso := piece(mount,sphere(0.36,0.62),p.wood.lightened(0.22),Vector3(0,0.85,0))
	torso.scale.z = 1.75
	piece(mount,box(Vector3(0.55,0.16,0.7)),p.roof,Vector3(0,1.12,0.02))
	piece(mount,box(Vector3(0.61,0.07,0.74)),p.metal,Vector3(0,1.04,0.02))
	for side in [-1.0,1.0]:
		for end in [-1.0,1.0]:
			var leg := _joint(mount,"Leg%d" % (int(side>0)*2+int(end>0)),Vector3(side*0.25,0.85,end*0.42))
			piece(leg,cylinder(0.065,0.105,0.40,8),p.wood.lightened(0.1),Vector3(0,-0.2,0))
			var knee := _joint(leg,"Knee",Vector3(0,-0.4,0))
			piece(knee,cylinder(0.05,0.065,0.32,8),p.light.darkened(0.2),Vector3(0,-0.15,0))
			piece(knee,box(Vector3(0.17,0.12,0.24)),Color("344642"),Vector3(0,-0.35,-0.03))
	piece(mount,cylinder(0.18,0.14,0.75,10),p.wood.lightened(0.22),Vector3(0,1.17,-0.54),Vector3(-24,0,0))
	var head := piece(mount,sphere(0.21,0.40),p.light.darkened(0.1),Vector3(0,1.56,-0.72),Vector3(50,0,0))
	piece(mount,box(Vector3(0.29,0.20,0.30)),p.wood,Vector3(0,1.45,-0.91))
	for side in [-1.0,1.0]:
		piece(mount,cylinder(0.07,0.015,0.48,6),p.metal,Vector3(side*0.17,1.88,-0.57),Vector3(24,0,-side*17))
		# Reins stop at the muzzle; keeping them short avoids cutting through
		# the rider's legs when the mount animates.
		piece(mount,box(Vector3(0.025,0.035,0.42)),p.wood.darkened(0.2),Vector3(side*0.19,1.43,-0.53),Vector3(-15,0,0))
	piece(mount,cylinder(0.055,0.025,0.45,7),p.wood,Vector3(0,0.82,0.75),Vector3(-50,0,0))

func _breaker(root: Node3D, p: Dictionary, team: int) -> void:
	# A four-legged tide construct, visibly distinct from all human infantry.
	var body := _joint(root,"Body",Vector3.ZERO)
	root.set_meta("body",body)
	var core := piece(body,sphere(0.47,0.71),p.wood,Vector3(0,0.58,0))
	core.scale.z = 1.5
	var shell := piece(body,cylinder(0.63,0.40,0.47,6 if team == 0 else 5),p.roof,Vector3(0,0.98,0),Vector3(0,30,0))
	shell.scale.z = 1.35
	var rim := piece(body,cylinder(0.64,0.62,0.1,6 if team == 0 else 5),p.metal,Vector3(0,0.74,0),Vector3(0,30,0),0.45)
	rim.scale.z = 1.35
	for side in [-1.0,1.0]:
		for end in [-1.0,1.0]:
			var leg := _joint(body,"BeastLeg%d" % (int(side>0)*2+int(end>0)),Vector3(side*0.48,0.57,end*0.48))
			piece(leg,cylinder(0.19,0.15,0.44,6),p.stone,Vector3(0,-0.22,0),Vector3(0,0,side*8))
			piece(leg,box(Vector3(0.30,0.15,0.40)),p.metal,Vector3(side*0.03,-0.47,-0.04),Vector3.ZERO,0.4)
	var ram := _joint(body,"Ram",Vector3(0,0.63,-0.62))
	piece(ram,cylinder(0.34,0.30,0.62,6),p.stone,Vector3(0,0,-0.18),Vector3(90,0,0))
	piece(ram,box(Vector3(0.79,0.36,0.25)),p.metal,Vector3(0,-0.05,-0.54),Vector3.ZERO,0.5)
	piece(ram,box(Vector3(0.53,0.13,0.28)),p.light,Vector3(0,-0.07,-0.60))
	# One central crystal is enough to identify the construct and cannot
	# intersect the ram or the shoulder shell during recoil.
	_crystal(body,Vector3(0,1.40,0),0.15,0.54,p.glow)
	piece(body,cylinder(0.11,0.055,0.41,6),p.metal,Vector3(0,0.57,0.83),Vector3(63,0,0),0.4)

func _tree(root: Node3D, seed_id: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_id * 4391 + 928
	var h := rng.randf_range(2.6,3.7)
	piece(root,cylinder(0.22,0.105,h*0.68,7),Color("73664e"),Vector3(0,h*0.34,0))
	# Two stable boughs and two crown lobes keep the resource silhouette clean
	# while preserving the hand-authored low-poly look.
	for i in range(2):
		var a := TAU*i/2.0 + float(seed_id)
		piece(root,cylinder(0.09,0.035,1.0,5),Color("807154"),Vector3(sin(a)*0.27,h*0.6,cos(a)*0.27),Vector3(25*cos(a),0,-25*sin(a)))
	var crown := piece(root,sphere(1.07,h*0.60),Color("538875"),Vector3(0,h*0.79,0))
	crown.rotation.y = seed_id
	piece(root,sphere(0.77,h*0.45),Color("77a281"),Vector3(-0.28,h*0.96,-0.20))

func _ore(root: Node3D, seed_id: int) -> void:
	piece(root,sphere(0.78,0.51),Color("798e8d"),Vector3(0,0.23,0))
	for i in range(3):
		var a := TAU*i/3.0 + float(seed_id)
		var h := 0.82 + float((i+seed_id)%2)*0.24
		_crystal(root,Vector3(sin(a)*0.48,h*0.49,cos(a)*0.48),0.24,h,Color("83c6b7") if i%2 == 0 else Color("b4e0cf"))

func _berry(root: Node3D, seed_id: int) -> void:
	for i in range(3):
		var a := TAU*i/3.0 + float(seed_id)
		piece(root,sphere(0.47,0.67),Color("6f9461") if i%2 == 0 else Color("487d65"),Vector3(sin(a)*0.33,0.43,cos(a)*0.33))
		piece(root,sphere(0.10,0.13),Color("e6a16d"),Vector3(sin(a)*0.47,0.64,cos(a)*0.48))
