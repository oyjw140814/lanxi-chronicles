extends RefCounted
## 03 contract: visual corridors and exclusion discs only. Never touches AStar/collision.
## roads: Array[PackedVector2Array], clearings: Array[{point:Vector2,radius:float}].
var profile := {"roads":[PackedVector2Array([Vector2(18,58),Vector2(40,40),Vector2(62,22)])],"clearings":[],"road_width":3.0}
var signature := ""
var grass_transforms: Array[Transform3D] = []

func set_profile(value: Dictionary) -> void:
	profile = value.duplicate(true)
	signature = ""

func road_distance(point: Vector2) -> float:
	var distance := INF
	for road in profile.get("roads",[]):
		for i in range(road.size()-1):
			distance = minf(distance,point.distance_to(Geometry2D.get_closest_point_to_segment(point,road[i],road[i+1])))
	return distance

func refresh_grass(grass: MultiMeshInstance3D, entities: Array) -> void:
	if grass == null: return
	var discs: Array = profile.get("clearings",[]).duplicate()
	var key := str(profile)
	for e in entities:
		if int(e.team) < 0 or str(e.kind) in ["heart","hq","house","barracks","tower"]:
			discs.append({"point":e.pos,"radius":float(e.get("radius",1.0))+0.6})
			key += str(e.id)+str(e.pos)
	if key == signature: return
	signature = key
	var rng := RandomNumberGenerator.new()
	rng.seed = 19932
	grass_transforms.clear()
	for i in range(grass.multimesh.instance_count):
		var p := Vector2(rng.randf_range(3,77),rng.randf_range(3,77))
		var hidden := road_distance(p) < float(profile.get("road_width",3.0))
		for disc in discs:
			if p.distance_squared_to(disc.point) < pow(float(disc.radius),2.0):
				hidden = true
				break
		var size := 0.001 if hidden else rng.randf_range(0.55,1.0)
		var basis := Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*size)
		var transform := Transform3D(basis,Vector3(p.x,0.015,p.y))
		grass_transforms.append(transform)
		grass.multimesh.set_instance_transform(i,transform)

func road_color(point: Vector2, ground: Color) -> Color:
	var width := float(profile.get("road_width",3.0))
	return Color("b8b591").lerp(ground,smoothstep(width*0.45,width+1.5,road_distance(point)))

func apply_visibility(grass: MultiMeshInstance3D, sim) -> void:
	if grass == null: return
	for i in range(grass_transforms.size()):
		var transform := grass_transforms[i]
		if not sim.is_visible(Vector2(transform.origin.x,transform.origin.z),0):
			transform.basis = transform.basis.scaled(Vector3.ONE*0.001)
		grass.multimesh.set_instance_transform(i,transform)
