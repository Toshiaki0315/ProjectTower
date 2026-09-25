extends Node2D

# ---------------------------------------------------
# エレベーターのカゴ：1本のシャフトの中を上下に動き、呼ばれた階に停まる。
# TileMapLayerの子として追加するので、positionはタイルマップ座標系。
#
# 待機階（ホーム）: 設定すると、呼び出しがなくなったカゴはその階に戻って待つ。
# 稼働時間帯: 決めた時間帯の外では、呼び出しを受け付けず、待機階に戻って止まる。
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

const SPEED := 48.0    # 昇降の速さ（px/秒。標準エレベーター）
const DOOR_TIME := 1.0 # 停車して扉を開けている時間（秒）
const CAPACITY := 8    # 定員（標準エレベーター）
const EXPRESS_SPEED := 144.0 # 急行エレベーターの速さ（標準の3倍）
const EXPRESS_CAPACITY := 20 # 急行エレベーターの定員
const LARGE_SPEED := 72.0    # 大型エレベーターの速さ（標準の1.5倍）
const LARGE_CAPACITY := 16   # 大型エレベーターの定員（標準の2倍）
const STANDARD_COLOR := Color(0.75, 0.78, 0.85) # 標準のカゴの扉（銀）
const EXPRESS_COLOR := Color(0.95, 0.78, 0.3)   # 急行のカゴの扉（金）
const SERVICE_COLOR := Color(0.45, 0.75, 0.65)  # サービスのカゴの扉（緑）
const LARGE_COLOR := Color(0.6, 0.72, 0.95)     # 大型のカゴの扉（青）

# 群管理で乗り場呼びを割り当てるときの手間（コスト）の見積もり。単位は「階数」
const STOP_COST := 1.5     # 停まる予定1つあたり（扉の開け閉めの時間）
const LOAD_COST := 0.3     # 乗っている人1人あたり（混んでいるカゴはなるべく避ける）
const FULL_COST := 100.0   # 満員のカゴ（停まっても乗れない）

var world: Node2D  # main.gd
var column: int    # シャフトのx座標
var shaft_type := "elevator" # シャフトの種類（"elevator" = 標準 / "express_elevator" = 急行 / "large_elevator" = 大型 / "service_elevator" = サービス）
var speed := SPEED       # 昇降の速さ（急行・大型は速い）
var capacity := CAPACITY # 定員（急行・大型は大きい）
var width_cells := 1     # カゴの横幅（マス数。大型は2）
var body_color := STANDARD_COLOR # 扉の色（標準は銀、急行は金、大型は青、サービスは緑）
var top_y: int     # シャフトの最上階
var bottom_y: int  # シャフトの最下階
var floor_y: int   # 最後に通過・停車した階
var target_y: int  # 移動中に向かっている隣の階
var state := State.IDLE
var direction := Direction.NONE
var door_timer := 0.0
var opened_frame := -1 # 扉を開けたフレーム（そのフレームのうちは閉めない。待っている人が乗り込めるように）
var car_calls := {}  # 階 -> true
var up_calls := {}   # 階 -> true
var down_calls := {} # 階 -> true
var passengers: Array = [] # 乗っている住人
var home_y := 0    # 待機階（呼び出しがなくなったら戻る階）
var has_home_floor := false # 待機階を設定しているか
var in_service := true # 稼働時間帯の中か（外では呼び出しを受け付けず、待機階へ戻って止まる）

# start_y: カゴが最初にいる階（シャフトを建てたときは最下階、カゴを追加したときはクリックした階）
func setup(p_world: Node2D, x: int, top: int, bottom: int, start_y: int) -> void:
	world = p_world
	column = x
	top_y = top
	bottom_y = bottom
	floor_y = start_y
	target_y = floor_y
	position = floor_position(floor_y)
	z_index = 8 # マス目の表示より手前、住人より奥

# シャフトの種類を決める（急行は速く・金色、大型は横2マスで定員が大きい）
func set_shaft_type(type: String) -> void:
	shaft_type = type
	speed = SPEED
	capacity = CAPACITY
	width_cells = 1
	body_color = STANDARD_COLOR
	if type == "express_elevator":
		speed = EXPRESS_SPEED
		capacity = EXPRESS_CAPACITY
		body_color = EXPRESS_COLOR
	elif type == "large_elevator":
		speed = LARGE_SPEED
		capacity = LARGE_CAPACITY
		width_cells = 2
		body_color = LARGE_COLOR
	elif type == "service_elevator":
		body_color = SERVICE_COLOR
	queue_redraw()

# 指定した階にカゴを置き直す（セーブデータの読み込み用）
func place_at_floor(y: int) -> void:
	if not has_floor(y):
		return
	floor_y = y
	target_y = y
	position = floor_position(y)
	state = State.IDLE
	direction = Direction.NONE

