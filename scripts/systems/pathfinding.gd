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
const CROWD_WAIT_COST := 2.0    # シャフトの乗り場で待っている人1人ぶんの手間（カゴの数で割る。混んでいるシャフトほど避ける）

# 指定マスから1回で移動できる先とそのコストの一覧（住人の移動ルールはすべてここで決まる）
# - 横移動:       隣のマスに建物があれば歩ける（エレベーターの扉の前も通り抜けられる）
# - 階段:         階段マスは、そのマスと1つ上の階をつなぐ
# - エスカレーター: 横2マス。左のマス（乗り口）と、1つ上の階の右のマスの上（降り口）を斜めにつなぐ。
#                   上りも下りも使える。定員も待ち時間もない
# - エレベーター: シャフトのマスから、同じシャフトの別の階へ乗って移動できる
#                 （シャフトの乗り場で待っている人が多いほど、待つ手間を高く見る。空いているシャフトを選ぶように）
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
			# シャフトが混んでいるほど、待ち時間が長くなる見込み（カゴが多いシャフトほど早くさばける）
			var cars_here: int = world.elevator_system.get_cars_at(cell).size()
			wait_cost += CROWD_WAIT_COST * world.elevator_system.waiting_at(cell) / maxi(cars_here, 1)
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
# 次に調べるマスは、優先度つきキュー（二分ヒープ）から一番コストの小さいものを取り出す
# （一覧を毎回全部なめると、高いビルで人が大勢来たときに重いため）。
# コストが同じなら、先に一覧に入ったマスを先に調べる（どの経路を選ぶかが、前と変わらないように）。
func find_path(from: Vector2i, to: Vector2i, staff := false, vip := false) -> Array[Vector2i]:
	if world.is_cell_empty(to):
		var none: Array[Vector2i] = []
		return none
	return find_path_to_any(from, {to: true}, staff, vip)

# fromから、targets（マス -> true）のどれか一番コストの小さいマスまでの経路（なければ空配列）
# 一番近い入口を探すときに、入口ごとに経路探索をしなくてすむ（1回で、着いたところで止まる）
func find_path_to_any(from: Vector2i, targets: Dictionary, staff := false, vip := false) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if world.is_cell_empty(from) or targets.is_empty():
		return result
	
	var cost_so_far := {} # マス -> スタートからの最小コスト
	var came_from := {}   # マス -> 1つ前のマス
	var order := {}       # マス -> はじめて一覧に入った順番（コストが同じときに先に調べる順）
	cost_so_far[from] = 0.0
	came_from[from] = from
	order[from] = 0
	# これから調べるマス [コスト, 順番, マス]。コストを下げたら入れ直し、古いものは取り出したときに捨てる
	var heap: Array = [[0.0, 0, from]]
	var done := {} # 最小コストが確定したマス
	while not heap.is_empty():
		var current: Vector2i = heap_pop(heap)[2]
		if done.has(current):
			continue # コストを下げる前に入れた古いもの
		if targets.has(current):
			# ゴールからスタートまで逆にたどって経路を組み立てる
			var c := current
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
				if not order.has(next):
					order[next] = order.size()
				heap_push(heap, [new_cost, order[next], next])
	return result

# ---------------------------------------------------
# 入口への道しるべ（entrance_field）: 入口から逆向きにビル全体を1回だけ調べて、
# マスごとに「一番近い入口へ向かうとき、次に進むマス」を覚えておく。
# 通勤の時間帯に大勢が来ても、1人ずつ経路を探さずに、道しるべをたどるだけですむ。
# 移動の手間は行きも帰りも同じなので、入口から来るときも、入口へ帰るときも使える。
# 乗り場の混み具合で手間が変わるので、ゲーム内で FIELD_MINUTES 分たつか、どこかのシャフトで待っている人が
# FIELD_CROWD_CHANGE 人以上増減したか、建物・入口が変わったら作り直す
# （作り直さないと、その間に来た人がみんな同じシャフトを選んで、1本にばかり並んでしまうため）。
# ---------------------------------------------------
const FIELD_MINUTES := 1.0
const FIELD_CROWD_CHANGE := 2
var entrance_fields := {} # [staff, vip] -> {"version": 建物の版, "entrances": 入口の一覧, "time": 作った時刻（分）,
                          #   "crowd": 作ったときのシャフトごとの待っている人数, "next": マス -> 次のマス}

