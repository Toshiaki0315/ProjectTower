extends Node

# ---------------------------------------------------
# 結婚式場・イベントホール：休日だけ催しがあり、大勢の来客が入口からやって来る。
#   EVENT_TYPES の会場ごとに、
#     arrive_start〜arrive_end の間のランダムな時刻に来客（visitors 人）が入口に現れ、会場へ向かう。
#     会場は横に何マスかの建物で、左端のマスで表す。来客は会場の中のマスに振り分ける。
#     会場に着いたら料金（price）を払う。
#     催しが終わる end の後、少しずつ（LEAVE_SPREAD 分の間に）入口へ帰っていく。
# 建設・撤去のたびに rebuild() を呼んで、会場の対応を更新する。
# ---------------------------------------------------

const EVENT_TYPES := {
	"wedding": {"visitors": 12, "arrive_start": 10 * 60, "arrive_end": 11 * 60, "end": 13 * 60,
		"price": 10000, "color": Color(1.0, 0.95, 0.75)},   # 結婚式場（来客はクリーム色）
	"event_hall": {"visitors": 15, "arrive_start": 13 * 60, "arrive_end": 14 * 60, "end": 17 * 60,
		"price": 3000, "color": Color(1.0, 0.7, 0.35)},     # イベントホール（来客はオレンジ）
}
const LEAVE_SPREAD := 20 # 催しの後、帰り始めるまでのばらつき（分）

var world: Node2D # main.gd

# 会場のマス -> {type, event_day, visitors}
#   event_day: 最後に催しがあった日
#   visitors:  今日の来客の予定と状態 [{arrive, leave, resident, spawned, arrived, leaving}, ...]
var halls: Dictionary = {}
var revenue_by_day: Dictionary = {} # 日 -> その日の来客の料金の合計
var visitors_by_day: Dictionary = {} # 日 -> その日に会場に着いた来客の数

func setup(p_world: Node2D) -> void:
	world = p_world

func rebuild() -> void:
	var cells: Array[Vector2i] = []
	for type in EVENT_TYPES:
		for cell in world.find_cells_of_type(type):
			if world.building_grid[cell].origin != cell:
				continue # 会場は左端のマスで表す
			cells.append(cell)
			if not halls.has(cell):
				halls[cell] = {"type": type, "event_day": 0, "visitors": []}
	for cell in halls.keys():
		if not cells.has(cell):
			for v in halls[cell].visitors:
				if is_instance_valid(v.resident):
					v.resident.queue_free() # 会場がなくなった来客は帰る
			halls.erase(cell)

func _process(_delta: float) -> void:
	var day: int = world.clock.day
	var now: int = world.clock.minute_of_day()
	for cell in halls:
		var hall = halls[cell]
		var info = EVENT_TYPES[hall.type]
		# 休日の朝、その日の来客の予定を立てる
		if world.clock.is_holiday() and hall.event_day != day and now >= info.arrive_start and now < info.end:
			hall.event_day = day
			hall.visitors = plan_visitors(cell, info, day)
		for v in hall.visitors:
			process_visitor(cell, hall, info, v, day, now)

# 来客ごとの来る時刻・帰る時刻を、会場と日ごとに決まった乱数で決める（毎回同じ結果になり、テストしやすい）
func plan_visitors(cell: Vector2i, info: Dictionary, day: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([cell, day, "event"])
	var spots: Array[Vector2i] = world.get_unit_cells(cell)
	var visitors := []
	for i in info.visitors:
		# 来客は会場のマスに順に振り分け、同じマスの人は左右に少しずらして描く
		var lap: int = i / spots.size()
		visitors.append({
			"spot": spots[i % spots.size()],
			"arrive": rng.randi_range(info.arrive_start, info.arrive_end - 1),
			"leave": info.end + rng.randi_range(0, LEAVE_SPREAD),
			"offset": Vector2([0, -4, 4][lap % 3], 0),
			"resident": null, "spawned": false, "arrived": false, "leaving": false,
		})
	return visitors

func process_visitor(_cell: Vector2i, _hall: Dictionary, info: Dictionary, v: Dictionary, day: int, now: int) -> void:
	# 来る時刻になったら入口に現れて会場へ向かう（たどり着けなければ来ない）
	if not v.spawned:
		if now >= v.arrive:
			v.spawned = true
			var route: Array[Vector2i] = world.path_from_nearest_entrance(v.spot)
			if not route.is_empty():
				v.resident = world.spawn_resident(route[0])
				v.resident.base_color = info.color
				v.resident.sprite_offset = v.offset
				v.resident.follow_path(route)
		return
	var resident = v.resident
	if not is_instance_valid(resident):
		return
	# 会場に着いたら料金を払う
	if not v.arrived and resident.cell == v.spot and not resident.is_moving():
		v.arrived = true
		revenue_by_day[day] = revenue_by_day.get(day, 0) + info.price
		visitors_by_day[day] = visitors_by_day.get(day, 0) + 1
	# 催しが終わったら入口へ帰る。入口に着いたら消える
	if not v.leaving and now >= v.leave and resident.state != resident.State.RIDING:
		v.leaving = true
		send_to_entrance(v)
	elif v.leaving and not resident.is_moving():
		if world.is_entrance(resident.cell) or world.nearest_entrance(resident.cell) == null:
			resident.queue_free()
			v.resident = null
		else:
			send_to_entrance(v)

# 入口へ向かわせる。たどり着けなければ、その場で帰ったことにする
func send_to_entrance(v: Dictionary) -> void:
	var route: Array[Vector2i] = world.path_to_nearest_entrance(v.resident.cell)
	if route.is_empty():
		v.resident.queue_free()
		v.resident = null
	elif route.size() > 1: # もう入口にいるなら、そのまま帰る
		v.resident.follow_path(route)

# 指定した会場に着いている来客の数（会場のどのマスを指定してもよい）
func count_at_hall(cell: Vector2i) -> int:
	if world.building_grid.has(cell):
		cell = world.building_grid[cell].origin
	if not halls.has(cell):
		return 0
	var n := 0
	for v in halls[cell].visitors:
		if is_instance_valid(v.resident) and v.arrived and not v.leaving:
			n += 1
	return n

# ビルの中にいる来客の数（向かっている途中・帰る途中も含む）
func count_in_building() -> int:
	var n := 0
	for cell in halls:
		for v in halls[cell].visitors:
			if is_instance_valid(v.resident):
				n += 1
	return n

func is_hall_type(type: String) -> bool:
	return EVENT_TYPES.has(type)
