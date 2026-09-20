extends Node2D

# ---------------------------------------------------
# テナントの評価：オフィス・ホテルの客室・住宅に、人のストレスから 良い・普通・悪い の評価を付ける。
#
# ■ オフィス
#   その日のストレス: 社員一人ひとりについて、その日にたまったストレスの一番高い値を記録する
#                     （通勤や昼食のエレベーター待ちでたまった分）
#   評価:            毎日の決算のときに、その日に出勤した社員の平均で決める（evaluate_day）
#                     平均 < GOOD_BELOW … 良い / < BAD_FROM … 普通 / それ以上 … 悪い
#                     出勤がなかった日（休日など）は前の評価のまま
#   退去:            評価が「悪い」の日が LEAVE_AFTER_BAD_DAYS 日続くと、テナントが退去して空室になる
#                     （空室の間は社員が出勤せず、賃料も入らず、人口にも数えない）
#   入居:            空室になって VACANT_DAYS 日たつと、新しいテナントが入居する（評価は「良い」から）
# ■ ホテルの客室
#   宿泊客がチェックインしてから帰るまでのストレスの一番高い値で、チェックアウトのときに評価が決まる。
#   評価が悪い部屋ほど客が来にくい（CHECKIN_CHANCE: その夜に客が来る確率）。
# ■ 衛生の悪化
#   ゴミ処理が追いつかない日が続くと（economy_system.pollution）、すべてのテナントの評価が下がる。
# ■ 騒音
#   住宅・客室は、まわりの騒音（noise_system）のぶんだけ評価が下がる（騒音1につきストレス6相当）。
# ■ 住宅
#   家族のその日のストレスの一番高い値の平均で、決算のときに評価が決まる。
#   悪い日が LEAVE_AFTER_BAD_DAYS 日続くと家族が退去し、販売収入を返金する。VACANT_DAYS 日後にまた入居者を募集する。
# 建物は左端のマスで表す。左上に評価の顔のマーク、空室なら灰色と「空室」の看板を描く。
# TileMapLayerの子として追加するので、座標はタイルマップ座標系。
# ---------------------------------------------------

enum Rating { GOOD, NORMAL, BAD }

const GOOD_BELOW := 30.0
const BAD_FROM := 60.0
const LEAVE_AFTER_BAD_DAYS := 3 # 評価が悪い日がこの日数続くと退去する
const VACANT_DAYS := 2          # 空室になってから新しいテナントが入居するまでの日数
const CHECKIN_CHANCE := {Rating.GOOD: 1.0, Rating.NORMAL: 0.6, Rating.BAD: 0.2} # 客室の評価ごとの、客が来る確率
const RATING_NAMES := {Rating.GOOD: "良い", Rating.NORMAL: "普通", Rating.BAD: "悪い"}
const RATING_COLORS := {
	Rating.GOOD: Color(0.3, 0.9, 0.4),
	Rating.NORMAL: Color(1.0, 0.85, 0.2),
	Rating.BAD: Color(1.0, 0.3, 0.3),
}

var world: Node2D # main.gd
var day_peak_stress := {} # 社員（オフィスのマス）・住宅の家族（部屋のマス） -> 今日たまったストレスの一番高い値
# オフィス（左端のマス） -> {rating, average, bad_days, vacant, vacant_days}
#   average:     最後に評価した日の、社員のストレスの平均
#   bad_days:    評価が「悪い」の日が続いている日数
#   vacant:      空室か
#   vacant_days: 空室になってからの日数
var offices := {}
var homes := {} # 住宅（左端のマス） -> オフィスと同じ形 {rating, average, bad_days, vacant, vacant_days}
var rooms := {} # 客室（左端のマス） -> {rating, average}（最後に泊まった客のストレス）

func setup(p_world: Node2D) -> void:
	world = p_world
	z_index = 9 # カゴより手前、住人より奥

func _process(_delta: float) -> void:
	# 社員ごとに、今日たまったストレスの一番高い値を記録する
	var workers: Dictionary = world.commute_system.workers
	for cell in workers:
		var resident = workers[cell].resident
		if is_instance_valid(resident):
			day_peak_stress[cell] = maxf(day_peak_stress.get(cell, 0.0), resident.stress)
	# 住宅の家族も同じように記録する（キーはその人の部屋のマス）
	for home in world.housing_system.homes.values():
		for m in home.members:
			if is_instance_valid(m.resident):
				day_peak_stress[m.room] = maxf(day_peak_stress.get(m.room, 0.0), m.resident.stress)
	queue_redraw()

