extends Node

# ---------------------------------------------------
# 移動ルールと経路探索：人がどこへ動けるか（get_moves）と、
# 目的地までの一番楽な道（find_path）を受け持つ。
# ---------------------------------------------------

var world: Node2D # main.gd

func setup(p_world: Node2D) -> void:
	world = p_world


# 移動の手間（コスト）。経路探索はこの合計が一番小さい経路を選ぶ。
# 1〜2階の移動なら階段、3階以上ならエレベーターの方が得になるよう調整している。
const WALK_COST := 1.0           # 横に1マス歩く
const STAIRS_COST := 2.0         # 階段で1階分上り下りする
const ESCALATOR_COST := 1.0      # エスカレーターで1階分上り下りする（待ち時間がなく、階段より楽）
const ELEVATOR_WAIT_COST := 4.0  # エレベーターに乗る（待ち時間の見込み。定員が大きいカゴほど短くなる）
const ELEVATOR_FLOOR_COST := 0.5 # エレベーターで1階分移動する
const VIP_WAIT_COST := 0.5      # VIPがVIP専用のカゴに乗る（待たずに乗れる）

# 指定マスから1回で移動できる先とそのコストの一覧（住人の移動ルールはすべてここで決まる）
# - 横移動:       隣のマスに建物があれば歩ける（エレベーターの扉の前も通り抜けられる）
# - 階段:         階段マスは、そのマスと1つ上の階をつなぐ
# - エスカレーター: 横2マス。左のマス（乗り口）と、1つ上の階の右のマスの上（降り口）を斜めにつなぐ。
#                   上りも下りも使える。定員も待ち時間もない
# - エレベーター: シャフトのマスから、同じシャフトの別の階へ乗って移動できる
#                 （サービスエレベーターは裏方＝清掃員だけ乗れる。staff で切り替える）
#                 （急行は1階とスカイロビーの階の間だけ。速いので1階分のコストは標準の1/3）
# 戻り値: [{"to": Vector2i, "cost": float}, ...]
#                 （VIP専用のシャフトは、VIPの来館中はVIPだけが乗れる。vip で切り替える）
func get_moves(cell: Vector2i, staff := false, vip := false) -> Array:
	var result: Array = []
	if not world.is_walkable(cell):
		return result
	for dir in [Vector2i.LEFT, Vector2i.RIGHT]:
		if world.is_walkable(cell + dir):
			result.append({"to": cell + dir, "cost": WALK_COST})
	if world.get_building_type(cell) == "stairs" and world.is_walkable(cell + Vector2i.UP):
		result.append({"to": cell + Vector2i.UP, "cost": STAIRS_COST})
	if world.get_building_type(cell + Vector2i.DOWN) == "stairs":
		result.append({"to": cell + Vector2i.DOWN, "cost": STAIRS_COST})
	if is_escalator_foot(cell) and world.is_walkable(cell + ESCALATOR_UP):
		result.append({"to": cell + ESCALATOR_UP, "cost": ESCALATOR_COST})
	if is_escalator_foot(cell - ESCALATOR_UP):
		result.append({"to": cell - ESCALATOR_UP, "cost": ESCALATOR_COST})
	var reserved: bool = world.elevator_system.is_reserved_for_vip(cell)
	if world.elevator_system.is_shaft_type(world.get_building_type(cell)) and (staff or world.get_building_type(cell) != "service_elevator") \
			and (vip or not reserved):
		var car = world.elevator_system.get_car_at(cell)
		if car and car.in_service and car.is_stop_floor(cell.y):
			# 速いカゴほど1階ぶんが安く、定員の大きいカゴほど待ち時間の見込みが短い
			var floor_cost: float = ELEVATOR_FLOOR_COST * car.SPEED / car.speed
			var wait_cost: float = ELEVATOR_WAIT_COST * car.CAPACITY / car.capacity
			if vip and reserved:
				wait_cost = VIP_WAIT_COST # VIP専用のカゴは待たずに乗れるので、VIPはこちらを選ぶ
			for y in range(car.top_y, car.bottom_y + 1):
				if y != cell.y and car.is_stop_floor(y):
					var cost := wait_cost + floor_cost * absi(y - cell.y)
					result.append({"to": Vector2i(cell.x, y), "cost": cost})
	return result

