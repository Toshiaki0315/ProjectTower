extends Node2D

# ---------------------------------------------------
# 空のイベント：ゲームの進み方には関係しない、眺めて楽しむための背景の出来事。
#   昼（DAY_FROM〜DAY_TO）:
#     飛行機   … 1日に数回、飛行機雲を引いて空を横切る（雨の日は飛ばない）
#     鳥の群れ … V字に並んだ鳥が、羽ばたきながら渡っていく（雨の日は飛ばない）
#     気球     … 晴れた休日に、ゆっくり流れていく
#     虹       … 雨の次の日（雨でなければ）、朝のうちに空にかかる
#   夜（NIGHT_FROM〜翌 NIGHT_TO）:
#     流れ星   … 一晩に何度か、すっと流れる（雨の夜は見えない）
#     ロケット … ときどき、遠くの地平線から炎と煙を引いて打ち上がる
#     UFO     … ごくまれに、ふらふらと空を漂って去っていく
#     花火     … 夏（7・8月）の休日の夜に、次々と打ち上がる
# その日に何が起きるかは日付から作る乱数で決める（同じ日なら毎回同じ。セーブしなくてよい）。
# 空は画面に映っている範囲に描く背景なので、位置は画面の空に対する割合で持つ
# （カメラを動かしても空の同じ場所に見える。太陽・月・サンタと同じ）。建物の後ろに隠れる。
# TileMapLayerの子として追加するので、座標はタイルマップ座標系。
# ---------------------------------------------------

const DAY_FROM := 7 * 60
const DAY_TO := 17 * 60
const NIGHT_FROM := 20 * 60
const NIGHT_TO := 4 * 60          # 翌朝のこの時刻まで
const AIRPLANES := [2, 4]         # 1日に飛ぶ飛行機の数（最小・最大）
const AIRPLANE_MINUTES := 40.0    # 空を横切るのにかかる時間（分）
const BIRD_FLOCKS := [1, 3]
const BIRD_MINUTES := 60.0
const BALLOON_CHANCE := 0.5       # 晴れた休日に気球が飛ぶ確率
const BALLOON_MINUTES := 240.0
const RAINBOW_FROM := 6 * 60 + 30
const RAINBOW_TO := 10 * 60 + 30
const RAINBOW_FADE := 30.0        # 虹が現れる・消えるのにかかる時間（分）
const SHOOTING_STARS := [3, 7]
const SHOOTING_STAR_MINUTES := 2.0
const ROCKET_CHANCE := 0.2        # 一晩にロケットが打ち上がる確率
const ROCKET_MINUTES := 25.0
const UFO_CHANCE := 0.04          # 一晩にUFOが現れる確率
const UFO_MINUTES := 50.0
const FIREWORKS_FROM := 19 * 60 + 30
const FIREWORKS_TO := 20 * 60 + 30
const FIREWORK_EVERY := 2.0       # 花火が打ち上がる間隔（分）
const FIREWORK_MINUTES := 5.0     # 1発が上がって開き、消えるまで（分）
const FIREWORK_MONTHS := [7, 8]
const FIREWORK_COLORS := [Color(1.0, 0.4, 0.4), Color(1.0, 0.85, 0.3), Color(0.5, 0.9, 1.0), Color(0.6, 1.0, 0.5), Color(1.0, 0.55, 0.95)]
const RAINBOW_COLORS := [Color("#ff4b4b"), Color("#ff9f40"), Color("#ffe14d"), Color("#5fd35f"), Color("#4db8ff"), Color("#5b6cff"), Color("#a65bff")]

var world: Node2D # main.gd
var cache := {} # 日 -> その日のイベントの一覧（events_for() の結果。毎フレーム作り直さないように）

func setup(p_world: Node2D) -> void:
	world = p_world
	z_index = -4 # 空の色（-5）より手前、建物のタイル（0）より奥