# 決算のときに呼ばれる: その日のストレスからオフィス・住宅の評価を決め、退去・入居を行う
# 戻り値: {"left": 退去したオフィスの数, "moved_in": 入居したオフィスの数,
#          "homes_left": 退去した住宅の数, "refund": 退去した住宅に返金した額}
func evaluate_day(day: int) -> Dictionary:
	var result := {"left": 0, "moved_in": 0, "homes_left": 0, "refund": 0}
	evaluate_homes(result)
	var workers: Dictionary = world.commute_system.workers
	var origins: Array[Vector2i] = world.find_units_of_type("office")
	for origin in origins:
		if not offices.has(origin):
			offices[origin] = new_tenant()
		var office = offices[origin]
		# 空室: 決まった日数がたったら新しいテナントが入居する
		if office.vacant:
			office.vacant_days += 1
			if office.vacant_days >= VACANT_DAYS:
				offices[origin] = new_tenant()
				result.moved_in += 1
			continue
		var total := 0.0
		var count := 0
		for cell in world.get_unit_cells(origin):
			if workers.has(cell) and workers[cell].arrived_day == day and not workers[cell].unreachable:
				total += day_peak_stress.get(cell, 0.0)
				count += 1
		if count == 0:
			continue # 出勤がなかった日は前の評価のまま
		# ビルが汚れている（ゴミ処理が追いつかない）ほど、働きにくい
		office.average = total / count + world.economy_system.pollution_stress()
		office.rating = rating_for(office.average)
		office.bad_days = office.bad_days + 1 if office.rating == Rating.BAD else 0
		# 評価の悪い日が続いたら退去する
		if office.bad_days >= LEAVE_AFTER_BAD_DAYS:
			office.vacant = true
			office.vacant_days = 0
			result.left += 1
	# なくなったオフィスの評価を消す
	for origin in offices.keys():
		if not origins.has(origin):
			offices.erase(origin)
	day_peak_stress.clear()
	return result

# 住宅の評価と退去（evaluate_day から呼ぶ）
func evaluate_homes(result: Dictionary) -> void:
	var housing = world.housing_system
	for origin in housing.homes:
		if not homes.has(origin):
			homes[origin] = new_tenant()
		var record = homes[origin]
		# 退去した後: 決まった日数がたったら、また入居者を募集する
		if record.vacant:
			record.vacant_days += 1
			if record.vacant_days >= VACANT_DAYS:
				homes[origin] = new_tenant()
			continue
		if not housing.homes[origin].moved_in:
			continue
		var total := 0.0
		var count := 0
		for m in housing.homes[origin].members:
			if day_peak_stress.has(m.room):
				total += day_peak_stress[m.room]
				count += 1
		if count == 0:
			continue # 誰もビルにいなかった日は前の評価のまま
		# 騒音がうるさい場所ほど、住み心地が悪い（評価に足す）
		record.average = total / count + world.noise_system.noise_stress(origin) + world.economy_system.pollution_stress()
		record.rating = rating_for(record.average)
		record.bad_days = record.bad_days + 1 if record.rating == Rating.BAD else 0
		if record.bad_days >= LEAVE_AFTER_BAD_DAYS:
			record.vacant = true
			record.vacant_days = 0
			result.refund += housing.move_out(origin)
			result.homes_left += 1
	for origin in homes.keys():
		if not housing.homes.has(origin):
			homes.erase(origin)

# ホテルの客がチェックアウトしたときに呼ばれる: その部屋の評価を決める
func rate_hotel_stay(origin: Vector2i, peak_stress: float) -> void:
	# 騒音がうるさい部屋ほど、泊まった客の評価が悪くなる
	var average: float = peak_stress + world.noise_system.noise_stress(origin) + world.economy_system.pollution_stress()
	rooms[origin] = {"rating": rating_for(average), "average": average}

# その夜に客室に客が来る確率（まだ評価がなければ必ず来る）
func hotel_checkin_chance(origin: Vector2i) -> float:
	if not rooms.has(origin):
		return 1.0
	return CHECKIN_CHANCE[rooms[origin].rating]

# 住宅が退去の後で、入居者を募集していない間か
func is_home_vacant(origin: Vector2i) -> bool:
	return homes.has(origin) and homes[origin].vacant

# 客室・住宅の評価の説明（まだ評価がなければ ""。どのマスを指定してもよい）
func get_room_rating_text(cell: Vector2i) -> String:
	cell = to_origin(cell)
	if not rooms.has(cell):
		return ""
	return "評価: %s・前の客のストレス%d" % [RATING_NAMES[rooms[cell].rating], int(rooms[cell].average)]

func get_home_rating_text(cell: Vector2i) -> String:
	cell = to_origin(cell)
	if not homes.has(cell):
		return ""
	var record = homes[cell]
	if record.vacant:
		return "退去・%d日後に入居者を募集" % (VACANT_DAYS - record.vacant_days)
	if not world.housing_system.homes.has(cell) or not world.housing_system.homes[cell].moved_in:
		return ""
	var text := "評価: %s・平均ストレス%d" % [RATING_NAMES[record.rating], int(record.average)]
	if record.bad_days > 0:
		text += "・悪い日が%d日続いている" % record.bad_days
	return text

func to_origin(cell: Vector2i) -> Vector2i:
	if world.building_grid.has(cell):
		return world.building_grid[cell].origin
	return cell

