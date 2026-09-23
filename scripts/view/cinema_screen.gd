extends Node2D

# ---------------------------------------------------
# 映画館のスクリーン：上映中・開場中・閉館の違いを、スクリーンの見た目で表す。
#   閉館（CinemaState.CLOSED）  … 赤い幕が閉じている
#   開場中（CinemaState.OPEN）  … 幕が開いて、スクリーンは白いまま（次の上映を待っている）
#   上映中（CinemaState.SHOWING）… スクリーンに映画が映る。場内の明かりが落ち、
#                                   後ろの映写室からスクリーンへ光が伸びる
# 映画は上映が始まってからの時間で移り変わる:
#   はじめの COUNTDOWN_MINUTES 分 … カウントダウン（円の中を線が回る）
#   本編 … SCENE_MINUTES 分ごとに「夕日の海」「夜の街」「草原を走る人」を順に映す
#   終わりの CREDITS_MINUTES 分 … エンドロール（黒地に白い文字の行が流れる）
# 動きはゲーム内の時刻で決める（早送りすると映画も早く進む）。
# 位置は映画館のドット絵（横8マス×高さ2階。1マス16ドット）に合わせてある。
# TileMapLayerの子として追加するので、座標はタイルマップ座標系。
# ---------------------------------------------------

const SCREEN := Rect2(6, 4, 28, 16)  # スクリーンの白い部分（映画館の左上から見たドット）
const MOVIE := Rect2(9, 6, 22, 14)   # 映画が映る部分（左右の幕と上の飾り幕を除いた内側）
const SIDE_CURTAIN := 3              # 開いたときに左右に残る幕の幅
const VALANCE := 2                   # 上の飾り幕の高さ
const BOOTH := Vector2(122, 6)       # 映写室の窓（光が出るところ）
const HALL := Rect2(0, 1, 128, 29)   # 場内（天井と床の線を除く）
const HALL_DIM := Color(0.0, 0.0, 0.05, 0.45) # 上映中に場内にかける暗さ
const BEAM_COLOR := Color(1.0, 0.97, 0.8, 0.12) # 映写の光
const CURTAIN_COLOR := Color("#9a1f2e")
const CURTAIN_FOLD := Color("#6e1420")  # 幕のひだ（暗い筋）
const CURTAIN_LIGHT := Color("#c0394a") # 幕のひだ（明るい筋）
const VALANCE_COLOR := Color("#d9a441") # 飾り幕の金色
const COUNTDOWN_MINUTES := 5.0
const CREDITS_MINUTES := 10.0
const SCENE_MINUTES := 35.0

var world: Node2D # main.gd

func setup(p_world: Node2D) -> void:
	world = p_world
	z_index = 6 # タイルやマス目の表示より手前、住人より奥

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var cinemas: Array[Vector2i] = world.find_units_of_type("cinema")
	if cinemas.is_empty():
		return
	var visitors = world.visitor_system
	var state: int = visitors.cinema_state()
	# 幕は建物と同じく、夜は暗く見せる（スクリーンの映像は光っているので、暗くしない）
	var tint: Color = Color.WHITE.lerp(world.lighting.NIGHT_TINT, world.clock.darkness())
	var elapsed := 0.0 # 上映が始まってからの分
	if state == visitors.CinemaState.SHOWING:
		elapsed = world.clock.minute - visitors.current_show()
	var tile_size := Vector2(world.tile_map.tile_set.tile_size)
	for origin in cinemas:
		var top_left := Vector2(origin.x, origin.y - 1) * tile_size # 映画館は上下2階。左端のマスは下の階
		match state:
			visitors.CinemaState.CLOSED:
				draw_curtains(top_left, SCREEN.size.x / 2.0, tint)
			visitors.CinemaState.OPEN:
				draw_curtains(top_left, SIDE_CURTAIN, tint)
			visitors.CinemaState.SHOWING:
				draw_hall_dark(top_left)
				draw_curtains(top_left, SIDE_CURTAIN, tint * Color(0.6, 0.6, 0.6))
				draw_movie(top_left + MOVIE.position, elapsed, visitors.CINEMA.length)

