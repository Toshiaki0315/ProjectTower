extends Node

# ---------------------------------------------------
# 地下駐車場とスロープ：車で来る外からのお客さん。
#   スロープ（地下1階）は、1階から車で下りてくる道。
#   駐車場は、スロープから車で行ける（＝歩いて行ける）場所にあるときだけ使える。
#   使える駐車場1棟につき CARS_PER_UNIT 台、1台につき PEOPLE_PER_CAR 人が来て、
#   VISIT_START〜VISIT_END の間のランダムな時刻に自分の車のマスに現れ、
#   一番近い飲食店で EAT_MINUTES 分食事をして（代金は飲食店の売上になる）、車に戻って帰る。
#   飲食店が1つもない日は、誰も来ない。
# 建設・撤去のたびに rebuild() を呼んで、使える駐車場を数え直す。
# ---------------------------------------------------

const CARS_PER_UNIT := 4      # 駐車場1棟に停められる車の数
const PEOPLE_PER_CAR := 2     # 車1台に乗ってくる人数
const VISIT_START := 11 * 60  # 来はじめる時刻
const VISIT_END := 14 * 60    # 来おわる時刻
const LEAVE_SPREAD := 30      # 食事の後、帰り始めるまでのばらつき（分）
const VISITOR_COLOR := Color(0.55, 0.85, 0.6) # 車で来たお客さんの色（緑）

enum Phase { GOING, EATING, LEAVING }

var world: Node2D # main.gd

var usable_units: Array[Vector2i] = [] # 使える駐車場（左端のマス）の一覧
var visitors: Array = []               # 今日の来客 [{car, seat, arrive, eat_left, phase, resident, spawned, paid}, ...]
var visit_day := 0                     # 最後に来客の予定を立てた日
var visitors_by_day := {}              # 日 -> その日に食事をした車の客の数

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
	var minutes: float = world.clock.last_advance # このフレームで進んだゲーム内の分数
	# その日の朝、来客の予定を立てる
	if visit_day != day and now >= VISIT_START and now < VISIT_END:
		visit_day = day
		visitors = plan_visitors(day)
	for v in visitors:
		process_visitor(v, day, now, minutes)

# 来客ごとの停めるマス・来る時刻を、日ごとに決まった乱数で決める（毎回同じ結果になり、テストしやすい）
func plan_visitors(day: int) -> Array:
	if world.find_units_of_type("restaurant").is_empty():
		return [] # 行き先（飲食店）がなければ誰も来ない
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([day, "parking"])
	var planned := []
	for unit in usable_units:
		var spots: Array[Vector2i] = world.get_unit_cells(unit)
		for car in CARS_PER_UNIT:
			var arrive := rng.randi_range(VISIT_START, VISIT_END - 1)
			for i in PEOPLE_PER_CAR:
				planned.append({
					"car": spots[car % spots.size()], # 停める（＝現れて、帰っていく）マス
					"seat": null, "arrive": arrive, "eat_left": 0.0, "phase": Phase.GOING,
					"offset": Vector2(-4 + 8 * i, 0), "resident": null, "spawned": false, "paid": false,
				})
	return planned

func process_visitor(v: Dictionary, day: int, now: int, minutes: float) -> void:
	# 来る時刻になったら、停めたマスに現れて飲食店へ向かう（行けなければ来ない）
	if not v.spawned:
		if now >= v.arrive:
			v.spawned = true
			if world.get_building_type(v.car) != "parking":
				return
			var seat = find_seat(v.car)
			if seat == null:
				return
			v.resident = world.spawn_resident(v.car)
			v.resident.base_color = VISITOR_COLOR
			v.resident.sprite_offset = v.offset
			v.seat = seat
			if not v.resident.go_to(seat):
				v.resident.queue_free()
				v.resident = null
		return
	var resident = v.resident
	if not is_instance_valid(resident):
		return
	match v.phase:
		Phase.GOING:
			if resident.cell == v.seat and not resident.is_moving():
				v.phase = Phase.EATING
				v.eat_left = world.commerce_system.EAT_MINUTES
		Phase.EATING:
			v.eat_left -= minutes
			if not v.paid:
				v.paid = true
				world.commerce_system.revenue_by_day[day] = world.commerce_system.revenue_by_day.get(day, 0) \
					+ world.commerce_system.MEAL_PRICE
				visitors_by_day[day] = visitors_by_day.get(day, 0) + 1
			if v.eat_left <= 0.0:
				v.phase = Phase.LEAVING
				go_home(v)
		Phase.LEAVING:
			# 車のマスに戻ったら、車で帰る（住人は消える）
			if not resident.is_moving():
				if resident.cell == v.car or world.find_path(resident.cell, v.car).is_empty():
					resident.queue_free()
					v.resident = null
				else:
					go_home(v)

func go_home(v: Dictionary) -> void:
	if not v.resident.go_to(v.car):
		v.resident.queue_free()
		v.resident = null

# 停めたマスから一番近い飲食店の席（なければnull）
func find_seat(from: Vector2i):
	var best = null
	var best_length := 0
	for restaurant in world.find_units_of_type("restaurant"):
		for seat in world.get_unit_cells(restaurant):
			var path: Array[Vector2i] = world.find_path(from, seat)
			if not path.is_empty() and (best == null or path.size() < best_length):
				best = seat
				best_length = path.size()
	return best

# 今ビルの中にいる、車で来たお客さんの数
func count_visitors() -> int:
	var count := 0
	for v in visitors:
		if is_instance_valid(v.resident):
			count += 1
	return count

# カーソル下の説明用（駐車場のどのマスを指定してもよい）
func get_parking_text(cell: Vector2i) -> String:
	var origin: Vector2i = world.building_grid[cell].origin
	if not usable_units.has(origin):
		return "スロープにつながっていないので使えません"
	return "%d台" % CARS_PER_UNIT
