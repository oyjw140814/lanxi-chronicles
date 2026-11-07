extends RefCounted
## Rendering-independent deterministic rules. The UI can safely hold entity IDs,
## but should refresh dictionaries after load. step() accepts real seconds.
const Data = preload("res://scripts/game_data.gd")
const WORLD_SIZE := 80.0
const FOG_SIZE := 40
const STEP := 0.1
var entities: Array[Dictionary] = []
var resources: Array[Dictionary] = []
var elapsed := 0.0
var result := ""
var tech: Array[int] = [0, 0]
var events: Array[Dictionary] = []
var stats: Dictionary = {}
var ai_enabled := true
var difficulty := "relaxed"
var seed_value := 42
var _next_id := 1
var _by_id: Dictionary = {}
var _grid := AStarGrid2D.new()
var _visible: Array = []
var _explored: Array = []
var _fog_clock := 0.0
var _ai_clock := 0.0
var _raid_clock := 480.0
var _accumulator := 0.0
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	reset()

func reset(p_seed_value: int = 42) -> void:
	seed_value = p_seed_value
	_rng.seed = seed_value
	entities.clear()
	_by_id.clear()
	resources = [{"food": 280, "wood": 340, "crystal": 140}, {"food": 280, "wood": 340, "crystal": 140}]
	tech = [0, 0]
	events.clear()
	stats = {"gathered": 0, "built": 0, "trained": 0, "kills": 0, "commands": 0, "explored": 0, "selected_worker": false}
	elapsed = 0.0
	result = ""
	_next_id = 1
	_fog_clock = 0.0
	_ai_clock = 0.0
	_raid_clock = 480.0 if difficulty == "relaxed" else 90.0
	_accumulator = 0.0
	_visible = []
	_explored = []
	for team in range(2):
		var visible_cells := PackedByteArray()
		var explored_cells := PackedByteArray()
		visible_cells.resize(FOG_SIZE * FOG_SIZE)
		explored_cells.resize(FOG_SIZE * FOG_SIZE)
		_visible.append(visible_cells)
		_explored.append(explored_cells)
	_spawn("heart", 0, Vector2(18, 58))
	_spawn("heart", 1, Vector2(62, 22))
	for i in range(4):
		_spawn("worker", 0, Vector2(13 + i * 2, 63))
		_spawn("worker", 1, Vector2(58 + i * 2, 17))
	_spawn("guard", 0, Vector2(22, 53))
	_spawn("ranger", 0, Vector2(25, 55))
	_spawn("guard", 1, Vector2(57, 27))
	_spawn("ranger", 1, Vector2(54, 25))
	# The balanced starting basins surround a central crystal ridge.
	var clusters := [
		["tree", Vector2(8, 52), 8], ["tree", Vector2(27, 66), 7],
		["berry", Vector2(10, 65), 5], ["ore", Vector2(27, 49), 5],
		["tree", Vector2(72, 28), 8], ["tree", Vector2(53, 14), 7],
		["berry", Vector2(70, 15), 5], ["ore", Vector2(53, 31), 5],
		["ore", Vector2(38, 42), 8], ["tree", Vector2(18, 24), 8],
		["tree", Vector2(61, 59), 8], ["berry", Vector2(40, 61), 5],
		["berry", Vector2(39, 19), 5]
	]
	for cluster in clusters:
		for i in range(int(cluster[2])):
			var angle := float(i) * 2.39996
			var dist := 1.1 + sqrt(float(i)) * 1.45
			var center: Vector2 = cluster[1]
			_spawn(str(cluster[0]), -1, center + Vector2(cos(angle), sin(angle)) * dist)
	_rebuild_grid()
	_update_fog()
	_emit("reset", {"seed": seed_value})

func entity(id: int) -> Dictionary:
	return _by_id.get(id, {})

func _spawn(kind: String, team: int, point: Vector2, progress: float = 1.0) -> Dictionary:
	var definition: Dictionary = Data.UNITS.get(kind, Data.BUILDINGS.get(kind, {}))
	var max_hp: float = float(definition.get("hp", 100.0))
	var e := {"id": _next_id, "kind": kind, "team": team, "pos": point,
		"hp": max_hp * maxf(progress, 0.1), "max_hp": max_hp,
		"built": progress, "state": "idle", "radius": float(definition.get("radius", 0.65)),
		"target": -1, "destination": point, "path": [], "path_age": 0.0,
		"cooldown": 0.0, "work_timer": 0.0, "carry": 0,
		"carry_kind": "", "source": -1, "queue": [], "train_progress": 0.0,
		"facing": 0.0, "hit_flash": 0.0, "attack_flash": 0.0, "amount": 650,
		"rally": point + Vector2(0, -4 if team == 0 else 4)}
	if Data.RESOURCE_KINDS.has(kind):
		e["resource"] = Data.RESOURCE_KINDS[kind]
		e["amount"] = 900 if kind == "ore" else 650
	entities.append(e)
	_by_id[_next_id] = e
	_next_id += 1
	return e

