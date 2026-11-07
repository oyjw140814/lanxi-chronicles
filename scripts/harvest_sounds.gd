extends RefCounted
## Original soft foley: filtered leaf/fibre noise and damped resonances.
## Local seeded noise never changes the simulation's random sequence.
const RATE := 22050

static func make(resource: String, variant: int) -> AudioStreamWAV:
	var duration := 0.62 if resource == "crystal" else 0.48
	var count := int(RATE * duration)
	var values := PackedFloat32Array()
	values.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4919 + variant * 101 + resource.hash()
	var pitch: float = [0.965, 1.0, 1.035][posmod(variant, 3)]
	var filtered := 0.0
	var soft_noise := 0.0
	var peak := 0.001
	for i in range(count):
		var t := float(i) / RATE
		filtered = lerpf(filtered, rng.randf_range(-1.0, 1.0), 0.22)
		soft_noise = lerpf(soft_noise, filtered, 0.18)
		var wave := 0.0
		match resource:
			"food":
				# Rounded fruit pluck, a tiny basket tap, and a soft leaf brush.
				wave = sin(TAU * pitch * (420.0*t + 2.2*(1.0-exp(-t*35.0)))) * exp(-t*26.0) * 0.42
				wave += sin(TAU * 784.0 * pitch * t) * exp(-t*16.0) * 0.12
				wave += sin(TAU * 1176.0 * pitch * t) * exp(-t*25.0) * 0.025
				wave += soft_noise * (exp(-t*9.0)*0.65 + exp(-pow((t-0.16)/0.06, 2.0))*0.15)
			"wood":
				# Muted wooden body; no sharp axe/metal transient.
				wave = sin(TAU * 185.0 * pitch * t) * exp(-t*22.0) * 0.48
				wave += sin(TAU * 342.0 * pitch * t) * exp(-t*30.0) * 0.24
				wave += sin(TAU * 566.0 * pitch * t) * exp(-t*42.0) * 0.09
				wave += soft_noise * (exp(-t*32.0)*1.3 + exp(-pow((t-0.12)/0.05, 2.0))*0.22)
			"crystal":
				# Low, rounded mineral chime with a short, mellow tail.
				wave = sin(TAU * 659.25 * pitch * t) * exp(-t*9.0) * 0.30
				wave += sin(TAU * 988.88 * pitch * t) * exp(-t*12.0) * 0.10
				wave += sin(TAU * 1648.13 * pitch * t) * exp(-t*20.0) * 0.025
				wave += soft_noise * exp(-t*32.0) * 0.32
		# Raised-cosine attack and release avoid clicks at both ends.
		var attack := 0.5 - 0.5*cos(PI*minf(t/0.008, 1.0))
		var release := 0.5 - 0.5*cos(PI*minf((duration-t)/0.08, 1.0))
		values[i] = wave * attack * release
		peak = maxf(peak, absf(values[i]))
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in range(count):
		bytes.encode_s16(i*2, int(values[i] / peak * 18000.0))
	var sample := AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate = RATE
	sample.data = bytes
	return sample