# 幕: 左右から width ドットずつ（スクリーンの半分なら、閉じている）。上には金色の飾り幕
func draw_curtains(top_left: Vector2, width: float, tint: Color) -> void:
	var screen := Rect2(top_left + SCREEN.position, SCREEN.size)
	for side in [0, 1]:
		var x0: float = screen.position.x if side == 0 else screen.end.x - width
		draw_rect(Rect2(x0, screen.position.y, width, screen.size.y), CURTAIN_COLOR * tint)
		for i in int(width):
			# 3ドットおきに暗いひだと明るいひだを入れる
			if i % 3 == 1:
				draw_rect(Rect2(x0 + i, screen.position.y, 1, screen.size.y), CURTAIN_FOLD * tint)
			elif i % 3 == 2:
				draw_rect(Rect2(x0 + i, screen.position.y, 1, screen.size.y), CURTAIN_LIGHT * tint)
	draw_rect(Rect2(screen.position, Vector2(screen.size.x, VALANCE)), VALANCE_COLOR * tint)

# 上映中: 場内の明かりを落とし（スクリーンは除く）、映写室からスクリーンへ光を伸ばす
func draw_hall_dark(top_left: Vector2) -> void:
	var hall := Rect2(top_left + HALL.position, HALL.size)
	var screen := Rect2(top_left + SCREEN.position, SCREEN.size)
	draw_rect(Rect2(hall.position, Vector2(hall.size.x, screen.position.y - hall.position.y)), HALL_DIM) # スクリーンより上
	draw_rect(Rect2(hall.position.x, screen.end.y, hall.size.x, hall.end.y - screen.end.y), HALL_DIM) # 下
	draw_rect(Rect2(hall.position.x, screen.position.y, screen.position.x - hall.position.x, screen.size.y), HALL_DIM) # 左
	draw_rect(Rect2(screen.end.x, screen.position.y, hall.end.x - screen.end.x, screen.size.y), HALL_DIM) # 右
	var booth := top_left + BOOTH
	draw_colored_polygon(PackedVector2Array([booth, top_left + MOVIE.position + Vector2(MOVIE.size.x, 0),
		top_left + MOVIE.end]), BEAM_COLOR)
	draw_rect(Rect2(booth - Vector2(1, 1), Vector2(2, 2)), Color(1.0, 0.95, 0.7)) # 映写機の光

# 映画（p: 映る部分の左上、elapsed: 上映が始まってからの分、length: 上映時間）
func draw_movie(p: Vector2, elapsed: float, length: float) -> void:
	if elapsed < COUNTDOWN_MINUTES:
		draw_countdown(p, elapsed)
	elif elapsed >= length - CREDITS_MINUTES:
		draw_credits(p, elapsed - (length - CREDITS_MINUTES))
	else:
		match int((elapsed - COUNTDOWN_MINUTES) / SCENE_MINUTES) % 3:
			0: draw_sunset(p, elapsed)
			1: draw_night_city(p, elapsed)
			2: draw_meadow(p, elapsed)

# 映る部分の中だけに四角を描く（はみ出す分は切る。ドットがにじまないよう、位置は整数にそろえる）
func dot(p: Vector2, x: float, y: float, w: float, h: float, color: Color) -> void:
	var rect := Rect2(p + Vector2(floorf(x), floorf(y)), Vector2(w, h)).intersection(Rect2(p, MOVIE.size))
	if rect.has_area():
		draw_rect(rect, color)

func draw_countdown(p: Vector2, t: float) -> void:
	dot(p, 0, 0, MOVIE.size.x, MOVIE.size.y, Color("#8a8a8a"))
	dot(p, 0, 7, MOVIE.size.x, 1, Color("#5a5a5a"))
	dot(p, 11, 0, 1, MOVIE.size.y, Color("#5a5a5a"))
	var center := p + Vector2(11.5, 7.5)
	draw_arc(center, 5.5, 0.0, TAU, 16, Color("#f0f0f0"), 1.0)
	var angle := fmod(t, 1.0) * TAU - PI / 2.0 # 1分で1回転
	draw_line(center, center + Vector2(cos(angle), sin(angle)) * 5.0, Color("#202020"), 1.0)