func _process(_delta: float) -> void:
	queue_redraw()

# ---------------------------------------------------
# その日のイベントの予定
#   1つのイベント: {"kind": 種類, "start": 始まる時刻（その日の0時からの分。夜の分は24時を超えてよい）,
#                   "length": 続く分, "x": 横の位置（0〜1）, "y": 高さ（0: 空の上端 〜 1: 地平線）, "dir": 進む向き（1: 右へ / -1: 左へ）}
# ---------------------------------------------------
func events_for(day: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([day, "sky"])
	var events: Array = []
	var weather = world.weather_system
	var rainy: bool = weather.weather_for(day) == weather.Weather.RAINY
	var md: Array = world.clock.date(day)
	if not rainy:
		for i in rng.randi_range(AIRPLANES[0], AIRPLANES[1]):
			events.append(make_event(rng, "airplane", DAY_FROM, DAY_TO - AIRPLANE_MINUTES, AIRPLANE_MINUTES, 0.1, 0.4))
		for i in rng.randi_range(BIRD_FLOCKS[0], BIRD_FLOCKS[1]):
			events.append(make_event(rng, "birds", DAY_FROM, DAY_TO - BIRD_MINUTES, BIRD_MINUTES, 0.3, 0.6))
		if weather.weather_for(day) == weather.Weather.SUNNY and world.clock.is_holiday(day) and rng.randf() < BALLOON_CHANCE:
			events.append(make_event(rng, "balloon", 9 * 60, 12 * 60, BALLOON_MINUTES, 0.25, 0.5))
		if weather.weather_for(day - 1) == weather.Weather.RAINY: # 雨上がり
			events.append({"kind": "rainbow", "start": RAINBOW_FROM, "length": RAINBOW_TO - RAINBOW_FROM, "x": 0.5, "y": 1.0, "dir": 1})
		for i in rng.randi_range(SHOOTING_STARS[0], SHOOTING_STARS[1]):
			events.append(make_event(rng, "shooting_star", NIGHT_FROM, 24 * 60 + NIGHT_TO - 10, SHOOTING_STAR_MINUTES, 0.05, 0.4))
	if rng.randf() < ROCKET_CHANCE:
		var rocket := make_event(rng, "rocket", NIGHT_FROM + 30, 24 * 60 + 2 * 60, ROCKET_MINUTES, 1.0, 1.0)
		rocket.x = rng.randf_range(0.15, 0.85)
		events.append(rocket)
	if rng.randf() < UFO_CHANCE:
		events.append(make_event(rng, "ufo", 22 * 60, 24 * 60 + 2 * 60, UFO_MINUTES, 0.15, 0.35))
	if FIREWORK_MONTHS.has(md[0]) and world.clock.is_holiday(day) and not rainy:
		var t := float(FIREWORKS_FROM)
		while t < FIREWORKS_TO:
			var burst := make_event(rng, "firework", 0, 0, FIREWORK_MINUTES, 0.15, 0.4)
			burst.start = t
			burst.x = rng.randf_range(0.15, 0.85)
			burst["color"] = rng.randi_range(0, FIREWORK_COLORS.size() - 1)
			events.append(burst)
			t += FIREWORK_EVERY * rng.randf_range(0.5, 1.5)
	return events

func make_event(rng: RandomNumberGenerator, kind: String, from: float, to: float, length: float, y_min: float, y_max: float) -> Dictionary:
	return {"kind": kind, "start": rng.randf_range(from, to), "length": length, "x": rng.randf(),
		"y": rng.randf_range(y_min, y_max), "dir": 1 if rng.randf() < 0.5 else -1}

# 今起きているイベントと、その進み具合（0〜1）の一覧 [[イベント, 進み具合], ...]
# 夜のイベントは日付をまたぐので、前の日の予定の続きも見る
func active_events() -> Array:
	var result: Array = []
	var now: float = world.clock.minute
	for offset in [0, 1]:
		var day: int = world.clock.day - offset
		if day < 1:
			continue
		for e in day_events(day):
			var t: float = (now + offset * 24 * 60 - e.start) / e.length
			if t >= 0.0 and t < 1.0:
				result.append([e, t])
	return result

func day_events(day: int) -> Array:
	if not cache.has(day):
		if cache.size() > 4:
			cache.clear() # 古い日の予定は捨てる
		cache[day] = events_for(day)
	return cache[day]

# 今そのイベントが起きているか（テストと、カーソルの説明などで使う）
func is_active(kind: String) -> bool:
	return active_events().any(func(item): return item[0].kind == kind)

# ---------------------------------------------------
# 描く
# ---------------------------------------------------
func _draw() -> void:
	var tile_size := Vector2(world.tile_map.tile_set.tile_size)
	var visible_rect: Rect2 = get_global_transform_with_canvas().affine_inverse() * get_viewport_rect()
	var sky_bottom: float = (world.ground_y + 1) * tile_size.y # 地平線（1階の床の下端）
	if visible_rect.position.y >= sky_bottom:
		return # 空が映っていない
	var sky := Rect2(visible_rect.position, Vector2(visible_rect.size.x, sky_bottom - visible_rect.position.y))
	for item in active_events():
		var e: Dictionary = item[0]
		var t: float = item[1]
		match e.kind:
			"airplane": draw_airplane(sky, e, t)
			"birds": draw_birds(sky, e, t)
			"balloon": draw_balloon(sky, e, t)
			"rainbow": draw_rainbow(sky, t)
			"shooting_star": draw_shooting_star(sky, e, t)
			"rocket": draw_rocket(sky, e, t)
			"ufo": draw_ufo(sky, e, t)
			"firework": draw_firework(sky, e, t)

# 空を横切るものの位置（dir の向きに、画面の外から外へ）
func crossing(sky: Rect2, e: Dictionary, t: float, margin := 40.0) -> Vector2:
	var along: float = t if e.dir > 0 else 1.0 - t
	return Vector2(sky.position.x - margin + (sky.size.x + margin * 2.0) * along, sky.position.y + sky.size.y * e.y)

func draw_airplane(sky: Rect2, e: Dictionary, t: float) -> void:
	var pos := crossing(sky, e, t).floor()
	var d: float = e.dir
	# 飛行機雲（後ろほど薄い）
	for i in 12:
		var puff := pos + Vector2(-d * (6 + i * 4) - 2, 0)
		draw_rect(Rect2(puff, Vector2(4, 1)), Color(1, 1, 1, 0.55 - i * 0.045))
	var body := Color(0.95, 0.95, 0.97)
	draw_rect(Rect2(pos + Vector2(-4, 0), Vector2(9, 2)), body) # 胴体
	draw_rect(Rect2(pos + Vector2(-4 if d > 0 else 4, -2), Vector2(1, 2)), body) # 尾翼
	draw_rect(Rect2(pos + Vector2(-1, 1), Vector2(3, 2)), Color(0.8, 0.82, 0.86)) # 主翼
	draw_rect(Rect2(pos + Vector2(3 if d > 0 else -4, 0), Vector2(1, 1)), Color(0.3, 0.5, 0.8)) # 操縦席の窓
	if fmod(t * 40.0, 1.0) < 0.5:
		draw_rect(Rect2(pos + Vector2(0, 3), Vector2.ONE), Color(1, 0.2, 0.2)) # 点滅する灯り

func draw_birds(sky: Rect2, e: Dictionary, t: float) -> void:
	var lead := crossing(sky, e, t).floor()
	var flap := int(t * 120.0) % 2 # 羽ばたき
	var color := Color(0.15, 0.15, 0.2)
	for i in 5:
		var row := (i + 1) / 2 # V字: 先頭の後ろに左右交互に並ぶ
		var side := -1 if i % 2 == 1 else 1
		var bird := lead + Vector2(-e.dir * row * 5, side * row * 3)
		if flap == 0:
			draw_rect(Rect2(bird + Vector2(-2, -1), Vector2(2, 1)), color)
			draw_rect(Rect2(bird + Vector2(1, -1), Vector2(2, 1)), color)
		else:
			draw_rect(Rect2(bird + Vector2(-2, 0), Vector2(2, 1)), color)
			draw_rect(Rect2(bird + Vector2(1, 0), Vector2(2, 1)), color)
		draw_rect(Rect2(bird + Vector2(0, 0), Vector2(1, 1)), color)

func draw_balloon(sky: Rect2, e: Dictionary, t: float) -> void:
	var pos := crossing(sky, e, t, 20.0) + Vector2(0, sin(t * TAU * 3.0) * 3.0)
	pos = pos.floor()
	var stripes := [Color(1.0, 0.35, 0.35), Color(1.0, 0.85, 0.3), Color(0.35, 0.6, 1.0)]
	var widths := [3, 5, 6, 6, 6, 5, 4, 3] # 上から下へ、丸くすぼまる形
	for row in widths.size():
		var w: int = widths[row]
		for col in w:
			draw_rect(Rect2(pos + Vector2(col - w / 2, row), Vector2.ONE), stripes[(col + row / 3) % stripes.size()])
	draw_line(pos + Vector2(-1, 8), pos + Vector2(-1, 11), Color(0.4, 0.3, 0.2), 0.5) # 綱
	draw_line(pos + Vector2(1, 8), pos + Vector2(1, 11), Color(0.4, 0.3, 0.2), 0.5)
	draw_rect(Rect2(pos + Vector2(-1, 11), Vector2(3, 2)), Color(0.55, 0.36, 0.2)) # かご

func draw_rainbow(sky: Rect2, t: float) -> void:
	var minutes: float = t * (RAINBOW_TO - RAINBOW_FROM)
	var alpha := clampf(minutes / RAINBOW_FADE, 0.0, 1.0) * clampf((RAINBOW_TO - RAINBOW_FROM - minutes) / RAINBOW_FADE, 0.0, 1.0)
	var radius := minf(sky.size.x * 0.32, sky.size.y * 0.9)
	var band := maxf(radius * 0.035, 1.5)
	var center := Vector2(sky.position.x + sky.size.x * 0.62, sky.end.y - band) # 地平線から立ち上がる（地面の下には描かない）
	for i in RAINBOW_COLORS.size():
		draw_arc(center, radius - i * band, PI, TAU, 64, Color(RAINBOW_COLORS[i], 0.32 * alpha), band)

func draw_shooting_star(sky: Rect2, e: Dictionary, t: float) -> void:
	var start := Vector2(sky.position.x + sky.size.x * e.x, sky.position.y + sky.size.y * e.y)
	var dir := Vector2(e.dir * 1.0, 0.45).normalized()
	var head := start + dir * sky.size.x * 0.25 * t
	var fade := 1.0 - t
	draw_line(head - dir * 18.0, head, Color(1, 1, 0.9, 0.35 * fade), 1.0)
	draw_line(head - dir * 8.0, head, Color(1, 1, 0.95, 0.8 * fade), 1.0)
	draw_rect(Rect2(head.floor(), Vector2.ONE), Color(1, 1, 1, fade))

func draw_rocket(sky: Rect2, e: Dictionary, t: float) -> void:
	# 地平線から、だんだん速く真上へ（少し傾きながら）昇っていく
	var rise := 0.3 * t + 0.7 * t * t
	var base := Vector2(sky.position.x + sky.size.x * e.x, sky.end.y)
	var pos := (base + Vector2(e.dir * 30.0 * rise, -(sky.size.y + 40.0) * rise)).floor()
	var puffs := int(pos.distance_to(base) / 2.0) + 1 # 煙（地平線のほうへ長く伸びて、ふくらみながら薄くなる）
	for i in puffs:
		var k := float(i) / puffs
		var smoke := pos.lerp(base, k) + Vector2(0, 7)
		if smoke.y + 4 > sky.end.y:
			continue # 地平線より下（地面）には描かない
		var size := 2.0 + k * 7.0
		draw_rect(Rect2(smoke - Vector2(size / 2.0, 0), Vector2(size, 4)), Color(0.8, 0.8, 0.86, 0.6 * (1.0 - k)))
	var flicker := int(t * 100.0) % 2
	draw_rect(Rect2(pos + Vector2(-1, 5), Vector2(3, 2 + flicker)), Color(1.0, 0.6, 0.15)) # 炎
	draw_rect(Rect2(pos + Vector2(0, 5), Vector2(1, 3 + flicker)), Color(1.0, 0.95, 0.5))
	draw_rect(Rect2(pos + Vector2(-1, 0), Vector2(3, 5)), Color(0.92, 0.92, 0.95)) # 機体
	draw_rect(Rect2(pos + Vector2(0, -1), Vector2(1, 1)), Color(0.9, 0.3, 0.3))   # 先端

func draw_ufo(sky: Rect2, e: Dictionary, t: float) -> void:
	var pos := crossing(sky, e, t) + Vector2(sin(t * TAU * 5.0) * 12.0, sin(t * TAU * 7.0) * 6.0) # ふらふら漂う
	pos = pos.floor()
	draw_rect(Rect2(pos + Vector2(-1, -2), Vector2(3, 2)), Color(0.6, 0.95, 1.0, 0.9)) # 窓
	draw_rect(Rect2(pos + Vector2(-4, 0), Vector2(9, 2)), Color(0.7, 0.72, 0.78))      # 円盤
	for i in 3: # 順に光る灯り
		var on := (int(t * 60.0) + i) % 3 == 0
		draw_rect(Rect2(pos + Vector2(-3 + i * 3, 1), Vector2.ONE), Color(1.0, 0.9, 0.3) if on else Color(0.4, 0.4, 0.45))
	if fmod(t * 6.0, 1.0) < 0.3: # ときどき下を照らす
		draw_colored_polygon(PackedVector2Array([pos + Vector2(-2, 2), pos + Vector2(3, 2), pos + Vector2(7, 14), pos + Vector2(-6, 14)]),
			Color(0.7, 1.0, 0.8, 0.18))

func draw_firework(sky: Rect2, e: Dictionary, t: float) -> void:
	var color: Color = FIREWORK_COLORS[e.color]
	var burst := Vector2(sky.position.x + sky.size.x * e.x, sky.position.y + sky.size.y * e.y)
	var rise_part := 0.25 # 最初の4分の1は、火の玉が昇っていく
	if t < rise_part:
		var k := t / rise_part
		var pos := Vector2(burst.x, sky.end.y).lerp(burst, k).floor()
		draw_rect(Rect2(pos, Vector2(1, 2)), Color(1.0, 0.9, 0.6))
		return
	var k := (t - rise_part) / (1.0 - rise_part) # 開いてから消えるまで
	var radius := 4.0 + 18.0 * sqrt(k)
	var alpha := 1.0 - k
	for i in 16:
		var angle := TAU * i / 16.0
		var spark := burst + Vector2(cos(angle), sin(angle)) * radius + Vector2(0, k * k * 6.0) # 少し垂れ下がる
		draw_rect(Rect2(spark.floor(), Vector2.ONE * (2.0 if k < 0.5 else 1.0)), Color(color, alpha))
		var inner := burst + Vector2(cos(angle + 0.2), sin(angle + 0.2)) * radius * 0.55 + Vector2(0, k * k * 4.0)
		draw_rect(Rect2(inner.floor(), Vector2.ONE), Color(color.lightened(0.4), alpha * 0.8))