# fromから一番近い入口までの経路 [from, ..., 入口]（たどり着けなければ空配列）
func path_to_nearest_entrance(from: Vector2i, entrances: Array[Vector2i], staff := false, vip := false) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var next: Dictionary = entrance_field(entrances, staff, vip)
	if not next.has(from):
		return result
	var c := from
	result.append(c)
	while next[c] != c:
		c = next[c]
		result.append(c)
	return result

# 入口への道しるべ（マス -> 次に進むマス。入口は自分自身）。古くなっていたら作り直す
func entrance_field(entrances: Array[Vector2i], staff: bool, vip: bool) -> Dictionary:
	var key := [staff, vip]
	var now: float = world.clock.day * world.clock.MINUTES_PER_DAY + world.clock.minute
	var crowd: Dictionary = world.elevator_system.waiting_counts_now()
	var field = entrance_fields.get(key)
	if field != null and field.version == world.building_version and field.entrances == entrances \
			and now - field.time < FIELD_MINUTES and now >= field.time and not crowd_changed(field.crowd, crowd):
		return field.next
	field = {"version": world.building_version, "entrances": entrances.duplicate(), "time": now, "crowd": crowd.duplicate(),
		"next": build_entrance_field(entrances, staff, vip)}
	entrance_fields[key] = field
	return field.next

# 道しるべを作ったときから、どこかのシャフトで待っている人が FIELD_CROWD_CHANGE 人以上増減したか
static func crowd_changed(before: Dictionary, now: Dictionary) -> bool:
	for key in now:
		if absi(now[key] - before.get(key, 0)) >= FIELD_CROWD_CHANGE:
			return true
	for key in before:
		if not now.has(key) and before[key] >= FIELD_CROWD_CHANGE:
			return true
	return false

# 入口からのダイクストラ法（入口が複数のスタート）。マス -> 入口へ向かうときに次に進むマス
func build_entrance_field(entrances: Array[Vector2i], staff: bool, vip: bool) -> Dictionary:
	var cost_so_far := {}
	var toward := {} # マス -> 入口へ向かうときに次に進むマス
	var order := {}
	var heap: Array = []
	for e in entrances:
		if world.is_cell_empty(e) or cost_so_far.has(e):
			continue
		cost_so_far[e] = 0.0
		toward[e] = e
		order[e] = order.size()
		heap_push(heap, [0.0, order[e], e])
	var done := {}
	while not heap.is_empty():
		var current: Vector2i = heap_pop(heap)[2]
		if done.has(current):
			continue
		done[current] = true
		# current から行けるマスは、そこから current へも同じ手間で戻れる（移動は行きも帰りも同じ）
		for move in get_moves(current, staff, vip):
			var next: Vector2i = move.to
			if done.has(next):
				continue
			var new_cost: float = cost_so_far[current] + move.cost
			if not cost_so_far.has(next) or new_cost < cost_so_far[next]:
				cost_so_far[next] = new_cost
				toward[next] = current
				if not order.has(next):
					order[next] = order.size()
				heap_push(heap, [new_cost, order[next], next])
	return toward

# 二分ヒープ: [コスト, 順番, マス] を、コスト → 順番 の小さい順に取り出す
static func heap_less(a: Array, b: Array) -> bool:
	return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])

static func heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if not heap_less(heap[i], heap[parent]):
			break
		var swap: Array = heap[i]
		heap[i] = heap[parent]
		heap[parent] = swap
		i = parent

static func heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	var n := heap.size()
	while true:
		var smallest := i
		var left := i * 2 + 1
		var right := left + 1
		if left < n and heap_less(heap[left], heap[smallest]):
			smallest = left
		if right < n and heap_less(heap[right], heap[smallest]):
			smallest = right
		if smallest == i:
			break
		var swap: Array = heap[i]
		heap[i] = heap[smallest]
		heap[smallest] = swap
		i = smallest
	return top