func new_tenant() -> Dictionary:
	return {"rating": Rating.GOOD, "average": 0.0, "bad_days": 0, "vacant": false, "vacant_days": 0}

# 指定マスのオフィスが空室か（オフィスのどのマスを指定してもよい）
func is_vacant(cell: Vector2i) -> bool:
	if world.building_grid.has(cell):
		cell = world.building_grid[cell].origin
	return offices.has(cell) and offices[cell].vacant

func count_vacant() -> int:
	var n := 0
	for origin in offices:
		if offices[origin].vacant:
			n += 1
	return n

func rating_for(average: float) -> Rating:
	if average < GOOD_BELOW:
		return Rating.GOOD
	if average < BAD_FROM:
		return Rating.NORMAL
	return Rating.BAD

# 指定マスを含むオフィスの評価の説明（まだ評価がなければ ""）
func get_rating_text(cell: Vector2i) -> String:
	if world.building_grid.has(cell):
		cell = world.building_grid[cell].origin
	if not offices.has(cell):
		return ""
	var office = offices[cell]
	if office.vacant:
		return "空室・%d日後に新しいテナントが入居" % (VACANT_DAYS - office.vacant_days)
	var text := "評価: %s・平均ストレス%d" % [RATING_NAMES[office.rating], int(office.average)]
	if office.bad_days > 0:
		text += "・悪い日が%d日続いている" % office.bad_days
	return text

func count_rating(rating: Rating) -> int:
	var n := 0
	for origin in offices:
		if offices[origin].rating == rating and not offices[origin].vacant:
			n += 1
	return n

# 空室（退去した後）のオフィス・住宅: 灰色に暗くして、「空室」の看板（白い板に赤い帯）を出す
func draw_vacant(origin: Vector2i, tile_size: Vector2) -> void:
	var cells: Array[Vector2i] = world.get_unit_cells(origin)
	var rect := Rect2(Vector2(origin) * tile_size, Vector2(tile_size.x * cells.size(), tile_size.y))
	draw_rect(Rect2(rect.position + Vector2(0, 1), rect.size - Vector2(0, 3)), Color(0.2, 0.2, 0.22, 0.6))
	var sign_pos := rect.position + Vector2(rect.size.x / 2.0 - 6, 5)
	draw_rect(Rect2(sign_pos - Vector2.ONE, Vector2(14, 7)), Color(0.1, 0.1, 0.1))
	draw_rect(Rect2(sign_pos, Vector2(12, 5)), Color(0.95, 0.95, 0.9))
	draw_rect(Rect2(sign_pos + Vector2(0, 2), Vector2(12, 1)), Color(0.85, 0.2, 0.2))

# オフィス・客室・住宅の左上に、評価の顔のマーク（5×5ドット）を描く（空室なら灰色と看板）
func _draw() -> void:
	var tile_size := Vector2(world.tile_map.tile_set.tile_size)
	var marks := {} # 左端のマス -> 評価（空室なら -1）
	for origin in offices:
		marks[origin] = -1 if offices[origin].vacant else offices[origin].rating
	for origin in rooms:
		marks[origin] = rooms[origin].rating
	for origin in homes:
		if homes[origin].vacant:
			marks[origin] = -1
		elif world.housing_system.homes.has(origin) and world.housing_system.homes[origin].moved_in:
			marks[origin] = homes[origin].rating
	for origin in marks:
		if not world.building_grid.has(origin):
			continue
		if marks[origin] == -1:
			draw_vacant(origin, tile_size)
			continue
		draw_face(Vector2(origin) * tile_size + Vector2(1, 1), marks[origin])

func draw_face(p: Vector2, rating: Rating) -> void:
	draw_rect(Rect2(p - Vector2.ONE, Vector2(7, 7)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(p, Vector2(5, 5)), RATING_COLORS[rating])
	var ink := Color(0.1, 0.1, 0.1)
	draw_rect(Rect2(p + Vector2(1, 1), Vector2.ONE), ink) # 目
	draw_rect(Rect2(p + Vector2(3, 1), Vector2.ONE), ink)
	match rating:
		Rating.GOOD: # 笑顔
			draw_rect(Rect2(p + Vector2(0, 3), Vector2.ONE), ink)
			draw_rect(Rect2(p + Vector2(1, 4), Vector2(3, 1)), ink)
			draw_rect(Rect2(p + Vector2(4, 3), Vector2.ONE), ink)
		Rating.NORMAL: # ふつう
			draw_rect(Rect2(p + Vector2(1, 3), Vector2(3, 1)), ink)
		Rating.BAD: # 怒った顔
			draw_rect(Rect2(p + Vector2(1, 3), Vector2(3, 1)), ink)
			draw_rect(Rect2(p + Vector2(0, 4), Vector2.ONE), ink)
			draw_rect(Rect2(p + Vector2(4, 4), Vector2.ONE), ink)
