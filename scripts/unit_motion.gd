extends RefCounted
## Visual-only rig. A hit event is already authoritative; animation never applies damage.
const Data = preload("res://scripts/game_data.gd")

func strike(visual: Dictionary, event: Dictionary) -> void:
	visual.attack_age = 0.0
	visual.attack_target = int(event.get("target",-1))
	visual.attack_point = event.point
	visual.attack_time = float(event.get("time",0.0))

func update(v: Dictionary, e: Dictionary, sim, dt: float, moving: bool, clock: float) -> void:
	if dt <= 0.0: return # Includes bow strings, hit recovery and all transitional poses.
	var art: Node3D = v.art
	if not art.has_meta("body"): return
	var body: Node3D = art.get_meta("body")
	var kind := str(e.kind)
	var speed := float(Data.UNITS.get(kind,{}).get("speed",4.0))
	var stride := 2.1 if kind == "rider" else (1.8 if kind == "breaker" else 1.35)
	# Integrate actual interpolated travel; idle clock cannot make stationary feet walk.
	v.gait = float(v.get("gait",float(e.id)*1.73)) + float(v.get("travel",speed*dt if moving else 0.0))/stride*TAU
	var phase := float(v.gait)
	var weight := move_toward(float(v.get("walk_weight",0.0)),1.0 if moving else 0.0,dt*7.0)
	v.walk_weight = weight
	v.attack_age = float(v.get("attack_age",10.0)) + dt
	var age := float(v.attack_age)
	var interval := float(Data.UNITS.get(kind,{}).get("interval",1.0))
	var recovery := 1.0 - smoothstep(0.035, minf(0.40,interval*0.36), age)
	var anticipation := 0.0
	var target: Dictionary = sim.entity(int(e.get("target",-1))) if sim != null else {}
	if target.is_empty() and sim != null:
		target = sim.entity(int(v.get("attack_target",-1)))
	var facing := false
	if not target.is_empty():
		var distance: float = e.pos.distance_to(target.pos)
		var reach := float(Data.UNITS.get(kind,{}).get("range",1.5)) + float(target.radius)
		if target.team >= 0 and target.team != e.team and distance < reach + speed*0.22:
			var cooldown := float(e.get("cooldown",0.0))
			anticipation = 1.0-smoothstep(0.03,0.32,cooldown) if cooldown > 0.0 else (0.75 if moving else 0.0)
			facing = not moving or distance < reach+0.3
		if str(e.get("state","")) in ["gather","build"] and not moving:
			facing = true
		if facing and e.pos.distance_squared_to(target.pos) > 0.001:
			art.rotation.y = lerp_angle(art.rotation.y,atan2(e.pos.x-target.pos.x,e.pos.y-target.pos.y),minf(1.0,dt*16.0))
	var blend := 1.0-exp(-dt*18.0)
	var bob := absf(sin(phase))*0.05*weight + sin(clock*1.8+e.id)*0.012*(1.0-weight)
	var pitch := -0.04*weight
	var roll := sin(phase)*0.035*weight
	var left := -sin(phase)*0.34*weight + 0.06
	var right := sin(phase)*0.34*weight + 0.06
	var elbow_right := -0.12
	var arm_yaw := 0.0
	var work := not moving and str(e.get("state","")) in ["gather","build"]
	if work:
		# Gather follows the authoritative 0.7 work_timer (including technology speed).
		var cycle := float(e.get("work_timer",0.0))/0.7
		if e.state == "build": cycle = fmod(clock/0.55,1.0)
		var stroke := sin(cycle*TAU)
		right = 0.85 + stroke*0.85
		left = 0.5 if e.state == "build" else 0.24
		pitch = 0.10 + maxf(stroke,0.0)*0.10
		elbow_right = -0.45
	elif kind == "ranger":
		left = lerpf(left,1.35, maxf(anticipation,recovery))
		right = lerpf(right,0.9,maxf(anticipation,recovery))
		arm_yaw = -0.85*anticipation-0.25*recovery
		elbow_right = -1.35*anticipation-0.3*recovery-0.12
	elif kind == "lancer":
		# Long weapon is levelled forward; the whole shoulder translates along -Z.
		right = 0.20 + anticipation*0.55 + recovery*1.28
		left = 0.35 + maxf(anticipation,recovery)*0.65
		pitch = -anticipation*0.1 + recovery*0.16
	elif kind == "rider":
		left = 0.85
		right = 0.30 + anticipation*0.45 + recovery*1.05
		pitch = recovery*0.11
	elif kind == "guard":
		left = 0.55+maxf(anticipation,recovery)*0.40
		right = 0.1-anticipation*0.95+recovery*1.7
		arm_yaw = anticipation*0.5-recovery*0.65
		roll += anticipation*0.08-recovery*0.12
	elif kind == "worker" and not work:
		right += -anticipation*0.55+recovery*1.45
	var hit := float(v.get("hit_age",1.0))
	v.hit_age = hit+dt
	var recoil := (1.0-smoothstep(0.0,0.22,hit))*0.09
	body.position.y = lerpf(body.position.y,float(art.get_meta("rest_height",0.0))+bob,blend)
	body.position.z = lerpf(body.position.z,recoil-(0.18*recovery if kind == "lancer" else 0.0),blend)
	body.rotation.x = lerp_angle(body.rotation.x,pitch-recoil,blend)
	body.rotation.z = lerp_angle(body.rotation.z,roll,blend)
	var leg_l := body.get_node_or_null("LegL") as Node3D
	var leg_r := body.get_node_or_null("LegR") as Node3D
	if leg_l != null and leg_r != null:
		for leg in [leg_l,leg_r]:
			var angle := sin(phase + (PI if leg == leg_r else 0.0))*0.55*weight
			leg.rotation.x = lerp_angle(leg.rotation.x,1.0 if kind == "rider" else angle,blend)
			var shin := leg.get_node_or_null("Shin") as Node3D
			if shin != null: shin.rotation.x = -1.0 if kind == "rider" else maxf(0.0,-angle)*1.1
	var arm_l := body.get_node_or_null("ArmL") as Node3D
	var arm_r := body.get_node_or_null("ArmR") as Node3D
	if arm_l != null and arm_r != null:
		arm_l.rotation.x = lerp_angle(arm_l.rotation.x,left,blend)
		arm_r.rotation.x = lerp_angle(arm_r.rotation.x,right,blend)
		arm_r.rotation.y = lerp_angle(arm_r.rotation.y,arm_yaw,blend)
		arm_r.get_node("Elbow").rotation.x = lerp_angle(arm_r.get_node("Elbow").rotation.x,elbow_right,blend)
	if art.has_meta("weapon") and arm_r != null:
		var wrist: Node3D = art.get_meta("weapon")
		var level_weight := maxf(anticipation,recovery)
		var level_angle: float = -PI*0.5-arm_r.rotation.x-arm_r.get_node("Elbow").rotation.x
		if kind == "guard": level_angle = -2.5*recovery
		wrist.rotation.x = lerp_angle(wrist.rotation.x,level_angle*level_weight,blend)
	if kind == "ranger" and arm_l != null:
		arm_l.get_node("Elbow").rotation.x = -arm_l.rotation.x
	if art.has_meta("bow_string"):
		var bow: Node3D = art.get_meta("bow_string")
		var draw := anticipation*0.23
		for side in [-1.0,1.0]:
			var string: Node3D = bow.get_node("Upper" if side > 0 else "Lower")
			string.rotation.x = -side*atan2(draw,0.39)
			string.position.z = draw*0.5
			string.scale.y = sqrt(0.39*0.39+draw*draw)/0.39
		art.get_meta("nocked_arrow").visible = age > interval*0.45
	if art.has_meta("cape"):
		art.get_meta("cape").rotation.x = 0.2 + sin(clock*5.0+e.id)*(0.12*weight+0.025)
	if art.has_meta("cargo"): art.get_meta("cargo").visible = int(e.get("carry",0)) > 0
	if art.has_meta("mount"):
		var mount: Node3D = art.get_meta("mount")
		mount.position.y = absf(sin(phase))*0.065*weight
		for i in range(4):
			var leg: Node3D = mount.get_node("Leg%d" % i)
			var gait := sin(phase + (PI if i in [1,2] else 0.0))
			leg.rotation.x = lerp_angle(leg.rotation.x,gait*0.58*weight,blend)
			leg.get_node("Knee").rotation.x = maxf(0.0,-gait)*0.65*weight
	if kind == "breaker":
		body.rotation.x = lerp_angle(body.rotation.x,-anticipation*0.18+recovery*0.23-recoil,blend)
		var ram: Node3D = body.get_node("Ram")
		ram.position.z = lerpf(ram.position.z,-0.62+anticipation*0.15-recovery*0.28,blend)
		for i in range(4):
			body.get_node("BeastLeg%d" % i).rotation.x = sin(phase+(PI if i in [1,2] else 0.0))*0.32*weight
	v.pose_phase = "strike" if age < 0.10 else ("recover" if recovery > 0.01 else ("prepare" if anticipation > 0.05 else ("work" if work else ("walk" if moving else "idle"))))
