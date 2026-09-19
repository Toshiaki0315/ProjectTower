extends RefCounted

# ---------------------------------------------------
# ドット絵：建物のタイル（16×16ドット）を文字で描き、起動時に画像にする。
# 1文字 = 1ドット。文字と色の対応は PALETTE、"." は透明。
# 画像ファイルを用意しなくても、ここを書き換えるだけで見た目を変えられる。
# ---------------------------------------------------

const SIZE := 16

const PALETTE := {
	"K": Color("#1b1b24"), # 輪郭・天井と床の線
	"F": Color("#3a3a44"), # 床
	"G": Color("#5a5e68"), # 暗い灰色（エレベーターの床・警備室の机）
	"g": Color("#b8b8ae"), # 明るい灰色（階段室の壁・ベッドの脚）
	"W": Color("#a9bdd0"), # オフィスの壁
	"B": Color("#50607a"), # 窓枠
	"w": Color("#cfe8ff"), # 窓ガラス
	"v": Color("#ffffff"), # 窓の光
	"D": Color("#8a5a34"), # 机
	"d": Color("#5e3b20"), # 机の脚
	"M": Color("#2b2f3a"), # パソコン
	"m": Color("#6fd3ff"), # 画面
	"C": Color("#384a8a"), # 椅子
	"S": Color("#e0c080"), # 階段の踏み面
	"s": Color("#9c7a48"), # 階段の側面
	"R": Color("#6b6f7a"), # 手すり・レール
	"r": Color("#3e424c"), # シャフトの壁
	"c": Color("#9aa0aa"), # ケーブル
	"H": Color("#b59ad6"), # 客室の壁
	"U": Color("#8c5a9c"), # カーテン
	"P": Color("#f4f1ea"), # シーツ・タオル
	"E": Color("#7d4fb3"), # 掛け布団
	"e": Color("#6a4428"), # 木の家具
	"L": Color("#ffd966"), # 黄色（ランプ・チーズ）
	"T": Color("#79b8b4"), # ハウスキーパー室の壁
	"Y": Color("#e0b030"), # バケツ
	"O": Color("#8a6a40"), # モップの柄
	"N": Color("#f0b070"), # 飲食店の壁
	"n": Color("#a04a20"), # カウンター
	"Q": Color("#d99a3a"), # ハンバーガーのパン
	"q": Color("#6a3a1a"), # ハンバーガーの肉
	"Z": Color("#8d9a6a"), # ゴミ処理場の壁
	"z": Color("#3f8a3f"), # 緑のゴミ箱
	"x": Color("#3a5a8a"), # 青のゴミ箱
	"A": Color("#5a6aa0"), # 警備室の壁
	"a": Color("#f2c230"), # 警備のバッジ
	"V": Color("#e8eef2"), # メディカルセンターの壁
	"X": Color("#d83a3a"), # 赤十字
	"h": Color("#a6cf9a"), # 住宅の壁
	"o": Color("#7a4a2a"), # ドア
	"p": Color("#3c9a4a"), # 観葉植物
	"y": Color("#c0504d"), # ソファ
}

