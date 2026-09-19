extends Node

# ---------------------------------------------------
# オフィスの通勤：オフィス1マスにつき社員1人。
#   出勤: ARRIVE_START〜ARRIVE_END の間のランダムな時刻に入口に現れ、自分のオフィスへ向かう
#   退勤: LEAVE_START〜LEAVE_END の間のランダムな時刻に入口へ向かい、着いたら帰る（消える）
# 入口からたどり着けないオフィスの社員は出勤できない（通勤不可として数える）。
# 建設・撤去のたびに rebuild() を呼んで、オフィスと社員の対応を更新する。
# ---------------------------------------------------

const ARRIVE_START := 8 * 60
const ARRIVE_END := 9 * 60
const LEAVE_START := 17 * 60
const LEAVE_END := 18 * 60

var world: Node2D # main.gd

# オフィスのマス -> 社員の情報
#   arrive, leave:  出勤・退勤する時刻（その日の経過分）
#   resident:       ビルの中にいる間の住人ノード（いなければnull）
#   arrived_day:    最後に出勤した日（同じ日に2回出勤しないため）
#   leaving:        帰宅中か
#   unreachable:    今日、入口からオフィスにたどり着けず出勤できなかったか
var workers: Dictionary = {}

func setup(p_world: Node2D) -> void:
	world = p_world

# オフィスの増減に合わせて社員を登録・削除する
func rebuild() -> void:
	var offices: Array[Vector2i] = world.find_cells_of_type("office")
	for cell in offices:
		if not workers.has(cell):
			workers[cell] = create_worker(cell)
	for cell in workers.keys():
		if not offices.has(cell):
			var resident = workers[cell].resident
			if is_instance_valid(resident):
				resident.queue_free() # オフィスがなくなった社員は帰る
			workers.erase(cell)

# 出退勤の時刻はマスごとに決まった乱数で決める（毎回同じ結果になり、テストしやすい）
func create_worker(cell: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(cell)
	return {
		"arrive": rng.randi_range(ARRIVE_START, ARRIVE_END - 1),
		"leave": rng.randi_range(LEAVE_START, LEAVE_END - 1),
		"resident": null,
		"arrived_day": 0,
		"leaving": false,
		"unreachable": false,
	}

func _process(_delta: float) -> void:
	var day: int = world.clock.day
	var now: int = world.clock.minute_of_day()
	for cell in workers:
		var w = workers[cell]
		# 出勤の時刻になったら、入口に現れてオフィスへ向かう
		if w.arrived_day != day and now >= w.arrive and now < w.leave:
			w.arrived_day = day
			w.unreachable = not start_commute(cell, w)
		var resident = w.resident
		if not is_instance_valid(resident):
			w.resident = null
			w.leaving = false
			continue
		# 退勤の時刻になったら入口へ向かう（エレベーターに乗っている間は降りてから）
		if not w.leaving and now >= w.leave and resident.state != resident.State.RIDING:
			w.leaving = true
			send_home(w)
		# 帰宅中に入口に着いたら帰る。経路が途切れて立ち止まったら探し直す
		elif w.leaving and not resident.is_moving():
			var entrance = world.get_entrance()
			if entrance != null and resident.cell == entrance:
				resident.queue_free()
				w.resident = null
				w.leaving = false
			else:
				send_home(w)

func start_commute(cell: Vector2i, w: Dictionary) -> bool:
	var entrance = world.get_entrance()
	if entrance == null or world.find_path(entrance, cell).is_empty():
		return false
	var resident = world.spawn_resident(entrance)
	resident.go_to(cell)
	w.resident = resident
	w.leaving = false
	return true

# 入口へ向かわせる。たどり着けなければ、その場で帰ったことにする
func send_home(w: Dictionary) -> void:
	var entrance = world.get_entrance()
	if entrance == null or (w.resident.cell != entrance and not w.resident.go_to(entrance)):
		w.resident.queue_free()
		w.resident = null
		w.leaving = false

# ---------------------------------------------------
# 集計（UI表示やテスト用）
# ---------------------------------------------------

# ビルの中にいる社員の数（通勤中・在社中・帰宅中を含む）
func count_in_building() -> int:
	var n := 0
	for cell in workers:
		if is_instance_valid(workers[cell].resident):
			n += 1
	return n

# 自分のオフィスに着いている社員の数
func count_at_office() -> int:
	var n := 0
	for cell in workers:
		var resident = workers[cell].resident
		if is_instance_valid(resident) and resident.cell == cell and not resident.is_moving():
			n += 1
	return n

# 今日、入口からたどり着けず出勤できなかった社員の数
func count_unreachable() -> int:
	var n := 0
	for cell in workers:
		if workers[cell].unreachable:
			n += 1
	return n
