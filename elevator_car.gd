extends Node2D

# ---------------------------------------------------
# エレベーターのカゴ：1本のシャフトの中を上下に動き、呼ばれた階に停まる。
# 呼ばれた順（先着順）に各階へ向かう。
# TileMapLayerの子として追加するので、positionはタイルマップ座標系。
# ---------------------------------------------------

signal arrived(floor_y: int) # 階に到着して扉を開けたとき

enum State { IDLE, MOVING, DOORS_OPEN }

const SPEED := 48.0    # 昇降の速さ（px/秒）
const DOOR_TIME := 1.0 # 停車して扉を開けている時間（秒）

var world: Node2D  # main.gd
var column: int    # シャフトのx座標
var top_y: int     # シャフトの最上階（yが小さいほど上）
var bottom_y: int  # シャフトの最下階
var requests: Array[int] = [] # 向かう予定の階（先頭から順に向かう）
var state := State.IDLE
var door_timer := 0.0

func setup(p_world: Node2D, x: int, top: int, bottom: int) -> void:
	world = p_world
	column = x
	top_y = top
	bottom_y = bottom
	position = world.tile_map.map_to_local(Vector2i(column, bottom_y)) # 最下階からスタート
	z_index = 8 # マス目の表示より手前、住人より奥

# シャフトの範囲が変わったときに呼ぶ。範囲外になった呼び出しは取り消す
func set_shaft(top: int, bottom: int) -> void:
	top_y = top
	bottom_y = bottom
	requests = requests.filter(func(y): return y >= top_y and y <= bottom_y)
	if requests.is_empty() and state == State.MOVING:
		state = State.IDLE

func has_floor(y: int) -> bool:
	return y >= top_y and y <= bottom_y

# 今いる階（移動中は、カゴの中心があるマスの階）
func current_floor() -> int:
	return world.tile_map.local_to_map(position).y

# 指定した階への呼び出しを受け付ける。シャフトの範囲外ならfalse
func request_floor(y: int) -> bool:
	if not has_floor(y):
		return false
	if requests.has(y):
		return true
	if y == current_floor() and state != State.MOVING:
		open_doors() # すでにその階に停まっている
		return true
	requests.append(y)
	return true

func open_doors() -> void:
	state = State.DOORS_OPEN
	door_timer = DOOR_TIME
	arrived.emit(current_floor())

func _process(delta: float) -> void:
	match state:
		State.DOORS_OPEN:
			door_timer -= delta
			if door_timer <= 0.0:
				state = State.IDLE
		State.IDLE:
			if not requests.is_empty():
				state = State.MOVING
		State.MOVING:
			if requests.is_empty():
				state = State.IDLE
			else:
				var target: Vector2 = world.tile_map.map_to_local(Vector2i(column, requests[0]))
				position = position.move_toward(target, SPEED * delta)
				if position == target:
					requests.pop_front()
					open_doors()
	queue_redraw()

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
