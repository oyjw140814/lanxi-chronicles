extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
const Data = preload("res://scripts/game_data.gd")
var failed := 0
var passed := 0

func _init() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if value:
		passed += 1
		print("PASS ", message)
	else:
		failed += 1
		push_error("FAIL " + message)

func _new() -> RefCounted:
	var sim := Sim.new()
	sim.ai_enabled = false
	return sim

func _advance(sim: RefCounted, seconds: float) -> void:
	var ticks := int(ceil(seconds / 0.1))
	for i in range(ticks):
		sim.step(0.1)

func _find(sim: RefCounted, kind: String, team: int = 0) -> Dictionary:
	for e in sim.entities:
		if e.kind == kind and e.team == team:
			return e
	return {}

func _ids(sim: RefCounted, kind: String, team: int = 0) -> Array:
	var result: Array = []
	for e in sim.entities:
		if e.kind == kind and e.team == team:
			result.append(e.id)
	return result

func _run() -> void:
	var start := Time.get_ticks_msec()
	_test_economy()
	_test_construction_production()
	_test_orders_paths_fog()
	_test_combat_results()
	_test_save_transaction()
	_test_ai()
	_test_complete_match()
	print("SIMULATION TESTS: %d passed, %d failed; %d ms" % [passed, failed, Time.get_ticks_msec() - start])
	quit(1 if failed > 0 else 0)

func _test_economy() -> void:
	var sim := _new()
	var worker := _find(sim, "worker")
	var tree: Dictionary = sim._nearest_resource(worker.pos, "wood")
	var previous_wood: int = sim.resources[0].wood
	_check(sim.command([worker.id], "gather", tree.pos, tree.id) == "", "采集指令接受可见资源")
	_advance(sim, 2)
	_check(sim.resources[0].wood == previous_wood, "资源必须运回基地后才入账")
	_advance(sim, 38)
	_check(sim.resources[0].wood > previous_wood and sim.stats.gathered >= 12, "工人采集并运回资源形成持续经济")
	_check(tree.amount < 650 and worker.carry <= 12, "资源扣减与负重上限正确")
	var food: Dictionary = sim._nearest_resource(worker.pos, "food")
	_check(sim.command([worker.id], "gather", food.pos, food.id) == "", "携带枝材时可重新分配采集穗粮")
	_advance(sim, 45)
	_check(sim.resources[0].food > 280, "重新分配后资源按正确种类交付")
	_check(sim.command([99999], "move", Vector2(20, 20)) != "", "死亡或无效选中 ID 返回反馈")
	sim.resources[0] = {"food": 0, "wood": 0, "crystal": 0}
	var count: int = sim.entities.size()
	_check(sim.build("house", Vector2(31, 58), [worker.id]) != "" and sim.entities.size() == count, "资源不足不会生成免费建筑")
	_check(sim.research() != "" and sim.tech[0] == 0, "研发需要真实支付资源")

func _test_construction_production() -> void:
	var sim := _new()
	var workers := _ids(sim, "worker")
	var initial_pop: Vector2i = sim.population(0)
	_check(initial_pop == Vector2i(6, 10), "初始人口包含工人与战斗单位")
	_check(not sim.can_place("house", Vector2(18, 58)), "阻止建筑重叠")
	_check(not sim.can_place("tower", Vector2(0, 0)), "阻止越界建造")
	_check(sim.build("house", Vector2(31, 58), workers) == "", "工人可在空地创建施工建筑")
	var house := _find(sim, "house")
	_check(sim.resources[0].wood == 270 and house.built == 0.0, "建造时准确扣费且需要施工")
	_check(sim.population(0).y == 10, "未完工住宅不增加人口上限")
	_advance(sim, 25)
	_check(house.built >= 1.0 and sim.population(0).y == 16, "多名工人走到现场后完成建筑并增加人口")
	_check(sim.build("barracks", Vector2(17, 45), workers) == "", "创建兵营")
	var barracks := _find(sim, "barracks")
	_check(sim.train(barracks.id, "guard") != "", "施工中的建筑禁止生产")
	_advance(sim, 25)
	_check(barracks.built >= 1.0, "兵营可以完工")
	var old_food: int = sim.resources[0].food
	_check(sim.train(barracks.id, "guard") == "" and sim.resources[0].food == old_food - 60, "生产入队时准确扣费")
	_check(sim.population(0).x == 7, "生产队列预占人口")
	_advance(sim, 13)
	_check(_ids(sim, "guard").size() == 2 and barracks.queue.is_empty(), "生产完成并出生可操作单位")
	var heart := _find(sim, "heart")
	_check(sim.train(heart.id, "breaker") == "", "基地招募中心可生产攻坚职业")
	sim.resources[0] = {"food": 10000, "wood": 10000, "crystal": 10000}
	var accepted := 0
	for i in range(6):
		if sim.train(barracks.id, "ranger") == "":
			accepted += 1
	_check(accepted == 5 and barracks.queue.size() == 5, "生产队列最多五个且拒绝额外扣费")
	_check(sim.research() == "" and sim.tech[0] == 1, "研发共鸣锻造成功")
	var after_research: Dictionary = sim.resources[0].duplicate()
	_check(sim.research() != "" and sim.resources[0] == after_research, "重复研发不扣费")
	var capped := _new()
	capped.resources[0].food = 10000
	var capped_heart := _find(capped, "heart")
	for i in range(4):
		capped.train(capped_heart.id, "worker")
	_check(capped.population(0) == Vector2i(10, 10) and capped.train(capped_heart.id, "worker") != "", "人口限制在排队时生效")

