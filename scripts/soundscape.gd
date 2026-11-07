extends Node
## All audio is synthesized here; no sampled third-party sound assets.
var volume := 0.55
var music_enabled := true
var voices: Array[AudioStreamPlayer] = []
var ambient: AudioStreamPlayer
var samples: Dictionary = {}
var last_attack := 0.0
const HarvestSounds = preload("res://scripts/harvest_sounds.gd")
var harvest_samples: Dictionary = {}
var harvest_voices: Array[AudioStreamPlayer] = []
var _resource_next: Dictionary = {}
var _worker_next: Dictionary = {}
var _harvest_variant: Dictionary = {}
var _harvest_paused := false

func _ready() -> void:
	for i in range(8):
		var player := AudioStreamPlayer.new()
		add_child(player)
		voices.append(player)
	for key in ["select", "order", "build", "train", "attack", "win", "error", "alert"]:
		samples[key] = _tone(key)
	for resource in ["food", "wood", "crystal"]:
		harvest_samples[resource] = []
		for variant in range(3):
			harvest_samples[resource].append(HarvestSounds.make(resource, variant))
	# Separate voices keep economic ambience from stealing alerts/UI cues.
	for i in range(3):
		var player := AudioStreamPlayer.new()
		add_child(player)
		harvest_voices.append(player)
	ambient = AudioStreamPlayer.new()
	add_child(ambient)
	ambient.stream = _ambient()
	apply(volume, music_enabled)
	ambient.play()

func apply(level: float, music: bool = true) -> void:
	volume = clampf(level, 0.0, 1.0)
	music_enabled = music
	if ambient:
		ambient.volume_db = linear_to_db(maxf(0.0001, volume * (0.3 if music else 0.0)))
	for player in harvest_voices:
		player.volume_db = linear_to_db(maxf(0.0001, volume * float(player.get_meta("gain", 0.0))))
		if volume <= 0.0: player.stop()

func play_harvest(resource: String, worker_id: int, audibility: float) -> bool:
	if _harvest_paused or volume <= 0.0 or audibility <= 0.01 or not harvest_samples.has(resource):
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if now < float(_resource_next.get(resource, 0.0)) or now < float(_worker_next.get(worker_id, 0.0)):
		return false
	for player in harvest_voices:
		if player.playing: continue
		var variant := int(_harvest_variant.get(resource, 0))
		player.stream = harvest_samples[resource][variant % 3]
		var active := harvest_voices.filter(func(voice): return voice.playing).size()
		var gain := 0.34 * clampf(audibility, 0.0, 1.0) / sqrt(1.0 + active)
		player.set_meta("gain", gain)
		player.volume_db = linear_to_db(maxf(0.0001, volume * gain))
		player.play()
		_harvest_variant[resource] = variant + 1
		_resource_next[resource] = now + 0.65
		# Prune expired worker entries so long games do not accumulate dead IDs.
		for id in _worker_next.keys():
			if float(_worker_next[id]) <= now: _worker_next.erase(id)
		_worker_next[worker_id] = now + 1.1
		return true
	return false

func set_harvest_paused(value: bool) -> void:
	if value == _harvest_paused: return
	_harvest_paused = value
	if value: reset_harvest()

func reset_harvest() -> void:
	for player in harvest_voices:
		player.stop()
		player.stream = null
	_resource_next.clear()
	_worker_next.clear()
	_harvest_variant.clear()

func _exit_tree() -> void:
	# Release both the stream and playback before removing the owning node.
	for player in voices + harvest_voices:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	if is_instance_valid(ambient):
		ambient.stop()
		ambient.stream = null
	samples.clear()
	harvest_samples.clear()
	voices.clear()
	harvest_voices.clear()

func play_cue(key: String) -> void:
	if not samples.has(key) or volume <= 0.0:
		return
	if key == "attack":
		var now := Time.get_ticks_msec() / 1000.0
		if now - last_attack < 0.18:
			return
		last_attack = now
	for player in voices:
		if not player.playing:
			player.stream = samples[key]
			player.volume_db = linear_to_db(maxf(0.0001, volume * 0.28))
			player.play()
			return

func _tone(key: String) -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.16
	var freq := 660.0
	match key:
		"order": freq = 440.0
		"build":
			freq = 330.0
			duration = 0.42
		"train":
			freq = 784.0
			duration = 0.32
		"attack":
			freq = 115.0
			duration = 0.1
		"error":
			freq = 175.0
			duration = 0.25
		"alert":
			freq = 392.0
			duration = 0.85
		"win":
			freq = 523.25
			duration = 1.5
	var count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		var t := float(i) / sample_rate
		var envelope := minf(t * 65.0, 1.0) * pow(1.0 - t / duration, 2.0)
		var f := freq
		if key == "win":
			f *= [1.0, 1.25, 1.5, 2.0][mini(3, int(t * 3.0))]
		if key == "alert": f *= 1.5 if int(t*5.0)%2 == 1 else 1.0
		var wave := sin(TAU * f * t) * 0.7 + sin(TAU * f * 2.0 * t) * 0.15
		data.encode_s16(i * 2, int(wave * envelope * 22000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.data = data
	return wav

func _ambient() -> AudioStreamWAV:
	var sample_rate := 11025
	var duration := 16.0
	var count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	var notes := [130.8128, 164.8138, 195.9977, 261.6256, 293.6648, 195.9977, 164.8138, 146.8324]
	for i in range(count):
		var t := float(i) / sample_rate
		var wave := 0.0
		for n in range(8):
			var since := fposmod(t - n * 2.0, duration)
			if since < 5.0:
				var env := minf(since * 3.0, 1.0) * exp(-since * 0.9) * clampf(5.0 - since, 0.0, 1.0)
				wave += sin(TAU * notes[n] * since) * env * 0.2
		data.encode_s16(i * 2, int(clampf(wave, -1.0, 1.0) * 18000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = count
	return wav
