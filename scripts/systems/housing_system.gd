extends Node

# ---------------------------------------------------
# 住宅：横に何マスかの建物（ユニット）で、1ユニット = 1世帯。住宅は左端のマスで表す。
#   家族の人数は住宅のマス数と同じで、1人ずつ自分のマス（部屋）を持つ。
#   入居:     まだ入居していない住宅には、夕方に入口から家族が来る。
#             最初の1人が家に着いたら入居が決まり、販売収入 SALE_PRICE が1回だけ入る。
#             販売収入は建設費より少し安い（建てるだけでお金が増えて、いくらでも建て増せてしまわないように）。
#             そのかわり、入居している間は毎日の決算で管理費 MANAGEMENT_FEE が入る。
#   毎日:     家族はそれぞれ、朝 LEAVE_START〜LEAVE_END に家から入口へ出かけ（ビルの外に出る）、
#             夕方 RETURN_START〜RETURN_END に入口から家に帰ってくる。
#   休日:     ゆっくり HOLIDAY_LEAVE_START〜HOLIDAY_LEAVE_END に出かけ、
#             HOLIDAY_RETURN_START〜HOLIDAY_RETURN_END に帰ってくる。
# 建設・撤去のたびに rebuild() を呼んで、住宅と入居者の対応を更新する。
# ---------------------------------------------------

const LEAVE_START := 7 * 60
const LEAVE_END := 9 * 60
const RETURN_START := 17 * 60
const RETURN_END := 20 * 60
const HOLIDAY_LEAVE_START := 10 * 60
const HOLIDAY_LEAVE_END := 12 * 60
const HOLIDAY_RETURN_START := 15 * 60
const HOLIDAY_RETURN_END := 18 * 60
const SALE_PRICE := 350000     # 販売収入（建設費40万Crより少し安い）
const MANAGEMENT_FEE := 3000   # 入居している住宅1戸から、毎日入る管理費
const RESIDENT_COLOR := Color(0.65, 1.0, 0.6)

var world: Node2D # main.gd

# 住宅の左端のマス -> {moved_in, members}
#   moved_in: 入居が決まっているか
#   members:  家族1人ずつの情報 [{room, resident, out_day, back_day, leaving}, ...]
#     room:      その人の部屋のマス
#     resident:  ビルの中にいる間の住人ノード（外出中はnull）
#     out_day:   最後に朝出かけた日
#     back_day:  最後に夕方帰ってきた（入口に現れた）日
#     leaving:   出かけるために入口へ向かっているか
var homes: Dictionary = {}
var revenue_by_day: Dictionary = {} # 日 -> その日の住宅の販売収入

func setup(p_world: Node2D) -> void:
	world = p_world

func rebuild() -> void:
	var origins: Array[Vector2i] = []
	for cell in world.find_cells_of_type("housing"):
		if world.building_grid[cell].origin != cell:
			continue # 住宅は左端のマスで表す
		origins.append(cell)
		if not homes.has(cell):
			var members := []
			for room in world.get_unit_cells(cell):
				members.append({"room": room, "resident": null, "out_day": 0, "back_day": 0, "leaving": false})
			homes[cell] = {"moved_in": false, "members": members}
	for cell in homes.keys():
		if not origins.has(cell):
			for m in homes[cell].members:
				if is_instance_valid(m.resident):
					m.resident.queue_free() # 家がなくなった入居者は出ていく
			homes.erase(cell)

func _process(_delta: float) -> void:
	var day: int = world.clock.day
	var now: int = world.clock.minute_of_day()
	for cell in homes:
		if world.tenant_system.is_home_vacant(cell):
			continue # 家族が退去した後、次の入居者を募集するまでは誰も来ない
		for m in homes[cell].members:
			process_member(cell, homes[cell], m, day, now)

