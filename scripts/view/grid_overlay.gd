extends Node2D

# ---------------------------------------------------
# マス目の表示
# - 画面に映っている範囲の背景グリッド線
# - 建物1マスごとの枠線（隣り合う建物の境目がわかるように）
# - カーソル下のマスの強調（緑: 操作できる / 赤: 操作できない）
# - 経路（人の通り道。上部バーのボタン／Rキーで切り替え。既定はオフ）
# TileMapLayerの子として追加するので、座標はタイルマップ座標系。
# ---------------------------------------------------

const GRID_COLOR := Color(1, 1, 1, 0.08)
const BORDER_COLOR := Color(0, 0, 0, 0.2) # ドット絵に天井・床の線があるので、枠線は控えめに
const BORDER_WIDTH := 1.5 # 画面上のpx（ズームしても太さが変わらない）
const HOVER_OK_COLOR := Color(0.3, 1.0, 0.4)
const HOVER_NG_COLOR := Color(1.0, 0.3, 0.3)
const PixelArt := preload("res://scripts/view/pixel_art.gd")
const ENTRANCE_COLOR := Color(0.2, 0.42, 0.72)       # 1階の入口の庇（青）
const SUBWAY_ENTRANCE_COLOR := Color(0.25, 0.65, 0.8) # 地下鉄駅の入口の庇（水色）
const ROUTE_WIDTH := 3.0           # 経路の太さ（画面上のpx、旧1.5から倍増）
const ROUTE_EDGE_COLOR := Color(0.05, 0.05, 0.1, 0.8) # 経路の縁取り（明るい建物の上でも見えるように）
const ROUTE_ALPHA := 0.7           # 経路の濃さ
const ROUTE_SELECTED_WIDTH := 6.0  # 選んでいる住人の経路は太く描く（旧3.0から倍増）
const HOME_COLOR := Color(1.0, 0.85, 0.2) # エレベーターの待機階の印
const GRIME_COLOR := Color(0.35, 0.25, 0.1) # 衛生の悪化で建物にかかる、くすんだ茶色
const GRIME_ALPHA_PER_LEVEL := 0.07        # 悪化のレベル1につき、くすみの濃さ（レベル5で0.35）
const GRIME_SPOT_COLOR := Color(0.2, 0.14, 0.06, 0.55) # 汚れの点
const VIP_ONLY_COLOR := Color(1.0, 0.75, 0.1) # VIP専用のシャフトの印（金色）
const BOMB_COLOR := Color(1.0, 0.25, 0.2) # 爆破予告のマスの印
# 色分け表示の色（main.overlay）
const HEAT_GOOD := Color(0.3, 0.9, 0.4, 0.45)   # ストレス: 評価が良い（緑）
const HEAT_NORMAL := Color(1.0, 0.85, 0.2, 0.5) # 普通（黄）
const HEAT_BAD := Color(1.0, 0.25, 0.25, 0.55)  # 悪い（赤）
const HEAT_VACANT := Color(0.5, 0.5, 0.55, 0.5) # 空室（灰色）
const NOISE_LOW := Color(1.0, 0.9, 0.3)         # 騒音: 少し（黄）〜 NOISE_HIGH（赤）
const NOISE_HIGH := Color(1.0, 0.15, 0.1)
const WAIT_BUSY := 4   # エレベーター待ち: この人数から橙、WAIT_JAM人から赤
const WAIT_JAM := 8
const FIRE_COLORS := [Color(1.0, 0.5, 0.1), Color(1.0, 0.8, 0.2)] # 燃えているマス（交互に点滅）
const ROACH_COLOR := Color(0.25, 0.15, 0.1) # ゴキブリ
const SOIL_COLOR := Color(0.36, 0.26, 0.18)       # 地下（1階より下）の土
const GROUND_LINE_COLOR := Color(0.55, 0.42, 0.28) # 地面の線

var world: Node2D # main.gd
var hover_screen_pos := Vector2.ZERO # 最後にマウスがあった画面上の位置
var hover_enabled := false           # マウスがゲーム画面内にあるか
var hover_visible := false           # カーソル下のマスを強調表示しているか
var hover_cell := Vector2i.ZERO      # カーソル下のマス

