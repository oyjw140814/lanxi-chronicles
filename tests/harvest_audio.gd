extends SceneTree
## Rule events, controller routing and PCM checks. Use --audio-driver Dummy
## to verify real software mixing independently of physical device availability.
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("HARVEST_AUDIO ", "PASS " if ok else "FAIL ", detail)

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280,800)
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH, true)
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(0, capture)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game._test_running = true
	await process_frame
	await process_frame
	game._new_game()
	game.set_process(false)
	game.sim.ai_enabled = false
	game.audio.apply(0.55, false)
	game.audio.set_harvest_paused(false)
	var audio = game.audio
	DirAccess.make_dir_recursive_absolute("res://builds/harvest-audio")
	var hashes: Array[int] = []
	for resource in ["food", "wood", "crystal"]:
		for index in range(3):
			var sample: AudioStreamWAV = audio.harvest_samples[resource][index]
			var bytes := sample.data
			var peak := 0
			var energy := 0.0
			for i in range(bytes.size()/2):
				var value := bytes.decode_s16(i*2)
				peak = maxi(peak, absi(value))
				energy += pow(float(value)/32768.0, 2.0)
			var rms := sqrt(energy / (bytes.size()/2))
			check(sample.mix_rate == 22050 and bytes.size() >= 20000 and rms > 0.03 and rms < 0.2 and peak <= 18001, resource+str(index)+" audible PCM with headroom")
			check(bytes.decode_s16(0) == 0 and absi(bytes.decode_s16(bytes.size()-2)) <= 1, resource+str(index)+" click-free endpoints")
			check(not hash(bytes) in hashes, resource+str(index)+" distinct timbre/variation")
			hashes.append(hash(bytes))
			sample.save_to_wav("res://builds/harvest-audio/%s-%d.wav" % [resource,index])
	# Actual resource extraction is the trigger, not selection or walking.
	for resource in ["food", "wood", "crystal"]:
		var sim = load("res://scripts/simulation.gd").new()
		sim.ai_enabled = false
		var worker: Dictionary = sim.entities.filter(func(e): return e.team == 0 and e.kind == "worker")[0]
		var target: Dictionary = sim._nearest_resource(worker.pos, resource)
		sim.command([worker.id], "gather", target.pos, target.id)
		worker.pos = Vector2(40,40)
		sim.events.clear()
		sim._update_gather(worker,target,0.1)
		check(not sim.events.any(func(e): return e.type == "harvest"), resource+" no sound while approaching")
		worker.pos = target.pos + Vector2(float(target.radius)+0.65,0)
		var amount: int = target.amount
		for i in range(8): sim._update_gather(worker,target,0.1)
		var events: Array = sim.events.filter(func(e): return e.type == "harvest")
		check(events.size() == 1 and events[0].resource == resource and events[0].amount == 2 and worker.carry == 2 and target.amount == amount-2, resource+" real extraction emits matching sound event")
		sim.events.clear()
		worker.carry = 12
		sim._update_gather(worker,target,0.8)
		check(worker.state == "return" and sim.events.is_empty(), resource+" no harvesting sound while returning")
		worker.carry = 0
		target.amount = 0
		sim._update_gather(worker,target,0.8)
		check(sim.events.is_empty(), resource+" depleted resource stays silent")
	# Simultaneous workers do not produce a wall of repeated sounds.
	check(audio.play_harvest("food", 1, 1.0), "first harvest plays")
	var accepted := 0
	for i in range(80):
		if audio.play_harvest("food", 10+i, 1.0): accepted += 1
	check(accepted == 0, "80 simultaneous workers are rate limited")
	check(audio.play_harvest("wood", 2, 1.0), "simultaneous different resources do not starve")
	check(audio.play_harvest("crystal", 3, 1.0), "third resource has its own voice")
	var deadline := Time.get_ticks_msec() + 750
	while Time.get_ticks_msec() < deadline: await process_frame
	var buffer := capture.get_buffer(capture.get_frames_available())
	var mixed_peak := 0.0
	for sample in buffer: mixed_peak = maxf(mixed_peak, maxf(absf(sample.x),absf(sample.y)))
	print("AUDIO_MIX frames=",buffer.size()," peak=",mixed_peak)
	check(buffer.size() > 0 and mixed_peak > 0.01 and mixed_peak < 0.8, "software mixer outputs audible non-clipping samples")
	check(audio.harvest_voices.size() == 3 and audio.voices.size() == 8, "bounded harvesting pool preserves alert voices")
	audio.apply(0.0,false)
	check(not audio.harvest_voices.any(func(p): return p.playing) and not audio.play_harvest("crystal",3,1.0), "mute stops current and future harvesting")
	audio.apply(0.55,false)
	audio.set_harvest_paused(true)
	check(not audio.play_harvest("food",1,1.0), "paused game cannot start harvest sound")
	audio.set_harvest_paused(false)
	check(audio.play_harvest("food",1,1.0), "resume permits new harvesting")
	audio.reset_harvest()
	check(audio._worker_next.is_empty() and not audio.harvest_voices.any(func(p): return p.playing), "reset clears old workers and tails")
	check(not audio.play_harvest("food",1,0.0) and not audio.play_harvest("invalid",1,1.0), "inaudible and unknown sources stay silent")
	# The production event consumer applies team, pause, fog and camera filters.
	var event := {"type":"harvest","team":0,"id":1,"resource":"wood","point":Vector2(21,55),"amount":2}
	game.sim.events.clear()
	game.sim.events.append(event)
	game._consume_events()
	check(audio._harvest_variant.get("wood",0) == 1, "controller routes visible nearby work to sound")
	for reason in ["enemy","offscreen","fog","pause"]:
		audio.reset_harvest()
		var hidden := event.duplicate()
		if reason == "enemy": hidden.team = 1
		if reason == "offscreen":
			game.camera_focus = Vector2(68,15)
			game._update_camera()
		if reason == "fog": hidden.point = Vector2(68,15)
		if reason == "pause": game.paused = true
		game.sim.events.clear()
		game.sim.events.append(hidden)
		game._consume_events()
		check(audio._harvest_variant.is_empty(), reason+" does not leak harvest audio")
		game.paused = false
		game.camera_focus = Vector2(21,55)
		game._update_camera()
	# Exercise normal SceneTree shutdown, as the standalone app does.
	print("HARVEST_AUDIO_SUMMARY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
