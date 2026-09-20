extends Node

# ---------------------------------------------------
# 騒音（ノイズ）：うるさい建物のまわりのマスに騒音を広げ、住宅とホテルの客室の評価を下げる。
#
# 騒音の広がり方: うるさい建物（NOISE_SOURCES）の各マスから、
#   周りのマスへ距離1につき1ずつ弱めながら広がる（強さ3なら、隣は2、2マス先は1）。
#   重なった分は足し算で、1マスの騒音は NOISE_MAX まで。
#   壁や床は考えず、縦横の距離（マンハッタン距離）で計算する。
# 評価への影響: 住宅・客室は、NOISE_TOLERANCE を超えた騒音 1 につきストレス NOISE_STRESS 相当が足される
#   （tenant_system の評価にそのまま効く）。静かな場所に住宅を置くのが大事になる。
# 建設・撤去のたびに rebuild() を呼んで、騒音の地図を作り直す。
# ---------------------------------------------------

# うるさい建物と、その強さ（そのマスの騒音の大きさ）
const NOISE_SOURCES := {
	"cinema": 5,           # 映画館（人が一斉に出入りする）
	"event_hall": 5,       # イベントホール
	"wedding": 4,          # 結婚式場
	"restaurant": 3,       # 飲食店
	"shop": 2,             # ショップ
	"recycling": 4,        # ゴミ処理場
	"subway": 4,           # 地下鉄駅
	"parking": 3,          # 地下駐車場
	"ramp": 2,             # スロープ
	"elevator": 2,         # エレベーター
	"express_elevator": 3, # 急行エレベーター
	"service_elevator": 2, # サービスエレベーター
	"escalator": 2,        # エスカレーター
	"lobby": 2, "lobby2": 2, "lobby3": 2, "sky_lobby": 2, # ロビー（人の出入りが多い）
}
const NOISE_MAX := 10      # 1マスの騒音の上限
const NOISE_TOLERANCE := 1 # これ以下の騒音は気にならない（静か）
const GARDEN_QUIET := 3    # 屋上庭園1つにつき、ビル全体の騒音をこれだけ和らげる
const NOISE_STRESS := 6.0  # これを超えた騒音1につき、住宅・客室の評価に足されるストレス

var world: Node2D # main.gd
var noise_map := {} # マス -> 騒音の大きさ（0のマスは持たない）

func setup(p_world: Node2D) -> void:
	world = p_world

# 建物の配置から騒音の地図を作り直す
func rebuild() -> void:
	noise_map.clear()
	for type in NOISE_SOURCES:
		var strength: int = NOISE_SOURCES[type]
		for cell in world.find_cells_of_type(type):
			spread(cell, strength)
	for cell in noise_map:
		noise_map[cell] = mini(noise_map[cell], NOISE_MAX)

# 1つのマスから、距離1につき1ずつ弱めながら騒音を広げる
func spread(from: Vector2i, strength: int) -> void:
	for dy in range(-strength + 1, strength):
		for dx in range(-strength + 1, strength):
			var value := strength - absi(dx) - absi(dy)
			if value <= 0:
				continue
			var cell := from + Vector2i(dx, dy)
			noise_map[cell] = noise_map.get(cell, 0) + value

# 指定したマスの騒音の大きさ
func get_noise(cell: Vector2i) -> int:
	return noise_map.get(cell, 0)

# 指定した建物（左端のマス）にかかっている騒音（建物のマスの平均）
func get_unit_noise(cell: Vector2i) -> int:
	var cells: Array[Vector2i] = world.get_unit_cells(cell)
	if cells.is_empty():
		return get_noise(cell)
	var total := 0
	for c in cells:
		total += get_noise(c)
	return int(round(float(total) / cells.size()))

# 騒音のぶん、評価に足されるストレス（住宅・客室用）。
# NOISE_TOLERANCE までの騒音は気にならないので、それを超えた分だけ効く
func noise_stress(cell: Vector2i) -> float:
	return maxi(get_unit_noise(cell) - NOISE_TOLERANCE - quiet_bonus(), 0) * NOISE_STRESS

# 屋上庭園があると、ビル全体の騒音が少し和らぐ
func quiet_bonus() -> int:
	return GARDEN_QUIET * world.find_units_of_type("garden").size()

# カーソル下の説明用（うるさいほど言葉が変わる）
func get_noise_text(cell: Vector2i) -> String:
	var noise := get_unit_noise(cell) - quiet_bonus()
	if noise <= NOISE_TOLERANCE:
		return "静か"
	if noise <= 3:
		return "騒音 %d（少しうるさい）" % noise
	if noise <= 6:
		return "騒音 %d（うるさい）" % noise
	return "騒音 %d（とてもうるさい）" % noise