var soil: Node2D # 地下の土を描く背景（タイルより奥）
var home_markers: Node2D # エレベーターの待機階の印（カゴより手前）

func setup(p_world: Node2D) -> void:
	world = p_world
	z_index = 5 # タイルより手前、住人より奥
	soil = SoilBackground.new()
	soil.overlay = self
	soil.z_index = -10 # マス目の表示(5)からの相対値。タイルより奥になる
	add_child(soil)
	home_markers = HomeMarkers.new()
	home_markers.overlay = self
	home_markers.z_index = 5 # カゴ(8)より手前に印を描く
	add_child(home_markers)

func _process(_delta: float) -> void:
	queue_redraw() # カメラの移動・ズームに追従するため毎フレーム描き直す
	soil.queue_redraw()
	home_markers.queue_redraw()

# カーソル下のマスを画面位置から計算し直す。
# カメラが動いても正しく追えるよう、main.gdが毎フレーム呼ぶ。
func update_hover() -> void:
	# ボタンやバーなどのUIの上にカーソルがあるときは表示しない
	hover_visible = hover_enabled and get_viewport().gui_get_hovered_control() == null
	if hover_visible:
		hover_cell = world.tile_map.local_to_map(make_canvas_position_local(hover_screen_pos))

# 衛生の悪化の汚れを描く。first〜last は画面に映っているマスの範囲
func draw_grime(level: int, first: Vector2i, last: Vector2i, tile_size: Vector2) -> void:
	var tint := GRIME_COLOR
	tint.a = GRIME_ALPHA_PER_LEVEL * level
	for x in range(first.x, last.x + 1):
		for y in range(first.y, last.y + 1):
			var cell := Vector2i(x, y)
			if world.is_cell_empty(cell):
				continue
			var pos := Vector2(cell) * tile_size
			draw_rect(Rect2(pos, tile_size), tint)
			# 汚れの点（マスごとに決まった場所。レベルが上がるほど増える）
			var h := absi(hash(cell))
			for i in mini(level, 4):
				var spot := Vector2((h >> (i * 4)) % 14 + 1, (h >> (i * 4 + 2)) % 12 + 2)
				draw_rect(Rect2(pos + spot, Vector2(1.5, 1.5)), GRIME_SPOT_COLOR)

# 住人の動線を、今いるところから行き先まで線で描く
func draw_route(resident, tile_size: Vector2, px: float) -> void:
	var points := PackedVector2Array([resident.position])
	for cell: Vector2i in resident.path:
		points.append(world.tile_map.map_to_local(cell))
	var color: Color = resident.get_body_color()
	color.a = ROUTE_ALPHA
	var width: float = ROUTE_SELECTED_WIDTH if resident.selected else ROUTE_WIDTH
	# 明るい建物の上でも見えるように、先に濃い色で縁取りしてから線を描く
	draw_polyline(points, ROUTE_EDGE_COLOR, (width + 2.0) * px)
	draw_polyline(points, color, width * px)
	var goal := Rect2(points[-1] - tile_size / 4.0, tile_size / 2.0) # 行き先の印
	draw_rect(goal, ROUTE_EDGE_COLOR, false, (width + 2.0) * px)
	draw_rect(goal, color, false, width * px)

