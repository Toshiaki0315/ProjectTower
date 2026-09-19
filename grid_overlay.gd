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

var world: Node2D # main.gd
var hover_screen_pos := Vector2.ZERO # 最後にマウスがあった画面上の位置
var hover_enabled := false           # マウスがゲーム画面内にあるか
var hover_visible := false           # カーソル下のマスを強調表示しているか
var hover_cell := Vector2i.ZERO      # カーソル下のマス

func setup(p_world: Node2D) -> void:
	world = p_world
	z_index = 5 # タイルより手前、住人より奥

func _process(_delta: float) -> void:
	queue_redraw() # カメラの移動・ズームに追従するため毎フレーム描き直す

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

	# 入口（マスの左端に緑の扉と、中へ向かう矢印）
	var entrance = world.get_entrance()
	if entrance != null:
		var rect := cell_rect(entrance, tile_size)
		draw_rect(Rect2(rect.position, Vector2(3, tile_size.y)), ENTRANCE_COLOR)
		var mid := rect.position + Vector2(5, tile_size.y / 2.0)
		draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -3), mid + Vector2(4, 0), mid + Vector2(0, 3)]), ENTRANCE_COLOR)
	
	# カーソル下のマス
	if hover_visible:
		var color := HOVER_OK_COLOR if world.can_click_cell(hover_cell) else HOVER_NG_COLOR
		var rect := cell_rect(hover_cell, tile_size)
		draw_rect(rect, Color(color, 0.25))
		draw_rect(rect.grow(-px), color, false, 2.0 * px)

func cell_rect(cell: Vector2i, tile_size: Vector2) -> Rect2:
	return Rect2(Vector2(cell) * tile_size, tile_size)
