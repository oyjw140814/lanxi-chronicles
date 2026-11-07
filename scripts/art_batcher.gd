extends RefCounted
## Bake rigid details per animation pivot. One shared surface per material family,
## vertex colours preserve the palette. LOD1 removes sub-30cm trim and uses one surface.
var cache: Dictionary = {}
var use_catalog := true
var catalog: Dictionary = {}

func _init() -> void:
	if FileAccess.file_exists("res://assets/art/mesh_catalog.json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/mesh_catalog.json"))
		if parsed is Dictionary: catalog = parsed

var _mats: Dictionary = {}

func bake(root: Node3D, cache_key: String) -> void:
	_bake_pivot(root, cache_key, "root")

func _bake_pivot(pivot: Node3D, key: String, path: String) -> void:
	var pieces: Array[Dictionary] = []
	_collect(pivot, Transform3D.IDENTITY, pieces, key, path)
	if pieces.is_empty(): return
	var mesh_key := key + "/" + path
	if not cache.has(mesh_key):
		if use_catalog and catalog.has(mesh_key):
			cache[mesh_key] = [load(catalog[mesh_key][0]),load(catalog[mesh_key][1])]
		else:
			cache[mesh_key] = [_combine(pieces, false), _combine(pieces, true, 0.85 if key.begins_with("heart") or key.begins_with("house") or key.begins_with("barracks") or key.begins_with("tower") else 0.30)]
	var node := MeshInstance3D.new()
	node.name = "Batched"
	node.mesh = cache[mesh_key][0]
	node.set_meta("lod_meshes", cache[mesh_key])
	pivot.add_child(node)

func _collect(parent: Node3D, local: Transform3D, pieces: Array[Dictionary], key: String, path: String) -> void:
	for child in parent.get_children():
		if not child is Node3D: continue
		if child.get_meta("art_pivot", false):
			_bake_pivot(child, key, path + "/" + str(child.name))
			continue
		if child.get_meta("art_animated_mesh", false): continue
		var xf: Transform3D = local * child.transform
		if child is MeshInstance3D and child.mesh != null:
			pieces.append({"mesh":child.mesh, "mat":child.material_override, "xf":xf})
		_collect(child, xf, pieces, key, path)
		parent.remove_child(child)
		child.free()

func _combine(pieces: Array[Dictionary], low: bool, trim: float = 0.30) -> ArrayMesh:
	var groups: Dictionary = {}
	for item in pieces:
		var mat := item.mat as StandardMaterial3D
		if mat == null: continue
		var extent: Vector3 = item.mesh.get_aabb().size * item.xf.basis.get_scale()
		if low and extent.length() < trim: continue
		var family := 0 if low else (2 if mat.emission_enabled else (1 if mat.metallic > 0.2 else 0))
		if not groups.has(family):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[family] = st
		var tool: SurfaceTool = groups[family]
		for surface in range(item.mesh.get_surface_count()):
			var a: Array = item.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for i in range(count):
				var idx := indices[i] if not indices.is_empty() else i
				tool.set_color(mat.albedo_color)
				tool.set_normal((item.xf.basis.inverse().transposed() * normals[idx]).normalized())
				tool.add_vertex(item.xf * vertices[idx])
	var mesh := ArrayMesh.new()
	for family in groups:
		var st: SurfaceTool = groups[family]
		st.index()
		st.set_material(_material(int(family)))
		st.commit(mesh)
	return mesh

func _material(family: int) -> StandardMaterial3D:
	if _mats.has(family): return _mats[family]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.88 if family == 0 else 0.38
	m.metallic = 0.0 if family == 0 else 0.48
	m.cull_mode = BaseMaterial3D.CULL_BACK
	if family == 2:
		m.emission_enabled = true
		m.emission = Color("3e806d")
		m.emission_energy_multiplier = 0.3
	_mats[family] = m
	return m

func set_lod(root: Node3D, level: int) -> void:
	for child in root.get_children():
		if child is MeshInstance3D and child.has_meta("lod_meshes"):
			child.mesh = child.get_meta("lod_meshes")[clampi(level,0,1)]
		if child is Node3D: set_lod(child, level)
