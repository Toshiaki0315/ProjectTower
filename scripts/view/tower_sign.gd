extends Node2D

# ---------------------------------------------------
# 屋上の看板：ビルの一番上の階の屋根に、ビルの名前（main.tower_name）の看板を立てる。
#   一番上の階の、左端から右端までの真ん中に立てる（エレベーターのシャフトだけが飛び出していても、その上に立つ）。
#   夜は文字と縁が明るく光る（ビルが暗くなっても名前が読める）。
# TileMapLayerの子として追加するので、座標はタイルマップ座標系。
# ---------------------------------------------------

const FONT_SIZE := 8          # 看板の文字の大きさ（ドット）
const PADDING := Vector2(4, 2) # 文字のまわりの余白
const POST_HEIGHT := 3        # 看板を支える柱の高さ
const BOARD_COLOR := Color(0.12, 0.13, 0.2)
const FRAME_COLOR := Color(0.85, 0.65, 0.25)       # 縁（金色）
const TEXT_COLOR := Color(1.0, 0.95, 0.8)
const NIGHT_TEXT_COLOR := Color(1.0, 0.85, 0.35)   # 夜は黄色く光る
const POST_COLOR := Color(0.3, 0.32, 0.38)

var world: Node2D # main.gd
var cached_key := [] # sign_rect() を計算したときの [建物のマスの数, 名前]（変わったときだけ計算し直す）
var cached_rect := Rect2()

func setup(p_world: Node2D) -> void:
	world = p_world
	z_index = 6 # 建物のタイルより手前、住人より奥

func _process(_delta: float) -> void:
	queue_redraw()

# 看板の板の四角（タイルマップ座標系）。地上に建物がなければ空の Rect2。
# 一番上の階は建設・撤去でマスの数が変わったときしか変わらないので、そのときだけ計算し直す
func sign_rect() -> Rect2:
	var key := [world.building_grid.size(), world.tower_name]
	if key != cached_key:
		cached_key = key
		cached_rect = compute_sign_rect()
	return cached_rect

func compute_sign_rect() -> Rect2:
	var top: int = world.ground_y + 1
	var left := 0
	var right := 0
	for cell: Vector2i in world.building_grid:
		if cell.y > world.ground_y:
			continue # 地下は数えない
		if cell.y < top:
			top = cell.y
			left = cell.x
			right = cell.x
		elif cell.y == top:
			left = mini(left, cell.x)
			right = maxi(right, cell.x)
	if top > world.ground_y:
		return Rect2()
	var tile_size := Vector2(world.tile_map.tile_set.tile_size)
	var font: Font = ThemeDB.fallback_font
	var size := font.get_string_size(world.tower_name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE) + PADDING * 2.0
	var center_x := (left + right + 1) / 2.0 * tile_size.x
	var bottom: float = top * tile_size.y - POST_HEIGHT # 屋根（一番上の階の上端）から柱のぶん上
	return Rect2(Vector2(center_x - size.x / 2.0, bottom - size.y).round(), size.round())

func _draw() -> void:
	var rect := sign_rect()
	if not rect.has_area():
		return
	var night: float = world.clock.darkness()
	# 柱（左右の2本）
	for x in [rect.position.x + 3, rect.end.x - 4]:
		draw_rect(Rect2(x, rect.end.y, 1, POST_HEIGHT), POST_COLOR)
	# 板と縁（夜は縁が光る）
	draw_rect(rect.grow(1), FRAME_COLOR.lerp(Color(1.0, 0.9, 0.5), night))
	draw_rect(rect, BOARD_COLOR)
	# 文字は画面の拡大率に合わせた大きさで描く（小さな文字を拡大すると、ぼやけて読みにくいため）
	var zoom: float = get_global_transform_with_canvas().get_scale().x
	var font: Font = ThemeDB.fallback_font
	var baseline := rect.position + Vector2(PADDING.x, PADDING.y + font.get_ascent(FONT_SIZE))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / zoom)
	draw_string(font, baseline * zoom, world.tower_name, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(FONT_SIZE * zoom)),
		TEXT_COLOR.lerp(NIGHT_TEXT_COLOR, night))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