func population(team: int) -> Vector2i:
	var used := 0
	var capacity := 0
	for e in entities:
		if e.team != team or e.hp <= 0:
			continue
		if Data.UNITS.has(e.kind):
			used += 1
		elif e.built >= 1.0:
			capacity += int(Data.BUILDINGS[e.kind].get("capacity", 0))
		used += e.queue.size()
	return Vector2i(used, mini(capacity, 80))

func can_place(kind: String, point: Vector2) -> bool:
	if not Data.BUILDINGS.has(kind) or kind == "heart" or not point.is_finite():
		return false
	var radius: float = Data.BUILDINGS[kind].radius
	if point.x < radius + 1 or point.y < radius + 1 or point.x > WORLD_SIZE - radius - 1 or point.y > WORLD_SIZE - radius - 1:
		return false
	for e in entities:
		if e.hp <= 0 or Data.UNITS.has(e.kind):
			continue
		if point.distance_to(e.pos) < radius + float(e.radius) + 1.25:
			return false
	return true

func build(kind: String, point: Vector2, worker_ids: Array, team: int = 0) -> String:
	if result != "":
		return "本局已结束，请重新开始。"
	if team < 0 or team > 1 or not Data.COSTS.has(kind) or not Data.BUILDINGS.has(kind):
		return "无法建造此建筑。"
	var workers: Array[Dictionary] = []
	for id in worker_ids:
		var worker := entity(int(id))
		if not worker.is_empty() and worker.team == team and worker.kind == "worker" and worker.hp > 0:
			workers.append(worker)
	if workers.is_empty():
		return "请先选择至少一名拾光者。"
	if not can_place(kind, point):
		return "这里空间不足：请远离建筑、资源和地图边缘。"
	if not is_visible(point, team):
		return "请先派单位探索并照亮建造地点。"
	var reachable := false
	for worker in workers:
		if not _find_path(worker.pos, point).is_empty():
			reachable = true
	if not reachable:
		return "拾光者无法到达这个位置。"
	var error := _spend(team, kind)
	if error != "":
		return error
	var building := _spawn(kind, team, point, 0.0)
	_rebuild_grid()
	for worker in workers:
		_set_order(worker, "build", point, building.id)
	_emit("build_started", {"id": building.id, "kind": kind, "team": team, "point": point})
	return ""

func train(building_id: int, kind: String) -> String:
	if result != "":
		return "本局已结束。"
	var building := entity(building_id)
	if building.is_empty() or building.hp <= 0 or not Data.BUILDINGS.has(building.kind):
		return "请先选择生产建筑。"
	if building.built < 1.0:
		return "建筑尚未完工。"
	if kind not in Data.BUILDINGS[building.kind].get("trains", []):
		return "这座建筑不能训练该单位。"
	if building.queue.size() >= 5:
		return "生产队列已满，最多可排队 5 个单位。"
	var pop := population(building.team)
	if pop.x >= pop.y:
		return "人口上限不足，请建造风栖居。"
	var error := _spend(building.team, kind)
	if error != "":
		return error
	building.queue.append(kind)
	_emit("train_started", {"id": building_id, "kind": kind, "team": building.team})
	return ""

func research(team: int = 0) -> String:
	if team < 0 or team > 1:
		return "未知阵营。"
	if result != "":
		return "本局已结束。"
	if tech[team] >= 1:
		return "共鸣锻造已完成。"
	if _heart(team).is_empty():
		return "需要一座回响心。"
	var error := _spend(team, "research")
	if error != "":
		return error
	tech[team] = 1
	_emit("research", {"team": team})
	return ""

func command(ids: Array, action: String, point: Vector2 = Vector2.ZERO, target_id: int = -1) -> String:
	if result != "":
		return "本局已结束。"
	if action not in ["move", "attack", "gather", "stop", "build"]:
		return "未知指令。"
	if not point.is_finite():
		return "目标位置无效。"
	var selected: Array[Dictionary] = []
	for id in ids:
		var e := entity(int(id))
		if not e.is_empty() and e.hp > 0 and e.team >= 0 and Data.UNITS.has(e.kind):
			selected.append(e)
	if selected.is_empty():
		return "请先选择单位。"
	var target := entity(target_id)
	if action in ["gather", "build"] and target.is_empty():
		return "目标已不存在。"
	if action == "gather" and not Data.RESOURCE_KINDS.has(target.kind):
		return "请选择风铃木、穗果丛或岚晶矿。"
	if action == "gather" and target.get("amount", 0) <= 0:
		return "此处资源已耗尽。"
	if action == "build" and (not Data.BUILDINGS.has(target.kind) or target.built >= 1.0):
		return "请选择尚未完工的己方建筑。"
	if action == "attack" and target_id >= 0 and target.is_empty():
		return "攻击目标已不存在。"
	if action == "attack" and not target.is_empty() and (target.team < 0 or target.team == selected[0].team):
		return "请选择敌方单位或建筑。"
	if not target.is_empty():
		point = target.pos
		if action != "build" and not is_visible(point, selected[0].team):
			return "目标已离开视野，请先探索该区域。"
	if point.x < 0 or point.y < 0 or point.x > WORLD_SIZE or point.y > WORLD_SIZE:
		return "目标超出地图边界。"
	var issued := 0
	for i in range(selected.size()):
		var e: Dictionary = selected[i]
		if action in ["gather", "build"] and e.kind != "worker":
			continue
		if action == "build" and e.team != target.team:
			continue
		if action == "stop":
			_set_order(e, "idle", e.pos, -1)
		else:
			var destination := point
			if selected.size() > 1 and action == "move":
				var width := int(ceil(sqrt(float(selected.size()))))
				destination += Vector2(float(i % width) - float(width - 1) * 0.5, float(i / width) - float(width - 1) * 0.5) * 1.3
				destination = destination.clamp(Vector2.ONE, Vector2(79, 79))
			var route := _find_path(e.pos, destination)
			if route.is_empty() and e.pos.distance_to(destination) > 1.5:
				continue
			_set_order(e, "attack_move" if action == "attack" and target.is_empty() else action, destination, target_id)
			e.path = route
			if action == "gather":
				e.source = target_id
		issued += 1
	if issued == 0:
		return "没有可执行该指令的单位，或目标无法到达。"
	stats.commands += 1
	_emit("command", {"action": action, "team": selected[0].team, "point": point, "target": target_id, "count": issued})
	return ""