# fromからtoへ1回で移動できるか
# 乗り場で待つ人は毎フレームこれを確かめるので、エレベーターで上下する移動は、行き先の一覧を作らずに
# get_moves() と同じ条件を直接確かめる（高いビルでは一覧が数十階ぶんになり、待つ人が多いと重いため）
func can_move(from: Vector2i, to: Vector2i, staff := false, vip := false) -> bool:
	if is_elevator_ride(from, to):
		return can_ride_elevator(from, to, staff, vip)
	for move in get_moves(from, staff, vip):
		if move.to == to:
			return true
	return false

# fromのシャフトのカゴで、toの階へ行けるか（get_moves() のエレベーターの条件と同じ）
func can_ride_elevator(from: Vector2i, to: Vector2i, staff: bool, vip: bool) -> bool:
	if not world.is_walkable(from):
		return false
	var type: String = world.get_building_type(from)
	if type == "service_elevator" and not staff:
		return false
	if world.elevator_system.is_reserved_for_vip(from) and not vip:
		return false
	var car = world.elevator_system.get_car_at(from)
	return car != null and car.in_service and car.is_stop_floor(from.y) \
		and to.y >= car.top_y and to.y <= car.bottom_y and car.is_stop_floor(to.y)

# エスカレーターの上り口（左下のマス）の、上の階の降り口までのずれ
const ESCALATOR_UP := Vector2i(1, -1)

# エスカレーターの上り口（左のマス）か
func is_escalator_foot(cell: Vector2i) -> bool:
	return world.get_building_type(cell) == "escalator" and world.building_grid[cell].origin == cell

# fromからtoへの移動がエスカレーターに乗る移動か
func is_escalator_ride(from: Vector2i, to: Vector2i) -> bool:
	return (to - from == ESCALATOR_UP and is_escalator_foot(from)) or (from - to == ESCALATOR_UP and is_escalator_foot(to))

# fromからtoへの移動がエレベーターに乗る移動か（同じシャフト内の別の階への移動）
func is_elevator_ride(from: Vector2i, to: Vector2i) -> bool:
	return from.x == to.x and from.y != to.y and world.elevator_system.is_shaft_type(world.get_building_type(from)) \
		and world.get_building_type(from) == world.get_building_type(to)

# ダイクストラ法でコストが最小の経路を求める
# 戻り値: [from, ..., to] のマス配列。経路がなければ空配列。
func find_path(from: Vector2i, to: Vector2i, staff := false, vip := false) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if world.is_cell_empty(from) or world.is_cell_empty(to):
		return result
	
	var cost_so_far := {} # マス -> スタートからの最小コスト
	var came_from := {}   # マス -> 1つ前のマス
	cost_so_far[from] = 0.0
	came_from[from] = from
	var open: Array[Vector2i] = [from] # これから調べるマス
	var done := {}                     # 最小コストが確定したマス
	while not open.is_empty():
		# まだ調べていないマスのうち、コストが一番小さいものを取り出す
		var best := 0
		for i in range(1, open.size()):
			if cost_so_far[open[i]] < cost_so_far[open[best]]:
				best = i
		var current: Vector2i = open[best]
		open.remove_at(best)
		if current == to:
			# ゴールからスタートまで逆にたどって経路を組み立てる
			var c := to
			while c != from:
				result.push_front(c)
				c = came_from[c]
			result.push_front(from)
			return result
		done[current] = true
		for move in get_moves(current, staff, vip):
			var next: Vector2i = move.to
			if done.has(next):
				continue
			var new_cost: float = cost_so_far[current] + move.cost
			if not cost_so_far.has(next) or new_cost < cost_so_far[next]:
				cost_so_far[next] = new_cost
				came_from[next] = current
				if not open.has(next):
					open.append(next)
	return result