# シャフトの範囲が変わったときに呼ぶ。範囲外になった呼び出しは取り消す
func set_shaft(top: int, bottom: int) -> void:
	top_y = top
	bottom_y = bottom
	for calls in [car_calls, up_calls, down_calls]:
		for y in calls.keys():
			if not is_stop_floor(y):
				calls.erase(y)
	if not has_floor(target_y):
		target_y = floor_y # 向かっていた階がなくなったら、元の階に戻る

func has_floor(y: int) -> bool:
	return y >= top_y and y <= bottom_y

# 停まれる階か（標準はシャフトの全部の階、急行は1階とスカイロビーの階だけ）
func is_stop_floor(y: int) -> bool:
	if not has_floor(y):
		return false
	return shaft_type != "express_elevator" or world.is_express_stop_floor(y)

# 今いる階（移動中は、カゴの中心があるマスの階）
func current_floor() -> int:
	return world.tile_map.local_to_map(position).y

func floor_position(y: int) -> Vector2:
	# 横2マスの大型は、2マスの真ん中に来るように半マスずらす
	return world.tile_map.map_to_local(Vector2i(column, y)) + Vector2((width_cells - 1) * 8.0, 0)

# ---------------------------------------------------
# 呼び出しの受け付け
# ---------------------------------------------------

# カゴ呼び（行き先ボタン）。停まれない階（シャフトの範囲外・急行の途中の階）ならfalse
func request_floor(y: int) -> bool:
	if not in_service or not is_stop_floor(y):
		return false
	car_calls[y] = true
	return true

# 乗り場呼び。dirはその人が行きたい方向
func call_from_hall(y: int, dir: Direction) -> bool:
	if not in_service or not is_stop_floor(y):
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
	return passengers.size() >= capacity

# dir方向へ行きたい人が、この階で乗れるか（扉が開いていて、同じ方向へ進むか行き先が未定で、満員でない）
func can_board(y: int, dir: Direction) -> bool:
	return in_service and is_doors_open_at(y) and (direction == dir or direction == Direction.NONE) and not is_full()

# 乗り込んで行き先ボタンを押す。行き先が未定のカゴなら、その方向へ進むことにする
func board(resident, dest_y: int) -> void:
	passengers.append(resident)
	request_floor(dest_y)
	if direction == Direction.NONE:
		direction = Direction.UP if dest_y < floor_y else Direction.DOWN

# y階で dir 方向へ行きたい人を拾いに行く手間の見積もり（群管理でカゴを選ぶのに使う。小さいほど早く着く）
#   止まっているカゴ:                         今の階からの距離
#   同じ方向に進んでいて、その階がまだ先にある: 今の階からの距離（途中で拾える）
#   それ以外（逆方向・通り過ぎた）:            今の方向の一番先の呼び出しまで行って、折り返してくる距離
#   ＋ 停まる予定の数・乗っている人数・満員かどうか
func estimate_cost(y: int, dir: Direction) -> float:
	var cur := current_floor()
	var cost := 0.0
	if direction == Direction.NONE:
		cost = absi(cur - y)
	else:
		var ahead: bool = (direction == Direction.UP and y <= cur) or (direction == Direction.DOWN and y >= cur)
		if ahead and direction == dir:
			cost = absi(cur - y)
		else:
			var end := farthest_call(direction, cur)
			cost = absi(cur - end) + absi(end - y)
	cost += STOP_COST * (car_calls.size() + up_calls.size() + down_calls.size())
	cost += LOAD_COST * passengers.size()
	if is_full():
		cost += FULL_COST
	return cost

# dir 方向に進んだとき、一番先にある呼び出しの階（なければ from）
func farthest_call(dir: Direction, from: int) -> int:
	var result := from
	for calls in [car_calls, up_calls, down_calls]:
		for c in calls:
			if (dir == Direction.UP and c < result) or (dir == Direction.DOWN and c > result):
				result = c
	return result

# 乗り場呼びを取り消す（群管理で別のカゴに割り当て直したとき）
func cancel_hall_call(y: int, dir: Direction) -> void:
	if dir == Direction.UP:
		up_calls.erase(y)
	else:
		down_calls.erase(y)

# ---------------------------------------------------
# 動かし方
# ---------------------------------------------------

# 1フレームの時間を使い切るまで、扉の開け閉め・次の行き先を決める・動く を続けて進める
#（1つ切り替えるたびに次のフレームを待つと、早送り中やfpsが低いときほど停まるたびに時間を失い、カゴが遅くなってしまう）
# ただし扉を開けたフレームのうちは閉めない（待っている人は、扉が開いているのを見て乗り込むため）
const MAX_STEPS_PER_FRAME := 16 # 1フレームに切り替える回数の上限（念のため）

