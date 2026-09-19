extends Node2D

# ---------------------------------------------------
# ホテルとハウスキーパー（清掃員）
#
# 客室は横に何マスかの建物（ユニット）で、1ユニット = 1室。部屋は左端のマスで表す。
# 種類は ROOM_TYPES（シングル・ツイン・スイート）。
# 種類ごとに、泊まる人数（guests）・1泊の宿泊料（rate）・清掃にかかる分数（cleaning）が違う。
# 客室の状態:
#   CLEAN     … きれいな空室。CHECKIN_START〜CHECKIN_END の間に宿泊客が入口から来る
#   OCCUPIED  … 宿泊中。翌朝 CHECKOUT_START〜CHECKOUT_END にチェックアウトして入口から帰る
#               （チェックアウト時に、その部屋の宿泊料が入る）
#   DIRTY     … 清掃待ち。清掃が済むまで次の客は泊まれない
# 清掃員（"housekeeping" 1マス = 1人）:
#   清掃待ちの部屋のうち一番近い部屋へ行き、その部屋の清掃時間をかけて掃除する。
#   仕事がなければハウスキーパー室に戻って待つ。
#
# TileMapLayerの子として追加し、部屋の状態（明かり・汚れ）を描く。
# 建設・撤去のたびに rebuild() を呼んで、客室・清掃員の対応を更新する。
# ---------------------------------------------------

enum RoomState { CLEAN, OCCUPIED, DIRTY }

const CHECKIN_START := 17 * 60
const CHECKIN_END := 21 * 60
const CHECKOUT_START := 7 * 60
const CHECKOUT_END := 10 * 60
const ROOM_TYPES := {
	"hotel": {"guests": 1, "rate": 20000, "cleaning": 20.0},       # シングル
	"hotel_twin": {"guests": 2, "rate": 35000, "cleaning": 30.0},  # ツイン
	"hotel_suite": {"guests": 2, "rate": 80000, "cleaning": 45.0}, # スイート
}
const GUEST_COLOR := Color(0.85, 0.75, 1.0)
const HOUSEKEEPER_COLOR := Color(0.5, 0.9, 1.0)

var world: Node2D # main.gd

# 客室のマス -> {type, state, guests, checkin_day, cleaner}
#   type:        客室の種類（ROOM_TYPES のキー）
#   guests:      宿泊客の住人ノードの配列
#   checkin_day: 最後に客が来た日（同じ日に2人来ないため）
#   cleaner:     この部屋の清掃を担当している清掃員の情報（いなければnull）
var rooms: Dictionary = {}
# ハウスキーパー室のマス -> {home, resident, room, clean_left}
#   room:        担当している部屋のマス（なければnull）
#   clean_left:  清掃の残り時間（ゲーム内の分）
var housekeepers: Dictionary = {}
var leaving_guests: Array = [] # チェックアウトして入口へ向かっている宿泊客
var revenue_by_day: Dictionary = {} # 日 -> その日の宿泊料の合計
var checkouts_by_day: Dictionary = {} # 日 -> その日にチェックアウトした部屋の数

func setup(p_world: Node2D) -> void:
	world = p_world
	z_index = 6 # マス目の表示より手前、カゴや住人より奥

# ---------------------------------------------------
# 客室・清掃員の登録
# ---------------------------------------------------

func rebuild() -> void:
	var room_cells: Array[Vector2i] = []
	for type in ROOM_TYPES:
		for cell in world.find_cells_of_type(type):
			if world.building_grid[cell].origin != cell:
				continue # 部屋は左端のマスで表す
			room_cells.append(cell)
			if not rooms.has(cell):
				rooms[cell] = {"type": type, "state": RoomState.CLEAN, "guests": [], "checkin_day": 0, "cleaner": null}
	for cell in rooms.keys():
		if not room_cells.has(cell):
			var room = rooms[cell]
			for guest in room.guests:
				if is_instance_valid(guest):
					guest.queue_free() # 部屋がなくなった客は帰る
			if room.cleaner:
				room.cleaner.room = null
			rooms.erase(cell)

	var home_cells: Array[Vector2i] = world.find_cells_of_type("housekeeping")
	for cell in home_cells:
		if not housekeepers.has(cell):
			var resident = world.spawn_resident(cell)
			resident.base_color = HOUSEKEEPER_COLOR
			housekeepers[cell] = {"home": cell, "resident": resident, "room": null, "clean_left": 0.0}
	for cell in housekeepers.keys():
		if not home_cells.has(cell):
			var keeper = housekeepers[cell]
			release_room(keeper)
			if is_instance_valid(keeper.resident):
				keeper.resident.queue_free()
			housekeepers.erase(cell)

