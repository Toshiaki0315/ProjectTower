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
const ENTRANCE_COLOR := Color(0.3, 1.0, 0.4)
const SUBWAY_ENTRANCE_COLOR := Color(0.4, 0.85, 1.0)
const SOIL_COLOR := Color(0.36, 0.26, 0.18)       # 地下（1階より下）の土
const GROUND_LINE_COLOR := Color(0.55, 0.42, 0.28) # 地面の線

var world: Node2D # main.gd
var hover_screen_pos := Vector2.ZERO # 最後にマウスがあった画面上の位置
var hover_enabled := false           # マウスがゲーム画面内にあるか
var hover_visible := false           # カーソル下のマスを強調表示しているか
var hover_cell := Vector2i.ZERO      # カーソル下のマス

var soil: Node2D # 地下の土を描く背景（タイルより奥）

func setup(p_world: Node2D) -> void:
	world = p_world
	z_index = 5 # タイルより手前、住人より奥
	soil = SoilBackground.new()
	soil.overlay = self
	soil.z_index = -10 # マス目の表示(5)からの相対値。タイルより奥になる
	add_child(soil)

func _process(_delta: float) -> void:
	queue_redraw() # カメラの移動・ズームに追従するため毎フレーム描き直す
	soil.queue_redraw()

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

	# 建物ごとの枠線
	var width := BORDER_WIDTH * px
	for cell in world.building_grid:
		draw_rect(cell_rect(cell, tile_size).grow(-width / 2.0), BORDER_COLOR, false, width)

	# 入口（マスの左端に扉と、中へ向かう矢印。1階の入口は緑、地下鉄駅は水色）
	for entrance in world.get_entrances():
		var color := ENTRANCE_COLOR if entrance == world.get_entrance() else SUBWAY_ENTRANCE_COLOR
		var rect := cell_rect(entrance, tile_size)
		draw_rect(Rect2(rect.position, Vector2(3, tile_size.y)), color)
		var mid := rect.position + Vector2(5, tile_size.y / 2.0)
		draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -3), mid + Vector2(4, 0), mid + Vector2(0, 3)]), color)
	
	# カーソル下のマス
	if hover_visible:
		var color := HOVER_OK_COLOR if world.can_click_cell(hover_cell) else HOVER_NG_COLOR
		var rect := cell_rect(hover_cell, tile_size)
		draw_rect(rect, Color(color, 0.25))
		draw_rect(rect.grow(-px), color, false, 2.0 * px)

func cell_rect(cell: Vector2i, tile_size: Vector2) -> Rect2:
	return Rect2(Vector2(cell) * tile_size, tile_size)


# 画面に映っている範囲（タイルマップ座標系）
func get_visible_rect() -> Rect2:
	return get_global_transform_with_canvas().affine_inverse() * get_viewport_rect()

# 地下の土の背景：1階の床より下を土の色で塗り、地面の線を引く（タイルより奥に描く）
class SoilBackground extends Node2D:
	var overlay # grid_overlay.gd

	func _draw() -> void:
		var tile_size := Vector2(overlay.world.tile_map.tile_set.tile_size)
		var visible_rect: Rect2 = overlay.get_visible_rect()
		var ground_bottom: float = (overlay.world.ground_y + 1) * tile_size.y # 1階の床の下端
		if visible_rect.end.y <= ground_bottom:
			return
		var top := maxf(ground_bottom, visible_rect.position.y)
		draw_rect(Rect2(visible_rect.position.x, top, visible_rect.size.x, visible_rect.end.y - top), overlay.SOIL_COLOR)
		draw_line(Vector2(visible_rect.position.x, ground_bottom), Vector2(visible_rect.end.x, ground_bottom),
			overlay.GROUND_LINE_COLOR, 2.0)
