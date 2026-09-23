extends Node

# ---------------------------------------------------
# セーブ／ロード：ビルの状態をファイル（JSON）に保存して、後から続きを遊べるようにする。
#   保存するもの: 建物の配置・資金・日付と時刻・ビルの評価（★）・VIPの合否・
#                 エレベーターの設定（待機階・稼働時間帯・カゴの数）・テナントの評価・
#                 客室と住宅の状態・衛生の悪化・ゴキブリ・掘った地下のマス。
#   保存しないもの: 今ビルの中を歩いている人（読み込んだ後、各システムがまた出してくる）。
# 保存先（Godotのユーザーデータのフォルダ）:
#   セーブの枠 1〜SLOT_COUNT … save.json（枠1）・save_2.json・save_3.json（⌘S で枠を選んで保存する）
#   オートセーブ           … autosave.json（毎日0時の決算のあとに、自動で上書きする）
# ---------------------------------------------------

const SLOT_COUNT := 3
const AUTOSAVE_SLOT := 0 # オートセーブの枠の番号（読み込みの画面で一番上に出す）
const VERSION := 1

var world: Node2D # main.gd
var save_dir := "user://"     # 保存先のフォルダ（テストでは別のフォルダにして、遊んでいるデータを上書きしない）
var autosave_enabled := true  # オートセーブするか（README の画像づくりでは止める）

func setup(p_world: Node2D) -> void:
	world = p_world

# その枠のファイル（0 はオートセーブ）
func slot_path(slot: int) -> String:
	if slot == AUTOSAVE_SLOT:
		return save_dir.path_join("autosave.json")
	return save_dir.path_join("save.json" if slot == 1 else "save_%d.json" % slot)

func slot_name(slot: int) -> String:
	return "オートセーブ" if slot == AUTOSAVE_SLOT else "枠%d" % slot

# どこかの枠（オートセーブを含む）にセーブデータがあるか
func has_save() -> bool:
	for slot in range(AUTOSAVE_SLOT, SLOT_COUNT + 1):
		if FileAccess.file_exists(slot_path(slot)):
			return true
	return false

# 枠に保存する・読み込む（メッセージには枠の名前を出す）
func save_slot(slot: int) -> bool:
	if not write_file(slot_path(slot)):
		world.show_message("セーブできませんでした（ファイルを開けません）")
		return false
	world.show_message("%sにセーブしました（%s日目 %s）" % [slot_name(slot), world.clock.day, world.clock.date_text()])
	return true

func load_slot(slot: int) -> bool:
	return load_game(slot_path(slot))

# 毎日の決算のあとに呼ばれる: オートセーブの枠に黙って保存する（決算のメッセージを邪魔しない）
func autosave() -> void:
	if autosave_enabled:
		write_file(slot_path(AUTOSAVE_SLOT))

# その枠のセーブデータの中身の要約（読み込みの画面に出す。なければ空）
#   {"day": 日, "date": "4月12日（金） 21:44", "funds": 資金, "stars": ★, "saved_at": 保存した日時}
func slot_info(slot: int) -> Dictionary:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or data.get("version", 0) != VERSION:
		return {}
	var day := int(data.day)
	var minute := int(data.minute)
	return {"day": day, "funds": int(data.funds), "stars": int(data.stars), "saved_at": str(data.get("saved_at", "")),
		"name": str(data.get("tower_name", world.DEFAULT_TOWER_NAME)),
		"date": "%s（%s） %02d:%02d" % [world.clock.date_text(day), world.clock.WEEKDAY_NAMES[world.clock.weekday(day)], minute / 60, minute % 60]}

# 今の状態をファイルに保存する。成功したらtrue（path を省くと枠1）
func save_game(path := "") -> bool:
	if not write_file(path if path != "" else slot_path(1)):
		world.show_message("セーブできませんでした（ファイルを開けません）")
		return false
	world.show_message("セーブしました（%s日目 %s）" % [world.clock.day, world.clock.date_text()])
	return true

func write_file(path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(collect(), "\t"))
	file.close()
	return true

# ファイルから読み込んで、その状態に戻す。成功したらtrue（path を省くと枠1）
func load_game(path := "") -> bool:
	if path == "":
		path = slot_path(1)
	if not FileAccess.file_exists(path):
		world.show_message("セーブデータがありません")
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(data) != TYPE_DICTIONARY or data.get("version", 0) != VERSION:
		world.show_message("セーブデータを読み込めませんでした")
		return false
	apply(data)
	world.show_message("セーブデータを読み込みました（%s日目 %s）" % [world.clock.day, world.clock.date_text()])
	return true