func _spend(team: int, kind: String) -> String:
	var cost: Dictionary = Data.COSTS[kind]
	var missing: PackedStringArray = []
	for resource in ["food", "wood", "crystal"]:
		var amount: int = int(cost.get(resource, 0)) - int(resources[team].get(resource, 0))
		if amount > 0:
			missing.append("%s %d" % [Data.RESOURCE_NAMES[resource], amount])
	if not missing.is_empty():
		return "资源不足，还需要：" + "、".join(missing)
	for resource in cost:
		resources[team][resource] -= int(cost[resource])
	return ""

func _set_order(e: Dictionary, state: String, point: Vector2, target_id: int) -> void:
	e.state = state
	e.destination = point
	e.target = target_id
	e.path = []
	e.path_age = 2.0
	e.work_timer = 0.0

func step(dt: float) -> void:
	if result != "" or not is_finite(dt) or dt <= 0.0:
		return
	# Fixed ticks produce identical rules at 30/60/120 rendering frames per second.
	_accumulator += minf(dt, 5.0)
	while _accumulator >= STEP - 0.000001 and result == "":
		_accumulator = maxf(0.0, _accumulator - STEP)
		_tick(STEP)

func _tick(dt: float) -> void:
	elapsed += dt
	_fog_clock += dt
	_ai_clock += dt
	var units := entities.duplicate()
	for e in units:
		if e.hp <= 0 or e.team < 0:
			continue
		e.cooldown = maxf(0.0, float(e.cooldown) - dt)
		e.hit_flash = maxf(0.0, float(e.hit_flash) - dt)
		e.attack_flash = maxf(0.0, float(e.attack_flash) - dt)
		if Data.BUILDINGS.has(e.kind):
			if e.built >= 1.0:
				_update_production(e, dt)
				if e.kind == "tower":
					_update_tower(e)
		else:
			_update_unit(e, dt)
	_cleanup_dead()
	if _fog_clock >= 0.35:
		_fog_clock = 0.0
		_update_fog()
	if ai_enabled and _ai_clock >= 2.0 and result == "":
		_ai_clock = 0.0
		_update_ai()

func _update_production(e: Dictionary, dt: float) -> void:
	if e.queue.is_empty():
		e.train_progress = 0.0
		return
	var pop := population(e.team)
	if pop.x > pop.y:
		return
	var kind: String = str(e.queue[0])
	e.train_progress += dt
	if e.train_progress < float(Data.UNITS[kind].train_time):
		return
	var spawn_point := _nearest_open(e.pos + Vector2(0, -1 if e.team == 0 else 1) * (float(e.radius) + 1.5))
	var unit := _spawn(kind, e.team, spawn_point)
	e.queue.pop_front()
	e.train_progress = 0.0
	_set_order(unit, "move", _nearest_open(e.rally), -1)
	if e.team == 0:
		stats.trained += 1
	_emit("trained", {"id": unit.id, "kind": kind, "team": e.team, "point": spawn_point})

func _update_unit(e: Dictionary, dt: float) -> void:
	e.path_age += dt
	var target := entity(int(e.target))
	if e.state == "gather":
		_update_gather(e, target, dt)
		return
	if e.state == "return":
		_update_return(e, dt)
		return
	if e.state == "build":
		_update_build(e, target, dt)
		return
	if e.state == "attack":
		if target.is_empty() or target.hp <= 0 or target.team == e.team:
			_set_order(e, "idle", e.pos, -1)
		elif not is_visible(target.pos, e.team):
			_set_order(e, "attack_move", target.pos, -1)
		else:
			_attack_or_chase(e, target, dt)
			return
	if e.kind != "worker" and e.state in ["idle", "attack_move"]:
		var enemy := _nearest_enemy(e, 9.0)
		if not enemy.is_empty():
			_attack_or_chase(e, enemy, dt)
			return
	# Workers defend themselves only while idle, never abandon resource orders.
	if e.kind == "worker" and e.state == "idle":
		var enemy := _nearest_enemy(e, 2.2)
		if not enemy.is_empty():
			_attack_or_chase(e, enemy, dt)
			return
	if e.state in ["move", "attack_move"]:
		if _walk(e, e.destination, dt, 0.45):
			_set_order(e, "idle", e.pos, -1)

