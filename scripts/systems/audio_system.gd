extends Node

# ---------------------------------------------------
# 音：効果音とBGMを、音の波形からコードで作る（音源ファイルは使わない）。
#   効果音（SOUNDS）: 建設・撤去・エレベーターの到着・決算・警報・操作できないとき
#   BGM: 和音をゆっくり鳴らすループ。時間帯（朝・昼・夕方・夜）で和音の流れと速さを変え、
#        ビルの★が上がるほど音を重ねて豪華にする（★2: 低音 / ★3: 分散和音 / ★4: 鐘 / ★5: 細かい分散和音）
#   M キーで音を消したり出したりできる。
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
# BGM: 時間帯ごとの和音の流れ（周波数の組み合わせ）と、1つの和音を鳴らす秒数。from: その時間帯が始まる時刻（分）
const BGM_RATE := 11025 # BGMの標本数（効果音より粗くして、作る手間を減らす）
const PERIODS := {
	"morning": {"name": "朝", "from": 5 * 60, "seconds": 2.0,
		"chords": [[262.0, 330.0, 392.0], [196.0, 247.0, 294.0], [220.0, 262.0, 330.0], [175.0, 220.0, 262.0]]},
	"day": {"name": "昼", "from": 10 * 60, "seconds": 1.6,
		"chords": [[262.0, 330.0, 392.0], [294.0, 370.0, 440.0], [220.0, 277.0, 330.0], [247.0, 311.0, 370.0]]},
	"evening": {"name": "夕方", "from": 17 * 60, "seconds": 2.4,
		"chords": [[175.0, 220.0, 262.0, 330.0], [196.0, 247.0, 294.0, 349.0], [165.0, 208.0, 247.0, 330.0], [220.0, 262.0, 330.0, 392.0]]},
	"night": {"name": "夜", "from": 20 * 60, "seconds": 3.0,
		"chords": [[196.0, 233.0, 294.0], [175.0, 220.0, 262.0], [147.0, 185.0, 220.0], [165.0, 196.0, 247.0]]},
}
const PERIOD_ORDER := ["morning", "day", "evening", "night"]

var world: Node2D # main.gd
var muted := false
var sounds := {}          # 名前 -> AudioStreamWAV
var players: Array = []   # 効果音を鳴らすプレイヤー（順番に使い回す）
var next_player := 0
var last_played := {}     # 名前 -> 最後に鳴らした時刻（秒）
var bgm_player: AudioStreamPlayer
var bgm_key := []         # 今鳴らしているBGM [時間帯, ★]
var bgm_cache := {}       # [時間帯, ★] -> 作ったBGM（同じ組み合わせは作り直さない）
var bgm_tasks := {}       # [時間帯, ★] -> 裏で作っている作業の番号（WorkerThreadPool）
var bgm_made := {}        # 裏で作り終えたBGM（作業の側から書き込むので、bgm_mutex で守る）
var bgm_mutex := Mutex.new()

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
	var first := current_bgm_key()
	bgm_cache[first] = make_bgm(PERIODS[first[0]], first[1]) # 最初の曲だけは、その場で作る
	set_bgm(first)

func _process(_delta: float) -> void:
	# 時間帯が変わったり★が上がったりしたら、BGMを切り替える。
	# まだ作っていない曲は裏で作り（1曲に0.1秒ほどかかり、ゲームが一瞬止まるため）、できあがるまでは前の曲を流す
	collect_made_bgm()
	var key := current_bgm_key()
	if key != bgm_key:
		if bgm_cache.has(key):
			set_bgm(key)
		elif not bgm_tasks.has(key):
			var period: Dictionary = PERIODS[key[0]]
			bgm_tasks[key] = WorkerThreadPool.add_task(func():
				var stream := make_bgm(period, key[1])
				bgm_mutex.lock()
				bgm_made[key] = stream
				bgm_mutex.unlock())

# 裏で作り終えた曲を受け取る
func collect_made_bgm() -> void:
	for key in bgm_tasks.keys():
		if WorkerThreadPool.is_task_completed(bgm_tasks[key]):
			WorkerThreadPool.wait_for_task_completion(bgm_tasks[key]) # 終わった作業を片づける（待たない）
			bgm_tasks.erase(key)
			bgm_mutex.lock()
			bgm_cache[key] = bgm_made[key]
			bgm_made.erase(key)
			bgm_mutex.unlock()

# 作っている途中の曲を待つ（ゲームを閉じるときに、裏の作業を残さないように）
func _exit_tree() -> void:
	for key in bgm_tasks:
		WorkerThreadPool.wait_for_task_completion(bgm_tasks[key])

# 今の時刻の時間帯（PERIODS のキー）
func period_for(minute: int) -> String:
	var result := "night" # 0時〜5時は、前の日の夜の続き
	for period in PERIOD_ORDER:
		if minute >= PERIODS[period].from:
			result = period
	return result

# 今鳴らすべきBGM [時間帯, ★]
func current_bgm_key() -> Array:
	var stars: int = world.rating_system.stars if world.rating_system else 1
	return [period_for(world.clock.minute_of_day()), stars]

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

# 音を消す・戻す（Mキー）
func toggle_mute() -> bool:
	muted = not muted
	if muted:
		bgm_player.stop()
	else:
		bgm_player.play()
	world.show_message("音を%sにしました（Mキーで切り替え）" % ("オフ" if muted else "オン"))
	return muted

# BGMを [時間帯, ★] の曲で鳴らし直す（作ったことのある曲は、覚えておいたものを使う）
func set_bgm(key: Array) -> void:
	bgm_key = key
	bgm_player.stream = bgm_cache[key]
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

# BGM: 和音を順に鳴らすループ。★が上がるほど音を重ねる
#   ★1: 和音 / ★2: ＋低音（和音の一番下の音の1オクターブ下）/ ★3: ＋分散和音（和音の音を1オクターブ上で順に鳴らす）
#   ★4: ＋鐘（和音の始まりに、高い音が響いて消える）/ ★5: 分散和音を倍の細かさにする
func make_bgm(period: Dictionary, stars: int) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	var count := int(period.seconds * BGM_RATE)
	var steps: int = 16 if stars >= 5 else 8 # 分散和音を1つの和音の間に何回鳴らすか
	for chord in period.chords:
		var step_length := count / steps
		for i in count:
			var t := float(i) / count
			var time := float(i) / BGM_RATE
			var value := 0.0
			for freq in chord:
				value += sin(TAU * time * freq) / chord.size() # 和音
			var layers := 1.0
			if stars >= 2: # 低音
				value += 0.5 * sin(TAU * time * chord[0] * 0.5)
				layers += 0.5
			if stars >= 3: # 分散和音（1音ずつ、はじいたように鳴らして消える）
				var step := i / step_length
				var within := float(i % step_length) / step_length
				var note: float = chord[step % chord.size()] * 2.0
				value += 0.35 * sin(TAU * time * note) * exp(-within * 5.0)
				layers += 0.35
			if stars >= 4: # 鐘（和音の始まりに鳴って、ゆっくり消える）
				value += 0.3 * sin(TAU * time * chord[0] * 4.0) * exp(-t * 6.0)
				layers += 0.3
			# 和音の始まりと終わりをなめらかにする（ぷつっと切れないように）
			samples.append(value / layers * 0.5 * minf(1.0, minf(t, 1.0 - t) * 8.0))
	var stream := to_stream(samples, true)
	stream.mix_rate = BGM_RATE
	return stream

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
