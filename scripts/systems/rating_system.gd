extends Node

# ---------------------------------------------------
# ビルの評価（★）：毎日の決算のときに条件を確かめ、満たしていれば★が1つ上がる（下がらない）。
# ★が高いほど、賃料と宿泊料に評価ボーナス（★1つにつき BONUS_PER_STAR）が上乗せされる。
#
# 人口 = 通勤できる社員の数（空室のオフィスを除く） + 客室の定員の合計 + 住宅の入居者の数
# 昇格の条件（REQUIREMENTS[次の★]）:
#   population: 必要な人口
#   buildings:  少なくとも1マス必要な建物
#   vip:        VIPの宿泊（最終試験）に合格していること（vip_system）
#   unhappy:    不満なテナント（評価が「悪い」か、退去しそうなオフィス・住宅）が、入居しているオフィス・住宅の
#               この割合以下であること（人を増やすだけでなく、エレベーターの混雑などを片づけないと上がらないように）
# ---------------------------------------------------

const REQUIREMENTS := {
	2: {"population": 50, "buildings": ["security"]},
	3: {"population": 120, "buildings": ["medical", "recycling"]},
	4: {"population": 250, "buildings": ["subway"], "vip": true, "unhappy": 0.1},
	5: {"population": 500, "buildings": ["observatory", "wedding"], "unhappy": 0.1}, # 最高評価。屋上の展望台と結婚式場のある、名所のタワー
}
const MAX_STARS := 5
const BONUS_PER_STAR := 0.25

var world: Node2D # main.gd
var stars := 1

func setup(p_world: Node2D) -> void:
	world = p_world

func population() -> int:
	var commute = world.commute_system
	return commute.count_employed() - commute.count_unreachable() + world.hotel_system.total_capacity() \
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
	if req.has("unhappy"):
		var rate := unhappy_rate() # 全部のテナントを調べるので1回だけ（ビルの状況の表示で毎フレーム呼ばれるため）
		if rate > req.unhappy:
			missing.append("不満なテナント%d割以下（今%d%%）" % [int(req.unhappy * 10), int(round(rate * 100))])
	if req.get("vip", false) and not world.vip_system.passed:
		missing.append("VIPの宿泊")
	return missing

# 不満なテナントの割合（入居しているオフィス・住宅のうち、評価が「悪い」か、退去しそうなもの）
func unhappy_rate() -> float:
	var tenants = world.tenant_system
	var total := 0
	var unhappy := 0
	for records in [tenants.offices, tenants.homes]:
		for origin in records:
			var record: Dictionary = records[origin]
			if record.vacant:
				continue
			if records == tenants.homes and not (world.housing_system.homes.has(origin) and world.housing_system.homes[origin].moved_in):
				continue # まだ入居していない住宅は数えない
			total += 1
			if record.rating == tenants.Rating.BAD or tenants.is_about_to_leave(origin):
				unhappy += 1
	return float(unhappy) / total if total > 0 else 0.0

# VIPの宿泊だけが足りない状態か（VIPはこのときに来館する）
func waiting_for_vip() -> bool:
	var missing := missing_for_next()
	return missing.size() == 1 and missing[0] == "VIPの宿泊"

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