func _update_gather(e: Dictionary, target: Dictionary, dt: float) -> void:
	if e.carry >= 12 or (e.carry > 0 and (target.is_empty() or target.amount <= 0)):
		_set_order(e, "return", e.pos, -1)
		return
	if target.is_empty() or not Data.RESOURCE_KINDS.has(target.kind) or target.amount <= 0:
		var resource_kind: String = str(e.carry_kind)
		var next := _nearest_resource(e.pos, resource_kind)
		if next.is_empty():
			_set_order(e, "idle", e.pos, -1)
		else:
			e.target = next.id
			e.source = next.id
		return
	if e.carry > 0 and e.carry_kind != target.resource:
		_set_order(e, "return", e.pos, -1)
		return
	if not _walk(e, target.pos, dt, float(target.radius) + 1.0):
		return
	e.work_timer += dt * (1.2 if tech[e.team] > 0 else 1.0)
	if e.work_timer >= 0.7:
		e.work_timer -= 0.7
		var take := mini(2, mini(12 - int(e.carry), int(target.amount)))
		target.amount -= take
		e.carry += take
		e.carry_kind = target.resource
		e.attack_flash = 0.22
		_emit("harvest", {"team": e.team, "id": e.id, "resource": target.resource, "point": e.pos, "amount": take})

func _update_return(e: Dictionary, dt: float) -> void:
	var heart := _heart(e.team)
	if heart.is_empty():
		_set_order(e, "idle", e.pos, -1)
		return
	if not _walk(e, heart.pos, dt, float(heart.radius) + 1.3):
		return
	if e.carry > 0 and e.carry_kind in ["food", "wood", "crystal"]:
		resources[e.team][e.carry_kind] += int(e.carry)
		if e.team == 0:
			stats.gathered += int(e.carry)
		_emit("gathered", {"team": e.team, "resource": e.carry_kind, "amount": e.carry, "id": e.id})
	e.carry = 0
	var source := entity(int(e.source))
	if source.is_empty() or int(source.amount) <= 0:
		source = _nearest_resource(e.pos, str(e.carry_kind))
	if source.is_empty():
		_set_order(e, "idle", e.pos, -1)
	else:
		_set_order(e, "gather", source.pos, source.id)
		e.source = source.id

func _update_build(e: Dictionary, target: Dictionary, dt: float) -> void:
	if target.is_empty() or target.hp <= 0 or target.built >= 1.0 or target.team != e.team:
		_set_order(e, "idle", e.pos, -1)
		return
	if not _walk(e, target.pos, dt, float(target.radius) + 1.5):
		return
	var gain := dt / float(Data.BUILDINGS[target.kind].build_time)
	target.built = minf(1.0, float(target.built) + gain)
	target.hp = minf(float(target.max_hp), float(target.hp) + float(target.max_hp) * gain * 0.9)
	e.attack_flash = 0.15
	if target.built >= 1.0:
		target.hp = minf(float(target.max_hp), float(target.hp))
		if target.team == 0:
			stats.built += 1
		_emit("built", {"id": target.id, "kind": target.kind, "team": target.team})
		_set_order(e, "idle", e.pos, -1)

func _attack_or_chase(e: Dictionary, target: Dictionary, dt: float) -> void:
	var definition: Dictionary = Data.UNITS[e.kind]
	var reach: float = float(definition.range) + float(target.radius)
	if e.pos.distance_to(target.pos) > reach:
		_walk(e, target.pos, dt, reach * 0.9)
		return
	e.facing = (target.pos - e.pos).angle()
	if e.cooldown > 0.0:
		return
	e.cooldown = float(definition.interval)
	_deal_damage(e, target, float(definition.damage))

func _update_tower(e: Dictionary) -> void:
	if e.cooldown > 0.0:
		return
	var target := _nearest_enemy(e, float(Data.BUILDINGS.tower.range))
	if target.is_empty():
		return
	e.cooldown = float(Data.BUILDINGS.tower.interval)
	_deal_damage(e, target, float(Data.BUILDINGS.tower.damage))

