extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("ART_RESULT ","PASS " if ok else "FAIL ",message)
func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280,800)
	var game = load("res://scripts/main.gd").new()
	root.add_child(game)
	game._test_running = true
	await process_frame
	await process_frame
	game._new_game()
	game.set_process(false)
	game.audio.apply(0.0,false)
	var heart: Dictionary = game.sim._heart(1)
	game.sim._spawn("worker",0,heart.pos+Vector2(4,0)) # Explicit final-heart visual fixture.
	game.sim._update_fog()
	game.camera_focus = heart.pos
	game._update_camera()
	game.world.sync(game.sim.entities,[],game.sim,0.0)
	heart.hp = 0.0
	game.sim._cleanup_dead()
	game._consume_events()
	var elapsed: float = game.sim.elapsed
	check(game.sim.result == "win" and game.sim.entity(heart.id).is_empty(),"胜负和基地移除立即结算")
	for i in range(8): game._process(0.1)
	check(not game._result_shown and not game.paused and game.world.battle_fx.stats().remains==1,"先播放最终基地倒塌")
	game._on_action("pause",null)
	var time: float = game._result_visual_clock
	for i in range(10): game._process(0.1)
	check(game._result_visual_clock == time and not game._result_shown,"显式暂停冻结倒塌及结算面板延时")
	game._on_action("resume",null)
	for i in range(9): game._process(0.1)
	check(game._result_shown and game.paused and game.hud.is_modal_open(),"恢复后自动显示原有胜利面板")
	check(game.sim.elapsed==elapsed,"视觉收尾不推进规则时间或AI")
	check(game.sim.command([game.sim.entities[0].id],"move",Vector2(40,40)) != "","规则结束后不再接受玩法命令")
	game._new_game()
	check(game._result_visual_clock==0.0 and not game._result_shown,"重开清零结果过渡")
	game.queue_free()
	await process_frame
	print("ART_RESULT_SUMMARY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
