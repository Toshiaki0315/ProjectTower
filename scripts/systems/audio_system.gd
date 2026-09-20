extends Node

# ---------------------------------------------------
# 音：効果音とBGMを、音の波形からコードで作る（音源ファイルは使わない）。
#   効果音（SOUNDS）: 建設・撤去・エレベーターの到着・決算・警報・操作できないとき
#   BGM: 和音をゆっくり鳴らすループ。昼と夜で和音を変える
#   ⌘M で音を消したり出したりできる。
# 音を鳴らしすぎないよう、同じ効果音は COOLDOWN 秒に1回までにする。
# ---------------------------------------------------

const RATE := 22050      # 1秒あたりの標本数
const COOLDOWN := 0.15   # 同じ効果音を続けて鳴らさない間隔（秒）
const SFX_PLAYERS := 6   # 同時に鳴らせる効果音の数
const SFX_VOLUME := -12.0 # 効果音の音量（dB）
const BGM_VOLUME := -24.0 # BGMの音量（dB）

# 効果音の作り方
#   notes:  [周波数, 長さ（秒）] の並び（順番に鳴らす）
#   wave:   "square"（かたい音） / "sine"（やわらかい音） / "noise"（ざらざらした音）
#   sweep:  音の高さを終わりまでに何倍にするか（1.0なら変えない）
const SOUNDS := {
	"build":    {"notes": [[660.0, 0.05], [880.0, 0.08]], "wave": "square", "sweep": 1.0},
	"demolish": {"notes": [[220.0, 0.16]], "wave": "noise", "sweep": 0.5},
	"chime":    {"notes": [[988.0, 0.12], [740.0, 0.2]], "wave": "sine", "sweep": 1.0},
	"money":    {"notes": [[784.0, 0.07], [988.0, 0.07], [1319.0, 0.18]], "wave": "square", "sweep": 1.0},
	"alert":    {"notes": [[880.0, 0.18], [660.0, 0.18], [880.0, 0.18], [660.0, 0.18]], "wave": "square", "sweep": 1.0},
	"error":    {"notes": [[160.0, 0.18]], "wave": "square", "sweep": 0.8},
}
# BGM: 昼と夜で鳴らす和音（周波数の組み合わせ）。1つの和音を CHORD_SECONDS 秒ずつ鳴らす
const CHORD_SECONDS := 2.0
const DAY_CHORDS := [[262.0, 330.0, 392.0], [294.0, 370.0, 440.0], [220.0, 277.0, 330.0], [247.0, 311.0, 370.0]]
const NIGHT_CHORDS := [[196.0, 233.0, 294.0], [175.0, 220.0, 262.0], [147.0, 185.0, 220.0], [165.0, 196.0, 247.0]]

var world: Node2D # main.gd
var muted := false
var sounds := {}          # 名前 -> AudioStreamWAV
var players: Array = []   # 効果音を鳴らすプレイヤー（順番に使い回す）
var next_player := 0
var last_played := {}     # 名前 -> 最後に鳴らした時刻（秒）
var bgm_player: AudioStreamPlayer
var bgm_night := false    # 今、夜のBGMを鳴らしているか

func setup(p_world: Node2D) -> void:
	world = p_world
	for name in SOUNDS:
		sounds[name] = make_sound(SOUNDS[name])
	for i in SFX_PLAYERS:
		var player := AudioStreamPlayer.new()
		player.volume_db = SFX_VOLUME
		add_child(player)
		players.append(player)
	bgm_player = AudioStreamPlayer.new()
	bgm_player.volume_db = BGM_VOLUME
	add_child(bgm_player)
	set_bgm(false)

func _process(_delta: float) -> void:
	# 夜になったらBGMを夜の和音に切り替える（朝になったら戻す）
	var night: bool = world.clock.darkness() > 0.5
	if night != bgm_night:
		set_bgm(night)

# 効果音を鳴らす（同じ音が続けて鳴らないように少し間を空ける）
func play(name: String) -> void:
	if muted or not sounds.has(name):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - last_played.get(name, -999.0) < COOLDOWN:
		return
	last_played[name] = now
	var player: AudioStreamPlayer = players[next_player]
	next_player = (next_player + 1) % players.size()
	player.stream = sounds[name]
	player.play()

# 音を消す・戻す（⌘M）
func toggle_mute() -> bool:
	muted = not muted
	if muted:
		bgm_player.stop()
	else:
		bgm_player.play()
	world.show_message("音を%sにしました（⌘Mで切り替え）" % ("オフ" if muted else "オン"))
	return muted

# BGMを昼／夜の和音で鳴らし直す
func set_bgm(night: bool) -> void:
	bgm_night = night
	bgm_player.stream = make_bgm(NIGHT_CHORDS if night else DAY_CHORDS)
	if not muted:
		bgm_player.play()

# ---------------------------------------------------
# 音の波形を作る
# ---------------------------------------------------

# 効果音: notes を順に鳴らした波形
func make_sound(info: Dictionary) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	for note in info.notes:
		var freq: float = note[0]
		var count := int(note[1] * RATE)
		for i in count:
			var t := float(i) / count                      # 0〜1（その音の中での進み具合）
			var phase := float(i) / RATE * freq * lerpf(1.0, info.sweep, t)
			var value := wave_value(info.wave, phase, i)
			samples.append(value * envelope(t))
	return to_stream(samples, false)

# BGM: 和音を順に鳴らすループ
func make_bgm(chords: Array) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	var count := int(CHORD_SECONDS * RATE)
	for chord in chords:
		for i in count:
			var t := float(i) / count
			var value := 0.0
			for freq in chord:
				value += sin(TAU * float(i) / RATE * freq) / chord.size()
			# 和音の始まりと終わりをなめらかにする（ぷつっと切れないように）
			samples.append(value * 0.5 * minf(1.0, minf(t, 1.0 - t) * 8.0))
	return to_stream(samples, true)

# 波の形（かたい音・やわらかい音・ざらざらした音）
func wave_value(wave: String, phase: float, index: int) -> float:
	match wave:
		"square":
			return 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
		"noise":
			return sin(float(index) * 12.9898) * 43758.5453 - floor(sin(float(index) * 12.9898) * 43758.5453) - 0.5
		_:
			return sin(TAU * phase)

# 音の入り・終わりをなめらかにする（0〜1の進み具合に対する音量）
func envelope(t: float) -> float:
	return minf(1.0, minf(t * 40.0, (1.0 - t) * 6.0))

# 波形（-1〜1）を16ビットの音データに変える
func to_stream(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var value := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream
