extends Node

# ---------------------------------------------------
# 商業施設（飲食店・ファストフード）：オフィスの社員が昼に食事をしに来る。
# ファストフードは食事が早くて安い（RESTAURANTS）。社員は経路が一番近い店を選ぶ。
#   LUNCH_START〜LUNCH_END の間のランダムな時刻に、自分のオフィスにいる社員が
#   経路が一番近い店へ向かい、店ごとの時間だけ食事をして、代金を払ってオフィスへ戻る。
#   飲食店は横に何マスかの建物で、店は左端のマスで表す。客は店の中のマスに振り分けて座る。
# 社員（住人ノード）は commute_system が管理しており、ここでは昼休みの行き来だけを受け持つ。
# ---------------------------------------------------

enum Phase { NONE, GOING, EATING, RETURNING }

const LUNCH_START := 12 * 60
const LUNCH_END := 13 * 60
# 店の種類ごとの、食事にかかる時間（分）と代金
const RESTAURANTS := {
	"restaurant": {"minutes": 30.0, "price": 1000}, # 飲食店（ゆっくり）
	"fastfood": {"minutes": 10.0, "price": 600},    # ファストフード（早い・安い）
}

var world: Node2D # main.gd

# オフィスのマス（= 社員） -> {lunch_day, phase, restaurant, seat, eat_left}
#   restaurant: 行く店（左端のマス）  seat: 店の中で座るマス
var lunches: Dictionary = {}
var revenue_by_day: Dictionary = {} # 日 -> その日の飲食店・ファストフードの売上
var meals_by_day: Dictionary = {}   # 日 -> その日の食事の数（ゴミの計算に使う）

func setup(p_world: Node2D) -> void:
	world = p_world

func _process(_delta: float) -> void:
	var day: int = world.clock.day
	var now: int = world.clock.minute_of_day()
	var minutes: float = world.clock.last_advance # このフレームで進んだゲーム内の分数
	var workers: Dictionary = world.commute_system.workers
	for office in workers:
		var resident = workers[office].resident
		if not lunches.has(office):
			lunches[office] = {"lunch_day": 0, "phase": Phase.NONE, "restaurant": null, "seat": null, "eat_left": 0.0}
		var lunch = lunches[office]
		if not is_instance_valid(resident) or workers[office].leaving:
			lunch.phase = Phase.NONE # ビルにいない・帰宅中なら昼休みは終わり
			continue
		match lunch.phase:
			Phase.NONE:
				# 昼の時刻になったら、オフィスにいる社員は飲食店へ向かう（1日1回）
				if lunch.lunch_day != day and now >= lunch_minute(office, day) and now < LUNCH_END \
						and resident.cell == office and not resident.is_moving():
					lunch.lunch_day = day
					var restaurant = find_nearest_restaurant(resident.cell)
					if restaurant != null:
						# 社員ごとに店の中の座るマスを変える（重ならないように）
						var seats: Array[Vector2i] = world.get_unit_cells(restaurant)
						var seat: Vector2i = seats[absi(hash(office)) % seats.size()]
						if resident.go_to(seat):
							lunch.restaurant = restaurant
							lunch.seat = seat
							lunch.phase = Phase.GOING
			Phase.GOING:
				if not RESTAURANTS.has(world.get_building_type(lunch.restaurant)):
					go_back(lunch, resident, office) # 店がなくなった
				elif resident.cell == lunch.seat and not resident.is_moving():
					lunch.phase = Phase.EATING
					lunch.eat_left = RESTAURANTS[world.get_building_type(lunch.restaurant)].minutes
			Phase.EATING:
				lunch.eat_left -= minutes
				if lunch.eat_left <= 0.0:
					revenue_by_day[day] = revenue_by_day.get(day, 0) + RESTAURANTS[world.get_building_type(lunch.restaurant)].price
					meals_by_day[day] = meals_by_day.get(day, 0) + 1
					go_back(lunch, resident, office)
			Phase.RETURNING:
				if not resident.is_moving():
					if resident.cell == office or not resident.go_to(office):
						lunch.phase = Phase.NONE

func go_back(lunch: Dictionary, resident, office: Vector2i) -> void:
	lunch.restaurant = null
	lunch.seat = null
	lunch.phase = Phase.RETURNING if resident.go_to(office) else Phase.NONE

# 昼に出かける時刻は、オフィスと日ごとに決まった乱数で決める
func lunch_minute(office: Vector2i, day: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([office, day, "lunch"])
	return rng.randi_range(LUNCH_START, LUNCH_END - 1)

# 経路が一番短い飲食店の左端のマス（たどり着ける店がなければnull）
func find_nearest_restaurant(from: Vector2i):
	var best = null
	var best_length := 0
	for type in RESTAURANTS:
		for cell: Vector2i in world.find_units_of_type(type):
			var path: Array[Vector2i] = world.find_path(from, cell)
			if not path.is_empty() and (best == null or path.size() < best_length):
				best = cell
				best_length = path.size()
	return best

# 指定した飲食店で食事中の客の数（店のどのマスを指定してもよい）
func count_eating_at(cell: Vector2i) -> int:
	if world.building_grid.has(cell):
		cell = world.building_grid[cell].origin
	var n := 0
	for office in lunches:
		if lunches[office].phase == Phase.EATING and lunches[office].restaurant == cell:
			n += 1
	return n