func _test_orders_paths_fog() -> void:
	var sim := _new()
	var worker := _find(sim, "worker")
	_check(sim.is_visible(Vector2(18, 58)) and not sim.is_visible(Vector2(62, 22)), "视野不会提前揭露敌方基地")
	_check(not sim.is_explored(Vector2(35, 32)), "未探索区域保持未知")
	_check(sim.build("house", Vector2(75, 60), [worker.id]) != "", "战争迷雾内禁止远程建造")
	# Route across the headquarters footprint must use the navigable perimeter.
	worker.pos = Vector2(11, 58)
	_check(sim.command([worker.id], "move", Vector2(25, 58)) == "", "移动到基地另一侧")
	var entered_building := false
	for i in range(120):
		sim.step(0.1)
		if worker.pos.distance_to(Vector2(18, 58)) < 2.5:
			entered_building = true
	_check(not entered_building and worker.pos.distance_to(Vector2(25, 58)) < 2, "AStar 寻路绕开建筑且能到达目标")
	_check(sim.command([worker.id], "move", Vector2(35, 32)) == "", "单位可向未探索区域移动")
	_advance(sim, 20)
	_check(sim.is_visible(Vector2(35, 32)) and sim.is_explored(Vector2(35, 32)), "侦察单位实际揭露迷雾")
	sim.command([worker.id], "move", Vector2(18, 58))
	_advance(sim, 20)
	_check(sim.is_explored(Vector2(35, 32)) and not sim.is_visible(Vector2(35, 32)), "离开后保留探索记录而隐藏实时视野")
	sim.command([worker.id], "stop")
	var stopped: Vector2 = worker.pos
	_advance(sim, 2)
	_check(worker.pos == stopped and worker.state == "idle", "停止指令清空移动意图")
	_check(sim.command([worker.id], "move", Vector2(-1, 8)) != "", "越界指令提供反馈")
	var guards := _ids(sim, "guard")
	var tree: Dictionary = sim._nearest_resource(Vector2(18, 58), "wood")
	_check(sim.command(guards, "gather", tree.pos, tree.id) != "", "军事单位不能执行工人采集任务")
	var before: float = sim.elapsed
	sim.step(0.0)
	sim.step(-1.0)
	_check(sim.elapsed == before, "暂停或无效时间不会推进状态")

