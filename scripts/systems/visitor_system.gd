extends Node

# ---------------------------------------------------
# 外から来るお客さん（店の客・車で来た客）の共通の動き。
#   1人のお客さん（visit）は、出発のマス（入口や駐車場）に現れて店の席へ向かい、
#   stay 分そこで過ごして代金を払い、出発のマスに戻って帰る（そこで消える）。
#   席まで行けないお客さんは来ない。
#
# 店の客: 店（飲食店・ショップ）ごとに、平日と休日で決まった人数が入口から来る。
#   雨の日は人数が減り（weather_system.visitor_rate）、地下鉄駅があると増える（subway_rate）。
#   平日は昼（社員の昼食に外からの客が加わる）、休日は昼から夕方まで。
# 車で来た客: parking_system が駐車場のマスを出発にして add_visit() で足す。
# 映画館の客: 上映時刻（CINEMA.shows）の少し前に一斉に来て、上映が終わると一斉に帰る。
#   駐車場が使えるぶんだけ、1回の客が増える。
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
# 映画館: 上映時刻に客が一斉に来て、上映が終わると一斉に帰る
#   shows/shows_holiday: 上映の開始時刻   length: 上映時間（分）
#   audience/audience_holiday: 1回の上映の客数   parking_bonus: 使える駐車場1台につき増える客数（上限あり）
const CINEMA := {
	"price": 1800, "stay": 120.0, "revenue": "cinema", "color": Color(0.85, 0.6, 0.95), # 映画の客（むらさき）
	"shows": [13 * 60, 16 * 60, 19 * 60], "shows_holiday": [11 * 60, 14 * 60, 17 * 60, 20 * 60],
	"length": 120, "audience": 10, "audience_holiday": 16, "arrive_before": 30, "parking_bonus_max": 8,
}
const SUBWAY_BONUS := 0.5      # 地下鉄駅1つにつき、外から来るお客さんが何割増えるか
const SUBWAY_BONUS_MAX := 2.0  # 増える割合の上限（2倍まで）
const WEEKDAY_START := 11 * 60 # 平日に来はじめる時刻
const WEEKDAY_END := 14 * 60
const HOLIDAY_START := 10 * 60 # 休日に来はじめる時刻
const HOLIDAY_END := 17 * 60

enum Phase { GOING, STAYING, LEAVING }

var world: Node2D # main.gd

var visits: Array = []       # 今日のお客さん
var plan_day := 0            # 最後に店の客の予定を立てた日
var revenue_by_day := {}     # 日 -> その日のショップの売上（飲食店の売上は commerce_system に入れる）
var cinema_revenue_by_day := {} # 日 -> その日の映画館の売上
var cinema_audience_by_day := {} # 日 -> その日に映画を見た客の数
var customers_by_day := {}   # 日 -> その日に店で過ごした外からの客の数

func setup(p_world: Node2D) -> void:
	world = p_world

func is_shop_type(type: String) -> bool:
	return SHOP_TYPES.has(type)

# 地下鉄駅があると、外から来るお客さんが増える（駅からの人の流入）
func subway_rate() -> float:
	return minf(1.0 + SUBWAY_BONUS * world.find_units_of_type("subway").size(), SUBWAY_BONUS_MAX)

# お客さんの種類ごとの設定（店と映画館）
func visit_info(type: String) -> Dictionary:
	return CINEMA if type == "cinema" else SHOP_TYPES[type]

# 今日の上映時刻の一覧
func showtimes(day: int) -> Array:
	return CINEMA.shows_holiday if world.clock.is_holiday(day) else CINEMA.shows

