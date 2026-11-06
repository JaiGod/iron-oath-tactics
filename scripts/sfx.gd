extends Node
## Procedural sound effects: every sound is synthesized into an AudioStreamWAV at startup.

const RATE := 22050
var sounds := {}
var players: Array = []
var idx := 0

func _ready() -> void:
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		players.append(p)
	sounds["select"] = _tone([[660, 0.05], [880, 0.06]], "sq", 0.25)
	sounds["move"] = _tone([[330, 0.04], [392, 0.04]], "tri", 0.35)
	sounds["hit"] = _noise(0.16, 900.0, 0.55)
	sounds["crit"] = _mix(_noise(0.28, 1400.0, 0.6), _tone([[180, 0.25]], "saw", 0.35))
	sounds["miss"] = _tone([[520, 0.05], [300, 0.09]], "tri", 0.3)
	sounds["heal"] = _tone([[523, 0.08], [659, 0.08], [784, 0.14]], "sin", 0.4)
	sounds["magic"] = _tone([[300, 0.06], [600, 0.06], [1200, 0.12]], "saw", 0.22)
	sounds["level"] = _tone([[523, 0.09], [659, 0.09], [784, 0.09], [1047, 0.22]], "sq", 0.25)
	sounds["win"] = _tone([[392, 0.14], [523, 0.14], [659, 0.14], [784, 0.4]], "tri", 0.45)
	sounds["lose"] = _tone([[392, 0.2], [330, 0.2], [262, 0.5]], "tri", 0.45)
	sounds["phase"] = _tone([[262, 0.1], [392, 0.18]], "sq", 0.2)
	sounds["build"] = _mix(_noise(0.1, 500.0, 0.5), _tone([[220, 0.12]], "sq", 0.3))
	sounds["death"] = _tone([[220, 0.12], [165, 0.12], [110, 0.3]], "saw", 0.3)

func play(name: String) -> void:
	if not Game.sound_on or not sounds.has(name) or DisplayServer.get_name() == "headless":
		return
	var p: AudioStreamPlayer = players[idx]
	idx = (idx + 1) % players.size()
	p.stream = sounds[name]
	p.play()

func _wav(data: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clamp(data[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w

func _tone(notes: Array, wave: String, vol: float) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	for n in notes:
		var f: float = n[0]
		var count := int(RATE * float(n[1]))
		for i in count:
			var t := float(i) / RATE
			var ph := fmod(t * f, 1.0)
			var s := 0.0
			match wave:
				"sq": s = 1.0 if ph < 0.5 else -1.0
				"saw": s = ph * 2.0 - 1.0
				"tri": s = 4.0 * abs(ph - 0.5) - 1.0
				_: s = sin(TAU * ph)
			var env: float = min(1.0, i / 120.0) * (1.0 - float(i) / count)
			out.append(s * env * vol)
	return _wav(out)

func _noise(dur: float, cutoff: float, vol: float) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	var count := int(RATE * dur)
	var y := 0.0
	var a: float = clamp(cutoff / RATE * 6.0, 0.01, 1.0)
	var r := RandomNumberGenerator.new()
	r.seed = 99
	for i in count:
		y += (r.randf_range(-1, 1) - y) * a
		var env := pow(1.0 - float(i) / count, 2.0)
		out.append(y * env * vol * 2.5)
	return _wav(out)

func _mix(a: AudioStreamWAV, b: AudioStreamWAV) -> AudioStreamWAV:
	var n: int = max(a.data.size(), b.data.size()) / 2
	var out := PackedFloat32Array()
	for i in n:
		var s := 0.0
		if i * 2 < a.data.size():
			s += a.data.decode_s16(i * 2) / 32000.0
		if i * 2 < b.data.size():
			s += b.data.decode_s16(i * 2) / 32000.0
		out.append(s * 0.7)
	return _wav(out)