func _draw() -> void:
	var tile_size := Vector2(world.tile_map.tile_set.tile_size)
	var px := 1.0 / get_global_transform_with_canvas().get_scale().x # 画面上の1pxの長さ

	# 背景のグリッド線（画面に映っている範囲だけ描く）
	var visible_rect: Rect2 = get_global_transform_with_canvas().affine_inverse() * get_viewport_rect()
	var first := Vector2i((visible_rect.position / tile_size).floor())
	var last := Vector2i((visible_rect.end / tile_size).ceil())
	for x in range(first.x, last.x + 1):
		draw_line(Vector2(x * tile_size.x, visible_rect.position.y), Vector2(x * tile_size.x, visible_rect.end.y), GRID_COLOR, -1)
	for y in range(first.y, last.y + 1):
		draw_line(Vector2(visible_rect.position.x, y * tile_size.y), Vector2(visible_rect.end.x, y * tile_size.y), GRID_COLOR, -1)

	# 建物（ユニット）ごとの枠線。横に複数マスの建物は、まとめて1つの枠で囲む
	var width := BORDER_WIDTH * px
	for cell in world.building_grid:
		if world.building_grid[cell].origin == cell:
			draw_rect(cells_rect(world.get_unit_cells(cell), tile_size).grow(-width / 2.0), BORDER_COLOR, false, width)

	# 動線（人がこれから通る道すじ）。見た目だけの機能で、経路探索や移動には触らない
	if world.show_routes:
		for resident in world.residents:
			if is_instance_valid(resident) and not resident.path.is_empty():
				draw_route(resident, tile_size, px)

	# 衛生の悪化: レベルに応じて、ビル全体が茶色くくすみ、汚れの点が増える（画面に映っている範囲だけ）
	var pollution: int = world.economy_system.pollution
	if pollution > 0:
		draw_grime(pollution, first, last, tile_size)

	# 色分け表示（ストレス・騒音・エレベーター待ち）
	if world.overlay != "":
		var heat := heat_cells()
		for cell in heat:
			draw_rect(cell_rect(cell, tile_size), heat[cell])
		if world.overlay == "wait":
			draw_wait_counts(tile_size)

	# カーソル下のマス
	# 建設モードなら、建てたときに使うマス全体を強調する
	if hover_visible:
		var color := HOVER_OK_COLOR if world.can_click_cell(hover_cell) else HOVER_NG_COLOR
		var rect := cells_rect(world.get_hover_footprint(hover_cell), tile_size)
		draw_rect(rect, Color(color, 0.25))
		draw_rect(rect.grow(-px), color, false, 2.0 * px)

# 色分け表示で塗るマスと色（マス -> 色）
#   ストレス:         オフィス・客室・住宅を、評価のストレスで 緑（良い）・黄（普通）・赤（悪い）に。空室は灰色
#   騒音:             騒音のあるマスを、うるさいほど濃い赤に（noise_system.noise_map）
#   エレベーター待ち: 乗り場で待っている人がいるシャフトのマスを、人数が多いほど 黄 → 橙 → 赤 に
func heat_cells() -> Dictionary:
	var heat := {}
	match world.overlay:
		"stress":
			var tenants = world.tenant_system
			var colors := {tenants.Rating.GOOD: HEAT_GOOD, tenants.Rating.NORMAL: HEAT_NORMAL, tenants.Rating.BAD: HEAT_BAD}
			for records in [tenants.offices, tenants.rooms, tenants.homes]:
				for origin in records:
					if not world.building_grid.has(origin):
						continue
					var record: Dictionary = records[origin]
					var color: Color = HEAT_VACANT if record.get("vacant", false) else colors[record.rating]
					for cell in world.get_unit_cells(origin):
						heat[cell] = color
		"noise":
			var noise = world.noise_system
			for cell in noise.noise_map:
				var level: float = float(noise.noise_map[cell]) / noise.NOISE_MAX
				heat[cell] = Color(NOISE_LOW.lerp(NOISE_HIGH, level), 0.15 + 0.45 * level)
		"wait":
			var waiting := waiting_counts()
			for cell in waiting:
				var n: int = waiting[cell]
				var color := Color(1.0, 0.85, 0.2, 0.45) if n < WAIT_BUSY else (Color(1.0, 0.55, 0.15, 0.55) if n < WAIT_JAM else Color(1.0, 0.2, 0.2, 0.65))
				heat[cell] = color
	return heat

# 乗り場で待っている人の数（マス -> 人数）
func waiting_counts() -> Dictionary:
	var counts := {}
	for resident in world.residents:
		if is_instance_valid(resident) and resident.state == resident.State.WAITING:
			counts[resident.cell] = counts.get(resident.cell, 0) + 1
	return counts

