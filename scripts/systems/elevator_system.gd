extends Node

# ---------------------------------------------------
# エレベーターの管理：グリッド情報からシャフトを組み立て、シャフトごとにカゴを置く。
# シャフト = 同じ列で縦につながった、同じ種類のエレベーターのマスのまとまり。
# 種類（SHAFT_TYPES）: "elevator" = 標準（全部の階に停まる） /
#                      "express_elevator" = 急行（1階とスカイロビーの階だけに停まる。速くて定員が多い）
#                      "large_elevator" = 大型（横2マス。全部の階に停まり、定員が大きくて少し速い）
#                      "service_elevator" = サービス（裏方＝清掃員だけが乗れる）
# 建設・撤去のたびに rebuild() を呼んで、シャフトとカゴを作り直す。
#
# カゴ: シャフトを建てると1台できる。add_car() で1本のシャフトに MAX_CARS 台まで増やせる。
# 乗り場呼び（群管理）: 待っている人のボタンはシャフト全体で受け付け、到着までの手間の見積もり
#   （ElevatorCar.estimate_cost）が一番小さいカゴに割り当てる。割り当てたカゴが満員になったら割り当て直す。
# ---------------------------------------------------

const ElevatorCar := preload("res://scripts/actors/elevator_car.gd")
const SHAFT_TYPES := ["elevator", "express_elevator", "large_elevator", "service_elevator"]
const MAX_CARS := 4        # 1本のシャフトに置けるカゴの数
const CAR_COST := 50000    # カゴを1台追加する費用
const CAR_MAINTENANCE := 3000 # 追加したカゴ1台の1日の維持費

# 稼働時間帯の選べる設定（クリックするたびにこの順に切り替わる）。start〜end は0時からの分
const SERVICE_PRESETS := [
	{"name": "終日", "start": 0, "end": 24 * 60},
	{"name": "6時〜24時", "start": 6 * 60, "end": 24 * 60},
	{"name": "8時〜20時", "start": 8 * 60, "end": 20 * 60},
]

var world: Node2D  # main.gd
var cars: Array = [] # すべてのカゴ（シャフトは column と top_y〜bottom_y で分かる）
var hall_assignments := {} # [乗り場のマス, 方向] -> 割り当てたカゴ
var home_floors := {}      # [シャフトの種類, 列のx] -> 待機階のy
var service_hours := {}    # [シャフトの種類, 列のx] -> SERVICE_PRESETS の番号（省略時は0＝終日）
var vip_only := {}         # [シャフトの種類, 列のx] -> true（VIPの来館中は、VIPだけが乗れる）

func setup(p_world: Node2D) -> void:
	world = p_world

# グリッド情報からシャフトを探し直し、カゴを対応させる。
# 既存のカゴは、今いる階を含むシャフトにそのまま引き継ぐ（1本に何台あってもよい）。
# カゴが1台もないシャフトには、最下階にカゴを1台置く。
func rebuild() -> void:
	var remaining := cars.duplicate()
	var new_cars: Array = []
	for shaft in find_shafts():
		var kept := 0
		for c in remaining.duplicate():
			if c.shaft_type == shaft.type and c.column == shaft.x \
					and c.current_floor() >= shaft.top and c.current_floor() <= shaft.bottom:
				remaining.erase(c)
				c.set_shaft(shaft.top, shaft.bottom)
				new_cars.append(c)
				kept += 1
		if kept == 0:
			new_cars.append(create_car(shaft.type, shaft.x, shaft.top, shaft.bottom, shaft.bottom))
	# シャフトがなくなった（または途中を撤去されて居場所がなくなった）カゴは消す
	for c in remaining:
		c.queue_free()
	cars = new_cars
	apply_home_floors()

# ---------------------------------------------------
# 待機階（ホーム）: 呼び出しがなくなったカゴが戻る階。シャフトごとに1つ設定できる
# ---------------------------------------------------

# シャフトの列（横2マスの大型エレベーターは、左端のマスの列で表す）
func shaft_column(cell: Vector2i) -> int:
	return world.building_grid[cell].origin.x if world.building_grid.has(cell) else cell.x

# シャフトを見分けるキー（同じ列に標準と急行が並ぶこともあるので、種類も見る）
func shaft_key(cell: Vector2i) -> Array:
	return [world.get_building_type(cell), shaft_column(cell)]

# 指定マスのシャフトの待機階（設定していなければnull）
func get_home(cell: Vector2i):
	return home_floors.get(shaft_key(cell))