# ---------------------------------------------------
# 毎フレームの処理
# ---------------------------------------------------

func _process(_delta: float) -> void:
	process_rooms()
	process_leaving_guests()
	var minutes: float = world.clock.last_advance # このフレームで進んだゲーム内の分数
	for cell in housekeepers:
		process_housekeeper(housekeepers[cell], minutes)
	queue_redraw()

func process_rooms() -> void:
	var day: int = world.clock.day
	var now: int = world.clock.minute_of_day()
	for cell in rooms:
		var room = rooms[cell]
		match room.state:
			RoomState.CLEAN:
				# チェックインの時刻になったら、入口から客（部屋の定員の人数）が来る（時刻は部屋と日ごとに決まった乱数）
				if room.checkin_day != day and now >= checkin_minute(cell, day) and now < CHECKIN_END:
					room.checkin_day = day
					var count: int = ROOM_TYPES[room.type].guests
					var unit_cells: Array[Vector2i] = world.get_unit_cells(cell)
					for i in count:
						# 客は部屋の中の別々のマスに振り分ける（重なって1人に見えないように）
						var spot: Vector2i = unit_cells[i * unit_cells.size() / count]
						var guest = spawn_guest(spot)
						if guest:
							room.guests.append(guest)
					if not room.guests.is_empty():
						room.state = RoomState.OCCUPIED
			RoomState.OCCUPIED:
				room.guests = room.guests.filter(is_instance_valid)
				if room.guests.is_empty():
					room.state = RoomState.DIRTY # 客がいなくなった（撤去など）。宿泊料はなし
				elif day > room.checkin_day and now >= checkout_minute(cell, day) and not is_any_guest_riding(room):
					checkout(cell, room)

func checkin_minute(cell: Vector2i, day: int) -> int:
	return random_minute(cell, day, CHECKIN_START, CHECKIN_END)

func checkout_minute(cell: Vector2i, day: int) -> int:
	return random_minute(cell, day + 1000, CHECKOUT_START, CHECKOUT_END)