# エレベーター待ち: 待っている人数を、乗り場のマスに数字で出す
# 文字は画面の拡大率に合わせた大きさで描く（屋上の看板と同じ。小さな文字を拡大すると、ぼやけて読みにくいため）
func draw_wait_counts(tile_size: Vector2) -> void:
	var font: Font = ThemeDB.fallback_font
	var zoom: float = get_global_transform_with_canvas().get_scale().x
	var size := int(round(9 * zoom))
	var waiting := waiting_counts()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / zoom)
	for cell in waiting:
		var pos := (Vector2(cell) * tile_size + Vector2(1, tile_size.y - 3)) * zoom
		draw_string_outline(font, pos, str(waiting[cell]), HORIZONTAL_ALIGNMENT_LEFT, -1, size, int(2 * zoom), Color(0, 0, 0, 0.8))
		draw_string(font, pos, str(waiting[cell]), HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func cell_rect(cell: Vector2i, tile_size: Vector2) -> Rect2:
	return Rect2(Vector2(cell) * tile_size, tile_size)

# 複数マスをまとめて囲む四角形
func cells_rect(cells: Array[Vector2i], tile_size: Vector2) -> Rect2:
	var rect := cell_rect(cells[0], tile_size)
	for cell in cells:
		rect = rect.merge(cell_rect(cell, tile_size))
	return rect


# 画面に映っている範囲（タイルマップ座標系）
func get_visible_rect() -> Rect2:
	return get_global_transform_with_canvas().affine_inverse() * get_viewport_rect()

# 背景：地上は時刻で色が変わる空（夜は星が出る）、1階の床より下は土。タイルより奥に描く
# 建物より手前に描く印
#   入口:   ロビーの左隣と右隣・地下鉄駅の左隣に、マスの半分の幅のアイコン
#   待機階: エレベーターが、呼び出しのないときに戻る階
class HomeMarkers extends Node2D:
	var overlay # grid_overlay.gd

	func _draw() -> void:
		var world = overlay.world
		var tile_size := Vector2(world.tile_map.tile_set.tile_size)
		# 入口のアイコン（マスの半分の幅）。1階の左の出入り口と地下鉄駅は建物の左隣、右の出入り口は右隣に描く
		#（地下駐車場は、車で来た人が駐車場のマスに現れるので、アイコンは描かない）
		var ground: Array[Vector2i] = world.get_ground_entrances()
		for entrance in ground:
			var right_side: bool = ground.size() > 1 and entrance == ground[-1]
			var x: float = (entrance.x + 1) * tile_size.x if right_side else entrance.x * tile_size.x - tile_size.x / 2.0
			draw_entrance(Vector2(x, entrance.y * tile_size.y), overlay.ENTRANCE_COLOR)
		for station in world.find_units_of_type("subway"):
			draw_entrance(Vector2(station) * tile_size - Vector2(tile_size.x / 2.0, 0), overlay.SUBWAY_ENTRANCE_COLOR)
		# ゴキブリがいるテナント（床に小さな虫を描く）
		for origin in world.incident_system.roaches:
			if not world.building_grid.has(origin):
				continue
			for cell in world.get_unit_cells(origin):
				if cell.y != origin.y:
					continue
				draw_roach(Vector2(cell) * tile_size + Vector2(4, tile_size.y - 4), world.tenant_system.blink_on())
				draw_roach(Vector2(cell) * tile_size + Vector2(11, tile_size.y - 6), not world.tenant_system.blink_on())

		# 消防ヘリ（火事のときにヘリポートから飛んでくる）
		if world.incident_system.has_heli():
			draw_heli(world.incident_system.heli.pos)

		# 燃えているマス（炎の色が交互に変わる）
		for cell in world.incident_system.fire:
			var flame_rect := Rect2(Vector2(cell) * tile_size, tile_size)
			var color: Color = overlay.FIRE_COLORS[0] if world.tenant_system.blink_on() else overlay.FIRE_COLORS[1]
			draw_rect(flame_rect, Color(color, 0.45))
			# 炎（下が広く、上がとがった三角）
			draw_colored_polygon([flame_rect.position + Vector2(3, tile_size.y - 2),
				flame_rect.position + Vector2(tile_size.x - 3, tile_size.y - 2),
				flame_rect.position + Vector2(tile_size.x / 2.0, 3)], color)

		# 爆弾を見つけたマス（赤い枠が点滅する。見つかるまでは場所は分からない）
		if world.incident_system.has_bomb() and world.incident_system.bomb.found and world.tenant_system.blink_on():
			var bomb_rect := Rect2(Vector2(world.incident_system.bomb.cell) * tile_size, tile_size)
			draw_rect(bomb_rect.grow(-1), overlay.BOMB_COLOR, false, 1.5)
			var center := bomb_rect.get_center()
			draw_circle(center, 3.0, overlay.BOMB_COLOR)
		# VIP専用のシャフト（右端の金色の帯）
		for cell in world.elevator_system.get_vip_only_cells():
			var pos := Vector2(cell) * tile_size
			draw_rect(Rect2(pos + Vector2(tile_size.x - 2.5, 1), Vector2(2, tile_size.y - 2)), overlay.VIP_ONLY_COLOR)
		for cell in world.elevator_system.get_home_cells():
			var pos := Vector2(cell) * tile_size
			# マスの左端の黄色い帯と、その中の下向きの三角（「ここに戻る」の印）
			draw_rect(Rect2(pos + Vector2(0.5, 2), Vector2(2, tile_size.y - 4)), overlay.HOME_COLOR)
			var cx := pos.x + 4.0
			var cy := pos.y + tile_size.y / 2.0
			draw_colored_polygon([Vector2(cx - 1.5, cy - 2), Vector2(cx + 1.5, cy - 2), Vector2(cx, cy + 1)], overlay.HOME_COLOR)

	# ゴキブリ（胴体とひげ。歩いて見えるよう、向きを交互に変える）
	func draw_roach(pos: Vector2, flip: bool) -> void:
		var dir := 1.0 if flip else -1.0
		draw_rect(Rect2(pos - Vector2(1.5, 1.0), Vector2(3, 2)), overlay.ROACH_COLOR)
		draw_line(pos + Vector2(1.5 * dir, -1.0), pos + Vector2(3.0 * dir, -2.5), overlay.ROACH_COLOR, 0.6)
		draw_line(pos + Vector2(1.5 * dir, -1.0), pos + Vector2(3.0 * dir, 0.0), overlay.ROACH_COLOR, 0.6)

	# 消防ヘリ（胴体・ローター・放水）
	func draw_heli(pos: Vector2) -> void:
		var body := Color(0.9, 0.35, 0.2)
		var glass := Color(0.75, 0.9, 1.0)
		draw_rect(Rect2(pos - Vector2(6, 3), Vector2(12, 5)), body)      # 胴体
		draw_rect(Rect2(pos + Vector2(2, -2), Vector2(4, 3)), glass)     # 窓
		draw_rect(Rect2(pos - Vector2(10, 1), Vector2(5, 2)), body)      # 尾
		draw_rect(Rect2(pos - Vector2(11, 4), Vector2(2, 4)), body)      # 尾翼
		draw_rect(Rect2(pos - Vector2(1, 5), Vector2(2, 2)), body)       # ローターの軸
		var blade := 9.0 if fmod(Time.get_ticks_msec() / 100.0, 2.0) < 1.0 else 4.0 # 回って見えるように長さを変える
		draw_line(pos + Vector2(-blade, -5), pos + Vector2(blade, -5), Color(0.2, 0.2, 0.25), 0.8)
		draw_line(pos + Vector2(-5, 2), pos + Vector2(5, 2), Color(0.3, 0.3, 0.35), 0.6) # 脚
		# 放水
		for i in 4:
			draw_line(pos + Vector2(-2 + i, 3), pos + Vector2(-3 + i, 10), Color(0.6, 0.85, 1.0, 0.7), 0.7)

	# 入口のアイコンを、左上を pos として1ドットずつ描く（"C" は入口の色）
	func draw_entrance(pos: Vector2, color: Color) -> void:
		var rows: Array = PixelArt.ENTRANCE_SPRITE
		for y in rows.size():
			var row: String = rows[y]
			for x in row.length():
				var ch := row[x]
				if ch == ".":
					continue
				var dot: Color = color if ch == "C" else PixelArt.ENTRANCE_COLORS[ch]
				draw_rect(Rect2(pos + Vector2(x, y), Vector2.ONE), dot)

class SoilBackground extends Node2D:
	var overlay # grid_overlay.gd

	func _draw() -> void:
		var world = overlay.world
		var tile_size := Vector2(world.tile_map.tile_set.tile_size)
		var visible_rect: Rect2 = overlay.get_visible_rect()
		var ground_bottom: float = (world.ground_y + 1) * tile_size.y # 1階の床の下端
		
		# 空
		if visible_rect.position.y < ground_bottom:
			var sky_bottom := minf(ground_bottom, visible_rect.end.y)
			draw_rect(Rect2(visible_rect.position.x, visible_rect.position.y,
				visible_rect.size.x, sky_bottom - visible_rect.position.y), world.clock.sky_color() * world.weather_system.sky_tint())
			draw_stars(visible_rect, sky_bottom, tile_size, world.clock.darkness())
			draw_santa(visible_rect, sky_bottom) # 12月24日・25日の夜に空を横切る
			if world.weather_system.is_rainy():
				draw_rain(visible_rect, sky_bottom, tile_size)
			draw_sun_and_moon(visible_rect, sky_bottom)
			draw_street_lamps(visible_rect, world.clock.darkness())
		
		# 土
		if visible_rect.end.y > ground_bottom:
			var top := maxf(ground_bottom, visible_rect.position.y)
			draw_rect(Rect2(visible_rect.position.x, top, visible_rect.size.x, visible_rect.end.y - top), overlay.SOIL_COLOR)
			draw_line(Vector2(visible_rect.position.x, ground_bottom), Vector2(visible_rect.end.x, ground_bottom),
				overlay.GROUND_LINE_COLOR, 2.0)

	# 太陽と月: 画面に映っている空の中を、左（昇る）から右（沈む）へ弧を描いて動く。
	# 背景なので建物の後ろに隠れる。大きさは画面上で一定（ズームしても変わらない）
	func draw_sun_and_moon(visible_rect: Rect2, sky_bottom: float) -> void:
		var clock = overlay.world.clock
		var px: float = 1.0 / overlay.get_global_transform_with_canvas().get_scale().x # 画面上の1px
		var sun: float = clock.sun_progress()
		if sun >= 0.0:
			var pos := celestial_position(sun, visible_rect, sky_bottom)
			var height := sin(PI * sun) # 0: 地平線 〜 1: 一番高い
			var sun_color := Color(1.0, 0.55, 0.2).lerp(Color(1.0, 0.97, 0.75), clampf(height * 1.5, 0.0, 1.0))
			draw_circle(pos, 26 * px, Color(sun_color, 0.25)) # 光の輪
			draw_circle(pos, 18 * px, sun_color)
		var moon: float = clock.moon_progress()
		if moon >= 0.0:
			var pos := celestial_position(moon, visible_rect, sky_bottom)
			draw_circle(pos, 14 * px, Color(1.0, 1.0, 0.85))
			draw_circle(pos + Vector2(7, -3) * px, 12 * px, clock.sky_color()) # 空の色で欠けさせて三日月にする

	# 街灯の柱と灯り（夜は灯りが明るくなる。光の輪は lighting.gd が重ねる）
	func draw_street_lamps(visible_rect: Rect2, darkness: float) -> void:
		var lighting = overlay.world.lighting
		if lighting == null:
			return
		var pole_color := Color(0.25, 0.27, 0.3)
		var head_color := Color(0.55, 0.55, 0.5).lerp(Color(1.0, 0.9, 0.55), darkness)
		for head in lighting.get_street_lamps(visible_rect):
			draw_rect(Rect2(head.x - 0.5, head.y, 1, lighting.LAMP_HEIGHT), pole_color)  # 柱
			draw_rect(Rect2(head.x - 2, head.y - 1, 4, 2), pole_color)                   # かさ
			draw_rect(Rect2(head.x - 1, head.y + 1, 2, 1), head_color)                   # 灯り

	# 雨（斜めの線をたくさん描く。マスごとに決まった乱数で、位置が時間とともに流れる）
	func draw_rain(visible_rect: Rect2, sky_bottom: float, tile_size: Vector2) -> void:
		var color := Color(0.75, 0.85, 1.0, 0.5)
		var flow: float = fmod(Time.get_ticks_msec() / 1000.0 * 60.0, 32.0) # 雨の流れ
		var first := Vector2i((visible_rect.position / tile_size).floor())
		var last := Vector2i((Vector2(visible_rect.end.x, sky_bottom) / tile_size).ceil())
		for y in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				var h := hash(Vector2i(x, y))
				if h % 3 != 0:
					continue
				var drop := Vector2(x, y) * tile_size + Vector2(h % 16, fmod((h / 16) % 16 + flow, 16.0))
				if drop.y > sky_bottom:
					continue
				draw_line(drop, drop + Vector2(-1.5, 4), color, 0.6)

	# サンタクロースのソリ（12月24日・25日の21時〜24時に、空を左から右へ横切る）
	func draw_santa(visible_rect: Rect2, sky_bottom: float) -> void:
		var world = overlay.world
		var t: float = world.clock.santa_progress()
		if t < 0.0:
			return
		var sky_height := sky_bottom - visible_rect.position.y
		var pos := Vector2(visible_rect.position.x + visible_rect.size.x * (-0.1 + 1.2 * t),
			visible_rect.position.y + sky_height * (0.45 + 0.05 * sin(t * PI * 6.0)))
		var red := Color(0.9, 0.25, 0.25)
		var brown := Color(0.55, 0.36, 0.2)
		var gold := Color(1.0, 0.9, 0.5)
		# トナカイ2頭（体と角）
		for i in 2:
			var deer := pos + Vector2(10 + i * 8, 0)
			draw_rect(Rect2(deer, Vector2(6, 3)), brown)
			draw_rect(Rect2(deer + Vector2(5, -3), Vector2(2, 3)), brown)
			draw_line(deer + Vector2(6, -3), deer + Vector2(8, -6), brown, 0.8)
			draw_line(deer + Vector2(1, 3), deer + Vector2(1, 5), brown, 0.8)
			draw_line(deer + Vector2(5, 3), deer + Vector2(5, 5), brown, 0.8)
		draw_line(pos + Vector2(6, 1), pos + Vector2(26, 1), gold, 0.6) # 手綱
		# ソリ（赤い箱とプレゼント）
		draw_rect(Rect2(pos - Vector2(2, 2), Vector2(9, 5)), red)
		draw_line(pos + Vector2(-3, 3), pos + Vector2(8, 3), gold, 0.8)
		draw_rect(Rect2(pos + Vector2(0, -5), Vector2(4, 3)), gold)
		# きらきらした軌跡
		for i in 5:
			var sparkle := pos - Vector2(6 + i * 5, -1 - i)
			draw_rect(Rect2(sparkle, Vector2.ONE * (1.5 - i * 0.2)), Color(1, 1, 0.8, 0.8 - i * 0.15))

	# 空の中の位置: t=0 で左下、t=0.5 で上の真ん中、t=1 で右下
	func celestial_position(t: float, visible_rect: Rect2, sky_bottom: float) -> Vector2:
		var sky_height := sky_bottom - visible_rect.position.y
		var x := visible_rect.position.x + visible_rect.size.x * (0.08 + 0.84 * t)
		var y := sky_bottom - sky_height * (0.1 + 0.75 * sin(PI * t))
		return Vector2(x, y)

	# 星: マスごとに決まった乱数で、いくつかのマスに1つずつ置く（カメラを動かしても同じ場所に見える）
	func draw_stars(visible_rect: Rect2, sky_bottom: float, tile_size: Vector2, darkness: float) -> void:
		if darkness <= 0.0:
			return
		var first := Vector2i((visible_rect.position / tile_size).floor())
		var last := Vector2i((Vector2(visible_rect.end.x, sky_bottom) / tile_size).ceil())
		for y in range(first.y, last.y):
			for x in range(first.x, last.x + 1):
				var h := hash(Vector2i(x, y))
				if h % 19 != 0:
					continue
				var star := Vector2(x, y) * tile_size + Vector2(h % 13 + 1, (h / 13) % 13 + 1)
				if star.y < sky_bottom - 2:
					draw_rect(Rect2(star, Vector2.ONE), Color(1, 1, 0.9, darkness * 0.9))
