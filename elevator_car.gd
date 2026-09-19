extends Node2D

# ---------------------------------------------------
# エレベーターのカゴ：1本のシャフトの中を上下に動き、呼ばれた階に停まる。
# TileMapLayerの子として追加するので、positionはタイルマップ座標系。
#
# 集合制御（実際のエレベーターと同じ動かし方）:
#   - 進んでいる方向の先に呼び出しがある限り、その方向へ進み続け、途中の呼ばれた階に寄る
#   - 先に呼び出しがなくなったら折り返す
# 呼び出しの種類:
#   カゴ呼び  (car_calls)            … 乗っている人が押した行き先。方向に関係なく停まる
#   乗り場呼び(up_calls / down_calls) … 待っている人の呼び出し。その方向へ進むときに停まる
# 定員（CAPACITY）: 満員のカゴには乗れない。満員の間は乗り場呼びでは停まらず、カゴ呼びにだけ停まる。
# ※ yが小さいほど上の階なので、「上へ」はyが減る方向。
# ---------------------------------------------------

signal arrived(floor_y: int) # 階に停まって扉を開けたとき

enum State { IDLE, MOVING, DOORS_OPEN }
enum Direction { NONE, UP, DOWN }

const SPEED := 48.0    # 昇降の速さ（px/秒）
const DOOR_TIME := 1.0 # 停車して扉を開けている時間（秒）
const CAPACITY := 8    # 定員

var world: Node2D  # main.gd
var column: int    # シャフトのx座標
var top_y: int     # シャフトの最上階
var bottom_y: int  # シャフトの最下階
var floor_y: int   # 最後に通過・停車した階
var target_y: int  # 移動中に向かっている隣の階
var state := State.IDLE
var direction := Direction.NONE
var door_timer := 0.0
var car_calls := {}  # 階 -> true
var up_calls := {}   # 階 -> true
var down_calls := {} # 階 -> true
var passengers: Array = [] # 乗っている住人

func setup(p_world: Node2D, x: int, top: int, bottom: int) -> void:
	world = p_world
	column = x
	top_y = top
	bottom_y = bottom
	floor_y = bottom_y # 最下階からスタート
	target_y = floor_y
	position = floor_position(floor_y)
	z_index = 8 # マス目の表示より手前、住人より奥

# シャフトの範囲が変わったときに呼ぶ。範囲外になった呼び出しは取り消す
func set_shaft(top: int, bottom: int) -> void:
	top_y = top
	bottom_y = bottom
	for calls in [car_calls, up_calls, down_calls]:
		for y in calls.keys():
			if not has_floor(y):
				calls.erase(y)
	if not has_floor(target_y):
		target_y = floor_y # 向かっていた階がなくなったら、元の階に戻る

func has_floor(y: int) -> bool:
	return y >= top_y and y <= bottom_y

# 今いる階（移動中は、カゴの中心があるマスの階）
func current_floor() -> int:
	return world.tile_map.local_to_map(position).y

func floor_position(y: int) -> Vector2:
	return world.tile_map.map_to_local(Vector2i(column, y))

# ---------------------------------------------------
# 呼び出しの受け付け
# ---------------------------------------------------

# カゴ呼び（行き先ボタン）。シャフトの範囲外ならfalse
func request_floor(y: int) -> bool:
	if not has_floor(y):
		return false
	car_calls[y] = true
	return true

# 乗り場呼び。dirはその人が行きたい方向
func call_from_hall(y: int, dir: Direction) -> bool:
	if not has_floor(y):
		return false
	if dir == Direction.UP:
		up_calls[y] = true
	else:
		down_calls[y] = true
	return true

# 指定した階で停車して扉を開けているか
func is_doors_open_at(y: int) -> bool:
	return state == State.DOORS_OPEN and floor_y == y

# 定員に達しているか
func is_full() -> bool:
	passengers = passengers.filter(is_instance_valid) # いなくなった住人を除く
	return passengers.size() >= CAPACITY

# dir方向へ行きたい人が、この階で乗れるか（扉が開いていて、同じ方向へ進むか行き先が未定で、満員でない）
func can_board(y: int, dir: Direction) -> bool:
	return is_doors_open_at(y) and (direction == dir or direction == Direction.NONE) and not is_full()

# 乗り込んで行き先ボタンを押す。行き先が未定のカゴなら、その方向へ進むことにする
func board(resident, dest_y: int) -> void:
	passengers.append(resident)
	request_floor(dest_y)
	if direction == Direction.NONE:
		direction = Direction.UP if dest_y < floor_y else Direction.DOWN

# ---------------------------------------------------
# 動かし方
# ---------------------------------------------------

func _process(delta: float) -> void:
	match state:
		State.DOORS_OPEN:
			door_timer -= delta
			if door_timer <= 0.0:
				state = State.IDLE
		State.IDLE:
			decide_next_action()
		State.MOVING:
			position = position.move_toward(floor_position(target_y), SPEED * delta)
			if position == floor_position(target_y):
				floor_y = target_y
				if should_stop_at(floor_y):
					stop_here()
				elif has_calls_beyond(floor_y, direction):
					start_moving() # 停まらずに次の階へ
				else:
					state = State.IDLE
	queue_redraw()