func _deal_damage(source: Dictionary, target: Dictionary, damage: float) -> void:
	if source.kind == "guard" and target.kind == "ranger":
		damage *= 1.5
	elif source.kind == "ranger" and target.kind == "breaker":
		damage *= 1.6
	elif source.kind == "rider" and target.kind == "ranger":
		damage *= 1.8
	elif source.kind == "lancer" and target.kind == "rider":
		damage *= 2.2
	elif source.kind == "breaker":
		if Data.BUILDINGS.has(target.kind):
			damage *= 2.5
		elif target.kind == "guard":
			damage *= 1.3
	damage *= 1.25 if tech[source.team] > 0 else 1.0
	if source.team == 1 and difficulty == "relaxed":
		damage *= 0.7
	target.hp -= damage
	target.hit_flash = 0.22
	source.attack_flash = 0.2
	_emit("attack", {"id": source.id, "target": target.id, "team": source.team, "damage": damage, "point": target.pos, "from": source.pos, "kind": source.kind})
	if target.hp <= 0 and source.team == 0:
		stats.kills += 1

func _nearest_enemy(e: Dictionary, reach: float) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := reach
	for other in entities:
		if other.team < 0 or other.team == e.team or other.hp <= 0:
			continue
		var dist: float = e.pos.distance_to(other.pos) - float(other.radius)
		if dist < best_distance and is_visible(other.pos, e.team):
			best_distance = dist
			best = other
	return best

func _heart(team: int) -> Dictionary:
	for e in entities:
		if e.team == team and e.kind == "heart" and e.hp > 0:
			return e
	return {}

func _nearest_resource(point: Vector2, resource: String = "") -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for e in entities:
		if e.team != -1 or not Data.RESOURCE_KINDS.has(e.kind) or e.amount <= 0:
			continue
		if resource != "" and e.resource != resource:
			continue
		var distance: float = point.distance_squared_to(e.pos)
		if distance < best_distance:
			best = e
			best_distance = distance
	return best

func _cleanup_dead() -> void:
	var rebuild := false
	for i in range(entities.size() - 1, -1, -1):
		var e: Dictionary = entities[i]
		if e.hp > 0:
			continue
		_emit("destroyed", {"id": e.id, "team": e.team, "kind": e.kind, "point": e.pos})
		if Data.BUILDINGS.has(e.kind):
			rebuild = true
		if e.kind == "heart":
			result = "win" if e.team == 1 else "lose"
			_emit("result", {"result": result, "elapsed": elapsed})
		_by_id.erase(e.id)
		entities.remove_at(i)
	if rebuild:
		_rebuild_grid()

func _rebuild_grid() -> void:
	_grid.region = Rect2i(0, 0, 80, 80)
	_grid.cell_size = Vector2.ONE
	_grid.offset = Vector2(0.5, 0.5)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	_grid.fill_solid_region(_grid.region, false)
	for e in entities:
		if e.hp <= 0 or Data.UNITS.has(e.kind):
			continue
		var radius: float = e.radius + (0.25 if e.team >= 0 else 0.1)
		for x in range(maxi(0, int(e.pos.x - radius - 1)), mini(80, int(e.pos.x + radius + 2))):
			for y in range(maxi(0, int(e.pos.y - radius - 1)), mini(80, int(e.pos.y + radius + 2))):
				if Vector2(x + 0.5, y + 0.5).distance_to(e.pos) < radius:
					_grid.set_point_solid(Vector2i(x, y), true)
	for e in entities:
		e.path = []
		e.path_age = 2.0

func _cell(point: Vector2) -> Vector2i:
	return Vector2i(clampi(int(point.x), 0, 79), clampi(int(point.y), 0, 79))

func _nearest_open(point: Vector2) -> Vector2:
	var origin := _cell(point)
	if not _grid.is_point_solid(origin):
		return point.clamp(Vector2(0.5, 0.5), Vector2(79.5, 79.5))
	for ring in range(1, 12):
		var best := Vector2(-1, -1)
		var distance := INF
		for x in range(-ring, ring + 1):
			for y in range(-ring, ring + 1):
				if absi(x) != ring and absi(y) != ring:
					continue
				var candidate := origin + Vector2i(x, y)
				if not _grid.region.has_point(candidate) or _grid.is_point_solid(candidate):
					continue
				var pos := Vector2(candidate) + Vector2(0.5, 0.5)
				if pos.distance_squared_to(point) < distance:
					best = pos
					distance = pos.distance_squared_to(point)
		if best.x >= 0:
			return best
	return Vector2(origin) + Vector2(0.5, 0.5)

func _find_path(from: Vector2, to: Vector2) -> Array:
	var start := _cell(_nearest_open(from))
	var finish := _cell(_nearest_open(to))
	if _grid.is_point_solid(start) or _grid.is_point_solid(finish):
		return []
	var raw := _grid.get_point_path(start, finish)
	var path: Array = []
	for point in raw:
		path.append(point)
	if not path.is_empty():
		path[0] = from
		path[path.size() - 1] = _nearest_open(to)
	return path