func _test_combat_results() -> void:
	var sim := _new()
	var guard := _find(sim, "guard")
	var ranger := _find(sim, "ranger", 1)
	guard.pos = Vector2(39, 40)
	ranger.pos = Vector2(40, 40)
	sim._update_fog()
	var hp: float = ranger.hp
	_check(sim.command([guard.id], "attack", ranger.pos, ranger.id) == "", "可攻击视野内敌人")
	sim.step(0.1)
	_check(is_equal_approx(float(ranger.hp), hp - 24.0), "棱盾卫克制弦光手的伤害倍率正确")
	var before_hp: float = guard.hp
	_advance(sim, 4)
	_check(sim.entity(ranger.id).is_empty() and sim.stats.kills > 0 and guard.hp < before_hp, "单位实战互相攻击并清理死亡目标")
	sim.command([guard.id], "stop")
	var breaker: Dictionary = sim._spawn("breaker", 0, Vector2(58, 22))
	var heart := _find(sim, "heart", 1)
	# Isolate siege behavior from escorts while retaining the real target HP.
	for e in sim.entities:
		if e.team == 1 and Data.UNITS.has(e.kind):
			e.pos = Vector2(78, 78)
	sim._update_fog()
	_check(sim.command([breaker.id], "attack", heart.pos, heart.id) == "", "攻坚单位接受基地目标")
	sim.step(0.1)
	_check(heart.hp == 1140.0, "裂岩兽对建筑造成 2.5 倍伤害")
	_advance(sim, 40)
	_check(sim.result == "win" and sim.entity(heart.id).is_empty(), "通过真实攻击摧毁敌方基地触发胜利")
	var end_time: float = sim.elapsed
	sim.step(1)
	_check(sim.elapsed == end_time and sim.train(_find(sim, "heart").id, "worker") != "", "结算后停止模拟并拒绝生产")
	var defeat := _new()
	var attacker: Dictionary = defeat._spawn("breaker", 1, Vector2(14, 58))
	for e in defeat.entities:
		if e.team == 0 and Data.UNITS.has(e.kind):
			e.pos = Vector2(1, 1)
	defeat._update_fog()
	var player_heart := _find(defeat, "heart")
	defeat.command([attacker.id], "attack", player_heart.pos, player_heart.id)
	_advance(defeat, 45)
	_check(defeat.result == "lose", "己方基地被真实摧毁触发失败")
	var tower_sim := _new()
	var tower: Dictionary = tower_sim._spawn("tower", 0, Vector2(38, 40))
	var target: Dictionary = tower_sim._spawn("guard", 1, Vector2(46, 40))
	tower_sim._update_fog()
	tower_sim.step(0.1)
	_check(target.hp < target.max_hp and tower.cooldown > 0, "哨塔在射程内自动攻击")

func _test_save_transaction() -> void:
	var sim := _new()
	var worker := _find(sim, "worker")
	var tree: Dictionary = sim._nearest_resource(worker.pos, "wood")
	sim.command([worker.id], "gather", tree.pos, tree.id)
	sim.train(_find(sim, "heart").id, "worker")
	_advance(sim, 5)
	var encoded := JSON.stringify(sim.save_dict())
	var decoded: Variant = JSON.parse_string(encoded)
	_check(decoded is Dictionary and encoded.contains('"pos":['), "完整存档可通过 JSON 序列化")
	var loaded := _new()
	_check(loaded.load_dict(decoded), "读取合法存档")
	_check(loaded.entities.size() == sim.entities.size() and loaded.resources == sim.resources and is_equal_approx(loaded.elapsed, sim.elapsed), "读档恢复实体、资源和比赛时间")
	_check(_find(loaded, "heart").queue == ["worker"] and _find(loaded, "worker").state == worker.state, "读档恢复生产与采集指令")
	_advance(loaded, 30)
	_check(loaded.stats.gathered > 0 and _ids(loaded, "worker").size() == 5, "读档后采集和生产继续正常完成")
	var snapshot: String = JSON.stringify(loaded.save_dict())
	var malformed: Dictionary = decoded.duplicate(true)
	malformed.entities[0].pos = ["invalid", 4]
	_check(not loaded.load_dict(malformed) and JSON.stringify(loaded.save_dict()) == snapshot, "坐标损坏的存档被原子拒绝")
	malformed = decoded.duplicate(true)
	malformed.entities[1].id = malformed.entities[0].id
	_check(not loaded.load_dict(malformed) and JSON.stringify(loaded.save_dict()) == snapshot, "重复实体 ID 被拒绝且不改变现有比赛")
	malformed = decoded.duplicate(true)
	malformed.resources[0].food = -100
	_check(not loaded.load_dict(malformed), "拒绝负数资源存档")
	malformed = decoded.duplicate(true)
	malformed.entities[0].queue = ["untrusted_kind"]
	_check(not loaded.load_dict(malformed), "拒绝未知生产类型存档")
	malformed = decoded.duplicate(true)
	malformed.erase("explored")
	_check(not loaded.load_dict(malformed), "缺失迷雾数据不会引发崩溃")
	_check(not loaded.load_dict({}) and JSON.stringify(loaded.save_dict()) == snapshot, "空存档被拒绝且现有比赛不变")
	var deterministic := _new()
	var twin := _new()
	for match_sim in [deterministic, twin]:
		var unit := _find(match_sim, "worker")
		match_sim.command([unit.id], "move", Vector2(35, 45))
		_advance(match_sim, 10)
	_check(JSON.stringify(deterministic.save_dict()) == JSON.stringify(twin.save_dict()), "相同初始状态和指令产生一致模拟结果")

