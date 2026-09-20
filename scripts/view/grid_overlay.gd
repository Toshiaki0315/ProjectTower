extends Node2D

# ---------------------------------------------------
# マス目の表示
# - 画面に映っている範囲の背景グリッド線
# - 建物1マスごとの枠線（隣り合う建物の境目がわかるように）
# - カーソル下のマスの強調（緑: 操作できる / 赤: 操作できない）
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
const HOME_COLOR := Color(1.0, 0.85, 0.2) # エレベーターの待機階の印
const BOMB_COLOR := Color(1.0, 0.25, 0.2) # 爆破予告のマスの印
const FIRE_COLORS := [Color(1.0, 0.5, 0.1), Color(1.0, 0.8, 0.2)] # 燃えているマス（交互に点滅）
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

	# カーソル下のマス
	# 建設モードなら、建てたときに使うマス全体を強調する
	if hover_visible:
		var color := HOVER_OK_COLOR if world.can_click_cell(hover_cell) else HOVER_NG_COLOR
		var rect := cells_rect(world.get_hover_footprint(hover_cell), tile_size)
		draw_rect(rect, Color(color, 0.25))
		draw_rect(rect.grow(-px), color, false, 2.0 * px)

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
#   入口:   ロビー（地下鉄駅）の左隣に、マスの半分の幅のアイコン
#   待機階: エレベーターが、呼び出しのないときに戻る階
class HomeMarkers extends Node2D:
	var overlay # grid_overlay.gd

	func _draw() -> void:
		var world = overlay.world
		var tile_size := Vector2(world.tile_map.tile_set.tile_size)
		# 入口のアイコン（建物の左隣に、マスの半分の幅で描く）
		for entrance in world.get_entrances():
			var entrance_color: Color = overlay.ENTRANCE_COLOR if entrance == world.get_entrance() else overlay.SUBWAY_ENTRANCE_COLOR
			draw_entrance(Vector2(entrance) * tile_size - Vector2(tile_size.x / 2.0, 0), entrance_color)
		# 燃えているマス（炎の色が交互に変わる）
		for cell in world.incident_system.fire:
			var flame_rect := Rect2(Vector2(cell) * tile_size, tile_size)
			var color: Color = overlay.FIRE_COLORS[0] if world.tenant_system.blink_on() else overlay.FIRE_COLORS[1]
			draw_rect(flame_rect, Color(color, 0.45))
			# 炎（下が広く、上がとがった三角）
			draw_colored_polygon([flame_rect.position + Vector2(3, tile_size.y - 2),
				flame_rect.position + Vector2(tile_size.x - 3, tile_size.y - 2),
				flame_rect.position + Vector2(tile_size.x / 2.0, 3)], color)

		# 爆破予告のマス（赤い枠が点滅する）
		if world.incident_system.has_bomb() and world.tenant_system.blink_on():
			var bomb_rect := Rect2(Vector2(world.incident_system.bomb.cell) * tile_size, tile_size)
			draw_rect(bomb_rect.grow(-1), overlay.BOMB_COLOR, false, 1.5)
			var center := bomb_rect.get_center()
			draw_circle(center, 3.0, overlay.BOMB_COLOR)
		for cell in world.elevator_system.get_home_cells():
			var pos := Vector2(cell) * tile_size
			# マスの左端の黄色い帯と、その中の下向きの三角（「ここに戻る」の印）
			draw_rect(Rect2(pos + Vector2(0.5, 2), Vector2(2, tile_size.y - 4)), overlay.HOME_COLOR)
			var cx := pos.x + 4.0
			var cy := pos.y + tile_size.y / 2.0
			draw_colored_polygon([Vector2(cx - 1.5, cy - 2), Vector2(cx + 1.5, cy - 2), Vector2(cx, cy + 1)], overlay.HOME_COLOR)

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
				visible_rect.size.x, sky_bottom - visible_rect.position.y), world.clock.sky_color())
			draw_stars(visible_rect, sky_bottom, tile_size, world.clock.darkness())
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