func _walk(e: Dictionary, point: Vector2, dt: float, stop_distance: float) -> bool:
	if e.pos.distance_to(point) <= stop_distance:
		return true
	# Chasing moving targets refreshes a route only when the target changes cell.
	if e.path.is_empty() or (e.path_age > 1.2 and e.get("path_target", Vector2(-99, -99)).distance_to(point) > 1.2):
		e.path = _find_path(e.pos, point)
		e.path_target = point
		e.path_age = 0.0
	if e.path.is_empty():
		return false
	while not e.path.is_empty() and e.pos.distance_to(e.path[0]) < 0.28:
		e.path.pop_front()
	if e.path.is_empty():
		return e.pos.distance_to(point) <= stop_distance + 1.3
	var waypoint: Vector2 = e.path[0]
	var direction: Vector2 = (waypoint - e.pos).normalized()
	var speed: float = Data.UNITS[e.kind].speed
	var distance := minf(speed * dt, e.pos.distance_to(waypoint))
	var next: Vector2 = e.pos + direction * distance
	# Soft separation avoids overlapping troops without deadlocking shared goals.
	var separation := Vector2.ZERO
	for other in entities:
		if other.id == e.id or other.hp <= 0 or not Data.UNITS.has(other.kind):
			continue
		var away: Vector2 = next - other.pos
		var minimum: float = (float(e.radius) + float(other.radius)) * 0.8
		var dist := away.length()
		if dist < minimum and dist > 0.01:
			separation += away / dist * (minimum - dist) * 2.0 * dt
		elif dist <= 0.01:
			separation += Vector2(0.15 if e.id > other.id else -0.15, 0) * dt
	var candidate: Vector2 = (next + separation.limit_length(distance * 0.4)).clamp(Vector2(0.5, 0.5), Vector2(79.5, 79.5))
	if not _grid.is_point_solid(_cell(candidate)):
		e.pos = candidate
	elif not _grid.is_point_solid(_cell(next)):
		e.pos = next
	else:
		e.path = []
	e.facing = direction.angle()
	return e.pos.distance_to(point) <= stop_distance

func is_visible(point: Vector2, team: int = 0) -> bool:
	if team < 0 or team > 1 or not point.is_finite() or point.x < 0 or point.y < 0 or point.x >= 80 or point.y >= 80:
		return false
	return _visible[team][clampi(int(point.y / 2), 0, 39) * FOG_SIZE + clampi(int(point.x / 2), 0, 39)] == 1

func is_explored(point: Vector2, team: int = 0) -> bool:
	if team < 0 or team > 1 or not point.is_finite() or point.x < 0 or point.y < 0 or point.x >= 80 or point.y >= 80:
		return false
	return _explored[team][clampi(int(point.y / 2), 0, 39) * FOG_SIZE + clampi(int(point.x / 2), 0, 39)] == 1

func _update_fog() -> void:
	for team in range(2):
		_visible[team].fill(0)
	for e in entities:
		if e.team < 0 or e.hp <= 0:
			continue
		var definition: Dictionary = Data.UNITS.get(e.kind, Data.BUILDINGS.get(e.kind, {}))
		var vision: float = definition.get("vision", 9.0)
		if e.built < 1.0:
			vision *= 0.5
		for x in range(maxi(0, int((e.pos.x - vision) / 2)), mini(40, int((e.pos.x + vision) / 2) + 1)):
			for y in range(maxi(0, int((e.pos.y - vision) / 2)), mini(40, int((e.pos.y + vision) / 2) + 1)):
				if Vector2(x * 2 + 1, y * 2 + 1).distance_squared_to(e.pos) <= vision * vision:
					_visible[e.team][y * FOG_SIZE + x] = 1
					_explored[e.team][y * FOG_SIZE + x] = 1
	var discovered := 0
	for value in _explored[0]:
		discovered += value
	stats.explored = discovered

func set_difficulty(value: String) -> void:
	if value not in ["relaxed", "standard"] or value == difficulty:
		return
	difficulty = value
	_raid_clock = maxf(480.0, elapsed + 180.0) if difficulty == "relaxed" else elapsed + 90.0
	if difficulty == "relaxed":
		_recall_enemy_army()

func _recall_enemy_army() -> void:
	var heart := _heart(1)
	if heart.is_empty(): return
	for e in entities:
		if e.team == 1 and Data.UNITS.has(e.kind) and e.kind != "worker":
			_set_order(e, "move", heart.pos + Vector2(-4,4), -1)

