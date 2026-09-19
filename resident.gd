extends Node2D

# ---------------------------------------------------
# 住人：グリッド上を1マスずつ歩き、階段で上下の階へ移動する。
# 移動できるかどうかの判断と経路探索は world（main.gd）に任せる。
# TileMapLayerの子として追加するので、positionはタイルマップ座標系。
# ---------------------------------------------------

const WALK_SPEED := 48.0   # 横移動の速さ（px/秒）
const STAIRS_SPEED := 24.0 # 階段での上下移動の速さ（px/秒）

var world: Node2D              # main.gd（グリッド情報と経路探索を持つ）
var cell: Vector2i             # 現在いるマス
var goal: Vector2i             # 目的地のマス
var path: Array[Vector2i] = [] # これから進むマス（先頭が次のマス）
var selected := false:
	set(value):
		selected = value
		queue_redraw()

func setup(p_world: Node2D, start_cell: Vector2i) -> void:
	world = p_world
	cell = start_cell
	goal = start_cell
	position = world.tile_map.map_to_local(cell)
	z_index = 10 # タイルより手前に描く

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
	queue_redraw()
	return true

func _process(delta: float) -> void:
	# 立っているマスが撤去されたら退場する
	if world.is_cell_empty(cell):
		world.show_message("住人の足元が撤去されたため、住人が退場しました")
		queue_free()
		return
	if path.is_empty():
		return

	var next: Vector2i = path[0]
	var target_pos: Vector2 = world.tile_map.map_to_local(next)

	# マスの中心から次の一歩を踏み出す前に、まだ通れるか確認する
	if position == world.tile_map.map_to_local(cell) and not world.can_move(cell, next):
		if not go_to(goal):
			path.clear()
			world.show_message("経路が途切れたため、住人が立ち止まりました")
			queue_redraw()
		return

	var speed := STAIRS_SPEED if next.y != cell.y else WALK_SPEED
	position = position.move_toward(target_pos, speed * delta)
	if position == target_pos:
		cell = next
		path.pop_front()
	queue_redraw()

func _draw() -> void:
	# 残りの経路を線で表示する
	if not path.is_empty():
		var points := PackedVector2Array([Vector2.ZERO])
		for c in path:
			points.append(world.tile_map.map_to_local(c) - position)
		draw_polyline(points, Color(1.0, 1.0, 0.4, 0.8), 1.5)

	# 体（黒い縁取り付きの人型）。選択中は黄色で表示する
	var color := Color(1.0, 0.85, 0.1) if selected else Color.WHITE
	draw_circle(Vector2(0, -4), 3.5, Color.BLACK)
	draw_rect(Rect2(-3, -1, 6, 9), Color.BLACK)
	draw_circle(Vector2(0, -4), 2.5, color)
	draw_rect(Rect2(-2, 0, 4, 7), color)