# 指定マスの階を待機階にする（すでにその階なら解除する）。メッセージを返す
func set_home(cell: Vector2i) -> String:
	if not is_shaft_type(world.get_building_type(cell)):
		return "待機階はエレベーターのシャフトに設定します"
	var car = get_car_at(cell)
	if car != null and not car.is_stop_floor(cell.y):
		return "急行エレベーターが停まらない階は待機階にできません"
	var key := shaft_key(cell)
	if home_floors.get(key) == cell.y:
		home_floors.erase(key)
		apply_home_floors()
		return "待機階を解除しました %s" % cell
	home_floors[key] = cell.y
	apply_home_floors()
	return "%sを待機階にしました（呼び出しがないとカゴが戻ります）" % world.get_floor_name(cell.y)

# 待機階の設定をカゴに反映する。シャフトからなくなった階の設定は消す
func apply_home_floors() -> void:
	for key in vip_only.keys(): # なくなったシャフトのVIP専用の設定は消す
		if not cars.any(func(car): return is_instance_valid(car) and car.shaft_type == key[0] and car.column == key[1]):
			vip_only.erase(key)
	for key in home_floors.keys():
		var found := false
		for car in cars:
			if is_instance_valid(car) and car.shaft_type == key[0] and car.column == key[1]:
				if car.has_floor(home_floors[key]):
					found = true
		if not found:
			home_floors.erase(key)
	for car in cars:
		if not is_instance_valid(car):
			continue
		var key := [car.shaft_type, car.column]
		car.set_home(home_floors.get(key, 0), home_floors.has(key))

# ---------------------------------------------------
# 稼働時間帯: 決めた時間帯の外では、そのシャフトは動かない（呼べず、乗れず、経路にも使われない）
# ---------------------------------------------------

# 指定マスのシャフトの稼働時間帯の設定
func get_service(cell: Vector2i) -> Dictionary:
	return SERVICE_PRESETS[service_hours.get(shaft_key(cell), 0)]

# 稼働時間帯を次の設定に切り替える。メッセージを返す
func cycle_service(cell: Vector2i) -> String:
	if not is_shaft_type(world.get_building_type(cell)):
		return "稼働時間帯はエレベーターのシャフトに設定します"
	var key := shaft_key(cell)
	service_hours[key] = (service_hours.get(key, 0) + 1) % SERVICE_PRESETS.size()
	return "このエレベーターの稼働時間帯を「%s」にしました" % SERVICE_PRESETS[service_hours[key]].name

# VIP専用の設定を切り替える。メッセージを返す
func toggle_vip_only(cell: Vector2i) -> String:
	var type: String = world.get_building_type(cell)
	if not is_shaft_type(type) or type == "service_elevator":
		return "VIP専用はお客さんが乗るエレベーター（標準・急行・大型）に設定します"
	var key := shaft_key(cell)
	if vip_only.has(key):
		vip_only.erase(key)
		return "VIP専用を解除しました"
	vip_only[key] = true
	return "VIP専用にしました（VIPが来館している間は、VIPだけが乗れます。待機階を1階にしておくと、着いたVIPをすぐ乗せられます）"

func is_vip_only(cell: Vector2i) -> bool:
	return world.building_grid.has(cell) and vip_only.has(shaft_key(cell))

# 今、VIPのために空けているシャフトか（VIP専用で、VIPがスイートへ向かっている間）
func is_reserved_for_vip(cell: Vector2i) -> bool:
	return is_vip_only(cell) and world.vip_system.is_arriving()

# VIP専用のシャフトのマス（目印を描くため）
func get_vip_only_cells() -> Array:
	var cells: Array = []
	for car in cars:
		if is_instance_valid(car) and vip_only.has([car.shaft_type, car.column]):
			for y in range(car.top_y, car.bottom_y + 1):
				cells.append(Vector2i(car.column, y))
	return cells

# 今この時刻に動いているシャフトか
func is_in_service(type: String, column: int) -> bool:
	var preset: Dictionary = SERVICE_PRESETS[service_hours.get([type, column], 0)]
	var minute: int = world.clock.minute_of_day()
	return minute >= preset.start and minute < preset.end

# カゴに今の稼働状況を伝える（毎フレーム）
func _process(_delta: float) -> void:
	for car in cars:
		if is_instance_valid(car):
			car.in_service = is_in_service(car.shaft_type, car.column)

# 待機階に設定されているマスの一覧（マス目の表示で印を描くのに使う）
func get_home_cells() -> Array:
	var cells: Array = []
	for key in home_floors:
		cells.append(Vector2i(key[1], home_floors[key]))
	return cells

func create_car(type: String, x: int, top: int, bottom: int, start_y: int):
	var car = ElevatorCar.new()
	car.setup(world, x, top, bottom, start_y)
	car.set_shaft_type(type)
	car.arrived.connect(func(y):
		world.audio_system.play("chime")
		world.show_message("エレベーターが %s に到着しました" % Vector2i(car.column, y)))
	world.tile_map.add_child(car)
	return car

