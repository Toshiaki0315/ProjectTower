extends Node

# ---------------------------------------------------
# エレベーターの管理：グリッド情報からシャフトを組み立て、シャフトごとにカゴを置く。
# シャフト = 同じ列で縦につながった "elevator" のマスのまとまり。
# 建設・撤去のたびに rebuild() を呼んで、シャフトとカゴを作り直す。
#
# カゴ: シャフトを建てると1台できる。add_car() で1本のシャフトに MAX_CARS 台まで増やせる。
# 乗り場呼び: 待っている人のボタンはシャフト全体で受け付け、choose_car() で選んだカゴに割り当てる。
# ---------------------------------------------------

const ElevatorCar := preload("res://elevator_car.gd")
const TYPE := "elevator"
const MAX_CARS := 4        # 1本のシャフトに置けるカゴの数
const CAR_COST := 50000    # カゴを1台追加する費用
const CAR_MAINTENANCE := 3000 # 追加したカゴ1台の1日の維持費

var world: Node2D  # main.gd
var cars: Array = [] # すべてのカゴ（シャフトは column と top_y〜bottom_y で分かる）
var hall_assignments := {} # [乗り場のマス, 方向] -> 割り当てたカゴ

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
			if c.column == shaft.x and c.current_floor() >= shaft.top and c.current_floor() <= shaft.bottom:
				remaining.erase(c)
				c.set_shaft(shaft.top, shaft.bottom)
				new_cars.append(c)
				kept += 1
		if kept == 0:
			new_cars.append(create_car(shaft.x, shaft.top, shaft.bottom, shaft.bottom))
	# シャフトがなくなった（または途中を撤去されて居場所がなくなった）カゴは消す
	for c in remaining:
		c.queue_free()
	cars = new_cars

func create_car(x: int, top: int, bottom: int, start_y: int):
	var car = ElevatorCar.new()
	car.setup(world, x, top, bottom, start_y)
	car.arrived.connect(func(y): world.show_message("エレベーターが %s に到着しました" % Vector2i(car.column, y)))
	world.tile_map.add_child(car)
	return car

# シャフトの一覧: [{"x": 列, "top": 最上階のy, "bottom": 最下階のy}, ...]
func find_shafts() -> Array:
	var result: Array = []
	for cell: Vector2i in world.find_cells_of_type(TYPE):
		# シャフトの最下段のマスからだけ数え始める
		if world.get_building_type(cell + Vector2i.DOWN) == TYPE:
			continue
		var top: int = cell.y
		while world.get_building_type(Vector2i(cell.x, top - 1)) == TYPE:
			top -= 1
		result.append({"x": cell.x, "top": top, "bottom": cell.y})
	return result

# 指定したマスを含むシャフトのカゴの一覧
func get_cars_at(cell: Vector2i) -> Array:
	var result: Array = []
	for car in cars:
		if is_instance_valid(car) and car.column == cell.x and car.has_floor(cell.y):
			result.append(car)
	return result

# 指定したマスを含むシャフトのカゴ（1台目。なければnull）
func get_car_at(cell: Vector2i):
	var list := get_cars_at(cell)
	return list[0] if not list.is_empty() else null

# 指定したマスの階にカゴを呼ぶ（エレベーターモードでシャフトをクリックしたとき）
func call_car(cell: Vector2i) -> bool:
	var car = get_car_at(cell)
	return car != null and car.request_floor(cell.y)

# ---------------------------------------------------
# カゴの追加
# ---------------------------------------------------

# 指定マスのシャフトにカゴを追加できない理由（できるなら ""）
func get_add_car_problem(cell: Vector2i) -> String:
	if world.get_building_type(cell) != TYPE:
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
	cars.append(create_car(cell.x, first.top_y, first.bottom_y, cell.y))
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
	if is_instance_valid(assigned) and assigned.has_floor(cell.y) \
			and (assigned.has_hall_call(cell.y, dir) or assigned.is_doors_open_at(cell.y)):
		return
	var car = choose_car(cell, dir)
	if car == null:
		hall_assignments.erase(key)
		return
	hall_assignments[key] = car
	car.call_from_hall(cell.y, dir)

# 乗り場呼びに応えるカゴを選ぶ（今は一番近いカゴ）
func choose_car(cell: Vector2i, _dir):
	var best = null
	for car in get_cars_at(cell):
		if best == null or absi(car.current_floor() - cell.y) < absi(best.current_floor() - cell.y):
			best = car
	return best

# dir方向へ行きたい人が、この階で乗れるカゴ（なければnull）
func find_boardable_car(cell: Vector2i, dir):
	for car in get_cars_at(cell):
		if car.can_board(cell.y, dir):
			return car
	return null
