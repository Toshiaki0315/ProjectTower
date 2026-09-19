extends Node

# ---------------------------------------------------
# 商業施設（飲食店）：オフィスの社員が昼に食事をしに来る。
#   LUNCH_START〜LUNCH_END の間のランダムな時刻に、自分のオフィスにいる社員が
#   経路が一番近い飲食店へ向かい、EAT_MINUTES 分食事をして、代金 MEAL_PRICE を払ってオフィスへ戻る。
# 社員（住人ノード）は commute_system が管理しており、ここでは昼休みの行き来だけを受け持つ。
# ---------------------------------------------------

enum Phase { NONE, GOING, EATING, RETURNING }

const LUNCH_START := 12 * 60
const LUNCH_END := 13 * 60
const EAT_MINUTES := 30.0
const MEAL_PRICE := 1000

var world: Node2D # main.gd

# オフィスのマス（= 社員） -> {lunch_day, phase, restaurant, eat_left}
var lunches: Dictionary = {}
var revenue_by_day: Dictionary = {} # 日 -> その日の飲食店の売上

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
			lunches[office] = {"lunch_day": 0, "phase": Phase.NONE, "restaurant": null, "eat_left": 0.0}
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
					if restaurant != null and resident.go_to(restaurant):
						lunch.restaurant = restaurant
						lunch.phase = Phase.GOING
			Phase.GOING:
				if world.get_building_type(lunch.restaurant) != "restaurant":
					go_back(lunch, resident, office) # 店がなくなった
				elif resident.cell == lunch.restaurant and not resident.is_moving():
					lunch.phase = Phase.EATING
					lunch.eat_left = EAT_MINUTES
			Phase.EATING:
				lunch.eat_left -= minutes
				if lunch.eat_left <= 0.0:
					revenue_by_day[day] = revenue_by_day.get(day, 0) + MEAL_PRICE
					go_back(lunch, resident, office)
			Phase.RETURNING:
				if not resident.is_moving():
					if resident.cell == office or not resident.go_to(office):
						lunch.phase = Phase.NONE

func go_back(lunch: Dictionary, resident, office: Vector2i) -> void:
	lunch.restaurant = null
	lunch.phase = Phase.RETURNING if resident.go_to(office) else Phase.NONE

# 昼に出かける時刻は、オフィスと日ごとに決まった乱数で決める
func lunch_minute(office: Vector2i, day: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([office, day, "lunch"])
	return rng.randi_range(LUNCH_START, LUNCH_END - 1)

# 経路が一番短い飲食店（たどり着ける店がなければnull）
func find_nearest_restaurant(from: Vector2i):
	var best = null
	var best_length := 0
	for cell: Vector2i in world.find_cells_of_type("restaurant"):
		var path: Array[Vector2i] = world.find_path(from, cell)
		if not path.is_empty() and (best == null or path.size() < best_length):
			best = cell
			best_length = path.size()
	return best

# 指定した飲食店で食事中の客の数
func count_eating_at(cell: Vector2i) -> int:
	var n := 0
	for office in lunches:
		if lunches[office].phase == Phase.EATING and lunches[office].restaurant == cell:
			n += 1
	return n