# エレベーターのシャフトの種類か
func is_shaft_type(type: String) -> bool:
	return type in SHAFT_TYPES

# シャフトの一覧: [{"type": 種類, "x": 列, "top": 最上階のy, "bottom": 最下階のy}, ...]
func find_shafts() -> Array:
	var result: Array = []
	for type in SHAFT_TYPES:
		for cell: Vector2i in world.find_units_of_type(type): # 大型は左端のマスだけ見る
			# シャフトの最下段のマスからだけ数え始める
			if world.get_building_type(cell + Vector2i.DOWN) == type:
				continue
			var top: int = cell.y
			while world.get_building_type(Vector2i(cell.x, top - 1)) == type:
				top -= 1
			result.append({"type": type, "x": cell.x, "top": top, "bottom": cell.y})
	return result

# 指定したマスを含むシャフトのカゴの一覧
func get_cars_at(cell: Vector2i) -> Array:
	var result: Array = []
	var type: String = world.get_building_type(cell)
	for car in cars:
		if is_instance_valid(car) and car.shaft_type == type and car.column == shaft_column(cell) and car.has_floor(cell.y):
			result.append(car)
	return result

# 指定したマスを含むシャフトのカゴ（1台目。なければnull）
func get_car_at(cell: Vector2i):
	var list := get_cars_at(cell)
	return list[0] if not list.is_empty() else null

# 指定したマスの階にカゴを呼ぶ（エレベーターモードでシャフトをクリックしたとき。急行は停まる階だけ）
func call_car(cell: Vector2i) -> bool:
	var car = get_car_at(cell)
	return car != null and car.request_floor(cell.y)

# ---------------------------------------------------
# カゴの追加
# ---------------------------------------------------

# 指定マスのシャフトにカゴを追加できない理由（できるなら ""）
func get_add_car_problem(cell: Vector2i) -> String:
	if not is_shaft_type(world.get_building_type(cell)):
		return "カゴはエレベーターのシャフトに追加します"
	if get_cars_at(cell).size() >= MAX_CARS:
		return "1本のシャフトに置けるカゴは%d台までです" % MAX_CARS
	if world.funds < CAR_COST:
		return "資金不足です！"
	return ""

# 指定マスの階にカゴを1台追加する
func add_car(cell: Vector2i) -> bool:
	if get_add_car_problem(cell) != "":
		return false
	var first = get_car_at(cell)
	cars.append(create_car(first.shaft_type, shaft_column(cell), first.top_y, first.bottom_y, cell.y))
	world.funds -= CAR_COST
	return true

# 追加したカゴの台数（シャフトを建てたときの1台目を除く。維持費の計算用）
func count_extra_cars() -> int:
	return cars.filter(is_instance_valid).size() - find_shafts().size()

# ---------------------------------------------------
# 乗り場呼びの割り当て
# ---------------------------------------------------

# 乗り場でボタンを押す（待っている間は毎フレーム呼ばれる）。
# まだ割り当てがないか、割り当てたカゴがもう応えられない（呼び出しを取り消した）ときは、カゴを選び直す
func request_hall(cell: Vector2i, dir) -> void:
	var key := [cell, dir]
	var assigned = hall_assignments.get(key)
	if is_instance_valid(assigned) and assigned.has_floor(cell.y) and not assigned.is_full() \
			and (assigned.has_hall_call(cell.y, dir) or assigned.is_doors_open_at(cell.y)):
		return
	# 割り当てたカゴが満員になった・呼び出しに応えた後などは、割り当て直す
	if is_instance_valid(assigned) and not assigned.is_doors_open_at(cell.y):
		assigned.cancel_hall_call(cell.y, dir)
	var car = choose_car(cell, dir)
	if car == null:
		hall_assignments.erase(key)
		return
	hall_assignments[key] = car
	car.call_from_hall(cell.y, dir)

# 乗り場呼びに応えるカゴを選ぶ（群管理）: 到着までの手間の見積もりが一番小さいカゴ
func choose_car(cell: Vector2i, dir):
	var best = null
	var best_cost := 0.0
	for car in get_cars_at(cell):
		var cost: float = car.estimate_cost(cell.y, dir)
		if best == null or cost < best_cost:
			best = car
			best_cost = cost
	return best

# dir方向へ行きたい人が、この階で乗れるカゴ（なければnull）
func find_boardable_car(cell: Vector2i, dir):
	for car in get_cars_at(cell):
		if car.can_board(cell.y, dir):
			return car
	return null
