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
#               この割合以下であること（人を増やすだけでなく、エレベーターの混雑などを片づけないと上がらないように）。
#               入居してから tenant_system.SETTLED_DAYS 回の評価を受けていないテナントは数えない
#               （入居したばかりのテナントは評価が「良い」から始まるので、一気に建てると割合が薄まってしまうため）
# 昇格: 次の★の条件を全部満たした決算が PROMOTE_DAYS 回続いたら、★が1つ上がる。
# 降格: 今の★の条件を満たさない決算が DEMOTE_DAYS 回続いたら、★が1つ下がる（VIPの合格・達成した目標は取り消さない）。
#       降格の判断では、不満なテナントの条件を KEEP_UNHAPPY まで緩める（★4の1割は★5の2割より厳しいので、
#       そのままだと★5から下がると、すぐに★4の条件も割って★3まで続けて下がってしまうため）。
# ---------------------------------------------------

const REQUIREMENTS := {
	2: {"population": 50, "buildings": ["security"]},
	3: {"population": 120, "buildings": ["medical", "recycling"]},
	4: {"population": 250, "buildings": ["subway"], "vip": true, "unhappy": 0.1},
	# 最高評価。屋上の展望台と結婚式場のある、名所のタワー。人口が倍になって通勤の混雑が大きいので、満足度は2割まで
	5: {"population": 500, "buildings": ["observatory", "wedding"], "unhappy": 0.2},
}
const MAX_STARS := 5
const BONUS_PER_STAR := 0.25
const PROMOTE_DAYS := 3 # 次の★の条件をこの回数の決算続けて満たしたら昇格
const DEMOTE_DAYS := 5  # 今の★の条件をこの回数の決算続けて満たさなかったら降格
const KEEP_UNHAPPY := 0.2 # ★を保つための、不満なテナントの割合の上限（取るときの条件より緩い）

var world: Node2D # main.gd
var stars := 1
var qualified_days := 0 # 次の★の条件を続けて満たした決算の回数
var failing_days := 0   # 今の★の条件を続けて満たさなかった決算の回数

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
	if stars >= MAX_STARS:
		var none: Array[String] = []
		return none
	return missing_for(stars + 1)

# その★の条件に足りないもの（★1なら空）。keeping: 今の★を保てるかを見るとき（不満なテナントの条件を緩める）
func missing_for(star: int, keeping := false) -> Array[String]:
	var missing: Array[String] = []
	if not REQUIREMENTS.has(star):
		return missing
	var req = REQUIREMENTS[star]
	if population() < req.population:
		missing.append("人口%d" % req.population)
	for type in req.buildings:
		if world.find_cells_of_type(type).is_empty():
			missing.append(world.BUILDINGS[type].name)
	if req.has("unhappy"):
		var limit: float = maxf(req.unhappy, KEEP_UNHAPPY) if keeping else req.unhappy
		var rate := unhappy_rate() # 全部のテナントを調べるので1回だけ（ビルの状況の表示で毎フレーム呼ばれるため）
		if rate > limit:
			missing.append("不満なテナント%d割以下（今%d%%）" % [int(round(limit * 10)), int(round(rate * 100))])
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
			if not tenants.is_settled(record):
				continue # 入居したばかりで、まだ落ち着いていない
			total += 1
			if record.rating == tenants.Rating.BAD or tenants.is_about_to_leave(origin):
				unhappy += 1
	return float(unhappy) / total if total > 0 else 0.0

# VIPの宿泊だけが足りない状態か（VIPはこのときに来館する）
func waiting_for_vip() -> bool:
	var missing := missing_for_next()
	return missing.size() == 1 and missing[0] == "VIPの宿泊"

# 決算のときに呼ばれる: 次の★の条件が続いたら★を上げ、今の★の条件を割った日が続いたら★を下げる。
# 戻り値: 1 … 上がった / -1 … 下がった / 0 … 変わらない
func evaluate() -> int:
	if stars < MAX_STARS:
		qualified_days = qualified_days + 1 if missing_for_next().is_empty() else 0
		if qualified_days >= PROMOTE_DAYS:
			stars += 1
			qualified_days = 0
			failing_days = 0
			return 1
	failing_days = failing_days + 1 if not missing_for(stars, true).is_empty() else 0
	if failing_days >= DEMOTE_DAYS:
		stars -= 1
		failing_days = 0
		qualified_days = 0
		return -1
	return 0

# 今の★の条件を割っているときの知らせ（割っていなければ ""）
func demotion_warning() -> String:
	if failing_days == 0:
		return ""
	return "★%dの条件を満たしていません（%s）。あと%d日続くと★%dに下がります" % [stars, "・".join(missing_for(stars, true)),
		DEMOTE_DAYS - failing_days, stars - 1]

func get_status_text() -> String:
	var text := "★%d 人口%d" % [stars, population()]
	var warning := demotion_warning()
	if warning != "":
		text += "（%s）" % warning
	if stars >= MAX_STARS:
		return text + "（最高評価）"
	var missing := missing_for_next()
	if missing.is_empty():
		return text + "（★%dの条件達成。あと%d日続けば昇格）" % [stars + 1, PROMOTE_DAYS - qualified_days]
	return text + "（★%dまで: %s）" % [stars + 1, "・".join(missing)]
