extends Node2D

# ---------------------------------------------------
# 演出：建てたとき・撤去したとき・お金が入ったときの、短いエフェクト。
#   "build":    白い枠がふわっと広がって消える
#   "demolish": 土ぼこりの丸がいくつか広がって消える
#   "money":    「+◯◯Cr」の文字が浮き上がって消える
#   "treasure": 埋蔵金を掘り当てたマスから、宝箱と金塊が飛び出して光り、金額の文字が浮かぶ
# TileMapLayerの子として追加するので、座標はタイルマップ座標系。
# ---------------------------------------------------

const BUILD_COLOR := Color(1.0, 1.0, 0.85)
const DUST_COLOR := Color(0.72, 0.62, 0.5)
const MONEY_COLOR := Color(0.5, 1.0, 0.6)
const LIFE := 0.8       # エフェクトが消えるまでの時間（秒）
const MONEY_LIFE := 1.6 # 「+◯◯Cr」だけは長めに出す
const TREASURE_LIFE := 3.0 # 埋蔵金の宝箱は、さらに長めに出す
const TREASURE_TEXT_COLOR := Color(1.0, 0.85, 0.2)
# 宝箱と金塊のドット絵（1文字が1px）。K 輪郭 / W 木の箱 / w 木の影 / G 金 / g 金の影 / L 錠前 / . 透明
const CHEST := [
	"..KKKKKKKK..",
	".KGGGGGGGGK.",
	"KGgGGGGGGgGK",
	"KWWWWLLWWWWK",
	"KKKKKLLKKKKK",
	"KWwWWLLWWwWK",
	"KWwWWWWWWwWK",
	"KWwWWWWWWwWK",
	".KKKKKKKKKK.",
]
const GOLD_BAR := [
	".KKKK.",
	"KGGGGK",
	"KgggGK",
	".KKKK.",
]
const TREASURE_COLORS := {
	"K": Color(0.25, 0.15, 0.05), "W": Color(0.62, 0.38, 0.18), "w": Color(0.45, 0.26, 0.12),
	"G": Color(1.0, 0.82, 0.2), "g": Color(0.85, 0.62, 0.1), "L": Color(0.95, 0.95, 0.85),
}
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

# 埋蔵金を掘り当てたマスから、宝箱と金塊が飛び出す
func play_treasure(cell: Vector2i, amount: int) -> void:
	var tile_size := Vector2(world.tile_map.tile_set.tile_size)
	add_effect("treasure", Rect2(Vector2(cell) * tile_size, tile_size), "+%s" % world.money_text(amount), TREASURE_LIFE)

# 文字で描いたドット絵を、左上 pos に描く（1文字を px の大きさで描く）
func draw_pixels(rows: Array, pos: Vector2, alpha: float, px := 1.0) -> void:
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			if TREASURE_COLORS.has(ch):
				draw_rect(Rect2(pos + Vector2(x, y) * px, Vector2(px, px)), Color(TREASURE_COLORS[ch], alpha))

# お金が入ったことを、文字で知らせる
func play_money(cell: Vector2i, amount: int) -> void:
	var tile_size := Vector2(world.tile_map.tile_set.tile_size)
	add_effect("money", Rect2(Vector2(cell) * tile_size, tile_size), "+%s" % world.money_text(amount), MONEY_LIFE)

# 出している演出を全部消す（更地にしたとき・セーブデータを読み込んだとき）
func clear() -> void:
	effects.clear()
	queue_redraw()

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
			"treasure":
				# 宝箱がぽんと飛び出し（はじめの2割で上がって止まる）、まわりに金塊と光が散る
				var center: Vector2 = effect.rect.get_center()
				var rise := minf(t / 0.2, 1.0) * 10.0
				var fade := 1.0 if t < 0.7 else (1.0 - t) / 0.3
				var box := center + Vector2(0, -rise) # 宝箱の真ん中
				draw_circle(box, 12.0 + sin(t * 20.0) * 1.5, Color(1.0, 0.9, 0.4, 0.25 * fade)) # 光
				draw_pixels(CHEST, box + Vector2(-9, -6.75), fade, 1.5) # 宝箱（1.5倍の大きさ）
				# 金塊が宝箱の左・右・上から、外へ飛び散る
				for offset: Vector2 in [Vector2(-16, 2), Vector2(10, 2), Vector2(-3, -14)]:
					draw_pixels(GOLD_BAR, box + offset + offset.normalized() * t * 6.0, fade)
				for i in 4: # きらきら
					var angle := t * 6.0 + i * PI / 2.0
					var spark: Vector2 = box + Vector2(cos(angle), sin(angle)) * 15.0
					draw_rect(Rect2(spark - Vector2(0.75, 0.75), Vector2(1.5, 1.5)), Color(1.0, 1.0, 0.8, fade))
				var text_pos: Vector2 = box + Vector2(-20, -22 - t * 6.0)
				draw_string(font, text_pos, effect.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(TREASURE_TEXT_COLOR, fade))
			"money":
				# 文字が上へ浮き上がる
				var pos: Vector2 = effect.rect.get_center() + Vector2(-16, -8 - t * 14.0)
				draw_string(font, pos, effect.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(MONEY_COLOR, alpha))
