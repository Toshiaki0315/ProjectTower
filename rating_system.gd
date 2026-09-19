extends Node

# ---------------------------------------------------
# ビルの評価（★）：毎日の決算のときに条件を確かめ、満たしていれば★が1つ上がる（下がらない）。
# ★が高いほど、賃料と宿泊料に評価ボーナス（★1つにつき BONUS_PER_STAR）が上乗せされる。
#
# 人口 = 通勤できる社員の数 + 客室の定員の合計 + 住宅の入居者の数
# 昇格の条件（REQUIREMENTS[次の★]）:
#   population: 必要な人口
#   buildings:  少なくとも1マス必要な建物
# ---------------------------------------------------

const REQUIREMENTS := {
	2: {"population": 50, "buildings": ["security"]},
	3: {"population": 120, "buildings": ["medical", "recycling"]},
	4: {"population": 250, "buildings": ["subway"]},
}
const MAX_STARS := 4
const BONUS_PER_STAR := 0.25

var world: Node2D # main.gd
var stars := 1

func setup(p_world: Node2D) -> void:
	world = p_world

func population() -> int:
	var commute = world.commute_system
	return commute.workers.size() - commute.count_unreachable() + world.hotel_system.total_capacity() \
		+ world.housing_system.count_residents()

# 賃料・宿泊料に上乗せする割合（★1なら0）
func bonus_rate() -> float:
	return BONUS_PER_STAR * (stars - 1)

# 次の★に足りないもの（最高評価なら空）
func missing_for_next() -> Array[String]:
	var missing: Array[String] = []
	if stars >= MAX_STARS:
		return missing
	var req = REQUIREMENTS[stars + 1]
	if population() < req.population:
		missing.append("人口%d" % req.population)
	for type in req.buildings:
		if world.find_cells_of_type(type).is_empty():
			missing.append(world.BUILDINGS[type].name)
	return missing

# 条件を満たしていれば★を上げる（決算のときに呼ばれる）。上がったらtrue
func evaluate() -> bool:
	if stars >= MAX_STARS or not missing_for_next().is_empty():
		return false
	stars += 1
	return true

func get_status_text() -> String:
	var text := "★%d 人口%d" % [stars, population()]
	if stars >= MAX_STARS:
		return text + "（最高評価）"
	var missing := missing_for_next()
	if missing.is_empty():
		return text + "（★%dの条件達成。次の決算で昇格）" % (stars + 1)
	return text + "（★%dまで: %s）" % [stars + 1, "・".join(missing)]