func _process(delta: float) -> void:
	var time_left := delta
	for step in MAX_STEPS_PER_FRAME:
		if time_left <= 0.0:
			break
		if state == State.DOORS_OPEN:
			if opened_frame == Engine.get_process_frames() or door_timer > time_left:
				door_timer -= time_left
				break
			time_left -= door_timer # 前のフレームで扉の時間が切れていたら（マイナス）、その分も今のフレームで進む
			state = State.IDLE
		elif state == State.IDLE:
			decide_next_action()
			if state == State.IDLE:
				break # 呼び出しがなく、止まったまま
		elif state == State.MOVING:
			time_left = move(time_left)
	queue_redraw()

# 動く。1フレームで階をまたいでも、余った時間ぶんは続けて進む。停まったら（扉を開けた・止まった）、余った時間を返す
func move(time_left: float) -> float:
	while time_left > 0.0 and state == State.MOVING:
		var target_pos := floor_position(target_y)
		var distance := position.distance_to(target_pos)
		if speed * time_left < distance:
			position = position.move_toward(target_pos, speed * time_left)
			return 0.0
		position = target_pos
		time_left -= distance / speed
		floor_y = target_y
		if should_stop_at(floor_y):
			stop_here()
		elif has_calls_beyond(floor_y, direction):
			start_moving() # 停まらずに次の階へ
		else:
			state = State.IDLE
	return time_left

# 停まっているときに、この階で扉を開けるか、どちらへ動くかを決める
func decide_next_action() -> void:
	# 稼働時間帯の外: 呼び出しを捨てて、待機階に戻って止まる
	if not in_service:
		car_calls.clear()
		up_calls.clear()
		down_calls.clear()
		direction = Direction.NONE
		if wants_to_go_home():
			direction = Direction.UP if home_y < floor_y else Direction.DOWN
			start_moving()
		return
	var next_dir := choose_direction(floor_y)
	if car_calls.has(floor_y) or wants_hall_stop(floor_y, next_dir) \
			or (next_dir == Direction.NONE and wants_any_hall_stop(floor_y)):
		stop_here()
	elif next_dir != Direction.NONE:
		direction = next_dir
		start_moving()
	else:
		direction = Direction.NONE
		# 呼び出しがなくなったら、待機階へ戻る
		if wants_to_go_home():
			direction = Direction.UP if home_y < floor_y else Direction.DOWN
			start_moving()

# 待機階が設定されていて、そこから離れているか
func wants_to_go_home() -> bool:
	return has_home_floor and has_floor(home_y) and floor_y != home_y

# 待機階を設定する（解除するときは set_home(0, false)）
func set_home(y: int, enabled := true) -> void:
	home_y = y
	has_home_floor = enabled

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
	opened_frame = Engine.get_process_frames()
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
	var half := 6.0 + (width_cells - 1) * 8.0 # 大型は横2マスぶんの幅で描く
	var body := Rect2(-half, -7, half * 2.0, 14)
	draw_rect(body.grow(1), Color.BLACK)
	if state == State.DOORS_OPEN:
		# 扉が開いている：明るい室内と、左右に寄せた扉
		draw_rect(body, Color(1.0, 0.95, 0.7))
		draw_rect(Rect2(-half, -7, 2, 14), body_color)
		draw_rect(Rect2(half - 2, -7, 2, 14), body_color)
	else:
		# 扉が閉まっている：銀色（急行は金色）の扉と中央の合わせ目
		draw_rect(body, body_color)
		draw_line(Vector2(0, -7), Vector2(0, 7), Color(0.3, 0.3, 0.35), 1.0)
	# 乗っている人数のゲージ（満員なら赤）
	var load_ratio := float(passengers.size()) / capacity
	if load_ratio > 0.0:
		var gauge_color := Color(1.0, 0.3, 0.3) if passengers.size() >= capacity else Color(0.3, 1.0, 0.4)
		draw_rect(Rect2(-half, 5, half * 2.0 * minf(load_ratio, 1.0), 2), gauge_color)
	# 進行方向の表示（▲ 上へ / ▼ 下へ）
	var arrow_color := Color(0.3, 1.0, 0.4)
	if direction == Direction.UP:
		draw_colored_polygon(PackedVector2Array([Vector2(0, -12), Vector2(-3, -9), Vector2(3, -9)]), arrow_color)
	elif direction == Direction.DOWN:
		draw_colored_polygon(PackedVector2Array([Vector2(0, -9), Vector2(-3, -12), Vector2(3, -12)]), arrow_color)