# ---------------------------------------------------
# 今の状態を集める
# ---------------------------------------------------
func collect() -> Dictionary:
	var elevators = world.elevator_system
	var tenants = world.tenant_system
	return {
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(false, true), # 保存した日時（読み込みの画面に出す）
		"funds": world.funds,
		"tower_name": world.tower_name,
		"day": world.clock.day,
		"minute": world.clock.minute,
		"stars": world.rating_system.stars,
		"vip_passed": world.vip_system.passed,
		"goal_index": world.goal_system.index,
		"tutorial_step": world.tutorial_system.step,
		"tutorial_finished": world.tutorial_system.finished,
		"pollution": world.economy_system.pollution,
		"last_day": world.economy_system.last_day,
		"treasure_total": world.incident_system.treasure_total,
		"units": collect_units(),
		"cars": collect_cars(),
		"home_floors": collect_keyed(elevators.home_floors),
		"service_hours": collect_keyed(elevators.service_hours),
		"vip_only": collect_keyed(elevators.vip_only),
		"offices": collect_tenants(tenants.offices),
		"rents": tenants.rent_levels.keys().map(func(cell): return {"x": cell.x, "y": cell.y, "value": tenants.rent_levels[cell]}),
		"homes": collect_tenants(tenants.homes),
		"rooms": collect_tenants(tenants.rooms),
		"hotel_rooms": collect_hotel_rooms(),
		"moved_in_homes": collect_cells(world.housing_system.homes.keys().filter(
			func(cell): return world.housing_system.homes[cell].moved_in)),
		"roaches": collect_cells(world.incident_system.roaches.keys()),
		"dug": collect_cells(world.incident_system.dug.keys()),
	}

func collect_units() -> Array:
	var units := []
	for cell in world.building_grid:
		if world.building_grid[cell].origin == cell:
			units.append({"type": world.building_grid[cell].type, "x": cell.x, "y": cell.y})
	return units

# カゴ: シャフトの種類・列・今いる階（シャフトを建て直した後、同じ数だけ置き直す）
func collect_cars() -> Array:
	var cars := []
	for car in world.elevator_system.cars:
		if is_instance_valid(car):
			cars.append({"type": car.shaft_type, "x": car.column, "y": car.current_floor()})
	return cars

func collect_cells(cells: Array) -> Array:
	return cells.map(func(cell: Vector2i): return {"x": cell.x, "y": cell.y})

# [種類, 列] や マス をキーにした設定を、保存できる形にする
func collect_keyed(records: Dictionary) -> Array:
	var list := []
	for key in records:
		list.append({"type": key[0], "x": key[1], "value": records[key]})
	return list

# テナントの評価（オフィス・住宅・客室）
func collect_tenants(records: Dictionary) -> Array:
	var list := []
	for origin in records:
		var record: Dictionary = records[origin].duplicate()
		record["x"] = origin.x
		record["y"] = origin.y
		list.append(record)
	return list

func collect_hotel_rooms() -> Array:
	var list := []
	for cell in world.hotel_system.rooms:
		var room: Dictionary = world.hotel_system.rooms[cell]
		list.append({"x": cell.x, "y": cell.y, "state": room.state, "dirty_day": room.get("dirty_day", 0)})
	return list

# ---------------------------------------------------
# 読み込んだ状態に戻す
# ---------------------------------------------------
func apply(data: Dictionary) -> void:
	world.clear_world()
	for unit in data.units:
		world.place_unit(Vector2i(int(unit.x), int(unit.y)), unit.type)
	world.funds = int(data.funds)
	world.set_tower_name(str(data.get("tower_name", "")), false) # 古いセーブデータにはない（そのときは初めの名前）
	world.clock.day = int(data.day)
	world.clock.minute = float(data.minute)
	world.rating_system.stars = int(data.stars)
	world.vip_system.passed = bool(data.vip_passed)
	world.goal_system.index = int(data.get("goal_index", 0))
	world.goal_system.cleared = world.goal_system.current() == null
	world.tutorial_system.step = int(data.get("tutorial_step", 0))
	world.tutorial_system.finished = bool(data.get("tutorial_finished", false))
	world.economy_system.pollution = int(data.pollution)
	world.economy_system.last_day = int(data.last_day)
	world.incident_system.treasure_total = int(data.treasure_total)
	world.incident_system.reset_incidents() # 前の続きの火災・爆破予告を持ち込まない
	world.vip_system.reset_visit() # 来館・宿泊の途中も持ち込まない
	world.request_system.reset() # テナントからの頼みごとも取り下げる
	world.rebuild_systems()
	apply_elevators(data)
	apply_tenants(data)
	apply_cells(data)
	world.update_funds_display()