const TILES := {
	"office": [
		"KKKKKKKKKKKKKKKK",
		"WWWWWWWWWWWWWWWW",
		"WBBBBBBWWBBBBBBW",
		"WBwwwvBWWBwwwvBW",
		"WBwwvwBWWBwwvwBW",
		"WBwwwwBWWBwwwwBW",
		"WBBBBBBWWBBBBBBW",
		"WWWWWWWWWWWWWWWW",
		"WWWMMMMWWWWWWWWW",
		"WWWMmmMWWWWCCCWW",
		"WWWMMMMWWWWCCCWW",
		"WDDDDDDDDWWWCWWW",
		"WdWWWWWWdWWCCCWW",
		"WdWWWWWWdWWCWCWW",
		"FFFFFFFFFFFFFFFF",
		"KKKKKKKKKKKKKKKK",
	],
	"stairs": [
		"KKKKKKKKKKKKKKKK",
		"ggggggggggRRggss",
		"ggggggggggggSSss",
		"ggggggggRRggssss",
		"ggggggggggSSssss",
		"ggggggRRggssssss",
		"ggggggggSSssssss",
		"ggggRRggssssssss",
		"ggggggSSssssssss",
		"ggRRggssssssssss",
		"ggggSSssssssssss",
		"RRggssssssssssss",
		"ggSSssssssssssss",
		"ggssssssssssssss",
		"FFFFFFFFFFFFFFFF",
		"KKKKKKKKKKKKKKKK",
	],
	"elevator": [
		"KKKKKKKKKKKKKKKK",
		"rrRrrrrccrrrrRrr",
		"rrRrrrrccrrrrRrr",
		"rrRrrrrccrrrrRrr",
		"rrRrrrrccrrrrRrr",
		"rrRrrrrccrrrrRrr",
		"rrRrrrrccrrrrRrr",
		"rrRrrrrccrrrrRrr",
		"rrRrrrrccrrrrRrr",
		"rrRrrrrccrrrrRrr",
		"rrRrrrrccrrrrRrr",
		"rrRrrrrccrrrrRrr",
		"rrRrrrrccrrrrRrr",
		"rrRrrrrccrrrrRrr",
		"GGGGGGGGGGGGGGGG",
		"KKKKKKKKKKKKKKKK",
	],
	"hotel": [
		"KKKKKKKKKKKKKKKK",
		"HHHHHHHHHHHHHHHH",
		"HHHBBBBBBBBBBHHH",
		"HHUBwwwwwwwwBUHH",
		"HHUBwwwwwwwwBUHH",
		"HHUBwwwwwwwwBUHH",
		"HHUBBBBBBBBBBUHH",
		"HHUHHHHHHHHHHUHH",
		"HHHHHHHHHHHHHHHH",
		"HLHHHHHHHHHHHHHH",
		"eLePPPEEEEEEEEeH",
		"ePPPPPEEEEEEEEeH",
		"eeeeeeeeeeeeeeeH",
		"eHHHHHHHHHHHHHeH",
		"FFFFFFFFFFFFFFFF",
		"KKKKKKKKKKKKKKKK",
	],
	"housekeeping": [
		"KKKKKKKKKKKKKKKK",
		"TTTTTTTTTTTTTTTT",
		"TeeeeeeeeeeeeeeT",
		"TTPPTPPTPPTTTTTT",
		"TTPPTPPTPPTTTTTT",
		"TeeeeeeeeeeeeeeT",
		"TTTTTTTTTTTTOTTT",
		"TTTTTTTTTTTTOTTT",
		"TTTTTTTTTTTTOTTT",
		"TTTTTTTTTTTTOTTT",
		"TTTTTTTTTTTTOTTT",
		"TTTKKKKKTTTTOTTT",
		"TTTKYYYKTTTPPPTT",
		"TTTKYYYKTTTPPPTT",
		"FFFFFFFFFFFFFFFF",
		"KKKKKKKKKKKKKKKK",
	],
	"restaurant": [
		"KKKKKKKKKKKKKKKK",
		"NNNNNNNNNNNNNNNN",
		"NNNNNQQQQQQNNNNN",
		"NNNNQQQQQQQQNNNN",
		"NNNNLLLLLLLLNNNN",
		"NNNNqqqqqqqqNNNN",
		"NNNNQQQQQQQQNNNN",
		"NNNNNNNNNNNNNNNN",
		"NNNNNNNNNNNNNNNN",
		"nnnnnnnnnNNNNNNN",
		"KKKKKKKKKNNeeeNN",
		"nnnnnnnnnNNNeNNN",
		"nnnnnnnnnNNNeNNN",
		"nnnnnnnnnNNeeeNN",
		"FFFFFFFFFFFFFFFF",
		"KKKKKKKKKKKKKKKK",
	],
	"recycling": [
		"KKKKKKKKKKKKKKKK",
		"ZZZZZZZZZZZZZZZZ",
		"ZZZZZZZZZZZZZZZZ",
		"ZZZZZZzzzzZZZZZZ",
		"ZZZZZzZZZZzZZZZZ",
		"ZZZZzZZZZZZzZZZZ",
		"ZZZZZZZZZZzZZZZZ",
		"ZZZZZZZZZZZZZZZZ",
		"ZKKKKKKZZKKKKKKZ",
		"ZKzzzzKZZKxxxxKZ",
		"ZKzwzzKZZKxwxxKZ",
		"ZKzzzzKZZKxxxxKZ",
		"ZKzzzzKZZKxxxxKZ",
		"ZKzzzzKZZKxxxxKZ",
		"FFFFFFFFFFFFFFFF",
		"KKKKKKKKKKKKKKKK",
	],
	"security": [
		"KKKKKKKKKKKKKKKK",
		"AAAAAAAAAAAAAAAA",
		"AKKKKKKAKKKKKKAA",
		"AKmmmmKAKmmmmKAA",
		"AKmmmmKAKmmmmKAA",
		"AKKKKKKAKKKKKKAA",
		"AKKKKKKAKKKKKKAA",
		"AKmmmmKAKmmmmKAA",
		"AKmmmmKAKmmmmKAA",
		"AKKKKKKAKKKKKKAA",
		"AAAAAAAAAAAaaaAA",
		"GGGGGGGGGGaaaaaA",
		"GAAAAAAAAGAaaaAA",
		"GAAAAAAAAGAAaAAA",
		"FFFFFFFFFFFFFFFF",
		"KKKKKKKKKKKKKKKK",
	],
	"medical": [
		"KKKKKKKKKKKKKKKK",
		"VVVVVVVVVVVVVVVV",
		"VVVVVVVVVVVVVVVV",
		"VVVVVVXXXXVVVVVV",
		"VVVVVVXXXXVVVVVV",
		"VVVXXXXXXXXXXVVV",
		"VVVXXXXXXXXXXVVV",
		"VVVVVVXXXXVVVVVV",
		"VVVVVVXXXXVVVVVV",
		"VVVVVVVVVVVVVVVV",
		"VVVVVVVVVPPPPPPV",
		"VVVVVVVVgggggggV",
		"VVVVVVVVgVVVVVgV",
		"VVVVVVVVgVVVVVgV",
		"FFFFFFFFFFFFFFFF",
		"KKKKKKKKKKKKKKKK",
	],
	"housing": [
		"KKKKKKKKKKKKKKKK",
		"hhhhhhhhhhhhhhhh",
		"hhBBBBBBhhhhhhhh",
		"hhBwwwvBhhhhhhhh",
		"hhBwwvwBhhhhhhhh",
		"hhBwwwwBhhhhhpph",
		"hhBBBBBBhhhhpppp",
		"hhhhhhhhhhhhhpph",
		"hhhhhhhhhhhhhhoh",
		"hhhhhhhhhhhhhhoh",
		"hyyyyyyyyhhhhKKK",
		"yyyyyyyyyyhhhKoK",
		"yyyyyyyyyyhhhhoh",
		"yhhhhhhhhyhhhhoh",
		"FFFFFFFFFFFFFFFF",
		"KKKKKKKKKKKKKKKK",
	],
}

# 指定した建物のタイル画像（16×16）を作る
static func make_tile_image(type: String) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var rows: Array = TILES[type]
	for y in SIZE:
		for x in SIZE:
			var ch: String = rows[y][x]
			image.set_pixel(x, y, PALETTE.get(ch, Color.TRANSPARENT))
	return image

# タイルを columns × rows 個並べた画像（1枚の画像を複数タイルに分けているTileSetのソース用）
static func make_atlas_image(type: String, columns: int, rows: int) -> Image:
	var tile := make_tile_image(type)
	var atlas := Image.create(SIZE * columns, SIZE * rows, false, Image.FORMAT_RGBA8)
	for ty in rows:
		for tx in columns:
			atlas.blit_rect(tile, Rect2i(0, 0, SIZE, SIZE), Vector2i(tx * SIZE, ty * SIZE))
	return atlas
