extends Node

# ---------------------------------------------------
# 住宅：1マス = 1世帯（入居者1人）。
#   入居:     まだ入居者がいない住宅には、RETURN_START〜RETURN_END の間に入口から入居者が来る。
#             家に着いたら入居が決まり、販売収入 SALE_PRICE が1回だけ入る。
#   毎日:     朝 LEAVE_START〜LEAVE_END に家から入口へ出かけ（ビルの外に出る）、
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
const SALE_PRICE := 250000
const RESIDENT_COLOR := Color(0.65, 1.0, 0.6)

var world: Node2D # main.gd

# 住宅のマス -> {moved_in, resident, out_day, back_day, leaving}
#   moved_in:  入居が決まっているか
#   resident:  ビルの中にいる間の住人ノード（外出中はnull）
#   out_day:   最後に朝出かけた日
#   back_day:  最後に夕方帰ってきた（入口に現れた）日
#   leaving:   出かけるために入口へ向かっているか
var homes: Dictionary = {}
var revenue_by_day: Dictionary = {} # 日 -> その日の住宅の販売収入

func setup(p_world: Node2D) -> void:
	world = p_world

func rebuild() -> void:
	var cells: Array[Vector2i] = world.find_cells_of_type("housing")
	for cell in cells:
		if not homes.has(cell):
			homes[cell] = {"moved_in": false, "resident": null, "out_day": 0, "back_day": 0, "leaving": false}
	for cell in homes.keys():
		if not cells.has(cell):
			if is_instance_valid(homes[cell].resident):
				homes[cell].resident.queue_free() # 家がなくなった入居者は出ていく
			homes.erase(cell)

func _process(_delta: float) -> void:
	var day: int = world.clock.day
	var now: int = world.clock.minute_of_day()
	for cell in homes:
		var home = homes[cell]
		var resident = home.resident
		if not is_instance_valid(resident):
			home.resident = null
			home.leaving = false
			# 夕方になったら入口に現れて家に向かう（まだ入居前なら、入居しに来る）
			if home.back_day != day and now >= return_minute(cell, day) and now < return_end(day):
				home.back_day = day
				spawn_at_entrance(cell, home)
			continue

		if home.leaving:
			# 入口に着いたらビルの外へ出る。経路が途切れたら探し直す
			if not resident.is_moving():
				var entrance = world.nearest_entrance(resident.cell)
				if entrance == null or resident.cell == entrance or not resident.go_to(entrance):
					resident.queue_free()
					home.resident = null
					home.leaving = false
			continue

		var at_home: bool = resident.cell == cell and not resident.is_moving()
		if at_home and not home.moved_in:
			# 初めて家に着いた → 入居が決まり、販売収入が入る
			home.moved_in = true
			revenue_by_day[day] = revenue_by_day.get(day, 0) + SALE_PRICE
			world.show_message("住宅 %s に入居者が決まりました（販売収入 +%s円）" % [cell, world.format_money(SALE_PRICE)])
		# 朝になったら入口へ出かける（家に着いてから）
		if at_home and home.out_day != day and now >= leave_minute(cell, day) and now < return_start(day):
			home.out_day = day
			var entrance = world.nearest_entrance(resident.cell)
			if entrance != null and resident.go_to(entrance):
				home.leaving = true

func spawn_at_entrance(cell: Vector2i, home: Dictionary) -> void:
	var entrance = world.nearest_entrance(cell)
	if entrance == null:
		return
	var resident = world.spawn_resident(entrance)
	resident.base_color = RESIDENT_COLOR
	resident.go_to(cell)
	home.resident = resident

# 出かける・帰る時刻（平日と休日で時間帯が違う）
func leave_minute(cell: Vector2i, day: int) -> int:
	if world.clock.is_holiday(day):
		return random_minute(cell, day + 1000, HOLIDAY_LEAVE_START, HOLIDAY_LEAVE_END)
	return random_minute(cell, day + 1000, LEAVE_START, LEAVE_END)

func return_minute(cell: Vector2i, day: int) -> int:
	return random_minute(cell, day, return_start(day), return_end(day))

func return_start(day: int) -> int:
	return HOLIDAY_RETURN_START if world.clock.is_holiday(day) else RETURN_START

func return_end(day: int) -> int:
	return HOLIDAY_RETURN_END if world.clock.is_holiday(day) else RETURN_END

# 住宅と日ごとに決まった乱数で時刻を決める（毎回同じ結果になり、テストしやすい）
func random_minute(cell: Vector2i, salt: int, from: int, to: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([cell, salt, "housing"])
	return rng.randi_range(from, to - 1)

func count_moved_in() -> int:
	var n := 0
	for cell in homes:
		if homes[cell].moved_in:
			n += 1
	return n

# 家にいる入居者の数
func count_at_home() -> int:
	var n := 0
	for cell in homes:
		var resident = homes[cell].resident
		if is_instance_valid(resident) and resident.cell == cell and not resident.is_moving():
			n += 1
	return n

func get_home_state_text(cell: Vector2i) -> String:
	if not homes.has(cell):
		return ""
	var home = homes[cell]
	if not home.moved_in:
		return "入居者募集中"
	var resident = home.resident
	if is_instance_valid(resident) and resident.cell == cell and not resident.is_moving():
		return "在宅"
	return "外出中"
