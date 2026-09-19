extends Node

# ---------------------------------------------------
# エレベーターの管理：グリッド情報からシャフトを組み立て、シャフトごとにカゴを1台置く。
# シャフト = 同じ列で縦につながった "elevator" のマスのまとまり。
# 建設・撤去のたびに rebuild() を呼んで、シャフトとカゴを作り直す。
# ---------------------------------------------------

const ElevatorCar := preload("res://elevator_car.gd")
const TYPE := "elevator"

var world: Node2D  # main.gd
var cars: Array = [] # シャフトごとのカゴ

func setup(p_world: Node2D) -> void:
	world = p_world

# グリッド情報からシャフトを探し直し、カゴを対応させる。
# 既存のカゴは、今いる階を含むシャフトにそのまま引き継ぐ。
func rebuild() -> void:
	var remaining := cars.duplicate()
	var new_cars: Array = []
	for shaft in find_shafts():
		var car = null
		for c in remaining:
			if c.column == shaft.x and c.current_floor() >= shaft.top and c.current_floor() <= shaft.bottom:
				car = c
				break
		if car:
			remaining.erase(car)
			car.set_shaft(shaft.top, shaft.bottom)
		else:
			car = ElevatorCar.new()
			car.setup(world, shaft.x, shaft.top, shaft.bottom)
			car.arrived.connect(func(y): world.show_message("エレベーターが %s に到着しました" % Vector2i(car.column, y)))
			world.tile_map.add_child(car)
		new_cars.append(car)
	# シャフトがなくなった（または途中を撤去されて居場所がなくなった）カゴは消す
	for c in remaining:
		c.queue_free()
	cars = new_cars

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

# 指定したマスを含むシャフトのカゴ（なければnull）
func get_car_at(cell: Vector2i):
	for car in cars:
		if car.column == cell.x and car.has_floor(cell.y):
			return car
	return null

# 指定したマスの階にカゴを呼ぶ
func call_car(cell: Vector2i) -> bool:
	var car = get_car_at(cell)
	return car != null and car.request_floor(cell.y)
