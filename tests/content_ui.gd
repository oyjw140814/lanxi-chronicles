extends RefCounted
var checks := 0
var failures := 0
func check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("CONTENT_UI ","PASS " if ok else "FAIL ",detail)

func run(game) -> int:
	var input = load("res://tests/runtime_input.gd").new()
	game._new_game()
	game.sim.ai_enabled = false
	game.tutorial_active = false
	game._refresh_hud()
	await input.frame(game)
	if await input.click_card(game,"招募"):
		check(game.hud._page == "recruit" and game.paused,"底部招募打开中央面板并暂停")
		var bounds: Rect2 = game.hud._modal_panel.get_global_rect()
		check(bounds.get_center().distance_to(game.get_viewport().get_visible_rect().get_center()) < 1.0,"招募面板位于屏幕中央")
		var food: int = game.sim.resources[0].food
		if await input.click_card(game,"招募工人"):
			check(game.sim.resources[0].food == food-45 and game.sim._heart(0).queue == ["worker"],"点击招募工人扣粮并加入真实队列")
		if await input.click_card(game,"招募骑士"):
			check("rider" in game.sim._heart(0).queue,"骑士招募按钮加入真实队列")
		var commands: int = game.sim.stats.commands
		await input.mouse(game,Vector2(20,200))
		check(game.sim.stats.commands == commands,"招募面板禁止指令穿透")
		game.sim.resources[0].food = 0
		if await input.click_card(game,"招募射手"):
			check("资源不足" in game.hud._recruit_feedback and "ranger" not in game.sim._heart(0).queue,"招募失败在面板内提示且不入队")
		await game._capture("06-recruitment")
		if await input.click_card(game,"返回战场"):
			check(not game.paused and not game.hud.is_modal_open(),"返回战场继续训练")
		for tick in range(320): game.sim.step(0.1)
		check(game.sim.entities.any(func(e): return e.team == 0 and e.kind == "rider"),"骑士生产完成进入可操作战场")
	game._new_game()
	game.sim.ai_enabled = false
	game.tutorial_active = false
	game._refresh_hud()
	game._update_threats()
	check(game.hud._warning_time == 0.0,"未见敌人时不发出位置警报")
	var enemy: Dictionary = game.sim._spawn("rider",1,Vector2(25,55))
	game.sim._update_fog()
	game._update_threats()
	check(game.hud._warning_time > 0.0 and game.hud._warning_effect.remaining > 0.0,"敌军进入视野触发横幅与边缘特效")
	var next_time: float = game._next_threat
	game._update_threats()
	check(game._next_threat == next_time,"持续可见敌人不会反复触发警报")
	await game.get_tree().create_timer(0.15).timeout
	await game._capture("07-enemy-alert")
	if await input.click_card(game,"敌军进入视野"):
		check(game.camera_focus.distance_to(game._threat_point) < 0.5,"点击警报镜头定位发现位置")
	game._new_game()
	game.sim.ai_enabled = false
	game.tutorial_active = false
	# Gallery uses original models and the production renderer, without AI modifications.
	game.set_process(false)
	game.sim.entities.clear()
	game.sim._by_id.clear()
	var index := 0
	for kind in game.Data.UNITS:
		game.sim._spawn(kind,0,Vector2(25+index*2.4,55))
		index += 1
	game.camera_focus = Vector2(31,55)
	game._update_camera()
	game.camera.size = 13.0
	game.sim._update_fog()
	game.world._fog_clock = 1.0
	game.world.sync(game.sim.entities,[],game.sim,0.05)
	for visual in game.world.visuals.values(): visual.art.rotation.y = -PI*0.75
	game.hud._root.visible = false
	await game._capture("08-professions-closeup")
	for entity in game.sim.entities:
		var visual: Dictionary = game.world.visuals[entity.id]
		if entity.kind == "breaker": continue
		check(visual.art.get_meta("body").has_node("ArmR/Elbow"),"关节与装备骨架存在："+entity.kind)
		var body: Node3D = visual.art.get_meta("body")
		game.world._animate_unit(visual,entity,0.1,true)
		check(absf(body.get_node("LegL").rotation.x) > 0.001,"行走动作驱动腿部："+entity.kind)
	game.hud._root.visible = true
	game.set_process(true)
	game._new_game()
	check(game.hud._warning_time == 0.0,"重开清除旧警报")
	failures += input.failures
	print("CONTENT_UI_SUMMARY checks=",checks," failures=",failures)
	return failures