# 停まっているときに、この階で扉を開けるか、どちらへ動くかを決める
func decide_next_action() -> void:
	var next_dir := choose_direction(floor_y)
	if car_calls.has(floor_y) or wants_hall_stop(floor_y, next_dir) \
			or (next_dir == Direction.NONE and wants_any_hall_stop(floor_y)):
		stop_here()
	elif next_dir != Direction.NONE:
		direction = next_dir
		start_moving()
	else:
		direction = Direction.NONE

func start_moving() -> void:
	target_y = floor_y + (-1 if direction == Direction.UP else 1)
	state = State.MOVING

# 移動中に階に着いたとき、ここで停まるか
func should_stop_at(y: int) -> bool:
	if car_calls.has(y) or wants_hall_stop(y, direction):
		return true
	# この先に呼び出しがないなら、逆方向の乗り場呼びでも停まって折り返す
	return not has_calls_beyond(y, direction) and wants_any_hall_stop(y)

# この階で停車する。次に進む方向を決め、その方向の乗り場呼びを取り消して扉を開ける
func stop_here() -> void:
	direction = choose_direction(floor_y)
	car_calls.erase(floor_y)
	if direction != Direction.DOWN:
		up_calls.erase(floor_y)
	if direction != Direction.UP:
		down_calls.erase(floor_y)
	state = State.DOORS_OPEN
	door_timer = DOOR_TIME
	arrived.emit(floor_y)

# y階にいるとき、次に進む方向
func choose_direction(y: int) -> Direction:
	if direction != Direction.NONE:
		var opposite := Direction.DOWN if direction == Direction.UP else Direction.UP
		if has_calls_beyond(y, direction):
			return direction # この先に呼び出しがある限り進み続ける
		if has_hall_call(y, opposite) or has_calls_beyond(y, opposite):
			return opposite  # 折り返す
		if has_hall_call(y, direction):
			return direction
		return Direction.NONE
	# 方向が決まっていないとき: この階の乗り場呼び → 一番近い呼び出しの方向
	if up_calls.has(y):
		return Direction.UP
	if down_calls.has(y):
		return Direction.DOWN
	var nearest = null
	for calls in [car_calls, up_calls, down_calls]:
		for c in calls:
			if c != y and (nearest == null or absi(c - y) < absi(nearest - y)):
				nearest = c
	if nearest == null:
		return Direction.NONE
	return Direction.UP if nearest < y else Direction.DOWN

# y階よりdir方向の先に、何か呼び出しがあるか
func has_calls_beyond(y: int, dir: Direction) -> bool:
	if dir == Direction.NONE:
		return false
	for calls in [car_calls, up_calls, down_calls]:
		for c in calls:
			if (dir == Direction.UP and c < y) or (dir == Direction.DOWN and c > y):
				return true
	return false

func has_hall_call(y: int, dir: Direction) -> bool:
	return (dir == Direction.UP and up_calls.has(y)) or (dir == Direction.DOWN and down_calls.has(y))

func has_any_hall_call(y: int) -> bool:
	return up_calls.has(y) or down_calls.has(y)

# 乗り場呼びで停まるか（満員なら誰も乗れないので停まらない）
func wants_hall_stop(y: int, dir: Direction) -> bool:
	return has_hall_call(y, dir) and not is_full()

func wants_any_hall_stop(y: int) -> bool:
	return has_any_hall_call(y) and not is_full()

# 降りる（乗客の一覧から外す）
func alight(resident) -> void:
	passengers.erase(resident)

# ---------------------------------------------------
# 描画
# ---------------------------------------------------

func _draw() -> void:
	var body := Rect2(-6, -7, 12, 14)
	draw_rect(body.grow(1), Color.BLACK)
	if state == State.DOORS_OPEN:
		# 扉が開いている：明るい室内と、左右に寄せた扉
		draw_rect(body, Color(1.0, 0.95, 0.7))
		draw_rect(Rect2(-6, -7, 2, 14), Color(0.75, 0.78, 0.85))
		draw_rect(Rect2(4, -7, 2, 14), Color(0.75, 0.78, 0.85))
	else:
		# 扉が閉まっている：銀色の扉と中央の合わせ目
		draw_rect(body, Color(0.75, 0.78, 0.85))
		draw_line(Vector2(0, -7), Vector2(0, 7), Color(0.3, 0.3, 0.35), 1.0)
	# 乗っている人数のゲージ（満員なら赤）
	var load_ratio := float(passengers.size()) / CAPACITY
	if load_ratio > 0.0:
		var gauge_color := Color(1.0, 0.3, 0.3) if passengers.size() >= CAPACITY else Color(0.3, 1.0, 0.4)
		draw_rect(Rect2(-6, 5, 12.0 * minf(load_ratio, 1.0), 2), gauge_color)
	# 進行方向の表示（▲ 上へ / ▼ 下へ）
	var arrow_color := Color(0.3, 1.0, 0.4)
	if direction == Direction.UP:
		draw_colored_polygon(PackedVector2Array([Vector2(0, -12), Vector2(-3, -9), Vector2(3, -9)]), arrow_color)
	elif direction == Direction.DOWN:
		draw_colored_polygon(PackedVector2Array([Vector2(0, -9), Vector2(-3, -12), Vector2(3, -12)]), arrow_color)