func _update_ai() -> void:
	var heart := _heart(1)
	var player_heart := _heart(0)
	if heart.is_empty() or player_heart.is_empty():
		return
	var workers: Array[Dictionary] = []
	var troops: Array = []
	var barracks: Dictionary = {}
	var unfinished: Dictionary = {}
	for e in entities:
		if e.team != 1:
			continue
		if e.kind == "worker":
			workers.append(e)
		elif Data.UNITS.has(e.kind):
			troops.append(e.id)
		elif e.kind == "barracks" and e.built >= 1.0:
			barracks = e
		if Data.BUILDINGS.has(e.kind) and e.built < 1.0:
			unfinished = e
	# Maintain a small economy; AI pays the same costs as the player.
	var relaxed := difficulty == "relaxed"
	if workers.size() + heart.queue.size() < (6 if relaxed else 7) and elapsed < 450:
		train(heart.id, "worker")
	for i in range(workers.size()):
		var worker: Dictionary = workers[i]
		if worker.state not in ["idle", "move"]:
			continue
		if not unfinished.is_empty() and i == 0:
			_set_order(worker, "build", unfinished.pos, unfinished.id)
			continue
		var wanted: String = ["wood", "food", "food", "wood", "crystal", "food", "wood"][i % 7]
		var target := _nearest_resource(worker.pos, wanted)
		if not target.is_empty():
			_set_order(worker, "gather", target.pos, target.id)
			worker.source = target.id
	if not workers.is_empty() and unfinished.is_empty():
		var kind := ""
		var pop := population(1)
		if barracks.is_empty() and elapsed > (60 if relaxed else 8):
			kind = "barracks"
		elif pop.y - pop.x <= 2 and pop.y < 34:
			kind = "house"
		if kind != "":
			var locations := [Vector2(62, 32), Vector2(67, 37), Vector2(72, 36), Vector2(73, 22), Vector2(63, 10), Vector2(49, 20)]
			for location in locations:
				if can_place(kind, location) and is_visible(location, 1):
					build(kind, location, [workers[0].id], 1)
					break
	var army_cap := (6 if elapsed < 720 else 10) if relaxed else 24
	if not barracks.is_empty() and barracks.queue.size() < (1 if relaxed else 2) and troops.size() + barracks.queue.size() < army_cap:
		var kinds := ["guard", "ranger", "lancer", "ranger"] if relaxed and elapsed < 720 else ["guard", "ranger", "lancer", "rider", "breaker"]
		var choice: String = kinds[int(elapsed / 17.0) % kinds.size()]
		train(barracks.id, choice)
	if elapsed > (720 if relaxed else 240) and tech[1] == 0 and resources[1].food > 200:
		research(1)
	if elapsed >= _raid_clock:
		_raid_clock = elapsed + (150.0 if relaxed else 80.0)
		if troops.size() >= 3:
			var raid_limit := (2 if elapsed < 720 else (3 if elapsed < 1080 else 4)) if relaxed else (2 if elapsed < 180 else (4 if elapsed < 300 else 7))
			var sent := 0
			for id in troops:
				var troop := entity(id)
				if relaxed and (troop.kind in ["breaker", "rider"] and elapsed < 720 or troop.state not in ["idle", "move"]):
					continue
				if elapsed < 180 and troop.kind == "breaker":
					continue
				if sent >= raid_limit:
					break
				_set_order(troop, "attack_move", player_heart.pos, -1)
				sent += 1
			if sent > 0: _emit("raid", {"team": 1, "count": sent})

func _emit(type: String, details: Dictionary = {}) -> void:
	var event := details.duplicate()
	event["type"] = type
	event["time"] = elapsed
	events.append(event)
	if events.size() > 256:
		events.pop_front()

func save_dict() -> Dictionary:
	var saved_entities: Array = []
	for e in entities:
		var saved := e.duplicate(true)
		saved.pos = [e.pos.x, e.pos.y]
		saved.destination = [e.destination.x, e.destination.y]
		saved.rally = [e.rally.x, e.rally.y]
		saved.erase("path_target")
		saved.path = []
		saved_entities.append(saved)
	return {"version": Data.SAVE_VERSION, "seed": seed_value, "elapsed": elapsed,
		"result": result, "resources": resources.duplicate(true), "tech": tech.duplicate(),
		"entities": saved_entities, "next_id": _next_id, "stats": stats.duplicate(true),
		"explored": [Array(_explored[0]), Array(_explored[1])],
		"raid_clock": _raid_clock, "ai_clock": _ai_clock, "ai_enabled": ai_enabled, "accumulator": _accumulator, "difficulty": difficulty}