func process_member(cell: Vector2i, home: Dictionary, m: Dictionary, day: int, now: int) -> void:
	var resident = m.resident
	if not is_instance_valid(resident):
		m.resident = null
		m.leaving = false
		# 夕方になったら入口に現れて家に向かう（まだ入居前なら、入居しに来る）
		if m.back_day != day and now >= return_minute(m.room, day) and now < return_end(day):
			m.back_day = day
			spawn_at_entrance(m)
		return

	if m.leaving:
		# 入口に着いたらビルの外へ出る。経路が途切れたら探し直す
		if not resident.is_moving():
			var entrance = world.nearest_entrance(resident.cell)
			if entrance == null or resident.cell == entrance or not resident.go_to(entrance):
				resident.queue_free()
				m.resident = null
				m.leaving = false
		return

	var at_home: bool = resident.cell == m.room and not resident.is_moving()
	if at_home and not home.moved_in:
		# 家族の最初の1人が家に着いた → 入居が決まり、販売収入が入る
		home.moved_in = true
		revenue_by_day[day] = revenue_by_day.get(day, 0) + SALE_PRICE
		world.show_message("住宅 %s に入居者が決まりました（販売収入 +%s）" % [cell, world.money_text(SALE_PRICE)])
	# 朝になったら入口へ出かける（家に着いてから）
	if at_home and m.out_day != day and now >= leave_minute(m.room, day) and now < return_start(day):
		m.out_day = day
		var entrance = world.nearest_entrance(resident.cell)
		if entrance != null and resident.go_to(entrance):
			m.leaving = true

# 家族が退去する（評価の悪い日が続いたとき）。家族はビルから出ていき、住宅は入居前の状態に戻る。
# 戻り値: 返金する販売収入
func move_out(origin: Vector2i) -> int:
	var home = homes[origin]
	for m in home.members:
		if is_instance_valid(m.resident):
			m.resident.queue_free()
		m.resident = null
		m.leaving = false
	home.moved_in = false
	return SALE_PRICE

func spawn_at_entrance(m: Dictionary) -> void:
	var entrance = world.nearest_entrance(m.room)
	if entrance == null:
		return
	var resident = world.spawn_resident(entrance)
	resident.base_color = RESIDENT_COLOR
	resident.go_to(m.room)
	m.resident = resident

# 出かける・帰る時刻（平日と休日で時間帯が違う）。家族1人ずつ（部屋ごと）に違う
func leave_minute(room: Vector2i, day: int) -> int:
	if world.clock.is_holiday(day):
		return random_minute(room, day + 1000, HOLIDAY_LEAVE_START, HOLIDAY_LEAVE_END)
	return random_minute(room, day + 1000, LEAVE_START, LEAVE_END)

func return_minute(room: Vector2i, day: int) -> int:
	return random_minute(room, day, return_start(day), return_end(day))

func return_start(day: int) -> int:
	return HOLIDAY_RETURN_START if world.clock.is_holiday(day) else RETURN_START

func return_end(day: int) -> int:
	return HOLIDAY_RETURN_END if world.clock.is_holiday(day) else RETURN_END

# 部屋と日ごとに決まった乱数で時刻を決める（毎回同じ結果になり、テストしやすい）
func random_minute(room: Vector2i, salt: int, from: int, to: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([room, salt, "housing"])
	return rng.randi_range(from, to - 1)

# 入居済みの住宅（世帯）の数
func count_moved_in() -> int:
	var n := 0
	for cell in homes:
		if homes[cell].moved_in:
			n += 1
	return n

# 入居済みの住宅に住んでいる人数（人口に数える）
func count_residents() -> int:
	var n := 0
	for cell in homes:
		if homes[cell].moved_in:
			n += homes[cell].members.size()
	return n

# 家にいる入居者の数
func count_at_home() -> int:
	var n := 0
	for cell in homes:
		for m in homes[cell].members:
			if is_at_home(m):
				n += 1
	return n

func is_at_home(m: Dictionary) -> bool:
	return is_instance_valid(m.resident) and m.resident.cell == m.room and not m.resident.is_moving()

# 指定マスを含む住宅の状態（住宅のどのマスを指定してもよい）
func get_home_state_text(cell: Vector2i) -> String:
	if world.building_grid.has(cell):
		cell = world.building_grid[cell].origin
	if not homes.has(cell):
		return ""
	var home = homes[cell]
	if not home.moved_in:
		return "入居者募集中"
	var at_home := 0
	for m in home.members:
		if is_at_home(m):
			at_home += 1
	return "在宅 %d/%d人" % [at_home, home.members.size()]
