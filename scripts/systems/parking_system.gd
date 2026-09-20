extends Node

# ---------------------------------------------------
# 地下駐車場とスロープ：車で来る外からのお客さん。
#   スロープ（地下1階）は、1階から車で下りてくる道。
#   駐車場は、スロープから車で行ける（＝歩いて行ける）場所にあるときだけ使える。
#   使える駐車場1棟につき CARS_PER_UNIT 台、1台につき PEOPLE_PER_CAR 人が来て、
#   VISIT_START〜VISIT_END の間のランダムな時刻に自分の車のマスに現れ、
#   一番近い店（飲食店・ショップ）で過ごして、車に戻って帰る。
#   店が1つもない日は、誰も来ない。
#   現れてから帰るまでの動きは visitor_system が受け持つ（入口から来るお客さんと同じ）。
# 建設・撤去のたびに rebuild() を呼んで、使える駐車場を数え直す。
# ---------------------------------------------------

const CARS_PER_UNIT := 4      # 駐車場1棟に停められる車の数
const PEOPLE_PER_CAR := 2     # 車1台に乗ってくる人数
const VISIT_START := 11 * 60  # 来はじめる時刻
const VISIT_END := 14 * 60    # 来おわる時刻
const VISITOR_COLOR := Color(0.55, 0.85, 0.6) # 車で来たお客さんの色（緑）

var world: Node2D # main.gd

var usable_units: Array[Vector2i] = [] # 使える駐車場（左端のマス）の一覧
var visitors: Array = []               # 今日の来客（visitor_system が動かしている記録）
var visit_day := 0                     # 最後に来客の予定を立てた日
var visitors_by_day := {}              # 日 -> その日に店で過ごした車の客の数

func setup(p_world: Node2D) -> void:
	world = p_world

# 使える駐車場を数え直す（スロープまで車で行ける駐車場だけ）
func rebuild() -> void:
	usable_units.clear()
	var ramps: Array[Vector2i] = world.find_units_of_type("ramp")
	for unit in world.find_units_of_type("parking"):
		for ramp in ramps:
			if not world.find_path(unit, ramp).is_empty():
				usable_units.append(unit)
				break

# 今停められる車の数
func car_capacity() -> int:
	return usable_units.size() * CARS_PER_UNIT

func _process(_delta: float) -> void:
	var day: int = world.clock.day
	var now: int = world.clock.minute_of_day()
	# その日の朝、来客の予定を立てる
	if visit_day != day and now >= VISIT_START and now < VISIT_END:
		visit_day = day
		plan_visitors(day)
	# 店で代金を払った客を、その日の人数として数える
	for v in visitors:
		if v.paid and not v.get("counted", false):
			v["counted"] = true
			visitors_by_day[day] = visitors_by_day.get(day, 0) + 1

# 来客ごとの停めるマス・行き先の店・来る時刻を、日ごとに決まった乱数で決める
#（毎回同じ結果になり、テストしやすい）
func plan_visitors(day: int) -> void:
	visitors = visitors.filter(func(v): return is_instance_valid(v.resident)) # 前日の残りは帰るまで残す
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([day, "parking"])
	for unit in usable_units:
		var spots: Array[Vector2i] = world.get_unit_cells(unit)
		for car in CARS_PER_UNIT:
			var arrive := rng.randi_range(VISIT_START, VISIT_END - 1)
			for i in PEOPLE_PER_CAR:
				var spot: Vector2i = spots[car % spots.size()] # 停める（＝現れて、帰っていく）マス
				var seat = find_seat(spot)
				if seat == null:
					continue # 行ける店がなければ来ない
				var visit: Dictionary = world.visitor_system.add_visit(spot, seat[0], seat[1], arrive, Vector2(-4 + 8 * i, 0))
				visit.color = VISITOR_COLOR # 車で来た客は緑
				visitors.append(visit)

# 停めたマスから一番近い店の席（[席のマス, 店の種類]。行ける店がなければnull）
func find_seat(from: Vector2i):
	var best = null
	var best_length := 0
	for type in world.visitor_system.SHOP_TYPES:
		for unit in world.find_units_of_type(type):
			for seat in world.get_unit_cells(unit):
				var path: Array[Vector2i] = world.find_path(from, seat)
				if not path.is_empty() and (best == null or path.size() < best_length):
					best = [seat, type]
					best_length = path.size()
	return best

# 今ビルの中にいる、車で来たお客さんの数
func count_visitors() -> int:
	return visitors.filter(func(v): return is_instance_valid(v.resident)).size()

# カーソル下の説明用（駐車場のどのマスを指定してもよい）
func get_parking_text(cell: Vector2i) -> String:
	var origin: Vector2i = world.building_grid[cell].origin
	if not usable_units.has(origin):
		return "スロープにつながっていないので使えません"
	return "%d台" % CARS_PER_UNIT