func load_dict(data: Dictionary) -> bool:
	# Parse into temporary data first; every rejection leaves the match unchanged.
	if data.get("difficulty", "relaxed") not in ["relaxed", "standard"]:
		return false
	if int(data.get("version", -1)) != Data.SAVE_VERSION:
		return false
	if not _number(data.get("elapsed")) or float(data.elapsed) < 0 or float(data.elapsed) > 864000:
		return false
	if data.get("result", "invalid") not in ["", "win", "lose"]:
		return false
	if not data.get("resources") is Array or data.resources.size() != 2 or not data.get("tech") is Array or data.tech.size() != 2:
		return false
	var checked_resources: Array[Dictionary] = []
	var checked_tech: Array[int] = []
	for team in range(2):
		if not data.resources[team] is Dictionary or not _integer(data.tech[team]) or int(data.tech[team]) not in [0, 1]:
			return false
		var inventory := {}
		for resource in ["food", "wood", "crystal"]:
			var value: Variant = data.resources[team].get(resource)
			if not _integer(value) or float(value) < 0 or float(value) > 100000000:
				return false
			inventory[resource] = int(value)
		checked_resources.append(inventory)
		checked_tech.append(int(data.tech[team]))
	if not data.get("entities") is Array or data.entities.size() > 3000:
		return false
	var checked_entities: Array[Dictionary] = []
	var ids := {}
	var max_id := 0
	var hearts := [0, 0]
	for raw in data.entities:
		if not raw is Dictionary:
			return false
		if not _integer(raw.get("id")) or int(raw.id) <= 0 or ids.has(int(raw.id)):
			return false
		var kind: String = str(raw.get("kind", ""))
		if not Data.UNITS.has(kind) and not Data.BUILDINGS.has(kind) and not Data.RESOURCE_KINDS.has(kind):
			return false
		if not _integer(raw.get("team")) or int(raw.team) not in [-1, 0, 1]:
			return false
		var team := int(raw.team)
		if (Data.RESOURCE_KINDS.has(kind) and team != -1) or (not Data.RESOURCE_KINDS.has(kind) and team == -1):
			return false
		for field in ["pos", "destination", "rally"]:
			if not _valid_point(raw.get(field)):
				return false
		for field in ["hp", "max_hp", "built", "radius", "cooldown", "work_timer", "train_progress", "facing", "hit_flash", "attack_flash", "path_age"]:
			if not _number(raw.get(field)):
				return false
		if float(raw.hp) <= 0 or float(raw.max_hp) <= 0 or float(raw.hp) > float(raw.max_hp) + 0.01 or float(raw.max_hp) > 100000:
			return false
		if float(raw.built) < 0 or float(raw.built) > 1 or float(raw.radius) < 0.1 or float(raw.radius) > 8:
			return false
		if raw.get("state") not in ["idle", "move", "attack_move", "attack", "gather", "return", "build"]:
			return false
		for field in ["target", "source", "carry", "amount"]:
			if not _integer(raw.get(field)):
				return false
		if int(raw.carry) < 0 or int(raw.carry) > 12 or int(raw.amount) < 0 or int(raw.amount) > 10000000:
			return false
		if raw.get("carry_kind") not in ["", "food", "wood", "crystal"]:
			return false
		if not raw.get("queue") is Array or raw.queue.size() > 5:
			return false
		for queued in raw.queue:
			if not Data.BUILDINGS.has(kind) or queued not in Data.BUILDINGS[kind].get("trains", []):
				return false
		if Data.RESOURCE_KINDS.has(kind) and raw.get("resource") != Data.RESOURCE_KINDS[kind]:
			return false
		var e: Dictionary = raw.duplicate(true)
		e.id = int(raw.id)
		e.team = team
		e.target = int(raw.target)
		e.source = int(raw.source)
		e.carry = int(raw.carry)
		e.amount = int(raw.amount)
		for field in ["pos", "destination", "rally"]:
			e[field] = Vector2(float(raw[field][0]), float(raw[field][1]))
		e.path = []
		e.path_age = 2.0
		ids[e.id] = true
		max_id = maxi(max_id, e.id)
		checked_entities.append(e)
		if kind == "heart":
			hearts[team] += 1
	if data.result == "" and (hearts[0] != 1 or hearts[1] != 1):
		return false
	if data.result == "win" and (hearts[0] != 1 or hearts[1] != 0):
		return false
	if data.result == "lose" and hearts[0] != 0:
		return false
	if not data.get("explored") is Array or data.explored.size() != 2:
		return false
	var checked_explored: Array = []
	for cells in data.explored:
		if not cells is Array or cells.size() != FOG_SIZE * FOG_SIZE:
			return false
		var checked := PackedByteArray()
		for value in cells:
			if not _integer(value) or int(value) not in [0, 1]:
				return false
			checked.append(int(value))
		checked_explored.append(checked)
	if not _number(data.get("raid_clock")) or not _number(data.get("ai_clock")) or not data.get("ai_enabled") is bool:
		return false
	if not _number(data.get("accumulator")) or float(data.accumulator) < 0.0 or float(data.accumulator) > 5.0:
		return false
	if not data.get("stats") is Dictionary or not _integer(data.get("seed")):
		return false
	for key in ["gathered", "built", "trained", "kills", "commands", "explored"]:
		if not _number(data.stats.get(key)) or float(data.stats[key]) < 0:
			return false
	# Commit only after validating the complete document.
	entities = checked_entities
	resources = checked_resources
	tech = checked_tech
	_by_id.clear()
	for e in entities:
		_by_id[e.id] = e
	_next_id = max_id + 1
	seed_value = int(data.seed)
	_rng.seed = seed_value
	elapsed = float(data.elapsed)
	result = str(data.result)
	stats = data.stats.duplicate(true)
	_explored = checked_explored
	_raid_clock = float(data.raid_clock)
	difficulty = str(data.get("difficulty", "relaxed"))
	if not data.has("difficulty"):
		_raid_clock = maxf(480.0, elapsed + 180.0)
		_recall_enemy_army()
	_ai_clock = float(data.ai_clock)
	_accumulator = float(data.accumulator)
	ai_enabled = bool(data.ai_enabled)
	_fog_clock = 0.0
	events.clear()
	_rebuild_grid()
	_update_fog()
	_emit("loaded")
	return true

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _integer(value: Variant) -> bool:
	return _number(value) and float(value) == floor(float(value))

func _valid_point(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1]) and float(value[0]) >= 0.0 and float(value[0]) <= 80.0 and float(value[1]) >= 0.0 and float(value[1]) <= 80.0
