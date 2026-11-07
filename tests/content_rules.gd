extends SceneTree
const Sim = preload("res://scripts/simulation.gd")
const Data = preload("res://scripts/game_data.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("CONTENT ","PASS " if ok else "FAIL ",detail)

func run() -> void:
	var sim := Sim.new()
	var raids: Array = []
	for tick in range(4700):
		sim.step(0.1)
		for event in sim.events:
			if event.type == "raid": raids.append(event.duplicate())
		sim.events.clear()
	check(sim.difficulty == "relaxed", "新局默认休闲人机")
	check(raids.is_empty() and sim.result == "" and sim._heart(0).hp == 1200.0, "无操作至 7 分 50 秒，AI 未主动出征、基地无损")
	var military := sim.entities.filter(func(e): return e.team == 1 and Data.UNITS.has(e.kind) and e.kind != "worker")
	check(military.size() <= 6 and sim.tech[1] == 0, "早期敌军规模受限，尚未研究强化")
	for tick in range(1800):
		sim.step(0.1)
		for event in sim.events:
			if event.type == "raid": raids.append(event.duplicate())
		sim.events.clear()
	check(not raids.is_empty() and raids[0].time >= 480 and raids[0].count <= 2,"首波不早于 8 分钟且最多 2 人")
	check(raids.size() <= 2 and (raids.size() < 2 or raids[1].time-raids[0].time >= 149.9),"波次间隔至少 150 秒")
	print("RELAXED_SAMPLE elapsed=",sim.elapsed," result=",sim.result," raids=",raids)
	sim.set_difficulty("standard")
	sim.set_difficulty("relaxed")
	check(sim._raid_clock >= sim.elapsed+179.9,"切换休闲至少留出 3 分钟准备")
	check(sim.entities.all(func(e): return e.team != 1 or not Data.UNITS.has(e.kind) or e.kind == "worker" or e.state == "move"),"切换休闲让敌方部队回营")
	var fresh := Sim.new()
	fresh.ai_enabled = false
	fresh.resources[0] = {"food":3000,"wood":3000,"crystal":3000}
	fresh._spawn("house",0,Vector2(30,57))
	fresh._spawn("house",0,Vector2(34,57))
	for kind in Data.UNITS:
		var before: int = fresh.resources[0].food
		check(fresh.train(fresh._heart(0).id,kind) == "" and fresh.resources[0].food == before-Data.COSTS[kind].food,"招募扣除食物："+kind)
		for tick in range(220): fresh.step(0.1)
		check(fresh.entities.any(func(e): return e.team == 0 and e.kind == kind) and fresh._heart(0).queue.is_empty(),"职业可生产并完成队列："+kind)
	var rider: Dictionary = fresh._spawn("rider",0,Vector2(40,30))
	var ranger: Dictionary = fresh._spawn("ranger",1,Vector2(42,30))
	fresh._deal_damage(rider,ranger,19.0)
	check(is_equal_approx(ranger.hp,85.0-19.0*1.8),"骑士克制射手倍率正确")
	var lancer: Dictionary = fresh._spawn("lancer",0,Vector2(40,33))
	var enemy_rider: Dictionary = fresh._spawn("rider",1,Vector2(42,33))
	fresh._deal_damage(lancer,enemy_rider,14.0)
	check(is_equal_approx(enemy_rider.hp,195.0-14.0*2.2),"枪卫克制骑士倍率正确")
	var target: Dictionary = fresh._spawn("guard",0,Vector2(42,36))
	fresh._deal_damage(enemy_rider,target,19.0)
	check(is_equal_approx(target.hp,165.0-19.0*0.7),"休闲敌军伤害降低 30%")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(fresh.save_dict()))
	var restored := Sim.new()
	check(restored.load_dict(saved) and restored.difficulty == "relaxed" and restored.entities.any(func(e): return e.kind == "rider"),"新职业与难度随存档恢复")
	saved.erase("difficulty")
	saved.raid_clock = 90.0
	check(restored.load_dict(saved) and restored._raid_clock >= restored.elapsed+179.9,"旧存档迁移到休闲并获得准备时间")
	saved.difficulty = "invalid"
	check(not restored.load_dict(saved),"拒绝非法难度存档")
	print("CONTENT_SUMMARY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