func apply_elevators(data: Dictionary) -> void:
	var elevators = world.elevator_system
	elevators.home_floors.clear()
	for record in data.home_floors:
		elevators.home_floors[[record.type, int(record.x)]] = int(record.value)
	elevators.service_hours.clear()
	for record in data.service_hours:
		elevators.service_hours[[record.type, int(record.x)]] = int(record.value)
	elevators.vip_only.clear()
	for record in data.get("vip_only", []): # 古いセーブデータにはない
		elevators.vip_only[[record.type, int(record.x)]] = true
	# カゴ: シャフトを建て直すと1本に1台できるので、足りない分だけ追加する
	var wanted := {} # [種類, 列] -> カゴがいた階の一覧
	for record in data.cars:
		var key := [record.type, int(record.x)]
		wanted[key] = wanted.get(key, []) + [int(record.y)]
	for key in wanted:
		for floor_y in wanted[key]:
			var cell := Vector2i(key[1], floor_y)
			if world.get_building_type(cell) != key[0]:
				continue
			if elevators.get_cars_at(cell).size() >= wanted[key].size():
				break # そのシャフトのカゴはもう足りている
			var before: int = world.funds
			elevators.add_car(cell)
			world.funds = before # 読み込みではお金はかからない
	# カゴを、保存されていた階に戻す（シャフトを建て直したカゴは最下階にいるため）
	for key in wanted:
		var floors: Array = wanted[key]
		var cars: Array = elevators.cars.filter(func(car):
			return is_instance_valid(car) and car.shaft_type == key[0] and car.column == key[1])
		for i in mini(cars.size(), floors.size()):
			cars[i].place_at_floor(floors[i])
	elevators.apply_home_floors()

func apply_tenants(data: Dictionary) -> void:
	world.tenant_system.rent_levels.clear()
	for record in data.get("rents", []): # 古いセーブデータにはない
		world.tenant_system.rent_levels[Vector2i(int(record.x), int(record.y))] = int(record.value)
	var tenants = world.tenant_system
	tenants.offices = restore_tenants(data.offices)
	tenants.homes = restore_tenants(data.homes)
	tenants.rooms = restore_tenants(data.rooms)
	for record in data.hotel_rooms:
		var cell := Vector2i(int(record.x), int(record.y))
		if world.hotel_system.rooms.has(cell):
			var room: Dictionary = world.hotel_system.rooms[cell]
			room.state = int(record.state)
			if room.state == world.hotel_system.RoomState.DIRTY:
				# 掃除されないまま日がたつとゴキブリが出るので、いつから汚れているかも戻す（古いセーブデータは読み込んだ日から）
				room.dirty_day = int(record.get("dirty_day", world.clock.day))
	for record in data.moved_in_homes:
		var cell := Vector2i(int(record.x), int(record.y))
		if world.housing_system.homes.has(cell):
			world.housing_system.homes[cell].moved_in = true

func restore_tenants(list: Array) -> Dictionary:
	var records := {}
	for item in list:
		var record: Dictionary = (item as Dictionary).duplicate()
		var origin := Vector2i(int(record.x), int(record.y))
		record.erase("x")
		record.erase("y")
		# JSONでは数が小数になるので、整数に戻す
		for key in ["rating", "bad_days", "vacant_days"]:
			if record.has(key):
				record[key] = int(record[key])
		records[origin] = record
	return records

func apply_cells(data: Dictionary) -> void:
	var incidents = world.incident_system
	incidents.roaches.clear()
	for record in data.roaches:
		incidents.roaches[Vector2i(int(record.x), int(record.y))] = true
	incidents.dug.clear()
	for record in data.dug:
		incidents.dug[Vector2i(int(record.x), int(record.y))] = true