# 部屋と日ごとに決まった乱数で時刻を決める（毎回同じ結果になり、テストしやすい）
func random_minute(cell: Vector2i, salt: int, from: int, to: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([cell, salt])
	return rng.randi_range(from, to - 1)

func is_any_guest_riding(room: Dictionary) -> bool:
	for guest in room.guests:
		if guest.state == guest.State.RIDING:
			return true
	return false

# 入口に客を出して部屋へ向かわせる。たどり着けなければnull
func spawn_guest(cell: Vector2i):
	var entrance = world.nearest_entrance(cell)
	if entrance == null:
		return null
	var guest = world.spawn_resident(entrance)
	guest.base_color = GUEST_COLOR
	guest.go_to(cell)
	return guest

# チェックアウト: 宿泊料を受け取り、客を入口へ向かわせ、部屋を清掃待ちにする
func checkout(_cell: Vector2i, room: Dictionary) -> void:
	var day: int = world.clock.day
	revenue_by_day[day] = revenue_by_day.get(day, 0) + ROOM_TYPES[room.type].rate
	checkouts_by_day[day] = checkouts_by_day.get(day, 0) + 1
	for guest in room.guests:
		var entrance = world.nearest_entrance(guest.cell)
		if entrance != null and guest.go_to(entrance):
			leaving_guests.append(guest)
		else:
			guest.queue_free()
	room.guests = []
	room.state = RoomState.DIRTY

# 入口に着いた客は帰る（消える）
func process_leaving_guests() -> void:
	for guest in leaving_guests.duplicate():
		if not is_instance_valid(guest):
			leaving_guests.erase(guest)
		elif not guest.is_moving():
			var entrance = world.nearest_entrance(guest.cell)
			if entrance == null or guest.cell == entrance or not guest.go_to(entrance):
				guest.queue_free()
				leaving_guests.erase(guest)

func process_housekeeper(keeper: Dictionary, minutes: float) -> void:
	var resident = keeper.resident
	if not is_instance_valid(resident):
		release_room(keeper)
		return
	if keeper.room == null:
		# 次の部屋を探す。なければハウスキーパー室に戻る
		if not assign_nearest_dirty_room(keeper) and resident.cell != keeper.home and not resident.is_moving():
			resident.go_to(keeper.home)
		return
	var room = rooms.get(keeper.room)
	if room == null or room.state != RoomState.DIRTY:
		release_room(keeper)
		return
	# 部屋に着いたら清掃する。途中で経路が途切れたら担当を外れる
	if resident.cell == keeper.room and not resident.is_moving():
		keeper.clean_left -= minutes
		if keeper.clean_left <= 0.0:
			room.state = RoomState.CLEAN
			release_room(keeper)
	elif not resident.is_moving() and not resident.go_to(keeper.room):
		release_room(keeper)

# まだ誰も担当していない清掃待ちの部屋のうち、経路が一番短い部屋を担当する
func assign_nearest_dirty_room(keeper: Dictionary) -> bool:
	var best = null
	var best_length := 0
	for cell in rooms:
		var room = rooms[cell]
		if room.state != RoomState.DIRTY or room.cleaner != null:
			continue
		var path: Array[Vector2i] = world.find_path(keeper.resident.cell, cell)
		if not path.is_empty() and (best == null or path.size() < best_length):
			best = cell
			best_length = path.size()
	if best == null:
		return false
	keeper.room = best
	keeper.clean_left = ROOM_TYPES[rooms[best].type].cleaning
	rooms[best].cleaner = keeper
	if keeper.resident.cell != best:
		keeper.resident.go_to(best)
	return true

func release_room(keeper: Dictionary) -> void:
	if keeper.room != null and rooms.has(keeper.room):
		rooms[keeper.room].cleaner = null
	keeper.room = null

# ---------------------------------------------------
# 集計・表示
# ---------------------------------------------------

func is_room_type(type: String) -> bool:
	return ROOM_TYPES.has(type)

# 全客室の定員の合計（人口に数える）
func total_capacity() -> int:
	var n := 0
	for cell in rooms:
		n += ROOM_TYPES[rooms[cell].type].guests
	return n

func count_rooms(state: RoomState) -> int:
	var n := 0
	for cell in rooms:
		if rooms[cell].state == state:
			n += 1
	return n

# 指定マスを含む客室の状態（部屋のどのマスを指定してもよい）
func get_room_state_text(cell: Vector2i) -> String:
	if world.building_grid.has(cell):
		cell = world.building_grid[cell].origin
	if not rooms.has(cell):
		return ""
	match rooms[cell].state:
		RoomState.OCCUPIED:
			return "宿泊中"
		RoomState.DIRTY:
			return "清掃中" if rooms[cell].cleaner != null and housekeeper_at(cell) else "清掃待ち"
	return "空室"

func housekeeper_at(cell: Vector2i) -> bool:
	var keeper = rooms[cell].cleaner
	return keeper != null and is_instance_valid(keeper.resident) and keeper.resident.cell == cell \
		and not keeper.resident.is_moving()

func _draw() -> void:
	var tile_size := Vector2(world.tile_map.tile_set.tile_size)
	for cell in rooms:
		for spot in world.get_unit_cells(cell):
			var rect := Rect2(Vector2(spot) * tile_size, tile_size)
			match rooms[cell].state:
				RoomState.OCCUPIED:
					# 宿泊中: 各区画の窓に黄色い明かり（どの区画も窓の位置はそろえてある）
					draw_rect(Rect2(rect.position + Vector2(4, 3), Vector2(8, 3)), Color(1.0, 0.9, 0.4, 0.85))
				RoomState.DIRTY:
					# 清掃待ち: 茶色い汚れ
					draw_rect(rect.grow(-2), Color(0.45, 0.3, 0.15, 0.55))
					draw_circle(rect.get_center() + Vector2(-3, 2), 2.0, Color(0.35, 0.22, 0.1))
					draw_circle(rect.get_center() + Vector2(3, -1), 1.5, Color(0.35, 0.22, 0.1))