func draw_sunset(p: Vector2, t: float) -> void:
	dot(p, 0, 0, 22, 3, Color("#ff9a52"))
	dot(p, 0, 3, 22, 3, Color("#ffb870"))
	dot(p, 0, 6, 22, 3, Color("#ffd49a"))
	for row in [[6, 9, 4], [7, 8, 6], [8, 8, 6]]: # 沈みかけの太陽
		dot(p, row[1], row[0], row[2], 1, Color("#fff0b0"))
	dot(p, 0, 9, 22, 5, Color("#2f5d9a")) # 海
	for i in 3: # 波のきらめき
		dot(p, fposmod(t * 1.5 + i * 8, 22), 10 + i, 2, 1, Color("#7fb2e6"))
	var boat := fposmod(t * 0.5, 28) - 5 # 帆船が左から右へ進む
	dot(p, boat, 9, 5, 1, Color("#3a2a20"))
	dot(p, boat + 2, 5, 1, 4, Color("#3a2a20"))
	dot(p, boat + 3, 6, 1, 3, Color("#f4f1ea"))
	dot(p, boat + 1, 7, 1, 2, Color("#f4f1ea"))

func draw_night_city(p: Vector2, t: float) -> void:
	dot(p, 0, 0, 22, 14, Color("#101838"))
	var stars := [Vector2(2, 1), Vector2(7, 3), Vector2(12, 1), Vector2(16, 4), Vector2(20, 2), Vector2(4, 5), Vector2(18, 0)]
	for i in stars.size():
		if (int(t * 2.0) + i) % 3 != 0: # またたく
			dot(p, stars[i].x, stars[i].y, 1, 1, Color("#e8e8ff"))
	var moon := 2 + fposmod(t * 0.3, 18)
	dot(p, moon, 1, 3, 3, Color("#f5f0c8"))
	dot(p, moon + 2, 1, 1, 1, Color("#101838")) # 三日月の欠け
	var heights := [5, 8, 4, 7, 9, 5, 6]
	var x := 0
	for i in heights.size(): # ビルの影と窓の明かり
		var h: int = heights[i]
		dot(p, x, 14 - h, 3, h, Color("#05070f"))
		for wy in range(14 - h + 1, 13, 2):
			if (i + wy) % 3 != 0:
				dot(p, x + 1, wy, 1, 1, Color("#ffd966"))
		x += 3 + i % 2

func draw_meadow(p: Vector2, t: float) -> void:
	dot(p, 0, 0, 22, 10, Color("#7ec8f0"))
	var cloud := 22 - fposmod(t * 0.6, 30)
	dot(p, cloud, 2, 5, 2, Color("#ffffff"))
	dot(p, cloud + 1, 1, 3, 1, Color("#ffffff"))
	var hill := fposmod(-t * 1.0, 22) # 背景の丘が流れて、走っているように見せる
	for dx in [0, 22, -22]:
		dot(p, hill + dx + 2, 8, 8, 2, Color("#3d8f41"))
		dot(p, hill + dx + 4, 7, 4, 1, Color("#3d8f41"))
	dot(p, 0, 10, 22, 4, Color("#4caf50"))
	var step := int(t * 4.0) % 2 # 走る人: 体が上下にはね、足を交互に出す
	var y := 4 + step
	dot(p, 10, y, 2, 2, Color("#f1c27d"))
	dot(p, 10, y + 2, 2, 2, Color("#e04040"))
	dot(p, 9 + step * 2, y + 4, 1, 2, Color("#34405a"))
	dot(p, 12 - step * 2, y + 4, 1, 2, Color("#34405a"))

func draw_credits(p: Vector2, t: float) -> void:
	dot(p, 0, 0, 22, 14, Color("#000000"))
	var offset := t * 2.0 # 下から上へ流れる
	var widths := [12, 8, 14, 6, 10]
	for i in 12:
		var y := 15 + i * 3 - offset
		var w: int = widths[i % widths.size()]
		dot(p, (22 - w) / 2.0, y, w, 1, Color("#d0d0d0"))
