extends RefCounted
## Read-only construction and damage dressing; no rule state or collisions.
func create(factory, kind: String, parent: Node3D) -> Dictionary:
	var root := Node3D.new()
	root.name = "DamageDressing"
	parent.add_child(root)
	var cracks := Node3D.new()
	root.add_child(cracks)
	var radius: float = factory.radius_for(kind)*0.78
	var h := 2.9 if kind == "tower" else 1.45
	for side in [-1.0,1.0]:
		for i in range(3):
			factory.piece(cracks,factory.box(Vector3(0.045,0.31,0.045)),Color("4e594b"),Vector3(side*radius*0.4,h-i*0.23,radius+0.06),Vector3(0,0,side*(25 if i%2 == 0 else -35)))
	factory.batcher.bake(cracks,"damage/"+kind)
	var smoke := Node3D.new()
	root.add_child(smoke)
	for i in range(3):
		var puff: MeshInstance3D = factory.piece(smoke,factory.sphere(0.16,0.23),Color("88968a"),Vector3(radius*0.3,h+float(i)*0.4,0))
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return {"root":root,"cracks":cracks,"smoke":smoke,"height":h}

func update(v: Dictionary, e: Dictionary, clock: float, secondary: bool) -> void:
	var damage: Dictionary = v.damage
	var built := float(e.get("built",1.0))
	# An unfinished building's lower initial HP is construction, not battle damage.
	var expected := float(e.max_hp)*maxf(0.1,0.1+0.9*built)
	var fraction := float(e.hp)/maxf(1.0,expected)
	damage.root.visible = fraction < 0.72
	damage.smoke.visible = fraction < 0.36 and secondary
	if damage.smoke.visible:
		for i in range(3):
			var puff: Node3D = damage.smoke.get_child(i)
			var phase := fmod(clock*0.55+float(i)/3.0,1.0)
			puff.position.y = float(damage.height)+phase*1.1
			puff.position.x = sin(phase*2.0+float(e.id))*0.2
			puff.scale = Vector3.ONE*sin(phase*PI)*(0.8+phase)
	if v.art.has_meta("tiers"):
		var roof: Node3D = v.art.get_meta("tiers")[2]
		roof.rotation.z = 0.055 if fraction < 0.36 else 0.0