func _process(_delta: float) -> void:
	var day: int = world.clock.day
	var now: int = world.clock.minute_of_day()
	var minutes: float = world.clock.last_advance # このフレームで進んだゲーム内の分数
	var start: int = HOLIDAY_START if world.clock.is_holiday(day) else WEEKDAY_START
	var end: int = HOLIDAY_END if world.clock.is_holiday(day) else WEEKDAY_END
	# 映画館は上映時刻が夜まであるので、店の客より早い時刻から予定を立てる
	var plan_from: int = mini(start, showtimes(day)[0] - CINEMA.arrive_before)
	if plan_day != day and now >= plan_from and now < end:
		plan_day = day
		visits = visits.filter(func(v): return is_instance_valid(v.resident)) # 前日の残りは帰るまで動かす
		plan_shop_visits(day, start, end)
		plan_cinema_visits(day)
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
			# 雨の日は減り、地下鉄駅があると増える
			var count := int((info.holiday if holiday else info.weekday) * world.weather_system.visitor_rate() * subway_rate())
			for i in count:
				var seat: Vector2i = seats[i % seats.size()]
				var entrance = world.nearest_entrance(seat)
				if entrance == null:
					continue # 入口から行けない店には客が来ない
				add_visit(entrance, seat, type, rng.randi_range(start, end - 1), Vector2(-4 + 4 * (i % 3), 0))

# その日の上映ごとに、来るお客さんの予定を立てる。
# 上映の arrive_before 分前から少しずつ集まり、上映が終わると一斉に帰る
func plan_cinema_visits(day: int) -> void:
	var cinemas: Array[Vector2i] = world.find_units_of_type("cinema")
	if cinemas.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([day, "cinema"])
	var holiday: bool = world.clock.is_holiday(day)
	var base: int = CINEMA.audience_holiday if holiday else CINEMA.audience
	# 駐車場が使えるぶんだけ客が増える（映画館は車で来る人が多い）
	var bonus: int = mini(world.parking_system.car_capacity(), CINEMA.parking_bonus_max)
	base = int(base * subway_rate()) # 地下鉄駅からも客が来る
	for unit in cinemas:
		var seats: Array[Vector2i] = world.get_unit_cells(unit).filter(func(c): return c.y == unit.y)
		for show in showtimes(day):
			for i in base + bonus:
				var seat: Vector2i = seats[i % seats.size()]
				var entrance = world.nearest_entrance(seat)
				if entrance == null:
					continue # 入口から行けない映画館には客が来ない
				var visit := add_visit(entrance, seat, "cinema", rng.randi_range(show - CINEMA.arrive_before, show - 5),
					Vector2([-4, 0, 4][(i / seats.size()) % 3], 0))
				visit["leave_at"] = show + CINEMA.length # 上映が終わったら一斉に帰る

# お客さんを1人増やす（出発のマス・店の席・来る時刻を決める）。作った記録を返す
func add_visit(start_cell: Vector2i, seat: Vector2i, type: String, arrive: int, offset := Vector2.ZERO) -> Dictionary:
	var visit := {
		"start": start_cell, "seat": seat, "type": type, "arrive": arrive, "offset": offset,
		"color": visit_info(type).color, "stay_left": 0.0, "phase": Phase.GOING,
		"resident": null, "spawned": false, "paid": false,
	}
	visits.append(visit)
	return visit

func process_visit(v: Dictionary, day: int, now: int, minutes: float) -> void:
	var info: Dictionary = visit_info(v.type)
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
			# 映画館は上映が終わる時刻に一斉に帰る。店は決まった時間だけいて帰る
			var done: bool = now >= v.leave_at if v.has("leave_at") else v.stay_left <= 0.0
			if done or world.get_building_type(v.seat) != v.type:
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
	match info.revenue:
		"food":
			world.commerce_system.revenue_by_day[day] = world.commerce_system.revenue_by_day.get(day, 0) + info.price
		"cinema":
			cinema_revenue_by_day[day] = cinema_revenue_by_day.get(day, 0) + info.price
			cinema_audience_by_day[day] = cinema_audience_by_day.get(day, 0) + 1
		_:
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

# カーソル下の説明用: 次の上映時刻と、今いる客の数
func get_cinema_text(cell: Vector2i) -> String:
	var now: int = world.clock.minute_of_day()
	var next_show := -1
	for show in showtimes(world.clock.day):
		if show >= now and next_show < 0:
			next_show = show
	var text := "客 %d人" % count_at_shop(cell)
	if next_show >= 0:
		text += "・次の上映 %d:%02d" % [next_show / 60, next_show % 60]
	else:
		text += "・今日の上映は終わり"
	return text

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
