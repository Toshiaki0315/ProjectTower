extends Node2D

# ---------------------------------------------------
# 住人：グリッド上を1マスずつ歩き、階段やエレベーターで上下の階へ移動する。
# 移動できるかどうかの判断と経路探索は world（main.gd）に任せる。
# TileMapLayerの子として追加するので、positionはタイルマップ座標系。
#
# 状態:
#   WALKING  … 経路に沿って歩く（階段の上り下りを含む）
#   WAITING  … シャフトの前でカゴを待つ（扉が開いたら乗る）
#   RIDING   … カゴに乗っている（目的の階で扉が開いたら降りる）
#
# ストレス（0〜100）:
#   カゴを待っている間たまり、目的地に着いて立ち止まっている間は回復する。
#   体の色で表す: 白（平常）→ ピンク（40以上）→ 赤（70以上）
# ---------------------------------------------------

enum State { WALKING, WAITING, RIDING }

const WALK_SPEED := 48.0   # 横移動の速さ（px/秒）
const STAIRS_SPEED := 24.0 # 階段での上下移動の速さ（px/秒）

const MAX_STRESS := 100.0
const STRESS_WAIT_RATE := 10.0    # 待っている間に1秒でたまるストレス
const STRESS_RECOVER_RATE := 5.0  # 目的地で1秒に回復するストレス
const STRESS_PINK := 40.0         # これ以上でピンク
const STRESS_RED := 70.0          # これ以上で赤
const PINK_COLOR := Color(1.0, 0.55, 0.75)
const RED_COLOR := Color(1.0, 0.2, 0.2)

var world: Node2D              # main.gd（グリッド情報と経路探索を持つ）
var cell: Vector2i             # 現在いるマス（乗車中は乗ったマス）
var goal: Vector2i             # 目的地のマス
var path: Array[Vector2i] = [] # これから進むマス（先頭が次のマス）
var state := State.WALKING
var car = null                 # 待っている／乗っているカゴ
var stress := 0.0
var selected := false:
	set(value):
		selected = value
		queue_redraw()

func setup(p_world: Node2D, start_cell: Vector2i) -> void:
	world = p_world
	cell = start_cell
	goal = start_cell
	position = world.tile_map.map_to_local(cell)
	z_index = 10 # タイルやカゴより手前に描く

func is_moving() -> bool:
	return not path.is_empty()

# 目的地を設定して経路を求める。経路がなければfalseを返す。
func go_to(target: Vector2i) -> bool:
	var new_path: Array[Vector2i] = world.find_path(cell, target)
	if new_path.is_empty():
		return false
	new_path.pop_front() # 先頭は現在地なので除く
	path = new_path
	goal = target
	state = State.WALKING
	car = null
	queue_redraw()
	return true

func _process(delta: float) -> void:
	update_stress(delta)
	match state:
		State.WALKING:
			process_walking(delta)
		State.WAITING:
			process_waiting()
		State.RIDING:
			process_riding()
	queue_redraw()

func process_walking(delta: float) -> void:
	# 立っているマスが撤去されたら退場する
	if world.is_cell_empty(cell):
		leave("住人の足元が撤去されたため、住人が退場しました")
		return
	if path.is_empty():
		return

	var next: Vector2i = path[0]
	var at_cell_center: bool = position == world.tile_map.map_to_local(cell)

	# マスの中心から次の一歩を踏み出す前に、まだ通れるか確認する
	if at_cell_center and not world.can_move(cell, next):
		if not go_to(goal):
			path.clear()
			world.show_message("経路が途切れたため、住人が立ち止まりました")
		return

	# 次の一歩がエレベーターなら、カゴを呼んで待つ
	if at_cell_center and world.is_elevator_ride(cell, next):
		car = world.elevator_system.get_car_at(cell)
		car.request_floor(cell.y)
		state = State.WAITING
		return

	var target_pos: Vector2 = world.tile_map.map_to_local(next)
	var speed := STAIRS_SPEED if next.y != cell.y else WALK_SPEED
	position = position.move_toward(target_pos, speed * delta)
	if position == target_pos:
		cell = next
		path.pop_front()

func process_waiting() -> void:
	if world.is_cell_empty(cell):
		leave("住人の足元が撤去されたため、住人が退場しました")
		return
	# シャフトが変わってカゴがなくなった／行き先の階に行けなくなったら経路を探し直す
	if not is_instance_valid(car) or not world.can_move(cell, path[0]):
		if not go_to(goal):
			path.clear()
			state = State.WALKING
			world.show_message("経路が途切れたため、住人が立ち止まりました")
		return
	# この階でカゴの扉が開いたら乗り込み、行き先の階を押す
	if car.is_doors_open_at(cell.y):
		car.request_floor(path[0].y)
		state = State.RIDING
	else:
		car.request_floor(cell.y) # 呼び出しが取り消されていたら呼び直す

func process_riding() -> void:
	# 乗っているカゴがなくなったら退場する（シャフトごと撤去されたなど）
	if not is_instance_valid(car):
		leave("乗っていたエレベーターが撤去されたため、住人が退場しました")
		return
	position = car.position # カゴと一緒に動く
	var dest: Vector2i = path[0]
	if not car.has_floor(dest.y):
		dest = Vector2i(car.column, car.current_floor()) # 行き先の階がなくなったら、今の階で降りる
		if not car.is_doors_open_at(dest.y):
			car.request_floor(dest.y)
			return
	# 目的の階で扉が開いたら降りる
	if car.is_doors_open_at(dest.y):
		cell = dest
		position = world.tile_map.map_to_local(cell)
		car = null
		state = State.WALKING
		if path[0] == dest:
			path.pop_front()
		elif not go_to(goal):
			path.clear()
			world.show_message("経路が途切れたため、住人が立ち止まりました")
	else:
		car.request_floor(dest.y) # 呼び出しが取り消されていたら押し直す

func update_stress(delta: float) -> void:
	if state == State.WAITING:
		stress = minf(stress + STRESS_WAIT_RATE * delta, MAX_STRESS)
	elif state == State.WALKING and path.is_empty():
		stress = maxf(stress - STRESS_RECOVER_RATE * delta, 0.0)

# ストレスに応じた体の色
func get_body_color() -> Color:
	if stress >= STRESS_RED:
		return RED_COLOR
	if stress >= STRESS_PINK:
		return PINK_COLOR
	return Color.WHITE

func leave(message: String) -> void:
	world.show_message(message)
	queue_free()

func _draw() -> void:
	# 残りの経路を線で表示する
	if not path.is_empty():
		var points := PackedVector2Array([Vector2.ZERO])
		for c in path:
			points.append(world.tile_map.map_to_local(c) - position)
		draw_polyline(points, Color(1.0, 1.0, 0.4, 0.8), 1.5)

	# 体（黒い縁取り付きの人型）。選択中は黄色、それ以外はストレスに応じた色
	var color := Color(1.0, 0.85, 0.1) if selected else get_body_color()
	draw_circle(Vector2(0, -4), 3.5, Color.BLACK)
	draw_rect(Rect2(-3, -1, 6, 9), Color.BLACK)
	draw_circle(Vector2(0, -4), 2.5, color)
	draw_rect(Rect2(-2, 0, 4, 7), color)

	# カゴを待っている間は頭の上に「…」を出す
	if state == State.WAITING:
		for i in 3:
			draw_circle(Vector2(-3 + i * 3, -10), 1.0, Color.WHITE)
