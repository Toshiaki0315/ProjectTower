extends Node2D

# ---------------------------------------------------
# 演出：建てたとき・撤去したとき・お金が入ったときの、短いエフェクト。
#   "build":    白い枠がふわっと広がって消える
#   "demolish": 土ぼこりの丸がいくつか広がって消える
#   "money":    「+◯◯円」の文字が浮き上がって消える
# TileMapLayerの子として追加するので、座標はタイルマップ座標系。
# ---------------------------------------------------

const BUILD_COLOR := Color(1.0, 1.0, 0.85)
const DUST_COLOR := Color(0.72, 0.62, 0.5)
const MONEY_COLOR := Color(0.5, 1.0, 0.6)
const LIFE := 0.8       # エフェクトが消えるまでの時間（秒）
const MONEY_LIFE := 1.6 # 「+◯◯円」だけは長めに出す
const MAX_EFFECTS := 40 # 出しすぎないように

var world: Node2D # main.gd
var effects: Array = [] # [{"type", "rect", "text", "left", "life"}, ...]

func setup(p_world: Node2D) -> void:
	world = p_world
	z_index = 12 # 建物・カゴ・人より手前

# 建てたところに、白い枠を出す
func play_build(cells: Array) -> void:
	add_effect("build", cells_rect(cells), "", LIFE)

# 撤去したところに、土ぼこりを出す
func play_demolish(cells: Array) -> void:
	add_effect("demolish", cells_rect(cells), "", LIFE)

# お金が入ったことを、文字で知らせる
func play_money(cell: Vector2i, amount: int) -> void:
	var tile_size := Vector2(world.tile_map.tile_set.tile_size)
	add_effect("money", Rect2(Vector2(cell) * tile_size, tile_size), "+%s円" % world.format_money(amount), MONEY_LIFE)

func add_effect(type: String, rect: Rect2, text: String, life: float) -> void:
	if effects.size() >= MAX_EFFECTS:
		effects.pop_front()
	effects.append({"type": type, "rect": rect, "text": text, "left": life, "life": life})

func cells_rect(cells: Array) -> Rect2:
	var tile_size := Vector2(world.tile_map.tile_set.tile_size)
	var rect := Rect2(Vector2(cells[0]) * tile_size, tile_size)
	for cell in cells:
		rect = rect.merge(Rect2(Vector2(cell) * tile_size, tile_size))
	return rect

func _process(delta: float) -> void:
	if effects.is_empty():
		return
	for effect in effects:
		effect.left -= delta
	effects = effects.filter(func(e): return e.left > 0.0)
	queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	for effect in effects:
		var t: float = 1.0 - effect.left / effect.life # 0（出たとき）〜1（消えるとき）
		var alpha: float = 1.0 - t
		match effect.type:
			"build":
				# 枠が少しずつ広がりながら、うすくなる
				draw_rect(effect.rect.grow(t * 4.0), Color(BUILD_COLOR, alpha), false, 1.5)
			"demolish":
				# 土ぼこりが左右に広がる
				for i in 4:
					var offset := Vector2(-6 + i * 4, -2 - i % 2 * 3)
					var center: Vector2 = effect.rect.get_center() + offset * (0.5 + t)
					draw_circle(center, 2.0 + t * 3.0, Color(DUST_COLOR, alpha * 0.7))
			"money":
				# 文字が上へ浮き上がる
				var pos: Vector2 = effect.rect.get_center() + Vector2(-16, -8 - t * 14.0)
				draw_string(font, pos, effect.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(MONEY_COLOR, alpha))
