extends Node

# ---------------------------------------------------
# 外から来るお客さん（店の客・車で来た客）の共通の動き。
#   1人のお客さん（visit）は、出発のマス（入口や駐車場）に現れて店の席へ向かい、
#   stay 分そこで過ごして代金を払い、出発のマスに戻って帰る（そこで消える）。
#   席まで行けないお客さんは来ない。
#
# 店の客: 店（飲食店・ショップ）ごとに、平日と休日で決まった人数が入口から来る。
#   平日は昼（社員の昼食に外からの客が加わる）、休日は昼から夕方まで。
# 車で来た客: parking_system が駐車場のマスを出発にして add_visit() で足す。
# ---------------------------------------------------

# 店の種類ごとの設定
#   price:   1人が払う代金   stay: 店にいる時間（分）
#   weekday/holiday: 店1軒あたりの、その日に外から来る客の数
#   revenue: 売上をどの項目に入れるか（"food" = 飲食 / "shop" = ショップ）
const SHOP_TYPES := {
	"restaurant": {"price": 1000, "stay": 30.0, "weekday": 2, "holiday": 8, "revenue": "food",
		"color": Color(1.0, 0.8, 0.5)},  # 飲食店の外からの客（うすいオレンジ）
	"shop": {"price": 1500, "stay": 20.0, "weekday": 3, "holiday": 10, "revenue": "shop",
		"color": Color(0.95, 0.65, 0.85)}, # ショップの客（ピンク）
}
const WEEKDAY_START := 11 * 60 # 平日に来はじめる時刻
const WEEKDAY_END := 14 * 60
const HOLIDAY_START := 10 * 60 # 休日に来はじめる時刻
const HOLIDAY_END := 17 * 60

enum Phase { GOING, STAYING, LEAVING }

var world: Node2D # main.gd

var visits: Array = []       # 今日のお客さん
var plan_day := 0            # 最後に店の客の予定を立てた日
var revenue_by_day := {}     # 日 -> その日のショップの売上（飲食店の売上は commerce_system に入れる）
var customers_by_day := {}   # 日 -> その日に店で過ごした外からの客の数

func setup(p_world: Node2D) -> void:
	world = p_world

func is_shop_type(type: String) -> bool:
	return SHOP_TYPES.has(type)

func _process(_delta: float) -> void:
	var day: int = world.clock.day
	var now: int = world.clock.minute_of_day()
	var minutes: float = world.clock.last_advance # このフレームで進んだゲーム内の分数
	var start: int = HOLIDAY_START if world.clock.is_holiday(day) else WEEKDAY_START
	var end: int = HOLIDAY_END if world.clock.is_holiday(day) else WEEKDAY_END
	if plan_day != day and now >= start and now < end:
		plan_day = day
		visits = visits.filter(func(v): return is_instance_valid(v.resident)) # 前日の残りは帰るまで動かす
		plan_shop_visits(day, start, end)
	for v in visits:
		process_visit(v, day, now, minutes)

# その日、店に来るお客さんの予定を立てる（店と日ごとに決まった乱数なので、毎回同じ結果になる）
func plan_shop_visits(day: int, start: int, end: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([day, "shop"])
	var holiday: bool = world.clock.is_holiday(day)
	for type in SHOP_TYPES:
		var info: Dictionary = SHOP_TYPES[type]
		for unit in world.find_units_of_type(type):
			var seats: Array[Vector2i] = world.get_unit_cells(unit)
			var count: int = info.holiday if holiday else info.weekday
			for i in count:
				var seat: Vector2i = seats[i % seats.size()]
				var entrance = world.nearest_entrance(seat)
				if entrance == null:
					continue # 入口から行けない店には客が来ない
				add_visit(entrance, seat, type, rng.randi_range(start, end - 1), Vector2(-4 + 4 * (i % 3), 0))

# お客さんを1人増やす（出発のマス・店の席・来る時刻を決める）。作った記録を返す
func add_visit(start_cell: Vector2i, seat: Vector2i, type: String, arrive: int, offset := Vector2.ZERO) -> Dictionary:
	var visit := {
		"start": start_cell, "seat": seat, "type": type, "arrive": arrive, "offset": offset,
		"color": SHOP_TYPES[type].color, "stay_left": 0.0, "phase": Phase.GOING,
		"resident": null, "spawned": false, "paid": false,
	}
	visits.append(visit)
	return visit

func process_visit(v: Dictionary, day: int, now: int, minutes: float) -> void:
	var info: Dictionary = SHOP_TYPES[v.type]
	# 来る時刻になったら出発のマスに現れて、店へ向かう（行けなければ来ない）
	if not v.spawned:
		if now >= v.arrive:
			v.spawned = true
			if world.get_building_type(v.seat) != v.type:
				return # 店がなくなった
			v.resident = world.spawn_resident(v.start)
			v.resident.base_color = v.color
			v.resident.sprite_offset = v.offset
			if not v.resident.go_to(v.seat):
				v.resident.queue_free()
				v.resident = null
		return
	var resident = v.resident
	if not is_instance_valid(resident):
		return
	match v.phase:
		Phase.GOING:
			if world.get_building_type(v.seat) != v.type:
				start_leaving(v) # 店がなくなったら帰る
			elif resident.cell == v.seat and not resident.is_moving():
				v.phase = Phase.STAYING
				v.stay_left = info.stay
				pay(v, info, day)
		Phase.STAYING:
			v.stay_left -= minutes
			if v.stay_left <= 0.0 or world.get_building_type(v.seat) != v.type:
				start_leaving(v)
		Phase.LEAVING:
			# 出発のマスに戻ったら帰る（住人は消える）
			if not resident.is_moving():
				if resident.cell == v.start or world.find_path(resident.cell, v.start).is_empty():
					resident.queue_free()
					v.resident = null
				else:
					send_home(v)

# 代金を払う（飲食店の売上は commerce_system に、ショップの売上はここに足す）
func pay(v: Dictionary, info: Dictionary, day: int) -> void:
	if v.paid:
		return
	v.paid = true
	customers_by_day[day] = customers_by_day.get(day, 0) + 1
	if info.revenue == "food":
		world.commerce_system.revenue_by_day[day] = world.commerce_system.revenue_by_day.get(day, 0) + info.price
	else:
		revenue_by_day[day] = revenue_by_day.get(day, 0) + info.price

func start_leaving(v: Dictionary) -> void:
	v.phase = Phase.LEAVING
	send_home(v)

func send_home(v: Dictionary) -> void:
	if not v.resident.go_to(v.start):
		v.resident.queue_free()
		v.resident = null

# 今ビルの中にいる、外から来たお客さんの数
func count_visitors() -> int:
	var count := 0
	for v in visits:
		if is_instance_valid(v.resident):
			count += 1
	return count

# 指定した店にいる外からの客の数（店のどのマスを指定してもよい）
func count_at_shop(cell: Vector2i) -> int:
	if not world.building_grid.has(cell):
		return 0
	var cells: Array[Vector2i] = world.get_unit_cells(cell)
	var count := 0
	for v in visits:
		if v.phase == Phase.STAYING and is_instance_valid(v.resident) and cells.has(v.resident.cell):
			count += 1
	return count