func _test_ai() -> void:
	var sim := Sim.new()
	sim.set_difficulty("standard")
	var initial_food: int = sim.resources[1].food
	_advance(sim, 75)
	var barracks := _find(sim, "barracks", 1)
	_check(not barracks.is_empty() and barracks.built >= 1.0, "AI 真实安排工人完成兵营")
	_check(_ids(sim, "worker", 1).size() >= 6, "AI 支付资源生产额外工人")
	_check(sim.entities.filter(func(e): return e.team == 1 and Data.UNITS.has(e.kind) and e.kind != "worker").size() >= 4, "AI 使用生产队列发展军队")
	_check(sim.resources[1].food != initial_food and _find(sim, "berry", -1).amount <= 650, "AI 执行经济活动")
	_advance(sim, 35)
	var raid := false
	for event in sim.events:
		if event.type == "raid":
			raid = true
	_check(raid, "AI 在约 90 秒后发起真实进攻")
	var near_player := false
	for e in sim.entities:
		if e.team == 1 and Data.UNITS.has(e.kind) and e.kind != "worker" and e.pos.distance_to(Vector2(18, 58)) < 30:
			near_player = true
	_check(near_player, "AI 军队确实穿越地图接近玩家")
	_advance(sim, 210)
	_check(sim.elapsed >= 110 and sim.entities.size() < 300 and sim.population(1).x <= 80, "持续运行期间单位规模与人口保持有界")
	print("AI smoke: elapsed=", sim.elapsed, " result=", sim.result, " team1_resources=", sim.resources[1], " entities=", sim.entities.size())

func _test_complete_match() -> void:
	# End-to-end rules test: ordinary costs, construction and orders against the
	# real AI, with no spawned army, resource grants or enemy health edits.
	var sim := Sim.new()
	var workers := _ids(sim, "worker")
	_check(sim.build("barracks", Vector2(17, 45), workers) == "", "完整对局从合法建造兵营开始")
	var last_raid := 0.0
	var production_index := 0
	for tick in range(6000):
		if sim.result != "":
			break
		if tick % 30 == 0:
			var player_workers := _ids(sim, "worker")
			var heart := _find(sim, "heart")
			if not heart.is_empty() and player_workers.size() + heart.queue.size() < 8:
				sim.train(heart.id, "worker")
			var incomplete := false
			for e in sim.entities:
				if e.team == 0 and Data.BUILDINGS.has(e.kind) and e.built < 1.0:
					incomplete = true
			for i in range(player_workers.size()):
				var worker: Dictionary = sim.entity(player_workers[i])
				if worker.state not in ["idle", "move"]:
					continue
				var resource: String = ["wood", "food", "food", "crystal", "wood", "food", "food", "wood"][i % 8]
				var node: Dictionary = sim._nearest_resource(worker.pos, resource)
				sim.command([worker.id], "gather", node.pos, node.id)
			if not incomplete and not player_workers.is_empty() and sim.population(0).y - sim.population(0).x < 3:
				for point in [Vector2(31, 58), Vector2(39, 53), Vector2(25, 38), Vector2(14, 36), Vector2(32, 32), Vector2(17, 70)]:
					if sim.can_place("house", point) and sim.is_visible(point):
						sim.build("house", point, [player_workers[0]])
						break
			var barracks := _find(sim, "barracks")
			if not barracks.is_empty() and barracks.built >= 1.0 and barracks.queue.size() < 2:
				var kinds := ["breaker", "ranger", "guard", "breaker", "ranger"]
				if sim.train(barracks.id, kinds[production_index % kinds.size()]) == "":
					production_index += 1
			if sim.elapsed > 180:
				sim.research()
			if sim.elapsed > 120 and sim.elapsed - last_raid >= 24:
				var troops: Array = []
				for e in sim.entities:
					if e.team == 0 and Data.UNITS.has(e.kind) and e.kind != "worker":
						troops.append(e.id)
				if troops.size() >= 5:
					sim.command(troops, "attack", Vector2(62, 22))
					last_raid = sim.elapsed
		sim.step(0.1)
	_check(sim.result == "win", "正常经济、生产和编队进攻可在十分钟内击败真实 AI")
	print("Complete match: elapsed=", sim.elapsed, " result=", sim.result, " resources=", sim.resources[0], " stats=", sim.stats)
